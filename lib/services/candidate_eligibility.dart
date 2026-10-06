bool isEligibleCandidate(Map<String, dynamic> r) {
  return r['discoveryState'] == 'READY' &&
      r['auditEligible'] == true &&
      r['stale'] != true;
}
