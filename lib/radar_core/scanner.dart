/// Faithful Dart port of upstream `src/scanner.mjs` at commit 7ecd342
import 'dart:async';
import 'ave.dart';
import 'config.dart';
import 'live_leads.dart';
import 'scoring.dart';
import 'secondary.dart';
import 'social.dart';
import 'state.dart';

class DeepClassification {
  final String status;
  final List<String> hardFailed;
  final List<String> waitingFailed;
  final String secondaryReason;

  const DeepClassification({
    required this.status,
    required this.hardFailed,
    required this.waitingFailed,
    this.secondaryReason = '',
  });

  Map<String, dynamic> toMap() => {
        'status': status,
        'hardFailed': hardFailed,
        'waitingFailed': waitingFailed,
        'secondaryReason': secondaryReason,
      };
}

DeepClassification classifyDeepResult(
  DeepScreenResult? deep, [
  Map<String, dynamic> auditMeta = const {},
]) {
  final failed = deep?.failed.toSet() ?? <String>{};
  final unknown =
      (deep?.blockingUnknownFields ?? deep?.unknownFields ?? []).toSet();

  bool unknownCheck(String name) {
    const prefixes = {
      'openSource': ['openSource'],
      'ownerRenounced': [
        'ownerRenounced',
        'renouncedMint',
        'renouncedFreezeAccount'
      ],
      'lpLocked': ['lockRate'],
      'notHoneypot': ['honeypot', 'sellability.'],
      'tax': ['buyTax', 'sellTax'],
      'rug': ['rugRatio'],
      'concentration': ['top10'],
      'dev': ['devHold'],
      'insider': ['insider'],
      'bundler': ['bundler'],
      'sniper': ['sniperHold'],
      'wash': ['wash'],
      'liquidity': ['liquidity'],
      'wallets': ['holders.'],
      'observation': ['candles'],
      'chartRisk': ['chartRisk.'],
    };
    final list = prefixes[name] ?? const [];
    return unknown.any((field) =>
        list.any((prefix) => field == prefix || field.startsWith(prefix)));
  }

  final transient = <String>{'wallets', 'observation', 'marketBehavior'};
  if (deep?.honeypotEvidence != '检测到貔貅') transient.add('notHoneypot');

  final hardFailed = failed
      .where((name) => !transient.contains(name) && !unknownCheck(name))
      .toList();
  final waitingFailed = failed
      .where((name) => transient.contains(name) || unknownCheck(name))
      .toList();

  if (auditMeta['complete'] == false) {
    waitingFailed.add('auditIncomplete');
  }

  if (hardFailed.isNotEmpty) {
    return DeepClassification(
        status: 'HARD_REJECT',
        hardFailed: hardFailed,
        waitingFailed: waitingFailed);
  }
  if (deep?.chainPass != true || auditMeta['complete'] == false) {
    return DeepClassification(
        status: 'WAIT_RECHECK',
        hardFailed: hardFailed,
        waitingFailed: waitingFailed);
  }
  return const DeepClassification(
      status: 'X_REVIEW', hardFailed: [], waitingFailed: []);
}

DeepClassification mergeSecondaryClassification(
  DeepClassification base,
  Map<String, dynamic>? secondary,
) {
  if (secondary == null) return base;
  final sources = (secondary['sources'] as Map?)?.values ?? const [];
  final supported =
      sources.any((s) => s is Map && s['status'] != 'UNSUPPORTED');
  final secInfo = secondary['security'] as Map?;
  final fatal = secInfo?['verdict'] == 'FATAL';
  final conflicts = (secondary['conflicts'] as List?) ?? const [];
  final blockingConflicts = conflicts
      .where((c) =>
          c is Map &&
          (c['type'] == 'MARKET_MISMATCH' || c['type'] == 'SECURITY_MISMATCH'))
      .toList();
  final incomplete = supported &&
      (secondary['status'] != 'COMPLETE' || secInfo?['verdict'] == 'UNKNOWN');

  String newStatus = base.status;
  if (fatal) {
    newStatus = 'HARD_REJECT';
  } else if (base.status == 'X_REVIEW' &&
      (incomplete || blockingConflicts.isNotEmpty)) {
    newStatus = 'WAIT_RECHECK';
  }

  String secondaryReason = '';
  if (fatal) {
    secondaryReason = '第二安全源触发一票否决';
  } else if (incomplete) {
    secondaryReason = '第二数据源不完整，等待复查';
  } else if (blockingConflicts.isNotEmpty) {
    secondaryReason = '多源数据冲突，等待复查';
  } else if (!supported) {
    secondaryReason = '当前链暂无第二数据源，仅供人工查看';
  }

  return DeepClassification(
    status: newStatus,
    hardFailed: base.hardFailed,
    waitingFailed: base.waitingFailed,
    secondaryReason: secondaryReason,
  );
}

