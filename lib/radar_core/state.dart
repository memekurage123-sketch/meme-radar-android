/// Faithful Dart port of upstream `src/state.mjs` at commit 7ecd342
import 'live_leads.dart';

class RadarState {
  int version;
  String status;
  int generatedAt;
  int lastAttemptAt;
  int lastSuccessAt;
  int nextCycleAt;
  int cycleStartedAt;
  bool scanInProgress;
  String activeChain;
  String pendingChain;
  List<String> supportedChains;
  Map<String, dynamic> chainStates;
  Map<String, dynamic> riskExclusions;
  int scanCount;
  int discoveredCount;
  int prequalifiedCount;
  List<Map<String, dynamic>> candidates;
  List<Map<String, dynamic>> rejected;
  List<Map<String, dynamic>> auditQueue;
  List<Map<String, dynamic>> liveLeads;
  Map<String, dynamic> auditQueueStats;
  List<Map<String, dynamic>> outcomes;
  Map<String, dynamic> outcomeSummary;
  Map<String, dynamic> sourceHealth;
  List<Map<String, dynamic>> events;

  RadarState({
    this.version = 2,
    this.status = 'STARTING',
    this.generatedAt = 0,
    this.lastAttemptAt = 0,
    this.lastSuccessAt = 0,
    this.nextCycleAt = 0,
    this.cycleStartedAt = 0,
    this.scanInProgress = false,
    this.activeChain = 'bsc',
    this.pendingChain = '',
    this.supportedChains = const ['sol', 'bsc', 'base', 'eth', 'robinhood'],
    Map<String, dynamic>? chainStates,
    Map<String, dynamic>? riskExclusions,
    this.scanCount = 0,
    this.discoveredCount = 0,
    this.prequalifiedCount = 0,
    List<Map<String, dynamic>>? candidates,
    List<Map<String, dynamic>>? rejected,
    List<Map<String, dynamic>>? auditQueue,
    List<Map<String, dynamic>>? liveLeads,
    Map<String, dynamic>? auditQueueStats,
    List<Map<String, dynamic>>? outcomes,
    Map<String, dynamic>? outcomeSummary,
    Map<String, dynamic>? sourceHealth,
    List<Map<String, dynamic>>? events,
  })  : chainStates = chainStates ?? {},
        riskExclusions = riskExclusions ?? {},
        candidates = candidates ?? [],
        rejected = rejected ?? [],
        auditQueue = auditQueue ?? [],
        liveLeads = liveLeads ?? [],
        auditQueueStats = auditQueueStats ??
            {'total': 0, 'due': 0, 'neverAudited': 0, 'waitingRecheck': 0},
        outcomes = outcomes ?? [],
        outcomeSummary = outcomeSummary ??
            {
              'minimumSample': 50,
              'calibrationReady': false,
              'tracked': 0,
              'completed5m': 0,
              'completed15m': 0,
              'completed30m': 0,
              'completed1h': 0,
              'completed2h': 0,
              'completed6h': 0,
              'completed24h': 0,
            },
        sourceHealth = sourceHealth ?? {},
        events = events ?? [];

  void addEvent(String type, String message, [Map<String, dynamic>? data]) {
    events.insert(0, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'message': message,
      if (data != null) ...data,
    });
    if (events.length > 500) {
      events = events.sublist(0, 500);
    }
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'status': status,
        'generatedAt': generatedAt,
        'lastAttemptAt': lastAttemptAt,
        'lastSuccessAt': lastSuccessAt,
        'nextCycleAt': nextCycleAt,
        'cycleStartedAt': cycleStartedAt,
        'scanInProgress': scanInProgress,
        'activeChain': activeChain,
        'pendingChain': pendingChain,
        'supportedChains': supportedChains,
        'chainStates': chainStates,
        'riskExclusions': riskExclusions,
        'scanCount': scanCount,
        'discoveredCount': discoveredCount,
        'prequalifiedCount': prequalifiedCount,
        'candidates': candidates,
        'rejected': rejected,
        'auditQueue': auditQueue,
        'liveLeads': liveLeads,
        'auditQueueStats': auditQueueStats,
        'outcomes': outcomes,
        'outcomeSummary': outcomeSummary,
        'sourceHealth': sourceHealth,
        'events': events,
      };

  factory RadarState.fromMap(Map<String, dynamic> raw) {
    final active = raw['activeChain']?.toString() ?? 'bsc';
    final rawLeads =
        raw['liveLeads'] is List ? (raw['liveLeads'] as List) : const [];
    final cleanLeads = <Map<String, dynamic>>[];
    for (final r in rawLeads) {
      final lead = sanitizeLiveLead(r, active);
      if (lead != null) cleanLeads.add(lead);
    }

    return RadarState(
      version: raw['version'] as int? ?? 2,
      status: raw['status']?.toString() ?? 'STARTING',
      generatedAt: raw['generatedAt'] as int? ?? 0,
      lastAttemptAt: raw['lastAttemptAt'] as int? ?? 0,
      lastSuccessAt: raw['lastSuccessAt'] as int? ?? 0,
      nextCycleAt: raw['nextCycleAt'] as int? ?? 0,
      cycleStartedAt: raw['cycleStartedAt'] as int? ?? 0,
      scanInProgress: false,
      activeChain: active,
      pendingChain: raw['pendingChain']?.toString() ?? '',
      supportedChains: (raw['supportedChains'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['sol', 'bsc', 'base', 'eth', 'robinhood'],
      chainStates: raw['chainStates'] is Map
          ? Map<String, dynamic>.from(raw['chainStates'] as Map)
          : {},
      riskExclusions: raw['riskExclusions'] is Map
          ? Map<String, dynamic>.from(raw['riskExclusions'] as Map)
          : {},
      scanCount: raw['scanCount'] as int? ?? 0,
      discoveredCount: raw['discoveredCount'] as int? ?? 0,
      prequalifiedCount: raw['prequalifiedCount'] as int? ?? 0,
      candidates: (raw['candidates'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      rejected: (raw['rejected'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      auditQueue: (raw['auditQueue'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      liveLeads: cleanLeads,
      outcomes: (raw['outcomes'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      events: (raw['events'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
    );
  }
}
