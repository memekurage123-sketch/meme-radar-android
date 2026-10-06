/// Faithful Dart port of upstream `src/config.mjs` at commit 7ecd342
class RadarConfig {
  final String chain;
  final List<String> supportedChains;
  final int port;
  final int scanIntervalMs;
  final int maxDeepAuditsPerCycle;
  final int auditCycleBudgetMs;
  final int outcomeReadsPerCycle;
  final String xReviewMode;

  final int minAgeSec;
  final int maxAgeSec;
  final double discoveryMinMarketCap;
  final double discoveryMaxMarketCap;
  final double priorityMinMarketCap;
  final double priorityMaxMarketCap;
  final double minLiquidity;
  final double strictLiquidity;

  final int matureMarketAgeSec;
  final int oldMarketAgeSec;
  final double minMatureVolume5mUsd;
  final double minOldVolume5mUsd;
  final double minMatureTurnover5m;
  final double minOldTurnover5m;
  final double maxCollapsedAthRatio;
  final double strongRebound1h;

  final double maxRugRatio;
  final double maxTop10Rate;
  final double maxInsiderRate;
  final double maxBundlerRate;
  final double maxSniperHoldRate;
  final double maxBotHoldRate;
  final double maxLinkedHoldRate;
  final double maxBuyTax;
  final double maxSellTax;
  final double maxTaxAsymmetry;
  final double minLpLockedRate;
  final int minOrdinaryWallets;

  final int dynamicRecheckMs;
  final int chainPassRecheckMs;
  final int hardRejectRecheckMs;
  final int queueRetentionMs;
  final int candidateRetentionMs;
  final int liveLeadRetentionMs;
  final int staleCandidateMs;
  final int outcomeRetentionMs;

  const RadarConfig({
    this.chain = 'robinhood',
    this.supportedChains = const ['sol', 'bsc', 'base', 'eth', 'robinhood'],
    this.port = 3791,
    this.scanIntervalMs = 300000,
    this.maxDeepAuditsPerCycle = 0,
    this.auditCycleBudgetMs = 80000,
    this.outcomeReadsPerCycle = 0,
    this.xReviewMode = 'manual',
    this.minAgeSec = 5 * 60,
    this.maxAgeSec = 7 * 86400,
    this.discoveryMinMarketCap = 10000.0,
    this.discoveryMaxMarketCap = 150000.0,
    this.priorityMinMarketCap = 20000.0,
    this.priorityMaxMarketCap = 80000.0,
    this.minLiquidity = 3000.0,
    this.strictLiquidity = 8000.0,
    this.matureMarketAgeSec = 60 * 60,
    this.oldMarketAgeSec = 6 * 60 * 60,
    this.minMatureVolume5mUsd = 100.0,
    this.minOldVolume5mUsd = 250.0,
    this.minMatureTurnover5m = 0.005,
    this.minOldTurnover5m = 0.01,
    this.maxCollapsedAthRatio = 0.10,
    this.strongRebound1h = 0.20,
    this.maxRugRatio = 0.20,
    this.maxTop10Rate = 0.30,
    this.maxInsiderRate = 0.15,
    this.maxBundlerRate = 0.15,
    this.maxSniperHoldRate = 0.08,
    this.maxBotHoldRate = 0.20,
    this.maxLinkedHoldRate = 0.10,
    this.maxBuyTax = 0.05,
    this.maxSellTax = 0.05,
    this.maxTaxAsymmetry = 0.02,
    this.minLpLockedRate = 0.80,
    this.minOrdinaryWallets = 8,
    this.dynamicRecheckMs = 2 * 60000,
    this.chainPassRecheckMs = 5 * 60000,
    this.hardRejectRecheckMs = 6 * 60 * 60000,
    this.queueRetentionMs = 24 * 60 * 60000,
    this.candidateRetentionMs = 2 * 60 * 60000,
    this.liveLeadRetentionMs = 30 * 60000,
    this.staleCandidateMs = 10 * 60000,
    this.outcomeRetentionMs = 7 * 24 * 60 * 60000,
  });

