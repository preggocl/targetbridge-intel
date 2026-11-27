# Handoff

Updated: 2026-11-27. Review branch: `receiver-legacy-upstream-sync`.

Latest local Sender review build: product version `3.3.0`, Intel release
identifier `3.3.0-intel.1`, and full UTC build number `20261127023800`. It is
stored in `build-intel/backups/3.3.0-intel.1-build-20261127023800/` in the
active iCloud project. It opens on the development Mac; physical Receiver
recovery, Thunderbolt interruption and lid-close behavior still need hardware
testing.

This branch carries forward the recovered Receiver Legacy changes from the
iCloud checkout and the upstream HEVC hardware-capability fix from PR #232.
The stable Sender release and its package identity remain unchanged. The
Receiver Legacy app uses a separate bundle identity and is excluded from the
Sender release workflow.

The Sender now automatically retries dropped/failed Receiver connections with
capped backoff. Verify this on physical Thunderbolt hardware before release.
The default-on keep-awake setting inhibits idle sleep during active capture;
display sleep is a separate setting. Neither overrides macOS lid-close sleep.

Closed-lid operation is now specified as a planned native Sender subproject in
`docs/Closed-Lid-Power-Addon.md`. It requires explicit administrator
authorization, a narrowly scoped helper, temporary power-policy changes,
exact restoration, battery/thermal stop conditions, and physical Intel and
Apple silicon validation. No helper is implemented or installed yet. The
Sender project currently targets macOS 14.0, so Receiver Legacy macOS 11 work
does not establish compatibility for this feature.

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
5. Implement the closed-lid power add-on only after reviewing its privilege
   boundary and selecting the oldest supported Sender macOS; follow the
   design's battery, thermal, lifecycle, and physical-hardware gates.

The current development machine is Apple Silicon/macOS 15.7.7. It cannot
substitute for the Big Sur runtime gate. Keep the original upstream Receiver
installation and its preferences untouched.
