import 'package:test/test.dart';
import 'package:meme_radar_android/radar_core/address.dart';
import 'package:meme_radar_android/radar_core/chart_risk.dart';
import 'package:meme_radar_android/radar_core/config.dart';
import 'package:meme_radar_android/radar_core/pool_identity.dart';
import 'package:meme_radar_android/radar_core/scoring.dart';

void main() {
  group('1. Address Normalization Parity Tests', () {
    const sol = 'So11111111111111111111111111111111111111112';
    const evm = '0x1234567890abcdef1234567890abcdef12345678';

    test('valid tokens and pools normalize correctly', () {
      expect(normalizeTokenAddress('sol', sol), equals(sol));
      expect(normalizeTokenAddress('bsc', evm.toUpperCase().replaceFirst('0X', '0x')), equals(evm));
      expect(normalizePoolAddress('bsc', '0x${'12' * 32}'), equals('0x${'12' * 32}'));
      expect(validTokenAddress('sol', sol), isTrue);
      expect(validTokenAddress('bsc', evm), isTrue);
    });

    test('invalid tokens are rejected exactly matching upstream', () {
      final invalidSol = '2' * 32; // Matches text regex but is not a 32-byte pubkey
      expect(validTokenAddress('sol', invalidSol), isFalse);
      expect(validTokenAddress('bsc', '0x${'0' * 40}'), isFalse);
      expect(validTokenAddress('eth', '0x${'e' * 40}'), isFalse);
      expect(normalizeTokenAddress('sol', '1' * 32), isNull); // All 1s is rejected
    });
  });

  group('2. Chart Risk Parity Tests', () {
    const now = 1800000000000;

    List<Map<String, dynamic>> series(List<double> closes, [int at = now]) {
      return List.generate(closes.length, (i) {
        final open = i > 0 ? closes[i - 1] : 1.0;
        final close = closes[i];
        final high = (open > close ? open : close) * 1.005;
        final low = (open < close ? open : close) * 0.995;
        return {
          'time': at - (closes.length - i) * 60000,
          'open': open,
          'close': close,
          'high': high,
          'low': low,
          'volume': 100.0,
        };
      });
    }

    List<Map<String, dynamic>> pump(int at) =>
        series([1.3776, 1.38, 1.38, 1.39, 1.39, 1.39, 1.40, 1.40, 1.40], at);

    List<Map<String, dynamic>> dump(int at) =>
        series([1.0, 0.65, 0.35, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18], at);

    test('pump produces VERTICAL_PLATEAU and dump produces SUSTAINED_COLLAPSE', () {
      final pumpBars = pump(now);
      final pumpObs = observeFiveMinutes(pumpBars, now);
      expect(pumpObs.pass, isTrue);

      final pumpRisk = chartRiskScreen(pumpBars, now);
      expect(pumpRisk.status, equals('REJECT'));
      expect(pumpRisk.pass, isFalse);
      expect(pumpRisk.codes, contains('VERTICAL_PLATEAU'));
      expect(pumpRisk.from, equals(pumpBars.first['time']));

      // Reversed order is also handled properly
      expect(chartRiskScreen(pumpBars.reversed.toList(), now).status, equals('REJECT'));

      // Seconds timestamp auto-scales to ms
      final scaledBars = pumpBars.map((b) => {...b, 'time': (b['time'] as int) / 1000.0}).toList();
      expect(chartRiskScreen(scaledBars, now).status, equals('REJECT'));

      final dumpBars = dump(now);
      final dumpRisk = chartRiskScreen(dumpBars, now);
      expect(dumpRisk.status, equals('REJECT'));
      expect(dumpRisk.codes, contains('SUSTAINED_COLLAPSE'));
    });

    test('smooth normal candles pass chartRiskScreen', () {
      final good = series([1.0, 1.01, 1.02, 1.025, 1.03, 1.04, 1.05, 1.06]);
      final risk = chartRiskScreen(good, now);
      expect(risk.pass, isTrue);
      expect(risk.status, equals('CLEAR_IN_WINDOW'));
    });

    test('insufficient or gap candles return UNKNOWN', () {
      final good = series([1.0, 1.01, 1.02, 1.025, 1.03, 1.04, 1.05, 1.06]);
      final tooFew = good.sublist(0, 3);
      final risk = chartRiskScreen(tooFew, now);
      expect(risk.status, equals('UNKNOWN'));
      expect(risk.pass, isFalse);
    });

    test('applyRiskExclusion marks row as HARD_REJECT', () {
      const address = '0x1234567890abcdef1234567890abcdef12345678';
      final row = {
        'chain': 'bsc',
        'address': address,
        'status': 'PASS',
        'deep': {
          'chainPass': true,
          'checks': {'chartRisk': true},
          'failed': <String>[],
        }
      };
      final exclusions = {
        'bsc:$address': {
          'reasons': ['单分钟跳升≥35%后窄幅平台，按风险偏好排除'],
          'codes': ['VERTICAL_PLATEAU'],
        }
      };
      final excluded = applyRiskExclusion(row, exclusions);
      expect(excluded['status'], equals('HARD_REJECT'));
      expect(excluded['deep']['chainPass'], isFalse);
      expect(excluded['deep']['checks']['chartRisk'], isFalse);
      expect(excluded['deep']['failed'], contains('chartRisk'));
    });
  });

  group('3. Pool Identity Parity Tests', () {
    const now = 1800000000000;
    const token = '0x1234567890abcdef1234567890abcdef12345678';
    const pair = '0xabcdef1234567890abcdef1234567890abcdef12';
    const otherToken = '0x5555555555555555555555555555555555555555';

    test('valid AVE pool evidence passes verification', () {
      final pool = {
        'source': 'AVE',
        'identityBasis': 'response',
        'chain': 'bsc',
        'pair': pair,
        'target_token': token,
        'token0_address': token,
        'token1_address': otherToken,
        'tvl': 15000.0,
        'volume_u_5m': 2000.0,
        'created_at': 1799990000,
        'first_trade_at': 1799990000,
        'capturedAt': now - 5000,
        'sourceUpdatedAt': now - 5000,
        'expiresAt': now + 30000,
      };
      final row = {
        'address': token,
        'pairAddress': pair,
        'poolEvidence': pool,
      };

      final verified = verifiedAvePoolEvidence(row, 'bsc', requireRowPair: true);
      expect(verified, isNotNull);
      expect(verified!.pair, equals(pair));
      expect(verified.token, equals(token));

      final market = verifiedPoolMarket(row, 'bsc', now);
      expect(market, isNotNull);
      expect(market!.source, equals('AVE'));
      expect(market.liquidity, equals(15000.0));
      expect(market.volume5m, equals(2000.0));
    });

    test('expired pool evidence is rejected', () {
      final pool = {
        'source': 'AVE',
        'identityBasis': 'response',
        'chain': 'bsc',
        'pair': pair,
        'target_token': token,
        'token0_address': token,
        'token1_address': otherToken,
        'tvl': 15000.0,
        'volume_u_5m': 2000.0,
        'created_at': 1799990000,
        'capturedAt': now - 70000, // > 60s ago
        'sourceUpdatedAt': now - 70000,
        'expiresAt': now - 10000, // already expired
      };
      final row = {
        'address': token,
        'pairAddress': pair,
        'poolEvidence': pool,
      };
      expect(verifiedPoolMarket(row, 'bsc', now), isNull);
    });
  });

  group('4. Scoring & Filtering Parity Tests', () {
    const now = 1800000000000;
    const nowSec = now / 1000.0;
    const address = '0x1234567890abcdef1234567890abcdef12345678';
    const config = RadarConfig(chain: 'bsc');

    Map<String, dynamic> sampleDiscovery(int at) => {
      'address': address,
      'chain': 'bsc',
      'market_cap': 50000.0,
      'liquidity': 12000.0,
      'creation_timestamp': at / 1000 - 600,
      'rug_ratio': 0.1,
      'bundler_rate': 0.05,
      'rat_trader_amount_rate': 0.05,
      'top70_sniper_hold_rate': 0.02,
      'is_wash_trading': false,
      'is_honeypot': false,
      'volume_1h': 5000.0,
      'holder_count': 120,
    };

    test('knownRiskReasons detects low LP, high tax, DEV hold > 1%, zero volume', () {
      final base = sampleDiscovery(now);
      expect(knownRiskReasons({...base, 'liquidity': 3310.0}, config), contains('流动性低于深审门槛'));
      expect(knownRiskReasons({...base, 'buy_tax': 0.10, 'sell_tax': 0.15}, config), contains('交易税超过风险门槛'));
      expect(knownRiskReasons({...base, 'dev_team_hold_rate': 0.0803}, config), contains('DEV持仓超过1%'));
      expect(knownRiskReasons({...base, 'volume_5m': 0.0}, config), contains('近5分钟无成交，暂不进入候选'));
    });

    test('discoveryScreen passes clean token within MC and liquidity boundaries', () {
      final row = sampleDiscovery(now);
      final res = discoveryScreen(row, config, nowSec);
      expect(res.pass, isTrue);
      expect(res.priorityBand, isTrue);
      expect(res.score, greaterThan(40.0));
      expect(res.reasons, isEmpty);
    });

    test('discoveryScreen rejects tokens with out-of-range MC or high rug ratio', () {
      final highRug = {...sampleDiscovery(now), 'rug_ratio': 0.40};
      expect(discoveryScreen(highRug, config, nowSec).pass, isFalse);

      final lowMc = {...sampleDiscovery(now), 'market_cap': 5000.0}; // min is 10000
      expect(discoveryScreen(lowMc, config, nowSec).pass, isFalse);
    });

    test('observeFiveMinutes checks valid 5m window return and drawdown', () {
      final closes = [1.0, 1.02, 1.03, 1.04, 1.05];
      final candles = List.generate(closes.length, (i) {
        return {
          'time': now - (5 - i) * 60000,
          'open': i > 0 ? closes[i - 1] : 1.0,
          'high': closes[i] * 1.01,
          'low': (i > 0 ? closes[i - 1] : 1.0) * 0.99,
          'close': closes[i],
          'volume': 100.0,
        };
      });
      final obs = observeFiveMinutes(candles, now);
      expect(obs.pass, isTrue);
      expect(obs.status, equals('PASS'));
      expect(obs.activeBars, equals(5));
      expect(obs.return5m, closeTo(0.05, 0.001));
    });

    test('analyzeWallets classifies ordinary, bot, and linked holders', () {
      final holders = [
        for (var i = 0; i < 10; i++)
          {
            'address': '0x${i.toString().padLeft(40, '0')}',
            'addr_type': 0,
            'is_new': false,
            'is_suspicious': false,
            'buy_tx_count_cur': 5,
            'amount_percentage': 0.02,
            'tags': <String>[],
          }
      ];
      final res = analyzeWallets(holders, config);
      expect(res.dataComplete, isTrue);
      expect(res.ordinaryCount, equals(10));
      expect(res.pass, isTrue);
    });

    test('deepScreen aggregates all sub-checks faithfully', () {
      final discovery = sampleDiscovery(now);
      final audit = {
        'security': {
          'open_source': true,
          'owner_renounced': true,
          'is_honeypot': false,
          'buy_tax': 0.01,
          'sell_tax': 0.01,
          'rug_ratio': 0.05,
          'top_10_holder_rate': 0.20,
          'dev_team_hold_rate': 0.005,
          'top70_sniper_hold_rate': 0.02,
          'locked_ratio': 0.90,
          'is_wash_trading': false,
        },
        'holders': [
          for (var i = 0; i < 10; i++)
            {
              'address': '0x${(i + 1).toString().padLeft(40, '0')}',
              'addr_type': 0,
              'is_new': false,
              'is_suspicious': false,
              'buy_tx_count_cur': 3,
              'amount_percentage': 0.02,
              'tags': <String>[],
            }
        ],
        'candles': List.generate(6, (i) {
          return {
            'time': now - (6 - i) * 60000,
            'open': 1.0,
            'high': 1.02,
            'low': 0.99,
            'close': 1.01,
            'volume': 500.0,
          };
        }),
        'traders': [
          for (var i = 0; i < 6; i++)
            {
              'address': '0x${(i + 10).toString().padLeft(40, '0')}',
              'sell_tx_count_cur': 2,
              'last_active_timestamp': now / 1000 - 60,
            }
        ],
        'info': {
          'liquidity': 15000.0,
          'price': {
            'price': 1.01,
            'price_5m': 1.00,
            'swaps_5m': 10,
            'buys_5m': 6,
            'sells_5m': 4,
            'sells_24h': 50,
            'volume_5m': 2000.0,
          },
          'holder_count': 100,
        }
      };

      final deep = deepScreen(config, discovery: discovery, audit: audit, nowMsParam: now);
      expect(deep.chainPass, isTrue);
      expect(deep.failed, isEmpty);
      expect(deep.checks['openSource'], isTrue);
      expect(deep.checks['ownerRenounced'], isTrue);
      expect(deep.checks['lpLocked'], isTrue);
      expect(deep.checks['notHoneypot'], isTrue);
      expect(deep.checks['chartRisk'], isTrue);
      expect(deep.checks['wallets'], isTrue);
    });
  });
}
