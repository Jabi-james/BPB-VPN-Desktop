// ignore_for_file: use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../models/theme_color.dart';
import '../services/scanner_channel.dart';
import '../services/updates.dart';
import '../services/cloudflare_api.dart';
import '../services/vpn_channel.dart';
import '../services/xray_config.dart';
import '../state/app_state.dart';
import 'cf_accounts_page.dart';
import 'chain_proxies_page.dart';
import 'cloudflare_scanner_page.dart';
import 'dns_page.dart';
import 'donation_page.dart';
import 'fragments_page.dart';
import 'license_page.dart';
import 'noises_page.dart';
import 'per_app_page.dart';
import 'prefs.dart';
import 'routing_page.dart';
import 'app_toast.dart';
import 'tor_bridges_page.dart';
import 'tor_custom_bridges_pref.dart';
import 'ssh_settings_page.dart';
import 'statistics_page.dart';
import 'hover_animated_icon.dart';
import 'chip_menu.dart';

class _BrowserPrivacyTile extends StatelessWidget {
  const _BrowserPrivacyTile();

  Future<void> _showPrompt(BuildContext context) async {
    final trust = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Symbols.language_rounded, size: 34),
        title: const Text('Browser Privacy'),
        content: const Text(
          'To reduce mismatches between your VPN exit IP and the information '
          'websites receive from your browser, install GeoSpoof. It can align '
          'your browser time zone and reported language with your VPN location.\n\n'
          'GeoSpoof is an independent third-party extension, not part of BPB. '
          'You can review its details and choose the store for your browser '
          'on its official website. Installation and setup are always your choice.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE05252)),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hell, No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A36A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('I Trust You'),
          ),
        ],
      ),
    );
    if (trust == true && context.mounted) {
      await VpnChannel.openUrl('https://geospoof.com/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.language_rounded),
      title: const Text('Browser Privacy'),
      subtitle: const Text('Align browser language and time zone with your VPN IP. You can also improve browser privacy by adding geo spoof add-on to your browser.'),
      trailing: const Icon(Symbols.open_in_new_rounded, size: 20),
      onTap: () => _showPrompt(context),
    );
  }
}

class _BrowserSecurityTestTile extends StatelessWidget {
  const _BrowserSecurityTestTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.fact_check_rounded),
      title: const Text('Security Test'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Check your public IP and browser leak indicators after applying your settings.',
          ),
          const SizedBox(height: 4),
          InkWell(

            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => VpnChannel.openUrl('https://browserleaks.com/ip'),
            child: const Text(
              'https://browserleaks.com/ip',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      trailing: const Icon(Symbols.open_in_new_rounded, size: 20),
      onTap: () => VpnChannel.openUrl('https://browserleaks.com/ip'),
    );
  }
}

