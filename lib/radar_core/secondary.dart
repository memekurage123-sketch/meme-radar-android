/// Faithful Dart port of upstream `src/secondary.mjs` at commit 7ecd342
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'address.dart';
import 'pool_identity.dart';

const Map<String, String> dexChainIds = {
  'sol': 'solana',
  'bsc': 'bsc',
  'base': 'base',
  'eth': 'ethereum',
};

const Map<String, String> dexBatchChainIds = dexChainIds;

const Map<String, String> goPlusEvmChainIds = {
  'eth': '1',
  'bsc': '56',
  'base': '8453',
};

final _numberPattern = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$',
    caseSensitive: false);
const int defaultMaxBytes = 1000000;

double? _optionalNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty || !_numberPattern.hasMatch(normalized)) return null;
    final parsed = double.tryParse(normalized);
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}

double? _optionalNonNegative(dynamic value) {
  final parsed = _optionalNumber(value);
  return (parsed != null && parsed >= 0) ? parsed : null;
}

double? _optionalRate(dynamic value) {
  double? parsed;
  if (value is String && value.trim().endsWith('%')) {
    final trimmed = value.trim();
    final percent = _optionalNumber(trimmed.substring(0, trimmed.length - 1));
    parsed = percent == null ? null : percent / 100.0;
  } else {
    parsed = _optionalNumber(value);
  }
  return (parsed != null && parsed >= 0 && parsed <= 1) ? parsed : null;
}

bool? _optionalBoolean(dynamic value) {
  if (value == true || value == false) return value as bool;
  if (value == 1 || value == 0) return value == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes'].contains(normalized)) return true;
    if (['0', 'false', 'no'].contains(normalized)) return false;
  }
  return null;
}

bool? _nestedBoolean(dynamic value) {
  if (value is Map) return _optionalBoolean(value['status']);
  return _optionalBoolean(value);
}

String _cleanString(dynamic value, [int maxLength = 160]) {
  if (value is! String) return '';
  final trimmed = value.trim();
  return trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed;
}

String _safeHttpUrl(dynamic value) {
  final raw = _cleanString(value, 2048);
  if (raw.isEmpty) return '';
  try {
    final url = Uri.parse(raw);
    return ['http', 'https'].contains(url.scheme) ? url.toString() : '';
  } catch (_) {
    return '';
  }
}

String _normalizedAddress(dynamic value, String chain) {
  final address = _cleanString(value, 128);
  return chain == 'sol' ? address : address.toLowerCase();
}

bool _sameAddress(dynamic left, dynamic right, String chain) {
  final a = _normalizedAddress(left, chain);
  final b = _normalizedAddress(right, chain);
  return a.isNotEmpty && b.isNotEmpty && a == b;
}

bool _validAddress(dynamic value, String chain) =>
    validTokenAddress(chain, _cleanString(value, 128));

Map<String, dynamic> _emptyMarket() => {
      'complete': false,
      'pairAddress': '',
      'dexId': '',
      'pairUrl': '',
      'symbol': '',
      'name': '',
      'priceUsd': null,
      'marketCap': null,
      'fdv': null,
      'liquidityUsd': null,
      'websites': <String>[],
    };

const List<List<dynamic>> evmSecurityRules = [
  ['isHoneypot', 'is_honeypot', true, true, 'GoPlus标记为貔貅'],
  ['openSource', 'is_open_source', false, true, '合约未开源'],
  ['mintable', 'is_mintable', true, true, '合约仍可增发'],
  ['ownerChangeBalance', 'owner_change_balance', true, true, '所有者可修改余额'],
  ['hiddenOwner', 'hidden_owner', true, true, '存在隐藏所有者'],
  ['cannotSellAll', 'cannot_sell_all', true, true, '持有人无法全部卖出'],
  ['selfDestruct', 'selfdestruct', true, false, '合约可自毁'],
  ['externalCall', 'external_call', true, false, '合约包含高风险外部调用'],
  ['slippageModifiable', 'slippage_modifiable', true, false, '滑点或税率可修改'],
  [
    'personalSlippageModifiable',
    'personal_slippage_modifiable',
    true,
    false,
    '可按地址修改滑点或税率'
  ],
  ['transferPausable', 'transfer_pausable', true, false, '代币转账可暂停'],
  ['blacklisted', 'is_blacklisted', true, false, '合约包含黑名单机制'],
  ['tradingCooldown', 'trading_cooldown', true, false, '合约包含交易冷却限制'],
];

