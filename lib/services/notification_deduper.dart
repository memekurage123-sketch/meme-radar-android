class NotificationDeduper {
  final Map<String, int> _notifiedMap;

  NotificationDeduper(this._notifiedMap);

  Map<String, int> get map => _notifiedMap;

  bool shouldNotify(String chain, String address, int nowMs) {
    if (address.isEmpty) return false;
    final dedupeKey = '${chain}_$address';
    final lastNotified = _notifiedMap[dedupeKey];
    
    if (lastNotified == null || (nowMs - lastNotified) >= 2 * 60 * 60 * 1000) {
      _notifiedMap[dedupeKey] = nowMs;
      return true;
    }
    return false;
  }

  Map<String, int> cleanMap(int nowMs) {
    final twoHours = 2 * 60 * 60 * 1000;
    return _notifiedMap.entries
        .where((e) => nowMs - e.value < twoHours)
        .fold<Map<String, int>>({}, (m, e) {
      m[e.key] = e.value;
      return m;
    });
  }
}
