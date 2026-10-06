import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../radar_core/ave.dart';
import 'bubble_sheet.dart';
import 'kline_chart.dart';

String? formatTokenAge(dynamic createdAtRaw, [int? nowSecParam]) {
  if (createdAtRaw == null) return null;
  final num? ts = createdAtRaw is num
      ? createdAtRaw
      : num.tryParse(createdAtRaw.toString());
  if (ts == null || ts <= 0) return null;

  final int sec = ts >= 100000000000 ? (ts / 1000).round() : ts.toInt();
  final int nowSec =
      nowSecParam ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final int diffSec = nowSec - sec;

  if (diffSec < 0) return null;
  if (diffSec < 60) return '< 1m';

  final int totalMins = diffSec ~/ 60;
  if (totalMins < 60) {
    return '${totalMins}m';
  }

  final int totalHours = totalMins ~/ 60;
  final int remainMins = totalMins % 60;
  if (totalHours < 24) {
    if (remainMins == 0) {
      return '${totalHours}h';
    }
    return '${totalHours}h ${remainMins}m';
  }

  final int days = totalHours ~/ 24;
  final int remainHours = totalHours % 24;
  if (remainHours == 0) {
    return '${days}d';
  }
  return '${days}d ${remainHours}h';
}

class CandidateCard extends StatefulWidget {
  final Map<String, dynamic> candidate;

  const CandidateCard({super.key, required this.candidate});

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  bool _isExpanded = false;
  bool _showKline = false;

  String _formatCurrency(dynamic value) {
    if (value == null) return '—';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '—';
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(2)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(1)}K';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '—';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '—';
    if (n < 0.000001) return '\$${n.toStringAsExponential(2)}';
    if (n < 0.01) return '\$${n.toStringAsFixed(6)}';
    if (n < 1.0) return '\$${n.toStringAsFixed(4)}';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _formatScore(dynamic value) {
    if (value == null) return '—';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(0);
  }

  String _truncateAddress(String? address) {
    if (address == null || address.isEmpty) return '';
    if (address.length <= 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制: $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final symbol = c['symbol']?.toString().toUpperCase() ?? '?';
    final name = c['name']?.toString() ?? '';
    final address = c['address']?.toString() ?? '';
    final chainRaw = c['chain']?.toString() ?? '';
    final chain = chainRaw.toUpperCase();
    final isPriority = c['priorityBand'] == true;

    // Fixed Primary Metrics (Score, MC, Liquidity, 币龄)
    final scoreStr = _formatScore(c['discoveryScore']);
    final mcStr = _formatCurrency(c['marketCap']);
    final liqStr = _formatCurrency(c['liquidity']);
    final ageStr = formatTokenAge(c['createdAt'] ?? c['poolCreatedAt']) ?? '—';

    // Fixed Secondary Metrics (Price, 5m Vol, 5m 买, 5m 卖, Holders)
    final priceStr = _formatPrice(c['price']);
    final vol5mStr = _formatCurrency(c['volume5m']);
    final buys5m = c['buys5m'] != null ? '${c['buys5m']}' : '—';
    final sells5m = c['sells5m'] != null ? '${c['sells5m']}' : '—';
    final holders = c['holders'] != null ? '${c['holders']}' : '—';

    final pairAddress = c['pairAddress']?.toString() ?? '';
    final twitter =
        (c['social'] is Map ? (c['social'] as Map)['twitter'] : null)
                ?.toString() ??
            '';

    // Tags list (displayed in independent tag area, does not affect primary metric columns)
    final List<String> tags = [];
    if (c['tags'] is List) {
      for (final t in c['tags']) {
        if (t != null && t.toString().trim().isNotEmpty) {
          tags.add(t.toString().trim());
        }
      }
    }

    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPriority
            ? BorderSide(
                color: theme.colorScheme.primary.withAlpha(128), width: 1.2)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(50),
                width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
            if (!_isExpanded) _showKline = false;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Symbol, Name, Badges (Priority, Chain)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      symbol,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (isPriority) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withAlpha(60),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.amber.shade700, width: 0.8),
                      ),
                      child: const Text(
                        'PRIORITY',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber),
                      ),
                    ),
                  ],
                  if (chain.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        chain,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // CA: Tap to copy
              if (address.isNotEmpty)
                InkWell(
                  onTap: () => _copyToClipboard(context, address, '合约地址 (CA)'),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'CA: ${_truncateAddress(address)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Optional Token Tags (Independent zone)
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags.map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.secondaryContainer.withAlpha(80),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 10),

              // Fixed 4-Column Primary Metrics Row (Score, MC, Liquidity, Age)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMetric('Score', scoreStr,
                      highlight: true, color: Colors.greenAccent),
                  _buildMetric('MC', mcStr),
                  _buildMetric('Liquidity', liqStr),
                  _buildMetric('Age', ageStr, color: Colors.amber.shade300),
                ],
              ),

              // Expandable Detail Section
              if (_isExpanded) ...[
                const Divider(height: 20),
                // Fixed 5-Column Secondary Metrics Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetric('Price', priceStr),
                    _buildMetric('5m Vol', vol5mStr),
                    _buildMetric('5m Buys', buys5m,
                        color: Colors.green.shade400),
                    _buildMetric('5m Sells', sells5m,
                        color: Colors.red.shade400),
                    _buildMetric('Holders', holders),
                  ],
                ),
                if (pairAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () =>
                        _copyToClipboard(context, pairAddress, 'Pair 地址'),
                    child: Row(
                      children: [
                        Icon(Icons.link,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          'Pair: ${_truncateAddress(pairAddress)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (twitter.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.alternate_email,
                          size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '@$twitter',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),

                // Action buttons: K线 | 气泡图 | AVE 主页 (统一蓝色精致风格)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: Icon(
                        _showKline ? Icons.keyboard_arrow_up : Icons.show_chart,
                        size: 15,
                      ),
                      label: Text(
                        _showKline ? '收起K线' : 'K线',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.blue.withAlpha(40),
                      ),
                      onPressed: () {
                        setState(() {
                          _showKline = !_showKline;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.bubble_chart_rounded, size: 15),
                      label: const Text('气泡图', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.blue.withAlpha(40),
                      ),
                      onPressed: () {
                        BubbleSheet.show(
                          context,
                          chain: chainRaw,
                          address: address,
                          symbol: symbol,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label:
                          const Text('AVE 主页', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(76, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.blue.withAlpha(40),
                      ),
                      onPressed: () async {
                        final lowerChain = chainRaw.toLowerCase();
                        final apiChain = aveChains[lowerChain] ?? lowerChain;
                        final aveUrl =
                            'https://pro.ave.ai/token/$address-$apiChain?ref=0001';
                        final uri = Uri.parse(aveUrl);
                        try {
                          final launched = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                          if (!launched && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('无法打开系统浏览器: $aveUrl'),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('打开 AVE 主页失败: $e'),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                if (_showKline)
                  KLineChartWidget(
                    chain: chainRaw,
                    address: address,
                    priceFormatted: priceStr,
                  ),
              ],

              // Expand / collapse chevron
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value,
      {bool highlight = false, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
