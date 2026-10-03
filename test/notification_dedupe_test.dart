import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/services/notification_deduper.dart';

void main() {
  group('NotificationDeduper tests', () {
    test('首次出现 Candidate A -> notify A', () {
      final deduper = NotificationDeduper({});
      final shouldNotify = deduper.shouldNotify('sol', 'TokenA', 1000);
      expect(shouldNotify, true);
    });

    test('下一周期 Candidate A 仍存在 -> 不重复 notify', () {
      final deduper = NotificationDeduper({'sol_TokenA': 1000});
      // Next cycle, say 5 mins later
      final shouldNotify = deduper.shouldNotify('sol', 'TokenA', 1000 + 5 * 60 * 1000);
      expect(shouldNotify, false);
    });

    test('Candidate A + 新 Candidate B -> 只 notify B', () {
      final deduper = NotificationDeduper({'sol_TokenA': 1000});
      final now = 1000 + 5 * 60 * 1000;
      final notifyA = deduper.shouldNotify('sol', 'TokenA', now);
      final notifyB = deduper.shouldNotify('sol', 'TokenB', now);
      expect(notifyA, false);
      expect(notifyB, true);
    });

    test('同 address 不同 chain -> 视为不同 Candidate', () {
      final deduper = NotificationDeduper({'sol_TokenA': 1000});
      final notifyDiffChain = deduper.shouldNotify('bsc', 'TokenA', 1000 + 5 * 60 * 1000);
      expect(notifyDiffChain, true);
    });

    test('超过 2h cooldown 后 A 再次 LIVE_READY -> 可以再次 notify', () {
      final deduper = NotificationDeduper({'sol_TokenA': 1000});
      final twoHoursAndOneMs = 1000 + (2 * 60 * 60 * 1000) + 1;
      final shouldNotify = deduper.shouldNotify('sol', 'TokenA', twoHoursAndOneMs);
      expect(shouldNotify, true);
    });

    test('cleanMap correctly removes expired entries', () {
      final deduper = NotificationDeduper({
        'sol_TokenA': 1000,
        'sol_TokenB': 1000 + 1 * 60 * 60 * 1000, // 1h ago
      });
      final now = 1000 + 2 * 60 * 60 * 1000 + 1; // 2h 1ms later
      final clean = deduper.cleanMap(now);
      expect(clean.containsKey('sol_TokenA'), false);
      expect(clean.containsKey('sol_TokenB'), true);
    });
  });
}
