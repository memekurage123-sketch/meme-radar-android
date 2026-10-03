import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CandidateCard extends StatefulWidget {
  final Map<String, dynamic> candidate;

  const CandidateCard({super.key, required this.candidate});

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  bool _isExpanded = false;

  String _formatCurrency(dynamic value) {
    if (value == null) return '-';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '-';
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(2)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(1)}K';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '-';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '-';
    if (n < 0.000001) return '\$${n.toStringAsExponential(2)}';
    if (n < 0.01) return '\$${n.toStringAsFixed(6)}';
    if (n < 1.0) return '\$${n.toStringAsFixed(4)}';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _formatScore(dynamic value) {
    if (value == null) return '-';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return '-';
    return n.toStringAsFixed(0);
  }

  String _truncateAddress(String? address) {
    if (address == null || address.isEmpty) return '-';
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
    final chain = c['chain']?.toString().toUpperCase() ?? '';
    final isPriority = c['priorityBand'] == true;
    final score = _formatScore(c['discoveryScore']);
    final mc = _formatCurrency(c['marketCap']);
    final liq = _formatCurrency(c['liquidity']);
    final vol5m = _formatCurrency(c['volume5m']);
    final price = _formatPrice(c['price']);
    final holders = c['holders']?.toString() ?? '-';
    final buys5m = c['buys5m']?.toString() ?? '-';
    final sells5m = c['sells5m']?.toString() ?? '-';
    final pairAddress = c['pairAddress']?.toString() ?? '';
    final dev = c['devHolding'] != null ? '${c['devHolding']}%' : '-';
    final tax = c['tax'] != null ? '${c['tax']}%' : '-';
    final twitter = (c['social'] is Map ? (c['social'] as Map)['twitter'] : null)?.toString() ?? '';

    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPriority
            ? BorderSide(color: theme.colorScheme.primary.withAlpha(128), width: 1.2)
            : BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(50), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Symbol, Name, Chain, Priority badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withAlpha(60),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade700, width: 0.8),
                      ),
                      child: const Text(
                        'PRIORITY',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              InkWell(
                onTap: address.isNotEmpty ? () => _copyToClipboard(context, address, '合约地址 (CA)') : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, size: 14, color: theme.colorScheme.primary),
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
              const SizedBox(height: 10),

              // Primary Metrics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMetric('Score', score, highlight: true, color: Colors.greenAccent),
                  _buildMetric('MC', mc),
                  _buildMetric('Liquidity', liq),
                  _buildMetric('DEV%', dev),
                  _buildMetric('Tax', tax),
                ],
              ),

              // Expandable Detail Section
              if (_isExpanded) ...[
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetric('Price', price),
                    _buildMetric('5m Vol', vol5m),
                    _buildMetric('5m Buys', buys5m, color: Colors.green.shade400),
                    _buildMetric('5m Sells', sells5m, color: Colors.red.shade400),
                    _buildMetric('Holders', holders),
                  ],
                ),
                if (pairAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _copyToClipboard(context, pairAddress, 'Pair 地址'),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14, color: theme.colorScheme.outline),
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
                      Icon(Icons.alternate_email, size: 14, color: theme.colorScheme.outline),
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
              ],

              // Expand / collapse chevron
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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

  Widget _buildMetric(String label, String value, {bool highlight = false, Color? color}) {
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
