# AGENTS.md

## What this is

An offline-first field-job app, built natively twice with the same features: for iOS with SwiftUI, and for Android. A worker sees today's jobs, completes them and attaches a photo. Without signal the app still shows the last list it received, and it keeps every completion and photo on the phone until the signal returns. Then it sends them, and the server records each one once.

The app talks to a hosted API, described by its own OpenAPI document at <https://api.showcase.bonsung.me/docs>. The API's code is not part of this repository.

The app is built through five stages. Every stage leaves a file or a record here, so how it was built can be read in this repository.

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

- A stage starts only after the owner approves the file the previous stage left.
- Tests come before code.
- API keys live only in `ios/Secrets.xcconfig` and `android/local.properties`, which git ignores. A key is never committed and never printed in a log.
- Only the owner merges pull requests.
- Never force-push.
- Everything written in this repository is in English.
