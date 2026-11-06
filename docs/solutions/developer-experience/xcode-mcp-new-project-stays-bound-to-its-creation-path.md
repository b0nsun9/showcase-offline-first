---
title: A project made with Xcode's XcodeNewProject stays bound to the path it was created at
date: 2026-11-06
category: developer-experience
module: ios/FieldJobs.xcodeproj (created through Xcode's MCP server)
problem_type: developer_experience
component: tooling
severity: medium
applies_when:
  - "Creating an Xcode project or target with Xcode's MCP server (`xcrun mcpbridge`, `.mcp.json`)"
  - "Moving a project that XcodeNewProject created somewhere else before editing it further"
  - "Editing the project file by hand where the MCP server has no tool"
retire_when: "Xcode's XcodeNewProject rebinds a moved project, or the MCP server gains tools for packages, xcconfigs and schemes; check the Xcode release notes and the tool list a newer Xcode's MCP server reports"
tags: [xcode, mcp, xcodenewproject, project-file, xcproj, tooling]
---

# A project made with Xcode's XcodeNewProject stays bound to the path it was created at

## Context

The owner chose Xcode's own MCP server over hand-writing a project file or using a generator such as Tuist. `XcodeNewProject` writes `<destination>/FieldJobs/FieldJobs.xcodeproj`, plus a source folder next to it. The plan created the project in an empty temporary directory and moved both items into `ios/` together.

After the move, `GetTargetBuildSettings` still showed `SRCROOT` at the temporary path. Xcode had kept the new project document bound to where it was created. So every later MCP edit, including the `FieldJobsTests` target that `XcodeNewTarget` added, went into the temporary copy, and nothing reached `ios/`.

## Guidance

- **After moving a project that `XcodeNewProject` created,** first call `XcodeCloseWorkspace`. Then move any files Xcode wrote in the meantime, and open the moved project with `XcodeOpenWorkspace`. Before any further MCP edit, confirm that `SRCROOT` resolves to `ios/` (`GetTargetBuildSettings`). An alternative is to close the workspace straight after `XcodeNewProject` and move only then.
- **Xcode 27.2 writes the project as `project.xcproj`,** a JSON format whose schema is at github.com/apple/xcode-project-format. It is not the older `project.pbxproj`. Opening it needs Xcode 27 or later, and CI's `xcode-27` runner is already there.
- **After any hand edit,** check the file with `xcrun xcprojformatter`, which decodes it and prints it in canonical form. Then let Xcode re-open it.
- **The MCP server has no tool for four things,** so they're hand edits to `project.xcproj` or files next to it:
  - local Swift package references and the products a target links (`Packages/Domain`, `Packages/Data`)
  - base configurations, which point the build configurations at `ios/Debug.xcconfig` and `ios/Release.xcconfig`
  - a unit-test target's test host and dependency on the app
  - the shared scheme under `ios/FieldJobs.xcodeproj/xcshareddata/xcschemes/`. Xcode keeps an auto-created scheme only in memory, and CI's `xcodebuild -scheme` needs it on disk.

## Why This Matters

The failure is silent. Every MCP call succeeds, and the edits look applied inside Xcode, but the repository's copy never changes. Without this check, the next engineer adding a target or setting through the MCP server can lose the work to a temporary directory and rediscover the cause from build-setting paths.

## When to Apply

- Any time `XcodeNewProject` or `XcodeNewTarget` is used in this repository, including a later widget or extension target.
- Any review of `ios/FieldJobs.xcodeproj` changes that were made outside Xcode.

## Examples

What worked for Task 5 of `docs/plans/2026-11-06-ios.md`:

1. `XcodeNewProject` into an empty temporary directory, then `mv` the `.xcodeproj` and the source folder into `ios/`.
2. `XcodeOpenWorkspace`, then `XcodeNewTarget` for the test bundle. Those edits landed in the temporary copy.
3. `XcodeCloseWorkspace`, then move the updated `project.xcproj` and the new test folder into `ios/` (it became `ios/FieldJobsTests/`), replacing the stale file.
4. The hand edits listed above, each checked with `xcrun xcprojformatter`.
5. `XcodeOpenWorkspace` on `ios/FieldJobs.xcodeproj`. `SRCROOT` now resolves to `ios/`, and later `UpdateTargetBuildSetting` calls land there.

## Related

- `.mcp.json`, which registers Xcode's MCP server for everyone working on the repository.
- Plan: `docs/plans/2026-11-06-ios.md`, Task 5 ("The project").
