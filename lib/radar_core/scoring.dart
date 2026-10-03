/// Faithful Dart port of upstream `src/scoring.mjs` at commit 7ecd342
import 'dart:math' as math;
import 'address.dart';
import 'chart_risk.dart';
import 'config.dart';
import 'pool_identity.dart';

final _numberPattern = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$', caseSensitive: false);

double? optionalNumber(dynamic value) {
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

double? optionalRate(dynamic value) {
  double? parsed;
  if (value is String && value.trim().endsWith('%')) {
    final trimmed = value.trim();
    final percent = optionalNumber(trimmed.substring(0, trimmed.length - 1));
    parsed = percent == null ? null : percent / 100;
  } else {
    parsed = optionalNumber(value);
  }
  return (parsed != null && parsed >= 0 && parsed <= 1) ? parsed : null;
}

int? optionalCount(dynamic value) {
  final parsed = optionalNumber(value);
  if (parsed != null && parsed >= 0 && parsed == parsed.truncateToDouble()) {
    return parsed.toInt();
  }
  return null;
}

double? optionalNonNegativeNumber(dynamic value) {
  final parsed = optionalNumber(value);
  return (parsed != null && parsed >= 0) ? parsed : null;
}

double? optionalSignedRate(dynamic value) {
  double? parsed;
  if (value is String && value.trim().endsWith('%')) {
    final trimmed = value.trim();
    final percent = optionalNumber(trimmed.substring(0, trimmed.length - 1));
    parsed = percent == null ? null : percent / 100;
  } else {
    parsed = optionalNumber(value);
  }
  return (parsed != null && parsed >= -5 && parsed <= 5) ? parsed : null;
}

bool? optionalBoolean(dynamic value) {
  if (value == true || value == false) return value as bool;
  if (value == 1 || value == 0) return value == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (['yes', 'true', '1'].contains(normalized)) return true;
    if (['no', 'false', '0'].contains(normalized)) return false;
  }
  return null;
}

double numVal(dynamic value, [double fallback = 0]) => optionalNumber(value) ?? fallback;

dynamic first(List<dynamic> values) {
  for (final value in values) {
    if (value != null && value != '') return value;
  }
  return null;
}

String _lower(dynamic value) => (value?.toString() ?? '').toLowerCase();

String normalizeAddress(dynamic value, [String chain = 'robinhood']) {
  if (value is! String) return '';
  final normalized = value.trim();
  return _lower(chain) == 'sol' ? normalized : normalized.toLowerCase();
}

bool validAddressForChain(dynamic value, [String chain = 'robinhood']) {
  return validTokenAddress(_lower(chain), value is String ? value : null);
}

List<String> normalizeTags(List<dynamic> values) {
  final tags = <String>[];
  for (final value in values) {
    final rows = value is List
        ? value
        : (value is String ? value.split(RegExp(r'[,;|]')) : const []);
    for (final row in rows) {
      final normalized = row.toString().trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      if (normalized.isNotEmpty) tags.add(normalized);
    }
  }
  return tags.toSet().toList();
}

final _smartTags = {'smart_degen'};
final _renownedTags = {'renowned', 'kol'};

class TaggedWalletSignals {
  final int smartWallets;
  final int renownedWallets;
  final int sampledTaggedWallets;

  TaggedWalletSignals({
    required this.smartWallets,
    required this.renownedWallets,
    required this.sampledTaggedWallets,
  });
}

TaggedWalletSignals taggedWalletSignals(dynamic holders, String chain) {
  final wallets = <String, Set<String>>{};
  final list = holders is List ? holders : const [];
  for (final row in list) {
    if (row is! Map) continue;
    final address = normalizeAddress(row['address'], chain);
    if (address.isEmpty) continue;
    final tags = wallets.putIfAbsent(address, () => <String>{});
    final newTags = normalizeTags([row['tags'], row['maker_token_tags']]);
    tags.addAll(newTags);
  }
  final allTagSets = wallets.values.toList();
  return TaggedWalletSignals(
    smartWallets: allTagSets.where((tags) => tags.any((tag) => _smartTags.contains(tag))).length,
    renownedWallets: allTagSets.where((tags) => tags.any((tag) => _renownedTags.contains(tag))).length,
    sampledTaggedWallets: allTagSets.where((tags) => tags.isNotEmpty).length,
  );
}

class DiscoverySignals {
  final int? smartDegenCount;
  final int? renownedCount;
  final int? holders;
  final int? swaps5m;
  final int? buys5m;
  final int? sells5m;
  final double? volume5m;
  final double? priceChange5m;
  final int smartBoost;
  final bool kolOnly;
  final int scoreAdjustment;

  DiscoverySignals({
    this.smartDegenCount,
    this.renownedCount,
    this.holders,
    this.swaps5m,
    this.buys5m,
    this.sells5m,
    this.volume5m,
    this.priceChange5m,
    required this.smartBoost,
    required this.kolOnly,
    required this.scoreAdjustment,
  });

  Map<String, dynamic> toMap() => {
        'smartDegenCount': smartDegenCount,
        'renownedCount': renownedCount,
        'holders': holders,
        'swaps5m': swaps5m,
        'buys5m': buys5m,
        'sells5m': sells5m,
        'volume5m': volume5m,
        'priceChange5m': priceChange5m,
        'smartBoost': smartBoost,
        'kolOnly': kolOnly,
        'scoreAdjustment': scoreAdjustment,
      };
}

DiscoverySignals discoverySignalView([Map<String, dynamic> row = const {}]) {
  final smartDegenCount = optionalCount(row['smart_degen_count']);
  final renownedCount = optionalCount(row['renowned_count']);
  final holders = optionalCount(row['holder_count']);
  final ave = row['marketProvider'] == 'AVE';
  final swaps5m = optionalCount(ave ? row['swaps_5m'] : first([row['swaps_5m'], row['swaps']]));
  final buys5m = optionalCount(ave ? row['buys_5m'] : first([row['buys_5m'], row['buys']]));
  final sells5m = optionalCount(ave ? row['sells_5m'] : first([row['sells_5m'], row['sells']]));
  final volume5m = optionalNonNegativeNumber(ave ? row['volume_5m'] : first([row['volume_5m'], row['volume']]));
  final priceChange5m = optionalSignedRate(first([
    row['price_change_percent5m'],
    row['price_change_percent_5m'],
    row['price_change_percent'],
  ]));
  final smartBoost = smartDegenCount == null
      ? 0
      : smartDegenCount >= 3
          ? 14
          : smartDegenCount == 2
              ? 7
              : 0;
  final kolOnly = smartDegenCount != null &&
      smartDegenCount <= 1 &&
      renownedCount != null &&
      renownedCount > 0;
  final scoreAdjustment = smartBoost - (kolOnly ? 4 : 0);

  return DiscoverySignals(
    smartDegenCount: smartDegenCount,
    renownedCount: renownedCount,
    holders: holders,
    swaps5m: swaps5m,
    buys5m: buys5m,
    sells5m: sells5m,
    volume5m: volume5m,
    priceChange5m: priceChange5m,
    smartBoost: smartBoost,
    kolOnly: kolOnly,
    scoreAdjustment: scoreAdjustment,
  );
}

double marketCap(Map<String, dynamic> row) {
  return numVal(first([row['market_cap'], row['usd_market_cap'], row['mcp']]));
}

double createdAt(Map<String, dynamic> row) {
  if (row['marketProvider'] == 'AVE') {
    return numVal(first([
      row['first_trade_at'],
      row['pool_created_at'],
      row['launch_at'],
      (row['ageBasis'] == 'launch' || row['ageBasis'] == 'token') ? row['creation_timestamp'] : null,
    ]));
  }
  return numVal(first([
    row['creation_timestamp'],
    row['created_timestamp'],
    row['open_timestamp'],
  ]));
}

bool aveHookPending(Map<String, dynamic> row, String chain) {
  final ca = normalizeAddress(row['address'], chain);
  final pool = row['poolEvidence'];
  final amms = <String>[];
  if (pool is Map &&
      pool['chain'] == chain &&
      normalizeAddress(pool['target_token'], chain) == ca &&
      (normalizeAddress(pool['token0_address'], chain) == ca ||
          normalizeAddress(pool['token1_address'], chain) == ca) &&
      pool['pair'] is String &&
      (pool['pair'] as String).isNotEmpty) {
    if (pool['amm'] != null) amms.add(pool['amm'].toString());
  }
  final pairs = row['pairs'];
  if (pairs is List) {
    for (final p in pairs.take(100)) {
      if (p is Map &&
          p['chain'] == chain &&
          normalizeAddress(p['address'], chain) == ca &&
          p['pair'] is String &&
          (p['pair'] as String).isNotEmpty) {
        if (p['amm'] != null) amms.add(p['amm'].toString());
      }
    }
  }
  return amms.any((amm) {
    final protocol = amm.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return protocol.contains('uniswapv4') ||
        protocol.contains('pancakeswapinfinity') ||
        protocol.contains('pancakeinfinity');
  });
}

