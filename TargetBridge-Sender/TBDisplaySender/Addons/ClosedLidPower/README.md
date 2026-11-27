# Closed-Lid Streaming Power

Internal native Sender add-on. This directory contains the pure safety policy,
public battery/thermal observation layer, bounded session lease, private
journal, and injected-settings coordinator. The feature is **not
user-operational**: it has no privileged daemon/XPC transport, production
power-setting adapter, lifecycle integration, settings UI, or lid detection.
The coordinator tests do not execute `pmset` and make no system power-setting
changes.

Read the design and safety requirements in
[`docs/Closed-Lid-Power-Addon.md`](../../../../docs/Closed-Lid-Power-Addon.md)
before adding code. Keep imported JSON addons outside this privilege boundary:
the manifest system must never load the helper or executable addon code.

Future implementation must remain opt-in, request administrator authorization only
when needed, restrict the helper to a small allowlisted protocol, restore the
pre-session power policy, and stop streaming on battery/thermal safety events.
Do not claim Intel, Apple silicon, or legacy macOS support until the physical
matrix in the design document passes.
