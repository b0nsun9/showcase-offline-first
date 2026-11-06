#!/bin/bash
# Tests for block-default-branch.sh: run `bash .claude/hooks/block-default-branch.test.sh`.
set -u
hook="$(cd "$(dirname "$0")" && pwd)/block-default-branch.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q -b develop
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" branch main
git -C "$repo" branch feature

fails=0
check() { # branch, command, expected exit code
  git -C "$repo" switch -q "$1"
  local payload actual
  payload=$(jq -n --arg c "$2" --arg d "$repo" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}')
  bash "$hook" <<<"$payload" 2>/dev/null
  actual=$?
  if [ "$actual" -ne "$3" ]; then echo "FAIL [$1] $2 → exit $actual, expected $3"; fails=$((fails + 1)); fi
}

check develop "git commit -m x" 2
check main    "git add a && git commit -m x" 2
check feature "git commit -m x" 0
check develop "git status" 0
check develop "ls -la" 0
check develop "git merge --ff-only origin/develop" 0
check develop "git merge feature" 2
check develop "git cherry-pick abc123" 2
check feature "git push -u origin HEAD" 0
check feature "git push origin HEAD:develop" 2
check feature "git push origin main" 2
check feature "git push origin HEAD:refs/heads/main" 2
check develop "git push" 2
check feature "git push origin docs/develop-notes" 0
check feature "git push origin feature/main" 0
check feature "git -C /elsewhere commit -m x" 0
# Text that only mentions develop, main or push must not count as a push.
check feature "printf 'pushing straight to develop and main' > m && git push -u origin HEAD" 0
check feature "git commit -m \"push to main later\"" 0
check feature "echo git push origin develop" 0
# Quoting the target must not get around the block.
check feature "git push origin 'HEAD:develop'" 2
check feature "cd /tmp && git push origin +HEAD:main" 2

if [ "$fails" -eq 0 ]; then echo "all 21 cases pass"; else echo "$fails case(s) failed"; exit 1; fi
