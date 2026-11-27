# Roadmap

## Next

- Validate opt-in Sender reconnect with physical cable pull, Receiver
  restart, and repeated outage/recovery cycles; verify manual stop cancels it.
- Validate closed-lid MacBook operation with external power, display, keyboard
  and mouse; the app cannot suppress macOS lid-close sleep by itself.
- Make the Receiver's macOS 11 dependency build reproducible. The source target
  alone is insufficient: upstream issue #167 documents a missing Big Sur
  CoreVideo symbol in bundled FFmpeg libraries.
- Build and audit the Receiver separately for x86_64 and arm64 using matching
  dependency architectures and a unique bundle identity.
- Run the legacy package on Intel Big Sur and complete sustained Full HD,
  reconnect, and sleep/wake acceptance before any release proposal.

## Planned

- Continue implementing the opt-in Closed-Lid Streaming Power native add-on.
  The pure safety policy and public battery/thermal monitor are in place.
  The helper transaction coordinator and durable lease recovery are tested.
  An unregistered LaunchDaemon/XPC executable builds for Intel and arm64 and
  uses signed-team filtering plus fixed `pmset` arguments. Next: configure the
  production signing identity, add launchd packaging and Sender client, then
  threat-review IPC and recovery before stream integration or UI. Derive the
  client UID from authenticated XPC identity and keep all
  settings calls behind an allowlisted interface. Keep it separate from idle-sleep
  control; require explicit administrator authorization, restore the exact prior power setting, and stop streaming on
  configured low-battery or critical thermal conditions. Complete the
  compatibility and physical hardware gates in
  [Closed-Lid-Power-Addon.md](Closed-Lid-Power-Addon.md) before release.
- Re-test Sender/Receiver combinations on Intel and Apple Silicon hardware.
- Track upstream issue #223 for Ventura compatibility and PR #243 for 5K
  receiver backpressure; adopt only after review and mixed-version validation.
- Keep the Receiver Legacy experiment separate from the stable Intel Sender
  release and its signing/package workflow.

## Exploratory

- Additional display profiles and automatic profile selection from receiver
  panel capabilities.
