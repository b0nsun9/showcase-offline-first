# iOS offline-first field-job app

Stage 1 spec, approved by the owner on 2026-11-06. The Android app gets its own spec later. Wherever this spec says "my call", the choice came from Claude, not the owner, and the owner can overturn it.

## Why

A field worker spends the day where the signal comes and goes. The app has to let them finish their work without ever waiting for the network. A job is done on the phone the moment they say so. The app keeps every completion and photo until the signal comes back, then sends them, and the server records each one once. The repository is a showcase of that behaviour, built natively for iOS (this spec) and later for Android with the same features.

## What the worker does

1. They open the app and see today's jobs, ordered by time window. Without signal they see the last list the app received.
2. They open a job and take one photo, which is required, and may write a note of up to 1,000 characters.
3. They tap **Complete job**. The job is done straight away on the phone, signal or not, and can't change after that.
4. While the app is open, it sends the completion and the photo whenever it has signal, without the worker doing anything.

## Goals

- A job is complete the moment the worker taps **Complete job**, with or without signal.
- Every completion and photo survives closing the app, a crash and a dead battery, and stays on the phone until the server has confirmed it.
- The server records each completion once, even when the signal drops in the middle of a call.
- The worker can see which jobs are still waiting to send and which have been sent.
- The architecture follows Clean Architecture, and the compiler enforces its dependency direction.

## Non-goals (decided by the owner)

- **No conflict merging.** Only this phone ever writes its own copy of the jobs, so one rule covers every disagreement (see "Refreshing the list").
- **Sending only while the app is open.** There are no background tasks (`BGTaskScheduler`) and no background `URLSession`. Work queued by a worker who closes the app is sent the next time they open it.
- **One photo per job, and no retake.**
- **No way to edit or un-complete a job** after Complete. The API has no way to do either.
- **The server's nightly data reset is treated as if it doesn't exist.** It's a showcase artefact of the API. There's no guard against it either: no stored dates and no checks before sending. The anti-goal "lands on the wrong job" is about the app's own mistakes, such as sending to the wrong job ID, not about the reset.
- **The repository's stage-4 hooks in `.claude/` aren't part of this spec or its plan.** They're planned separately. The owner's one stated requirement for them: they must block commits made directly to `develop` or `main`.
- **No running on a real iOS 15 device or simulator.** Only the compiler checks that iOS 15.6 works (see "Testing and CI").

## Anti-goals (these would make it a failure, even if it works)

- A job shows as done on the phone but never reaches the server, or is silently dropped from the queue.
- A completion is recorded twice, or lands on the wrong job.
- The worker has to wait on a spinner before a job counts as done.
- Domain code imports Core Data, URLSession or UIKit.
- The API key is committed, or it is printed in a log.

## The API

The API is hosted, and its code isn't in this repository. The OpenAPI document is at `https://api.showcase.bonsung.me/openapi.json`, viewable at `/docs`. The dev API at `https://dev.api.showcase.bonsung.me` has the same document; only the server address differs.

| Environment | Host | Used by |
|---|---|---|
| dev | `dev.api.showcase.bonsung.me` | Debug builds, integration tests, CI |
| production | `api.showcase.bonsung.me` | Release builds |

Every `/v1` request carries:

- `Authorization: Bearer <key>`. A missing or wrong key gets 401 `unauthorized`.
- `X-Install-Id: <uuid>`. The app makes this UUID on first launch and keeps it. Each install has its own private copy of today's eight jobs (`job-1` to `job-8`), and installs never see each other's changes. The first request of any kind creates those jobs, so a write sent before any list still succeeds.

| Call | What it does | What matters to the app |
|---|---|---|
| `GET /v1/jobs` | Returns `{ "jobs": [Job] }`, all eight jobs, ordered by time window | The full list every time. There's no "changed since" option. |
| `POST /v1/jobs/{id}/complete` | Body `{ "completedAt": "<ISO 8601>", "note": "<string or null>" }`, header `Idempotency-Key` | See "Idempotency" below. Answers `{ "job": Job }`. |
| `PUT /v1/jobs/{id}/photo` | Body is the raw image bytes, with `Content-Type: image/*` | 5,242,880 bytes at most, otherwise 413. Answers `{ "bytes", "sha256" }`, the SHA-256 in lower-case hex. Uploading the same photo again answers 200 and isn't recorded again. A different photo replaces the first. |
| `GET /v1/arrivals` | Counts of writes received and recorded | The app doesn't use it. It's for watching the showcase from a browser. |

