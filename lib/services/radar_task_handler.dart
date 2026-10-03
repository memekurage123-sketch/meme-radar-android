import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../radar_core/ave.dart';
import '../radar_core/config.dart';
import '../radar_core/scanner.dart';
import '../radar_core/state.dart';
import '../radar_core/live_discovery.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'notification_deduper.dart';
import 'candidate_eligibility.dart';

@pragma('vm:entry-point')
void startCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(RadarTaskHandler());
}

class RadarTaskHandler extends TaskHandler {
  AveClient? _aveClient;
  Scanner? _scanner;
  RadarState? _state;
  StorageService? _storageService;
  NotificationService? _notificationService;
  String _activeChain = 'bsc';
  List<Map<String, dynamic>> _liveDiscoveryRows = [];
  bool _isCycleRunning = false;
  bool _pendingCycle = false;

  String _formatCurrency(dynamic value) {
    if (value == null) return '-';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null || !n.isFinite) return '-';
    if (n >= 1000000000) return '\$${(n / 1000000000).toStringAsFixed(2)}B';
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '\$${(n / 1000).toStringAsFixed(1)}K';
    return '\$${n.toStringAsFixed(2)}';
  }

  String _formatScore(dynamic value) {
    if (value == null) return '-';
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return '-';
    return n.toStringAsFixed(0);
  }
  
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _storageService = StorageService();
      _notificationService = NotificationService();
      await _notificationService!.init();
      
      _activeChain = await _storageService!.getSelectedChain('bsc');
      final apiKey = await _storageService!.getApiKey();

      if (apiKey == null || apiKey.trim().isEmpty) {
        FlutterForegroundTask.sendDataToMain(jsonEncode({'event': 'error', 'message': 'API Key not found in secure storage'}));
        return;
      }

      _state = RadarState(activeChain: _activeChain);
      _aveClient = AveClient(apiKey: apiKey.trim());
      _scanner = Scanner(aveClient: _aveClient!, config: RadarConfig(chain: _activeChain), state: _state!);
      
      _runCycle();
    } catch (e) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({'event': 'error', 'message': 'Init Error: ${e.toString()}'}));
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _runCycle();
  }
  
  Future<void> _runCycle() async {
    if (_scanner == null || _state == null) return;

    if (_isCycleRunning) {
      _pendingCycle = true;
      return;
    }

    _isCycleRunning = true;
    _pendingCycle = false;

    final stopwatch = Stopwatch()..start();
    try {
      final res = await _scanner!.cycle();
      final discoveredRows = (res['discoveredRows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      
      _liveDiscoveryRows = normalizeLiveRows(
        discoveredRows,
        _activeChain,
        RadarConfig(chain: _activeChain),
        previous: _liveDiscoveryRows,
        initialized: _liveDiscoveryRows.isNotEmpty,
      );

      final candidates = _liveDiscoveryRows.where(isEligibleCandidate).toList();
      final notifiedMap = await _storageService!.getNotifiedCandidates();
      final deduper = NotificationDeduper(notifiedMap);
      bool mapUpdated = false;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      
      for (final c in candidates) {
        final address = c['pairAddress'] ?? c['address'] ?? '';
        
        if (deduper.shouldNotify(_activeChain, address, nowMs)) {
          final symbol = c['symbol'] ?? 'Unknown';
          final chainUpper = _activeChain.toUpperCase();
          final isPriority = c['priorityBand'] == true;
          
          final title = '$symbol · $chainUpper${isPriority ? ' · PRIORITY' : ''}';
          final mc = _formatCurrency(c['marketCap']);
          final vol = _formatCurrency(c['volume5m']);
          final score = _formatScore(c['discoveryScore']);
          
          final body = 'MC $mc · Vol5m $vol · Score $score';
          final dedupeKey = '${_activeChain}_$address';
          final notificationId = dedupeKey.hashCode;
          
          await _notificationService?.showCandidateNotification(
            id: notificationId,
            title: title,
            body: body,
          );
          
          mapUpdated = true;
        }
      }
      
      if (mapUpdated) {
        await _storageService!.saveNotifiedCandidates(deduper.cleanMap(nowMs));
      }

      stopwatch.stop();

      final payload = {
        'event': 'cycle_complete',
        'activeChain': _activeChain,
        'scanCount': _state!.scanCount,
        'totalDiscovered': _state!.discoveredCount,
        'totalPrequalified': _state!.prequalifiedCount,
        'marketQualifiedCount': candidates.length,
        'liveDiscoveryRows': _liveDiscoveryRows,
        'lastCycleDurationMs': stopwatch.elapsedMilliseconds,
        'lastScanTime': DateTime.now().millisecondsSinceEpoch,
      };
      
      FlutterForegroundTask.sendDataToMain(jsonEncode(payload));
    } catch (e) {
      FlutterForegroundTask.sendDataToMain(jsonEncode({
        'event': 'error',
        'message': e.toString(),
      }));
    } finally {
      _isCycleRunning = false;
      if (_pendingCycle) {
        Future.microtask(() => _runCycle());
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _aveClient?.close();
    _aveClient = null;
    _scanner = null;
    _state = null;
  }
  
  @override
  void onReceiveData(Object data) {
    if (data is String) {
      try {
        final Map<String, dynamic> msg = jsonDecode(data);
        if (msg['action'] == 'setChain') {
          final newChain = msg['chain'] as String;
          if (newChain != _activeChain) {
            _activeChain = newChain;
            _state?.activeChain = newChain;
            _liveDiscoveryRows.clear();
            
            if (_aveClient != null) {
               _scanner = Scanner(aveClient: _aveClient!, config: RadarConfig(chain: _activeChain), state: _state!);
            }
            _runCycle();
          }
        } else if (msg['action'] == 'triggerCycle') {
          _runCycle();
        } else if (msg['action'] == 'requestState') {
          if (_state != null) {
            FlutterForegroundTask.sendDataToMain(jsonEncode({
              'event': 'cycle_complete',
              'activeChain': _activeChain,
              'scanCount': _state!.scanCount,
              'totalDiscovered': _state!.discoveredCount,
              'totalPrequalified': _state!.prequalifiedCount,
              'marketQualifiedCount': _liveDiscoveryRows.where(isEligibleCandidate).length,
              'liveDiscoveryRows': _liveDiscoveryRows,
              'lastCycleDurationMs': 0,
              'lastScanTime': DateTime.now().millisecondsSinceEpoch,
            }));
          }
        }
      } catch (_) {}
    }
  }
}
