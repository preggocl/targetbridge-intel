# Closed-Lid Streaming Power Add-on

Status: **safety policy, public battery/thermal monitor, and pure restore
transaction model implemented; no privileged code is installed and the feature
is not user-operational**
Owner: TargetBridge Sender  
Scope: optional, native Sender add-on for keeping an active stream alive when a
portable Mac's lid closes, with explicit power, battery, and thermal safeguards.

## Decision

Build this as an internal subproject of the TargetBridge repository and Sender,
not as a separate repository or a user-importable JSON addon. The feature must
coordinate with capture, connection recovery, and stream teardown. The current
manifest addon system gates built-in capabilities and intentionally does not
load executable code; it is not an appropriate privilege boundary.

The feature is opt-in and off by default. Its stronger lid-close behavior may
change a system-wide macOS power setting and therefore requires a narrowly
scoped, explicit administrator authorization. It may only be active while a
Sender stream is running. The setting is temporary and the add-on must restore
the value it found before the session on every normal or recoverable exit.

This add-on does not create a virtual display and does not claim to make a
TargetBridge Receiver count as Apple's physically attached clamshell display.
It is an optional software workaround, not an Apple-supported clamshell mode.

### Implementation status (2026-11-27)

The current development milestone adds a pure safety-policy reducer, an
injectable monitor using IOPowerSources and ProcessInfo thermal notifications,
and a pure helper-transaction model for prior-value capture, bounded session
identifiers, and compare-before-restore decisions. Focused Intel-architecture
tests cover these pieces. The privileged design now targets an `SMAppService`
LaunchDaemon under the existing macOS 14 deployment floor, with XPC restricted
to the signed TargetBridge team and a single allowlisted power-policy
operation. There is no daemon target or registration code, durable journal,
XPC transport, lid sensor, stream lifecycle integration, settings control, or
hardware acceptance yet. This implementation cannot keep a Mac awake with its
lid closed and does not change system power settings.

## User experience and warning

Place the control in Sender Settings beside the existing streaming power
controls. Keep the privilege explanation visible but understated: a small
information disclosure directly below the switch, not a blocking warning
dialog or bright alert banner.

Proposed Spanish copy:

> Requiere autorización de administrador para ajustar temporalmente el reposo
> de macOS. TargetBridge restaura el ajuste anterior al terminar la sesión.

Proposed English copy:

> Administrator authorization is required to temporarily adjust macOS sleep.
> TargetBridge restores the previous setting when the session ends.

The first-use system authorization prompt is expected. The inline explanation
must also say that a closed Mac remains powered and needs an open, ventilated
surface. Do not imply that the add-on prevents heat, guarantees battery health,
or overrides thermal emergencies.

Localize the control and disclosure in all six shared Sender languages. Keep
the explanatory copy available after first-run authorization; the permission
is not a one-time warning that can never be reviewed again.

The UI should distinguish states: off, waiting for stream, active on AC,
active on battery (only if the user explicitly enabled battery operation),
paused by safety guard, and unavailable on this Mac/macOS. Show the reason when
the add-on stops a stream.

## Session behavior

1. The user enables the feature and approves the privileged helper once.
2. The Sender waits; it does not alter power settings just because the app is
   open or logged in.
3. When capture and streaming are both active, check power source, battery,
   thermal state, and (where safely supported) lid state.
4. If the lid is closed and policy permits the session, request the temporary
   lid-close sleep override from the helper. Keep the regular idle-sleep
   assertion separate; it does not suppress forced lid-close sleep.
5. On manual stop, Receiver loss after reconnect policy is exhausted, Sender
   quit, or any safety stop: stop capture, cancel reconnect work, restore the
   original power setting, and release the helper session lease.
6. If the helper loses its client, the session lease expires, or the app
   crashes, a watchdog must restore the prior setting. A reboot must also leave
   the machine in its normal policy; verify actual `pmset` persistence on every
   supported OS rather than assuming it.

The helper must not accept arbitrary shell commands. Its protocol should be
limited to authenticated `begin-session`, `heartbeat/status`, and `end-session`
requests with a bounded session identifier and validated policy. The app itself
must never run as root. Save and restore the exact prior value; do not blindly
write `0` if the user already had sleep disabled before TargetBridge started.

## Safety policy

### Power source and battery

- Require external power by default. A user may explicitly allow battery use.
- When battery use is enabled, offer a configurable stop threshold. Start with
  a conservative default of 25%; validate a permitted range during UX and
  hardware testing before implementation.
- If the saved pre-session policy already disables sleep, do not arm a
  battery-powered closed-lid session in the first version. Preserve that user
  policy and require AC for the override instead.
- On threshold crossing, stop capture and streaming gracefully, disable
  automatic reconnect for that safety stop, restore normal sleep policy, and
  request ordinary macOS sleep if needed to reduce further discharge.
- Treat missing, stale, or unknown battery readings as unsafe for a
  battery-enabled closed-lid session. Do not assume AC is connected.
- Describe this as a low-battery safeguard, not a guarantee that charge can
  never reach zero. Battery reporting and system shutdown have latency, and a
  degraded battery can behave unpredictably.

Use IOPowerSources notifications and descriptions where available. The API
reports capacity and power-source changes; do not poll shell output as the
primary production interface.

### Thermal state

- Observe `ProcessInfo.thermalState` and its change notification where the
  deployment target supports it.
- At `serious`, reduce stream workload where possible (lower frame rate or
  select a lower-cost encoding/profile) and tell the user the safeguard is
  active.
