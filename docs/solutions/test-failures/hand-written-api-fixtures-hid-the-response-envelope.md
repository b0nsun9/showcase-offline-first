---
title: Hand-written API fixtures hid that the server wraps its answers in an envelope
date: 2026-11-06
category: test-failures
module: ios/Packages/Data (APIClient)
problem_type: test_failure
component: api_layer
symptoms:
  - "All unit tests passed while the client could not decode a single real server answer"
  - "Against the real API every refresh would fail and every completion's 200 would be retried forever"
  - "The integration tests that would have caught it were always skipped because no dev key was set"
root_cause: test_isolation
resolution_type: test_fix
severity: critical
tags: [api-client, fixtures, openapi, integration-tests, envelope, offline-first]
---

# Hand-written API fixtures hid that the server wraps its answers in an envelope

## Problem

The API answers `GET /v1/jobs` with `{"jobs": [Job]}` and `POST /v1/jobs/{id}/complete` with `{"job": Job}`. The client decoded a bare `[JobDTO]` and a bare `JobDTO`, and its unit tests passed, because their stub answers had been written by hand in the same bare shape. A later review of the send queue caught it. Shipped, every refresh would have failed, and an undecodable 200 maps to a retryable network failure, so every completion would have been re-sent forever until the server's 500-writes-a-day limit answered 429.

## Symptoms

- All unit tests passed while the client could not decode a single real server answer.
- Against the real API, every refresh would fail and every completion's 200 would be retried forever.
- The integration tests that would have caught it were always skipped, because no dev key was set.

## What Didn't Work

- **Unit tests with invented fixtures.** A stub answer written from memory tests the client against the author's belief, not against the server. Fixture and client agreed, so the tests passed.
- **Integration tests that only run with a key.** `DevAPITests` call the real dev API, and `sameKeyTwiceIsRecordedOnce` decodes a real completion answer, but they're skipped when `SHOWCASE_DEV_API_KEY` is unset. Neither the build machine nor CI had the key, so the one test grounded in the real server never ran.

## Solution

- The client decodes the documented envelopes through private wrappers, and its signatures stay as they were (pending in PR #4).
- The fixtures in `ios/Packages/Data/Tests/DataTests/APIClientTests.swift` are copied from the OpenAPI document's `JobList`, `JobEnvelope` and `Job` schemas, including every required field.
- `bareShapesAreRejected` pins the old wrong shapes as failures, so the fixtures can't drift back.

## Why This Works

The fixtures now come from the server's own contract instead of the client author's assumption, and the regression test makes the old assumption fail loudly. The remaining gap closes only when the live tests actually run.

## Prevention

- Copy stub answers from the OpenAPI document (`https://dev.api.showcase.bonsung.me/openapi.json`), never from memory. Re-check them when the API's version changes.
- Treat an always-skipped live test as no test. Set the GitHub secret `SHOWCASE_DEV_API_KEY`, so CI runs `DevAPITests` on every pull request from this repository, and run them locally before merging API-layer changes.

## Related Issues

- `docs/solutions/logic-errors/server-echo-mid-sync-overwrites-phone-owned-photo.md`: a test fake that didn't match what the real server returns at that step hid a bug in the same way.
