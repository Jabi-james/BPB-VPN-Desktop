# Desktop port plan

This document tracks the desktop adaptation of BPB. The Android application remains the feature and UI reference; desktop support is added behind platform-specific services rather than by replacing the Flutter screens.

## Repository findings

- The application is a Flutter/Dart project. The existing screens, configuration models, Cloudflare deployment flow, connection profiles and much of the settings UI are reusable.
- The current VPN bridge in `lib/services/vpn_channel.dart` is an Android MethodChannel/EventChannel adapter (`bpb/core`, `bpb/state`, and scanner events). It is not a desktop implementation.
- Android VPN lifecycle and TUN setup live in `BpbVpnService.kt`; Android-only behavior also includes app allow/deny lists, notifications, Android file/share pickers, certificate installation and the browser dialer.
- `xray/xray.go` already contains the Xray controller, scanner bridge, DNS helper and ECH gateway in Go. `scripts/build_xray.sh` currently packages it as an Android AAR using gomobile.
- `psiphon/` and the Tor helper are built for Android by dedicated scripts. Their current Android packaging cannot be assumed to work on Windows or Linux.
- The dependency graph includes desktop-capable secure storage implementations, but every plugin and every Android-only action still needs a platform audit.

## Target architecture

1. Keep Flutter UI, profile/configuration models, Cloudflare API and shared config generation common.
2. Introduce a platform-neutral connection/service contract for lifecycle state, start/stop, logs, traffic counters, scanner events, DNS checks, file import/export and system proxy control.
3. Retain the existing Android channel adapter unchanged while adding Windows and Linux adapters.
4. Build Xray as native desktop executables (or a small supervised helper process) for each target OS. Keep config and log formats shared with Android.
5. Implement Proxy mode first: launch/stop Xray, expose its local SOCKS/HTTP inbound, and manage/restore the OS system proxy explicitly.
6. Implement TUN mode only after Proxy mode is stable: Windows requires a supported Wintun integration and elevated route/DNS management; Linux requires a TUN device and privileged route/DNS management. Both must restore routes and DNS on every shutdown/error path.
7. Port scanner, DNS checks, Tor and Psiphon independently. Do not mark a feature available until its desktop binary, lifecycle, logs and failure cleanup are tested.
8. Preserve the current UI and hide or disable only controls whose platform implementation is not yet available, with a clear explanation.

## Milestones and acceptance criteria

- **D0 — Build baseline:** Windows and Linux runners can generate, analyze, test and compile the Flutter shell in CI.
- **D1 — Platform abstraction:** Android remains behaviorally unchanged; desktop adapters expose a tested, explicit capability matrix.
- **D2 — Xray Proxy mode:** start/stop, logs, connection state and system proxy apply/restore work on both desktop OSes.
- **D3 — TUN mode:** IPv4/IPv6 routing, DNS, permissions/elevation, disconnect cleanup and network-change recovery pass real-machine tests.
- **D4 — Feature parity:** scanner, WARP/MASQUE, Tor, Psiphon, chain proxies, import/export and remaining settings are ported and tested individually.

## Safety and release gates

A successful Flutter build is not proof that a VPN works. Before a desktop release, test connect/disconnect, application restart, forced process termination, sleep/resume, network changes, DNS restoration, route restoration, IPv4/IPv6 leak behavior and failure recovery on real Windows and Linux machines. Do not publish a build as a working VPN until these tests pass.
