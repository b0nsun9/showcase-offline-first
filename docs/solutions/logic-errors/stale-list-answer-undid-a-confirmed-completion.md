---
title: A job-list answer requested before a confirmation could undo it
date: 2026-11-06
category: logic-errors
module: ios/Packages/Data (JobStore, LiveJobRepository)
problem_type: logic_error
component: database
symptoms:
  - "A job showing \"Done · sent\" could flip back to \"To do\" after a refresh, with its note cleared"
  - "A re-opened job screen showed Complete enabled again, because the photo was still on the phone"
  - "It needed two overlapping requests, so no single-path test showed it"
root_cause: concurrency
resolution_type: code_fix
severity: high
tags: [offline-first, sync, refresh, stale-response, race, confirmation-counter, android]
---

# A job-list answer requested before a confirmation could undo it

## Problem

The spec's refresh rule says "nothing pending → show what the server says". That's right for a fresh answer. But a `GET /v1/jobs` answer can be built before job X's completion reaches the server, and only applied after X's completion and photo are both confirmed. By then X has nothing pending, so the old answer won. "Done · sent" flipped to "To do", the note was cleared, and Complete could enable again. The final whole-app review caught it (fix pending in the iOS final-review pull request).

Overlap is ordinary, not exotic. Launch starts two refreshes at once, one when the scene becomes active and one on the network monitor's first report, and a pull-to-refresh can overlap a send.

## Symptoms

- A job showing "Done · sent" could flip back to "To do" after a refresh, with its note cleared.
- A re-opened job screen showed Complete enabled again, because the photo was still on the phone.
- It needed two overlapping requests, so no single-path test showed it.

## What Didn't Work

- **Trusting "nothing pending".** That a job has nothing pending says nothing about how old the answer is. The merge rule can't tell a fresh "pending" from one built before the completion arrived.
- **Narrowing the merge rule** ("never let a server 'pending' undo a local completion"). It's a one-line change, but it rewrites the spec's refresh table. It also guards only this one field, not other stale fields.

## Solution

`JobStore` keeps a confirmation counter in memory:

- **Bump.** Every `finish` bumps it, in the same `perform` as the save, after the confirmed item is deleted.
- **Read before.** `LiveJobRepository.refresh()` reads `store.confirmations` before calling `listJobs()`.
- **Skip.** It passes the value to `JobStore.apply(server:asOf:)`, which writes nothing when the counter has moved since:

```swift
func apply(server: [Job], asOf confirmations: Int) async throws {
    try await transact {
        guard self.confirmations == confirmations else { return } // the answer may predate a confirmation
        // … merge and write as before
    }
}
```

The regression test is `listAnswerFromBeforeConfirmationKeepsCompletion` in `ios/Packages/Data/Tests/DataTests/LiveJobRepositoryTests.swift`. It holds a list answer, confirms the job, then releases the old answer. The job stays completed, sent, and keeps its note.

## Why This Works

- **No stale answer can be applied.** A job reaches "nothing pending" only through `finish`, and every `finish` bumps the counter on the same serial context queue that `apply` checks it on. So an answer whose request left before a confirmation is always detected.
- **The cost is a skipped good answer now and then.** The refresh after the queue empties, or the next one, replaces it.
- **The counter can live in memory.** A list answer never outlives the process that asked for it, and the app holds a single store.

## Prevention

- **A server answer describes the server when the request left, not when the reply lands.** Any "the server wins" rule needs a check that nothing the phone confirmed happened in between.
- **Test with two overlapping requests.** Hold one answer in the fake, change state, then release it. Single-path tests can't show this race.
- **The Android app needs the same guard,** alongside the rules in the related learnings below.

## Related Issues

- `docs/solutions/logic-errors/server-echo-mid-sync-overwrites-phone-owned-photo.md`: a server reply carrying partial state mid-sync.
- `docs/solutions/logic-errors/backoff-reset-on-reconnect-missed-launch-and-in-flight-sends.md`: state read before an `await` going stale.
- Spec: `docs/specs/2026-11-06-ios-offline-first-app.md`, "Refreshing the list". The table stays as written.
