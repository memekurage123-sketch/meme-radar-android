import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _keyApiKey = 'ave_api_key';
  static const _keySelectedChain = 'selected_chain';
  static const _keySortMethod = 'sort_method';
  static const _keyNotifiedCandidates = 'notified_candidates';

  final FlutterSecureStorage _storage;

  StorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  Future<String?> getApiKey() async {
    try {
      return await _storage.read(key: _keyApiKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _keyApiKey);
    } else {
      await _storage.write(key: _keyApiKey, value: trimmed);
    }
  }

  Future<String> getSelectedChain([String fallback = 'bsc']) async {
    try {
      final chain = await _storage.read(key: _keySelectedChain);
      if (chain != null &&
          ['sol', 'bsc', 'base', 'eth', 'robinhood']
              .contains(chain.toLowerCase())) {
        return chain.toLowerCase();
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> saveSelectedChain(String chain) async {
    try {
      await _storage.write(key: _keySelectedChain, value: chain.toLowerCase());
    } catch (_) {}
  }

  Future<String> getSortMethod([String fallback = 'recent']) async {
    try {
      final method = await _storage.read(key: _keySortMethod);
      if (method != null &&
          ['recent', 'volume5m', 'priority'].contains(method)) {
        return method;
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> saveSortMethod(String method) async {
    try {
      await _storage.write(key: _keySortMethod, value: method);
    } catch (_) {}
  }

  Future<Map<String, int>> getNotifiedCandidates() async {
    try {
      final data = await _storage.read(key: _keyNotifiedCandidates);
      if (data != null) {
        final Map<String, dynamic> map = jsonDecode(data);
        return map.map((k, v) => MapEntry(k, v as int));
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveNotifiedCandidates(Map<String, int> cleanMap) async {
    try {
      await _storage.write(
          key: _keyNotifiedCandidates, value: jsonEncode(cleanMap));
    } catch (_) {}
  }
}
