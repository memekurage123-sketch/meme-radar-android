/// Faithful Dart port of upstream `src/pool-identity.mjs` at commit 7ecd342
import 'address.dart';

final _evmPool = RegExp(r'^0x(?:[0-9a-f]{40}|[0-9a-f]{64})$', caseSensitive: false);
final _solPool = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

String _clean(dynamic value) => value is String ? value.trim() : '';

String _normalized(dynamic value, String chain) =>
    chain == 'sol' ? _clean(value) : _clean(value).toLowerCase();

String poolAddress(dynamic value, String chain) {
  final address = _clean(value);
  final isMatch = (chain == 'sol' ? _solPool : _evmPool).hasMatch(address);
  return isMatch ? _normalized(address, chain) : '';
}

String tokenAddress(dynamic value, String chain) {
  final cleaned = _clean(value);
  return validTokenAddress(chain, cleaned) ? _normalized(value, chain) : '';
}

double? _finite(dynamic value) {
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String && value.trim().isNotEmpty) {
    final d = double.tryParse(value.trim());
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

double? _nonnegative(dynamic value) {
  final parsed = _finite(value);
  return parsed != null && parsed >= 0 ? parsed : null;
}

int? _seconds(dynamic value) {
  final parsed = _finite(value);
  if (parsed != null && parsed > 0 && parsed == parsed.truncateToDouble()) {
    return parsed.toInt();
  }
  return null;
}

bool _freshClock(dynamic capturedAt, dynamic sourceUpdatedAt, dynamic expiresAt, int now) {
  final c = _finite(capturedAt);
  final s = _finite(sourceUpdatedAt);
  final e = _finite(expiresAt);
  if (c == null || s == null || e == null) return false;
  return c > 0 &&
      s > 0 &&
      e > now &&
      s <= c &&
      c <= now &&
      now - s <= 60000;
}

class VerifiedAvePoolIdentity {
  final Map<String, dynamic> pool;
  final String pair;
  final String token;
  final String token0;
  final String token1;
  final String rowPair;

  VerifiedAvePoolIdentity({
    required this.pool,
    required this.pair,
    required this.token,
    required this.token0,
    required this.token1,
    required this.rowPair,
  });

  Map<String, dynamic> toMap() => {
        'pool': pool,
        'pair': pair,
        'token': token,
        'token0': token0,
        'token1': token1,
        'rowPair': rowPair,
      };
}

class VerifiedPoolMarket {
  final String source;
  final String pair;
  final double liquidity;
  final double volume5m;
  final int? poolCreatedAt;
  final int? firstTradeAt;
  final Map<String, dynamic>? evidence;

  VerifiedPoolMarket({
    required this.source,
    required this.pair,
    required this.liquidity,
    required this.volume5m,
    this.poolCreatedAt,
    this.firstTradeAt,
    this.evidence,
  });

  Map<String, dynamic> toMap() => {
        'source': source,
        'pair': pair,
        'liquidity': liquidity,
        'volume5m': volume5m,
        if (poolCreatedAt != null) 'poolCreatedAt': poolCreatedAt,
        if (firstTradeAt != null) 'firstTradeAt': firstTradeAt,
        if (evidence != null) 'evidence': evidence,
      };
}

VerifiedAvePoolIdentity? verifiedAvePoolEvidence(
  dynamic row,
  String chain, {
  bool requireRowPair = false,
}) {
  if (row is! Map) return null;
  final pool = row['poolEvidence'];
  final token = tokenAddress(row['address'], chain);
  if (token.isEmpty ||
      pool is! Map ||
      pool['source'] != 'AVE' ||
      pool['identityBasis'] != 'response' ||
      pool['chain'] != chain) {
    return null;
  }
  final pair = poolAddress(pool['pair'], chain);
  final target = tokenAddress(pool['target_token'], chain);
  final token0 = tokenAddress(pool['token0_address'], chain);
  final token1 = tokenAddress(pool['token1_address'], chain);

  if (pair.isEmpty ||
      target.isEmpty ||
      target != token ||
      token0.isEmpty ||
      token1.isEmpty ||
      token0 == token1 ||
      (token != token0 && token != token1)) {
    return null;
  }

  final rowPair = poolAddress(row['pairAddress'], chain);
  if (requireRowPair && rowPair != pair) return null;

  return VerifiedAvePoolIdentity(
    pool: Map<String, dynamic>.from(pool),
    pair: pair,
    token: token,
    token0: token0,
    token1: token1,
    rowPair: rowPair,
  );
}

VerifiedPoolMarket? verifiedPoolMarket(dynamic row, String chain, [int? nowMs]) {
  if (row is! Map) return null;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  if (row['marketOverlayProvider'] == 'DEXSCREENER') {
    final pair = poolAddress(row['pairAddress'], chain);
    final token = tokenAddress(row['address'], chain);
    final liquidity = _nonnegative(row['liquidity']);
    final volume5m = _nonnegative(row['volume_5m']);
    final createdAt = _seconds(row['pool_created_at']);
    if (token.isEmpty ||
        row['chain'] != chain ||
        pair.isEmpty ||
        liquidity == null ||
        volume5m == null ||
        createdAt == null ||
        !_freshClock(row['capturedAt'], row['sourceUpdatedAt'], row['expiresAt'], now)) {
      return null;
    }
    return VerifiedPoolMarket(
      source: 'DEXSCREENER',
      pair: pair,
      liquidity: liquidity,
      volume5m: volume5m,
      poolCreatedAt: createdAt,
    );
  }

  final identity = verifiedAvePoolEvidence(row, chain, requireRowPair: true);
  if (identity == null ||
      !_freshClock(identity.pool['capturedAt'], identity.pool['sourceUpdatedAt'], identity.pool['expiresAt'], now)) {
    return null;
  }

  final liquidity = _nonnegative(identity.pool['tvl']);
  final volume5m = _nonnegative(identity.pool['volume_u_5m']);
  final poolCreatedAt = _seconds(identity.pool['created_at']);
  final firstTradeAt = _seconds(identity.pool['first_trade_at']);

  if (liquidity == null ||
      volume5m == null ||
      (poolCreatedAt == null && firstTradeAt == null)) {
    return null;
  }

  return VerifiedPoolMarket(
    source: 'AVE',
    pair: identity.pair,
    liquidity: liquidity,
    volume5m: volume5m,
    poolCreatedAt: poolCreatedAt,
    firstTradeAt: firstTradeAt,
    evidence: identity.pool,
  );
}