const List<List<dynamic>> solSecurityRules = [
  ['mintable', 'mintable', true, true, '代币仍可增发'],
  ['freezable', 'freezable', true, true, '代币账户仍可冻结'],
  ['closable', 'closable', true, false, '代币账户可被关闭'],
  [
    'balanceMutableAuthority',
    'balance_mutable_authority',
    true,
    false,
    '存在修改余额权限'
  ],
  ['transferFeeUpgradable', 'transfer_fee_upgradable', true, false, '转账费权限可升级'],
  ['nonTransferable', 'non_transferable', true, false, '代币被标记为不可转账'],
];

dynamic _findGoPlusRecord(dynamic payload, String tokenAddress, String chain) {
  if (payload is! Map) return null;
  final result = payload['result'];
  if (result is List) {
    for (final row in result) {
      if (row is Map &&
          _sameAddress(row['contract_address'] ?? row['address'] ?? row['mint'],
              tokenAddress, chain)) {
        return row;
      }
    }
    return null;
  }
  if (result is Map) {
    for (final entry in result.entries) {
      if (_sameAddress(entry.key, tokenAddress, chain) && entry.value is Map) {
        return entry.value;
      }
    }
    if (chain == 'sol' &&
        solSecurityRules.any((r) => result.containsKey(r[1]))) {
      return result;
    }
  }
  return null;
}

Map<String, dynamic> parseGoPlus(dynamic payload,
    {required String chain, required String tokenAddress}) {
  if (payload is! Map) {
    throw Exception('unexpected GoPlus JSON shape');
  }
  if (payload.containsKey('code') &&
      payload['code'] != 1 &&
      payload['code'] != '1') {
    throw Exception('GoPlus rejected request');
  }
  final record = _findGoPlusRecord(payload, tokenAddress, chain);
  if (record is! Map) {
    return {
      'found': false,
      'security': {
        'complete': false,
        'verdict': 'UNKNOWN',
        'fatal': <Map<String, String>>[],
        'unknownFields': ['tokenSecurity'],
        'fields': <String, dynamic>{},
        'buyTax': null,
        'sellTax': null,
      }
    };
  }
  final rules = chain == 'sol' ? solSecurityRules : evmSecurityRules;
  final fields = <String, dynamic>{};
  final fatal = <Map<String, String>>[];
  final unknownFields = <String>[];

  for (final rule in rules) {
    final field = rule[0] as String;
    final rawField = rule[1] as String;
    final fatalWhen = rule[2] as bool;
    final reason = rule[4] as String;

    final value = _nestedBoolean(record[rawField]);
    fields[field] = value;
    if (value == null) {
      unknownFields.add(field);
    } else if (value == fatalWhen) {
      fatal.add({'field': field, 'reason': reason});
    }
  }

  final buyTax = chain == 'sol' ? null : _optionalRate(record['buy_tax']);
  final sellTax = chain == 'sol' ? null : _optionalRate(record['sell_tax']);
  if (chain != 'sol') {
    if (buyTax == null) unknownFields.add('buyTax');
    if (sellTax == null) unknownFields.add('sellTax');
  }

  final complete = unknownFields.isEmpty;
  return {
    'found': true,
    'security': {
      'complete': complete,
      'verdict': fatal.isNotEmpty
          ? 'FATAL'
          : complete
              ? 'NO_FATAL_FLAGS'
              : 'UNKNOWN',
      'fatal': fatal,
      'unknownFields': unknownFields,
      'fields': fields,
      'buyTax': buyTax,
      'sellTax': sellTax,
    }
  };
}

