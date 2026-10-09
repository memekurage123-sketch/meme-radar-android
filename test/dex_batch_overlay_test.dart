import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/radar_core/config.dart';
import 'package:meme_radar_android/radar_core/scoring.dart';
import 'package:meme_radar_android/radar_core/secondary.dart';

void main() {
  group('DexBatchMarketOverlay & EVM Discovery Parity Tests', () {
    const testChain = 'bsc';
    const testCa = '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c';
    const testPair = '0x172fcd41e0913e95784454622d1c3724f546f849';

    test('parseDexBatch extracts pool market correctly for BSC token', () {
      final now = 1791235200000;
      final mockPayload = [
        {
          'chainId': 'bsc',
          'dexId': 'pancakeswap',
          'pairAddress': testPair,
          'baseToken': {
            'address': testCa,
            'name': 'Wrapped BNB',
            'symbol': 'WBNB'
          },
          'quoteToken': {
            'address': '0x55d398326f99059ff775485246999027b3197955',
            'name': 'Tether USD',
            'symbol': 'USDT'
          },
          'priceUsd': '737.26',
          'marketCap': 50000,
          'liquidity': {'usd': 15000.0},
          'volume': {'m5': 8000.0},
          'txns': {
            'm5': {'buys': 45, 'sells': 20}
          },
          'pairCreatedAt': now - 3600000, // 1 hour ago
        }
      ];

      final marketByToken = parseDexBatch(
        mockPayload,
        chain: testChain,
        dexChainId: 'bsc',
        tokenAddresses: [testCa],
        capturedAt: now,
      );

      expect(marketByToken.containsKey(testCa), isTrue);
      final m = marketByToken[testCa]!;
      expect(m['pairAddress'], testPair);
      expect(m['dexId'], 'pancakeswap');
      expect(m['liquidity'], 15000.0);
      expect(m['volume5m'], 8000.0);
      expect(m['buys5m'], 45);
      expect(m['sells5m'], 20);
      expect(m['pairCreatedAt'], now - 3600000);
    });

    test('overlayDexMarket enriches incomplete AVE row and passes aveDiscoveryScreen', () {
      final now = 1791235200000;
      final nowSec = now / 1000.0;

      // Incomplete raw AVE row without pairAddress or creation timestamp
      final rawAveRow = {
        'address': testCa,
        'chain': testChain,
        'marketProvider': 'AVE',
        'symbol': 'WBNB',
        'name': 'Wrapped BNB',
        'price': 737.26,
        'market_cap': 50000.0,
        'holder_count': 120,
        'capturedAt': now,
        'sourceUpdatedAt': now,
        'expiresAt': now + 30000,
        'stale': false,
        'volume_5m': 0.0, // unknown or 0 in raw trending
        'liquidity': null,
      };

      // Before enrichment, aveDiscoveryScreen must fail due to missing pool age / liquidity
      const config = RadarConfig(chain: testChain);
      final preScreen = discoveryScreen(rawAveRow, config, nowSec);
      expect(preScreen.pass, isFalse);
      expect(preScreen.reasons.contains('池龄或首笔成交时间未知'), isTrue);

      // Perform overlay enrichment
      final marketByToken = {
        testCa: {
          'pairAddress': testPair,
          'dexId': 'pancakeswap',
          'liquidity': 15000.0,
          'volume5m': 8000.0,
          'buys5m': 45,
          'sells5m': 20,
          'swaps5m': 65,
          'pairCreatedAt': now - 3600000, // 1 hour ago
          'priceUsd': 737.26,
          'marketCap': 50000.0,
        }
      };

      final enrichedRows = overlayDexMarket([rawAveRow], testChain, marketByToken, now, 20000);
      expect(enrichedRows.length, 1);
      final enriched = enrichedRows[0];

      expect(enriched['marketOverlayProvider'], 'DEXSCREENER');
      expect(enriched['pairAddress'], testPair);
      expect(enriched['pool_created_at'], (now - 3600000) ~/ 1000);
      expect(enriched['liquidity'], 15000.0);
      expect(enriched['volume_5m'], 8000.0);
      expect(enriched['buys_5m'], 45);
      expect(enriched['sells_5m'], 20);

      // Now aveDiscoveryScreen must PASS!
      final postScreen = discoveryScreen(enriched, config, nowSec);
      expect(postScreen.reasons, isEmpty);
      expect(postScreen.pass, isTrue);
      expect(postScreen.priorityBand, isTrue); // 50000 is in [20000, 80000]
    });
  });
}