class FreshAvePoolTrajectory {
  final bool identityVerified;
  final bool evidenceFresh;
  final double? current;
  final double? ath;
  final double? athRatio;
  final double? change1h;

  FreshAvePoolTrajectory({
    required this.identityVerified,
    required this.evidenceFresh,
    this.current,
    this.ath,
    this.athRatio,
    this.change1h,
  });
}

FreshAvePoolTrajectory? freshAvePoolTrajectory(Map<String, dynamic> row, String chain, int now) {
  final identity = verifiedAvePoolEvidence(row, chain, requireRowPair: true);
  if (identity == null) return null;
  final pool = identity.pool;
  final ca = identity.token;
  final poolPair = identity.pair;
  final rowPair = identity.rowPair;

  final capturedAt = optionalNumber(pool['capturedAt']);
  final sourceUpdatedAt = optionalNumber(pool['sourceUpdatedAt']);
  final expiresAt = optionalNumber(pool['expiresAt']);
  final poolFresh = capturedAt != null &&
      sourceUpdatedAt != null &&
      expiresAt != null &&
      capturedAt > 0 &&
      sourceUpdatedAt > 0 &&
      sourceUpdatedAt <= capturedAt &&
      capturedAt <= now &&
      now - sourceUpdatedAt <= 60000 &&
      expiresAt > now;

  final overlayCapturedAt = optionalNumber(row['capturedAt']);
  final overlaySourceUpdatedAt = optionalNumber(row['sourceUpdatedAt']);
  final overlayExpiresAt = optionalNumber(row['expiresAt']);
  final samePoolOverlayFresh = row['marketOverlayProvider'] == 'DEXSCREENER' &&
      rowPair == poolPair &&
      row['marketOverlayPriceUpdated'] == true &&
      overlayCapturedAt != null &&
      overlaySourceUpdatedAt != null &&
      overlayCapturedAt > 0 &&
      overlaySourceUpdatedAt > 0 &&
      overlaySourceUpdatedAt <= overlayCapturedAt &&
      overlayCapturedAt <= now &&
      now - overlaySourceUpdatedAt <= 60000 &&
      overlayExpiresAt != null &&
      overlayExpiresAt > now;

  final poolCurrent = optionalNumber(
    normalizeAddress(pool['token0_address'], chain) == ca
        ? pool['token0_price_usd']
        : pool['token1_price_usd'],
  );
  final current = poolFresh
      ? poolCurrent
      : samePoolOverlayFresh
          ? optionalNumber(row['price'])
          : null;
  final ath = optionalNumber(pool['price_ath_u']);
  final rawChange1h = optionalNumber(pool['price_change_1h']);

  if (current == null || current <= 0 || ath == null || ath <= 0) {
    return FreshAvePoolTrajectory(
      identityVerified: true,
      evidenceFresh: poolFresh,
      athRatio: null,
      change1h: null,
    );
  }

  return FreshAvePoolTrajectory(
    identityVerified: true,
    evidenceFresh: poolFresh,
    current: current,
    ath: ath,
    athRatio: current / ath,
    change1h: (!poolFresh || rawChange1h == null) ? null : rawChange1h / 100,
  );
}

class DiscoveryScreenResult {
  final bool pass;
  final List<String> reasons;
  final bool priorityBand;
  final double score;
  final double mc;
  final double liquidity;
  final double ageSec;
  final String? ageBasis;
  final String? marketProvider;
  final int? createdAt;
  final DiscoverySignals signals;
  final List<String> unknownFields;

  DiscoveryScreenResult({
    required this.pass,
    required this.reasons,
    required this.priorityBand,
    required this.score,
    required this.mc,
    required this.liquidity,
    required this.ageSec,
    this.ageBasis,
    this.marketProvider,
    this.createdAt,
    required this.signals,
    required this.unknownFields,
  });

  Map<String, dynamic> toMap() => {
        'pass': pass,
        'reasons': reasons,
        'priorityBand': priorityBand,
        'score': score,
        'mc': mc,
        'liquidity': liquidity,
        'ageSec': ageSec,
        if (ageBasis != null) 'ageBasis': ageBasis,
        if (marketProvider != null) 'marketProvider': marketProvider,
        if (createdAt != null) 'createdAt': createdAt,
        'signals': signals.toMap(),
        'unknownFields': unknownFields,
      };
}

List<String> knownRiskReasons(Map<String, dynamic> row, RadarConfig config, {double? strictLiquidity}) {
  final reasons = <String>[];
  final lp = optionalNumber(row['liquidity']);
  final buy = optionalRate(row['buy_tax']);
  final sell = optionalRate(row['sell_tax']);
  final dev = optionalRate(first([row['dev_team_hold_rate'], row['creator_balance_rate'], row['creator_hold_rate']]));
  final strictLp = strictLiquidity ?? config.strictLiquidity;

  if (lp != null && lp < strictLp) reasons.add('流动性低于深审门槛');
  if ((buy != null && buy > config.maxBuyTax) ||
      (sell != null && sell > config.maxSellTax) ||
      (buy != null && sell != null && (buy - sell).abs() > config.maxTaxAsymmetry)) {
    reasons.add('交易税超过风险门槛');
  }
  if (dev != null && dev > 0.01) reasons.add('DEV持仓超过1%');
  if (optionalNumber(row['volume_5m']) == 0) reasons.add('近5分钟无成交，暂不进入候选');
  return reasons;
}