`Job` has the fields `id`, `address`, `task`, `date` (a New Zealand date), `windowStart` and `windowEnd` (`HH:mm`), `status` (`pending` or `completed`), `completedAt`, `note`, `photo` (`{bytes, sha256}` or null) and `updatedAt`. The app doesn't need `updatedAt`.

**Idempotency.** The phone creates the `Idempotency-Key` when the worker taps Complete, and every retry sends the same key with the same request.

- The same key with the same request replays the first answer, with the header `Idempotent-Replayed: true`, and isn't recorded again.
- The same key with a different request gets 422 `idempotency_key_reused`. That's why a queued completion's body must never change.
- A duplicate that arrives while the first request is still running gets 409 `request_in_progress` with `Retry-After`. If the first request was cut off, a retry with the same key after 30 seconds runs it again, safely.
- Completing a job that is already completed, even under a new key, answers 200 with what was first recorded.

**Write limit.** Each IP address gets 500 writes (`POST` and `PUT`) per New Zealand day. After that the server answers 429 `write_limit_reached`, with `Retry-After` set to the seconds left in the day. An install's first request counts as one write.

**Errors.** Every error is JSON, `{"error": "<code>"}`. A 500 `internal_error` is safe to retry.

## Behaviour

### Taking the photo and writing the note

- The photo comes from the camera. My call: when no camera is available, as on the simulator, the app falls back to the photo library so the flow can still be tested.
- My call: the photo is encoded as a JPEG and shrunk, by lowering the quality and then the size, until it fits within 5,242,880 bytes. The app works out the SHA-256 of exactly those bytes, and those bytes are what gets uploaded, with `Content-Type: image/jpeg`. The server's 413 then can't happen.
- Once taken, the photo is the job's photo, with no retake (decided by the owner).
- My call: the photo and the note are saved on the phone as a draft as soon as they exist. Leaving the screen or a crash then loses neither.
- The note is optional and has a counter showing how much of the 1,000 characters is used. My call: the counter counts UTF-16 code units (`note.utf16.count`). That's the strictest way to count, so a note the app accepts is never too long for the server, however the server counts.

### Completing a job

- **Complete job** stays disabled until a photo has been taken (decided by the owner).
- Tapping it does all of the following in one Core Data save, so a crash can't leave a job done with nothing queued, or the other way round:
  - marks the job completed on the phone
  - records `completedAt` as the time of the tap, an ISO 8601 UTC string with milliseconds, kept exactly as it will be sent
  - freezes the note
  - creates the `Idempotency-Key`, a UUID
  - queues the completion request and the photo upload
- After that the job is locked on screen and shows "Completed hh:mm · waiting to send".

### Sending (the queue)

- **When it sends.** Only while the app is in the foreground:
  - when the app launches or comes to the foreground
  - when the network becomes available (`NWPathMonitor`)
  - straight after a Complete
  - when a retry wait ends
- **Order.** One sender at a time, working through the queue oldest first.
- **What a retry sends.** A completion retry sends the stored key and the stored `completedAt` and note, unchanged.
- **When a job counts as sent.** Only once its completion has been answered with 200, and its photo has been answered with 200 and a size and hash matching the phone's own.
- **Nothing is deleted** from the queue until the server has confirmed it.

How each answer is handled:

| Answer | What the app does |
|---|---|
| 200 to a completion, replayed or not | Marks the completion sent and stores the job the server returned. |
| 200 to a photo, size and hash match | Marks the photo sent. |
| 200 to a photo, size or hash differ | Uploads it again. My call: after three mismatches in a row it marks the photo "couldn't send". |
| No answer: no network, timeout, connection lost | Retries later. My call: the wait grows exponentially from about 2 seconds up to about 5 minutes, with jitter. The wait resets when the network comes back. |
| 500 `internal_error` | Retries, the same way. |
| 409 `request_in_progress` | Waits `Retry-After` seconds, then retries the same request. |
| 429 `write_limit_reached` | Pauses **all** writes for `Retry-After` seconds, since the limit covers the whole IP address. |
| 401 `unauthorized` | Stops sending everything, keeps the queue, and shows that the app can't send because of a configuration problem. It tries again on the next launch or foreground. |
| 400, 404, 413, 415, 422 | These shouldn't happen if the app is right. My call: the item is marked "couldn't send" and kept, never deleted, the job shows it, and the rest of the queue carries on. |

