# AGENTS.md

## What this is

An offline-first field-job app, built natively twice with the same features: for iOS with SwiftUI, and for Android. A worker sees today's jobs, completes them and attaches a photo. Without signal the app still shows the last list it received, and it keeps every completion and photo on the phone until the signal returns. Then it sends them, and the server records each one once.

The app talks to a hosted API, described by its own OpenAPI document at <https://api.showcase.bonsung.me/docs>. The API's code is not part of this repository.

The app is built through five stages. Every stage leaves a file or a record here, so how it was built can be read in this repository.

## Before any work

Invoke the `workflow` skill before you start any work.

## Rules

- A stage starts only after the owner approves the file the previous stage left. For a plan task, the owner's merge of its pull request is that approval, and the next task starts only after it.
- Tests come before code.
- API keys live only in `ios/Secrets.xcconfig` and `android/local.properties`, which git ignores. A key is never committed and never printed in a log.
- Only the owner merges pull requests.
- Never force-push.
- Everything written in this repository is in English.
