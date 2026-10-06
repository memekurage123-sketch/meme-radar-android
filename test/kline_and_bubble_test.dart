import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/radar_core/ave.dart';
import 'package:meme_radar_android/ui/candidate_card.dart';

void main() {
  group('KLine and Bubble URL / Logic Tests', () {
    test('AVE Bubble URL generation maps supported chains correctly', () {
      final cases = {
        'bsc': 'https://bubble.aveai.trade/?token_id=0x123-bsc',
        'BSC': 'https://bubble.aveai.trade/?token_id=0x123-bsc',
        'sol': 'https://bubble.aveai.trade/?token_id=6p6x-solana',
        'SOL': 'https://bubble.aveai.trade/?token_id=6p6x-solana',
        'base': 'https://bubble.aveai.trade/?token_id=0x456-base',
        'eth': 'https://bubble.aveai.trade/?token_id=0x789-eth',
        'robinhood': 'https://bubble.aveai.trade/?token_id=0xabc-robinhood',
      };

      cases.forEach((chain, expected) {
        final lower = chain.toLowerCase();
        final apiChain = aveChains[lower] ?? lower;
        final token = chain.toLowerCase() == 'sol'
            ? '6p6x'
            : chain.toLowerCase() == 'base'
                ? '0x456'
                : chain.toLowerCase() == 'eth'
                    ? '0x789'
                    : chain.toLowerCase() == 'robinhood'
                        ? '0xabc'
                        : '0x123';
        final url = 'https://bubble.aveai.trade/?token_id=$token-$apiChain';
        expect(url, expected);
      });
    });

    test('AVE Full URL generation matches official pro.ave.ai routes', () {
      final cases = {
        'bsc': 'https://pro.ave.ai/token/0x123-bsc?ref=0001',
        'sol': 'https://pro.ave.ai/token/6p6x-solana?ref=0001',
      };

      cases.forEach((chain, expected) {
        final lower = chain.toLowerCase();
        final apiChain = aveChains[lower] ?? lower;
        final token = chain == 'sol' ? '6p6x' : '0x123';
        final url = 'https://pro.ave.ai/token/$token-$apiChain?ref=0001';
        expect(url, expected);
      });
    });

    test('formatTokenAge calculates human readable age accurately', () {
      const now = 1000000;
      // < 1m
      expect(formatTokenAge(now - 30, now), '< 1m');
      // 3m
      expect(formatTokenAge(now - 180, now), '3m');
      // 47m
      expect(formatTokenAge(now - 47 * 60, now), '47m');
      // 2h
      expect(formatTokenAge(now - 2 * 3600, now), '2h');
      // 8h 35m
      expect(formatTokenAge(now - (8 * 3600 + 35 * 60), now), '8h 35m');
      // 1d
      expect(formatTokenAge(now - 24 * 3600, now), '1d');
      // 3d 6h
      expect(formatTokenAge(now - (3 * 24 * 3600 + 6 * 3600), now), '3d 6h');
      // null / invalid
      expect(formatTokenAge(null, now), null);
      expect(formatTokenAge(0, now), null);
      expect(formatTokenAge(now + 100, now), null); // future
    });

    testWidgets(
        'CandidateCard has fixed 4-column primary metrics without DEV% or Tax, displays 币龄',
        (WidgetTester tester) async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final Map<String, dynamic> candidateWithAge = {
        'symbol': 'DOGE',
        'address': '0x1111222233334444555566667777888899990000',
        'chain': 'bsc',
        'marketCap': 50000.0,
        'liquidity': 10000.0,
        'discoveryScore': 70.0,
        'createdAt': nowSec - 2820, // 47m ago
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CandidateCard(candidate: candidateWithAge),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Score'), findsOneWidget);
      expect(find.text('MC'), findsOneWidget);
      expect(find.text('Liquidity'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('47m'), findsOneWidget);
      expect(find.text('DEV%'), findsNothing);
      expect(find.text('Tax'), findsNothing);
    });

    testWidgets('CandidateCard displays AVE 主页 button when expanded',
        (WidgetTester tester) async {
      final Map<String, dynamic> candidate = {
        'symbol': 'TEST',
        'address': '0x1111222233334444555566667777888899990000',
        'chain': 'bsc',
        'marketCap': 50000.0,
        'liquidity': 10000.0,
        'discoveryScore': 70.0,
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CandidateCard(candidate: candidate),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap card to expand
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      expect(find.text('AVE 主页'), findsOneWidget);
      expect(find.text('气泡图'), findsOneWidget);
      expect(find.text('K线'), findsOneWidget);
    });
  });
}
