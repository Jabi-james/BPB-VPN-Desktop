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

## Reference implementation reviewed

The supplied [Spider Firefox VPN repository](https://github.com/ppj30088-hash/firefox-spider-vpn) confirms that a Flutter-based client can ship desktop builds while keeping platform-specific networking behind a native core. Its public project description also separates the local proxy/system-proxy path from full-device TUN behavior. For BPB, the useful design lessons are to keep Proxy mode usable without administrator privileges, treat TUN as a separately permissioned subsystem, and make cleanup/recovery part of the service lifecycle. This is an architectural reference only; BPB will retain its own Xray-based protocol/configuration logic and will not copy unrelated account or service code.

## UI reference and desktop scanner decision

- The Android screenshot supplied by the project owner is the visual source of truth for the desktop home screen: BPB header/mode selector/tool icons; Connection, Mode, Exit Node and Chain selectors; prominent connection-status/power card; Duration/Ping/My IP/LAN IP; and separate download/upload rate and total-traffic cards. Preserve the dark palette, thin outlines, rounded cards and blue connect control. Adapt spacing and card width responsively for desktop rather than redesigning the visual language.
- PattN (patterniha/PattN) is documented by its own README as an Iranian-focused fork of v2rayN, not as a standalone scanner library. It is a C# desktop client with Windows/Linux/macOS build workflows and Xray/sing-box support. Its README does not document a reusable scanner API or a separate scanner module. Therefore do not copy PattN wholesale or claim that its scanner has been ported.
- PattN/v2rayN is still a useful behavioral reference for desktop node testing and core lifecycle. Before reusing any implementation, inspect the exact latency-test path, probe method, timeout/concurrency controls, result model and licensing in the source. Prefer implementing a BPB-native scanner adapter around the desktop Xray process and BPB's existing scan UI/model, so Android and desktop can use different probe backends while returning the same normalized results.
- Desktop scan backends must distinguish at least: TCP reachability/connect latency, protocol/handshake or core-based test latency, and real URL download/throughput tests. These metrics are not interchangeable. Do not label a TCP connect result as a successful VPN handshake or as real internet speed.

## Desktop scanner implementation (in progress)

- The desktop adapter now launches a small native `bpb_scanner` helper beside the Flutter executable and communicates over newline-delimited JSON on stdin/stdout.
- The helper calls the existing `xray.NewScannerBridge`, which in turn uses the existing shared `scanner.Scanner` algorithm and the same Xray outbound/HTTP probe implementation used by Android. It does not introduce a second scanning algorithm.
- Flutter's existing `ScannerChannel` retains Android MethodChannel/EventChannel behavior and routes Windows/Linux calls to the native helper. Scanner event/result JSON remains the same.
- The desktop CI workflow compiles the helper for Windows amd64 and Linux amd64 and includes it in the build artifact.
- Remaining verification: run the workflow, confirm the helper compiles against the pinned Xray/Go dependencies, and test real scans for VLESS, WARP, MASQUE H2/H3, pause/resume/stop, and event delivery on actual Windows/Linux hosts. Until those tests pass, desktop scanning is implemented but not yet release-verified.

## Product requirements: Android-equivalent UI and feature parity

These are release requirements, not optional redesign suggestions.

### UI parity
- Use the existing Flutter widgets and theme as the source of truth for Windows and Linux. Do not redesign the home screen or settings pages as a separate desktop product.
- Preserve the Android visual language: dark/light themes and accent colors, typography, icons, rounded cards, borders, spacing, chip/dropdown selectors, labels, field order, conditional visibility, animations, dialogs, and page navigation.
- Preserve the home-screen order: app bar/actions, ConnectionCard (Connection, Mode, Exit Node, Region/Chain as applicable), StatusCard, download/upload traffic cards, and conditional Worker usage card.
- Preserve the existing Settings page section order and every existing setting control. Desktop may use responsive sizing or a centered content width on wide monitors, but must not reorder, rename, omit, or regroup settings merely to look like a generic desktop client.
- Keep the same state model, validation, persistence, defaults, and config-generation behavior. A setting is not complete if it only appears in the UI.

### Functional parity
The desktop port must implement and test every Android-supported mode and its settings, including:
- Worker/VLESS and Serverless modes, including Domain Fronting and DNS variants.
- WARP and MASQUE (HTTP/2 and HTTP/3), including endpoint and protocol-specific options.
- Chain proxies and their supported protocols/transports, with the same selection and exit-node behavior.
- Psiphon and Tor, including region selection, bridges and Snowflake AMP where supported by the source version.
- Fragment/serverless packet and UDP obfuscation/noise settings, ECH-related controls where applicable, fingerprint/SNI/IP-version/transport options.
- DNS modes and custom servers (UDP, TCP, DoH, DoQ), Fake DNS, IPv6 preferences, routing strategy/rules, per-app routing where the OS supports an equivalent, and scanner settings.
- Cloudflare account/deployment management, import/export/config view, logs, connection state, traffic counters, ping and exit IP information, themes, reset/persistence, updates and other existing Settings pages.

### Platform implementation rule
Shared Dart UI and config-generation logic should remain shared. Android MethodChannel/VpnService code must not be called on Windows/Linux; replace only platform-specific execution with native desktop adapters. If a feature cannot be supported with equivalent behavior on a target OS, document the exact limitation and do not mark it as parity-complete.

### Acceptance gate
A feature checklist must compare every Android settings control and mode with its desktop implementation. Test generated configs and real traffic for each protocol/mode, connect/disconnect, error paths, DNS and route restoration, IPv4/IPv6, sleep/resume, network changes, and process crashes on actual Windows and Linux machines. CI compilation alone does not satisfy feature parity.