Map<String, dynamic> parseDexScreener(dynamic payload,
    {required String chain,
    required String dexChainId,
    required String tokenAddress}) {
  if (payload is! List) {
    throw Exception('unexpected DexScreener JSON shape');
  }
  final pairs = payload
      .where((pair) {
        if (pair is! Map) return false;
        final cId = _cleanString(pair['chainId'], 32);
        final baseAddr = pair['baseToken'] is Map
            ? (pair['baseToken'] as Map)['address']
            : null;
        return cId == dexChainId && _sameAddress(baseAddr, tokenAddress, chain);
      })
      .map((e) => e as Map)
      .toList();

  if (pairs.isEmpty) {
    return {'found': false, 'market': _emptyMarket()};
  }

  pairs.sort((a, b) {
    final bLiq = _optionalNonNegative((b['liquidity'] as Map?)?['usd']) ?? -1.0;
    final aLiq = _optionalNonNegative((a['liquidity'] as Map?)?['usd']) ?? -1.0;
    return bLiq.compareTo(aLiq);
  });

  final pair = pairs[0];
  final infoWebsites = (pair['info'] as Map?)?['websites'];
  final websites = (infoWebsites is List ? infoWebsites : const [])
      .map((row) => row is Map ? _safeHttpUrl(row['url']) : '')
      .where((s) => s.isNotEmpty)
      .toSet()
      .take(10)
      .toList();

  final baseToken =
      pair['baseToken'] is Map ? pair['baseToken'] as Map : const {};
  final priceUsd = _optionalNonNegative(pair['priceUsd']);
  final marketCap = _optionalNonNegative(pair['marketCap']);
  final fdv = _optionalNonNegative(pair['fdv']);
  final liquidityUsd =
      _optionalNonNegative((pair['liquidity'] as Map?)?['usd']);

  final market = {
    'complete': priceUsd != null && marketCap != null && liquidityUsd != null,
    'pairAddress': _cleanString(pair['pairAddress'], 128),
    'dexId': _cleanString(pair['dexId'], 64),
    'pairUrl': _safeHttpUrl(pair['url']),
    'symbol': _cleanString(baseToken['symbol'], 40),
    'name': _cleanString(baseToken['name'], 120),
    'priceUsd': priceUsd,
    'marketCap': marketCap,
    'fdv': fdv,
    'liquidityUsd': liquidityUsd,
    'websites': websites,
  };
  return {'found': true, 'market': market};
}

class SecondaryValidator {
  final http.Client? client;
  final int timeoutMs;
  final Map<String, double> conflictThresholds;

  SecondaryValidator({
    this.client,
    this.timeoutMs = 8000,
    Map<String, double>? conflictThresholds,
  }) : conflictThresholds = {
          'price': conflictThresholds?['price'] ?? 0.10,
          'marketCap': conflictThresholds?['marketCap'] ?? 0.20,
          'liquidity': conflictThresholds?['liquidity'] ?? 0.25,
        };

