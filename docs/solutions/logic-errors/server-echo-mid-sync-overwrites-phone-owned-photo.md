---
title: A server reply that arrives mid-sync carries partial state and must not overwrite what the phone owns
date: 2026-11-06
category: logic-errors
module: ios/Packages/Data (JobStore)
problem_type: logic_error
component: database
symptoms:
  - "After the completion was confirmed, the job showed no photo until the next refresh"
  - "savePhoto accepted a second photo for a completed job, so the queued upload sent the replacement"
  - "The one-photo, no-retake rule held in tests but broke against the real send order"
root_cause: data_integrity
resolution_type: code_fix
severity: high
tags: [offline-first, sync, core-data, server-echo, photo, outbox]
---

# A server reply that arrives mid-sync carries partial state and must not overwrite what the phone owns

## Problem

The send queue sends a job's completion first and its photo second. When the completion is answered, the store saves the job the server returned (`JobStore.finish(_:serverJob:)`). At that moment the server has no photo yet, so the returned job has `photo: null`. Saving its `PhotoInfo` wiped the phone's size and hash. The phone still held the photo bytes, but the no-retake guard looked at the info fields, so a second photo got in and replaced the one waiting to upload. This was caught in review before it shipped. The fix is pending in the Task 3 pull request (the Core Data store).

## Symptoms

- After the completion was confirmed, the job showed no photo until the next refresh.
- `savePhoto` accepted a second photo for a completed job, so the queued upload sent the replacement.
- The one-photo, no-retake rule held in tests but broke against the real send order.

## What Didn't Work

- **Following the plan literally.** The approved plan said `finish` stores the server job's "fields and `PhotoInfo`". That's correct once both requests are confirmed, and wrong in between.
- **The original test.** `confirmedJobKeepsPhotoBytes` built its fake server job with the photo already set. The real server never returns that while the photo upload is still queued, so the test passed and the bug stayed hidden.

## Solution

The phone is the source of truth for anything it created and hasn't seen confirmed. In `JobStore.write`, used by both `finish` and `apply`, the server's photo info is stored only when the phone holds no photo bytes:

```swift
// The phone's own photo info wins while it holds the bytes; the server's is stored only without them.
if e.value(forKey: "photo") == nil {
    e.setValue(Int64(job.photo?.bytes ?? 0), forKey: "photoBytes")
    e.setValue(job.photo?.sha256, forKey: "photoSHA256")
}
```

The no-retake guard in `savePhoto` checks the stored bytes, `entity.value(forKey: "photo") == nil`, not `photoSHA256`, because a server write can blank that field. `complete` checks the bytes for "photo present" in the same way. The regression test is `finishWithPhotolessServerJobKeepsLocalPhotoAndBlocksRetake` in `ios/Packages/Data/Tests/DataTests/JobStoreTests.swift`.

## Why This Works

Each request's reply describes the server after **that** request, not after all of the phone's queued work. With several requests for one record in flight, every reply but the last is a partial view. A guard keyed on data that the replies can overwrite inherits that partial view. Keying it on data only the phone writes, the photo bytes, makes it immune.

## Prevention

- When a fake server reply in a test stands in for one step of a multi-step sync, give it exactly what the real server knows at that step. A fake that already reflects later requests hides this class of bug.
- For each field a server reply writes back, ask whether the phone owns it until a later request is confirmed. If it does, never overwrite it from the reply.

## Related Issues

- Spec: `docs/specs/2026-11-06-ios-offline-first-app.md`, sections "Taking the photo" (no retake) and "Refreshing the list" (the phone wins while its work is unconfirmed).
- Plan: `docs/plans/2026-11-06-ios.md`, Task 3 (the `finish` interface) and Task 4 (send order: completion, then photo).
