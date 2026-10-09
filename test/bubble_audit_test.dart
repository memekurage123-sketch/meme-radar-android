import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/services/bubble_audit_service.dart';

void main() {
  group('BubbleAuditResult logic test', () {
    test('Cluster warning triggers at 8.0%', () {
      const res = BubbleAuditResult(maxClusterRatio: 8.5);
      expect(res.hasClusterWarning, isTrue);
      expect(res.hasClusterCaution, isFalse);
    });

    test('Cluster caution triggers at 4.0% - 7.9%', () {
      const res = BubbleAuditResult(maxClusterRatio: 5.2);
      expect(res.hasClusterWarning, isFalse);
      expect(res.hasClusterCaution, isTrue);
    });

    test('Healthy indicators logic', () {
      const res = BubbleAuditResult(
        maxClusterRatio: 1.2,
        smartCount: 3,
        kolCount: 2,
        cabalCount: 0,
      );
      expect(res.hasClusterWarning, isFalse);
      expect(res.isSmartMoneyHealthy, isTrue);
      expect(res.isKolStrong, isTrue);
      expect(res.hasCabalWarning, isFalse);
    });
  });
}