My call: requests time out after 30 seconds, or 60 seconds for a photo upload.

### Refreshing the list

- **When it refreshes:**
  - when the app launches or comes to the foreground
  - when the network becomes available
  - on pull-to-refresh
  - after the queue empties
- **If the refresh fails,** the app keeps the last list and shows "Updated hh:mm".
- **On first launch with no signal** there's no list yet, so the app shows an empty state saying it will load today's jobs once it has signal.
- **When the phone and the server disagree,** one rule decides. There's no merging.

| What the phone has | What the server says | What the app shows |
|---|---|---|
| A completion queued but not yet confirmed | The job is pending | Completed. The phone wins until the server confirms. |
| A completion queued | The job is completed, because the server recorded it but its answer was lost | Completed, and the app keeps sending. The server replays, then the app marks it sent. |
| A photo queued but not yet confirmed | Any `photo` value | The phone's photo, which it keeps sending. |
| Nothing pending | Anything | What the server says. |

My call: the proof that a photo arrived intact is the size and hash in the upload's own 200 answer, not a later refresh. Once a job is confirmed, nothing about it is pending, and the last row applies. The phone keeps the photo's bytes after confirmation, so the job screen can still show it. It never uploads a confirmed photo again.

## Screens

These come from the mockups the owner approved during brainstorming.

**Today's jobs.**

- **Header.** The title "Today" and "Updated hh:mm".
- **Banner.** It appears when there's no signal or something is waiting to send, for example: "No signal. 2 jobs are waiting to send and will go when the signal comes back."
- **Rows.** One per job: the time window, the address, the task, and a status label:
  - **To do**
  - **Done · waiting**
  - **Done · sent**
  - **Done · couldn't send** (my call, for the failure cases above)
- **Pull-to-refresh.**

**A job.**

- **Details.** The address, the task and the time window.
- **Photo area.** Tapping it opens the camera. Once taken, the photo is shown.
- **Note field.** It has an "n / 1000" counter.
- **Complete job button.** It stays disabled until there's a photo.
- **After Complete.** Everything is read-only, and the job shows "Completed hh:mm" with "waiting to send", "sent" or "couldn't send".

**Accessibility (my call).**

- Dynamic Type works on both screens.
- Every status is spoken by VoiceOver.
- No status relies on colour alone.
- The photo area has a VoiceOver label.

All text is in English.

## Architecture

Clean Architecture. The dependencies point inwards towards Domain, with dependency inversion between Domain and Data:

```
SwiftUI view → view model → use case → JobRepository (protocol, in Domain)
                                              ↑ implements
                                   Data: Core Data + API client
```

