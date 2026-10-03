import 'package:flutter_test/flutter_test.dart';
import 'package:meme_radar_android/services/radar_service.dart';
import 'package:meme_radar_android/services/storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FakeStorageService extends StorageService {
  final Map<String, String> _data = {};

  FakeStorageService() : super(storage: const FlutterSecureStorage());

  @override
  Future<String?> getApiKey() async => _data['ave_api_key'];

  @override
  Future<void> saveApiKey(String apiKey) async {
    _data['ave_api_key'] = apiKey;
  }

  @override
  Future<String> getSelectedChain([String fallback = 'bsc']) async {
    final chain = _data['selected_chain'];
    if (chain != null && ['sol', 'bsc', 'base', 'eth', 'robinhood'].contains(chain)) {
      return chain;
    }
    return fallback;
  }

  @override
  Future<void> saveSelectedChain(String chain) async {
    _data['selected_chain'] = chain.toLowerCase();
  }
}

void main() {
  test('RadarService allows switching to all 5 supported chains', () async {
    final storage = FakeStorageService();
    final service = RadarService(storageService: storage);

    // Initial default is bsc
    expect(service.activeChain, 'bsc');

    // Test changing to each chain
    final chains = ['sol', 'bsc', 'base', 'eth', 'robinhood'];
    
    for (final chain in chains) {
      service.setChain(chain);
      expect(service.activeChain, chain, reason: 'Failed to switch to $chain');
    }
  });

  test('RadarService ignores IPC messages if status is stopped', () async {
    final storage = FakeStorageService();
    final service = RadarService(storageService: storage);

    // Initial state is stopped
    expect(service.status, RadarScanStatus.stopped);

    service.testOnReceiveTaskData('{"event": "cycle_complete", "activeChain": "eth", "scanCount": 10, "totalDiscovered": 5, "totalPrequalified": 2, "marketQualifiedCount": 1, "liveDiscoveryRows": [], "lastCycleDurationMs": 100, "lastScanTime": 10000000}');

    // State should remain stopped, the message should be ignored
    expect(service.status, RadarScanStatus.stopped);
    expect(service.activeChain, 'bsc'); // Should not have updated to 'eth'
  });

  test('RadarService processes IPC messages if status is not stopped', () async {
    final storage = FakeStorageService();
    final service = RadarService(storageService: storage);

    service.testStatus = RadarScanStatus.scanning;

    service.testOnReceiveTaskData('{"event": "cycle_complete", "activeChain": "eth", "scanCount": 10, "totalDiscovered": 5, "totalPrequalified": 2, "marketQualifiedCount": 1, "liveDiscoveryRows": [], "lastCycleDurationMs": 100, "lastScanTime": 10000000}');

    // State should become idle, message processed
    expect(service.status, RadarScanStatus.idle);
    expect(service.activeChain, 'eth');
  });
}
