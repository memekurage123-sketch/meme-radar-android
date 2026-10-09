import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../radar_core/ave.dart';

/// 链上持仓与气泡图深度体检结果
class BubbleAuditResult {
  final double maxClusterRatio; // 最大关联出资人小号集群持仓比 (0.0 ~ 100.0)
  final int smartCount;         // 聪明钱钱包数
  final double smartRatio;      // 聪明钱合计持仓比 (0.0 ~ 100.0)
  final int kolCount;           // KOL 钱包数
  final double kolRatio;        // KOL 合计持仓比 (0.0 ~ 100.0)
  final int cabalCount;         // Cabal (阴谋集团) 钱包数
  final double top100Ratio;     // 前 10 大户持仓占比
  final bool isLoaded;
  final String? error;

  const BubbleAuditResult({
    this.maxClusterRatio = 0.0,
    this.smartCount = 0,
    this.smartRatio = 0.0,
    this.kolCount = 0,
    this.kolRatio = 0.0,
    this.cabalCount = 0,
    this.top100Ratio = 0.0,
    this.isLoaded = false,
    this.error,
  });

  bool get hasClusterWarning => maxClusterRatio >= 8.0;
  bool get hasClusterCaution => maxClusterRatio >= 4.0 && maxClusterRatio < 8.0;
  bool get hasCabalWarning => cabalCount > 0;
  bool get isSmartMoneyHealthy => smartCount >= 2 || smartRatio >= 1.0;
  bool get isKolStrong => kolCount >= 2 || kolRatio >= 2.0;
}

class BubbleAuditService {
  BubbleAuditService._();
  static final BubbleAuditService instance = BubbleAuditService._();

  static const Map<String, String> _chainMapping = {
    'bsc': 'bsc',
    'solana': 'solana',
    'sol': 'solana',
    'base': 'base',
    'eth': 'eth',
    'ethereum': 'eth',
  };

  // 内存高频缓存
  final Map<String, BubbleAuditResult> _cache = {};
  final Set<String> _inFlight = {};

  BubbleAuditResult? getCached(String address, String chain) {
    final lowerChain = chain.toLowerCase().trim();
    final apiChain = aveChains[lowerChain] ??
        _chainMapping[lowerChain] ??
        (lowerChain == 'ethereum' ? 'eth' : lowerChain);
    final cleanAddr = address.trim();
    final formattedAddr = (apiChain == 'solana') ? cleanAddr : cleanAddr.toLowerCase();
    final key = '$formattedAddr-$apiChain';
    return _cache[key];
  }

