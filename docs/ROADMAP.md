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

- Re-test Sender/Receiver combinations on Intel and Apple Silicon hardware.
- Track upstream issue #223 for Ventura compatibility and PR #243 for 5K
  receiver backpressure; adopt only after review and mixed-version validation.
- Keep the Receiver Legacy experiment separate from the stable Intel Sender
  release and its signing/package workflow.

## Exploratory

- Additional display profiles and automatic profile selection from receiver
  panel capabilities.
