#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=sh
# Author: Landon Bouma (landonb &#x40; retrosoft &#x2E; com)
# Project: https://github.com/landonb/git-smart#💡
# License: MIT

# *** A Git command wrapper to provide a few enhancements.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# USAGE:
#
# - Source this file from your ~/.bashrc.
#
#   It'll alias `git` to the function below.
#
# - Read on to learn what it does.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# This wrapper started as a way to avoid clobbering unstaged and untracked
# files on destructive commands, like `git co -- {}` and `git reset --hard {}`.
# It's since been enhanced (complicated further =) to skip unnecessary checks.
#
# The wrapper provides three main features:
#
# - 1) Prompts user to continue if any of these commands are called:
#
#       git co -- {}
#       git co .
#       git reset --hard {}
#
#   - In some cases, you can recover from `git reset` by looking in the
#     reflog and just checking out the branch identified before the reset.
#     But not if `--hard` is specified, in which case you might lose
#     unstaged changes and/or untracked files.
#
# - 2) Skips Husky pre-commit hook if this command is called:
#
#       git cherry-pick {}
#
#   - If `git cherry-pick` is called, sets HUSKY_SKIP_HOOKS=1 (unless
#     HUSKY_SKIP_HOOKS already set) so that Husky does not call the
#     pre-commit hook.
#
#     - This is because cherry-pick does not support the --no-verify
#       option (like git-commit and git-rebase do), and I don't see
#       the value in pre-commit checks in general, because I rebase
#       often, and I often rebase dozens of commits at once.
#
#   - If you have pre-commit hooks but are not running Husky, and
#     if you run the cherry-pick command often, you might just want
#     to `/bin/rm .git/hooks/pre-commit` and not worry about it.
#     (Or `cd .git/hooks && /bin/mv pre-commit post-commit` and
#      run checks when it really counts, before publishing code.)
#
# - 3) Skips Husky pre-push hook if any of these commands are called:
#
#       git push {remote} :{branch-to-delete}
#       git push -d {remote} {branch-to-delete}
#       git push --delete {remote} {branch-to-delete}
#
#   - Because there's no reason to run checks if you're just deleting.

# HISTORY/2017-06-06: We all sometimes make mistakes, so I like to make
# destructive commands less easily destructive.
#
# - E.g., I alias the `rm` command in my environment to `rm_safe`
#  (from https://github.com/landonb/sh-rm_safe), which "removes"
#  file objects to the ~/.trash directory (that you can remove
#  for real later with the `rmtrash` command).
#
# - Likewise, Git has a few destructive commands that I wanted to
#   make less easily destructive.
#
#   - For instance, when I first started using Git, I'd sometimes type
#
#       git co -- blurgh
#
#     when I meant to type instead
#
#       git reset HEAD blurgh
#
#     So I decided to add a prompt before running the clobbery checkout command.
#
# - Then later I found other uses for this wrapper, as documented above.

# NOTE: The name of this function appears in the terminal window title, e.g., on
#       `git log`, the tmux window title might be, `_git_safe log | {tmux-title}`.

