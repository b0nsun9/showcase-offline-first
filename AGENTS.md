# AGENTS.md

## What this is

An offline-first field-job app, built natively twice with the same features: for iOS with SwiftUI, and for Android. A worker sees today's jobs, completes them and attaches a photo. Without signal the app still shows the last list it received, and it keeps every completion and photo on the phone until the signal returns. Then it sends them, and the server records each one once.

The app talks to a hosted API, described by its own OpenAPI document at <https://api.showcase.bonsung.me/docs>. The API's code is not part of this repository.

The app is built through five stages. Every stage leaves a file or a record here, so how it was built can be read in this repository.

## The five stages

| Stage | Tool | What it leaves | How often |
|---|---|---|---|
| 1. Brainstorm | `superpowers:brainstorming` | the spec, `docs/specs/YYYY-MM-DD-<topic>.md` | once per topic |
| 2. Plan | `superpowers:writing-plans` | `docs/plans/YYYY-MM-DD-<platform>.md`, split into tasks | once per platform |
| 3. Build | `superpowers:test-driven-development` and `superpowers:subagent-driven-development` | the code, on the task's own branch | every task |
| 4. Gate and test | the tests, this repository's hooks in `.claude/` and a review | the review's outcome, and the hooks | every task |
| 5. Compound | `compound-engineering:ce-compound` | a learning in `docs/solutions/`, or the reason none qualified | every task |

The owner approves the spec and the plan before the next stage starts. After that, each task runs stages 3 to 5 locally and goes up as one pull request.

## How a task runs

1. **Wait for the previous task's merge.** Start only after the owner has merged the previous task's pull request. Then branch `<platform>/task-<N>-<slug>` from `develop`. Never stack one task's branch on another's.
2. **Read the learnings.** Check `docs/solutions/` for learnings about the area the task touches.
3. **Build** (stage 3), test-first: write a failing test, see it fail, then write the code that makes it pass. Invoke `superpowers:test-driven-development` explicitly.
4. **Gate** (stage 4):
   - Every test the plan names passes locally.
   - A fresh reviewer checks the task against the spec and the plan, and for code quality. Each finding gets a fix, and then a re-review of just that fix, until nothing important is left open.
   - Once hooks exist, they pass too.
5. **Compound** (stage 5): run `compound-engineering:ce-compound` for every task. It either writes a learning or says why none qualifies.
6. **Open the pull request** into `develop`. Its description shows the owner what to approve:
   - **Summary:** what is now possible, and where the task sits in the plan.
   - **Results:**
     - every command that was run, with its output (test counts, builds)
     - the CI run
     - for anything on screen, screenshots committed under `docs/results/<platform>/task-<N>/`
   - **Decisions for approval:** every choice that goes beyond the spec or the plan, or changes them, each with its reason.
   - **Not verified:** what wasn't checked, and why.
7. **Stop.** The owner approves the task by merging its pull request. The next task starts only after that merge.

## Branches

- `develop` is the default branch. Every pull request targets it.
- Nobody commits directly to `develop` or `main`. Work reaches them only through pull requests that the owner merges. The planned hooks will enforce this.

## Keys and configuration

- **Where keys live.** API keys live only in `ios/Secrets.xcconfig` and `android/local.properties`, which git ignores. `ios/Secrets.example.xcconfig` shows the expected names: `API_KEY_DEV` and `API_KEY_PROD`.
- **Filling the files.** Fill them from a secret store without printing the key. On the owner's Mac the keys are in the Keychain, under the services `showcase-api-dev` and `showcase-api-prod`, account `api-key`:

  ```sh
  printf 'API_KEY_DEV = %s\n' "$(security find-generic-password -s showcase-api-dev -a api-key -w)" > ios/Secrets.xcconfig
  ```

- **Hosts.** Debug builds use `dev.api.showcase.bonsung.me`, and Release builds use `api.showcase.bonsung.me`.
- **CI.** CI reads the dev key from the repository secret `SHOWCASE_DEV_API_KEY`. Tests that call the live dev API skip themselves when it's missing or empty.

## Tools

- **Xcode's MCP server.** It is shared through `.mcp.json` (`xcrun mcpbridge`). It needs Xcode running, and each person approves it the first time Claude Code starts here.
- **The Xcode project** comes from Xcode's own templates, created through that server. No third-party project tools: no Tuist, XcodeGen, CocoaPods or Carthage. Code is shared through local Swift packages.

## Rules

- A stage starts only after the owner approves the file the previous stage left. For a task, the owner's merge of its pull request is that approval.
- Tests come before code.
- A key is never committed, and never printed in a log, a pull request or a screenshot.
- Only the owner merges pull requests.
- Never force-push.
- Everything written in this repository is in English.
