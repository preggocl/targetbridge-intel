# Changelog

## Unreleased — Sender connection recovery

- Added opt-in Sender reconnect retries for Receiver/link loss and failed
  connection attempts, using 2–30 second capped backoff.
- Added a separate default-on keep-awake option during active capture; display
  sleep remains independently configurable and lid-close sleep cannot be
  overridden by the app.
- Added x86_64 local review build `3.3.0` / `3.3.0-intel.1`, build
  `20261127023800`, archived under `build-intel/backups/`; 85 tests passed and
  the app opened locally. Physical link recovery is not yet validated.

## Unreleased — Closed-lid power add-on design

- Documented an opt-in native Sender subproject for temporary closed-lid
  streaming power control, including a restrained privilege notice, helper
  security boundary, battery/thermal safeguards, and Intel/Apple silicon
  compatibility gates. No privileged helper or power-setting change is
  implemented in this design milestone.

## Unreleased — Closed-lid safety foundation

- Added a pure stream power policy plus public IOPowerSources battery and
  ProcessInfo thermal observations with focused tests. This is an internal
  foundation only; no lid override, privileged helper, lifecycle integration,
  or settings control is enabled.
- Selected Apple's `SMAppService` LaunchDaemon path for the current macOS 14
  floor and added a tested pure begin/restore transaction model. Registration,
  XPC, daemon integration, and production power-setting I/O remain unimplemented.
- Added a serialized session coordinator and atomic private lease journal with
  120-second monotonic heartbeat expiry, boot-session recovery, owner/mode
  checks, and compare-before-restore. Tests use injected settings storage;
  production daemon, XPC, and system-setting adapter remain unimplemented.
- Verified the expanded Sender suite: 116 tests pass; Intel Release and arm64
  Debug builds succeed.

## Unreleased — Full HD legacy receiver support

- Added 1920 × 1080 H.264 profiles at 30 fps and 60 fps.
- Added a Full HD extended-desktop quick profile for conservative receivers.
- Increased capture surface headroom using the upstream capture-pool approach.
- Verified 84 x86_64 Sender tests and a local x86_64 Release build.