_git_safe () {
  local disallowed=false
  local skip_hooks=${HUSKY_SKIP_HOOKS}

  _git_prompt_user_where_reflog_wont_save_them () {
    local prompt_yourself=false

    _git_prompt_determine_if_destructive () {
      # Check if `git co` or git-reset command.
      # NOTE: `co` is a simple alias, `co = checkout`.
      #       See .gitconfig in the root of this project.
      # NOTE: (lb): I'm not concerned with the long-form counterpart, `checkout`,
      #       a command I almost never type, and for which can remain unchecked,
      #       as a sort of "force-checkout" option to avoid being prompted.
      if [ "$1" = "co" ] && [ "$2" = "--" ]; then
        prompt_yourself=true
      fi
      # Also catch `git co .`.
      if [ "$1" = "co" ] && [ "$2" = "." ]; then
        prompt_yourself=true
      fi

      # Verify `git reset --hard ...` command.
      if [ "$1" = "reset" ] && [ "$2" = "--hard" ]; then
        prompt_yourself=true
      fi
    }

    _git_prompt_ask_user_to_continue () {
      printf "Are you sure this is absolutely what you want? [Y/n] "
      read -e YES_OR_NO
      # As writ for Bash 4.x+ only:
      #   if [[ ${YES_OR_NO^^} =~ ^Y.* ]] || [ -z "${YES_OR_NO}" ]; then
      # Or as writ for POSIX-compliance:
      if [ -z "${YES_OR_NO}" ] || [ "$(_first_char_capped ${YES_OR_NO})" = 'Y' ]; then
        # FIXME/2017-06-06: Someday soon I'll remove this sillinessmessage.
        # WHEN?/2020-01-08: (lb): I'll see it when I believe it. Still here!
        echo "YASSSSSSSSSSSSS"
      else
        echo "I see"
        disallowed=true
      fi
    }

    if [ $# -lt 2 ]; then
      return
    fi

    _git_prompt_determine_if_destructive "$@"

    if ${prompt_yourself}; then
      _git_prompt_ask_user_to_continue
    fi
  }

  _git_husky_hooks_cherry_pick_skip_hooks () {
    # MAYBE/2021-01-04 14:31: Also check aliases? || [ "$1" = "pr" ] and "pp", etc.
    #                         Or maybe in the alias itself probably-instead.
    if [ "$1" != "cherry-pick" ]; then
      # Command is not `git cherry-pick [...]`.
      return
    fi

    # Always skip hooks (pre-commit) on cherry-pick.
    skip_hooks=${HUSKY_SKIP_HOOKS:-1}
  }

  _git_husky_hooks_pre_push_touch_bypass () {
    # Straight to the point -- does this even matter?
    if [ ! -f "${HOME}/.huskyrc" ]; then
      return
    fi
    # Likewise: Check if called within Git working tree,
    # and that pre-push wired (a file husky place-creates).
    local working_dir
    working_dir="$(command git rev-parse --show-toplevel)"
    if [ $? -ne 0 ] || [ ! -f "${working_dir}/.git/hooks/pre-push" ]; then
      return
    fi

    # MAYBE/2021-01-04 14:31: Also check aliases? || [ "$1" = "pr" ] and "pp", etc.
    #                         Or maybe in the alias itself instead?
    if [ "$1" != "push" ]; then
      # Not `git push [...]`.
      #  >&2 printf "%s\n" "It's Git, but it's no Push."
      return
    fi

    for argument in "$@"; do
      if [ "${argument}" = "--help" ] || [ "${argument}" = "-h" ]; then
        # User is requesting Help.
        # - Zap! This is what we in the biz pan as a short-cirtuit return. ;)
        #   Aka, Flow Control Surprise!
        >&2 printf "%s\n" "Here, let me help you."
        return
      fi
    done

    # ***

    # If flow already returned, means pre-push is *not* going to be called.
    # For code flowing past this commit, pre-push -- and ~/.huskyrc -- are
    # on deck.
    #
    # We might want to tell ~/.huskyrc not to run checks,
    # specifically if the user is deleting remote branch.

    # Load USER_HUSKY_RC_SKIP_INDICATOR, a touch file used to control
    # ~/.huskyrc later when it's run by husky-run.
    . "${HOME}/.huskyrc" --source

    # You're running this single-threaded like, right.
    # - Clean up should an earlier touchfile not have been removed.
    [ -f "${USER_HUSKY_RC_SKIP_INDICATOR}" ] && /bin/rm "${USER_HUSKY_RC_SKIP_INDICATOR}"

    # There are 2 delete remote branch variants we can ignore on:
    #
    #   git push --delete/-d ...
    #   git push remote :branch
    #
    # First delete variant:
    for argument in "$@"; do
      if [ "${argument}" = "--delete" ] || [ "${argument}" = "-d" ]; then
        # Hopes deleted. Oh, expletive deleted.
        # Brannigan, get out here and surrender before I get my expletives deleted.
        # Fry, delete that. Delete that right now!
        # (Whispers) Send. (Coughing) Did you delete it? Uh...
        # And everybody knows, once you delete a photo, it's gone forever.
        # And delete 12 terabytes of outdated catchphrases. Sounds like fun on a bun!
        # [Sniffles] I'll always remember you, Fry. [Robotic Voice] Memory deleted.
        #  printf "%s\n" "Hopes deleted."
        #  printf "%s\n" "Get out here and surrender before I get my expletives deleted."
        >&2 printf "%s\n" "Oh, expletive deleted."
        touch "${USER_HUSKY_RC_SKIP_INDICATOR}"
        break
      fi
    done
    #
    # Old school delete variant (using this shows you dev-age, can I get a
    # “DEV!”, What What!):
    # MAGIC_NUMBER: "$3", as in: git push remote :branch
    #                                 $1    $2      $3
    if [[ "$3" =~ ^:.* ]]; then
      >&2 printf "%s\n" "I'm going to allow this."
      touch "${USER_HUSKY_RC_SKIP_INDICATOR}"
    fi
  }

  _first_char_capped () {
    printf "$1" | cut -c1-1 | tr '[:lower:]' '[:upper:]'
  }

  # Prompt user if command consequences are undoable,
  # i.e., if previous file state would be *unrecoverable*.
  _git_prompt_user_where_reflog_wont_save_them "$@"

  if ! ${disallowed}; then
    # Because husky prefers config from package.json and does not merge
    # (additional) config from .husrkrc[.js[on]], do so here.
    _git_husky_hooks_cherry_pick_skip_hooks "$@"
  fi

  if ! ${disallowed}; then
    # MAYBE/2021-02-04: I wrote a pre-push that uses `ps -ocommand=` to
    # fetch the parent process's arguments, so it can figure out whether
    # to bypass hooks (because --delete) on its own. So it might be (maybe)
    # a better idea to replace husky's .git/hooks/pre-push with that file,
    # instead of dealing with (and maintaining) this overly complicated
    # git-safe wrapper business.
    _git_husky_hooks_pre_push_touch_bypass "$@"
  fi

  local exit_code=0

  if ! ${disallowed}; then
    HUSKY_SKIP_HOOKS=${skip_hooks} command git "$@"
    exit_code=$?

    # This function did not actually check if the current project even
    # uses husky, so perhaps ~/.huskyrc never ran, so let us clean up.
    [ -f "${USER_HUSKY_RC_SKIP_INDICATOR}" ] && /bin/rm "${USER_HUSKY_RC_SKIP_INDICATOR}"
  fi

  return ${exit_code}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

main () {
  if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    >&2 echo "ERROR: Trying sourcing the file instead: . $0" && exit 1
  else
    # To remove the alias, try:
    #
    #   unalias git 2> /dev/null
    alias git='_git_safe'
  fi
}

main "$@"
unset -f main