  Future<Map<String, dynamic>> validate({
    required String chain,
    required String tokenAddress,
    Map<String, dynamic> primary = const {},
  }) async {
    final normalizedChain = _cleanString(chain, 24).toLowerCase();
    final address = _cleanString(tokenAddress, 128);
    final dexChainId = dexChainIds[normalizedChain];
    final goPlusChainId = goPlusEvmChainIds[normalizedChain];
    final goPlusSupported = normalizedChain == 'sol' || (goPlusChainId != null);
    final dexSupported = dexChainId != null;

    final market = _emptyMarket();
    var security = {
      'complete': false,
      'verdict': 'UNSUPPORTED',
      'fatal': <dynamic>[],
      'unknownFields': ['tokenSecurity'],
      'fields': <String, dynamic>{},
      'buyTax': null,
      'sellTax': null,
    };
    final sources = <String, dynamic>{
      'dexScreener': {'status': dexSupported ? 'PENDING' : 'UNSUPPORTED'},
      'goPlus': {'status': goPlusSupported ? 'PENDING' : 'UNSUPPORTED'},
    };

    if ((dexSupported || goPlusSupported) &&
        !_validAddress(address, normalizedChain)) {
      if (dexSupported) {
        sources['dexScreener'] = {
          'status': 'ERROR',
          'errorCode': 'INVALID_ADDRESS'
        };
      }
      if (goPlusSupported) {
        sources['goPlus'] = {'status': 'ERROR', 'errorCode': 'INVALID_ADDRESS'};
      }
      return {
        'status': 'DEGRADED',
        'complete': false,
        'checkedAt': DateTime.now().millisecondsSinceEpoch,
        'chain': normalizedChain,
        'tokenAddress': address,
        'sources': sources,
        'market': market,
        'security': security,
        'conflicts': <dynamic>[],
      };
    }

    final dexUrl = dexSupported
        ? 'https://api.dexscreener.com/token-pairs/v1/$dexChainId/${Uri.encodeComponent(address)}'
        : '';
    final goPlusUrl = !goPlusSupported
        ? ''
        : normalizedChain == 'sol'
            ? 'https://api.gopluslabs.io/api/v1/solana/token_security?contract_addresses=${Uri.encodeComponent(address)}'
            : 'https://api.gopluslabs.io/api/v1/token_security/$goPlusChainId?contract_addresses=${Uri.encodeComponent(address)}';

    final httpClient = client ?? http.Client();
    try {
      final futures = <Future<dynamic>>[
        if (dexSupported)
          _fetchDex(httpClient, dexUrl,
              chain: normalizedChain,
              dexChainId: dexChainId,
              tokenAddress: address),
        if (goPlusSupported)
          _fetchGoPlus(httpClient, goPlusUrl,
              chain: normalizedChain, tokenAddress: address),
      ];
      final results = await Future.wait(futures);

      var idx = 0;
      if (dexSupported) {
        final res = results[idx++] as Map<String, dynamic>;
        sources['dexScreener'] = res['source'];
        market.addAll(res['market'] as Map<String, dynamic>);
      }
      if (goPlusSupported) {
        final res = results[idx++] as Map<String, dynamic>;
        sources['goPlus'] = res['source'];
        security = res['security'] as Map<String, dynamic>;
      }
    } finally {
      if (client == null) httpClient.close();
    }

    final complete = sources['dexScreener']?['status'] == 'OK' &&
        sources['goPlus']?['status'] == 'OK' &&
        market['complete'] == true &&
        security['complete'] == true;

    return {
      'status': complete ? 'COMPLETE' : 'DEGRADED',
      'complete': complete,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
      'chain': normalizedChain,
      'tokenAddress': address,
      'sources': sources,
      'market': market,
      'security': security,
      'conflicts': <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> _fetchDex(http.Client hc, String url,
      {required String chain,
      required String dexChainId,
      required String tokenAddress}) async {
    try {
      final res = await hc.get(Uri.parse(url), headers: {
        'Accept': 'application/json'
      }).timeout(Duration(milliseconds: timeoutMs));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final payload = jsonDecode(res.body);
        final parsed = parseDexScreener(payload,
            chain: chain, dexChainId: dexChainId, tokenAddress: tokenAddress);
        return {
          'source': {'status': parsed['found'] == true ? 'OK' : 'NO_DATA'},
          'market': parsed['market'],
        };
      }
      return {
        'source': {'status': 'ERROR', 'errorCode': 'HTTP_${res.statusCode}'},
        'market': _emptyMarket()
      };
    } catch (e) {
      return {
        'source': {'status': 'ERROR', 'errorCode': 'REQUEST_FAILED'},
        'market': _emptyMarket()
      };
    }
  }

  Future<Map<String, dynamic>> _fetchGoPlus(http.Client hc, String url,
      {required String chain, required String tokenAddress}) async {
    try {
      final res = await hc.get(Uri.parse(url), headers: {
        'Accept': 'application/json'
      }).timeout(Duration(milliseconds: timeoutMs));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final payload = jsonDecode(res.body);
        final parsed =
            parseGoPlus(payload, chain: chain, tokenAddress: tokenAddress);
        return {
          'source': {'status': parsed['found'] == true ? 'OK' : 'NO_DATA'},
          'security': parsed['security'],
        };
      }
      return {
        'source': {'status': 'ERROR', 'errorCode': 'HTTP_${res.statusCode}'},
        'security': {
          'complete': false,
          'verdict': 'UNKNOWN',
          'fatal': <dynamic>[],
          'unknownFields': ['tokenSecurity'],
          'fields': <String, dynamic>{},
          'buyTax': null,
          'sellTax': null,
        }
      };
    } catch (e) {
      return {
        'source': {'status': 'ERROR', 'errorCode': 'REQUEST_FAILED'},
        'security': {
          'complete': false,
          'verdict': 'UNKNOWN',
          'fatal': <dynamic>[],
          'unknownFields': ['tokenSecurity'],
          'fields': <String, dynamic>{},
          'buyTax': null,
          'sellTax': null,
        }
      };
    }
  }
}

int? _optionalCount(dynamic value) {
  final n = _optionalNumber(value);
  return (n != null && n >= 0 && n == n.truncateToDouble()) ? n.toInt() : null;
}

