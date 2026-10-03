/// Faithful Dart port of upstream `src/social.mjs` at commit 7ecd342
class SocialCapability {
  final bool available;
  final String backend;
  final String reason;
  final String mode;

  const SocialCapability({
    this.available = false,
    this.backend = '',
    this.reason = '当前采用X人工复核模式',
    this.mode = 'manual',
  });
}

class SocialGateResult {
  final String status;
  final int score;
  final String reason;

  const SocialGateResult({
    required this.status,
    required this.score,
    required this.reason,
  });

  Map<String, dynamic> toMap() => {
        'status': status,
        'score': score,
        'reason': reason,
      };
}

SocialGateResult socialGate({
  String? twitter,
  int followerCount = 0,
  bool? duplicateSocial,
  SocialCapability? capability,
}) {
  if (twitter == null || twitter.isEmpty) {
    return const SocialGateResult(status: 'FAIL', score: 0, reason: '没有X账号');
  }
  if (duplicateSocial == true) {
    return const SocialGateResult(status: 'FAIL', score: 0, reason: '社媒链接疑似复用');
  }
  if (capability == null || !capability.available) {
    return SocialGateResult(
      status: 'UNVERIFIED',
      score: 0,
      reason: capability?.reason ?? '无法读取X评论，不能确认真人社区',
    );
  }
  return SocialGateResult(
    status: 'UNVERIFIED',
    score: 0,
    reason: '已检测到X后端${capability.backend}，评论真实性解析器尚未完成联调',
  );
}
