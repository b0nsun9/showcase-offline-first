---
name: five-stage-workflow
description: Use when starting any work in the showcase-offline-first repository, such as a new feature or platform, a plan task, a fix, or a docs or config change, and whenever deciding whether to start the next task.
---

# The five-stage workflow

## Overview

Every change goes through five stages, and every stage leaves a file or a record, so how the app was built can be read from the repository. **The owner approves each stage before the next one starts. For a plan task, the owner's merge of its pull request is that approval.**

**Violating the letter of this workflow is violating its spirit.** This skill and `AGENTS.md` outrank any other skill's "keep going" instruction, including `superpowers:subagent-driven-development`'s "do not pause between tasks".

## Which stages apply

| The work | Stages |
|---|---|
| New topic or platform | 1. Brainstorm (`superpowers:brainstorming`) → spec in `docs/specs/`, approved. 2. Plan (`superpowers:writing-plans`) → `docs/plans/YYYY-MM-DD-<platform>.md`, approved. Then each task. |
| A plan task | Stages 3–5 locally, then one pull request (the task loop below) |
| Not in a plan, and changes app behaviour | Needs a spec first (stage 1) |
| Docs, config or tooling only | Its own branch from `develop`, and one pull request with results |

## The task loop

1. **Is the previous task's pull request merged?** If not, stop and wait. If it is, branch `<platform>/task-<N>-<slug>` from the latest `develop`. Never branch from another task's branch.
2. **Read `docs/solutions/`** for learnings about the area the task touches.
3. **Build** (stage 3): **REQUIRED SUB-SKILL:** invoke `superpowers:test-driven-development` explicitly. Then use `superpowers:subagent-driven-development` for this one task only.
4. **Gate** (stage 4):
   - Every test the plan names passes locally.
   - A fresh reviewer checks the task against the spec and for quality. Every fix gets a scoped re-review, until nothing Critical or Important is left open.
   - Any hooks in `.claude/` pass.
   - A live dev-API test that skipped is **not** a pass. Get the key (see Keys), or list it under Not verified.
5. **Compound** (stage 5): invoke `compound-engineering:ce-compound` for **every** task. It writes the learning to `docs/solutions/`, or states why none qualified.
6. **Open one pull request** into `develop`, its description in this order:
   - **Summary:** what is now possible, and where the task sits in the plan.
   - **Results:**
     - every command that was run, with its output
     - the CI run
     - for anything on screen, screenshots committed under `docs/results/<platform>/task-<N>/`
   - **Decisions for approval:** every choice that goes beyond the spec or the plan, or changes them, each with its reason.
   - **Not verified:** what wasn't checked, and why.
   - Then, once CI finishes, add its result.
7. **STOP.** Tell the owner the pull request is ready, and do nothing on the next task until they merge it.

## Rationalizations

| Thought | Reality |
|---|---|
| "subagent-driven-development says don't pause between tasks" | The owner's workflow outranks it. Stop after each task's pull request. |
| "I'll stack the next branch on this one to save time" | Wait for the merge, then branch from `develop`. |
| "Waiting for the owner idles the whole day" | Idle is correct. Review feedback on an unmerged pull request can force rework in everything stacked on it. |
| "A stacked branch is reversible, so I'll retarget it later" | It's still building on unapproved work. Don't start until the merge. |
| "No learning here, so I'll skip ce-compound" | Run it. It decides, and it records why. |
| "The tests were written first, so the TDD skill isn't needed" | Invoke it explicitly. |
| "The unit tests pass, and the live test skipped" | A skipped live test is no result. |
| "I'll make a ruling and keep going" | A ruling that changes behaviour goes under Decisions for approval. |

**Red flags:** starting a task while a pull request is unmerged, a branch cut from a task branch, a task with no `ce-compound` run, or a pull request without Results. All of these mean: stop and fix it before going on.

## Branches, keys and tools

- **Branches.** `develop` is the default branch, and all pull requests target it. Nobody commits on `develop` or `main`, only the owner merges, and nobody force-pushes.
- **Keys** live only in `ios/Secrets.xcconfig` (`API_KEY_DEV`, `API_KEY_PROD`; the template is `ios/Secrets.example.xcconfig`) and in `android/local.properties`. git ignores both files.
  - Fill them without printing the key. On the owner's Mac:

    ```sh
    printf 'API_KEY_DEV = %s\n' "$(security find-generic-password -s showcase-api-dev -a api-key -w)" > ios/Secrets.xcconfig
    ```

  - CI uses the repository secret `SHOWCASE_DEV_API_KEY`.
  - Never put a key in a log, a pull request or a screenshot.
- **Hosts.** Debug builds use `dev.api.showcase.bonsung.me`, and Release builds use `api.showcase.bonsung.me`.
- **Tools.**
  - Xcode's MCP server is shared through `.mcp.json`. It needs Xcode running.
  - The Xcode project comes from Xcode's own templates. No Tuist, XcodeGen, CocoaPods or Carthage.
  - Code is shared through local Swift packages.
  - Everything written in the repository is in English.
