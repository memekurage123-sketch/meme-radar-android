/// Faithful Dart port of upstream `src/chart-risk.mjs` at commit 7ecd342
import 'dart:math' as math;

const int chartRiskVersion = 1;
const int _minute = 60000;

double? _parseNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    final parsed = double.tryParse(trimmed);
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}

class CandleBar {
  final int time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  CandleBar({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandleBar &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          open == other.open &&
          high == other.high &&
          low == other.low &&
          close == other.close &&
          volume == other.volume;

  @override
  int get hashCode => Object.hash(time, open, high, low, close, volume);
}

class ChartRiskResult {
  final int version;
  final int bars;
  final int from;
  final int to;
  final String scope;
  final List<String> reasons;
  final List<String> codes;
  final bool pass;
  final String status;
  final List<String> unknownFields;
  final double? maxConfirmedDrawdown;

  const ChartRiskResult({
    this.version = chartRiskVersion,
    required this.bars,
    required this.from,
    required this.to,
    this.scope = 'observed_1m_window',
    required this.reasons,
    required this.codes,
    required this.pass,
    required this.status,
    required this.unknownFields,
    this.maxConfirmedDrawdown,
  });

  Map<String, dynamic> toMap() => {
        'version': version,
        'bars': bars,
        'from': from,
        'to': to,
        'scope': scope,
        'reasons': reasons,
        'codes': codes,
        'pass': pass,
        'status': status,
        'unknownFields': unknownFields,
        if (maxConfirmedDrawdown != null) 'maxConfirmedDrawdown': maxConfirmedDrawdown,
      };
}

ChartRiskResult chartRiskScreen(dynamic candles, [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final rows = <int, CandleBar>{};
  var invalid = candles is! List;
  var conflict = false;

  final list = candles is List ? candles : const [];
  for (final raw in list) {
    if (raw == null) {
      invalid = true;
      continue;
    }
    dynamic rawTime = raw is Map ? (raw['time'] ?? raw['t']) : null;
    var timeD = _parseNumber(rawTime);
    if (timeD != null && timeD < 1e12) timeD *= 1000;
    final time = timeD?.toInt();

    final open = _parseNumber(raw is Map ? (raw['open'] ?? raw['o']) : null);
    final high = _parseNumber(raw is Map ? (raw['high'] ?? raw['h']) : null);
    final low = _parseNumber(raw is Map ? (raw['low'] ?? raw['l']) : null);
    final close = _parseNumber(raw is Map ? (raw['close'] ?? raw['c']) : null);
    final volume = _parseNumber(raw is Map ? (raw['volume'] ?? raw['v']) : null);

    if (time == null ||
        time <= 0 ||
        time > now + _minute ||
        open == null ||
        open <= 0 ||
        high == null ||
        high <= 0 ||
        low == null ||
        low <= 0 ||
        close == null ||
        close <= 0 ||
        high < math.max(open, close) ||
        low > math.min(open, close) ||
        volume == null ||
        volume < 0) {
      invalid = true;
      continue;
    }

    if (time + _minute > now) {
      // Do not judge a still-forming candle.
      continue;
    }

    final bar = CandleBar(time: time, open: open, high: high, low: low, close: close, volume: volume);
    final old = rows[time];
    if (old != null && old != bar) {
      conflict = true;
    }
    rows[time] = bar;
  }

  final bars = rows.values.toList()..sort((a, b) => a.time.compareTo(b.time));
  var gap = false;
  var priceGap = false;
  for (var i = 1; i < bars.length; i++) {
    if ((bars[i].time - bars[i - 1].time - _minute).abs() > 1000) gap = true;
    if ((bars[i].open / bars[i - 1].close - 1).abs() >= 0.35) priceGap = true;
  }

  final from = bars.isNotEmpty ? bars.first.time : 0;
  final to = bars.isNotEmpty ? bars.last.time + _minute : 0;

  if (invalid ||
      conflict ||
      gap ||
      priceGap ||
      bars.length < 5 ||
      bars.where((b) => b.volume > 0).length < 4 ||
      now - to > 2 * _minute) {
    return ChartRiskResult(
      bars: bars.length,
      from: from,
      to: to,
      pass: false,
      status: 'UNKNOWN',
      reasons: ['形态数据不足、冲突、断档或过期，等待复核'],
      codes: const [],
      unknownFields: const ['chartRisk.candles'],
    );
  }

  final codes = <String>[];
  final reasons = <String>[];

  // A vertical 1m jump followed by at least three narrow plateau closes.
  for (var i = 0; i < bars.length - 3; i++) {
    final bar = bars[i];
    final after = bars.sublist(i + 1, i + 4);
    final anchor = bar.open;
    final jump = bar.close / anchor - 1;
    final closes = [bar.close, ...after.map((b) => b.close)];
    final maxClose = closes.reduce(math.max);
    final minClose = closes.reduce(math.min);
    if (bar.volume > 0 &&
        after.every((b) => b.volume > 0) &&
        jump >= 0.35 &&
        (maxClose / minClose - 1) <= 0.15 &&
        (after.last.close / anchor) >= 1.30) {
      codes.push('VERTICAL_PLATEAU');
      reasons.push('单分钟跳升≥35%后窄幅平台，按风险偏好排除');
      break;
    }
  }

  // Only earlier CLOSES establish a peak. Two later closes must both be below
  // 40% of that peak; an unordered high/low in one candle cannot prove a dump.
  var peak = bars[0].volume > 0 ? bars[0].close : 0.0;
  var maxConfirmedDrawdown = 0.0;
  for (var i = 1; i < bars.length - 1; i++) {
    final laterMax = math.max(bars[i].close, bars[i + 1].close);
    final drawdown = peak > 0 ? 1.0 - laterMax / peak : 0.0;
    maxConfirmedDrawdown = math.max(maxConfirmedDrawdown, drawdown);
    if (bars[i].volume > 0 && bars[i + 1].volume > 0 && drawdown >= 0.60) {
      codes.push('SUSTAINED_COLLAPSE');
      reasons.push('已观测收盘高点后连续两根回撤≥60%，保留风险排除');
      break;
    }
    if (bars[i].volume > 0) peak = math.max(peak, bars[i].close);
  }

  return ChartRiskResult(
    bars: bars.length,
    from: from,
    to: to,
    pass: codes.isEmpty,
    status: codes.isNotEmpty ? 'REJECT' : 'CLEAR_IN_WINDOW',
    codes: codes,
    reasons: reasons,
    maxConfirmedDrawdown: maxConfirmedDrawdown,
    unknownFields: const [],
  );
}

extension _ListPush<T> on List<T> {
  void push(T value) => add(value);
}

Map<String, dynamic> applyRiskExclusion(Map<String, dynamic> row, [Map<String, dynamic> exclusions = const {}, String? chainOverride]) {
  final chain = chainOverride ?? (row['chain']?.toString() ?? '');
  final address = (row['address']?.toString() ?? '').trim();
  final key = '$chain:${chain == 'sol' ? address : address.toLowerCase()}';
  final held = exclusions[key];
  if (held == null) return row;

  final heldMap = held is Map<String, dynamic> ? held : <String, dynamic>{};
  final reasons = (heldMap['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [];

  final deep = Map<String, dynamic>.from(row['deep'] as Map? ?? {});
  final checks = Map<String, dynamic>.from(deep['checks'] as Map? ?? {});
  checks['chartRisk'] = false;
  final failed = Set<String>.from((deep['failed'] as List?)?.map((e) => e.toString()) ?? [])..add('chartRisk');

  final chartRisk = Map<String, dynamic>.from(heldMap);
  chartRisk['status'] = 'REJECT';
  chartRisk['pass'] = false;

  deep['chainPass'] = false;
  deep['checks'] = checks;
  deep['failed'] = failed.toList();
  deep['chartRisk'] = chartRisk;

  final result = Map<String, dynamic>.from(row);
  result['status'] = 'HARD_REJECT';
  result['decisionReason'] = reasons.join('；');
  result['deep'] = deep;
  return result;
}
