/// Faithful Dart port of upstream `src/address.mjs` at commit 7ecd342
final _evmToken = RegExp(r'^0x[0-9a-f]{40}$', caseSensitive: false);
final _evmPool = RegExp(r'^0x(?:[0-9a-f]{40}|[0-9a-f]{64})$', caseSensitive: false);
final _solanaText = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
const _base58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

int _solanaBytes(String value) {
  if (!_solanaText.hasMatch(value)) return 0;
  var number = BigInt.zero;
  final big58 = BigInt.from(58);
  for (var i = 0; i < value.length; i++) {
    final digit = _base58.indexOf(value[i]);
    if (digit < 0) return 0;
    number = number * big58 + BigInt.from(digit);
  }
  final hex = number.toRadixString(16);
  final significant = number == BigInt.zero ? 0 : (hex.length / 2).ceil();
  final leadingOnes = RegExp(r'^1*').firstMatch(value)?[0]?.length ?? 0;
  return significant + leadingOnes;
}

String? normalizeTokenAddress(String chain, String? value) {
  if (value == null || value != value.trim()) return null;
  if (chain == 'sol') {
    return _solanaBytes(value) == 32 && !RegExp(r'^1+$').hasMatch(value) ? value : null;
  }
  if (_evmToken.hasMatch(value) && !RegExp(r'^0x(?:0{40}|e{40})$', caseSensitive: false).hasMatch(value)) {
    return value.toLowerCase();
  }
  return null;
}

String? normalizePoolAddress(String chain, String? value) {
  final token = normalizeTokenAddress(chain, value);
  if (token != null) return token;
  if (chain == 'sol' || value == null || value != value.trim()) return null;
  if (_evmPool.hasMatch(value) && !RegExp(r'^0x0{64}$', caseSensitive: false).hasMatch(value)) {
    return value.toLowerCase();
  }
  return null;
}

bool validTokenAddress(String chain, String? value) => normalizeTokenAddress(chain, value) != null;
bool validPoolAddress(String chain, String? value) => normalizePoolAddress(chain, value) != null;
