import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../radar_core/ave.dart';
import '../services/storage_service.dart';

class _KLineCacheEntry {
  final List<Map<String, dynamic>> data;
  final int timestamp;
  _KLineCacheEntry(this.data, this.timestamp);
}

final Map<String, _KLineCacheEntry> _kLineCache = {};

class KLineChartWidget extends StatefulWidget {
  final String chain;
  final String address;
  final String priceFormatted;

  const KLineChartWidget({
    super.key,
    required this.chain,
    required this.address,
    required this.priceFormatted,
  });

  @override
  State<KLineChartWidget> createState() => _KLineChartWidgetState();
}

class _KLineChartWidgetState extends State<KLineChartWidget> {
  // 5 supported intervals: 1m, 5m, 15m, 30m, 1h
  static const List<Map<String, dynamic>> _intervals = [
    {'label': '1m', 'value': 1},
    {'label': '5m', 'value': 5},
    {'label': '15m', 'value': 15},
    {'label': '30m', 'value': 30},
    {'label': '1h', 'value': 60},
  ];

  static const List<int> _limits = [60, 120, 300, 1000];

  int _selectedInterval = 1;
  int _selectedLimit = 60;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  String _formatRange(int intervalMinutes, int count) {
    final totalMins = intervalMinutes * count;
    if (totalMins < 60) {
      return '≈ ${totalMins}m';
    } else if (totalMins < 1440) {
      final hours = totalMins / 60.0;
      return hours == hours.roundToDouble()
          ? '≈ ${hours.toInt()}h'
          : '≈ ${hours.toStringAsFixed(1)}h';
    } else {
      final days = totalMins / 1440.0;
      return days == days.roundToDouble()
          ? '≈ ${days.toInt()}d'
          : '≈ ${days.toStringAsFixed(1)}d';
    }
  }

