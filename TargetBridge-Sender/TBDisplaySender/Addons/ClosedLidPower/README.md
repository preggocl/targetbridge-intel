# Closed-Lid Streaming Power

Internal native Sender add-on. This directory is the code boundary for the
pure safety policy and public battery/thermal observation layer. The feature is
**not user-operational**: it has no privileged helper, lifecycle integration,
settings UI, or lid detection, and makes no system power-setting changes.

Read the design and safety requirements in
[`docs/Closed-Lid-Power-Addon.md`](../../../../docs/Closed-Lid-Power-Addon.md)
before adding code. Keep imported JSON addons outside this privilege boundary:
the manifest system must never load the helper or executable addon code.

Future implementation must remain opt-in, request administrator authorization only
when needed, restrict the helper to a small allowlisted protocol, restore the
pre-session power policy, and stop streaming on battery/thermal safety events.
Do not claim Intel, Apple silicon, or legacy macOS support until the physical
matrix in the design document passes.
