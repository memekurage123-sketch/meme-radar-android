import 'dart:io';
import 'package:meme_radar_android/radar_core/ave.dart';
import 'package:meme_radar_android/radar_core/config.dart';
import 'package:meme_radar_android/radar_core/scanner.dart';
import 'package:meme_radar_android/radar_core/scoring.dart';
import 'package:meme_radar_android/radar_core/state.dart';

void main(List<String> args) async {
  print('==============================================');
  print(' Meme Radar Core — CLI Verification Tool');
  print('==============================================');

  // 1. Read API key safely
  String? apiKey = Platform.environment['AVE_API_KEY'];
  for (final arg in args) {
    if (arg.startsWith('--key=')) {
      apiKey = arg.substring(6).trim();
    }
  }
  if (apiKey == null || apiKey.isEmpty) {
    final localKeyFile = File('.ave-key.local');
    if (localKeyFile.existsSync()) {
      apiKey = localKeyFile.readAsStringSync().trim();
    }
  }

  // Chain selection (default to bsc or first positional arg)
  var chain = 'bsc';
  for (final arg in args) {
    if (!arg.startsWith('--') &&
        ['bsc', 'sol', 'base', 'eth', 'robinhood']
            .contains(arg.toLowerCase())) {
      chain = arg.toLowerCase();
    }
  }

  if (apiKey == null || apiKey.isEmpty) {
    print('\n[INFO] 未检测到环境变量 AVE_API_KEY 或 --key 参数。');
    print('使用方法：');
    print('  export AVE_API_KEY="your_api_key"');
    print('  dart run bin/radar_test.dart [bsc|sol|base|eth]');
    print('\n正在使用离线内置样本数据验证 Radar Core 完整评估管道...');
    await runSamplePipeline(chain);
    return;
  }

  final maskedKey = apiKey.length > 8
      ? '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}'
      : '****';
  print('\n[✓] 检测到 AVE API Key: $maskedKey (未泄露完整 Key)');
  print('[i] 目标链: $chain');
  print('[i] 正在请求 AVE Data API ($aveOrigin)...');

  final aveClient = AveClient(apiKey: apiKey);
  final config = RadarConfig(chain: chain);
  final state = RadarState(activeChain: chain);
  final scanner = Scanner(aveClient: aveClient, config: config, state: state);

  try {
    final stopwatch = Stopwatch()..start();
    final result = await scanner.cycle();
    stopwatch.stop();

    print('\n==============================================');
    print(' 扫描完成！耗时: ${stopwatch.elapsedMilliseconds} ms');
    print('==============================================');
    print('状态: ${result['status']}');
    print('获取原始代币数: ${result['discovered']}');
    print('初筛通过代币数 (Prequalified): ${result['prequalified']}');
    print('实时候选池 (Live Leads): ${result['liveLeads']}');

    if (state.candidates.isNotEmpty) {
      print('\n--- 候选代币摘要 (Top ${state.candidates.length}) ---');
      for (var i = 0; i < state.candidates.length; i++) {
        final c = state.candidates[i];
        final symbol = c['symbol'] ?? '?';
        final address = c['address'] ?? '';
        final mc = (c['marketCap'] as num?)?.toStringAsFixed(0) ?? 'N/A';
        final liq = (c['liquidity'] as num?)?.toStringAsFixed(0) ?? 'N/A';
        final price = (c['price'] as num?)?.toStringAsPrecision(4) ?? 'N/A';
        final score = (c['discoveryScore'] as num?)?.toStringAsFixed(1) ?? '0';
        final priority = c['priorityBand'] == true ? ' [PRIORITY]' : '';

        print('[$i] $symbol$priority');
        print('    CA:    $address');
        print('    市值:  \$$mc | 流动性: \$$liq | 价格: \$$price');
        print('    得分:  $score | 状态: ${c['status']}');
      }
    } else {
      print('\n[i] 本轮扫描未产生满足全部初筛硬性门槛的候选（正常现象，Meme 过滤严苛）。');
    }

    print('\n[✓] 真实 AVE API 扫描执行测试 PASS！');
  } catch (e) {
    print('\n[!] 扫描请求异常: $e');
    exitCode = 1;
  } finally {
    aveClient.close();
  }
}

Future<void> runSamplePipeline(String chain) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final nowSec = now / 1000.0;
  final config = RadarConfig(chain: chain);

  final sampleTokens = [
    {
      'address': '0x1111111111111111111111111111111111111111',
      'chain': chain,
      'marketProvider': 'AVE',
      'symbol': 'PEPE_GEM',
      'name': 'Pepe Gem Meme',
      'market_cap': 45000.0,
      'liquidity': 15000.0,
      'price': 0.00045,
      'creation_timestamp': (now / 1000 - 900).toInt(),
      'launch_at': (now / 1000 - 900).toInt(),
      'volume_5m': 2500.0,
      'buys_5m': 12,
      'sells_5m': 8,
      'holder_count': 180,
      'rug_ratio': 0.05,
      'bundler_rate': 0.05,
      'rat_trader_amount_rate': 0.04,
      'is_wash_trading': false,
      'is_honeypot': false,
      'capturedAt': now - 5000,
      'sourceUpdatedAt': now - 5000,
      'expiresAt': now + 30000,
    },
    {
      'address': '0x2222222222222222222222222222222222222222',
      'chain': chain,
      'marketProvider': 'AVE',
      'symbol': 'LOW_LIQ_RISK',
      'name': 'Low Liquidity Meme',
      'market_cap': 35000.0,
      'liquidity': 1200.0, // < 3000 threshold
      'price': 0.0001,
      'creation_timestamp': (now / 1000 - 600).toInt(),
      'launch_at': (now / 1000 - 600).toInt(),
      'volume_5m': 800.0,
      'buys_5m': 5,
      'sells_5m': 2,
      'holder_count': 60,
      'rug_ratio': 0.02,
      'bundler_rate': 0.01,
      'capturedAt': now - 5000,
      'sourceUpdatedAt': now - 5000,
      'expiresAt': now + 30000,
    },
    {
      'address': '0x3333333333333333333333333333333333333333',
      'chain': chain,
      'marketProvider': 'AVE',
      'symbol': 'RUG_ALERT',
      'name': 'Rugged Token',
      'market_cap': 60000.0,
      'liquidity': 20000.0,
      'price': 0.005,
      'creation_timestamp': (now / 1000 - 800).toInt(),
      'launch_at': (now / 1000 - 800).toInt(),
      'volume_5m': 3000.0,
      'buys_5m': 10,
      'sells_5m': 15,
      'holder_count': 90,
      'rug_ratio': 0.45, // > 0.30 threshold
      'capturedAt': now - 5000,
      'sourceUpdatedAt': now - 5000,
      'expiresAt': now + 30000,
    }
  ];

  print('[i] 评估样本数量: ${sampleTokens.length}');
  var passed = 0;
  for (final t in sampleTokens) {
    final screen = discoveryScreen(t, config, nowSec);
    final sym = t['symbol'];
    if (screen.pass) {
      passed++;
      print(
          '  ✓ [$sym] 通过初筛! 得分: ${screen.score.toStringAsFixed(1)}, 优先波段: ${screen.priorityBand}');
    } else {
      print('  ✗ [$sym] 被过滤: ${screen.reasons.join(', ')}');
    }
  }
  print('\n[✓] 离线管道评估验证完成：输入 3 个样本，通过 $passed 个，过滤 ${3 - passed} 个。');
}