class _WebRtcProtectionPref extends StatelessWidget {
  const _WebRtcProtectionPref();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = state.readBool('general.webRtcLeakProtection');
    return SwitchListTile(
      secondary: const Icon(Symbols.security_rounded),
      title: const Text('WebRTC Leak Protection'),
      subtitle: const Text('Chrome and Edge · Restart the browser to apply policy changes'),
      value: enabled,
      onChanged: (value) async {
        final verified = await state.setWebRtcLeakProtection(value);
        if (!context.mounted) return;
        AppToast.showSnackBar(context, SnackBar(
          content: Text(!verified
              ? 'WebRTC Leak Protection could not be verified. Check Windows browser policies.'
              : value
                  ? 'WebRTC Leak Protection Enabled. You are Secure.'
                  : 'WebRTC Leak Protection Disabled. You are not Secure.'),
          duration: const Duration(seconds: 4),
        ));
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _sshDirty = false;
  bool _sshSelected = false;
  VoidCallback? _saveSsh;

  void _onSshSaveStateChanged(VoidCallback save, bool dirty) {
    if (!mounted) return;
    setState(() {
      _saveSsh = save;
      _sshDirty = dirty;
    });
  }

  static const fingerprints = {
    'chrome': 'Chrome',
    'firefox': 'Firefox',
    'safari': 'Safari',
    'ios': 'iOS',
    'android': 'Android',
    'edge': 'Edge',
    '360': '360',
    'qq': 'QQ',
    'random': 'Random',
    'randomized': 'Randomized',
    'unsafe': 'Unsafe',
  };

  static const routingStrategy = {'AsIs': 'Speed', 'IPIfNonMatch': 'Accuracy'};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final d = state.device;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_sshSelected)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF238636), foregroundColor: Colors.white, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 34)),
              onPressed: _sshDirty ? _saveSsh : null,
              icon: const Icon(Symbols.save_rounded, size: 17),
              label: const Text('Save'),
            ),
          IconButton(
            tooltip: 'Reset settings',
            icon: const Icon(Symbols.settings_backup_restore_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset settings?'),
                  content: const Text(
                    'Proxy settings return to their defaults. VLESS Clean IPs, WARP and MASQUE '
                    'endpoints and Tor custom bridges are preserved.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true) state.resetSettings();
            },
          ),
        ],
      ),
      body: _SettingsSections(
        onSectionChanged: (isSsh) => setState(() => _sshSelected = isSsh),
        children: [
          const SectionHeader('Global'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.link_rounded),
                title: const Text('Chain proxies'),
                subtitle: Text(switch (p.chains.length) {
                  0 => 'None added',
                  1 => '1 config',
                  final n => '$n configs',
                }),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const ChainProxiesPage())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const TextPref(
                'general.localDns',
                'Local DNS',
                icon: Symbols.home_rounded,
                hint: 'IP, tcp://IP or localhost',
                help:
                    'Resolves outbound domains and bypass routing rules. '
                    'It can be an UDP DNS, TCP DNS or "localhost" to use system DNS.',
                validator: validateLocalDns,
              ),
              const TextPref(
                'general.antiSanctionDns',
                'Anti Sanction DNS',
                icon: Symbols.account_circle_off_rounded,
                help:
                    'Resolves the sanctioned domains so they work over a direct connection. '
                    'This only applies to Serverless, WARP and MASQUE connections when Exit node is set to Default. '
                    'It can be UDP DNS, TCP DNS, DoQ or DoH.',
                validator: validateSanctionDns,
              ),
              const SwitchPref(
                'general.enableFakeDns',
                'Fake DNS',
                icon: Symbols.dns_rounded,
                subtitle: 'Faster but may not work with some apps',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const SwitchPref(
                'general.enableIpv6',
                'IPv6 connection',
                icon: Symbols.counter_6_rounded,
                subtitle: 'Enable it based on your ISP',
              ),
              const SwitchPref(
                'general.preferIpv6',
                'Prefer IPv6',
                icon: Symbols.counter_6_rounded,
                subtitle: 'Enable it based on your ISP',
              ),
              const SwitchPref(
                'device.lanSharing.enabled',
                'Share over LAN',
                icon: Symbols.lan_rounded,
                subtitle: 'Share a Socks, HTTP proxy on port 10880',
              ),
              if (d.lanSharing) ...[
                const TextPref(
                  'device.lanSharing.username',
                  'Proxy username',
                  icon: Symbols.account_circle_rounded,
                  hint: 'Optional',
                  help:
                      'Recommended to set a username and password to only allow trusted devices. '
                      'Leave both empty for no login.',
                  allowEmpty: true,
                  validator: validateProxyUsername,
                ),
                const TextPref(
                  'device.lanSharing.password',
                  'Proxy password',
                  icon: Symbols.password_rounded,
                  hint: 'Optional',
                  help: 'Used only together with a username.',
                  allowEmpty: true,
                  secret: true,
                  validator: validateProxyPassword,
                ),
              ],
              const IntPref(
                'device.mtu',
                'VPN MTU',
                icon: Symbols.straighten_rounded,
                min: 1280,
                max: 9000,
              ),
              FutureBuilder<bool>(
                future: VpnChannel.supportsAppendHttpProxy,
                builder: (context, snapshot) => snapshot.data == true
                    ? const SwitchPref(
                        'device.appendHttpProxy',
                        'Add HTTP proxy to VPN',
                        icon: Symbols.http_rounded,
                        subtitle:
                            'Use proxy directly for supported apps, browsers',
                      )
                    : const SizedBox.shrink(),
              ),
              if (defaultTargetPlatform != TargetPlatform.windows)
                ListTile(
                  leading: const Icon(Symbols.apps_rounded),
                  title: const Text('Per-app proxy'),
                  subtitle: Text(switch (d.perAppMode) {
                    PerAppMode.include =>
                      'Proxy selected apps (${d.perAppApps.length})',
                    PerAppMode.exclude =>
                      'Exclude selected apps (${d.perAppApps.length})',
                    PerAppMode.off => 'Proxy all apps',
                  }),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const PerAppPage()))),
                ),
            ],
          ),

          const ConnectionGroupHeader(),
          const CoreGroupHeader('BPB Core'),
          const SectionHeader('Worker VLESS'),
          SettingsCard(
            children: [
              const _DeploymentTile(),
              const TextPref(
                'vless.remoteDns.server',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                help: 'Resolves foreign domains for routing and can be a DoH or TCP DNS.',
                validator: validateRemoteDns,
              ),
              const MultiIntPref(
                'vless.ports',
                'Ports',
                XrayConfigBuilder.httpsPorts,
                icon: Symbols.numbers_rounded,
              ),
              const ChoicePref(
                'vless.tlsFingerprint',
                'TLS Fingerprint',
                fingerprints,
                icon: Symbols.fingerprint_rounded,
              ),
              if (state.worker != null) const _CustomDomainTile(),
              const SwitchPref(
                'vless.customCdn.enabled',
                'Custom CDN',
                icon: Symbols.cloud_rounded,
                subtitle: 'Enable for domain fronting',
              ),
              if (p.vless.customCdn.enabled) ...const [
                ListPref(
                  'vless.customCdn.addresses',
                  'Custom CDN addresses',
                  icon: Symbols.list_arrow_rounded,
                  hint: 'speedtest.net\n151.101.66.219\n2a04:4e42::731',
                  help: 'Used with the custom CDN host and SNI together.',
                  itemValidator: validateHost,
                ),
                TextPref(
                  'vless.customCdn.host',
                  'Custom CDN host',
                  icon: Symbols.host_rounded,
                  allowEmpty: true,
                  validator: validateHost,
                ),
                TextPref(
                  'vless.customCdn.sni',
                  'Custom CDN SNI',
                  icon: Symbols.host_rounded,
                  allowEmpty: true,
                  validator: validateHost,
                ),
              ],
              const SwitchPref(
                'vless.ech.enabled',
                'TLS ECH',
                icon: Symbols.encrypted_rounded,
                subtitle: 'Hide the real SNI',
              ),
              if (p.vless.ech.enabled)
                const TextPref(
                  'vless.ech.dns',
                  'ECH DNS server',
                  icon: Symbols.dns_rounded,
                  hint: '8.8.8.8 or https://8.8.8.8/dns-query',
                  help:
                      'DNS server the ECH config is fetched from, an IP or a DoH with an IP host. '
                      'DNS server should be reachable from your network and not blocked by your ISP.',
                  validator: validateEchDns,
                ),
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('TCP Fragments'),
                subtitle: Text(_fragmentSummary(p.fragments)),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage())),
                ),
              ),
              TextPref(
                'vless.upstreamProxy',
                'Upstream TCP Proxy',
                icon: Symbols.swap_vert_rounded,
                hint: 'host:port',
                help: 'Setup a upstream TCP proxy like SNI spoofing.',
                allowEmpty: true,
                validator: validateEndpoint,
              ),
              const ListPref(
                'vless.proxyIps',
                'Proxy IPs or domains',
                icon: Symbols.list_arrow_rounded,
                help:
                    'Used by the worker to connect to Cloudflare-hosted sites. Leave empty for its '
                    'built-in default. It is highly recommended to leave it empty, because Proxy IPs expire frequently '
                    'while the default IPs update regularly.',
                hint: 'proxyip.example.com\n94.1.2.3\n95.4.5.6:8443\n[2001:db8::1]\n[2001:db8::2]:8443',
                allowEmpty: true,
                itemValidator: validateHostPort,
              ),
              const SwitchPref(
                'vless.enableTcpFastOpen',
                'TCP Fast Open',
                icon: Symbols.bolt_rounded,
                subtitle: 'Enable with caution',
              ),
              const TextPref(
                'vless.fallbackUrl',
                'Fallback website',
                icon: Symbols.eyeglasses_rounded,
                hint: 'https://example.com',
                help: 'Non-VPN visitors to the worker see this website instead of a 404. ',
                allowEmpty: true,
                validator: validateHttpsUrl,
              ),
              const IntPref(
                'vless.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'vless.cleanIps',
                'Clean IPs or domains',
                icon: Symbols.list_arrow_rounded,
                hint: 'www.speedtest.net\n104.16.1.1\n2606:4700::6810:84e5',
                help:
                    'Set clean Cloudflare IPs or domains to boost connection speed. '
                    'Include at least one IPv4 address.',
                itemValidator: validateHost,
                listValidator: validateCleanIps,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan clean IPs'),
                subtitle: const Text('Find fast IPs for VLESS'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const CloudflareScannerPage(
                      protocol: ScanProtocol.vless,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _CloudflareAccountsTile()]),

          const SectionHeader('MASQUE'),
          SettingsCard(
            children: [
              const TextPref(
                'masque.remoteDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1',
                help: 'It can be an UDP DNS, TCP DNS or DoH.',
                validator: validateTunnelDns,
              ),
              const TextPref(
                'masque.sni',
                'SNI',
                icon: Symbols.host_rounded,
                hint: MasqueSettings.defaultSni,
                validator: validateHost,
              ),
              const ChoicePref('masque.transport', 'Transport', {
                'h2': 'H2 · TCP',
                'h3': 'H3 · QUIC',
              }, icon: Symbols.swap_horiz_rounded),
              if (p.masque.transport == 'h2')
                const ChoicePref(
                  'masque.tlsFingerprint',
                  'H2 Fingerprint',
                  fingerprints,
                  icon: Symbols.fingerprint_rounded,
                ),
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('H2 TCP Fragments'),
                subtitle: Text(_fragmentSummary(p.masque.fragments)),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage(section: 'masque.')),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('H3 UDP Obfuscation'),
                subtitle: Text(
                  '${p.masque.udpNoises.length} noise${p.masque.udpNoises.length == 1 ? '' : 's'}',
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage(section: 'masque.')),
                  ),
                ),
              ),
              const IntPref(
                'masque.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'masque.endpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.198.1:443\n[2606:4700:103::1]:443',
                help: 'Each endpoint in a new line. Include at least two IPv4 endpoints.',
                itemValidator: validateEndpoint,
                listValidator: validateIpv4Endpoints,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan endpoints'),
                subtitle: const Text('Find fast IPs for MASQUE'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  CloudflareScannerPage(
                      protocol: p.masque.transport == 'h3'
                          ? ScanProtocol.masqueH3
                          : ScanProtocol.masqueH2,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _MasqueAccountTile()]),

          const SectionHeader('WARP'),
          SettingsCard(
            children: [
              const TextPref(
                'warp.remoteDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1',
                help: 'It can be a UDP DNS, TCP DNS or DoH.',
                validator: validateTunnelDns,
              ),
              const SwitchPref(
                'warp.enableReservedBytes',
                'Reserved bytes',
                icon: Symbols.memory_rounded,
                subtitle: 'May help on some ISPs',
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('UDP Obfuscation'),
                subtitle: Text(
                  '${p.udpNoises.length} noise${p.udpNoises.length == 1 ? '' : 's'}',
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage()))),
              ),
              const IntPref(
                'warp.keepAlive',
                'Keep alive interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Keep WARP connection alive. Set 0 to disable.',
                min: 0,
                max: 25,
                suffix: ' s',
              ),
              const IntPref(
                'warp.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'warp.endpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: 'engage.cloudflareclient.com:2408\n162.159.192.1:2408\n[2606:4700:d0::a29f:c001]:2408',
                help: 'Cloudflare Warp endpoints. Include at least two IPv4 endpoints.',
                itemValidator: validateEndpoint,
                listValidator: validateIpv4Endpoints,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan endpoints'),
                subtitle: const Text('Find fast IPs for WARP'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const CloudflareScannerPage(
                      protocol: ScanProtocol.warp,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _WarpAccountTile()]),

          const CoreGroupHeader('Aether Core'),
          const SectionHeader('MASQUE'),
          SettingsCard(
            children: [
              const TextPref(
                'device.aether.masqueDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1,1.0.0.1',
                help: 'DNS resolvers used inside the Aether MASQUE tunnel. Separate multiple resolvers with commas.',
              ),
              const TextPref(
                'device.aether.masqueSni',
                'MASQUE SNI',
                icon: Symbols.host_rounded,
                hint: 'www.cloudflare.com',
                validator: validateHost,
              ),
              const ChoicePref('device.aether.masqueTransport', 'Transport', {
                'h2': 'H2 · TCP',
                'h3': 'H3 · QUIC',
              }, icon: Symbols.swap_horiz_rounded),
              const ListTile(
                leading: Icon(Symbols.fingerprint_rounded),
                title: Text('TLS Fingerprint'),
                subtitle: Text('Chrome · Aether uses its built-in BoringSSL fingerprint'),
              ),
              if (d.aetherMasqueFragment) ...const [
                TextPref(
                  'device.aether.masqueFragmentSize',
                  'Fragment size (bytes)',
                  icon: Symbols.straighten_rounded,
                  hint: '8-16',
                ),
                TextPref(
                  'device.aether.masqueFragmentDelay',
                  'Fragment delay (ms)',
                  icon: Symbols.timer_rounded,
                  hint: '2-10',
                ),
              ],
              const ChoicePref('device.aether.masqueNoize', 'Obfuscation profile', {
                'off': 'Off',
                'firewall': 'Firewall',
                'gfw': 'GFW',
              }, icon: Symbols.shield_rounded),
              if (d.aetherMasqueTransport == 'h3')
                const SwitchPref(
                  'device.aether.quicV2',
                  'QUIC v2 opener',
                  icon: Symbols.network_check_rounded,
                  subtitle: 'Keep enabled unless the network blocks it',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              const ListPref(
                'device.aether.masqueEndpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.198.2:443\\n162.159.199.2:443',
                help: 'Up to ten MASQUE endpoints verified by Aether. The fastest is used first.',
                itemValidator: validateEndpoint,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scanner settings'),
                subtitle: const Text('Choose scan mode and scan MASQUE endpoints'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const AetherScannerPage(protocol: 'masque'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(children: [const _AetherMasqueAccountTile()]),

          const SectionHeader('WARP'),
          SettingsCard(
            children: [
              const TextPref(
                'device.aether.wgDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1,1.0.0.1',
                help: 'DNS resolvers used inside the Aether WireGuard tunnel. Separate multiple resolvers with commas.',
              ),
              const ChoicePref('device.aether.wgNoize', 'Obfuscation profile', {
                'off': 'Off',
                'light': 'Light',
                'balanced': 'Balanced',
                'aggressive': 'Aggressive',
              }, icon: Symbols.shield_rounded),
              const IntPref(
                'device.aether.wgKeepalive',
                'Keep alive interval (s)',
                icon: Symbols.timer_rounded,
                min: 1,
                max: 120,
                suffix: ' s',
              ),
              const ListTile(
                leading: Icon(Symbols.numbers_rounded),
                title: Text('Reserved bytes'),
                subtitle: Text('Not exposed by Aether’s WireGuard implementation'),
              ),
              const SwitchPref(
                'device.aether.wgNoProfileRetry',
                'Disable profile retry',
                icon: Symbols.repeat_rounded,
                subtitle: 'Do not retry other obfuscation profiles during scan',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              const ListPref(
                'device.aether.wgEndpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.192.1:2408\\n162.159.193.1:2408',
                help: 'Up to ten WireGuard endpoints verified by Aether. The fastest is used first.',
                itemValidator: validateEndpoint,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scanner settings'),
                subtitle: const Text('Choose scan mode and scan WireGuard endpoints'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const AetherScannerPage(protocol: 'wg'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(children: [const _AetherWgAccountTile()]),
          const CoreGroupEnd(),

          const SectionHeader('SSH'),
          SshSettingsPage(embedded: true, onSaveStateChanged: _onSshSaveStateChanged),

          const SectionHeader('Tor'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.download_rounded),
                title: const Text('Get bridges'),
                subtitle: const Text('Fresh bridges from Tor'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const TorBridgesPage())),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.list_alt_rounded),
                title: const Text('Custom bridges'),
                subtitle: Text(p.tor.bridges.isEmpty
                    ? 'No bridges added'
                    : '${p.tor.bridges.length} saved bridge(s)'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _CompactSettingsTheme(
                      child: const TorCustomBridgesPref(),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SectionHeader('Serverless'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.dns_rounded),
                title: const Text('DNS servers'),
                subtitle: Text('DNS mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const DnsPage()))),
              ),
              const SwitchPref(
                'serverless.dnsSettings.fakeSniServers',
                'Fake SNI servers',
                icon: Symbols.encrypted_rounded,
                subtitle: 'DNS mode',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('TCP Fragments'),
                subtitle: Text('Packet mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage(section: 'serverless.')),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('UDP Obfuscation'),
                subtitle: Text('Packet mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage(section: 'serverless.')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              if (defaultTargetPlatform == TargetPlatform.windows)
                const _WindowsMitmCaTile()
              else
                const _MitmCaTile(),
            ],
          ),

          const ConnectionGroupEnd(),
          const SectionHeader('Browser Security'),
          const SettingsCard(
            children: [
              _WebRtcProtectionPref(),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsCard(
            children: [
              _BrowserPrivacyTile(),
            ],
          ),
          const SizedBox(height: 16),
          const SettingsCard(
            children: [
              _BrowserSecurityTestTile(),
            ],
          ),

          const SectionHeader('Routing'),
          SettingsCard(
            children: [
              ChoicePref(
                'routing.domainStrategy',
                'Strategy',
                routingStrategy,
                icon: Symbols.discover_tune_rounded,
              ),
              _RulesTile(
                title: 'Bypass rules',
                icon: Symbols.alt_route_rounded,
                group: 'bypass',
                labels: RoutingPage.bypassLabels,
                domainHint: 'example.ir',
                ipHint:
                    '10.0.0.1/24\n192.178.24.110\n2a00:1450:400e:808::200e/128',
              ),
              _RulesTile(
                title: 'Sanction rules',
                icon: Symbols.alt_route_rounded,
                group: 'sanctionBypass',
                labels: RoutingPage.sanctionBypassLabels,
                domainHint: 'gemini.google.com',
                help: RoutingPage.sanctionHelp,
              ),
              _RulesTile(
                title: 'Block rules',
                icon: Symbols.do_not_disturb_on_rounded,
                group: 'block',
                labels: RoutingPage.blockLabels,
                domainHint: 'ads.example.com',
                ipHint: '10.10.34.34/24\n2001:4188:2:600:10:10:34:34/112',
              ),
              const _GeoAssetsTile(),
            ],
          ),

          const SectionHeader('Statistics'),
          const StatisticsPanel(),
          const SizedBox(height: 16),

          const SectionHeader('Import / Export'),
          const SettingsCard(
            children: [
              _ExportSettingsTile(download: false),
              _ImportSettingsTile(),
              _ExportSettingsTile(download: true),
            ],
          ),

          const SectionHeader('Appearance'),

          const SectionHeader('About'),
          SettingsCard(
            children: [
              const _VersionTile(),
              const _UpdateTile(),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.code_rounded, color: Color(0xFF3B82F6)),
                title: const Text('BPB Source Code'),
                subtitle: const Text('github.com/bia-pain-bache/BPB-VPN'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20, color: Color(0xFF3B82F6)),
                onTap: () => VpnChannel.openUrl('https://github.com/bia-pain-bache/BPB-VPN'),
              ),
              ListTile(
                leading: const Icon(Icons.desktop_windows_rounded, color: Color(0xFF1685D8)),
                title: const Text('Desktop App Repo'),
                subtitle: const Text('github.com/NottDevv/BPB-VPN-Desktop'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20, color: Color(0xFF1685D8)),
                onTap: () => VpnChannel.openUrl('https://github.com/NottDevv/BPB-VPN-Desktop'),
              ),
              ListTile(
                leading: const Icon(Symbols.code_rounded, color: Color(0xFF8B5CF6)),
                title: const Text('Desktop App Source Code'),
                subtitle: const Text('github.com/NottDevv/BPB-VPN-Desktop-Dev'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20, color: Color(0xFF8B5CF6)),
                onTap: () => VpnChannel.openUrl('https://github.com/NottDevv/BPB-VPN-Desktop-Dev'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.copyright_rounded, color: Color(0xFF8B5CF6)),
                title: const Text('Open Source License'),
                subtitle: const Text('GNU GPL v3.0'),
                trailing: const Icon(Symbols.chevron_right_rounded, color: Color(0xFF8B5CF6)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const LicensePageView())),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.favorite_rounded, color: Color(0xFF16A36A)),
                title: const Text('Donation (NotDev)'),
                subtitle: const Text('Support NotDev'),
                trailing: const Icon(Symbols.chevron_right_rounded, color: Color(0xFF16A36A)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _CompactSettingsTheme(
                      child: const DonationPage(
                        title: 'Donation (NotDev)',
                        trc20Address: 'TNMUWffS9VPhBsNTaTcHNHV6eErbRjVL51',
                        bep20Address: '0x1Ef196A6949A53e6Cc73e2A3c406fF3e312084A0',
                        tonAddress: 'UQAu1EXaAjVFFi60K4O8lIudr01xAruRPydqx0DsuxvXu2Oe',
                      ),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.favorite_rounded, color: Color(0xFFE0528A)),
                title: const Text('Donation (BPB)'),
                subtitle: const Text('Keep this project alive'),
                trailing: const Icon(Symbols.chevron_right_rounded, color: Color(0xFFE0528A)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _CompactSettingsTheme(
                      child: const DonationPage(title: 'Donation (BPB)'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AetherScannerPage extends StatefulWidget {
  final String protocol;
  const AetherScannerPage({required this.protocol, super.key});

  @override
  State<AetherScannerPage> createState() => _AetherScannerPageState();
}

class _AetherScannerPageState extends State<AetherScannerPage> {
  bool _loading = false;
  bool _stopping = false;
  bool _paused = false;
  bool _hasScanned = false;
  int _outputCount = 10;
  String? _error;
  List<AetherScanResult> _results = const [];
  final Set<String> _selectedEndpoints = {};

  Future<void> _scan() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _hasScanned = true;
      _error = null;
      _results = const [];
      _selectedEndpoints.clear();
      _paused = false;
    });
    try {
      final results = await AppScope.of(context).scanAetherEndpoints(
        widget.protocol,
        outputCount: _outputCount,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _selectedEndpoints
          ..clear()
          ..addAll(results.map((result) => result.endpoint));
        _loading = false;
        _stopping = false;
        _paused = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _stopping = false;
        _paused = false;
      });
    }
  }

  Future<void> _togglePause() async {
    final wasPaused = _paused;
    try {
      if (wasPaused) {
        await VpnChannel.resumeAetherEndpointScan();
      } else {
        await VpnChannel.pauseAetherEndpointScan();
      }
      if (mounted) setState(() => _paused = !wasPaused);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _importSelected(AppState state) {
    final selected = _results
        .where((result) => _selectedEndpoints.contains(result.endpoint))
        .map((result) => result.endpoint)
        .toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Select at least one endpoint to import.');
      return;
    }
    final added = state.installAetherScannedEndpoints(widget.protocol, selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
        added == 0
            ? 'These endpoints are already installed'
            : 'Imported $added endpoint(s)',
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final protocolName = widget.protocol == 'masque' ? 'MASQUE' : 'WireGuard';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Aether $protocolName Scanner')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose how Aether scans the network. These are Aether-native options, not BPB scanner settings.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: const ChoicePref('device.aether.scanMode', 'Scan mode', {
                      'turbo': 'Turbo',
                      'balanced': 'Balanced',
                      'thorough': 'Thorough',
                      'stealth': 'Stealth',
                      'ironclad': 'Ironclad',
                    }, icon: Symbols.speed_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: const ChoicePref('device.aether.ipVersion', 'IP version', {
                      'v4': 'IPv4',
                      'v6': 'IPv6',
                      'both': 'IPv4 + IPv6',
                    }, icon: Symbols.language_rounded)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _outputCount,
                        decoration: const InputDecoration(
                          labelText: 'Output count',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (var count = 1; count <= 10; count++)
                            DropdownMenuItem(value: count, child: Text('$count')),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value != null) setState(() => _outputCount = value);
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _scan,
                icon: Icon(_hasScanned ? Symbols.refresh_rounded : Symbols.manage_search_rounded),
                label: Text(_hasScanned ? 'Scan again' : 'Scan'),
              ),
              if (_loading)
                OutlinedButton.icon(
                  onPressed: _stopping ? null : _togglePause,
                  icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(_paused ? 'Resume' : 'Pause'),
                ),
              if (_loading)
                OutlinedButton.icon(
                  onPressed: _stopping
                      ? null
                      : () async {
                          setState(() => _stopping = true);
                          try {
                            await AppScope.of(context).cancelAetherEndpointScan();
                          } catch (error) {
                            if (mounted) {
                              setState(() {
                                _stopping = false;
                                _error = '$error';
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(_stopping ? 'Stopping…' : 'Stop'),
                ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Center(child: Text(_stopping ? 'Stopping Aether scan…' : 'Aether is scanning and verifying endpoints…')),
          ] else if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ] else if (_hasScanned) ...[
            const SizedBox(height: 18),
            Text('${_results.length} healthy endpoint(s) found', style: theme.textTheme.titleMedium),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${_selectedEndpoints.length} selected', style: theme.textTheme.bodySmall),
            for (final (index, result) in _results.indexed)
              CheckboxListTile(
                value: _selectedEndpoints.contains(result.endpoint),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selectedEndpoints.add(result.endpoint);
                  } else {
                    _selectedEndpoints.remove(result.endpoint);
                  }
                }),
                secondary: IconButton(
                  tooltip: 'Copy endpoint',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: result.endpoint),
                  ),
                ),
                title: Text(
                  result.endpoint,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: Text(
                  'Ping: ${result.pingMs.toStringAsFixed(2)} ms'
                  '${index == 0 ? ' · Fastest' : ''}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            Center(
              child: FilledButton.icon(
                onPressed: () => _importSelected(state),
                icon: const Icon(Icons.file_download_done_rounded),
                label: const Text('Import selected endpoints'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _CompactSettingsTheme extends StatelessWidget {
  final Widget child;
  const _CompactSettingsTheme({required this.child});
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 18),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 13),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 13),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 11.5),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 12.5),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 11.5),
        ),
        iconTheme: base.iconTheme.copyWith(
          size: 18,
          color: base.colorScheme.primary,
        ),
        listTileTheme: base.listTileTheme.copyWith(
          visualDensity: VisualDensity.compact,
          minTileHeight: 44,
          minVerticalPadding: 4,
          iconColor: base.colorScheme.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      child: child,
    );
  }
}

/// Desktop settings navigation with a dedicated Connection landing page.
class _SettingsSections extends StatefulWidget {
  final List<Widget> children;
  final ValueChanged<bool>? onSectionChanged;
  const _SettingsSections({required this.children, this.onSectionChanged});

  @override
  State<_SettingsSections> createState() => _SettingsSectionsState();
}

class ConnectionGroupHeader extends StatelessWidget {
  const ConnectionGroupHeader({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class ConnectionGroupEnd extends StatelessWidget {
  const ConnectionGroupEnd({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class CoreGroupHeader extends StatelessWidget {
  final String title;
  const CoreGroupHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class CoreGroupEnd extends StatelessWidget {
  const CoreGroupEnd({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _SettingsSectionEntry {
  final String id;
  final String title;
  final List<Widget> children;
  const _SettingsSectionEntry(this.id, this.title, this.children);
}

class _ConnectionNode {
  final String title;
  final List<_SettingsSectionEntry> sections;
  final _SettingsSectionEntry? directSection;
  const _ConnectionNode.group(this.title, this.sections) : directSection = null;
  _ConnectionNode.direct(this.directSection)
      : title = directSection!.title,
        sections = const [];
}

class _SettingsNavigation {
  final List<_SettingsSectionEntry> rootSections;
  final List<_ConnectionNode> connectionItems;
  const _SettingsNavigation(this.rootSections, this.connectionItems);
}

class _SettingsSectionsState extends State<_SettingsSections> {
  String _selectedId = 'root::Global';
  String? _connectionGroup;
  String? _connectionSection;
  String? _appearanceSubsection;

  _SettingsNavigation _navigation() {
    final rootSections = <_SettingsSectionEntry>[];
    final connectionItems = <_ConnectionNode>[];
    var inConnection = false;
    String? coreTitle;
    String? sectionTitle;
    var sectionChildren = <Widget>[];
    var coreSections = <_SettingsSectionEntry>[];

    void finishSection() {
      if (sectionTitle == null) return;
      final entry = _SettingsSectionEntry(
        inConnection
            ? (coreTitle == null
                ? 'connection::direct::${sectionTitle!}'
                : 'connection::section::${coreTitle!}::${sectionTitle!}')
            : 'root::${sectionTitle!}',
        sectionTitle!,
        sectionChildren,
      );
      if (!inConnection) {
        rootSections.add(entry);
      } else if (coreTitle == null) {
        connectionItems.add(_ConnectionNode.direct(entry));
      } else {
        coreSections.add(entry);
      }
      sectionTitle = null;
      sectionChildren = <Widget>[];
    }

    void finishCoreGroup() {
      if (coreTitle == null) return;
      connectionItems.add(_ConnectionNode.group(coreTitle!, List.of(coreSections)));
      coreSections.clear();
      coreTitle = null;
    }

    for (final child in widget.children) {
      if (child is ConnectionGroupHeader) {
        finishSection();
        finishCoreGroup();
        inConnection = true;
      } else if (child is ConnectionGroupEnd) {
        finishSection();
        finishCoreGroup();
        inConnection = false;
      } else if (child is CoreGroupHeader) {
        finishSection();
        finishCoreGroup();
        coreTitle = child.title;
      } else if (child is CoreGroupEnd) {
        finishSection();
        finishCoreGroup();
      } else if (child is SectionHeader) {
        finishSection();
        sectionTitle = child.title;
      } else if (sectionTitle != null) {
        sectionChildren.add(child);
      }
    }
    finishSection();
    finishCoreGroup();
    return _SettingsNavigation(rootSections, connectionItems);
  }

  void _openConnection() {
    setState(() {
      _selectedId = 'connection::home';
      _connectionGroup = null;
      _connectionSection = null;
      widget.onSectionChanged?.call(false);
    });
  }

  void _openGroup(String title) {
    setState(() {
      _selectedId = 'connection::group::$title';
      _connectionGroup = title;
      _connectionSection = null;
      widget.onSectionChanged?.call(false);
    });
  }

  void _openConnectionSection(_SettingsSectionEntry section, {String? group}) {
    setState(() {
      _selectedId = section.id;
      _connectionGroup = group;
      _connectionSection = section.title;
      widget.onSectionChanged?.call(section.title == 'SSH');
    });
  }

  void _back() {
    setState(() {
      if (_appearanceSubsection != null) {
        _appearanceSubsection = null;
        _selectedId = 'root::Appearance';
      } else if (_connectionSection != null && _connectionGroup != null) {
        _selectedId = 'connection::group::$_connectionGroup';
        _connectionSection = null;
        widget.onSectionChanged?.call(false);
      } else if (_connectionGroup != null || _connectionSection != null) {
        _selectedId = 'connection::home';
        _connectionGroup = null;
        _connectionSection = null;
        widget.onSectionChanged?.call(false);
      }
    });
  }

  Color _iconColor(String title) => _sectionColor(title);

  Widget _navTile(BuildContext context, String title, String id, bool active,
      ThemeData theme, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: active ? theme.colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(children: [
              _sectionIconWidget(title, 18),
              const SizedBox(width: 9),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: active ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ))),
            ]),
          ),
        ),
      ),
    );
  }

  String _description(String title) => switch (title) {
    'BPB Core' => 'VLESS, MASQUE and WARP connection settings',
    'Aether Core' => 'Alternative core and tunnel configurations',
    'SSH' => 'Configure SSH servers and exit-node tunneling',
    'Tor' => 'Tor routing and custom bridge settings',
    'Serverless' => 'DNS-based and serverless connection options',
    'Browser Security' => 'Browser leak protection and location privacy',
    'Worker VLESS' => 'Configure servers, TLS, routing and VLESS transport',
    'MASQUE' => 'Configure MASQUE endpoints and transport options',
    'WARP' => 'Configure WireGuard endpoints and WARP behavior',
    _ => 'Open $title configuration',
  };

  Widget _choiceCard(BuildContext context, String title, String subtitle,
      VoidCallback onTap, ThemeData theme) {
    final color = _iconColor(title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8)),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: Center(child: _sectionIconWidget(title, 22)),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ])),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pageHeader(String title, VoidCallback onBack, ThemeData theme, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Back',
          visualDensity: VisualDensity.compact,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        if (icon != null) ...[
          Icon(icon, size: 19, color: theme.colorScheme.primary),
          const SizedBox(width: 9),
        ],
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigation = _navigation();
    final theme = Theme.of(context);
    final connectionSelected = _selectedId.startsWith('connection::');
    final rootSelected = navigation.rootSections.where((s) => s.id == _selectedId).firstOrNull;
    final selectedGroup = _connectionGroup == null
        ? null
        : navigation.connectionItems.where((n) => n.title == _connectionGroup && n.directSection == null).firstOrNull;
    _SettingsSectionEntry? selectedConnectionSection;
    if (_connectionSection != null) {
      for (final node in navigation.connectionItems) {
        if (node.directSection?.title == _connectionSection && node.directSection?.id == _selectedId) {
          selectedConnectionSection = node.directSection;
        }
        for (final section in node.sections) {
          if (section.id == _selectedId) selectedConnectionSection = section;
        }
      }
    }

    final isConnectionHome = _selectedId == 'connection::home';
    final isGroupHome = _selectedId.startsWith('connection::group::');
    final children = <Widget>[];
    if (rootSelected != null && rootSelected.title != 'Appearance') {
      children.addAll(rootSelected.children);
    } else if (isConnectionHome) {
      children.add(const SizedBox(height: 12));
      for (final node in navigation.connectionItems) {
        children.add(_choiceCard(context, node.title, _description(node.title), () {
          if (node.directSection != null) {
            _openConnectionSection(node.directSection!);
          } else {
            _openGroup(node.title);
          }
        }, theme));
      }
    } else if (isGroupHome && selectedGroup != null) {
      children.add(_pageHeader('Connection', _back, theme));
      for (final section in selectedGroup.sections) {
        children.add(_choiceCard(context, section.title, _description(section.title),
          () => _openConnectionSection(section, group: selectedGroup.title), theme));
      }
    } else if (rootSelected?.title == 'Appearance') {
      if (_appearanceSubsection == null) {
        children.add(const SizedBox(height: 12));
        children.add(_choiceCard(context, 'Theme Options', 'Choose the appearance mode and accent color', () {
          setState(() => _appearanceSubsection = 'theme');
        }, theme));
        children.add(_choiceCard(context, 'Font & Typography', 'Select a built-in or custom typeface and adjust text size', () {
          setState(() => _appearanceSubsection = 'font');
        }, theme));
      } else if (_appearanceSubsection == 'theme') {
        children.add(_pageHeader('Theme Options', _back, theme, icon: Symbols.palette_rounded));
        children.add(const SettingsCard(children: [_ThemeModeTile()]));
        children.add(const SizedBox(height: 12));
        children.add(const SettingsCard(children: [_ThemeColorTile()]));
      } else {
        children.add(_pageHeader('Font Selection', _back, theme, icon: Symbols.font_download_rounded));
        children.add(const SettingsCard(children: [_UserFontTile()]));
        children.add(const SizedBox(height: 12));
        children.add(const SettingsCard(children: [_FontScaleTile()]));
      }
    } else if (selectedConnectionSection != null) {
      children.add(_pageHeader(_connectionGroup ?? 'Connection', _back, theme));
      children.addAll(selectedConnectionSection.children);
    }

    final showConnection = connectionSelected;
    final contentSectionTitle =
        rootSelected?.title ?? selectedConnectionSection?.title;
    final contentIconColor = contentSectionTitle == null
        ? theme.colorScheme.primary
        : _sectionColor(contentSectionTitle);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 204,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
                  children: [
                for (final section in navigation.rootSections.where((s) => s.title == 'Global'))
                  _navTile(context, section.title, section.id, section.id == _selectedId, theme, () {
                    setState(() { _selectedId = section.id; _connectionGroup = null; _connectionSection = null; _appearanceSubsection = null; });
                    widget.onSectionChanged?.call(false);
                  }),
                _navTile(context, 'Connection', 'connection::home', isConnectionHome || showConnection, theme, _openConnection),
                for (final section in navigation.rootSections.where((s) => s.title == 'Browser Security'))
                  _navTile(context, section.title, section.id, section.id == _selectedId, theme, () {
                    setState(() { _selectedId = section.id; _connectionGroup = null; _connectionSection = null; });
                    widget.onSectionChanged?.call(false);
                  }),
                for (final section in navigation.rootSections.where((s) => !['Global', 'Browser Security'].contains(s.title)))
                  _navTile(context, section.title, section.id, section.id == _selectedId, theme, () {
                    setState(() { _selectedId = section.id; _connectionGroup = null; _connectionSection = null; });
                    widget.onSectionChanged?.call(false);
                  }),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              image: DecorationImage(image: AssetImage('images/icon/bgs.jpg'), fit: BoxFit.cover, opacity: 0.24),
            ),
            child: Theme(
              data: theme.copyWith(
                textTheme: theme.textTheme.copyWith(
                  titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                  bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                  bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
                iconTheme: theme.iconTheme.copyWith(
                  size: 18,
                  color: contentIconColor,
                ),
                listTileTheme: theme.listTileTheme.copyWith(
                  visualDensity: VisualDensity.compact,
                  minTileHeight: 44,
                  minVerticalPadding: 4,
                  iconColor: contentIconColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32, top: 4),
                children: children,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


Color _sectionColor(String title) => switch (title) {
  'Global' => const Color(0xFF3B82F6),
  'Connection' => const Color(0xFF0EA5E9),
  'Browser Security' => const Color(0xFF10B981),
  'Worker VLESS' => const Color(0xFF22A6B3),
  'BPB Core' => const Color(0xFF64748B),
  'Aether Core' => const Color(0xFF8B5CF6),
  'MASQUE' => const Color(0xFFF28C28),
  'WARP' => const Color(0xFFF48120),
  'SSH' => const Color(0xFF18A999),
  'Tor' => const Color(0xFF7D4698),
  'Serverless' => const Color(0xFF568BFF),
  'Routing' => const Color(0xFF0D9488),
  'Import / Export' => const Color(0xFF3B82F6),
  'Appearance' => const Color(0xFF78B7FF),
  'Theme Options' => const Color(0xFFB084F5),
  'Font & Typography' => const Color(0xFF38A6B8),
  'About' => const Color(0xFF8B5CF6),
  _ => const Color(0xFF64748B),
};

Widget _sectionIconWidget(String title, double size) {
  final color = _sectionColor(title);
  final fallback = Icon(_sectionIcon(title), size: size, color: color);
  final asset = switch (title) {
    'Serverless' => 'images/icon/Serverless.png',
    _ => null,
  };
  final Widget icon = asset == null
      ? fallback
      : Image.asset(asset, width: size, height: size, fit: BoxFit.contain,
          filterQuality: FilterQuality.high, errorBuilder: (_, _, _) => fallback);
  return HoverAnimatedIcon(child: SizedBox(width: size, height: size, child: Center(child: icon)));
}

/// Consistent rounded icons for the Settings navigation.
IconData _sectionIcon(String title) => switch (title) {
  'Global' => Icons.tune_rounded,
  'Connection' => Icons.hub_rounded,
  'Browser Security' => Icons.security_rounded,
  'Worker VLESS' => Icons.route_rounded,
  'BPB Core' => Icons.memory_rounded,
  'Aether Core' => Icons.bubble_chart_rounded,
  'MASQUE' => Icons.shield_rounded,
  'WARP' => Icons.cloud_rounded,
  'SSH' => Icons.key_rounded,
  'Tor' => Icons.visibility_off_rounded,
  'Serverless' => Icons.cloud_queue_rounded,
  'Routing' => Icons.alt_route_rounded,
  'Import / Export' => Icons.import_export_rounded,
  'Appearance' => Icons.palette_rounded,
  'Theme Options' => Icons.palette_rounded,
  'Font & Typography' => Icons.text_fields_rounded,
  'About' => Icons.info_outline_rounded,
  _ => Icons.settings_rounded,
};

/// App-wide text size, independent of the Windows display scaling.
class _FontScaleTile extends StatelessWidget {
  const _FontScaleTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: state.fontScale,
      builder: (context, scale, _) {
        final theme = Theme.of(context);
        final percent = ((scale - 0.8) / 0.5).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Symbols.text_fields_rounded, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Text('Font Size', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text('Adjust the text scale throughout the app.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, constraints) {
                final usableWidth = (constraints.maxWidth - 24).clamp(0.0, double.infinity).toDouble();
                return Column(
                  children: [
                    Slider(
                      value: scale,
                      min: 0.8,
                      max: 1.3,
                      divisions: 10,
                      label: null,
                      onChanged: state.setFontScale,
                    ),
                    SizedBox(
                      height: 22,
                      child: Stack(children: [
                        Positioned(
                          left: (12 + usableWidth * percent).clamp(0.0, constraints.maxWidth - 12).toDouble(),
                          child: Transform.translate(
                            offset: const Offset(-12, 0),
                            child: Text(
                              '${(scale * 100).round()}%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// User fonts are loaded from the Fonts folder beside the running executable.
class _UserFontTile extends StatefulWidget {
  const _UserFontTile();

  @override
  State<_UserFontTile> createState() => _UserFontTileState();
}

class _UserFontTileState extends State<_UserFontTile> with WidgetsBindingObserver {
  String? _selectedFamily;

  static const _builtInFonts = {
    'ClashGrotesk': 'Clash Grotesk',
    'Segoe UI': 'Segoe UI',
    'Arial': 'Arial',
    'Tahoma': 'Tahoma',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = AppScope.read(context);
    _selectedFamily = state.fontFamily.value;
    state.refreshUserFonts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppScope.read(context).refreshUserFonts();
    }
  }

  Future<void> _apply() async {
    final family = _selectedFamily;
    if (family == null) return;
    try {
      await AppScope.read(context).applyFontFamily(family);
      if (!mounted) return;
      final state = AppScope.read(context);
      AppToast.showSnackBar(context, 
        SnackBar(content: Text('Font applied: ${_builtInFonts[family] ?? state.userFonts.where((font) => font.family == family).firstOrNull?.name ?? family}')),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.showSnackBar(context, 
        SnackBar(content: Text('Could not load this font: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final fonts = state.userFonts;
    final customSelected = fonts.any((font) => font.family == _selectedFamily);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Symbols.font_download_rounded, color: theme.colorScheme.primary, size: 19),
            const SizedBox(width: 9),
            Text('Built-in Fonts', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _builtInFonts.entries) ...[
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _selectedFamily == entry.key,
                    showCheckmark: false,
                    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => setState(() => _selectedFamily = entry.key),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ChipMenu<String>(
                  values: [for (final font in fonts) font.family],
                  selected: customSelected ? _selectedFamily : null,
                  label: (family) => fonts.firstWhere((font) => font.family == family).name,
                  placeholder: 'Select from Fonts folder',
                  width: 280,
                  expand: true,
                  onSelected: (value) => setState(() => _selectedFamily = value),
                  enabled: fonts.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Open Fonts folder',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.folder_open_rounded),
                onPressed: () async {
                  try {
                    await state.openUserFontsFolder();
                  } catch (error) {
                    if (!context.mounted) return;
                    AppToast.showSnackBar(context, 
                      SnackBar(content: Text('Could not open Fonts folder: $error')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Place .ttf or .otf files in the Fonts folder inside the app directory, then select one here.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (fonts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('No custom fonts found yet.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _selectedFamily == null ? null : _apply,
              icon: const Icon(Symbols.check_rounded, size: 18),
              label: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light / dark / follow the OS.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: state.themeMode,
      builder: (context, mode, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Symbols.contrast_rounded),
            title: Text('Theme mode'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (v) => state.setThemeMode(v.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme colour picker: a row of colour circles, the selected one checked.
class _ThemeColorTile extends StatelessWidget {
  const _ThemeColorTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: state.themeColor,
      builder: (context, selected, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Symbols.palette_rounded),
            title: Text('Theme color'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in ThemeColor.values)
                    Tooltip(
                      message: c.label,
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        customBorder: const CircleBorder(),
                        onTap: () => state.setThemeColor(c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.seed,
                            // Ring around the selected colour.
                            border: Border.all(
                              color: c == selected
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: c == selected
                              ? const Icon(
                                  Symbols.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A routing group: the presets on and how many custom entries; opens its page.
class _RulesTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String group;
  final Map<String, String> labels;
  final String domainHint;

  /// Null for a group without custom IPs.
  final String? ipHint;
  final String? help;
  const _RulesTile({
    required this.title,
    required this.icon,
    required this.group,
    required this.labels,
    required this.domainHint,
    this.ipHint,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final routing = state.profile.routing;
    final enabled = [
      for (final e in labels.entries)
        if (state.readBool('routing.$group.presets.${e.key}')) e.value,
    ];
    final countrySummary = group == 'bypass'
        ? routing.geoFilesCountry != routing.geoCountry
            ? 'Please Update Geo Files'
            : '${RoutingPage.geoCountries[routing.geoCountry] ?? 'Country'} Geo Rules'
        : null;
    final presetSummary = [
      ?countrySummary,
      if (enabled.isNotEmpty) enabled.join(', '),
    ];
    final custom =
        state.readList('routing.$group.domains').length +
        (ipHint == null ? 0 : state.readList('routing.$group.ips').length);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        [
          presetSummary.isEmpty ? 'No presets' : presetSummary.join(', '),
          if (custom > 0) '$custom custom',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>_CompactSettingsTheme(child:  RoutingPage(
            title: title,
            group: group,
            labels: labels,
            domainHint: domainHint,
            ipHint: ipHint,
            help: help,
          )),
        ),
      ),
    );
  }
}

/// Custom domain row: tap to attach a domain while none is set; the trash icon detaches it.
class _CustomDomainTile extends StatefulWidget {
  const _CustomDomainTile();

  @override
  State<_CustomDomainTile> createState() => _CustomDomainTileState();
}

class _CustomDomainTileState extends State<_CustomDomainTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      AppToast.showSnackBar(context, SnackBar(content: Text(success)));
    } on StateError catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    } catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final state = AppScope.read(context);
    final domain = await showTextInputDialog(
      context,
      title: 'Add custom domain',
      hint: 'vpn.example.com',
      help:
          'The domain must be registered on the same Cloudflare account. '
          'Just add a desired subdomain which is not available on Cloudflare yet. '
          'BPB creates the DNS record and adds it to the worker.',
      validator: (v) => isDomain(v) ? null : 'Invalid domain',
    );
    if (domain == null || !mounted) return;
    await _run(
      () => state.setCustomDomain(domain.toLowerCase()),
      'Custom domain added',
    );
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final domain = state.worker!.customDomain ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete custom domain?'),
        content: Text(
          '$domain will be detached from the worker in Cloudflare. '
          'Configs fall back to the workers.dev address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(state.removeCustomDomain, 'Custom domain deleted');
  }

  @override
  Widget build(BuildContext context) {
    final domain = AppScope.of(context).worker?.customDomain ?? '';
    return ListTile(
      leading: const Icon(Symbols.host_rounded),
      title: const Text('Custom domain'),
      subtitle: Text(domain.isEmpty ? 'Not set' : domain),
      onTap: _busy || domain.isNotEmpty ? null : _add,
      trailing: _busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : domain.isEmpty
          ? null
          : IconButton(
              tooltip: 'Delete custom domain',
              icon: const Icon(Symbols.delete_outline_rounded),
              onPressed: _delete,
            ),
    );
  }
}

/// Windows CA creation and installation guide for Serverless Domain Fronting.
class _CertificateStep extends StatelessWidget {
  final String number;
  final String text;

  const _CertificateStep(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(number, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WindowsMitmCaTile extends StatefulWidget {
  const _WindowsMitmCaTile();

  @override
  State<_WindowsMitmCaTile> createState() => _WindowsMitmCaTileState();
}

class _WindowsMitmCaTileState extends State<_WindowsMitmCaTile> {
  late Future<({bool created, bool installed})> _status = _loadStatus();
  bool _busy = false;

  Future<({bool created, bool installed})> _loadStatus() async {
    final state = AppScope.read(context);
    final created = await state.hasMitmCa();
    final installed = created && await state.isMitmCaInstalled();
    return (created: created, installed: installed);
  }

  void _refresh() {
    if (mounted) setState(() => _status = _loadStatus());
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).createMitmCa();
      if (!mounted) return;
      AppToast.showSnackBar(context, 
        const SnackBar(content: Text('Certificate created successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showSnackBar(context, 
        SnackBar(content: Text('Could not create the certificate: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _install() async {
    final state = AppScope.read(context);
    var installStarted = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Symbols.verified_user_rounded, size: 36, weight: 600),
          title: const Text('Install BPB MITM certificate'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _CertificateStep('1.', 'Press “Install” below to open the certificate.'),
                const _CertificateStep('2.', 'In the certificate window, click “Install Certificate...”.'),
                const _CertificateStep('3.', 'Choose “Current User” and click Next.'),
                const _CertificateStep('4.', 'Select “Place all certificates in the following store”.'),
                const _CertificateStep('5.', 'Click Browse, then choose “Trusted Root Certification Authorities”.'),
                const _CertificateStep('6.', 'Click Next → Finish and confirm the Windows security prompt.'),
                const SizedBox(height: 16),
                const Text('Edge and Chrome use the Windows certificate store.'),
                const SizedBox(height: 8),
                const Text('For Firefox:'),
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 4),
                  child: Text('Import the certificate under Settings → Privacy & Security → Certificates.'),
                ),
                const SizedBox(height: 16),
                const Text('⚠️ Only trust the certificate generated by this BPB installation.'),
                const SizedBox(height: 6),
                const Text('⚠️ Never share bpb-cert.key.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(installStarted ? 'Close' : 'Cancel'),
            ),
            FilledButton(
              onPressed: installStarted
                  ? null
                  : () async {
                      setDialogState(() => installStarted = true);
                      try {
                        await state.openMitmCaCertificate();
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() => installStarted = false);
                          AppToast.showSnackBar(context, 
                            SnackBar(content: Text('Could not open the certificate: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Install'),
            ),
          ],
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool created, bool installed})>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final created = status?.created ?? false;
        final installed = status?.installed ?? false;
        final subtitle = snapshot.connectionState == ConnectionState.waiting
            ? 'Checking certificate…'
            : !created
                ? 'Not installed'
                : installed
                    ? 'Installed'
                    : 'Created · Not installed';
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MITM certificate'),
          subtitle: Text(subtitle),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonalIcon(
                  icon: Icon(
                    created ? Symbols.security_rounded : Symbols.add_rounded,
                    size: 18,
                  ),
                  label: Text(created ? 'Install' : 'Create'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : created
                          ? _install
                          : _create,
                ),
        );
      },
    );
  }
}

/// Domain Fronting's CA (bpb-cert.crt / .key): created on this device on first install, then
/// handed to Android's certificate install (like [_WarpAccountTile]).
class _MitmCaTile extends StatefulWidget {
  const _MitmCaTile();

  @override
  State<_MitmCaTile> createState() => _MitmCaTileState();
}

class _MitmCaTileState extends State<_MitmCaTile> {
  late Future<bool> _created = AppScope.read(context).hasMitmCa();
  bool _busy = false;

  Future<void> _install() async {
    final state = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.verified_user_rounded, size: 36, weight: 600),
        title: const Text('Install certificate'),
        content: const Text(
          'Certificate will be saved to Downloads folder. Install it in Settings → '
          'Security → Encryption & credentials → Install a certificate → CA certificate.\n\n'
          'Never share BPB certificate files with anyone. Whoever has them can sniff your '
          'browser traffic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final saved = await state.installMitmCa();
      if (saved != null) {
        AppToast.showSnackBar(context, SnackBar(content: Text('Saved to $saved')));
      }
    } catch (e) {
      AppToast.showSnackBar(context, 
        SnackBar(content: Text('Could not install the certificate: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _created = state.hasMitmCa();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _created,
      builder: (context, snapshot) {
        final created = snapshot.data ?? false;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MITM certificate'),
          subtitle: Text(created ? 'Created' : 'Not created'),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.security_rounded, size: 18),
                  label: const Text('Install'),
                  onPressed: _install,
                ),
        );
      },
    );
  }
}

/// Shows the registered WARP account and renews it (panel: "Renew Warp Accounts").
class _WarpAccountTile extends StatelessWidget {
  const _WarpAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final registered = state.profile.warp.account != null;
    return ListTile(
      leading: const Icon(Symbols.vpn_key_rounded),
      title: const Text('WARP account'),
      subtitle: Text(registered ? 'Registered' : 'Not registered'),
      trailing: state.renewingWarp
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonalIcon(
              icon: const Icon(Symbols.autorenew_rounded, size: 18),
              label: Text(registered ? 'Renew' : 'Register'),
              onPressed: () async {
                if (registered) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Renew WARP account'),
                      content: const Text(
                        'Are you sure? A new account replaces the current one.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Renew'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                try {
                  await state.renewWarpAccount();
                  AppToast.showSnackBar(context, 
                    const SnackBar(content: Text('WARP account updated')),
                  );
                } on StateError catch (e) {
                  AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
                }
              },
            ),
    );
  }
}

/// Shows Aether's local MASQUE identity and can replace it with a newly registered identity.
class _AetherMasqueAccountTile extends StatelessWidget {
  const _AetherMasqueAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<bool>(
      future: state.hasAetherMasqueIdentity,
      builder: (context, snapshot) {
        final registered = snapshot.data == true;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MASQUE account'),
          subtitle: Text(snapshot.connectionState == ConnectionState.waiting
              ? 'Checking…'
              : registered ? 'Registered' : 'Not registered'),
          trailing: state.renewingAetherMasque
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.autorenew_rounded, size: 18),
                  label: Text(registered ? 'Renew' : 'Register'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          state.isConnected || state.isBusy
                      ? null
                      : () async {
                          if (registered) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Renew Aether MASQUE identity'),
                                content: const Text(
                                  'A new MASQUE identity will replace the current one. Continue?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Renew'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          try {
                            await state.renewAetherMasqueIdentity();
                            AppToast.showSnackBar(context, 
                              const SnackBar(content: Text('Aether MASQUE identity updated')),
                            );
                          } catch (e) {
                            AppToast.showSnackBar(context, SnackBar(content: Text('$e')));
                          }
                        },
                ),
        );
      },
    );
  }
}

/// Shows Aether's independent WireGuard/WARP identity and can register or renew it.
class _AetherWgAccountTile extends StatelessWidget {
  const _AetherWgAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<bool>(
      future: state.hasAetherWgIdentity,
      builder: (context, snapshot) {
        final registered = snapshot.data == true;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('WARP account'),
          subtitle: Text(snapshot.connectionState == ConnectionState.waiting
              ? 'Checking…'
              : registered ? 'Registered' : 'Not registered'),
          trailing: state.renewingAetherWg
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.autorenew_rounded, size: 18),
                  label: Text(registered ? 'Renew' : 'Register'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          state.isConnected || state.isBusy
                      ? null
                      : () async {
                          if (registered) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Renew Aether WARP identity'),
                                content: const Text(
                                  'A new WireGuard/WARP identity will replace the current one without changing the MASQUE identity. Continue?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Renew'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          try {
                            await state.renewAetherWgIdentity();
                            AppToast.showSnackBar(context, 
                              const SnackBar(content: Text('Aether WARP identity updated')),
                            );
                          } catch (e) {
                            AppToast.showSnackBar(context, SnackBar(content: Text('$e')));
                          }
                        },
                ),
        );
      },
    );
  }
}

/// Shows the registered MASQUE account and renews it, like [_WarpAccountTile].
class _MasqueAccountTile extends StatelessWidget {
  const _MasqueAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final registered = state.profile.masque.account != null;
    return ListTile(
      leading: const Icon(Symbols.vpn_key_rounded),
      title: const Text('MASQUE account'),
      subtitle: Text(registered ? 'Registered' : 'Not registered'),
      trailing: state.renewingMasque
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonalIcon(
              icon: const Icon(Symbols.autorenew_rounded, size: 18),
              label: Text(registered ? 'Renew' : 'Register'),
              onPressed: () async {
                if (registered) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Renew MASQUE account'),
                      content: const Text(
                        'Are you sure? A new account replaces the current one.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Renew'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                try {
                  await state.renewMasqueAccount();
                  AppToast.showSnackBar(context, 
                    const SnackBar(content: Text('MASQUE account updated')),
                  );
                } on StateError catch (e) {
                  AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
                }
              },
            ),
    );
  }
}

/// "1 fragment", "3 fragments", like the noises' subtitles.
String _fragmentSummary(List<Fragment> fragments) =>
    '${fragments.length} fragment${fragments.length == 1 ? '' : 's'}';

/// Which of the selected account's deployments (Workers or Pages) Worker mode connects to; the
/// VLESS settings below are its own. The account is picked in Cloudflare accounts.
class _DeploymentTile extends StatelessWidget {
  const _DeploymentTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final s = state.selected;
    if (s == null) {
      return const ListTile(
        leading: Icon(Symbols.deployed_code_rounded),
        title: Text('Type'),
        subtitle: Text('None. Add a Cloudflare account below.'),
      );
    }
    final key = AppState.deploymentKey(s.account, s.deployment);
    final deploying = state.isDeploying(s.account, s.deployment);
    final error = state.deployErrors[key];
    // Proxy IPs and the fallback website deploy right away; only a failure stays on screen.
    final status = deploying
        ? 'Deploying…'
        : s.deployment.pending
        ? 'Not deployed${error != null ? ': $error' : ' yet'}'
        : null;
    final all = s.account.deployments;
    return ListTile(
      leading: const Icon(Symbols.deployed_code_rounded),
      title: const Text('Type'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: s.deployment.type.label),
            if (status != null)
              TextSpan(
                text: '\n$status',
                style: TextStyle(
                  color: deploying ? null : theme.colorScheme.error,
                ),
              ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: deploying
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : s.deployment.pending
          ? IconButton(
              tooltip: 'Deploy again',
              icon: const Icon(Symbols.refresh_rounded),
              onPressed: () => state.redeploy(s.account, s.deployment.type),
            )
          : null,
      onTap: all.length < 2
          ? null
          : () async {
              final picked = await showDialog<WorkerType>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Type'),
                  children: [
                    RadioGroup<WorkerType>(
                      groupValue: s.deployment.type,
                      onChanged: (v) => Navigator.of(context).pop(v),
                      child: Column(
                        children: [
                          for (final d in all)
                            RadioListTile<WorkerType>(
                              value: d.type,
                              title: Text(d.type.label),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final d = picked == null ? null : s.account.deployment(picked);
              if (d != null) state.selectDeployment(s.account, d);
            },
    );
  }
}

/// Opens the Cloudflare accounts (like the WARP account tile in the WARP section).
class _CloudflareAccountsTile extends StatelessWidget {
  const _CloudflareAccountsTile();

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).selected?.account;
    return ListTile(
      leading: const Icon(Symbols.cloud_rounded),
      title: const Text('Cloudflare accounts'),
      subtitle: account == null
          ? null
          : Text(account.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const CfAccountsPage()))),
    );
  }
}


/// The installed app's version (pubspec.yaml's); opens the cores' versions.
class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: VpnChannel.appInfo().then((i) => i.version).catchError((_) => ''),
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Symbols.info_rounded, color: Color(0xFF3B82F6)),
        title: const Text('Version'),
        subtitle: Text(snapshot.data ?? '…'),
        trailing: const Icon(Symbols.chevron_right_rounded, color: Color(0xFF3B82F6)),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const _VersionsPage()))),
      ),
    );
  }
}

/// The cores' versions: Xray, Psiphon and Tor.
class _VersionsPage extends StatelessWidget {
  const _VersionsPage();

  /// The core's module version as its short commit, as Psiphon's own builds record it: Psiphon
  /// no longer tags releases, so it's a pseudo-version (v1.0.11-0.20261005170209-c4a09096ab40 →
  /// Commit c4a0909).
  static String _psiphon(String s) {
    final commit = RegExp(r'-([0-9a-f]{7})[0-9a-f]{5}$')
        .firstMatch(s)
        ?.group(1);
    return commit != null ? 'Commit $commit' : s.replaceFirst(RegExp('^v'), '');
  }

  /// "Tor version 0.4.8.17." → 0.4.8.17.
  static String _tor(String s) =>
      RegExp(r'Tor version (\S+?)\.?(\s|$)').firstMatch(s)?.group(1) ??
      s.split('\n').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Version')),
      body: FutureBuilder(
        future: VpnChannel.versions(),
        builder: (context, snapshot) {
          final v = snapshot.data;
          String shown(String Function(String) format, String? raw) =>
              switch (raw) {
                null => snapshot.hasError ? 'Unknown' : '…',
                '' => 'Unknown',
                final r => format(r),
              };
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded, color: Color(0xFF8B5CF6)),
                    title: const Text('Xray core · Mod'),
                    subtitle: Text(shown((s) => s, v?.xray)),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.cloud_rounded, color: Color(0xFFF48120)),
                    title: const Text('Worker version'),
                    subtitle: Text('v${CloudflareApi.workerVersion}'),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded, color: Color(0xFF3B82F6)),
                    title: const Text('Psiphon tunnel core · Mod'),
                    subtitle: Text(shown(_psiphon, v?.psiphon)),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded, color: Color(0xFF7D4698)),
                    title: const Text('Tor Expert Bundle'),
                    subtitle: Text(shown(_tor, v?.tor)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _UpdateAction { download, later, repository }

/// Checks GitHub for a newer release on request; the installer is downloaded in the browser.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;

  Future<void> _check() async {
    final state = AppScope.read(context);
    setState(() => _checking = true);
    try {
      final update = await state.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        AppToast.showSnackBar(context, 
          const SnackBar(content: Text('BPB is up to date')),
        );
      } else {
        await _offer(update);
      }
    } on StateError catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _offer(AppUpdate update) async {
    final action = await showDialog<_UpdateAction>(
      context: context,
      builder: (context) {
        final repoBlue = Theme.of(context).colorScheme.primary;
        return AlertDialog(
          title: Text('BPB ${update.version} is available'),
          content: SingleChildScrollView(
            child: Text(update.notes.isEmpty ? 'No release notes.' : update.notes),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A36A),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(_UpdateAction.download),
              child: const Text('Download'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE05252)),
              onPressed: () => Navigator.of(context).pop(_UpdateAction.later),
              child: const Text('Not Now'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: repoBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(_UpdateAction.repository),
              child: const Text('Check Repo'),
            ),
          ],
        );
      },
    );
    if (action == null || action == _UpdateAction.later || !mounted) return;
    final url = action == _UpdateAction.repository
        ? update.pageUrl
        : update.apkUrl ?? update.pageUrl;
    if (!await VpnChannel.openUrl(url) && action == _UpdateAction.download) {
      await Clipboard.setData(ClipboardData(text: url));
      AppToast.showSnackBar(context, 
        const SnackBar(content: Text('Link copied. Open it in your browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.update_rounded, color: Color(0xFF0EA5E9)),
      title: const Text('Check for updates'),
      subtitle: const Text('Latest release on GitHub'),
      trailing: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _checking ? null : _check,
    );
  }
}

/// Downloads the latest geo assets (geoip.dat, geosite.dat) on request.
class _GeoAssetsTile extends StatefulWidget {
  const _GeoAssetsTile();

  @override
  State<_GeoAssetsTile> createState() => _GeoAssetsTileState();
}

class _GeoAssetsTileState extends State<_GeoAssetsTile>
    with AutomaticKeepAliveClientMixin<_GeoAssetsTile> {
  bool _updating = false;

  // Settings uses a lazy ListView. Keep this tile (and its in-flight download)
  // alive while it is scrolled out of view.
  @override
  bool get wantKeepAlive => _updating;
  String? _downloadingFile;
  double? _progress;

  Future<void> _update() async {
    final state = AppScope.read(context);
    setState(() {
      _updating = true;
      _downloadingFile = null;
      _progress = null;
    });
    updateKeepAlive();
    try {
      await state.updateGeoAssets(
        onProgress: (file, received, total) {
          if (!mounted) return;
          setState(() {
            _downloadingFile = file;
            _progress = total != null && total > 0
                ? (received / total).clamp(0.0, 1.0).toDouble()
                : null;
          });
        },
      );
      AppToast.show(
        context,
        state.isConnected
            ? 'Geo files updated. Reconnect to use them.'
            : 'Geo files updated successfully',
      );
    } on StateError catch (e) {
      AppToast.show(context, e.message);
    } catch (e) {
      AppToast.show(context, 'Geo assets update failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _downloadingFile = null;
          _progress = null;
        });
        updateKeepAlive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final progressLabel = _downloadingFile == null
        ? 'Preparing download...'
        : 'Downloading $_downloadingFile'
              '${_progress == null ? '' : ' · ${(_progress! * 100).round()}%'}';
    final appState = AppScope.of(context);
    final routing = appState.profile.routing;
    final updatedAt = appState.geoAssetsUpdatedAt;
    final sourceLabel = switch (routing.geoCountry) {
      'iran' => 'Chocolate4U',
      'china' => 'Loyalsoldier',
      'russia' => 'Loyalsoldier + RunetFreedom',
      _ => 'Geo source',
    };
    final countryLabel = RoutingPage.geoCountries[routing.geoCountry] ?? 'Iran';
    final updatedLabel = routing.geoFilesCountry != routing.geoCountry
        ? 'Please Update Geo Files'
        : updatedAt == null
        ? '$countryLabel · $sourceLabel'
        : 'Last updated: ${updatedAt.year.toString().padLeft(4, '0')}-'
              '${updatedAt.month.toString().padLeft(2, '0')}-'
              '${updatedAt.day.toString().padLeft(2, '0')} '
              '${updatedAt.hour.toString().padLeft(2, '0')}:'
              '${updatedAt.minute.toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Symbols.update_rounded),
          title: const Text('Update Geo assets'),
          subtitle: Text(
            _updating ? progressLabel : updatedLabel,
          ),
          trailing: _updating
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _updating ? null : _update,
        ),
        if (_updating)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LinearProgressIndicator(value: _progress),
          ),
      ],
    );
  }
}

/// Pretty JSON for display/copy.
String prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// Exports the profile (everything but the WARP account) as a JSON file: shared with an
/// app or saved to Downloads. Device settings and the worker are never included.
class _ExportSettingsTile extends StatelessWidget {
  /// Save to Downloads instead of opening the share sheet.
  final bool download;
  const _ExportSettingsTile({required this.download});

  Future<void> _export(BuildContext context) async {
    final state = AppScope.read(context);
    final name =
        'bpb-settings-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final content = state.exportSettingsFile();
    try {
      if (download) {
        final where = await VpnChannel.saveFile(name: name, content: content);
        if (where != null) {
          AppToast.showSnackBar(context, SnackBar(content: Text('Saved to $where')));
        }
      } else {
        await VpnChannel.shareFile(
          name: name,
          content: content,
          title: 'Share settings',
        );
      }
    } on PlatformException catch (e) {
      AppToast.showSnackBar(context, 
        SnackBar(content: Text("Couldn't export: ${e.message}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(download ? Symbols.download_rounded : Symbols.send_rounded),
    title: Text(download ? 'Export settings' : 'Share settings'),
    subtitle: Text(
      download
          ? 'Save settings file to Downloads'
          : 'Send settings file to other users',
    ),
    onTap: () => _export(context),
  );
}

/// Loads settings from a file made by "Share settings" or "Download settings".
class _ImportSettingsTile extends StatelessWidget {
  const _ImportSettingsTile();

  Future<void> _import(BuildContext context) async {
    final state = AppScope.read(context);
    final String? text;
    try {
      text = (await VpnChannel.pickFile())?.content;
    } on PlatformException catch (e) {
      AppToast.showSnackBar(context, 
        SnackBar(content: Text("Couldn't read the file: ${e.message}")),
      );
      return;
    }
    if (text == null || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import settings?'),
        content: const Text(
          'Your settings are replaced with the ones in this file. '
          'Your WARP account, worker and this device\'s setup (per-app list, LAN sharing, theme…) stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      state.importSettingsFile(text);
      AppToast.showSnackBar(context, 
        const SnackBar(content: Text('Settings imported')),
      );
    } on FormatException catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Symbols.upload_rounded),
    title: const Text('Import settings'),
    subtitle: const Text('Load settings from a file'),
    onTap: () => _import(context),
  );
}