Map<String, Map<String, dynamic>> parseDexBatch(
  dynamic payload, {
  required String chain,
  required String dexChainId,
  required List<String> tokenAddresses,
  required int capturedAt,
}) {
  if (payload is! List || payload.length > 1000) {
    throw Exception('unexpected DexScreener batch JSON shape');
  }
  final requested =
      tokenAddresses.map((v) => _normalizedAddress(v, chain)).toSet();
  final best = <String, Map<String, dynamic>>{};

  for (final pair in payload) {
    if (pair is! Map || _cleanString(pair['chainId'], 32) != dexChainId) {
      continue;
    }
    final baseAddress =
        _normalizedAddress(pair['baseToken']?['address'], chain);
    final quoteAddress =
        _normalizedAddress(pair['quoteToken']?['address'], chain);
    final members = [baseAddress, quoteAddress]
        .where((addr) => requested.contains(addr))
        .toList();
    final pairAddress = pair['pairAddress']?.toString();
    if (members.isEmpty || !validPoolAddress(chain, pairAddress)) continue;

    final liquidity = _optionalNonNegative(pair['liquidity']?['usd']);
    final volume5m = _optionalNonNegative(pair['volume']?['m5']);
    final txns = pair['txns'] is Map ? pair['txns'] as Map : const {};
    final m5 = txns['m5'] is Map ? txns['m5'] as Map : const {};
    final buys5m = _optionalCount(m5['buys']);
    final sells5m = _optionalCount(m5['sells']);
    final createdAt = _optionalNonNegative(pair['pairCreatedAt'])?.toInt();
    if (liquidity == null ||
        volume5m == null ||
        createdAt == null ||
        createdAt <= 0 ||
        createdAt > capturedAt + 300000) {
      continue;
    }

    final poolMarket = <String, dynamic>{
      'pairAddress': _cleanString(pairAddress, 128),
      'dexId': _cleanString(pair['dexId'], 64),
      'liquidity': liquidity,
      'volume5m': volume5m,
      'pairCreatedAt': createdAt,
      'swaps5m': (buys5m != null && sells5m != null) ? buys5m + sells5m : null,
    };

    for (final tokenAddress in members) {
      final isBase = tokenAddress == baseAddress;
      final market = <String, dynamic>{
        ...poolMarket,
        'priceUsd': isBase ? _optionalNonNegative(pair['priceUsd']) : null,
        'marketCap': isBase ? _optionalNonNegative(pair['marketCap']) : null,
        'fdv': isBase ? _optionalNonNegative(pair['fdv']) : null,
        'buys5m': isBase ? buys5m : null,
        'sells5m': isBase ? sells5m : null,
      };

      final previous = best[tokenAddress];
      if (previous == null ||
          (market['liquidity'] as double) >
              (previous['liquidity'] as double)) {
        best[tokenAddress] = market;
      }
    }
  }

  return best;
}

List<Map<String, dynamic>> overlayDexMarket(
  List<Map<String, dynamic>> rows,
  String chain,
  Map<String, Map<String, dynamic>> marketByToken,
  int capturedAt,
  int ttlMs,
) {
  return rows.map((row) {
    final addr = _normalizedAddress(row['address'], chain);
    final market = marketByToken[addr];
    if (market == null) return row;

    final evidence = verifiedAvePoolEvidence(row, chain);
    final evidencePair = evidence?.pair ?? '';
    if (evidencePair.isNotEmpty &&
        evidencePair != _normalizedAddress(market['pairAddress'], chain)) {
      return row;
    }

    final cleanRow = evidence != null
        ? Map<String, dynamic>.from(row)
        : (Map<String, dynamic>.from(row)
          ..remove('first_trade_at')
          ..remove('firstTradeAt')
          ..remove('last_trade_at')
          ..remove('lastTradeAt')
          ..remove('poolEvidence'));

    final marketCap = market['marketCap'] ?? cleanRow['market_cap'];
    final priceUsd = market['priceUsd'] as double?;
    final marketOverlayPriceUpdated = priceUsd != null && priceUsd > 0;
    final price = marketOverlayPriceUpdated ? priceUsd : null;

    final pairCreatedAtMs = market['pairCreatedAt'] as int;

    return <String, dynamic>{
      ...cleanRow,
      if (price != null) 'price': price,
      if (marketCap != null) 'market_cap': marketCap,
      'marketCapSourceUpdatedAt': market['marketCap'] != null
          ? capturedAt
          : cleanRow['marketCapSourceUpdatedAt'],
      'marketCapCapturedAt': market['marketCap'] != null
          ? capturedAt
          : cleanRow['marketCapCapturedAt'],
      'marketCapExpiresAt': market['marketCap'] != null
          ? capturedAt + ttlMs
          : cleanRow['marketCapExpiresAt'],
      'liquidity': market['liquidity'],
      'volume_5m': market['volume5m'],
      'buys_5m': market['buys5m'],
      'sells_5m': market['sells5m'],
      'swaps_5m': market['swaps5m'],
      'buy_volume_5m': null,
      'sell_volume_5m': null,
      'pool_created_at': pairCreatedAtMs ~/ 1000,
      'poolCreatedAt': pairCreatedAtMs,
      'pairAddress': market['pairAddress'],
      'dexId': market['dexId'],
      'ageBasis': 'pool',
      'activityWindow': '5m',
      'tokenSourceUpdatedAt':
          cleanRow['tokenSourceUpdatedAt'] ?? cleanRow['sourceUpdatedAt'],
      'tokenCapturedAt': cleanRow['tokenCapturedAt'] ?? cleanRow['capturedAt'],
      'capturedAt': capturedAt,
      'sourceUpdatedAt': capturedAt,
      'sampledAt': capturedAt,
      'expiresAt': capturedAt + ttlMs,
      'stale': false,
      'marketOverlayProvider': 'DEXSCREENER',
      'marketOverlayCapturedAt': capturedAt,
      'marketOverlayPriceUpdated': marketOverlayPriceUpdated,
    };
  }).toList();
}

