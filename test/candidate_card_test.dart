import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/ui/candidate_card.dart';

void main() {
  testWidgets('CandidateCard renders correctly with a valid LIVE_READY fixture',
      (WidgetTester tester) async {
    final Map<String, dynamic> candidateFixture = {
      'symbol': 'PEPE',
      'address': '0x6982508145454ce325ddbe47a25d4ec3d2311933',
      'chain': 'eth',
      'marketCap': 420000000.0,
      'liquidity': 15000000.0,
      'price': 0.000001,
      'volume5m': 50000.0,
      'buys5m': 150,
      'sells5m': 50,
      'priorityBand': 'HIGH',
      'discoveryScore': 85.0,
      'status': 'LIVE_READY',
      // No explicit dev/tax data provided, should render Unknown/N/A
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [CandidateCard(candidate: candidateFixture)],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('PEPE'), findsWidgets);
    expect(find.textContaining('0x6982'), findsWidgets);
    expect(find.textContaining('\$420.00M'), findsWidgets);
    expect(find.textContaining('\$15.00M'), findsWidgets);
    // Score might be shown as 85
    expect(find.textContaining('85'), findsWidgets);
  });
}
