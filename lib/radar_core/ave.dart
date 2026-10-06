/// Faithful Dart port of upstream `src/ave.mjs` at commit 7ecd342
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'address.dart';

const Map<String, String> aveChains = {
  'bsc': 'bsc',
  'eth': 'eth',
  'base': 'base',
  'sol': 'solana',
  'robinhood': 'robinhood',
  'arc': 'arc',
  'stable': 'stable',
};

const String aveOrigin = 'https://prod.ave-api.com';

class AveLimits {
  final int intervalMs;
  final int timeoutMs;
  final int maxBytes;
  final int dailyCu;
  final int totalCu;
  final int hourlyCu;
  final int trendingTtlMs;
  final int detailsTtlMs;
  final int klinesTtlMs;

  const AveLimits({
    this.intervalMs = 60000,
    this.timeoutMs = 12000,
    this.maxBytes = 1048576,
    this.dailyCu = 30000,
    this.totalCu = 1000000,
    this.hourlyCu = 1250,
    this.trendingTtlMs = 210000,
    this.detailsTtlMs = 30000,
    this.klinesTtlMs = 60000,
  });
}

const AveLimits defaultAveLimits = AveLimits();

class AveException implements Exception {
  final String code;
  final String message;
  final int status;
  final int? retryAt;

  AveException(this.code, this.message, [this.status = 502, this.retryAt]);

  @override
  String toString() => 'AveException($code): $message (status: $status)';
}

double? _numeric(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return (d.isFinite && d >= 0) ? d : null;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    return (parsed != null && parsed.isFinite && parsed >= 0) ? parsed : null;
  }
  return null;
}

double? _signedNumeric(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}

int? _seconds(dynamic value) {
  final num? n =
      value is num ? value : (value is String ? num.tryParse(value) : null);
  if (n != null && n > 0 && n < 100000000000 && n == n.truncateToDouble()) {
    return n.toInt();
  }
  return null;
}

int? _upstreamTime(dynamic value) {
  final s = _seconds(value);
  return s == null ? null : s * 1000;
}

String _text(dynamic value, int limit) {
  if (value is! String) return '';
  final s = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '');
  return s.length > limit ? s.substring(0, limit) : s;
}

class AveClient {
  final String apiKey;
  final http.Client _client;
  final AveLimits limits;
  final bool _ownsClient;

  AveClient({
    required this.apiKey,
    http.Client? client,
    this.limits = defaultAveLimits,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    if (apiKey.trim().isEmpty) {
      throw AveException('AVE_CONFIG', 'AVE 行情凭证未配置');
    }
    final uri = Uri.parse('$aveOrigin$path');
    final response = await _client.get(
      uri,
      headers: {
        'X-API-KEY': apiKey.trim(),
        'Accept': 'application/json',
      },
    ).timeout(Duration(milliseconds: limits.timeoutMs));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AveException('AVE_AUTH', 'AVE 行情凭证或权限未通过', response.statusCode);
    }
    if (response.statusCode == 429) {
      throw AveException('AVE_RATE_LIMITED', 'AVE 行情限流，已进入冷却', 429);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AveException('AVE_UPSTREAM',
          'AVE 行情请求未成功: HTTP ${response.statusCode}', response.statusCode);
    }

    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw AveException('AVE_SCHEMA', 'AVE 行情返回非有效 JSON');
    }