class DexBatchMarketOverlay {
  final http.Client _client;
  final bool _ownsClient;
  final int timeoutMs;
  final int ttlMs;
  final int staleTtlMs;
  final Map<String, _DexCacheEntry> _cache = {};
  final Map<String, int> _batchTurns = {};

  DexBatchMarketOverlay({
    http.Client? client,
    this.timeoutMs = 8000,
    this.ttlMs = 20000,
    this.staleTtlMs = 60000,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<Map<String, dynamic>>> enrich(
    String chain,
    List<Map<String, dynamic>> rows, {
    double minMarketCap = 0,
    double maxMarketCap = double.infinity,
  }) async {
    if (rows.isEmpty) return rows;
    final normalizedChain = _cleanString(chain, 24).toLowerCase();
    final dexChainId = dexBatchChainIds[normalizedChain];
    if (dexChainId == null) return rows;

    final eligible = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      final mc = _optionalNonNegative(row['market_cap']);
      final addr = row['address']?.toString() ?? '';
      if (row['marketProvider'] == 'AVE' &&
          mc != null &&
          mc >= minMarketCap &&
          mc <= maxMarketCap &&
          validTokenAddress(normalizedChain, addr)) {
        final norm = _normalizedAddress(addr, normalizedChain);
        if (seen.add(norm)) {
          eligible.add(norm);
          if (eligible.length >= 300) break;
        }
      }
    }
    if (eligible.isEmpty) return rows;

    final now = DateTime.now().millisecondsSinceEpoch;
    final cursor = _batchTurns[normalizedChain] ?? 0;
    final offset = cursor % eligible.length;
    final selected = eligible.skip(offset).take(30).toList();
    _batchTurns[normalizedChain] = offset + selected.length;

    final key = '$normalizedChain:${(List<String>.from(selected)..sort()).join(',')}';
    final cached = _cache[key];
    if (cached != null && cached.until > now) {
      return overlayDexMarket(
          rows, normalizedChain, cached.marketByToken, cached.capturedAt, ttlMs);
    }

    try {
      final encodedAddrs = selected.map(Uri.encodeComponent).join(',');
      final url =
          'https://api.dexscreener.com/tokens/v1/$dexChainId/$encodedAddrs';
      final res = await _client.get(Uri.parse(url), headers: {
        'Accept': 'application/json'
      }).timeout(Duration(milliseconds: timeoutMs));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final payload = jsonDecode(res.body);
        final capturedAt = DateTime.now().millisecondsSinceEpoch;
        final marketByToken = parseDexBatch(
          payload,
          chain: normalizedChain,
          dexChainId: dexChainId,
          tokenAddresses: selected,
          capturedAt: capturedAt,
        );

        final entry = _DexCacheEntry(
          marketByToken: marketByToken,
          capturedAt: capturedAt,
          until: capturedAt + ttlMs,
          staleUntil: capturedAt + staleTtlMs,
        );
        if (!_cache.containsKey(key) && _cache.length >= 16) {
          _cache.remove(_cache.keys.first);
        }
        _cache[key] = entry;

        return overlayDexMarket(
            rows, normalizedChain, marketByToken, capturedAt, ttlMs);
      }
    } catch (_) {
      if (cached != null && cached.staleUntil > now) {
        return overlayDexMarket(
            rows, normalizedChain, cached.marketByToken, cached.capturedAt, ttlMs);
      }
    }

    return rows;
  }
}

class _DexCacheEntry {
  final Map<String, Map<String, dynamic>> marketByToken;
  final int capturedAt;
  final int until;
  final int staleUntil;

  _DexCacheEntry({
    required this.marketByToken,
    required this.capturedAt,
    required this.until,
    required this.staleUntil,
  });
}
