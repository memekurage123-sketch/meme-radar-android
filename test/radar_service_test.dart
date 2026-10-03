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
}
