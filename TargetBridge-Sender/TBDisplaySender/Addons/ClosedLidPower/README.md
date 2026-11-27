# Closed-Lid Streaming Power

Internal native Sender add-on. This directory is the planned code boundary for
stream-session coordination, power/thermal/lid capability adapters, settings,
and tests. The feature is **not implemented**; it currently contains no
privileged helper and makes no system power-setting changes.

Read the design and safety requirements in
[`docs/Closed-Lid-Power-Addon.md`](../../../../docs/Closed-Lid-Power-Addon.md)
before adding code. Keep imported JSON addons outside this privilege boundary:
the manifest system must never load the helper or executable addon code.

Implementation must remain opt-in, request administrator authorization only
when needed, restrict the helper to a small allowlisted protocol, restore the
pre-session power policy, and stop streaming on battery/thermal safety events.
Do not claim Intel, Apple silicon, or legacy macOS support until the physical
matrix in the design document passes.
