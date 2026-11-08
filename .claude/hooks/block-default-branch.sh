#!/bin/bash
# PreToolUse hook for Bash: blocks committing on develop or main, and pushing straight to them.
# Work reaches develop and main only through pull requests that the owner merges.
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")

# shortcut: judges the branch of the session's directory, not a `cd` or `git -C` target inside the command.
branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
on_protected=false
[[ "$branch" == develop || "$branch" == main ]] && on_protected=true

deny() {
  echo "Blocked by .claude/hooks/block-default-branch.sh: $1. Commit on a branch cut from develop and open a pull request; only the owner merges into develop or main." >&2
  exit 2
}

# Look at each simple command (split on ;, &&, ||, | and newlines) that starts with `git`.
while IFS= read -r segment; do
  read -ra words <<<"${segment//[\"\'()]/}"
  [[ "${words[0]}" == git ]] || continue
  i=1
  while [[ "${words[i]}" == -* ]]; do # global options; -C and -c take a value
    [[ "${words[i]}" == -C || "${words[i]}" == -c ]] && i=$((i + 1))
    i=$((i + 1))
  done
  sub=${words[i]}
  args=("${words[@]:i+1}")

  case "$sub" in
    commit | cherry-pick | revert | am)
      $on_protected && deny "this would commit on $branch" ;;
    merge)
      $on_protected && [[ " ${args[*]} " != *" --ff-only "* ]] && deny "a merge on $branch can create a commit" ;;
    push)
      $on_protected && deny "this would push from $branch"
      positional=0
      for arg in "${args[@]}"; do
        [[ "$arg" == -* ]] && continue
        positional=$((positional + 1))
        [[ $positional -eq 1 ]] && continue # the remote
        dest=${arg##*:}
        dest=${dest#+}
        dest=${dest#refs/heads/}
        [[ "$dest" == develop || "$dest" == main ]] && deny "this pushes straight to $dest"
      done ;;
  esac
done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$cmd")
exit 0