DiscoveryScreenResult aveDiscoveryScreen(Map<String, dynamic> row, RadarConfig config, [double? nowSecParam]) {
  final nowSec = nowSecParam ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
  final now = (nowSec * 1000).toInt();
  final chain = config.chain;

  final mcValue = optionalNonNegativeNumber(row['market_cap']);
  final liquidityValue = optionalNonNegativeNumber(row['liquidity']);
  final poolIdentity = verifiedAvePoolEvidence(row, chain, requireRowPair: true);
  final poolMarket = verifiedPoolMarket(row, chain, now);

  final tradeAt = poolIdentity != null ? optionalNumber(poolIdentity.pool['first_trade_at'])?.toInt() : null;
  final poolAt = poolIdentity != null
      ? optionalNumber(poolIdentity.pool['created_at'])?.toInt()
      : poolMarket?.source == 'DEXSCREENER'
          ? poolMarket?.poolCreatedAt
          : null;
  final launchAt = optionalNumber(row['launch_at'])?.toInt();
  final tokenAt = (row['ageBasis'] == 'launch' || row['ageBasis'] == 'token')
      ? optionalNumber(row['creation_timestamp'])?.toInt()
      : null;

  final created = (tradeAt != null && tradeAt > 0)
      ? tradeAt
      : (poolAt != null && poolAt > 0)
          ? poolAt
          : (launchAt != null && launchAt > 0)
              ? launchAt
              : tokenAt;

  final ageBasis = (tradeAt != null && tradeAt > 0)
      ? 'trade'
      : (poolAt != null && poolAt > 0)
          ? 'pool'
          : (launchAt != null && launchAt > 0)
              ? 'launch'
              : (tokenAt != null && tokenAt > 0)
                  ? 'token'
                  : 'unknown';

  final ageSec = (created != null && created > 0) ? (nowSec - created) : 0.0;
  final mc = mcValue ?? 0.0;
  final liquidity = liquidityValue ?? 0.0;
  final volume = optionalNonNegativeNumber(row['volume_5m']);

  final reasons = knownRiskReasons(row, config, strictLiquidity: config.minLiquidity);

  final rowAddress = row['address']?.toString() ?? '';
  if (row['chain'] != chain || !validAddressForChain(rowAddress, chain) || RegExp(r'^0x(?:0{40}|e{40})$', caseSensitive: false).hasMatch(rowAddress)) {
    reasons.add('链或代币地址不匹配');
  }
  if (optionalNumber(row['price']) == null || optionalNumber(row['price'])! <= 0) {
    reasons.add('价格数据未知');
  }

  final capturedAt = optionalNumber(row['capturedAt']);
  final sourceUpdatedAt = optionalNumber(row['sourceUpdatedAt']);
  final expiresAt = optionalNumber(row['expiresAt']);

  if (row['stale'] == true ||
      capturedAt == null ||
      sourceUpdatedAt == null ||
      capturedAt <= 0 ||
      sourceUpdatedAt <= 0 ||
      capturedAt > now ||
      sourceUpdatedAt > capturedAt ||
      now - capturedAt > 60000 ||
      now - sourceUpdatedAt > 60000 ||
      (row.containsKey('expiresAt') && (expiresAt == null || expiresAt <= now))) {
    reasons.add('AVE 行情已过期或原始时间未核验');
  }

  if (row.containsKey('marketCapSourceUpdatedAt')) {
    final mcSrc = optionalNumber(row['marketCapSourceUpdatedAt']);
    final mcCap = optionalNumber(row['marketCapCapturedAt']);
    final mcExp = optionalNumber(row['marketCapExpiresAt']);
    if (mcSrc == null ||
        mcCap == null ||
        mcExp == null ||
        mcSrc <= 0 ||
        mcSrc > mcCap ||
        mcCap > now ||
        now - mcSrc > 60000 ||
        mcExp <= now) {
      reasons.add('市值原始时间待更新');
    }
  }

  if (created == null || created <= 0) {
    reasons.add('池龄或首笔成交时间未知');
  } else if (ageSec < config.minAgeSec) {
    reasons.add(ageBasis == 'trade'
        ? '首笔成交不足5分钟'
        : ageBasis == 'pool'
            ? '池创建不足5分钟'
            : '上线不足5分钟');
  } else if (ageSec > config.maxAgeSec) {
    reasons.add('超过观察池龄上限');
  }

  if (mcValue == null) {
    reasons.add('市值数据未知');
  } else if (!(mc >= config.discoveryMinMarketCap && mc <= config.discoveryMaxMarketCap)) {
    reasons.add('市值不在发现范围');
  }

  if (liquidityValue == null) {
    reasons.add('流动性数据未知');
  } else if (liquidity < config.minLiquidity) {
    reasons.add('流动性不足');
  }

  if (volume == null || volume <= 0) {
    reasons.add('近5分钟成交额不足或未知');
  }

  if (volume != null && liquidityValue != null && ageSec >= config.matureMarketAgeSec) {
    final old = ageSec >= config.oldMarketAgeSec;
    final absolute = old ? config.minOldVolume5mUsd : config.minMatureVolume5mUsd;
    final turnover = old ? config.minOldTurnover5m : config.minMatureTurnover5m;
    final activityVolume = poolMarket?.volume5m ?? volume;
    final activityLiquidity = poolMarket?.liquidity ?? liquidity;
    if (old && poolMarket == null) {
      reasons.add('老池缺少同池流动性与成交证据');
    }
    if (activityVolume < math.max(absolute, activityLiquidity * turnover)) {
      reasons.add(old ? '老池当前成交活跃度不足' : '当前成交活跃度不足');
    }
  }

  final trajectory = freshAvePoolTrajectory(row, chain, now);
  final mature = ageSec >= config.matureMarketAgeSec;
  final old = ageSec >= config.oldMarketAgeSec;

  if (mature && row['poolEvidence'] != null && trajectory == null) {
    reasons.add('池历史证据身份待核验');
  }
  if (old && (trajectory == null || trajectory.athRatio == null)) {
    reasons.add('老池历史轨迹待核验');
  }
  if (trajectory != null &&
      trajectory.athRatio != null &&
      mature &&
      trajectory.athRatio! <= config.maxCollapsedAthRatio &&
      !(trajectory.change1h != null && trajectory.change1h! > config.strongRebound1h)) {
    reasons.add('距历史高点跌幅过深且未出现强势反弹');
  } else if (trajectory != null && mature && !trajectory.evidenceFresh) {
    reasons.add('池历史轨迹已过期，等待更新');
  }

  for (final field in ['buy_volume_5m', 'sell_volume_5m']) {
    if (row[field] != null && (optionalNonNegativeNumber(row[field]) == null || optionalNonNegativeNumber(row[field])! <= 0)) {
      reasons.add(field == 'buy_volume_5m' ? '近5分钟买入额不足或未核验' : '近5分钟卖出额不足或未核验');
    }
  }

  if (optionalCount(row['buys_5m']) == 0) reasons.add('近5分钟无买入成交');
  if (optionalCount(row['sells_5m']) == 0) reasons.add('近5分钟无卖出成交');
  if (optionalBoolean(row['is_honeypot']) == true || row['sellable'] == false || optionalBoolean(row['cannot_sell_all']) == true) {
    reasons.add('已知貔貅或卖出受限');
  }
  if (optionalBoolean(row['is_wash_trading']) == true) reasons.add('检测到刷量');

  for (final entry in [
    ['rug_ratio', 'rug风险'],
    ['bundler_rate', '捆绑机器人占比'],
    ['rat_trader_amount_rate', '内幕占比'],
  ]) {
    final field = entry[0];
    final label = entry[1];
    if ((optionalRate(row[field]) ?? 0) > 0.3) reasons.add('$label过高');
  }

  if (aveHookPending(row, chain)) {
    reasons.add('Hook架构池待核验，交易路由未确认');
  }

  final signals = discoverySignalView(row);
  final priorityBand = mc >= config.priorityMinMarketCap && mc <= config.priorityMaxMarketCap;
  final score = (priorityBand ? 35.0 : 10.0) +
      math.min(25.0, liquidity / 1000.0) +
      math.min(20.0, (volume ?? 0) / 1000.0) +
      math.min(20.0, numVal(row['holder_count']) / 10.0);

  final unknownFields = <String>[];
  if (optionalRate(row['rug_ratio']) == null) unknownFields.add('rugRatio');
  if (optionalRate(row['bundler_rate']) == null) unknownFields.add('bundler');
  if (optionalRate(row['rat_trader_amount_rate']) == null) unknownFields.add('insider');
  if (optionalBoolean(row['is_wash_trading']) == null) unknownFields.add('wash');
  if (optionalBoolean(row['is_honeypot']) == null) unknownFields.add('honeypot');

  final uniqueReasons = reasons.toSet().toList();
  return DiscoveryScreenResult(
    pass: uniqueReasons.isEmpty,
    reasons: uniqueReasons,
    priorityBand: priorityBand,
    score: score,
    mc: mc,
    liquidity: liquidity,
    ageSec: ageSec,
    ageBasis: ageBasis,
    marketProvider: 'AVE',
    createdAt: created,
    signals: signals,
    unknownFields: unknownFields,
  );
}

DiscoveryScreenResult discoveryScreen(Map<String, dynamic> row, RadarConfig config, [double? nowSecParam]) {
  if (row['marketProvider'] == 'AVE') {
    return aveDiscoveryScreen(row, config, nowSecParam);
  }
  final nowSec = nowSecParam ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
  final mcValue = optionalNumber(first([row['market_cap'], row['usd_market_cap'], row['mcp']]));
  final createdValue = optionalNumber(first([row['creation_timestamp'], row['created_timestamp'], row['open_timestamp']]));
  final liquidityValue = optionalNumber(row['liquidity']);
  final rug = optionalRate(row['rug_ratio']);
  final bundler = optionalRate(first([row['bundler_rate'], row['bundler_trader_amount_rate']]));
  final insider = optionalRate(first([row['rat_trader_amount_rate'], row['suspected_insider_hold_rate']]));
  final wash = optionalBoolean(row['is_wash_trading']);
  final honeypot = optionalBoolean(row['is_honeypot']);

  final mc = mcValue ?? 0.0;
  final created = createdValue != null ? createdValue.toInt() : 0;
  final ageSec = created > 0 ? (nowSec - created) : 0.0;
  final liquidity = liquidityValue ?? 0.0;

  final reasons = knownRiskReasons(row, config);

  if (!validAddressForChain(row['address'], config.chain)) reasons.add('地址格式异常');
  if (createdValue == null || created <= 0) {
    reasons.add('创建时间未知');
  } else if (ageSec < config.minAgeSec) {
    reasons.add('创建不足5分钟');
  } else if (ageSec > config.maxAgeSec) {
    reasons.add('超过观察年龄上限');
  }

  if (mcValue == null) {
    reasons.add('市值数据未知');
  } else if (!(mc >= config.discoveryMinMarketCap && mc <= config.discoveryMaxMarketCap)) {
    reasons.add('市值不在发现范围');
  }

  if (liquidityValue == null) {
    reasons.add('流动性数据未知');
  } else if (liquidity < config.minLiquidity) {
    reasons.add('流动性不足');
  }

  if (rug == null) {
    reasons.add('rug风险数据未知');
  } else if (rug > 0.30) {
    reasons.add('rug风险过高');
  }

  if (bundler == null) {
    reasons.add('捆绑机器人数据未知');
  } else if (bundler > 0.30) {
    reasons.add('捆绑机器人占比过高');
  }

  if (insider == null) {
    reasons.add('内幕数据未知');
  } else if (insider > 0.30) {
    reasons.add('内幕/老鼠仓占比过高');
  }

  if (wash == null) {
    reasons.add('刷量数据未知');
  } else if (wash) {
    reasons.add('检测到刷量');
  }

  if (_lower(config.chain) != 'sol') {
    if (honeypot == null) {
      reasons.add('貔貅数据未知');
    } else if (honeypot) {
      reasons.add('检测到貔貅盘');
    }
  }

  final priorityBand = mc >= config.priorityMinMarketCap && mc <= config.priorityMaxMarketCap;
  final volume = numVal(first([row['volume_1h'], row['volume'], row['volume_24h']]));
  final holders = numVal(row['holder_count']);
  final signals = discoverySignalView(row);
  final score = (priorityBand ? 35.0 : 10.0) +
      math.min(25.0, liquidity / 1000.0) +
      math.min(20.0, volume / 1000.0) +
      math.min(20.0, holders / 10.0) +
      signals.scoreAdjustment;

  final unknownFields = <String>[];
  if (mcValue == null) unknownFields.add('marketCap');
  if (createdValue == null) unknownFields.add('createdAt');
  if (liquidityValue == null) unknownFields.add('liquidity');
  if (rug == null) unknownFields.add('rugRatio');
  if (bundler == null) unknownFields.add('bundler');
  if (insider == null) unknownFields.add('insider');
  if (wash == null) unknownFields.add('wash');
  if (_lower(config.chain) != 'sol' && honeypot == null) unknownFields.add('honeypot');

  return DiscoveryScreenResult(
    pass: reasons.isEmpty,
    reasons: reasons,
    priorityBand: priorityBand,
    score: score,
    mc: mc,
    liquidity: liquidity,
    ageSec: ageSec,
    signals: signals,
    unknownFields: unknownFields,
  );
}

