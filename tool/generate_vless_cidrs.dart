import 'dart:io';

import 'package:bpb/services/geoip_cidr_extractor.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_vless_cidrs.dart <geoip.dat> <output.txt>',
    );
    exitCode = 64;
    return;
  }

  final input = File(args[0]);
  final output = File(args[1]);
  if (!await input.exists()) {
    stderr.writeln('GeoIP asset not found: ${input.path}');
    exitCode = 1;
    return;
  }

  try {
    final cidrs = GeoIpCidrExtractor.extractCloudflareCidrs(
      await input.readAsBytes(),
    );
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.tmp');
    await temporary.writeAsString('${cidrs.join('\n')}\n', flush: true);
    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);

    final ipv4 = cidrs.where((cidr) => !cidr.contains(':')).length;
    final ipv6 = cidrs.length - ipv4;
    stdout.writeln(
      'Generated ${cidrs.length} Cloudflare CIDRs ($ipv4 IPv4, $ipv6 IPv6) at ${output.path}',
    );
  } catch (error) {
    stderr.writeln('Could not generate VLESS CIDRs: $error');
    exitCode = 1;
  }
}
