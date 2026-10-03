/// Faithful Dart port of upstream `src/live-discovery.mjs` at commit 7ecd342
import 'address.dart';
import 'config.dart';
import 'scoring.dart';

double? _number(dynamic value) {
  if (value == null || value == '' || value is bool) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  final parsed = double.tryParse(value.toString().trim());
  return (parsed != null && parsed.isFinite) ? parsed : null;
}

int? _count(dynamic value) {
  final n = _number(value);
  return (n != null && n >= 0 && n == n.truncateToDouble()) ? n.toInt() : null;
}

String _text(dynamic value, int max) {
  final s = (value?.toString() ?? '').replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '');
  return s.length > max ? s.substring(0, max) : s;
}

String _safeText(dynamic value, int max) {
  final str = value?.toString() ?? '';
  if (RegExp(r'gmgn_[a-z0-9]{8,}|bearer\s|api[_ -]?key|private[_ -]?key', caseSensitive: false).hasMatch(str)) {
    return '?';
  }
  return _text(value, max);
}

String _identity(String chain, String value) => chain == 'sol' ? value : value.toLowerCase();

final Set<String> _waitingReasons = {
  'AVE 行情已过期或原始时间未核验',
  '市值原始时间待更新',
  '池龄或首笔成交时间未知',
  '市值数据未知',
  '流动性数据未知',
  '近5分钟成交额不足或未知',
  '价格数据未知',
};

class AveDisplayStateResult {
  final DiscoveryScreenResult screen;
  final bool visible;
  final String state;

  AveDisplayStateResult({
    required this.screen,
    required this.visible,
    required this.state,
  });
}

AveDisplayStateResult aveDisplayState(Map<String, dynamic> raw, String chain, RadarConfig config, [int? atMs]) {
  final at = atMs ?? DateTime.now().millisecondsSinceEpoch;
  final screen = discoveryScreen(raw, config.copyWith(chain: chain), at / 1000.0);
  final visible = screen.pass || screen.reasons.every((reason) => _waitingReasons.contains(reason));
  final missing = (_number(raw['liquidity']) ?? 0) <= 0 ||
      (_number(raw['volume_5m']) ?? 0) <= 0 ||
      (screen.createdAt == null || screen.createdAt! <= 0) ||
      (_number(raw['market_cap']) ?? 0) <= 0;

  return AveDisplayStateResult(
    screen: screen,
    visible: visible,
    state: screen.pass ? 'READY' : (missing ? 'PENDING' : 'STALE'),
  );
}

List<Map<String, dynamic>> normalizeLiveRows(
  List<dynamic> input,
  String chain,
  RadarConfig config, {
  List<dynamic> previous = const [],
  int? atMs,
  bool initialized = false,
}) {
  final at = atMs ?? DateTime.now().millisecondsSinceEpoch;
  final before = <String, Map<String, dynamic>>{};
  for (final row in previous) {
    if (row is Map && row['address'] != null) {
      before[_identity(chain, row['address'].toString())] = Map<String, dynamic>.from(row);
    }
  }

  final unique = <String, Map<String, dynamic>>{};
  for (final raw in input.take(300)) {
    if (raw is! Map || raw['marketProvider'] != 'AVE' || !validTokenAddress(chain, raw['address']?.toString()) || raw['chain'] != chain) {
      continue;
    }
    final rawMap = Map<String, dynamic>.from(raw);
    final address = _identity(chain, rawMap['address'].toString());
    final display = aveDisplayState(rawMap, chain, config, at);
    if (!display.visible) continue;

    final stale = !display.screen.pass;
    final old = before[address];
    final observedAt = _number(rawMap['sourceUpdatedAt'])?.toInt();
    final oldObservedAt = old != null ? _number(old['observedAt'])?.toInt() : null;
    final elapsed = (old != null && observedAt != null && oldObservedAt != null) ? observedAt - oldObservedAt : 0;
    final comparable = !stale && old?['marketProvider'] == 'AVE' && elapsed >= 5000 && elapsed <= 120000;
    final price = _number(rawMap['price']);
    final holders = _count(rawMap['holder_count']);
    final holderAt = _number(rawMap['tokenSourceUpdatedAt'] ?? rawMap['sourceUpdatedAt'])?.toInt();
    final oldHolderAt = old != null ? _number(old['holderSourceUpdatedAt'])?.toInt() ?? 0 : 0;
    final holderComparable = comparable && holderAt != null && holderAt > oldHolderAt;

    final oldPrice = old != null ? _number(old['price']) : null;
    final oldHolders = old != null ? _count(old['holders']) : null;

    unique[address] = {
      'address': address,
      'chain': chain,
      'marketProvider': 'AVE',
      'symbol': _safeText(rawMap['symbol'] ?? '?', 30),
      'name': _safeText(rawMap['name'], 80),
      'marketCap': _number(rawMap['market_cap']),
      'liquidity': _number(rawMap['liquidity']),
      'createdAt': display.screen.createdAt,
      'ageBasis': display.screen.ageBasis,
      'price': (price != null && price > 0) ? price : null,
      'volume1m': null,
      'buys1m': null,
      'sells1m': null,
      'swaps1m': null,
      'volume5m': _number(rawMap['volume_5m']),
      'buys5m': _count(rawMap['buys_5m']),
      'sells5m': _count(rawMap['sells_5m']),
      'activityWindow': '5m',
      'holders': holders,
      'smartMoney': null,
      'observedAt': observedAt,
      'capturedAt': _number(rawMap['capturedAt'])?.toInt(),
      'sourceUpdatedAt': observedAt,
      'expiresAt': _number(rawMap['expiresAt'])?.toInt(),
      'holderSourceUpdatedAt': holderAt,
      'stale': stale,
      'discoveryState': display.state,
      'firstSeenAt': old?['firstSeenAt'] ?? at,
      'newAt': old?['newAt'] ?? (initialized && old == null ? at : 0),
      'qualifiedAt': old?['qualifiedAt'] ?? (display.screen.pass ? at : null),
      'deltaWindowMs': comparable ? elapsed : null,
      'priceDelta': (comparable && price != null && price > 0 && oldPrice != null && oldPrice > 0)
          ? price / oldPrice - 1.0
          : null,
      'holdersDelta': (holderComparable && holders != null && oldHolders != null) ? holders - oldHolders : null,
      'smartDelta': null,
      'priorityBand': display.screen.priorityBand,
      'hasUnknownRisk': true,
      'auditEligible': display.screen.pass,
      'pairAddress': rawMap['pairAddress'],
      'website': rawMap['website'],
      'twitter': _safeText(rawMap['twitter_username'], 80),
    };
  }

  final rows = unique.values.toList();
  rows.sort((a, b) {
    final vA = (a['volume5m'] as num?)?.toDouble() ?? 0.0;
    final vB = (b['volume5m'] as num?)?.toDouble() ?? 0.0;
    return vB.compareTo(vA);
  });
  return rows;
}
