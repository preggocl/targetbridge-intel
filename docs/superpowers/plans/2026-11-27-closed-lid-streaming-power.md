# Closed-Lid Streaming Power Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current Codex session. Keep the implementation native to the TargetBridge Sender; do not introduce arbitrary executable JSON addons.

**Goal:** Add an opt-in, safety-controlled Sender subproject that can keep a live stream running with a MacBook lid closed, while monitoring battery and thermal state and restoring macOS power policy.

**Architecture:** Build a pure policy/state layer, public power/thermal adapters, then a narrowly scoped privileged helper with a durable lease/journal and exact restoration. Connect it to the existing Sender stream lifecycle and settings only after helper failure/recovery semantics are implemented. Keep the existing idle-sleep assertion separate.

**Tech Stack:** Swift 6, SwiftUI, IOKit `IOPowerSources`, Foundation `ProcessInfo`, XcodeGen, XCTest, macOS privileged launch service selected after deployment-target review.

**Spec:** `docs/Closed-Lid-Power-Addon.md`

## Global Constraints

- The add-on is off by default and may change power policy only during an opted-in active stream.
- Require external power by default; the initial proposed low-battery threshold is 25% and must be user-configurable before release.
- At serious thermal state reduce stream workload; at critical state stop capture, disable reconnect for that safety stop, and restore power policy.
- Capture the prior sleep setting durably before mutation and use compare-and-restore so newer user settings are not overwritten.
- The app must not run as root; the helper accepts only a small validated command set and never arbitrary shell input.
- The privilege notice is a quiet inline disclosure below the setting, localized in all six shared languages.
- Current Sender deployment target is macOS 14.0. Do not claim macOS 11 Sender compatibility from Receiver Legacy work.
- Do not add private brightness/temperature APIs or a virtual display as part of this add-on.
- Never install/register a privileged helper or change system power settings in development validation.

## Review Focus

- Unknown or stale power-source readings must never be treated as AC power; pin this in policy tests.
- A low-battery safety stop must cancel auto-reconnect before stopping streaming; pin this in integration tests.
- Critical thermal state must stop capture and restore policy; pin this in policy and lifecycle tests.
- An external power-setting change during a session must survive teardown; pin this in helper transaction tests.
- Helper loss, app force-quit, and reboot must recover an orphaned override; pin these in helper recovery tests and physical acceptance.

---

### Task 1: Pure safety policy and state model

**Files:**
- Create: `TargetBridge-Sender/TBDisplaySender/Addons/ClosedLidPower/TBClosedLidPowerPolicy.swift`
- Modify: `TargetBridge-Sender/TBDisplaySenderTests/TBClosedLidPowerPolicyTests.swift`

**Interfaces:**
- Produce `TBClosedLidPowerObservation`, `TBClosedLidPowerThermalState`, `TBClosedLidPowerSource`, `TBClosedLidPowerAction`, and `TBClosedLidPowerPolicy.evaluate(_:configuration:)`.
- `evaluate` is pure: no I/O, timers, process calls, helper calls, or Sender singleton access.

- [x] Write tests for disabled/waiting state, AC streaming, battery opt-in, unknown power, threshold stop, serious thermal reduction, critical thermal stop, and lid/helper unavailable.
- [x] Run focused XCTest to confirm the new tests fail because policy types/behavior are missing.
- [x] Implement the smallest pure policy reducer that passes those cases.
- [x] Re-run focused tests; 10 policy tests pass. Full existing Sender suite remains pending.
- [ ] Commit the policy as an isolated change.

### Task 2: Public battery and thermal observations

**Files:**
- Create: `TargetBridge-Sender/TBDisplaySender/Addons/ClosedLidPower/TBClosedLidPowerMonitor.swift`
- Modify: `TargetBridge-Sender/TBDisplaySenderTests/TBClosedLidPowerMonitorTests.swift`

**Interfaces:**
- Produce a main-actor observable monitor with current power source, battery percentage, thermal state, support/availability, and deterministic shutdown.
- Read power data through IOPowerSources and subscribe to source-change notifications; read thermal state through ProcessInfo and observe its change notification.

- [x] Add tests for unavailable battery data, percentages outside 0...100, and observer cleanup. Unknown thermal support handling is implemented as an explicit unsupported state.
- [x] Run focused tests and confirm the intended failures.
- [x] Implement public-API adapters with injectable readers for deterministic tests.
- [ ] Re-run existing Sender suite; compile x86_64 and arm64 configurations.
- [ ] Commit the monitor separately.

### Task 3a: Helper transaction core and service decision

This is a safe prerequisite for the helper target; it does not access macOS
power settings or install/register privileged services.

