class NotificationDeduper {
  final Map<String, int> _notifiedMap;

  NotificationDeduper(this._notifiedMap);

  Map<String, int> get map => _notifiedMap;

  bool shouldNotify(String chain, String address, int nowMs) {
    if (address.isEmpty) return false;
    final dedupeKey = '${chain}_$address';
    final lastNotified = _notifiedMap[dedupeKey];

    // 14天的毫秒数: 14 * 24 * 60 * 60 * 1000 = 1209600000
    // 推送过一次的老币，极长期内（14天）绝不重复发送通知
    if (lastNotified == null || (nowMs - lastNotified) >= 14 * 24 * 60 * 60 * 1000) {
      _notifiedMap[dedupeKey] = nowMs;
      return true;
    }
    return false;
  }

  Map<String, int> cleanMap(int nowMs) {
    final fourteenDays = 14 * 24 * 60 * 60 * 1000;
    return _notifiedMap.entries
        .where((e) => nowMs - e.value < fourteenDays)
        .fold<Map<String, int>>({}, (m, e) {
      m[e.key] = e.value;
      return m;
    });
  }
}
