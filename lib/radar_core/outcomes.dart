/// Faithful Dart port of upstream `src/outcomes.mjs` at commit 7ecd342
import 'dart:convert';
import 'package:crypto/crypto.dart';

const Map<String, int> horizons = {
  'm5': 300000,
  'm15': 900000,
  'm30': 1800000,
  'h1': 3600000,
  'h2': 7200000,
  'h6': 21600000,
  'h24': 86400000,
};

const int maxSampleAttempts = 3;
const int maxSampleLatenessMs = 24 * 3600000;
const Set<String> pauseCodes = {
  'AVE_RATE_LIMITED',
  'AVE_BUDGET',
  'AVE_HOURLY_BUDGET',
  'AVE_TOTAL_BUDGET',
  'AVE_QUOTA',
  'AVE_DISCOVERY_RESERVE',
  'AVE_ABORTED',
  'AVE_CHANGED',
  'AVE_DISABLED',
};

List<Map<String, dynamic>> sampleRejected(
  List<Map<String, dynamic>> outcomes,
  Map<String, dynamic> candidate,
  int now,
) {
  final price = candidate['price'] is num ? (candidate['price'] as num).toDouble() : 0.0;
  if (candidate['status'] != 'HARD_REJECT' || price <= 0) return outcomes;
  if (outcomes.any((row) => row['address'] == candidate['address'])) return outcomes;

  // Stable 1-in-5 sampling, independent of subsequent returns or popularity.
  final input = utf8.encode('${candidate['chain']}:${candidate['address']}');
  final digest = sha256.convert(input).bytes;
  if (digest[0] % 5 != 0 || outcomes.where((row) => row['initialDecision'] == 'HARD_REJECT').length >= 200) {
    return outcomes;
  }

  final deep = candidate['deep'] is Map ? candidate['deep'] as Map : const {};
  final failed = (deep['failed'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

  outcomes.add({
    'chain': candidate['chain'],
    'address': candidate['address'],
    'symbol': candidate['symbol'],
    'baselineAt': now,
    'baselinePrice': price,
    'baselineProvider': candidate['marketProvider'] ?? 'LEGACY_UNKNOWN',
    'initialDecision': 'HARD_REJECT',
    'latestDecision': candidate['status'],
    'latestFailed': failed,
    'samples': <String, dynamic>{},
    'sampling': 'SHA256_MOD5',
    'strategyVersion': 'radar-v3',
  });
  return outcomes;
}

class DueOutcomeJob {
  final Map<String, dynamic> row;
  final String key;
  final int targetAt;
  final String? chain;

  DueOutcomeJob({
    required this.row,
    required this.key,
    required this.targetAt,
    this.chain,
  });
}

List<DueOutcomeJob> dueOutcomeJobs(List<Map<String, dynamic>> outcomes, int now) {
  final jobs = <DueOutcomeJob>[];
  for (final row in outcomes) {
    final samples = (row['samples'] as Map?) ?? const {};
    final sampleRetries = (row['sampleRetries'] as Map?) ?? const {};
    final baselineAt = (row['baselineAt'] as num?)?.toInt() ?? 0;

    for (final entry in horizons.entries) {
      final key = entry.key;
      final duration = entry.value;
      if (samples.containsKey(key)) continue;
      if (now < baselineAt + duration + 60000) continue;

      final retryInfo = sampleRetries[key] as Map?;
      final nextAt = (retryInfo?['nextAt'] as num?)?.toInt() ?? 0;
      final attempts = (retryInfo?['attempts'] as num?)?.toInt() ?? 0;

      if (now < nextAt) continue;
      if (attempts >= maxSampleAttempts) continue;
      if (now - (baselineAt + duration) > maxSampleLatenessMs) continue;

      jobs.add(DueOutcomeJob(
        row: row,
        key: key,
        targetAt: baselineAt + duration,
      ));
    }
  }

  jobs.sort((a, b) {
    final aRetries = ((a.row['sampleRetries'] as Map?)?[a.key] as Map?)?['attempts'] as int? ?? 0;
    final bRetries = ((b.row['sampleRetries'] as Map?)?[b.key] as Map?)?['attempts'] as int? ?? 0;
    final diff = aRetries.compareTo(bRetries);
    if (diff != 0) return diff;
    return a.targetAt.compareTo(b.targetAt);
  });
  return jobs;
}

List<DueOutcomeJob> selectOutcomeJobs(
  Map<String, List<Map<String, dynamic>>> scopes, {
  List<String> enabledChains = const [],
  String provider = 'AVE',
  int limit = 0,
  int? nowMs,
}) {
  if (provider != 'AVE' || limit <= 0) return const [];
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final enabled = enabledChains.toSet();

  final list = <DueOutcomeJob>[];
  for (final entry in scopes.entries) {
    final chain = entry.key;
    if (!enabled.contains(chain)) continue;
    final rows = entry.value.where((row) =>
        (row['chain'] == null || row['chain'] == chain) && row['baselineProvider'] == 'AVE').toList();
    for (final job in dueOutcomeJobs(rows, now)) {
      list.add(DueOutcomeJob(
        row: job.row,
        key: job.key,
        targetAt: job.targetAt,
        chain: chain,
      ));
    }
  }

  list.sort((a, b) {
    final aRetries = ((a.row['sampleRetries'] as Map?)?[a.key] as Map?)?['attempts'] as int? ?? 0;
    final bRetries = ((b.row['sampleRetries'] as Map?)?[b.key] as Map?)?['attempts'] as int? ?? 0;
    final diff = aRetries.compareTo(bRetries);
    if (diff != 0) return diff;
    return a.targetAt.compareTo(b.targetAt);
  });

  return list.take(limit).toList();
}

Map<String, dynamic> outcomeCoverage(List<Map<String, dynamic>> outcomes, [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> cohort(String decision) {
    final rows = outcomes.where((r) => r['initialDecision'] == decision).toList();
    final result = <String, dynamic>{};
    for (final entry in horizons.entries) {
      final key = entry.key;
      final duration = entry.value;
      final eligible = rows.where((r) => now >= ((r['baselineAt'] as num?)?.toInt() ?? 0) + duration).toList();
      final values = eligible
          .map((r) => ((r['samples'] as Map?)?[key] as Map?)?['return'])
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList()
        ..sort();
      final n = values.length;
      final median = n == 0 ? null : (values[(n - 1) ~/ 2] + values[n ~/ 2]) / 2.0;
      final positiveRate = n == 0 ? null : values.where((x) => x > 0).length / n;

      result[key] = {
        'eligible': eligible.length,
        'completed': n,
        'missing': eligible.length - n,
        'median': median,
        'positiveRate': positiveRate,
      };
    }
    return result;
  }

  return {
    'passed': cohort('X_REVIEW'),
    'rejected': cohort('HARD_REJECT'),
  };
}
