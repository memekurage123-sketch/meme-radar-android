/// Faithful Dart port of upstream `src/live-leads.mjs` at commit 7ecd342
import 'dart:math' as math;
import 'address.dart';

const int liveLeadRetentionMs = 30 * 60000;

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
  final parsed = _number(value);
  if (parsed != null && parsed >= 0 && parsed == parsed.truncateToDouble()) {
    return parsed.toInt();
  }
  return null;
}

int? _clock(dynamic value) {
  final parsed = _number(value);
  return (parsed != null && parsed > 0) ? parsed.toInt() : null;
}

String _text(dynamic value, int maximum) {
  final s = (value?.toString() ?? '')
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '');
  return s.length > maximum ? s.substring(0, maximum) : s;
}

String _safeText(dynamic value, int maximum) {
  final str = value?.toString() ?? '';
  if (RegExp(
          r'gmgn_[a-z0-9]{8,}|bearer\s|api[_ -]?key|private[_ -]?key|passphrase|secret',
          caseSensitive: false)
      .hasMatch(str)) {
    return '?';
  }
  return _text(value, maximum);
}

String _identity(String chain, String address) =>
    chain == 'sol' ? address : address.toLowerCase();

String _safeUrl(dynamic value) {
  try {
    final uri = Uri.parse(value?.toString() ?? '');
    if (uri.scheme == 'https' && uri.userInfo.isEmpty) {
      final s = uri.toString();
      return s.length > 500 ? s.substring(0, 500) : s;
    }
    return '';
  } catch (_) {
    return '';
  }
}

Map<String, dynamic>? sanitizeLiveLead(dynamic source,
    [String fallbackChain = '']) {
  if (source is! Map) return null;
  final chain = _text(source['chain'] ?? fallbackChain, 24).toLowerCase();
  final address = _text(source['address'], 80);
  if (chain.isEmpty ||
      !validTokenAddress(chain, address) ||
      source['marketProvider'] != 'AVE') {
    return null;
  }

  final qualifiedAt =
      _clock(source['qualifiedAt'] ?? source['firstSeenAt'] ?? source['newAt']);
  final lastConfirmedAt =
      _clock(source['lastConfirmedAt'] ?? source['qualifiedAt']);
  final displayUntil = _clock(source['displayUntil']);

  if (qualifiedAt == null ||
      lastConfirmedAt == null ||
      displayUntil == null ||
      displayUntil <= lastConfirmedAt ||
      displayUntil - lastConfirmedAt > 60 * 60000) {
    return null;
  }

  final ageBasis = source['ageBasis']?.toString();
  return {
    'chain': chain,
    'address': _identity(chain, address),
    'marketProvider': 'AVE',
    'symbol': _safeText(source['symbol'] ?? '?', 30),
    'name': _safeText(source['name'], 80),
    'marketCap': _number(source['marketCap']),
    'liquidity': _number(source['liquidity']),
    'price': _number(source['price']),
    'createdAt': _number(source['createdAt']),
    'ageBasis': ['pool', 'trade', 'launch', 'token'].contains(ageBasis)
        ? ageBasis
        : 'unknown',
    'capturedAt': _clock(source['capturedAt']),
    'sourceUpdatedAt': _clock(source['sourceUpdatedAt']),
    'expiresAt': _clock(source['expiresAt']),
    'poolCreatedAt': _clock(source['poolCreatedAt']),
    'firstTradeAt': _clock(source['firstTradeAt']),
    'volume5m': _number(source['volume5m']),
    'buys5m': _count(source['buys5m']),
    'sells5m': _count(source['sells5m']),
    'holders': _count(source['holders']),
    'pairAddress':
        normalizePoolAddress(chain, _text(source['pairAddress'], 80)) ?? '',
    'website': _safeUrl(source['website']),
    'twitter': RegExp(r'^[A-Za-z0-9_]{1,15}$')
            .hasMatch(source['twitter']?.toString() ?? '')
        ? source['twitter'].toString()
        : '',
    'priorityBand': source['priorityBand'] == true,
    'discoveryScore': _number(source['discoveryScore']),
    'firstSeenAt': _clock(source['firstSeenAt']) ?? qualifiedAt,
    'newAt': _clock(source['newAt']) ?? qualifiedAt,
    'qualifiedAt': qualifiedAt,
    'lastConfirmedAt': lastConfirmedAt,
    'displayUntil': displayUntil,
    'displayEligible': true,
  };
}

