import 'package:flutter_test/flutter_test.dart';
import 'package:bpb/models/settings.dart';

void main() {
  test('SSH settings round-trip through the profile model', () {
    const ssh = SshSettings(
      host: 'ssh.example.com',
      port: 2222,
      user: 'vpn-user',
      password: 'secret',
      privateKey: 'private-key',
      passphrase: 'key-passphrase',
      keepAliveInterval: 20,
      tcpKeepAliveInterval: 30,
    );

    final profile = Profile.fromJson({'ssh': ssh.toJson()});

    expect(profile.ssh.isConfigured, isTrue);
    expect(profile.ssh.host, 'ssh.example.com');
    expect(profile.ssh.port, 2222);
    expect(profile.ssh.user, 'vpn-user');
    expect(profile.ssh.password, 'secret');
    expect(profile.ssh.privateKey, 'private-key');
    expect(profile.ssh.passphrase, 'key-passphrase');
    expect(profile.ssh.keepAliveInterval, 20);
    expect(profile.ssh.tcpKeepAliveInterval, 30);
  });

  test('SSH credentials are excluded from exported profiles', () {
    final profile = Profile.fromJson({
      'ssh': {
        'host': 'ssh.example.com',
        'port': 22,
        'user': 'vpn-user',
        'password': 'secret',
      },
    });

    expect(profile.toExportJson().containsKey('ssh'), isFalse);

    final imported = Profile.fromJson({}).keepingPrivate(profile);
    expect(imported.ssh.host, 'ssh.example.com');
    expect(imported.ssh.password, 'secret');
  });

  test('SSH is not configured without a password or private key', () {
    expect(
      const SshSettings(host: 'ssh.example.com', user: 'vpn-user').isConfigured,
      isFalse,
    );
  });
}