    if (body is! Map) {
      throw AveException('AVE_SCHEMA', 'AVE 行情格式不正确');
    }
    return Map<String, dynamic>.from(body);
  }

  /// Trending tokens
  Future<Map<String, dynamic>> trending(String chain,
      {int page = 0, int pageSize = 100}) async {
    final apiChain = aveChains[chain];
    if (apiChain == null) throw AveException('AVE_INPUT', '不支持的链: $chain');

    final path =
        '/v2/tokens/trending?chain=$apiChain&current_page=$page&page_size=$pageSize';
    final raw = await _get(path);
    final capturedAt = DateTime.now().millisecondsSinceEpoch;

    final data = (raw['status'] == 1 && raw['data'] is Map)
        ? raw['data'] as Map
        : (raw['tokens'] is List ? raw : null);
    if (data == null) throw AveException('AVE_SCHEMA', 'AVE trending 数据结构不匹配');

    final tokens = data['tokens'];
    if (tokens is! List) {
      throw AveException('AVE_SCHEMA', 'AVE trending tokens 缺失');
    }

    final rows = <Map<String, dynamic>>[];
    for (final item in tokens) {
      if (item is! Map) continue;
      final rawToken =
          item['token']?.toString() ?? item['address']?.toString() ?? '';
      final ca = normalizeTokenAddress(chain, rawToken);
      if (ca == null) continue;

      final price = _numeric(item['current_price_usd']);
      if (price == null || price <= 0) continue;

      final mainPair =
          normalizePoolAddress(chain, item['main_pair']?.toString());
      final sampledAt = _upstreamTime(item['updated_at']);
      final expiresAt =
          sampledAt == null ? null : capturedAt + limits.detailsTtlMs;
      final launchedAt =
          _seconds(item['launch_at']) ?? _seconds(item['created_at']);
      final ageBasis = item['launch_at'] != null
          ? 'launch'
          : (item['created_at'] != null ? 'token' : null);

      final row = {
        'address': ca,
        'chain': chain,
        'apiChain': apiChain,
        'symbol': _text(item['symbol'], 40),
        'name': _text(item['name'], 100),
        'source': 'AVE',
        'marketProvider': 'AVE',
        if (mainPair != null) 'pairAddress': mainPair,
        'price': price,
        'market_cap': _numeric(item['market_cap']),
        'holder_count': _numeric(item['holders'])?.toInt(),
        'tvl': _numeric(item['tvl']),
        'marketCapSourceUpdatedAt': sampledAt,
        'marketCapCapturedAt': capturedAt,
        'marketCapExpiresAt': expiresAt,
        'liquidity': _numeric(item['main_pair_tvl']) ?? _numeric(item['tvl']),
        'liquidityBasis': item['main_pair_tvl'] != null
            ? 'main_pair_tvl'
            : (item['tvl'] != null ? 'token_tvl' : null),
        'creation_timestamp': launchedAt,
        'launch_at': _seconds(item['launch_at']),
        'token_created_at': _seconds(item['created_at']),
        'ageBasis': ageBasis,
        'volume_5m': _numeric(item['token_tx_volume_usd_5m']),
        'buy_volume_5m': _numeric(item['token_buy_volume_u_5m']) ??
            _numeric(item['token_buy_tx_volume_usd_5m']),
        'sell_volume_5m': _numeric(item['token_sell_volume_u_5m']) ??
            _numeric(item['token_sell_tx_volume_usd_5m']),
        'swaps_5m': _numeric(item['token_tx_count_5m'])?.toInt(),
        'buys_5m': _numeric(item['token_buy_tx_count_5m'])?.toInt(),
        'sells_5m': _numeric(item['token_sell_tx_count_5m'])?.toInt(),
        'price_change_percent5m':
            _signedNumeric(item['token_price_change_5m']) == null
                ? null
                : _signedNumeric(item['token_price_change_5m'])! / 100.0,
        'rug_ratio': null,
        'bundler_rate': null,
        'rat_trader_amount_rate': null,
        'is_wash_trading': null,
        'is_honeypot': null,
        'capturedAt': capturedAt,
        'sourceUpdatedAt': sampledAt,
        'sampledAt': sampledAt,
        'expiresAt': expiresAt,
        'stale': false,
        'identityBasis': item['token'] == null && item['address'] == null
            ? 'request_path'
            : 'response',
        'aveUrl': 'https://pro.ave.ai/token/$ca-$apiChain?ref=0001',
      };
      rows.add(row);
    }

    return {
      'rows': rows,
      'capturedAt': capturedAt,
      'nextPage': data['next_page'],
    };
  }

  /// Token details + pairs list
  Future<Map<String, dynamic>> tokenDetails(
      String chain, String tokenAddress) async {
    final apiChain = aveChains[chain];
    if (apiChain == null) throw AveException('AVE_INPUT', '不支持的链: $chain');
    final ca = normalizeTokenAddress(chain, tokenAddress);
    if (ca == null) throw AveException('AVE_INPUT', '无效的代币地址: $tokenAddress');

    final path = '/v2/tokens/$ca-$apiChain';
    final raw = await _get(path);
    final capturedAt = DateTime.now().millisecondsSinceEpoch;

    final data =
        (raw['status'] == 1 && raw['data'] is Map) ? raw['data'] as Map : raw;
    final token = data['token'] is Map ? data['token'] as Map : null;
    if (token == null) throw AveException('AVE_SCHEMA', 'AVE token details 缺失');

    final pairsRaw = data['pairs'];
    final pairs = <Map<String, dynamic>>[];
    if (pairsRaw is List) {
      for (final p in pairsRaw) {
        if (p is! Map) continue;
        final pool = normalizePoolAddress(chain, p['pair']?.toString());
        if (pool == null) continue;
        pairs.add({
          'chain': chain,
          'address': ca,
          'pair': pool,
          'amm': _text(p['amm'], 80),
          'sourceUpdatedAt': _upstreamTime(p['updated_at']),
        });
      }
    }

    return {
      'token': token,
      'pairs': pairs,
      'capturedAt': capturedAt,
    };
  }

  /// Single pool / pair details
  Future<Map<String, dynamic>> pairDetails(
      String chain, String pairAddress) async {
    final apiChain = aveChains[chain];
    if (apiChain == null) throw AveException('AVE_INPUT', '不支持的链: $chain');
    final pair = normalizePoolAddress(chain, pairAddress);
    if (pair == null) throw AveException('AVE_INPUT', '无效的交易对地址: $pairAddress');

    final path = '/v2/pairs/$pair-$apiChain';
    final raw = await _get(path);
    final capturedAt = DateTime.now().millisecondsSinceEpoch;

    final data =
        (raw['status'] == 1 && raw['data'] is Map) ? raw['data'] as Map : raw;
    final token0 =
        normalizeTokenAddress(chain, data['token0_address']?.toString());
    final token1 =
        normalizeTokenAddress(chain, data['token1_address']?.toString());
    final target =
        normalizeTokenAddress(chain, data['target_token']?.toString());

    if (token0 == null ||
        token1 == null ||
        token0 == token1 ||
        target == null) {
      throw AveException('AVE_SCHEMA', '交易对 token0/token1 数据不完整');
    }

    final result = <String, dynamic>{
      'pair': pair,
      'chain': chain,
      'amm': _text(data['amm'], 80),
      'token0_address': token0,
      'token1_address': token1,
      'target_token': target,
      'created_at': _seconds(data['created_at']),
      'updated_at': data['updated_at'],
      'first_trade_at': _seconds(data['first_trade_at']),
      'last_trade_at': _seconds(data['last_trade_at']),
      'token0_price_usd': _numeric(data['token0_price_usd']),
      'token1_price_usd': _numeric(data['token1_price_usd']),
      'tvl': _numeric(data['tvl']),
      'market_cap': _numeric(data['market_cap']),
      'fdv': _numeric(data['fdv']),
      'price_ath_u': _numeric(data['price_ath_u']),
      'volume_u_1m': _numeric(data['volume_u_1m']),
      'volume_u_5m': _numeric(data['volume_u_5m']),
      'volume_u_1h': _numeric(data['volume_u_1h']),
      'volume_u_24h': _numeric(data['volume_u_24h']),
      'buy_volume_u_5m': _numeric(data['buy_volume_u_5m']),
      'sell_volume_u_5m': _numeric(data['sell_volume_u_5m']),
      'price_change_1m': _signedNumeric(data['price_change_1m']),
      'price_change_5m': _signedNumeric(data['price_change_5m']),
      'price_change_1h': _signedNumeric(data['price_change_1h']),
      'price_change_24h': _signedNumeric(data['price_change_24h']),
      'buys_tx_24h_count': _numeric(data['buys_tx_24h_count'])?.toInt(),
      'sells_tx_24h_count': _numeric(data['sells_tx_24h_count'])?.toInt(),
      'sourceUpdatedAt': _upstreamTime(data['updated_at']),
      'capturedAt': capturedAt,
      'source': 'AVE',
      'identityBasis': 'response',
    };

    return result;
  }

  /// 1-minute K-lines for token
  Future<Map<String, dynamic>> tokenKlines(String chain, String tokenAddress,
      {int interval = 1, int limit = 60}) async {
    final apiChain = aveChains[chain];
    if (apiChain == null) throw AveException('AVE_INPUT', '不支持的链: $chain');
    final ca = normalizeTokenAddress(chain, tokenAddress);
    if (ca == null) throw AveException('AVE_INPUT', '无效的代币地址: $tokenAddress');

    final path =
        '/v2/klines/token/$ca-$apiChain?interval=$interval&limit=$limit';
    final raw = await _get(path);
    final capturedAt = DateTime.now().millisecondsSinceEpoch;

    final data =
        (raw['status'] == 1 && raw['data'] is Map) ? raw['data'] as Map : raw;
    final points = data['points'];
    if (points is! List) throw AveException('AVE_SCHEMA', 'K线 points 缺失');

    final list = <Map<String, dynamic>>[];
    for (final p in points) {
      if (p is! Map) continue;
      final t = _seconds(p['time']);
      if (t == null) continue;
      final open = _numeric(p['open']);
      final high = _numeric(p['high']);
      final low = _numeric(p['low']);
      final close = _numeric(p['close']);
      final volume = _numeric(p['volume']) ?? 0.0;
      if (open == null || high == null || low == null || close == null) {
        continue;
      }

      list.add({
        'time': t * 1000,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      });
    }

    list.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
    return {
      'chain': chain,
      'address': ca,
      'list': list,
      'capturedAt': capturedAt,
      'sourceUpdatedAt':
          list.isNotEmpty ? (list.last['time'] as int) + 60000 : null,
    };
  }

  /// High-level discover & enrichment method matching upstream
  Future<List<Map<String, dynamic>>> discover(String chain,
      {int limit = 6, bool enrichPairs = true}) async {
    final trendingRes = await trending(chain);
    final rows = List<Map<String, dynamic>>.from(trendingRes['rows'] as List);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!enrichPairs) return rows;

    var enrichedCount = 0;
    for (var i = 0; i < rows.length && enrichedCount < limit; i++) {
      final row = rows[i];
      final pairAddr = row['pairAddress']?.toString();
      if (pairAddr == null || pairAddr.isEmpty) continue;

      try {
        final pair = await pairDetails(chain, pairAddr);
        final enriched = _applyPairMarket(row, pair, now);
        rows[i] = enriched;
        enrichedCount++;
      } catch (_) {
        // Continue if pair lookup fails for an individual pool
      }
    }
    return rows;
  }

  Map<String, dynamic> _applyPairMarket(
      Map<String, dynamic> row, Map<String, dynamic> pair, int now) {
    final address = row['address']?.toString() ?? '';
    final target = pair['target_token']?.toString();
    final token0 = pair['token0_address']?.toString();
    final token1 = pair['token1_address']?.toString();

    if (pair['chain'] != row['chain'] ||
        target != address ||
        (token0 != address && token1 != address)) {
      return row;
    }

    final price = token0 == address
        ? (pair['token0_price_usd'] as num?)
        : (pair['token1_price_usd'] as num?);
    if (price == null || price <= 0) return row;

    final capturedAt = pair['capturedAt'] as int? ?? now;
    final sampledAt = pair['sourceUpdatedAt'] as int?;
    final expiresAt =
        sampledAt == null ? null : sampledAt + limits.detailsTtlMs;

    final updated = Map<String, dynamic>.from(row);
    updated['price'] = price.toDouble();
    if (pair['market_cap'] != null) updated['market_cap'] = pair['market_cap'];
    updated['liquidity'] = pair['tvl'];
    updated['pairAddress'] = pair['pair'];
    updated['dexId'] = pair['amm'];
    updated['capturedAt'] = capturedAt;
    updated['sourceUpdatedAt'] = sampledAt;
    updated['expiresAt'] = expiresAt;
    updated['pool_created_at'] = pair['created_at'];
    updated['first_trade_at'] = pair['first_trade_at'];
    updated['last_trade_at'] = pair['last_trade_at'];
    updated['poolCreatedAt'] = _upstreamTime(pair['created_at']);
    updated['firstTradeAt'] = _upstreamTime(pair['first_trade_at']);
    updated['lastTradeAt'] = _upstreamTime(pair['last_trade_at']);
    updated['ageBasis'] = 'pool';
    updated['volume_5m'] = pair['volume_u_5m'];
    updated['volume_1h'] = pair['volume_u_1h'];
    updated['volume_24h'] = pair['volume_u_24h'];
    updated['buy_volume_5m'] = pair['buy_volume_u_5m'];
    updated['sell_volume_5m'] = pair['sell_volume_u_5m'];
    if (pair['price_change_5m'] != null) {
      updated['price_change_percent5m'] =
          (pair['price_change_5m'] as num).toDouble() / 100.0;
    }
    updated['buys_24h'] = pair['buys_tx_24h_count'];
    updated['sells_24h'] = pair['sells_tx_24h_count'];
    updated['poolEvidence'] = Map<String, dynamic>.from(pair);

    return updated;
  }
}
