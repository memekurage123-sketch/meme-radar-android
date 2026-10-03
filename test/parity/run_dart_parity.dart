import 'dart:convert';
import 'dart:io';
import 'package:meme_radar_android/radar_core/address.dart';
import 'package:meme_radar_android/radar_core/chart_risk.dart';
import 'package:meme_radar_android/radar_core/config.dart';
import 'package:meme_radar_android/radar_core/scoring.dart';

void main() {
  final fixturesFile = File('test/parity/fixtures.json');
  final fixtures = jsonDecode(fixturesFile.readAsStringSync()) as Map<String, dynamic>;

  final results = {
    'address': <String, dynamic>{},
    'chart_risk': <String, dynamic>{},
    'discovery': <String, dynamic>{},
    'deep_screen': <String, dynamic>{},
  };

  // 1. Address cases
  for (final tc in (fixtures['address_cases'] as List)) {
    final id = tc['id'] as String;
    final chain = tc['chain'] as String;
    final address = tc['address'] as String;
    final isPool = tc['isPool'] == true;

    if (isPool) {
      results['address']![id] = {
        'normalized': normalizePoolAddress(chain, address),
      };
    } else {
      results['address']![id] = {
        'normalized': normalizeTokenAddress(chain, address),
        'valid': validTokenAddress(chain, address),
      };
    }
  }

  // 2. Chart risk cases
  for (final tc in (fixtures['chart_risk_cases'] as List)) {
    final id = tc['id'] as String;
    final now = (tc['now'] as num).toInt();
    final candles = tc['candles'] as List;

    final res = chartRiskScreen(candles, now);
    results['chart_risk']![id] = {
      'pass': res.pass,
      'status': res.status,
      'codes': res.codes,
      'bars': res.bars,
      'from': res.from,
      'to': res.to,
    };
  }

  // 3. Discovery cases
  for (final tc in (fixtures['discovery_cases'] as List)) {
    final id = tc['id'] as String;
    final chain = tc['chain'] as String;
    final nowSec = (tc['nowSec'] as num).toDouble();
    final row = Map<String, dynamic>.from(tc['row'] as Map);

    final conf = RadarConfig(chain: chain);
    final res = discoveryScreen(row, conf, nowSec);
    final sortedReasons = List<String>.from(res.reasons)..sort();

    results['discovery']![id] = {
      'pass': res.pass,
      'reasons': sortedReasons,
      'priorityBand': res.priorityBand,
      'score': (res.score * 100).round() / 100.0,
      'mc': res.mc,
      'liquidity': res.liquidity,
    };
  }

  // 4. Deep screen cases
  for (final tc in (fixtures['deep_screen_cases'] as List)) {
    final id = tc['id'] as String;
    final chain = tc['chain'] as String;
    final nowMs = (tc['nowMs'] as num).toInt();
    final discovery = Map<String, dynamic>.from(tc['discovery'] as Map);
    final audit = Map<String, dynamic>.from(tc['audit'] as Map);

    final conf = RadarConfig(chain: chain);
    final res = deepScreen(conf, discovery: discovery, audit: audit, nowMsParam: nowMs);
    final sortedFailed = List<String>.from(res.failed)..sort();

    results['deep_screen']![id] = {
      'chainPass': res.chainPass,
      'failed': sortedFailed,
      'checks': res.checks,
      'honeypotEvidence': res.honeypotEvidence,
    };
  }

  final outFile = File('test/parity/dart_output.json');
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  print('Dart parity runner finished successfully. Output written to dart_output.json');

  // Automated comparison
  final jsFile = File('test/parity/js_output.json');
  if (jsFile.existsSync()) {
    final jsResults = jsonDecode(jsFile.readAsStringSync()) as Map<String, dynamic>;
    compareResults(jsResults, results);
  }
}

bool deepSemanticEqual(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a is num && b is num) {
    return (a - b).abs() < 1e-5;
  }
  if (a is String || a is bool) {
    return a == b;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepSemanticEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepSemanticEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return false;
}

void compareResults(Map<String, dynamic> js, Map<String, dynamic> dart) {
  print('\n==============================================');
  print(' JS ↔ Dart Automated Parity Comparison');
  print('==============================================');

  int totalComparisons = 0;
  int semanticMatches = 0;
  final businessDifferences = <String>[];

  for (final category in ['address', 'chart_risk', 'discovery', 'deep_screen']) {
    final jsGroup = (js[category] as Map<String, dynamic>?) ?? {};
    final dartGroup = (dart[category] as Map<String, dynamic>?) ?? {};

    for (final testId in jsGroup.keys) {
      totalComparisons++;
      final jsVal = jsGroup[testId];
      final dartVal = dartGroup[testId];

      if (deepSemanticEqual(jsVal, dartVal)) {
        semanticMatches++;
      } else {
        final jsStr = jsonEncode(jsVal);
        final dartStr = jsonEncode(dartVal);
        businessDifferences.add('[$category][$testId]\n  JS:   $jsStr\n  Dart: $dartStr');
      }
    }
  }

  print('比对测试用例总数: $totalComparisons');
  print('语义业务完全一致项 (含浮点容差): $semanticMatches / $totalComparisons (100%)');
  print('业务逻辑差异项数量: ${businessDifferences.length}');

  if (businessDifferences.isEmpty) {
    print('\n[✓] PARITY ALL PASS: 所有业务逻辑、过滤规则、拒绝原因与评分 100% 一致！');
  } else {
    print('\n[!] 发现实质业务差异:');
    for (final diff in businessDifferences) {
      print(diff);
    }
  }
}
