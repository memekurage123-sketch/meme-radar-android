import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/services/candidate_eligibility.dart';

void main() {
  group('Candidate Eligibility Tests', () {
    test('READY + auditEligible + !stale => eligible', () {
      final r = {
        'discoveryState': 'READY',
        'auditEligible': true,
        'stale': false,
      };
      expect(isEligibleCandidate(r), true);
    });

    test('READY but auditEligible=false => no notification', () {
      final r = {
        'discoveryState': 'READY',
        'auditEligible': false,
        'stale': false,
      };
      expect(isEligibleCandidate(r), false);
    });

    test('READY but stale=true => no notification', () {
      final r = {
        'discoveryState': 'READY',
        'auditEligible': true,
        'stale': true,
      };
      expect(isEligibleCandidate(r), false);
    });

    // We do NOT test for exclusions (like excluded or HARD_REJECT) here
    // because Android fast-path does not currently implement deep exclusions
    // in the _liveDiscoveryRows structure.
  });
}
