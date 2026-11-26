import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'theme.dart';

const _download = Color(0xFF39FF75);
const _upload = Color(0xFF8B7CFF);
const _worker = Color(0xFF8B7CFF);
const _total = Color(0xFF46B8FF);

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TrafficCard(
            download: state.allTimeDown,
            upload: state.allTimeUp,
            total: state.allTimeDown + state.allTimeUp,
          ),
          if (state.worker != null && state.mode.needsWorker) ...[
            const SizedBox(height: 16),
            const _WorkerRequestCard(),
          ],
        ],
      ),
    );
  }
}

/// One unified traffic panel: Download, Upload and Total always share one row.
class _TrafficCard extends StatelessWidget {
  final int download;
  final int upload;
  final int total;
  const _TrafficCard({required this.download, required this.upload, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.9),
      shape: roundedShape(kHeroRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _total.withValues(alpha: 0.14),
                ),
                child: const Icon(Symbols.swap_vert_rounded, color: _total),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Traffic usage', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('All-time data transfer', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              )),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _TrafficValue(label: 'DOWNLOAD', value: formatBytes(download), icon: Symbols.south_rounded, color: _download)),
              _verticalDivider(theme),
              Expanded(child: _TrafficValue(label: 'UPLOAD', value: formatBytes(upload), icon: Symbols.north_rounded, color: _upload)),
              _verticalDivider(theme),
              Expanded(child: _TrafficValue(label: 'TOTAL', value: formatBytes(total), icon: Symbols.swap_vert_rounded, color: _total)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _verticalDivider(ThemeData theme) => Container(
    width: 1, height: 48, margin: const EdgeInsets.symmetric(horizontal: 7),
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
  );
}

class _TrafficValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _TrafficValue({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 7),
        Text(label, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.35, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))),
      ],
    );
  }
}

class _WorkerRequestCard extends StatelessWidget {
  static const _limit = 100000;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final usage = state.usage;
    final total = usage?.total ?? 0;
    final ratio = (total / _limit).clamp(0.0, 1.0).toDouble();
    final remaining = (_limit - total).clamp(0, _limit).toInt();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer.withValues(alpha: 0.92),
      shape: roundedShape(kHeroRadius,
        side: BorderSide(color: _worker.withValues(alpha: 0.42))),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [_worker.withValues(alpha: 0.28), _worker.withValues(alpha: 0.08)],
                ),
              ),
              child: const Icon(Symbols.cloud_sync_rounded, color: _worker, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Worker Request', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text('Cloudflare · Last 24 hours', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
            IconButton(
              tooltip: 'Refresh Worker requests',
              onPressed: state.loadingUsage ? null : state.refreshUsage,
              icon: state.loadingUsage
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Symbols.refresh_rounded),
            ),
          ]),
          const SizedBox(height: 18),
          if (usage != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                color: _worker.withValues(alpha: 0.075),
                border: Border.all(color: _worker.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 94, height: 94,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(child: CircularProgressIndicator(
                      value: ratio, strokeWidth: 9, strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: ratio >= 0.9 ? scheme.error : _worker,
                    )),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${(ratio * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text('USED', style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant, letterSpacing: 1.0)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(formatCount(total), style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 3),
                  Text('requests in the last 24 hours',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Symbols.hourglass_bottom_rounded, size: 16, color: _worker),
                    const SizedBox(width: 6),
                    Text('${formatCount(remaining)} remaining',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _WorkerBreakdown(label: 'THIS WORKER', value: formatCount(usage.worker), color: _worker)),
              const SizedBox(width: 9),
              Expanded(child: _WorkerBreakdown(label: 'ACCOUNT TOTAL', value: formatCount(usage.total), color: _total)),
              const SizedBox(width: 9),
              Expanded(child: _WorkerBreakdown(label: 'DAILY LIMIT', value: formatCount(_limit), color: scheme.onSurfaceVariant)),
            ]),
          ] else if (state.usageError != null) ...[
            Text(state.usageError!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text(
                state.loadingUsage ? 'Loading request usage…' : 'No request data available',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
            ),
        ]),
      ),
    );
  }
}

class _WorkerBreakdown extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WorkerBreakdown({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant, fontSize: 9, letterSpacing: 0.25)),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    );
  }
}