- At `critical`, stop capture/streaming, disable reconnect for the safety stop,
  and restore the original sleep policy immediately.
- On systems that do not expose thermal-state support, surface that thermal
  protection is unavailable. Some older systems report `nominal` when the API
  is unsupported, so check OS/API availability separately; do not infer support
  from that value alone.
- Do not build a private temperature-sensor reader for the first version.

Apple's thermal API exposes a coarse system state, not a temperature in
degrees. It can be unavailable on older systems, and a safety response cannot
guarantee that hardware will never overheat.

### Lid and display

Lid detection through `AppleClamshellState` is used by third-party examples but
is not a stable public contract. Treat it as a compatibility adapter behind a
capability check. Verify it on every supported Intel/Apple silicon and macOS
combination. If it cannot be read, do not attempt the lid-close override.

Do not dim the built-in panel using private `DisplayServices` APIs in the
initial version. The native macOS behavior may disable the internal display
when the lid closes; the stream must rely on the Sender's capture/display
pipeline and be tested for that condition.

## Privilege and security boundary

The actual override used by the referenced projects is a system-wide power
setting (`pmset disablesleep`), not a per-process assertion. The implementation
must therefore:

- isolate privileged work in a small helper with a strict allowlist;
- ask for authorization only when enabling the feature for the first time;
- change the setting only during an active, explicitly opted-in stream;
- durably record the pre-session value before changing it and restore it on
  stop, timeout, error, and helper/app lifecycle events;
- use compare-and-restore behavior so a newer user/system setting made during
  the session is not overwritten by a stale saved value;
- prevent two Sender instances from racing over the saved value;
- recover an orphaned session from a root-owned journal if the helper exits or
  the Mac restarts; test reboot behavior instead of assuming it resets state;
- keep an audit-friendly status/reason in the app without logging private data;
- fail closed: if authorization, state capture, helper health, or restore
  verification fails, stop/decline the closed-lid mode and leave macOS policy
  untouched where possible.

Use the macOS 13+ `SMAppService` LaunchDaemon mechanism for the current macOS
14.0 Sender floor. Registration requires explicit administrator approval;
observe its status and provide a clear unsupported/approval-required state.
`SMJobBless` is deprecated and is not the selected path. Require a real
Developer ID team identity for production helper communication; ad-hoc builds
must leave the privileged feature unavailable. The legacy Receiver work does
not change this floor. Do not lower the Sender deployment target or claim
legacy support as part of this add-on without a separate build/runtime
compatibility decision.

## Compatibility and validation matrix

The desired architecture is `x86_64` Intel and `arm64` Apple silicon, with
Rosetta treated separately from native arm64. The current project configuration
sets the Sender deployment target to macOS 14.0. Existing Receiver Legacy
support does not imply that this Sender or its helper runs on macOS 11.

Before implementation is called compatible, test at least:

| Host | Required evidence |
|---|---|
| Intel Mac, current supported macOS | Build, helper authorization, lid event, stream continuity, restore on stop/crash |
| Apple silicon Mac, current supported macOS | Same checks, plus accessory/power behavior and native arm64 |
| Intel Mac on the oldest proposed Sender macOS | APIs compile and run, thermal/battery capability fallback, helper install/remove |
| Apple silicon Mac on the oldest proposed Sender macOS | Native arm64 behavior and same safety checks |
| Rosetta Sender on Apple silicon | Separate x86_64 behavior; do not infer from native arm64 |

For each host, verify AC removal, battery threshold, unknown battery data,
thermal-state transitions where injectable, lid open/close, Receiver drop,
manual stop, app force-quit/crash, helper restart, reboot, and exact restoration
of a non-default pre-session power setting. A simulator or unit test cannot
prove clamshell behavior; physical hardware acceptance is required.

## Relationship to the four reviewed projects

- **DoDo** is the closest lifecycle/safety reference: temporary sessions,
  charger policy, battery cutoff, thermal cutoff, and a restricted helper.
- **ClosedDisplay** is a useful state-machine reference for lid, power, and
  thermal monitoring, but its published requirements are Apple silicon and
  macOS 14+.
- **nosleep** is a useful reference for bounded operation and low-battery
  cutoff. Its private brightness helper and standalone CLI are not in scope.
- **mac-keepawake** demonstrates an older macOS-oriented approach, but its
  maintainer says Intel is untested and it changes additional display and
  screen-saver settings that TargetBridge does not need.

No source code is copied from these projects in this design document. If code
is later reused, preserve its MIT notice and attribution and review it against
TargetBridge's security and compatibility requirements.

## Implementation milestones

1. Prototype unprivileged capability detection for power source, thermal
   state, and lid state; record hardware/OS results before enabling any system
   setting.
2. Add a pure state machine and tests for session lifecycle, battery cutoff,
   thermal response, helper loss, and restore decisions.
3. Implement and threat-review the minimal privileged helper and its
   authorization/install/uninstall path.
4. Add the opt-in Settings UI and understated privilege disclosure, initially
   behind an internal feature flag.
5. Validate on physical Intel and Apple silicon Macs, including the oldest
   supported OS, then decide whether to ship it with the Sender.

## Sources checked

- [DoDo](https://github.com/juliennigou/DoDo)
- [ClosedDisplay](https://github.com/DINHDUY/mac-closed-display)
- [nosleep](https://github.com/omsimos/nosleep)
- [mac-keepawake](https://github.com/fainir/mac-keepawake)
- [Apple ProcessInfo thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
- [Apple IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple Service Management helper migration](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Apple XPC peer signing requirements](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:))
- [Apple: idle-sleep assertion behavior](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