Map<String, dynamic> securityView([
  Map<String, dynamic> source = const {},
  Map<String, dynamic> discovery = const {},
  Map<String, dynamic> info = const {},
]) {
  final stat = info['stat'] is Map<String, dynamic> ? info['stat'] as Map<String, dynamic> : const {};
  final dev = info['dev'] is Map<String, dynamic> ? info['dev'] as Map<String, dynamic> : const {};
  return {
    'openSource': first([source['open_source'], source['is_open_source'], discovery['open_source'], discovery['is_open_source']]),
    'ownerRenounced': first([source['owner_renounced'], source['is_renounced'], discovery['owner_renounced'], discovery['is_renounced']]),
    'honeypot': first([source['is_honeypot'], discovery['is_honeypot']]),
    'buyTax': first([source['buy_tax'], discovery['buy_tax']]),
    'sellTax': first([source['sell_tax'], discovery['sell_tax']]),
    'rugRatio': first([source['rug_ratio'], discovery['rug_ratio']]),
    'top10': first([source['top_10_holder_rate'], discovery['top_10_holder_rate'], stat['top_10_holder_rate'], dev['top_10_holder_rate']]),
    'devHold': first([source['dev_team_hold_rate'], source['creator_balance_rate'], discovery['dev_team_hold_rate'], discovery['creator_balance_rate'], stat['dev_team_hold_rate'], stat['creator_hold_rate']]),
    'creatorStatus': first([source['creator_token_status'], discovery['creator_token_status'], dev['creator_token_status']]),
    'insider': first([source['suspected_insider_hold_rate'], source['rat_trader_amount_rate'], discovery['rat_trader_amount_rate'], stat['top_rat_trader_percentage']]),
    'bundler': first([source['bundler_trader_amount_rate'], discovery['bundler_rate'], discovery['bundler_trader_amount_rate'], stat['top_bundler_trader_percentage']]),
    'sniperHold': first([source['top70_sniper_hold_rate'], discovery['top70_sniper_hold_rate']]),
    'wash': first([source['is_wash_trading'], discovery['is_wash_trading']]),
    'burnStatus': first([source['burn_status'], discovery['burn_status']]),
    'lockRate': first([source['lock_percent'], source['locked_ratio'], discovery['lock_percent'], discovery['locked_ratio'], info['locked_ratio']]),
    'renouncedMint': first([source['renounced_mint'], discovery['renounced_mint']]),
    'renouncedFreezeAccount': first([source['renounced_freeze_account'], discovery['renounced_freeze_account']]),
  };
}

final _riskTags = {'bundler', 'rat_trader', 'sniper', 'wash_trader', 'dex_bot'};

class AnalyzeWalletsResult {
  final int sampled;
  final int ordinaryCount;
  final double ordinaryHoldRate;
  final int riskWalletCount;
  final double? botHoldRate;
  final double? linkedHoldRate;
  final int duplicateCount;
  final int missingAddressCount;
  final int invalidRateCount;
  final List<String> unknownFields;
  final bool dataComplete;
  final bool pass;

  AnalyzeWalletsResult({
    required this.sampled,
    required this.ordinaryCount,
    required this.ordinaryHoldRate,
    required this.riskWalletCount,
    this.botHoldRate,
    this.linkedHoldRate,
    required this.duplicateCount,
    required this.missingAddressCount,
    required this.invalidRateCount,
    required this.unknownFields,
    required this.dataComplete,
    required this.pass,
  });

  Map<String, dynamic> toMap() => {
        'sampled': sampled,
        'ordinaryCount': ordinaryCount,
        'ordinaryHoldRate': ordinaryHoldRate,
        'riskWalletCount': riskWalletCount,
        if (botHoldRate != null) 'botHoldRate': botHoldRate,
        if (linkedHoldRate != null) 'linkedHoldRate': linkedHoldRate,
        'duplicateCount': duplicateCount,
        'missingAddressCount': missingAddressCount,
        'invalidRateCount': invalidRateCount,
        'unknownFields': unknownFields,
        'dataComplete': dataComplete,
        'pass': pass,
      };
}

AnalyzeWalletsResult analyzeWallets(dynamic holders, RadarConfig config) {
  final rows = holders is List ? holders : const [];
  final grouped = <String, Map<String, dynamic>>{};
  var missingAddressCount = 0;

  for (final row in rows) {
    if (row is! Map) continue;
    final address = normalizeAddress(row['address'], config.chain);
    if (address.isEmpty) {
      missingAddressCount += 1;
      continue;
    }
    final current = grouped.putIfAbsent(address, () => {
      'address': address,
      'addrTypes': <double?>[],
      'tags': <String>{},
      'holdRates': <double>[],
      'invalidHoldRate': false,
      'isNewValues': <bool?>[],
      'suspiciousValues': <bool?>[],
      'buyTxCounts': <double?>[],
      'sources': <String>{},
    });

    final addrType = optionalNumber(row['addr_type']);
    (current['addrTypes'] as List<double?>).add(addrType);
    final tags = normalizeTags([row['tags'], row['maker_token_tags']]);
    (current['tags'] as Set<String>).addAll(tags);
    final holdRate = optionalRate(row['amount_percentage']);
    if (holdRate == null || holdRate < 0) {
      current['invalidHoldRate'] = true;
    } else {
      (current['holdRates'] as List<double>).add(holdRate);
    }
    (current['isNewValues'] as List<bool?>).add(optionalBoolean(row['is_new']));
    (current['suspiciousValues'] as List<bool?>).add(optionalBoolean(row['is_suspicious']));
    (current['buyTxCounts'] as List<double?>).add(optionalNumber(row['buy_tx_count_cur']));

    final nativeTransfer = row['native_transfer'] is Map ? row['native_transfer'] as Map : null;
    final source = normalizeAddress(first([nativeTransfer?['from_address'], nativeTransfer?['address']]), config.chain);
    if (source.isNotEmpty) {
      (current['sources'] as Set<String>).add(source);
    }
  }

  final normalized = grouped.values.map((row) {
    final addrTypes = row['addrTypes'] as List<double?>;
    final holdRates = row['holdRates'] as List<double>;
    final isNewValues = row['isNewValues'] as List<bool?>;
    final suspiciousValues = row['suspiciousValues'] as List<bool?>;
    final buyTxCounts = row['buyTxCounts'] as List<double?>;

    return {
      'address': row['address'],
      'addrTypeKnown': addrTypes.isNotEmpty && addrTypes.every((v) => v != null),
      'regular': addrTypes.isNotEmpty && addrTypes.every((v) => v == 0),
      'tags': (row['tags'] as Set<String>).toList(),
      'holdRate': (row['invalidHoldRate'] == true || holdRates.isEmpty) ? null : holdRates.reduce(math.max),
      'isNew': isNewValues.contains(true) ? true : isNewValues.every((v) => v == false) ? false : null,
      'suspicious': suspiciousValues.contains(true) ? true : suspiciousValues.every((v) => v == false) ? false : null,
      'buyTxCount': (buyTxCounts.isNotEmpty && buyTxCounts.every((v) => v != null)) ? buyTxCounts.whereType<double>().reduce(math.max) : null,
      'sources': (row['sources'] as Set<String>).toList(),
    };
  }).toList();

  final regular = normalized.where((row) => row['regular'] == true).toList();
  final taggedRisk = regular.where((row) {
    final tags = row['tags'] as List<String>;
    return tags.any((tag) => _riskTags.contains(tag)) || row['suspicious'] == true;
  }).toList();

  final ordinary = regular.where((row) {
    final tags = row['tags'] as List<String>;
    final buyTx = row['buyTxCount'] as double?;
    return (row['address'] as String).isNotEmpty &&
        row['isNew'] == false &&
        row['suspicious'] == false &&
        buyTx != null &&
        buyTx > 0 &&
        row['holdRate'] != null &&
        !tags.any((tag) => _riskTags.contains(tag));
  }).toList();

  final invalidRateCount = regular.where((row) => row['holdRate'] == null).length;
  final riskRateUnknown = taggedRisk.any((row) => row['holdRate'] == null);
  final botHoldRate = riskRateUnknown
      ? null
      : taggedRisk.fold<double>(0.0, (sum, row) => sum + (row['holdRate'] as double? ?? 0.0));

  final sourceGroups = <String, List<Map<String, dynamic>>>{};
  for (final row in regular) {
    final sources = row['sources'] as List<String>;
    for (final src in sources) {
      sourceGroups.putIfAbsent(src, () => []).add(row);
    }
  }

  final linked = sourceGroups.values.where((group) => group.length >= 2).expand((g) => g).toList();
  final uniqueLinkedMap = <String, Map<String, dynamic>>{};
  for (final row in linked) {
    uniqueLinkedMap[row['address'] as String] = row;
  }
  final uniqueLinked = uniqueLinkedMap.values.toList();
  final linkedRateUnknown = uniqueLinked.any((row) => row['holdRate'] == null);
  final linkedHoldRate = linkedRateUnknown
      ? null
      : uniqueLinked.fold<double>(0.0, (sum, row) => sum + (row['holdRate'] as double? ?? 0.0));
  final ordinaryHoldRate = ordinary.fold<double>(0.0, (sum, row) => sum + (row['holdRate'] as double? ?? 0.0));

  final unknownFields = <String>[];
  if (missingAddressCount > 0) unknownFields.add('holders.address');
  if (normalized.any((row) => row['addrTypeKnown'] != true)) unknownFields.add('holders.addrType');
  if (invalidRateCount > 0) unknownFields.add('holders.amountPercentage');
  if (regular.any((row) => row['isNew'] == null)) unknownFields.add('holders.isNew');
  if (regular.any((row) => row['suspicious'] == null)) unknownFields.add('holders.isSuspicious');
  if (regular.any((row) => row['buyTxCount'] == null)) unknownFields.add('holders.buyTxCount');

  final dataComplete = unknownFields.isEmpty;
  final pass = dataComplete &&
      ordinary.length >= config.minOrdinaryWallets &&
      botHoldRate != null &&
      botHoldRate <= config.maxBotHoldRate &&
      linkedHoldRate != null &&
      linkedHoldRate <= config.maxLinkedHoldRate;

  return AnalyzeWalletsResult(
    sampled: regular.length,
    ordinaryCount: ordinary.length,
    ordinaryHoldRate: ordinaryHoldRate,
    riskWalletCount: taggedRisk.length,
    botHoldRate: botHoldRate,
    linkedHoldRate: linkedHoldRate,
    duplicateCount: rows.length - missingAddressCount - grouped.length,
    missingAddressCount: missingAddressCount,
    invalidRateCount: invalidRateCount,
    unknownFields: unknownFields,
    dataComplete: dataComplete,
    pass: pass,
  );
}