  RadarConfig copyWith({
    String? chain,
    List<String>? supportedChains,
    int? port,
    int? scanIntervalMs,
    int? maxDeepAuditsPerCycle,
    int? auditCycleBudgetMs,
    int? outcomeReadsPerCycle,
    String? xReviewMode,
    int? minAgeSec,
    int? maxAgeSec,
    double? discoveryMinMarketCap,
    double? discoveryMaxMarketCap,
    double? priorityMinMarketCap,
    double? priorityMaxMarketCap,
    double? minLiquidity,
    double? strictLiquidity,
    int? matureMarketAgeSec,
    int? oldMarketAgeSec,
    double? minMatureVolume5mUsd,
    double? minOldVolume5mUsd,
    double? minMatureTurnover5m,
    double? minOldTurnover5m,
    double? maxCollapsedAthRatio,
    double? strongRebound1h,
    double? maxRugRatio,
    double? maxTop10Rate,
    double? maxInsiderRate,
    double? maxBundlerRate,
    double? maxSniperHoldRate,
    double? maxBotHoldRate,
    double? maxLinkedHoldRate,
    double? maxBuyTax,
    double? maxSellTax,
    double? maxTaxAsymmetry,
    double? minLpLockedRate,
    int? minOrdinaryWallets,
    int? dynamicRecheckMs,
    int? chainPassRecheckMs,
    int? hardRejectRecheckMs,
    int? queueRetentionMs,
    int? candidateRetentionMs,
    int? liveLeadRetentionMs,
    int? staleCandidateMs,
    int? outcomeRetentionMs,
  }) {
    return RadarConfig(
      chain: chain ?? this.chain,
      supportedChains: supportedChains ?? this.supportedChains,
      port: port ?? this.port,
      scanIntervalMs: scanIntervalMs ?? this.scanIntervalMs,
      maxDeepAuditsPerCycle:
          maxDeepAuditsPerCycle ?? this.maxDeepAuditsPerCycle,
      auditCycleBudgetMs: auditCycleBudgetMs ?? this.auditCycleBudgetMs,
      outcomeReadsPerCycle: outcomeReadsPerCycle ?? this.outcomeReadsPerCycle,
      xReviewMode: xReviewMode ?? this.xReviewMode,
      minAgeSec: minAgeSec ?? this.minAgeSec,
      maxAgeSec: maxAgeSec ?? this.maxAgeSec,
      discoveryMinMarketCap:
          discoveryMinMarketCap ?? this.discoveryMinMarketCap,
      discoveryMaxMarketCap:
          discoveryMaxMarketCap ?? this.discoveryMaxMarketCap,
      priorityMinMarketCap: priorityMinMarketCap ?? this.priorityMinMarketCap,
      priorityMaxMarketCap: priorityMaxMarketCap ?? this.priorityMaxMarketCap,
      minLiquidity: minLiquidity ?? this.minLiquidity,
      strictLiquidity: strictLiquidity ?? this.strictLiquidity,
      matureMarketAgeSec: matureMarketAgeSec ?? this.matureMarketAgeSec,
      oldMarketAgeSec: oldMarketAgeSec ?? this.oldMarketAgeSec,
      minMatureVolume5mUsd: minMatureVolume5mUsd ?? this.minMatureVolume5mUsd,
      minOldVolume5mUsd: minOldVolume5mUsd ?? this.minOldVolume5mUsd,
      minMatureTurnover5m: minMatureTurnover5m ?? this.minMatureTurnover5m,
      minOldTurnover5m: minOldTurnover5m ?? this.minOldTurnover5m,
      maxCollapsedAthRatio: maxCollapsedAthRatio ?? this.maxCollapsedAthRatio,
      strongRebound1h: strongRebound1h ?? this.strongRebound1h,
      maxRugRatio: maxRugRatio ?? this.maxRugRatio,
      maxTop10Rate: maxTop10Rate ?? this.maxTop10Rate,
      maxInsiderRate: maxInsiderRate ?? this.maxInsiderRate,
      maxBundlerRate: maxBundlerRate ?? this.maxBundlerRate,
      maxSniperHoldRate: maxSniperHoldRate ?? this.maxSniperHoldRate,
      maxBotHoldRate: maxBotHoldRate ?? this.maxBotHoldRate,
      maxLinkedHoldRate: maxLinkedHoldRate ?? this.maxLinkedHoldRate,
      maxBuyTax: maxBuyTax ?? this.maxBuyTax,
      maxSellTax: maxSellTax ?? this.maxSellTax,
      maxTaxAsymmetry: maxTaxAsymmetry ?? this.maxTaxAsymmetry,
      minLpLockedRate: minLpLockedRate ?? this.minLpLockedRate,
      minOrdinaryWallets: minOrdinaryWallets ?? this.minOrdinaryWallets,
      dynamicRecheckMs: dynamicRecheckMs ?? this.dynamicRecheckMs,
      chainPassRecheckMs: chainPassRecheckMs ?? this.chainPassRecheckMs,
      hardRejectRecheckMs: hardRejectRecheckMs ?? this.hardRejectRecheckMs,
      queueRetentionMs: queueRetentionMs ?? this.queueRetentionMs,
      candidateRetentionMs: candidateRetentionMs ?? this.candidateRetentionMs,
      liveLeadRetentionMs: liveLeadRetentionMs ?? this.liveLeadRetentionMs,
      staleCandidateMs: staleCandidateMs ?? this.staleCandidateMs,
      outcomeRetentionMs: outcomeRetentionMs ?? this.outcomeRetentionMs,
    );
  }
}
