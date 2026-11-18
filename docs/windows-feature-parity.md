# Windows feature parity audit

Audit basis: Android Flutter UI/state, Android `MainActivity.kt` / `BpbVpnService.kt`, shared Dart services and the Windows Go host. A successful CI build proves compilation and the tests that exist; it does **not** prove runtime connectivity. Statuses below distinguish shared implementation from verified Windows runtime.

Legend:
- **Shared**: Dart/Xray logic is platform-independent and is included in the Windows build.
- **Windows implemented (build only)**: a Windows-specific path exists and compiles; real Windows runtime still needs a manual test.
- **Partial**: some pieces exist, but a platform-specific dependency or workflow remains missing.
- **Android only / not implemented**: Windows must not present this as working.

## Connection and core

| Android capability | Windows status | Notes |
|---|---|---|
| VLESS / Cloudflare Worker connection | Windows implemented (build only) | Shared Xray config; Go child process supports local proxy. |
| WARP / WireGuard registration and config | Shared; runtime unverified | Registrar and Xray outbound are shared; no Windows end-to-end test yet. |
| MASQUE registration and config (H2/H3) | Shared; runtime unverified | Registrar and Xray outbound are shared; network/QUIC runtime not tested. |
| Serverless connection | Shared; runtime unverified | Shared config builder and Xray core. |
| Proxy mode | Windows implemented (build only) | Local mixed inbound on 127.0.0.1:10880. |
| System Proxy mode | Windows implemented (build only) | Windows per-user proxy registry snapshot/restore. |
| Full-device VPN / TUN | Not implemented | Windows UI has a TUN choice but Go host rejects it. Must implement Wintun, elevation/service lifecycle, routes, DNS, cleanup. |
| Connection state / connect / disconnect / reconnect | Partial | Windows process bridge exists; no runtime smoke test, and no persisted service/state after app exit. |
| Traffic counters / ping / Xray logs | Partial | Xray traffic, delay and stdout/stderr log bridge exist; real runtime accuracy unverified. |
| Psiphon exit / region selection | Not implemented | Android uses Android native library/service; no Windows Psiphon binary/process adapter bundled. |
| Tor exit / bridges / region selection | Not implemented | Android Tor native service/binary integration is not ported to Windows. |
| Setup-wizard “Retry with Tor” | Not implemented | Uses Android SetupTor service; intentionally deferred rather than attempting a fragile port. |
| Browser Dialer | Not implemented | Depends on Android WebView/BrowserDialer integration. |

## Cloudflare account and deployment

| Android capability | Windows status | Notes |
|---|---|---|
| First-run question: existing Cloudflare account? | Shared UI | Flutter wizard is included. |
| Open Cloudflare sign-up page | Windows implemented (build only) | Windows default browser launcher added. |
| Create-token instructions and token page | Windows implemented (build only) | Uses the same browser launcher; actual browser handoff needs manual test. |
| Paste and validate API token; list accounts | Shared | Cloudflare API and validation are Dart code. |
| Deploy Workers and Pages | Shared | Deployment code and bundled worker are shared; must test against a real account. |
| Save/select/remove accounts and deployments | Shared | Shared state/storage code; Windows secure-storage plugin behavior still needs runtime verification. |
| Redeploy/update Worker and Pages, update ENV, custom domain, usage | Shared | Cloudflare API methods are shared; runtime/API permission checks remain. |
| Cloudflare API fallback via active tunnel | Shared; runtime unverified | Uses the local proxy when a connection is active. |
| ECH gateway fallback | Partial / not implemented on Windows | Gateway startup still calls Android MethodChannel. |
| Retry Cloudflare setup via Tor | Not implemented | Depends on the unported Windows Tor bootstrap. |

## Scanner and connection customization

| Android capability | Windows status | Notes |
|---|---|---|
| VLESS / WARP / MASQUE endpoint scanner | Windows implemented (build only) | Separate `bpb_scanner.exe` process protocol exists. |
| Scanner pause/resume/stop and progress | Windows implemented (build only) | Desktop process/event bridge exists. |
| Clean IPs and endpoint settings | Shared | Stored in common profile and used by common Xray config builder. |
| TLS SNI/fingerprint, IP version, transport, ports | Shared | Common configuration model/builder. |
| TCP fragmentation | Shared | Common configuration builder. |
| UDP obfuscation/noise presets and custom packets | Shared | Common configuration builder. |
| ECH settings | Partial | Config and client exist; ECH gateway startup is still Android-only. |
| Upstream proxy / custom CDN / Domain Fronting | Shared config; runtime unverified | Domain-fronting proxy-mode test remains skipped; do not mark verified. |
| Proxy-chain import and chain configuration | Shared config; file import/export partial | Core parsing/config is shared; any platform file-picker flow must be exercised. |
| Routing presets/custom domain and IP rules | Shared config | Windows proxy-mode runtime routing behavior not yet tested. |
| DNS modes / custom DNS / Fake DNS / anti-sanction DNS | Shared config; DNS tester Android only | The DNS settings screen can configure common Xray DNS, but the explicit DNS-test native method is Android-only. |

## Other settings and app utilities

| Android capability | Windows status | Notes |
|---|---|---|
| Per-app VPN routing / installed-app picker | Android only | Windows equivalent is not implemented; current Android package-name UI must be hidden or replaced on Windows. |
| MTU / append HTTP proxy | Partial | Android VPN-specific; Windows TUN not available. |
| LAN proxy authentication | Shared model/config; runtime unverified | Must test Windows local proxy auth and LAN exposure. |
| Logs | Partial | Windows only exposes Xray child stdout/stderr; Tor/Psiphon logs do not exist. |
| View generated Xray config | Shared | Common config builder. |
| Import/export BPB settings JSON | Windows implemented (build only) | Native Windows file dialogs added; file encoding and cancellation need runtime test. |
| Share/export file | Partial | Windows maps share sheet to Save As; no Android-style share sheet. |
| Update geoip/geosite assets | Not implemented | Save operation still calls Android MethodChannel. |
| MITM CA generate/save/install | Partial / Android only | Certificate generation is shared Dart; native save/install and Windows trust-store flow are not implemented. |
| App/core version display | Partial | Xray version from Go host; Psiphon/Tor versions unavailable. Windows app version currently uses a compile-time fallback. |
| App self-update | Not implemented | Existing updater is Android APK-oriented; Windows release/update channel is not defined. |
| Themes, colors, reset settings, persistence | Shared; Windows runtime unverified | Flutter settings and profile model are shared; secure storage and persistence need runtime check. |
| Get Tor bridges from Tor Project | Shared | Bridge fetching/parsing is Dart HTTP; bridge installation only configures settings, not a Windows Tor runtime. |
| Quick Settings tile / Android notifications / Android VPN permission | Android only | No Windows counterpart planned as-is. |

## Windows work order

1. Finish Windows platform bridges and remove/hide Android-only controls that currently fail when clicked.
2. Test Cloudflare onboarding and actual Worker + Pages deployment with a test Cloudflare account.
3. Test WARP and MASQUE registration, persistence, config generation, and proxy-mode traffic.
4. Test scanner, import/export, geo assets, ECH fallback, DNS tools and settings persistence.
5. Implement and test Wintun/TUN.
6. Consider Tor/Psiphon only after Windows binaries, process lifecycle, bridge/bootstrap, logs and licensing are handled. Tor setup retry is deferred for now because it is not a small UI-only port.

**No feature is called runtime-verified until it has been exercised on Windows.**