  Future<void> _fetchData() async {
    final currentReqId = ++_requestId;
    final cacheKey =
        '${widget.chain}_${widget.address}_${_selectedInterval}_$_selectedLimit';
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _kLineCache[cacheKey];

    if (cached != null && now - cached.timestamp < 60000) {
      if (mounted) {
        setState(() {
          _data = cached.data;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    AveClient? client;
    try {
      final apiKey = await StorageService().getApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw Exception("API Key not found");
      }

      client = AveClient(apiKey: apiKey);
      final res = await client.tokenKlines(
        widget.chain,
        widget.address,
        interval: _selectedInterval,
        limit: _selectedLimit,
      );

      if (_requestId != currentReqId || !mounted) return;

      final list = (res['list'] as List).cast<Map<String, dynamic>>();
      _kLineCache[cacheKey] = _KLineCacheEntry(list, now);

      setState(() {
        _data = list;
        _loading = false;
      });
    } catch (e) {
      if (_requestId != currentReqId || !mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      client?.close();
    }
  }

  void _onIntervalChanged(int interval) {
    if (_selectedInterval != interval) {
      setState(() {
        _selectedInterval = interval;
      });
      _fetchData();
    }
  }

  void _onLimitChanged(int limit) {
    if (_selectedLimit != limit) {
      setState(() {
        _selectedLimit = limit;
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeText = _formatRange(_selectedInterval, _selectedLimit);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Range hint & Current price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'K线范围 $rangeText',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                widget.priceFormatted,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Selectors (Intervals & Limits)
          Row(
            children: [
              // Interval selector
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: _intervals.map((item) {
                    final isSelected = _selectedInterval == item['value'];
                    return _buildSelectChip(
                      label: item['label'] as String,
                      selected: isSelected,
                      onTap: () => _onIntervalChanged(item['value'] as int),
                      theme: theme,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 8),
              // Limit selector
              Wrap(
                spacing: 4,
                children: _limits.map((l) {
                  final isSelected = _selectedLimit == l;
                  return _buildSelectChip(
                    label: '$l',
                    selected: isSelected,
                    onTap: () => _onLimitChanged(l),
                    theme: theme,
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Chart Display Area
          SizedBox(
            height: 130,
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withAlpha(60),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _data.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null && _data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
            const SizedBox(height: 4),
            Text(
              '加载失败',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.error),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _fetchData,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_data.isEmpty) {
      return Center(
        child: Text(
          '暂无 K 线数据',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;

        // Calculate price extremes
        double minP = double.infinity;
        double maxP = double.negativeInfinity;
        for (final c in _data) {
          final h = c['high'] as double;
          final l = c['low'] as double;
          if (h > maxP) maxP = h;
          if (l < minP) minP = l;
        }

        if (minP == double.infinity ||
            maxP == double.negativeInfinity ||
            minP == maxP) {
          minP = minP == double.infinity ? 0 : minP * 0.99;
          maxP = maxP == double.negativeInfinity ? 1 : maxP * 1.01;
        }

        final padding = (maxP - minP) * 0.05;
        if (padding > 0) {
          minP -= padding;
          maxP += padding;
        }

        // Horizontal scrolling: each candle has a comfortable fixed width
        // If data points are few (e.g. 60), spread across viewportWidth if it's wider
        const candleWidth = 6.0;
        final contentWidth =
            math.max(viewportWidth, _data.length * candleWidth);

        return Stack(
          children: [
            // Background Price Grid (fixed to viewport)
            CustomPaint(
              size: Size(viewportWidth, viewportHeight),
              painter: _PriceGridPainter(
                minPrice: minP,
                maxPrice: maxP,
                gridColor: theme.colorScheme.outlineVariant.withAlpha(45),
                textColor: theme.colorScheme.outline,
              ),
            ),

            // Scrollable Candlesticks (reversed so newest candles are on the right by default)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: CustomPaint(
                size: Size(contentWidth, viewportHeight),
                painter: _CandlestickPainter(
                  data: _data,
                  minPrice: minP,
                  maxPrice: maxP,
                  candleWidth: contentWidth / math.max(_data.length, 1),
                  upColor: Colors.greenAccent.shade400,
                  downColor: Colors.redAccent.shade400,
                ),
              ),
            ),

            // Overlay loading spinner if updating
            if (_loading)
              Positioned(
                top: 4,
                right: 4,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PriceGridPainter extends CustomPainter {
  final double minPrice;
  final double maxPrice;
  final Color gridColor;
  final Color textColor;

  _PriceGridPainter({
    required this.minPrice,
    required this.maxPrice,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = size.width;
    final chartHeight = size.height;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i <= 3; i++) {
      final y = chartHeight - (i / 3) * chartHeight;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);

      final price = minPrice + (maxPrice - minPrice) * (i / 3);
      String pStr;
      if (price < 0.000001) {
        pStr = price.toStringAsExponential(2);
      } else if (price < 0.01) {
        pStr = price.toStringAsFixed(6);
      } else if (price < 1) {
        pStr = price.toStringAsFixed(4);
      } else {
        pStr = price.toStringAsFixed(2);
      }

      textPainter.text = TextSpan(
        text: pStr,
        style: TextStyle(color: textColor, fontSize: 8),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y > 10 ? y - 12 : 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PriceGridPainter oldDelegate) {
    return oldDelegate.minPrice != minPrice || oldDelegate.maxPrice != maxPrice;
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final double minPrice;
  final double maxPrice;
  final double candleWidth;
  final Color upColor;
  final Color downColor;

  _CandlestickPainter({
    required this.data,
    required this.minPrice,
    required this.maxPrice,
    required this.candleWidth,
    required this.upColor,
    required this.downColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final chartHeight = size.height;
    final bodyWidth = math.max(1.5, candleWidth * 0.7);

    final paint = Paint()..style = PaintingStyle.fill;
    final wickPaint = Paint()..strokeWidth = 1;

    final yRange = maxPrice - minPrice;
    if (yRange <= 0) return;

    for (var i = 0; i < data.length; i++) {
      final c = data[i];
      final open = c['open'] as double;
      final close = c['close'] as double;
      final high = c['high'] as double;
      final low = c['low'] as double;

      final isUp = close >= open;
      final color = isUp ? upColor : downColor;
      paint.color = color;
      wickPaint.color = color;

      final centerX = (i * candleWidth) + (candleWidth / 2);

      final yOpen = chartHeight - ((open - minPrice) / yRange * chartHeight);
      final yClose = chartHeight - ((close - minPrice) / yRange * chartHeight);
      final yHigh = chartHeight - ((high - minPrice) / yRange * chartHeight);
      final yLow = chartHeight - ((low - minPrice) / yRange * chartHeight);

      // Wick
      canvas.drawLine(Offset(centerX, yHigh), Offset(centerX, yLow), wickPaint);

      // Body
      final top = math.min(yOpen, yClose);
      final bottom = math.max(yOpen, yClose);
      var height = bottom - top;
      if (height < 1.0) height = 1.0;

      final bodyRect = Rect.fromLTWH(
        centerX - (bodyWidth / 2),
        top,
        bodyWidth,
        height,
      );
      canvas.drawRect(bodyRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.candleWidth != candleWidth;
  }
}
