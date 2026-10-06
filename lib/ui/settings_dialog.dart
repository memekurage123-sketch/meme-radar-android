import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../services/radar_service.dart';
import '../services/storage_service.dart';

class SettingsDialog extends StatefulWidget {
  final StorageService storageService;
  final RadarService radarService;

  const SettingsDialog({
    super.key,
    required this.storageService,
    required this.radarService,
  });

  static Future<bool?> show(
    BuildContext context, {
    required StorageService storageService,
    required RadarService radarService,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SettingsDialog(
        storageService: storageService,
        radarService: radarService,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;
  String? _savedKeyMasked;
  late String _currentSortMethod;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    _currentSortMethod = widget.radarService.sortMethod;
    _loadExistingKey();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    final granted = await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled() ??
        false;
    if (mounted) {
      setState(() {
        _notificationGranted = granted;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final plugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (plugin != null) {
      await plugin.requestNotificationsPermission();
      _checkNotificationPermission();
    }
  }

  Future<void> _loadExistingKey() async {
    final key = await widget.storageService.getApiKey();
    if (key != null && key.isNotEmpty && mounted) {
      setState(() {
        _savedKeyMasked = _maskKey(key);
      });
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final keyToTest = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : await widget.storageService.getApiKey();

    if (keyToTest == null || keyToTest.isEmpty) {
      setState(() {
        _testResult = '请输入或先保存 AVE API Key';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final res = await widget.radarService.testConnection(keyToTest);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = res['success'] == true;
        _testResult =
            res['message']?.toString() ?? (_testSuccess ? '连接成功' : '连接失败');
      });
    }
  }

  Future<void> _saveSettings() async {
    final input = _controller.text.trim();
    if (input.isNotEmpty) {
      await widget.storageService.saveApiKey(input);
    }
    widget.radarService.setSortMethod(_currentSortMethod);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, size: 24),
          SizedBox(width: 8),
          Text('Settings'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('排序方式 (仅影响本地视图)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<String>(
                value: _currentSortMethod,
                isExpanded: true,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'recent', child: Text('最近出现')),
                  DropdownMenuItem(value: 'volume5m', child: Text('5m 成交额')),
                  DropdownMenuItem(value: 'priority', child: Text('2–8万市值优先')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _currentSortMethod = value;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text('Candidate Notifications',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _notificationGranted
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  size: 20,
                  color: _notificationGranted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notificationGranted ? 'Enabled' : 'Permission required',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (!_notificationGranted)
                  TextButton(
                    onPressed: _requestNotificationPermission,
                    child: const Text('Request'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('AVE API Key',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              '仅保存在本机 Android Keystore 中，直接请求 AVE 官方 API，绝不上载。',
              style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            if (_savedKeyMasked != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      '已保存: $_savedKeyMasked',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              obscureText: _obscureText,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText:
                    _savedKeyMasked != null ? '更换 API Key' : '输入 AVE API Key',
                hintText: '粘贴您的 API Key',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isTesting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('正在测试连接 AVE...', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            if (_testResult != null && !_isTesting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? Colors.green.withAlpha(40)
                      : Colors.red.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _testSuccess
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testSuccess ? Icons.check_circle : Icons.error,
                      size: 16,
                      color: _testSuccess ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _testSuccess
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : _testConnection,
          child: const Text('测试连接'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
