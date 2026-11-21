import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Applies browser-native WebRTC policies for the current Windows user.
///
/// Chrome's WebRtcIPHandling policy and Edge's WebRtcLocalhostIpHandling policy
/// prevent WebRTC from using non-proxied UDP. This keeps WebRTC from silently
/// opening a direct UDP path when the browser is using a system proxy.
class WebRtcLeakProtection {
  static const _chromeKey = r'HKCU\Software\Policies\Google\Chrome';
  static const _edgeKey = r'HKCU\Software\Policies\Microsoft\Edge';

  static const _policies = <_BrowserPolicy>[
    _BrowserPolicy(
      key: _chromeKey,
      valueName: 'WebRtcIPHandling',
      value: 'disable_non_proxied_udp',
      ownershipKey: 'webrtcProtection.chromePolicyOwned',
    ),
    _BrowserPolicy(
      key: _edgeKey,
      valueName: 'WebRtcLocalhostIpHandling',
      value: 'DisableNonProxiedUdp',
      ownershipKey: 'webrtcProtection.edgePolicyOwned',
    ),
  ];

  /// Enables or removes only the policies BPB itself created.
  ///
  /// Existing policies are never overwritten. If an administrator or another
  /// utility has configured a different value, BPB leaves it untouched.
  static Future<bool> apply(
    bool enabled,
    SharedPreferences preferences,
  ) async {
    if (!Platform.isWindows) return false;

    for (final policy in _policies) {
      final owned = preferences.getBool(policy.ownershipKey) ?? false;
      if (!enabled && !owned) continue;
      final current = await _read(policy);

      if (enabled) {
        if (current == policy.value) continue;
        if (current != null) continue;

        // Create the complete policy key even when Google/Chrome does not exist.
        final keyResult = await Process.run(
          'reg.exe',
          ['add', policy.key, '/f'],
          runInShell: false,
          stdoutEncoding: systemEncoding,
          stderrEncoding: systemEncoding,
        );
        if (keyResult.exitCode != 0) continue;

        final result = await Process.run(
          'reg.exe',
          [
            'add',
            policy.key,
            '/v',
            policy.valueName,
            '/t',
            'REG_SZ',
            '/d',
            policy.value,
            '/f',
          ],
          runInShell: false,
          stdoutEncoding: systemEncoding,
          stderrEncoding: systemEncoding,
        );
        if (result.exitCode == 0 && await _read(policy) == policy.value) {
          await preferences.setBool(policy.ownershipKey, true);
        }
      } else if (owned) {
        // Do not delete a value that has since been changed by the user/admin.
        if (current == policy.value) {
          await Process.run(
            'reg.exe',
            [
              'delete',
              policy.key,
              '/v',
              policy.valueName,
              '/f',
            ],
            runInShell: false,
            stdoutEncoding: systemEncoding,
            stderrEncoding: systemEncoding,
          );
        }
        await preferences.remove(policy.ownershipKey);
      }
    }

    // Verify only policies managed by this app. When protection is disabled,
    // leave unrelated browser policies untouched and do not query them.
    for (final policy in _policies) {
      final owned = preferences.getBool(policy.ownershipKey) ?? false;
      if (!enabled && !owned) continue;
      final current = await _read(policy);
      if (enabled && current != policy.value) return false;
      if (!enabled && current == policy.value) return false;
    }
    return true;
  }

  static Future<String?> _read(_BrowserPolicy policy) async {
    final result = await Process.run(
      'reg.exe',
      ['query', policy.key, '/v', policy.valueName],
      runInShell: false,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    if (result.exitCode != 0) return null;

    final output = '${result.stdout}\n${result.stderr}';
    final match = RegExp(
      RegExp.escape(policy.valueName) + r'\s+REG_SZ\s+([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(output);
    return match?.group(1)?.trim();
  }
}

class _BrowserPolicy {
  final String key;
  final String valueName;
  final String value;
  final String ownershipKey;

  const _BrowserPolicy({
    required this.key,
    required this.valueName,
    required this.value,
    required this.ownershipKey,
  });
}