- [x] Select `SMAppService` LaunchDaemon for the current macOS 14 floor; do not use deprecated `SMJobBless`.
- [x] Require XPC peer code-signing validation; ad-hoc builds must report the feature unavailable.
- [x] Add pure transaction decisions for begin/restore, session ID validation, and compare-before-restore.
- [x] Add focused tests for prior value, invalid/existing sessions, external changes, and bounded identifiers.
- [x] Implement a private atomic lease journal and serialized session coordinator with injected settings I/O, owner checks, bounded heartbeat expiry using monotonic uptime, compare-and-restore, and boot-session recovery decisions.
- [x] Test filesystem mode/owner, malformed/symlink records, lease expiry, wrong owner, helper retry after failed restore, external setting changes, and boot-session change.
- [x] Add an unregistered daemon executable target with fixed-argument `pmset`, signed-team XPC listener gate, peer UID ownership, watchdog, and allowlisted XPC methods.
- [x] Derive the required peer Team ID from the helper's own code signature; reject unsigned/ad-hoc identity before activating the listener.
- [x] Unit-test the exact `pmset` executable/argument allowlist and fail-closed output parser without launching the process.
- [ ] Add LaunchDaemon packaging metadata and Sender client only after signing identity, peer verification, IPC integration tests, and lifecycle recovery are reviewed.
- [ ] Threat-review code identity, IPC framing/allowlist, journal permissions, crash/reboot recovery, and uninstall.

The injected coordinator tests do not invoke `pmset`; the compiled but
unregistered daemon target contains that adapter. The daemon derives caller
UID from XPC's kernel-supplied `effectiveUserIdentifier` after the listener's
code-signing gate, never from a request field. Use one coordinator instance
inside the singleton daemon to serialize all client sessions. Do not run the
helper in development while its approved signing team is unconfigured.

### Task 3: Privileged helper and reversible power-policy transaction

**Files:**
- Create: `TargetBridge-Sender/ClosedLidPowerHelper/` helper target, XPC protocol, launch service metadata, and root-owned recovery journal.
- Modify: `TargetBridge-Sender/project.yml`, signing/package scripts, helper security documentation.
- Create: helper transaction and recovery tests.

**Interfaces:**
- Expose only validated `beginSession`, `heartbeat`, `status`, and `endSession` operations.
- Persist the original policy before applying an override; compare current value before restoration; serialize concurrent sessions; recover expired/orphaned leases after helper restart and reboot.

- [x] Select the service mechanism compatible with the exact supported macOS floor and code-signing model (`SMAppService` LaunchDaemon, macOS 14+).
- [ ] Threat-review authorization, XPC peer validation, file permissions, replay/race behavior, crash recovery, and uninstall.
- [ ] Test command allowlisting, invalid requests, session ownership, exact restoration, compare-and-restore, expiry, helper restart, and boot recovery.
- [ ] Build without registering/installing the helper; manual registration and power changes require a separate explicit user action.
- [ ] Commit only after the helper and recovery tests pass.

### Task 4: Sender lifecycle and safety integration

**Files:**
- Modify: `TargetBridge-Sender/TBDisplaySender/TBDisplaySenderService.swift`
- Modify: `TargetBridge-Sender/TBDisplaySender/TBDisplaySenderManager.swift`
- Modify: reconnect and stream lifecycle tests.

**Interfaces:**
- Start a helper lease only after capture is live and the feature is enabled.
- On stop/failure/safety event, cancel reconnect first, stop capture, then end the helper lease and verify restoration.
- Serious thermal state requests a reduced-cost profile; critical thermal and low battery stop the stream with a visible reason.

- [ ] Test ordering and idempotency for manual stop, Receiver loss, low battery, critical thermal, and helper failure.
- [ ] Implement lifecycle integration without changing the existing default keep-awake behavior.
- [ ] Re-run focused and full Sender suites.
- [ ] Commit lifecycle integration separately.

### Task 5: Settings UI, warning, localization, and physical acceptance

**Files:**
- Modify: `TargetBridge-Sender/TBDisplaySender/TBDisplaySenderSettingsView.swift`
- Modify: `TargetBridge-Sender/TBDisplaySender/TBDisplaySenderLocalization.swift`
- Modify: all six `TargetBridge-Shared/Languages/*.json` files.
- Update: `docs/Closed-Lid-Power-Addon.md`, `docs/Features.md`, `docs/Testing.md`, `docs/Compatibility.md`, `docs/PROJECT_STATE.md`, `docs/HANDOFF.md`, `docs/ROADMAP.md`, `docs/CHANGELOG.md`.

**Interfaces:**
- Add an opt-in setting with a quiet inline administrator-authorization disclosure and clear active/paused/unavailable status.
- Battery threshold starts at 25%; battery operation is explicit opt-in and unavailable when power readings are unknown.

- [ ] Test preference defaults, accessible disclosure, all six translations, capability fallbacks, and stop-reason messaging.
- [ ] Build x86_64 Intel and arm64 Apple silicon products without installing the helper.
- [ ] On physical Macs, test lid open/close, AC removal, low battery, thermal transitions, Receiver drop, manual stop, force-quit, helper restart, reboot, and restoration of non-default prior settings.
- [ ] Only claim the OS/architecture combinations that passed the full acceptance matrix.
- [ ] Update continuity docs with exact build number, commit, and target-platform evidence.

## Current execution boundary

Tasks 1, 2, and the pure lease/journal/coordinator core are implemented. Do not expose an enabled clamshell control until
Tasks 3 and 4 provide a real, recoverable privilege boundary. The initial
milestone must remain safe to build and run without admin authorization and
without changing macOS power settings.
