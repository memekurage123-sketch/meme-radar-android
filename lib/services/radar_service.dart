import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../radar_core/ave.dart';
import 'storage_service.dart';
import 'radar_task_handler.dart';
import 'candidate_eligibility.dart';

enum RadarScanStatus {
  stopped,
  scanning,
  idle,
  error,
}

class RadarService extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService _storageService;

  RadarScanStatus _status = RadarScanStatus.stopped;
  String _activeChain = 'bsc';
  int _lastCycleDurationMs = 0;
  DateTime? _lastScanTime;
  String? _lastError;
  int _scanIntervalSeconds = 300;
  String _sortMethod = 'recent';
  
  List<Map<String, dynamic>> _liveDiscoveryRows = [];
  int _marketQualifiedCount = 0;
  int _scanCount = 0;
  int _totalDiscovered = 0;
  int _totalPrequalified = 0;
  bool _isStartingScan = false;

  RadarService({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  RadarScanStatus get status => _status;
  @visibleForTesting
  set testStatus(RadarScanStatus s) => _status = s;

  bool get isRunning => _status == RadarScanStatus.scanning || _status == RadarScanStatus.idle;
  bool get isCycleRunning => _status == RadarScanStatus.scanning;
  String get activeChain => _activeChain;
  String get sortMethod => _sortMethod;
  int get lastCycleDurationMs => _lastCycleDurationMs;
  DateTime? get lastScanTime => _lastScanTime;
  String? get lastError => _lastError;
  int get scanIntervalSeconds => _scanIntervalSeconds;

  List<Map<String, dynamic>> get candidates {
    final list = _liveDiscoveryRows.where(isEligibleCandidate).toList();
    if (_sortMethod == 'recent') {
      list.sort((a, b) {
        final ta = a['qualifiedAt'] ?? a['newAt'] ?? a['firstSeenAt'] ?? 0;
        final tb = b['qualifiedAt'] ?? b['newAt'] ?? b['firstSeenAt'] ?? 0;
        return tb.compareTo(ta);
      });
    } else if (_sortMethod == 'volume5m') {
      list.sort((a, b) {
        final va = (a['volume5m'] as num?)?.toDouble() ?? 0.0;
        final vb = (b['volume5m'] as num?)?.toDouble() ?? 0.0;
        return vb.compareTo(va);
      });
    } else if (_sortMethod == 'priority') {
      list.sort((a, b) {
        final pa = a['priorityBand'] == true ? 1 : 0;
        final pb = b['priorityBand'] == true ? 1 : 0;
        if (pa != pb) return pb.compareTo(pa);
        final va = (a['volume5m'] as num?)?.toDouble() ?? 0.0;
        final vb = (b['volume5m'] as num?)?.toDouble() ?? 0.0;
        return vb.compareTo(va);
      });
    }
    return list;
  }
  
  int get totalDiscovered => _totalDiscovered;
  int get totalPrequalified => _totalPrequalified;
  int get scanCount => _scanCount;
  int get marketQualifiedCount => _marketQualifiedCount;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    _activeChain = await _storageService.getSelectedChain('bsc');
    _sortMethod = await _storageService.getSortMethod('recent');
    
    _initForegroundTask();
    
    if (await FlutterForegroundTask.isRunningService) {
      _status = RadarScanStatus.idle;
      _requestDataFromTask();
    }
    
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkServiceState();
    }
  }

  Future<void> _checkServiceState() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning && _status == RadarScanStatus.stopped) {
      _status = RadarScanStatus.idle;
      _requestDataFromTask();
      notifyListeners();
    } else if (!isRunning && _status != RadarScanStatus.stopped) {
      _status = RadarScanStatus.stopped;
      notifyListeners();
    }
  }
  
  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'meme_radar_scan',
        channelName: 'Meme Radar Scanning',
        channelDescription: 'Maintains background scanning of the blockchain',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_scanIntervalSeconds * 1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @visibleForTesting
  void testOnReceiveTaskData(Object data) => _onReceiveTaskData(data);

  void _onReceiveTaskData(Object data) {
    if (_status == RadarScanStatus.stopped) return;

    if (data is String) {
      try {
        final Map<String, dynamic> msg = jsonDecode(data);
        if (msg['event'] == 'cycle_complete') {
          _activeChain = msg['activeChain'];
          _scanCount = msg['scanCount'];
          _totalDiscovered = msg['totalDiscovered'];
          _totalPrequalified = msg['totalPrequalified'];
          _marketQualifiedCount = msg['marketQualifiedCount'];
          _liveDiscoveryRows = (msg['liveDiscoveryRows'] as List).cast<Map<String, dynamic>>();
          
          final int cycleDurationMs = msg['lastCycleDurationMs'] ?? 0;
          if (cycleDurationMs > 0) {
            _lastCycleDurationMs = cycleDurationMs;
          }
          
          _lastScanTime = DateTime.fromMillisecondsSinceEpoch(msg['lastScanTime']);
          _status = RadarScanStatus.idle;
          _lastError = null;
          
          FlutterForegroundTask.updateService(
            notificationTitle: 'Meme Radar',
            notificationText: 'Radar is scanning · ${_activeChain.toUpperCase()}',
          );
          
          notifyListeners();
        } else if (msg['event'] == 'error') {
          _lastError = msg['message'];
          _status = RadarScanStatus.error;
          notifyListeners();
        }
      } catch (e) {
        _lastError = e.toString();
        _status = RadarScanStatus.error;
        notifyListeners();
      }
    }
  }

  void _requestDataFromTask() {
    FlutterForegroundTask.sendDataToTask(jsonEncode({
      'action': 'requestState'
    }));
  }

  void setSortMethod(String method) {
    if (['recent', 'volume5m', 'priority'].contains(method) && method != _sortMethod) {
      _sortMethod = method;
      _storageService.saveSortMethod(method);
      notifyListeners();
    }
  }

  void setChain(String chain) {
    final lower = chain.toLowerCase();
    if (['sol', 'bsc', 'base', 'eth', 'robinhood'].contains(lower) && lower != _activeChain) {
      _activeChain = lower;
      _storageService.saveSelectedChain(lower);
      if (isRunning) {
        _status = RadarScanStatus.scanning;
        FlutterForegroundTask.sendDataToTask(jsonEncode({
          'action': 'setChain',
          'chain': lower,
        }));
        
        FlutterForegroundTask.updateService(
          notificationTitle: 'Meme Radar',
          notificationText: 'Radar is scanning · ${_activeChain.toUpperCase()}',
        );
      }
      notifyListeners();
    }
  }

  void setScanInterval(int seconds) {
    _scanIntervalSeconds = seconds.clamp(15, 600);
    notifyListeners();
  }

  Future<Map<String, dynamic>> testConnection(String apiKey, [String? chain]) async {
    final testChain = chain ?? _activeChain;
    final client = AveClient(apiKey: apiKey);
    try {
      final res = await client.trending(testChain, page: 0, pageSize: 10);
      final count = (res['rows'] as List?)?.length ?? 0;
      return {
        'success': true,
        'count': count,
        'message': '连接成功，拉取到 $count 个代币',
      };
    } catch (e) {
      return {
        'success': false,
        'count': 0,
        'message': e.toString(),
      };
    } finally {
      client.close();
    }
  }

  Future<void> startScan() async {
    if (_isStartingScan) return;

    _isStartingScan = true;
    try {
      final apiKey = await _storageService.getApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        _status = RadarScanStatus.error;
        _lastError = '请先配置 AVE API Key';
        notifyListeners();
        return;
      }

      if (await FlutterForegroundTask.isRunningService) {
        return;
      }

      _lastError = null;
      _status = RadarScanStatus.scanning;
      notifyListeners();

      await FlutterForegroundTask.startService(
        notificationTitle: 'Meme Radar',
        notificationText: 'Radar is scanning · ${_activeChain.toUpperCase()}',
        callback: startCallback,
      );
    } finally {
      _isStartingScan = false;
    }
  }

  void stopScan() async {
    await FlutterForegroundTask.stopService();
    _status = RadarScanStatus.stopped;
    _liveDiscoveryRows.clear();
    notifyListeners();
  }

  Future<void> runSingleCycle() async {
    if (!isRunning) return;
    _status = RadarScanStatus.scanning;
    notifyListeners();
    FlutterForegroundTask.sendDataToTask(jsonEncode({
      'action': 'triggerCycle',
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }
}
