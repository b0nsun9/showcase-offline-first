# AGENTS.md

## What this is

An offline-first field-job app, built natively twice with the same features: for iOS with SwiftUI, and for Android. A worker sees today's jobs, completes them and attaches a photo. Without signal the app still shows the last list it received, and it keeps every completion and photo on the phone until the signal returns. Then it sends them, and the server records each one once.

The app talks to a hosted API, described by its own OpenAPI document at <https://api.showcase.bonsung.me/docs>. The API's code is not part of this repository.

The app is built through five stages. Every stage leaves a file or a record here, so how it was built can be read in this repository.

## Before any work

Invoke the `five-stage-workflow` skill (`.claude/skills/five-stage-workflow/`) before you start any work here, whether a feature, a plan task, a fix, or a docs or config change. Follow it until the work's pull request is merged. It says which stages the work needs, how each task runs, what its pull request must show, and when to stop and wait for the owner.

## The five stages

| Stage | Tool | What it leaves |
|---|---|---|
| 1. Brainstorm | `superpowers:brainstorming` | the spec, `docs/specs/YYYY-MM-DD-<topic>.md` |
| 2. Plan | `superpowers:writing-plans` | `docs/plans/YYYY-MM-DD-<platform>.md` |
| 3. Build | `superpowers:test-driven-development` and `superpowers:subagent-driven-development` | the code, on one branch per plan task |
| 4. Gate and test | the tests, this repository's hooks in `.claude/` and a review | the hooks |
| 5. Compound | `compound-engineering:ce-compound` | `docs/solutions/` |

Stages 3 to 5 run locally. Only then does the branch go up as a pull request, one per plan task.

## Rules

- A stage starts only after the owner approves the file the previous stage left. For a plan task, the owner's merge of its pull request is that approval, and the next task starts only after it.
- Tests come before code.
- API keys live only in `ios/Secrets.xcconfig` and `android/local.properties`, which git ignores. A key is never committed and never printed in a log.
- Only the owner merges pull requests.
- Never force-push.
- Everything written in this repository is in English.