  Future<BubbleAuditResult> auditToken(String address, String chain) async {
    final lowerChain = chain.toLowerCase().trim();
    final apiChain = aveChains[lowerChain] ??
        _chainMapping[lowerChain] ??
        (lowerChain == 'ethereum' ? 'eth' : lowerChain);

    // Solana (Base58) 严格大小写敏感，严禁转小写；EVM 链统一转小写
    final cleanAddr = address.trim();
    final formattedAddr = (apiChain == 'solana') ? cleanAddr : cleanAddr.toLowerCase();
    final key = '$formattedAddr-$apiChain';

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    if (_inFlight.contains(key)) {
      // 等待进行中的请求，避免重复触发
      while (_inFlight.contains(key)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _cache[key] ?? const BubbleAuditResult(error: 'cancelled');
    }

    _inFlight.add(key);

    try {
      final url = Uri.parse(
          'https://h5.phaetd4l.com/v1api/v3/stats/holders?token_id=$formattedAddr-$apiChain');

      final headers = {
        'origin': 'https://bubble.aveai.trade',
        'referer': 'https://bubble.aveai.trade/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      };

      // 增加自动重试 1 次（解决网络瞬时抖动）
      http.Response? response;
      for (int attempt = 0; attempt < 2; attempt++) {
        final client = http.Client();
        try {
          response = await client
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) break;
        } catch (_) {
          if (attempt == 1) rethrow;
          await Future.delayed(const Duration(milliseconds: 500));
        } finally {
          client.close();
        }
      }

      if (response == null || response.statusCode != 200) {
        final res = BubbleAuditResult(
          error: 'HTTP ${response?.statusCode ?? 0}',
          isLoaded: true,
        );
        _cache[key] = res;
        return res;
      }

      final jsonMap = jsonDecode(response.body);
      if (jsonMap is! Map<String, dynamic> || jsonMap['status'] != 1) {
        final res = BubbleAuditResult(
          error: jsonMap['msg']?.toString() ?? 'API Error',
          isLoaded: true,
        );
        _cache[key] = res;
        return res;
      }

      final data = jsonMap['data'] as Map<String, dynamic>? ?? {};
      final holders = (data['holderStats'] as List<dynamic>?) ?? [];

      // 1. 前 10 大持仓集中度 (Top10 Ratio)
      // 计算前 10 个非 LP 地址的持仓比例之和
      double top10Sum = 0.0;
      int top10Count = 0;
      for (final h in holders) {
        if (h is! Map<String, dynamic>) continue;
        final tags = (h['new_tags'] as List<dynamic>?) ?? [];
        bool isLp = false;
        for (final t in tags) {
          if (t is Map && (t['en']?.toString().toUpperCase() == 'LP')) {
            isLp = true;
            break;
          }
        }
        if (isLp) continue;

        final ratio =
            (double.tryParse(h['balance_ratio']?.toString() ?? '0') ?? 0.0) *
                100.0;
        top10Sum += ratio;
        top10Count++;
        if (top10Count >= 10) break;
      }

      // 2. 关联钱包集群出资人归集 (Cluster)
      final Map<String, List<double>> funderGroups = {};
      int smart = 0;
      double smartR = 0.0;
      int kol = 0;
      double kolR = 0.0;
      int cabal = 0;

      for (final h in holders) {
        if (h is! Map<String, dynamic>) continue;
        final addr = (h['holder']?.toString() ?? '').toLowerCase();
        final ratio =
            (double.tryParse(h['balance_ratio']?.toString() ?? '0') ?? 0.0) *
                100.0;

        // 出资人归集
        final tf =
            (h['token_first_transfer_in_from']?.toString() ?? '').toLowerCase();
        final sf =
            (h['sol_first_transfer_in_from']?.toString() ?? '').toLowerCase();
        final funder = tf.isNotEmpty ? tf : sf;

        if (funder.isNotEmpty && funder != addr) {
          funderGroups.putIfAbsent(funder, () => []).add(ratio);
        }

        // 标签解析: AVE 会返回 "SmartMoney", "KOL", "Cabal", "聪明钱", "抄底" 等
        final tags = (h['new_tags'] as List<dynamic>?) ?? [];
        bool isSmartWallet = false;
        bool isKolWallet = false;
        for (final t in tags) {
          if (t is! Map<String, dynamic>) continue;
          final en = (t['en']?.toString() ?? '').toLowerCase();
          final cn = (t['cn']?.toString() ?? '').toLowerCase();
          final nick = (t['nick_name']?.toString() ?? '').toLowerCase();

          if (en.contains('smart') ||
              cn.contains('聪明') ||
              cn.contains('波段') ||
              cn.contains('抄底') ||
              nick.contains('smart')) {
            isSmartWallet = true;
          }
          if (en.contains('kol') ||
              cn.contains('大v') ||
              cn.contains('推特') ||
              en.contains('twitter') ||
              nick.contains('kol')) {
            isKolWallet = true;
          }
          if (en.contains('cabal') || cn.contains('阴谋') || nick.contains('cabal')) {
            cabal++;
          }
        }

        if (isSmartWallet) {
          smart++;
          smartR += ratio;
        }
        if (isKolWallet) {
          kol++;
          kolR += ratio;
        }
      }

      // 找出最大集群
      double maxCluster = 0.0;
      for (final group in funderGroups.values) {
        if (group.length >= 2) {
          final sum = group.fold<double>(0.0, (prev, elem) => prev + elem);
          if (sum > maxCluster) {
            maxCluster = sum;
          }
        }
      }

      final result = BubbleAuditResult(
        maxClusterRatio: double.parse(maxCluster.toStringAsFixed(1)),
        smartCount: smart,
        smartRatio: double.parse(smartR.toStringAsFixed(1)),
        kolCount: kol,
        kolRatio: double.parse(kolR.toStringAsFixed(1)),
        cabalCount: cabal,
        top100Ratio: double.parse(top10Sum.toStringAsFixed(1)),
        isLoaded: true,
      );

      _cache[key] = result;
      return result;
    } catch (e, st) {
      debugPrint('BubbleAuditService exception: $e\n$st');
      final res = BubbleAuditResult(
        error: e.toString(),
        isLoaded: true,
      );
      _cache[key] = res;
      return res;
    } finally {
      _inFlight.remove(key);
    }
  }
}