class Scanner {
  final AveClient aveClient;
  final SecondaryValidator? secondaryValidator;
  final RadarConfig config;
  final RadarState state;

  Scanner({
    required this.aveClient,
    this.secondaryValidator,
    required this.config,
    required this.state,
  });

  /// Executes one full scanning cycle
  Future<Map<String, dynamic>> cycle() async {
    final chain = state.activeChain;

    state.scanInProgress = true;
    state.lastAttemptAt = DateTime.now().millisecondsSinceEpoch;

    try {
      // 1. Fetch raw discovery rows from AVE
      final discoveredRows = await aveClient.discover(
        chain,
        limit:
            config.maxDeepAuditsPerCycle > 0 ? config.maxDeepAuditsPerCycle : 6,
        enrichPairs: true,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final nowSec = now / 1000.0;

      state.discoveredCount += discoveredRows.length;
      final observations = <Map<String, dynamic>>[];
      final prequalified = <Map<String, dynamic>>[];

      // 2. Screen each token through discoveryScreen
      for (final row in discoveredRows) {
        final screen =
            discoveryScreen(row, config.copyWith(chain: chain), nowSec);

        final observation = {
          'address': row['address'],
          'chain': chain,
          'eligible': screen.pass,
          'score': screen.score,
          'reasons': screen.reasons,
          'priorityBand': screen.priorityBand,
          'lead': {
            ...row,
            'qualifiedAt': screen.pass ? now : null,
            'discoveryScore': screen.score,
            'priorityBand': screen.priorityBand,
          }
        };
        observations.add(observation);

        if (screen.pass) {
          prequalified.add(row);
        }
      }

      state.prequalifiedCount += prequalified.length;

      // 3. Reconcile Live Leads
      final reconciled = reconcileLiveLeads(
        state.liveLeads,
        observations,
        chain: chain,
        confirmedAt: now,
        retentionMs: config.liveLeadRetentionMs,
      );
      state.liveLeads = reconciled;

      // 4. Update candidates list
      final currentCandidates = <Map<String, dynamic>>[];
      for (final lead in reconciled) {
        final social = socialGate(
          twitter: lead['twitter']?.toString(),
          capability: const SocialCapability(),
        );

        final candidate = {
          'chain': chain,
          'address': lead['address'],
          'symbol': lead['symbol'],
          'name': lead['name'],
          'marketCap': lead['marketCap'],
          'liquidity': lead['liquidity'],
          'price': lead['price'],
          'volume5m': lead['volume5m'],
          'buys5m': lead['buys5m'],
          'sells5m': lead['sells5m'],
          'holders': lead['holders'],
          'priorityBand': lead['priorityBand'],
          'discoveryScore': lead['discoveryScore'],
          'pairAddress': lead['pairAddress'],
          'marketProvider': 'AVE',
          'status': 'PREQUALIFIED',
          'social': social.toMap(),
        };

        currentCandidates.add(candidate);
      }

      state.candidates = currentCandidates;
      state.scanCount++;
      state.lastSuccessAt = now;
      state.status = 'IDLE';

      return {
        'status': 'OK',
        'chain': chain,
        'discovered': discoveredRows.length,
        'prequalified': prequalified.length,
        'liveLeads': reconciled.length,
        'discoveredRows': discoveredRows,
      };
    } catch (e) {
      state.status = 'ERROR';
      state.addEvent('SCAN_ERROR', e.toString());
      rethrow;
    } finally {
      state.scanInProgress = false;
      state.generatedAt = DateTime.now().millisecondsSinceEpoch;
    }
  }
}
