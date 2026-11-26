import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'theme.dart';

const _download = Color(0xFF39FF75);
const _upload = Color(0xFF8B7CFF);

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final total = state.allTimeDown + state.allTimeUp;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: _SpeedCard(
                  title: 'Download speed',
                  value: '${formatBytes(state.downSpeed)}/s',
                  icon: Symbols.download_rounded,
                  color: _download,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SpeedCard(
                  title: 'Upload speed',
                  value: '${formatBytes(state.upSpeed)}/s',
                  icon: Symbols.upload_rounded,
                  color: _upload,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Total traffic',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TotalCard(
                  title: 'Download',
                  value: formatBytes(state.allTimeDown),
                  icon: Symbols.south_rounded,
                  color: _download,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TotalCard(
                  title: 'Upload',
                  value: formatBytes(state.allTimeUp),
                  icon: Symbols.north_rounded,
                  color: _upload,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TotalCard(
                  title: 'Total',
                  value: formatBytes(total),
                  icon: Symbols.swap_vert_rounded,
                  color: const Color(0xFF46B8FF),
                  featured: true,
                ),
              ),
            ],
          ),
          if (state.worker != null && state.mode.needsWorker) ...[
            const SizedBox(height: 22),
            _WorkerRequestCard(),
          ],
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SpeedCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.88),
      shape: roundedShape(
        kCardRadius,
        side: BorderSide(color: color.withValues(alpha: 0.38)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool featured;

  const _TotalCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: featured
              ? [color.withValues(alpha: 0.28), color.withValues(alpha: 0.09)]
              : [theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.78), theme.colorScheme.surfaceContainer.withValues(alpha: 0.72)],
        ),
        border: Border.all(color: color.withValues(alpha: featured ? 0.58 : 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
          ),
        ],
      ),
    );
  }
}

class _WorkerRequestCard extends StatelessWidget {
  static const _limit = 100000;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final usage = state.usage;
    final total = usage?.total ?? 0;
    final ratio = (total / _limit).clamp(0.0, 1.0).toDouble();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.88),
      shape: roundedShape(
        kHeroRadius,
        side: BorderSide(color: const Color(0xFF8B7CFF).withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: const Color(0xFF8B7CFF).withValues(alpha: 0.16),
                  ),
                  child: const Icon(Symbols.cloud_sync_rounded, color: _upload),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Worker Request', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('Cloudflare Workers · Last 24 hours',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Worker requests',
                  onPressed: state.loadingUsage ? null : state.refreshUsage,
                  icon: state.loadingUsage
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Symbols.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (usage != null) ...[
              Row(
                children: [
                  Expanded(child: _RequestValue(label: 'This Worker', value: formatCount(usage.worker))),
                  Expanded(child: _RequestValue(label: 'Account total', value: formatCount(usage.total))),
                  Expanded(child: _RequestValue(label: 'Remaining', value: formatCount((_limit - total).clamp(0, _limit).toInt()))),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 9,
                  color: ratio >= 0.9 ? theme.colorScheme.error : _upload,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(ratio * 100).toStringAsFixed(1)}% of daily allowance',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text('${formatCount(_limit)} requests',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ] else if (state.usageError != null) ...[
              Text(state.usageError!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            ] else
              Text(state.loadingUsage ? 'Loading request usage…' : 'No request data available',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _RequestValue extends StatelessWidget {
  final String label;
  final String value;
  const _RequestValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        )),
      ],
    );
  }
}
