# Handoff

Updated: 2026-11-27. Review branch: `receiver-legacy-upstream-sync`.

This branch carries forward the recovered Receiver Legacy changes from the
iCloud checkout and the upstream HEVC hardware-capability fix from PR #232.
The stable Sender release and its package identity remain unchanged. The
Receiver Legacy app uses a separate bundle identity and is excluded from the
Sender release workflow.

The iCloud source checkout remains on `receiver-legacy-software-decode` with
damaged Git ancestry. Its files mirror this review branch, but do future Git
commits from the clean review checkout instead of resetting or rebasing the
iCloud copy.

Next gates:

1. Rebuild and pin FFmpeg, SDL2/SDL3 and transitive libraries with macOS 11
   compatibility; the current Homebrew bundles may carry newer `minos` values
   or unavailable system imports.
2. Build x86_64 and arm64 packages against matching dependency slices and pass
   the bundle audit.
3. Launch and test on Intel Big Sur, then run at least 15 minutes of Full HD
   streaming with disconnect/reconnect and sleep/wake checks.
4. Revisit upstream PR #243 only after it is merged or its protocol and old/new
   Sender behavior have been independently validated.

The current development machine is Apple Silicon/macOS 15.7.7. It cannot
substitute for the Big Sur runtime gate. Keep the original upstream Receiver
installation and its preferences untouched.
