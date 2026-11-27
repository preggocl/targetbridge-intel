# Project state

Updated: 2026-11-26

Active review branch: `receiver-legacy-upstream-sync`, based on the fork's
`intel-sender` branch. The stable Intel Sender remains `3.3.0-intel.1`; the
experimental Receiver bundle also defaults to this fork version string and
uses a separate legacy bundle identity. This
Receiver work is experimental and is not included in the Sender release.

The iCloud checkout still has local branch `receiver-legacy-software-decode`
and damaged Git ancestry (its parent commit `0d98e9d` is missing locally). Its
source files have been synced to this review branch, but its history was not
rewritten. Continue commits and GitHub updates from the clean review checkout.

## Recovered and carried forward

- Intel Sender configuration and packaging remain isolated from upstream.
- Full HD 30/60 Sender profiles were previously verified against a Receiver
  Legacy prototype on an iMac 2011 running Big Sur 11.7.10.
- Receiver physical/logical display reporting and software decode fallback
  were submitted upstream as PRs [#169](https://github.com/swellweb/targetBridge/pull/169)
  and [#170](https://github.com/swellweb/targetBridge/pull/170); both merged
  into `maint-3.5` on 2026-08-18.
- The recovered Receiver Legacy work reports actual panel geometry, keeps
  Retina logical dimensions, converts software-decoded frames to NV12, uses a
  distinct About panel, identifies the host computer, and adds Spanish UI.
- The Receiver keeps the 4 MiB TCP receive buffer used by upstream 3.6.2.
- This branch adopts the HEVC hardware-capability guard from upstream PR
  [#232](https://github.com/swellweb/targetBridge/pull/232), merged to
  `maint-3.6` on 2026-11-12. VideoToolbox must report hardware HEVC support
  before the Receiver advertises it.

## Current upstream status

- Latest upstream release checked: `v3.6.2` (2026-11-15).
- Upstream issue [#167](https://github.com/swellweb/targetBridge/issues/167)
  remains open/planned: bundled dylibs in the official x86_64 Receiver can
  import `_CVBufferCopyAttachments`, which Big Sur does not provide.
- Upstream issue [#223](https://github.com/swellweb/targetBridge/issues/223)
  remains open: the official Receiver release line requires macOS 14 on Intel
  and macOS 15 on Apple Silicon; Ventura support is still requested.
- Upstream PR [#243](https://github.com/swellweb/targetBridge/pull/243) is open
  against `main`; its frame ACK / sender credit-window protocol may help 5K
  receiver backpressure, but is not yet a released, adopted change.

## Compatibility boundary

The Receiver source targets macOS 11 and can be compiled for the host's native
`x86_64` or `arm64` architecture when matching FFmpeg/SDL dependencies exist.
The legacy package path now uses a unique app name and bundle identifier and
audits bundled Mach-O architecture, deployment target, and the known Big Sur
CoreVideo import. Homebrew bottles may fail this audit; a passing source build
is not evidence of a working Big Sur package.

The development host is Apple Silicon on macOS 15.7.7. No Intel/macOS 11 host
was available in this run, so Big Sur launch, decode, reconnect, and sustained
streaming remain unverified. Do not publish or install this Receiver as a
replacement for the upstream app until its dependencies are rebuilt for legacy
macOS and the physical acceptance run passes.