List<Map<String, dynamic>> reconcileLiveLeads(
  dynamic previous,
  dynamic observations, {
  required String chain,
  required dynamic confirmedAt,
  int retentionMs = liveLeadRetentionMs,
}) {
  final at = _clock(confirmedAt);
  final duration = math.max(5 * 60000, math.min(60 * 60000, retentionMs));
  if (at == null || chain.isEmpty) return const [];

  final byAddress = <String, Map<String, dynamic>>{};
  final prevList = previous is List ? previous : const [];
  for (final source in prevList) {
    final lead = sanitizeLiveLead(source, chain);
    if (lead != null &&
        lead['chain'] == chain &&
        (lead['displayUntil'] as int) > at) {
      byAddress[_identity(chain, lead['address'] as String)] = lead;
    }
  }

  final obsList = observations is List ? observations : const [];
  for (final obs in obsList) {
    if (obs is! Map) continue;
    final leadData = obs['lead'] is Map ? obs['lead'] as Map : null;
    final address = _text(obs['address'] ?? leadData?['address'], 80);
    if (!validTokenAddress(chain, address)) continue;
    final key = _identity(chain, address);

    if (obs['eligible'] != true || obs['hardRejected'] == true) {
      byAddress.remove(key);
      continue;
    }

    final old = byAddress[key];
    final source = Map<String, dynamic>.from(leadData ?? obs);
    final qualifiedAt = (old?['qualifiedAt'] as int?) ??
        _clock(source['qualifiedAt'] ??
            source['firstSeenAt'] ??
            source['newAt']) ??
        at;

    source['chain'] = chain;
    source['address'] = address;
    source['qualifiedAt'] = qualifiedAt;
    source['firstSeenAt'] = (old?['firstSeenAt'] as int?) ??
        _clock(source['firstSeenAt']) ??
        qualifiedAt;
    source['newAt'] =
        (old?['newAt'] as int?) ?? _clock(source['newAt']) ?? qualifiedAt;
    source['lastConfirmedAt'] = at;
    source['displayUntil'] = at + duration;

    final lead = sanitizeLiveLead(source, chain);
    if (lead != null) {
      byAddress[key] = lead;
    }
  }

  final leads =
      byAddress.values.where((l) => (l['displayUntil'] as int) > at).toList();
  leads.sort((a, b) {
    final cDiff =
        (b['lastConfirmedAt'] as int).compareTo(a['lastConfirmedAt'] as int);
    if (cDiff != 0) return cDiff;
    final pDiff = (b['priorityBand'] == true ? 1 : 0)
        .compareTo(a['priorityBand'] == true ? 1 : 0);
    if (pDiff != 0) return pDiff;
    final vA = (a['volume5m'] as num?)?.toDouble() ?? 0.0;
    final vB = (b['volume5m'] as num?)?.toDouble() ?? 0.0;
    return vB.compareTo(vA);
  });

  return leads.take(200).toList();
}

List<Map<String, dynamic>> activeLiveLeads(dynamic source, String chain,
    [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final list = source is List ? source : const [];
  final active = <Map<String, dynamic>>[];
  for (final row in list) {
    final lead = sanitizeLiveLead(row, chain);
    if (lead != null &&
        lead['chain'] == chain &&
        (lead['displayUntil'] as int) > now) {
      active.add(lead);
    }
  }
  return active;
}
