/// Faithful Dart port of upstream `src/secondary.mjs` at commit 7ecd342
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'address.dart';

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

final _numberPattern = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$', caseSensitive: false);
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

bool _validAddress(dynamic value, String chain) => validTokenAddress(chain, _cleanString(value, 128));

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
  ['personalSlippageModifiable', 'personal_slippage_modifiable', true, false, '可按地址修改滑点或税率'],
  ['transferPausable', 'transfer_pausable', true, false, '代币转账可暂停'],
  ['blacklisted', 'is_blacklisted', true, false, '合约包含黑名单机制'],
  ['tradingCooldown', 'trading_cooldown', true, false, '合约包含交易冷却限制'],
];

const List<List<dynamic>> solSecurityRules = [
  ['mintable', 'mintable', true, true, '代币仍可增发'],
  ['freezable', 'freezable', true, true, '代币账户仍可冻结'],
  ['closable', 'closable', true, false, '代币账户可被关闭'],
  ['balanceMutableAuthority', 'balance_mutable_authority', true, false, '存在修改余额权限'],
  ['transferFeeUpgradable', 'transfer_fee_upgradable', true, false, '转账费权限可升级'],
  ['nonTransferable', 'non_transferable', true, false, '代币被标记为不可转账'],
];

dynamic _findGoPlusRecord(dynamic payload, String tokenAddress, String chain) {
  if (payload is! Map) return null;
  final result = payload['result'];
  if (result is List) {
    for (final row in result) {
      if (row is Map && _sameAddress(row['contract_address'] ?? row['address'] ?? row['mint'], tokenAddress, chain)) {
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
    if (chain == 'sol' && solSecurityRules.any((r) => result.containsKey(r[1]))) {
      return result;
    }
  }
  return null;
}

Map<String, dynamic> parseGoPlus(dynamic payload, {required String chain, required String tokenAddress}) {
  if (payload is! Map) {
    throw Exception('unexpected GoPlus JSON shape');
  }
  if (payload.containsKey('code') && payload['code'] != 1 && payload['code'] != '1') {
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
      'verdict': fatal.isNotEmpty ? 'FATAL' : complete ? 'NO_FATAL_FLAGS' : 'UNKNOWN',
      'fatal': fatal,
      'unknownFields': unknownFields,
      'fields': fields,
      'buyTax': buyTax,
      'sellTax': sellTax,
    }
  };
}

Map<String, dynamic> parseDexScreener(dynamic payload, {required String chain, required String dexChainId, required String tokenAddress}) {
  if (payload is! List) {
    throw Exception('unexpected DexScreener JSON shape');
  }
  final pairs = payload.where((pair) {
    if (pair is! Map) return false;
    final cId = _cleanString(pair['chainId'], 32);
    final baseAddr = pair['baseToken'] is Map ? (pair['baseToken'] as Map)['address'] : null;
    return cId == dexChainId && _sameAddress(baseAddr, tokenAddress, chain);
  }).map((e) => e as Map).toList();

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

  final baseToken = pair['baseToken'] is Map ? pair['baseToken'] as Map : const {};
  final priceUsd = _optionalNonNegative(pair['priceUsd']);
  final marketCap = _optionalNonNegative(pair['marketCap']);
  final fdv = _optionalNonNegative(pair['fdv']);
  final liquidityUsd = _optionalNonNegative((pair['liquidity'] as Map?)?['usd']);

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

    if ((dexSupported || goPlusSupported) && !_validAddress(address, normalizedChain)) {
      if (dexSupported) sources['dexScreener'] = {'status': 'ERROR', 'errorCode': 'INVALID_ADDRESS'};
      if (goPlusSupported) sources['goPlus'] = {'status': 'ERROR', 'errorCode': 'INVALID_ADDRESS'};
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
        if (dexSupported) _fetchDex(httpClient, dexUrl, chain: normalizedChain, dexChainId: dexChainId, tokenAddress: address),
        if (goPlusSupported) _fetchGoPlus(httpClient, goPlusUrl, chain: normalizedChain, tokenAddress: address),
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

  Future<Map<String, dynamic>> _fetchDex(http.Client hc, String url, {required String chain, required String dexChainId, required String tokenAddress}) async {
    try {
      final res = await hc.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(Duration(milliseconds: timeoutMs));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final payload = jsonDecode(res.body);
        final parsed = parseDexScreener(payload, chain: chain, dexChainId: dexChainId, tokenAddress: tokenAddress);
        return {
          'source': {'status': parsed['found'] == true ? 'OK' : 'NO_DATA'},
          'market': parsed['market'],
        };
      }
      return {'source': {'status': 'ERROR', 'errorCode': 'HTTP_${res.statusCode}'}, 'market': _emptyMarket()};
    } catch (e) {
      return {'source': {'status': 'ERROR', 'errorCode': 'REQUEST_FAILED'}, 'market': _emptyMarket()};
    }
  }

  Future<Map<String, dynamic>> _fetchGoPlus(http.Client hc, String url, {required String chain, required String tokenAddress}) async {
    try {
      final res = await hc.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(Duration(milliseconds: timeoutMs));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final payload = jsonDecode(res.body);
        final parsed = parseGoPlus(payload, chain: chain, tokenAddress: tokenAddress);
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