- **Domain**, a local Swift package with no dependencies besides Foundation.
  - **Entities:** `Job`, its sync state (to do, waiting, sent, couldn't send), and photo info. They're value types and `Sendable`.
  - **`JobRepository`:** a protocol.
  - **Use cases:**
    - load jobs: the cached list, plus a refresh
    - attach a photo: save the draft
    - complete a job: checks there's a photo and the note fits
    - send pending work
  - My call: the use cases are concrete types, without protocols of their own.
- **Data**, a local Swift package that depends on Domain. It holds:
  - the Core Data stack, with one store for both the cached jobs and the queue
  - the API client, on URLSession
  - the queue sender and its retry rules
  - the network monitor
  - the `JobRepository` implementation

  Core Data objects never leave this package: the repository maps them to Domain structs.
- **The app target (presentation).**
  - SwiftUI views and `ObservableObject` view models. Views talk only to view models, and view models only to use cases.
  - The app's entry point is the only place that creates Data's types and hands them to the use cases, through plain initializers, with no dependency-injection framework.
  - The camera wrapper and the JPEG encoding live here, because they need UIKit. Domain receives plain bytes.
- My call: the repository tells the view models about changes, such as a job's state moving from waiting to sent, through an `AsyncStream<[Job]>`. That's part of the standard library, so Domain stays free of Combine and Core Data.
- **Photos** are a binary attribute with external storage turned on.

## Platform and constraints

- SwiftUI, built with Xcode 27.2. The oldest supported version is iOS 15.6.
  - Because of that, view models use `ObservableObject` and `@Published` rather than `@Observable`, and screens use `NavigationView` rather than `NavigationStack`.
  - The camera and the photo picker go through a UIKit wrapper.
- No third-party libraries. URLSession, Core Data, Network, CryptoKit and UIKit cover everything.
- The iOS code lives under `ios/`.
- The rules in `AGENTS.md` apply:
  - tests come before code
  - one pull request per plan task, targeting `develop`, merged only by the owner
  - no force-pushing
  - everything written in English

## Configuration and secrets

- **Committed xcconfig files**, one per build configuration, set the API host: Debug uses dev and Release uses production. Only the host is stored, because xcconfig treats `//` as the start of a comment.
- **The API key** lives only in `ios/Secrets.xcconfig`, which git ignores. The committed files pull it in with an optional include (`#include?`), so the project still builds without it, as in CI unit runs.
- **The host and key reach the app** through Info.plist build settings. My call: `Secrets.xcconfig` holds one key per environment.
- **A missing key** blocks sending in the same way as a 401.
- **The key is never logged.** The app logs no request headers.
- **The install ID** is a UUID made on first launch and kept in `UserDefaults` (my call). A reinstall wipes the local data, so it gets a new ID with fresh jobs, which is consistent.

## Testing and CI

Tests come first, using Swift Testing.

Xcode 27.2's Swift Testing framework is built for iOS 17.0 at the earliest; its module interface targets `ios17.0-simulator`. Test targets therefore need a minimum of iOS 17.0, while the app and the Domain and Data packages stay at 15.6. How the package tests meet that minimum, for example by also declaring macOS and running there, is left to the builder.

**Unit tests** never call the live API.

- **What they run against:**
  - Use cases run against a fake `JobRepository`.
  - View models run against the real use cases on top of a fake repository.
  - The API client runs against a stubbed network layer, a `URLProtocol` subclass.
  - Core Data runs against an in-memory store.
- **Scenarios they must cover:**
  - The signal drops after a completion has been sent but before its answer arrives. The retry carries the same key and the same body.
  - The job state and the queued requests are written in one save. Nothing is half-written.
  - 409 and 429 are honoured, and 429 pauses every write.
  - 401 stops sending. 400, 404, 413, 415 and 422 mark the item "couldn't send" without deleting it.
  - A photo whose hash doesn't match is uploaded again, and is marked "couldn't send" after three mismatches.
  - Every row of the refresh table in "Refreshing the list".
  - The note limit, counted in UTF-16.
  - **Complete job** is disabled without a photo.
  - The JPEG always fits within 5,242,880 bytes.

**Integration tests** run as a separate test plan or target against the dev API, using a new install ID on every run.

- **What they check:**
  - Sending the same completion twice with the same key gets the second answer with `Idempotent-Replayed: true`, and the job is recorded once.
  - An uploaded photo's size and SHA-256 come back matching.
- **They stay small.** They use only a handful of writes per run, because of the 500-per-day limit for each IP address.
- **Without a dev key** they're skipped, with a clear message. That covers local runs. CI always supplies the key.

**CI** is GitHub Actions, on pull requests and on pushes to `develop` and `main`.

- **Runner:** a macOS image with Xcode 27.
- **Builds:** the app, for iOS 15.6.
- **Tests:**
  - the unit tests, on the newest iOS simulator
  - the integration tests, with the dev key from a repository secret (my call for the name: `SHOWCASE_DEV_API_KEY`)
- **The key is never echoed.**

No GitHub runner has an iOS 15 or 16 simulator; the oldest is iOS 17.0. The owner accepted that iOS 15.6 is only checked by the compiler, which refuses any API newer than the minimum version.

## Left to the builder

- The names of the project, targets and packages, and the layout under `ios/`.
- Whether the Core Data model is written in code or as an `.xcdatamodeld` file.
- How Core Data's contexts are split between the UI and the sender, provided the save on Complete stays atomic.
- Swift language mode and concurrency details, with `Sendable` Domain types required.
- The exact retry timings within the ranges given, and the exact wording of on-screen text.
- The CI runner label, the workflow layout and the simulator model.
- The order of tasks in the plan.