String normalizedCreatorStatus(dynamic value) {
  final status = _lower(value).trim();
  if (['creator_close', 'close', 'closed', 'sell', 'sold', 'exited'].contains(status)) return 'EXITED';
  if (['creator_hold', 'hold', 'holding'].contains(status)) return 'HOLDING';
  return 'UNKNOWN';
}

class MarketBehaviorResult {
  final bool pass;
  final String status;
  final List<String> downgradeReasons;
  final List<String> warnings;
  final List<String> strengths;
  final List<String> unknownFields;
  final Map<String, dynamic> evidence;

  MarketBehaviorResult({
    required this.pass,
    required this.status,
    required this.downgradeReasons,
    required this.warnings,
    required this.strengths,
    required this.unknownFields,
    required this.evidence,
  });
}

MarketBehaviorResult marketBehaviorScreen(
  RadarConfig config, {
  Map<String, dynamic> discovery = const {},
  Map<String, dynamic> info = const {},
  dynamic holders = const [],
  ObserveFiveMinutesResult? observation,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final price = info['price'] is Map ? info['price'] as Map : const {};
  final tagEvidence = taggedWalletSignals(holders, config.chain);

  final walletTagsStat = info['wallet_tags_stat'] is Map ? info['wallet_tags_stat'] as Map : const {};
  final aggregateSmart = optionalCount(first([walletTagsStat['smart_wallets'], discovery['smart_degen_count']]));
  final aggregateRenowned = optionalCount(first([walletTagsStat['renowned_wallets'], discovery['renowned_count']]));
  final smartKnown = aggregateSmart != null || tagEvidence.smartWallets > 0;
  final renownedKnown = aggregateRenowned != null || tagEvidence.renownedWallets > 0;
  final smartWallets = smartKnown ? math.max(aggregateSmart ?? 0, tagEvidence.smartWallets) : null;
  final renownedWallets = renownedKnown ? math.max(aggregateRenowned ?? 0, tagEvidence.renownedWallets) : null;

  final stat = info['stat'] is Map ? info['stat'] as Map : const {};
  final dev = info['dev'] is Map ? info['dev'] as Map : const {};
  final holderCount = optionalCount(first([info['holder_count'], stat['holder_count'], discovery['holder_count']]));
  final swaps5m = optionalCount(first([price['swaps_5m'], discovery['swaps_5m'], discovery['swaps']]));
  final buys5m = optionalCount(first([price['buys_5m'], discovery['buys_5m'], discovery['buys']]));
  final sells5m = optionalCount(first([price['sells_5m'], discovery['sells_5m'], discovery['sells']]));
  final volume5m = optionalNonNegativeNumber(first([price['volume_5m'], discovery['volume_5m'], discovery['volume']]));

  final currentPrice = optionalNumber(price['price']);
  final priorPrice5m = optionalNumber(price['price_5m']);
  final calculatedPriceChange = currentPrice != null && currentPrice > 0 && priorPrice5m != null && priorPrice5m > 0
      ? currentPrice / priorPrice5m - 1
      : null;
  final priceChange5m = optionalSignedRate(first([
    calculatedPriceChange,
    discovery['price_change_percent5m'],
    discovery['price_change_percent_5m'],
    discovery['price_change_percent'],
  ]));

  final created = optionalNumber(first([
    info['open_timestamp'],
    discovery['open_timestamp'],
    info['creation_timestamp'],
    discovery['creation_timestamp'],
    discovery['created_timestamp'],
  ]));
  final ageSec = (created != null && created > 0) ? (now / 1000.0 - created) : null;

  final creatorStatus = normalizedCreatorStatus(first([dev['creator_token_status'], discovery['creator_token_status']]));
  final creatorCreatedCount = optionalCount(discovery['creator_created_count']);
  final creatorGraduatedCount = optionalCount(discovery['creator_created_open_count']);
  final creatorLaunchCount = optionalCount(first([dev['creator_open_count'], creatorCreatedCount]));
  final creatorOpenRatio = creatorCreatedCount != null &&
          creatorCreatedCount > 0 &&
          creatorGraduatedCount != null &&
          creatorGraduatedCount <= creatorCreatedCount
      ? creatorGraduatedCount / creatorCreatedCount
      : null;
  final creatorDeletedPosts = optionalCount(dev['twitter_del_post_token_count']);
  final creatorPromotedTokens = optionalCount(dev['twitter_create_token_count']);

  final txTotal = (buys5m != null && sells5m != null) ? buys5m + sells5m : null;
  final swapCountConsistent = (swaps5m == null || txTotal == null)
      ? null
      : (swaps5m - txTotal).abs() <= math.max(2, (swaps5m * 0.05).ceil());
  final swapsPerHolder5m = (swaps5m != null && holderCount != null && holderCount > 0) ? (swaps5m / holderCount) : null;

  final holderList = holders is List ? holders : const [];
  final holderSampleDistinct = holderList
      .map((row) => row is Map ? normalizeAddress(row['address'], config.chain) : '')
      .where((s) => s.isNotEmpty)
      .toSet()
      .length;
  final holderSampleConsistent = (holderCount == null || holderSampleDistinct == 0) ? null : holderCount >= holderSampleDistinct;
  final sellBuyRatio = (buys5m != null && sells5m != null)
      ? (buys5m > 0 ? (sells5m / buys5m) : sells5m == 0 ? 0.0 : null)
      : null;

  final kolOnly = smartWallets != null && smartWallets <= 1 && renownedWallets != null && renownedWallets > 0;
  final activityHolderMismatch = swaps5m != null &&
      swaps5m >= 100 &&
      swapsPerHolder5m != null &&
      swapsPerHolder5m >= 15 &&
      smartWallets != null &&
      smartWallets < 2;
  final distributionFlow = priceChange5m != null &&
      priceChange5m >= 0.12 &&
      buys5m != null &&
      sells5m != null &&
      sells5m >= 20 &&
      (buys5m == 0 || (sellBuyRatio != null && sellBuyRatio >= 1.5));
  final oldSuddenPump = ageSec != null && ageSec >= 24 * 60 * 60 && priceChange5m != null && priceChange5m >= 0.35;
  final fadingPump = observation?.pass == true &&
      optionalSignedRate(observation?.return5m) != null &&
      observation!.return5m >= 0.10 &&
      observation.volumeTrend == 'FALLING' &&
      observation.decliningVolumeBars >= 3;
  final repeatLauncherWithWeakHistory = creatorLaunchCount != null &&
      creatorLaunchCount >= 10 &&
      ((creatorOpenRatio != null && creatorOpenRatio < 0.20) ||
          (creatorDeletedPosts != null &&
              creatorDeletedPosts >= 3 &&
              creatorPromotedTokens != null &&
              creatorPromotedTokens > 0 &&
              (creatorDeletedPosts / creatorPromotedTokens) >= 0.50));
  final repeatLauncherStillHolding = creatorLaunchCount != null && creatorLaunchCount >= 10 && creatorStatus == 'HOLDING';

  final downgradeReasons = <String>[];
  if (kolOnly) downgradeReasons.add('仅见KOL钱包，未见至少2个独立聪明钱钱包');
  if (swapCountConsistent == false) downgradeReasons.add('5分钟买卖笔数与总交换数不一致');
  if (holderSampleConsistent == false) downgradeReasons.add('持有人总数小于已返回的独立钱包样本');
  if (activityHolderMismatch) downgradeReasons.add('5分钟交易笔数与持有人数量严重不匹配');
  if (distributionFlow) downgradeReasons.add('短时上涨同时卖单显著压过买单，疑似分发阶段');
  if (oldSuddenPump) downgradeReasons.add('老盘5分钟突然大幅拉升，等待避免追高');
  if (fadingPump) downgradeReasons.add('价格上涨但连续缩量，等待确认承接');
  if (repeatLauncherWithWeakHistory) downgradeReasons.add('创建者反复发币且可验证历史质量偏弱');
  if (repeatLauncherStillHolding) downgradeReasons.add('创建者反复发币且当前仍持币');

  final warnings = <String>[];
  if (creatorLaunchCount != null && creatorLaunchCount >= 10) warnings.add('创建者历史发币$creatorLaunchCount个');
  if (creatorStatus == 'UNKNOWN') warnings.add('创建者当前持币状态未知');

  final strengths = <String>[];
  if (smartWallets != null && smartWallets >= 3) strengths.add('$smartWallets个聪明钱钱包形成多钱包验证');
  if (smartWallets == 2) strengths.add('2个聪明钱钱包，只有轻度加分');

  final unknownFields = <String>[];
  if (smartWallets == null) unknownFields.add('marketBehavior.smartWallets');
  if (renownedWallets == null) unknownFields.add('marketBehavior.renownedWallets');
  if (holderCount == null) unknownFields.add('marketBehavior.holderCount');
  if (swaps5m == null) unknownFields.add('marketBehavior.swaps5m');
  if (buys5m == null) unknownFields.add('marketBehavior.buys5m');
  if (sells5m == null) unknownFields.add('marketBehavior.sells5m');
  if (volume5m == null) unknownFields.add('marketBehavior.volume5m');
  if (priceChange5m == null) unknownFields.add('marketBehavior.priceChange5m');
  if (ageSec == null) unknownFields.add('marketBehavior.age');
  if (creatorLaunchCount == null) unknownFields.add('marketBehavior.creatorLaunchCount');

  return MarketBehaviorResult(
    pass: downgradeReasons.isEmpty,
    status: downgradeReasons.isNotEmpty ? 'WAITING' : 'PASS',
    downgradeReasons: downgradeReasons,
    warnings: warnings,
    strengths: strengths,
    unknownFields: unknownFields,
    evidence: {
      'smartWallets': smartWallets,
      'renownedWallets': renownedWallets,
      'taggedSmartWallets': tagEvidence.smartWallets,
      'taggedRenownedWallets': tagEvidence.renownedWallets,
      'sampledTaggedWallets': tagEvidence.sampledTaggedWallets,
      'holderCount': holderCount,
      'holderSampleDistinct': holderSampleDistinct,
      'swaps5m': swaps5m,
      'buys5m': buys5m,
      'sells5m': sells5m,
      'volume5m': volume5m,
      'priceChange5m': priceChange5m,
      'swapsPerHolder5m': swapsPerHolder5m,
      'swapCountConsistent': swapCountConsistent,
      'holderSampleConsistent': holderSampleConsistent,
      'sellBuyRatio': sellBuyRatio,
      'ageSec': ageSec,
      'creatorStatus': creatorStatus,
      'creatorLaunchCount': creatorLaunchCount,
      'creatorCreatedCount': creatorCreatedCount,
      'creatorGraduatedCount': creatorGraduatedCount,
      'creatorOpenRatio': creatorOpenRatio,
      'creatorDeletedPosts': creatorDeletedPosts,
      'creatorPromotedTokens': creatorPromotedTokens,
    },
  );
}

class ObserveFiveMinutesResult {
  final bool pass;
  final String status;
  final String reason;
  final int bars;
  final double return5m;
  final double maxDrawdown;
  final double volumeConcentration;
  final double totalVolume;
  final int activeBars;
  final double? volumeChange;
  final String volumeTrend;
  final int decliningVolumeBars;
  final int invalidBars;
  final int duplicateBars;
  final bool continuous;
  final bool fresh;
  final List<int>? gapsMs;
  final int? latestClosedAt;
  final int? stalenessMs;
  final List<String> unknownFields;

  ObserveFiveMinutesResult({
    required this.pass,
    required this.status,
    required this.reason,
    required this.bars,
    this.return5m = 0.0,
    this.maxDrawdown = 0.0,
    this.volumeConcentration = 1.0,
    this.totalVolume = 0.0,
    this.activeBars = 0,
    this.volumeChange,
    this.volumeTrend = 'UNKNOWN',
    this.decliningVolumeBars = 0,
    required this.invalidBars,
    required this.duplicateBars,
    required this.continuous,
    required this.fresh,
    this.gapsMs,
    this.latestClosedAt,
    this.stalenessMs,
    required this.unknownFields,
  });
}

ObserveFiveMinutesResult observeFiveMinutes(dynamic candles, [int? nowMsParam]) {
  final nowMs = nowMsParam ?? DateTime.now().millisecondsSinceEpoch;
  final source = candles is List ? candles : const [];
  final parsed = source.map((raw) {
    if (raw is! Map) return null;
    return {
      'time': optionalNumber(first([raw['time'], raw['t']])),
      'open': optionalNumber(raw['open']),
      'high': optionalNumber(raw['high']),
      'low': optionalNumber(raw['low']),
      'close': optionalNumber(raw['close']),
      'volume': optionalNumber(raw['volume']),
    };
  }).toList();

  final valid = parsed.where((row) {
    if (row == null) return false;
    final time = row['time'];
    final open = row['open'];
    final high = row['high'];
    final low = row['low'];
    final close = row['close'];
    final volume = row['volume'];
    return time != null &&
        time > 0 &&
        open != null &&
        open > 0 &&
        high != null &&
        high > 0 &&
        low != null &&
        low > 0 &&
        close != null &&
        close > 0 &&
        volume != null &&
        volume >= 0 &&
        high >= math.max(open, close) &&
        low <= math.min(open, close);
  }).map((e) => e!).toList();

  final invalidBars = source.length - valid.length;
  final uniqueMap = <double, Map<String, dynamic>>{};
  for (final row in valid) {
    uniqueMap[row['time'] as double] = row;
  }
  final unique = uniqueMap.values.toList();
  final duplicateBars = valid.length - unique.length;

  final rows = unique
      .where((row) => (row['time'] as double) + 60000 <= nowMs)
      .toList()
    ..sort((a, b) => (a['time'] as double).compareTo(b['time'] as double));
  final selectedRows = rows.length > 10 ? rows.sublist(rows.length - 10) : rows;

  if (selectedRows.length < 5) {
    return ObserveFiveMinutesResult(
      pass: false,
      status: 'WAITING',
      reason: '不足5根有效且已收盘的1分钟K线',
      bars: selectedRows.length,
      invalidBars: invalidBars,
      duplicateBars: duplicateBars,
      continuous: false,
      fresh: false,
      unknownFields: const ['candles'],
    );
  }

  final firstFive = selectedRows.sublist(selectedRows.length - 5);
  final start = firstFive[0]['open'] as double;
  final end = firstFive.last['close'] as double;
  final gapsMs = <int>[];
  for (var i = 1; i < firstFive.length; i++) {
    final gap = ((firstFive[i]['time'] as double) - (firstFive[i - 1]['time'] as double)).toInt();
    gapsMs.add(gap);
  }
  final continuous = gapsMs.every((gap) => (gap - 60000).abs() <= 1000);
  final latestClosedAt = ((firstFive.last['time'] as double) + 60000).toInt();
  final stalenessMs = math.max(0, nowMs - latestClosedAt);
  final fresh = stalenessMs <= 2 * 60000;

  if (!continuous) {
    return ObserveFiveMinutesResult(
      pass: false,
      status: 'WAITING',
      reason: '最近K线不连续，等待完整5分钟窗口',
      bars: firstFive.length,
      invalidBars: invalidBars,
      duplicateBars: duplicateBars,
      continuous: continuous,
      fresh: fresh,
      gapsMs: gapsMs,
      latestClosedAt: latestClosedAt,
      stalenessMs: stalenessMs,
      unknownFields: const ['candles.continuity'],
    );
  }

  if (!fresh) {
    return ObserveFiveMinutesResult(
      pass: false,
      status: 'WAITING',
      reason: '最近K线已过期，等待行情更新',
      bars: firstFive.length,
      invalidBars: invalidBars,
      duplicateBars: duplicateBars,
      continuous: continuous,
      fresh: fresh,
      gapsMs: gapsMs,
      latestClosedAt: latestClosedAt,
      stalenessMs: stalenessMs,
      unknownFields: const ['candles.freshness'],
    );
  }

  var peak = firstFive[0]['high'] as double;
  var maxDrawdown = 0.0;
  for (final row in firstFive) {
    final high = row['high'] as double;
    final low = row['low'] as double;
    peak = math.max(peak, high);
    final dd = peak > 0 ? (peak - low) / peak : 0.0;
    maxDrawdown = math.max(maxDrawdown, dd);
  }

  final volumes = firstFive.map((row) => row['volume'] as double).toList();
  final totalVolume = volumes.fold<double>(0.0, (a, b) => a + b);
  final volumeConcentration = totalVolume > 0 ? (volumes.reduce(math.max) / totalVolume) : 1.0;
  final earlyVolume = (volumes[0] + volumes[1]) / 2.0;
  final recentVolume = (volumes[volumes.length - 2] + volumes.last) / 2.0;
  final volumeChange = earlyVolume > 0 ? (recentVolume / earlyVolume - 1.0) : (recentVolume > 0 ? null : 0.0);
  final volumeTrend = volumeChange == null
      ? 'UNKNOWN'
      : volumeChange > 0.15
          ? 'RISING'
          : volumeChange < -0.15
              ? 'FALLING'
              : 'STABLE';
  var decliningVolumeBars = 0;
  for (var i = 1; i < volumes.length; i++) {
    if (volumes[i] < volumes[i - 1]) decliningVolumeBars++;
  }

  final return5m = end / start - 1.0;
  final activeBars = volumes.where((v) => v > 0).length;
  final pass = return5m >= -0.12 &&
      return5m <= 0.80 &&
      maxDrawdown <= 0.25 &&
      volumeConcentration <= 0.65 &&
      activeBars >= 4;

  final reason = return5m < -0.12
      ? '观察期跌幅过大'
      : return5m > 0.80
          ? '5分钟涨幅过大，拒绝追高'
          : maxDrawdown > 0.25
              ? '观察期最大回撤过大'
              : volumeConcentration > 0.65
                  ? '成交集中在单根K线，疑似机器脉冲'
                  : activeBars < 4
                      ? '多数分钟无成交'
                      : '5分钟盘面通过';

  return ObserveFiveMinutesResult(
    pass: pass,
    status: pass ? 'PASS' : 'FAIL',
    reason: reason,
    bars: firstFive.length,
    return5m: return5m,
    maxDrawdown: maxDrawdown,
    volumeConcentration: volumeConcentration,
    totalVolume: totalVolume,
    activeBars: activeBars,
    volumeChange: volumeChange,
    volumeTrend: volumeTrend,
    decliningVolumeBars: decliningVolumeBars,
    invalidBars: invalidBars,
    duplicateBars: duplicateBars,
    continuous: continuous,
    fresh: fresh,
    gapsMs: gapsMs,
    latestClosedAt: latestClosedAt,
    stalenessMs: stalenessMs,
    unknownFields: const [],
  );
}

double? _unixSeconds(dynamic value) {
  final parsed = optionalNumber(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed >= 1000000000000 ? parsed / 1000.0 : parsed;
}

class EmpiricalSellabilityResult {
  final bool pass;
  final double? sells5m;
  final double? sells24h;
  final int distinctSellers;
  final int historicalDistinctSellers;
  final int windowSec;
  final List<String> unknownFields;
  final String evidenceType;
  final String evidenceNote;

  EmpiricalSellabilityResult({
    required this.pass,
    this.sells5m,
    this.sells24h,
    required this.distinctSellers,
    required this.historicalDistinctSellers,
    required this.windowSec,
    required this.unknownFields,
    this.evidenceType = 'recent_active_seller_proxy',
    this.evidenceNote = '不同卖家按最近链上活跃时间近似对齐5分钟窗口；活跃动作不一定就是卖出，仍不是合约级卖出保证。',
  });
}

EmpiricalSellabilityResult empiricalSellability({
  Map<String, dynamic> info = const {},
  Map<String, dynamic> discovery = const {},
  dynamic traders = const [],
  double? nowSecParam,
  int windowSec = 5 * 60,
  String chain = 'robinhood',
}) {
  final nowSec = nowSecParam ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
  final price = info['price'] is Map ? info['price'] as Map : const {};
  final sells5m = optionalNumber(first([price['sells_5m'], discovery['sells_5m'], discovery['sells']]));
  final sells24h = optionalNumber(first([price['sells_24h'], discovery['sells_24h']]));

  final unique = <String, Map<String, dynamic>>{};
  final list = traders is List ? traders : const [];
  for (final row in list) {
    if (row is! Map) continue;
    final address = normalizeAddress(row['address'], chain);
    if (address.isEmpty) continue;
    final sellTxCount = optionalNumber(row['sell_tx_count_cur']);
    final lastActiveAt = _unixSeconds(first([row['last_active_timestamp'], row['last_active_at']]));
    final previous = unique[address] ?? {'address': address, 'sellTxCount': null, 'lastActiveAt': null};

    final prevTx = previous['sellTxCount'] as double?;
    final prevAct = previous['lastActiveAt'] as double?;

    unique[address] = {
      'address': address,
      'sellTxCount': sellTxCount == null ? prevTx : math.max(prevTx ?? 0.0, sellTxCount),
      'lastActiveAt': lastActiveAt == null ? prevAct : math.max(prevAct ?? 0.0, lastActiveAt),
    };
  }

  final historicalSellers = unique.values
      .where((row) => row['sellTxCount'] != null && (row['sellTxCount'] as double) > 0)
      .toList();
  final recentActiveSellers = historicalSellers.where((row) {
    final act = row['lastActiveAt'] as double?;
    return act != null && act >= (nowSec - windowSec) && act <= (nowSec + 60);
  }).toList();

  final historicalDistinctSellers = historicalSellers.length;
  final distinctSellers = recentActiveSellers.length;

  final unknownFields = <String>[];
  if (sells5m == null) unknownFields.add('sellability.sells5m');
  if (sells24h == null) unknownFields.add('sellability.sells24h');
  if (historicalSellers.any((row) => row['lastActiveAt'] == null)) {
    unknownFields.add('sellability.traderLastActiveAt');
  }

  final pass = unknownFields.isEmpty && (sells5m != null && sells5m >= 2) && (sells24h != null && sells24h >= 10) && distinctSellers >= 5;

  return EmpiricalSellabilityResult(
    pass: pass,
    sells5m: sells5m,
    sells24h: sells24h,
    distinctSellers: distinctSellers,
    historicalDistinctSellers: historicalDistinctSellers,
    windowSec: windowSec,
    unknownFields: unknownFields,
  );
}

class DeepScreenResult {
  final bool chainPass;
  final List<String> failed;
  final Map<String, bool> checks;
  final AnalyzeWalletsResult wallets;
  final ObserveFiveMinutesResult observation;
  final ChartRiskResult chartRisk;
  final MarketBehaviorResult marketBehavior;
  final EmpiricalSellabilityResult sellability;
  final String honeypotEvidence;
  final List<String> unknownFields;
  final List<String> blockingUnknownFields;
  final Map<String, dynamic> security;

  DeepScreenResult({
    required this.chainPass,
    required this.failed,
    required this.checks,
    required this.wallets,
    required this.observation,
    required this.chartRisk,
    required this.marketBehavior,
    required this.sellability,
    required this.honeypotEvidence,
    required this.unknownFields,
    required this.blockingUnknownFields,
    required this.security,
  });
}

DeepScreenResult deepScreen(
  RadarConfig config, {
  required Map<String, dynamic> discovery,
  required Map<String, dynamic> audit,
  int? nowMsParam,
}) {
  final nowMs = nowMsParam ?? DateTime.now().millisecondsSinceEpoch;
  final info = audit['info'] is Map ? Map<String, dynamic>.from(audit['info'] as Map) : const <String, dynamic>{};
  final pool = audit['pool'] is Map ? Map<String, dynamic>.from(audit['pool'] as Map) : const <String, dynamic>{};
  final secAudit = audit['security'] is Map ? Map<String, dynamic>.from(audit['security'] as Map) : const <String, dynamic>{};
  final sec = securityView(secAudit, discovery, info);

  final isSol = _lower(config.chain) == 'sol';
  final openSource = optionalBoolean(sec['openSource']);
  final ownerRenounced = optionalBoolean(sec['ownerRenounced']);
  final renouncedMint = optionalBoolean(sec['renouncedMint']);
  final renouncedFreezeAccount = optionalBoolean(sec['renouncedFreezeAccount']);
  final honeypot = optionalBoolean(sec['honeypot']);
  final buyTax = optionalRate(sec['buyTax']);
  final sellTax = optionalRate(sec['sellTax']);
  final rugRatio = optionalRate(sec['rugRatio']);
  final top10 = optionalRate(sec['top10']);
  final devHold = optionalRate(sec['devHold']);
  final insider = optionalRate(sec['insider']);
  final bundler = optionalRate(sec['bundler']);
  final sniperHold = optionalRate(sec['sniperHold']);
  final wash = optionalBoolean(sec['wash']);
  final liquidityValue = optionalNumber(first([pool['liquidity'], info['liquidity'], discovery['liquidity']]));
  final liquidity = liquidityValue ?? 0.0;
  final lockRate = optionalRate(first([sec['lockRate'], info['locked_ratio']]));
  final lpBurned = _lower(sec['burnStatus']) == 'burn';

  final wallets = analyzeWallets(audit['holders'], config);
  final observation = observeFiveMinutes(audit['candles'], nowMs);
  final chartRisk = chartRiskScreen(audit['candles'], nowMs);
  final marketBehavior = marketBehaviorScreen(
    config,
    discovery: discovery,
    info: info,
    holders: audit['holders'],
    observation: observation,
    nowMs: nowMs,
  );
  final sellability = empiricalSellability(
    info: info,
    discovery: discovery,
    traders: audit['traders'],
    nowSecParam: nowMs / 1000.0,
    chain: config.chain,
  );

  final exactNotHoneypot = honeypot == false;
  final explicitHoneypot = honeypot == true;

  final checks = <String, bool>{
    'openSource': openSource == true,
    'ownerRenounced': isSol ? (renouncedMint == true && renouncedFreezeAccount == true) : (ownerRenounced == true),
    'lpLocked': lpBurned || (lockRate != null && lockRate >= config.minLpLockedRate),
    'notHoneypot': isSol || exactNotHoneypot || (!explicitHoneypot && sellability.pass),
    'tax': buyTax != null &&
        sellTax != null &&
        buyTax <= config.maxBuyTax &&
        sellTax <= config.maxSellTax &&
        (buyTax - sellTax).abs() <= config.maxTaxAsymmetry,
    'rug': rugRatio != null && rugRatio <= config.maxRugRatio,
    'concentration': top10 != null && top10 <= config.maxTop10Rate,
    'dev': devHold != null && devHold <= 0.01,
    'insider': insider != null && insider <= config.maxInsiderRate,
    'bundler': bundler != null && bundler <= config.maxBundlerRate,
    'sniper': sniperHold != null && sniperHold <= config.maxSniperHoldRate,
    'wash': wash == false,
    'liquidity': liquidityValue != null && liquidity >= config.strictLiquidity,
    'wallets': wallets.pass,
    'observation': observation.pass,
    'chartRisk': chartRisk.pass,
    'marketBehavior': marketBehavior.pass,
  };

  final failed = checks.entries.where((e) => !e.value).map((e) => e.key).toList();
  final chainPass = failed.isEmpty;
  final honeypotEvidence = isSol
      ? 'SOL不使用EVM貔貅字段；以铸币和冻结权限为安全基线'
      : exactNotHoneypot
          ? '安全证据明确非貔貅'
          : sellability.pass
              ? '经验卖出证据'
              : explicitHoneypot
                  ? '检测到貔貅'
                  : '未验证';

  final unknownFields = <String>[];
  if (openSource == null) unknownFields.add('openSource');
  if (!isSol && ownerRenounced == null) unknownFields.add('ownerRenounced');
  if (isSol && renouncedMint == null) unknownFields.add('renouncedMint');
  if (isSol && renouncedFreezeAccount == null) unknownFields.add('renouncedFreezeAccount');
  if (!isSol && honeypot == null) unknownFields.add('honeypot');
  if (buyTax == null) unknownFields.add('buyTax');
  if (sellTax == null) unknownFields.add('sellTax');
  if (rugRatio == null) unknownFields.add('rugRatio');
  if (top10 == null) unknownFields.add('top10');
  if (devHold == null) unknownFields.add('devHold');
  if (insider == null) unknownFields.add('insider');
  if (bundler == null) unknownFields.add('bundler');
  if (sniperHold == null) unknownFields.add('sniperHold');
  if (wash == null) unknownFields.add('wash');
  if (!lpBurned && lockRate == null) unknownFields.add('lockRate');
  if (liquidityValue == null) unknownFields.add('liquidity');
  unknownFields.addAll(wallets.unknownFields);
  unknownFields.addAll(observation.unknownFields);
  unknownFields.addAll(chartRisk.unknownFields);
  if (!isSol && honeypot != false) {
    unknownFields.addAll(sellability.unknownFields);
  }

  final blockingUnknownFields = <String>[];
  if (openSource == null) blockingUnknownFields.add('openSource');
  if (!isSol && ownerRenounced == null) blockingUnknownFields.add('ownerRenounced');
  if (isSol && renouncedMint == null) blockingUnknownFields.add('renouncedMint');
  if (isSol && renouncedFreezeAccount == null) blockingUnknownFields.add('renouncedFreezeAccount');
  if (!isSol && honeypot == null && !sellability.pass) blockingUnknownFields.add('honeypot');
  if (buyTax == null) blockingUnknownFields.add('buyTax');
  if (sellTax == null) blockingUnknownFields.add('sellTax');
  if (rugRatio == null) blockingUnknownFields.add('rugRatio');
  if (top10 == null) blockingUnknownFields.add('top10');
  if (devHold == null) blockingUnknownFields.add('devHold');
  if (insider == null) blockingUnknownFields.add('insider');
  if (bundler == null) blockingUnknownFields.add('bundler');
  if (sniperHold == null) blockingUnknownFields.add('sniperHold');
  if (wash == null) blockingUnknownFields.add('wash');
  if (!lpBurned && lockRate == null) blockingUnknownFields.add('lockRate');
  if (liquidityValue == null) blockingUnknownFields.add('liquidity');
  blockingUnknownFields.addAll(wallets.unknownFields);
  if (observation.status == 'WAITING') {
    blockingUnknownFields.addAll(observation.unknownFields);
  }
  blockingUnknownFields.addAll(chartRisk.unknownFields);
  if (!isSol && honeypot == null && !sellability.pass) {
    blockingUnknownFields.addAll(sellability.unknownFields);
  }

  return DeepScreenResult(
    chainPass: chainPass,
    failed: failed,
    checks: checks,
    wallets: wallets,
    observation: observation,
    chartRisk: chartRisk,
    marketBehavior: marketBehavior,
    sellability: sellability,
    honeypotEvidence: honeypotEvidence,
    unknownFields: unknownFields.toSet().toList(),
    blockingUnknownFields: blockingUnknownFields.toSet().toList(),
    security: {
      'openSource': openSource,
      'ownerRenounced': isSol ? (renouncedMint == true && renouncedFreezeAccount == true) : ownerRenounced,
      'evmOwnerRenounced': ownerRenounced,
      'renouncedMint': renouncedMint,
      'renouncedFreezeAccount': renouncedFreezeAccount,
      'honeypot': honeypot,
      'buyTax': buyTax,
      'sellTax': sellTax,
      'taxDifference': (buyTax != null && sellTax != null) ? (buyTax - sellTax).abs() : null,
      'rugRatio': rugRatio,
      'top10': top10,
      'devHold': devHold,
      'creatorStatus': normalizedCreatorStatus(sec['creatorStatus']),
      'insider': insider,
      'bundler': bundler,
      'sniperHold': sniperHold,
      'wash': wash,
      'lockRate': lockRate,
      'lpBurned': lpBurned,
      'liquidity': liquidityValue,
    },
  );
}
