---
title: The backoff reset on reconnect silently missed a launch with signal and a send that was in flight
date: 2026-11-06
category: logic-errors
module: ios/Packages/Data (LiveJobRepository, Outbox, JobStore)
problem_type: logic_error
component: background_job
symptoms:
  - "After Wi-Fi came back on the simulator, queued work took about 65–80 s to send, not the 2 s first backoff"
  - "A relaunch with signal could leave queued work waiting up to 5 minutes"
  - "All unit tests passed, including the one for the backoff reset on network return"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [offline-first, backoff, retry, network-monitor, nwpathmonitor, outbox, android]
---

# The backoff reset on reconnect silently missed a launch with signal and a send that was in flight

## Problem

The spec says the retry wait "resets when the network comes back". `LiveJobRepository` did that on an offline-to-online transition: it cleared the stored backoff waits, set their attempt counts to 0, refreshed, then drained. The live check in Task 6 still saw queued work wait 65–80 s after Wi-Fi returned. Review found two holes in how that one rule was wired. Both are fixed in the Task 6 pull request, the job screen, which is pending.

## Symptoms

- After Wi-Fi came back on the simulator, queued work took about 65–80 s to send, not the 2 s first backoff.
- A relaunch with signal could leave queued work waiting up to 5 minutes, the maximum backoff stored by the previous session.
- All unit tests passed, including the one for the backoff reset on network return.

## What Didn't Work

- **Assuming online at launch.** `isOnline` started as `true`, so the network monitor's first "satisfied" report wasn't a change. The reset never ran on a launch with signal, so waits stored in the last session survived it.
- **Computing the backoff from an attempt count read at the start of the send pass.** A request hanging on a dying connection fails only after the network is back. By then `clearBackoffWaits()` had reset the row's count to 0, but the outbox still held the old `OutboxItem.attempts` from before the reset, and scheduled a long wait from it.

## Solution

1. **Start unknown and treat the first report as a transition.** `isOnline` is a `Bool?` that starts `nil`, and snapshots show `isOnline ?? true`. A first report of `true` now runs the same clear, refresh and drain as a reconnect (`ios/Packages/Data/Sources/Data/LiveJobRepository.swift`).
2. **Compute the delay from the stored count, inside the write that stores the new one.** `JobStore.reschedule(_:at:isBackoff:)` takes a closure `(attempts) -> Date` and calls it with the row's current `attempts` within the same Core Data transaction (`ios/Packages/Data/Sources/Data/Store/JobStore.swift`). Retry-After waits pass a closure that ignores the count.

Regression tests, each seen failing first, are in `ios/Packages/Data/Tests/DataTests/LiveJobRepositoryTests.swift`:

- `firstOnlineReportClearsStoredBackoff`
- `failureInFlightAcrossReconnectWaitsFirstBackoff`

## Why This Works

A "reset on change" rule is only as good as its notion of the previous state. An assumed previous state ("we were online") hides the first real report, and a cached copy of state ("attempts as of the start of the pass") goes stale at the very moment the reset happens. Reading the state at decision time, from the store, inside the same transaction, removes both gaps.

## Prevention

- **Initial state.** Any value derived from a network monitor starts unknown, never assumed. Test the first report, not only later transitions.
- **Retry counts.** Read them at the moment the decision is made, from the store, never from an item fetched before an `await`.
- **The Android app needs the same rule.** `ConnectivityManager`'s first `onAvailable` callback has to count as a reconnect, and its backoff must also read the stored count.

## Related Issues

- `docs/solutions/logic-errors/server-echo-mid-sync-overwrites-phone-owned-photo.md`: another case where state captured mid-sync went stale.
- Spec: `docs/specs/2026-11-06-ios-offline-first-app.md`, the Sending section ("The wait resets when the network comes back").
