import 'package:flutter/material.dart';
import '../services/radar_service.dart';
import '../services/storage_service.dart';
import 'settings_dialog.dart';
import 'candidate_card.dart';

class RadarScreen extends StatefulWidget {
  final StorageService storageService;
  final RadarService radarService;

  const RadarScreen({
    super.key,
    required this.storageService,
    required this.radarService,
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final List<Map<String, String>> _chains = const [
    {'id': 'sol', 'name': 'Solana'},
    {'id': 'bsc', 'name': 'BSC'},
    {'id': 'base', 'name': 'Base'},
    {'id': 'eth', 'name': 'Ethereum'},
    {'id': 'robinhood', 'name': 'Robinhood'},
  ];

  @override
  void initState() {
    super.initState();
    _checkInitialKey();
  }

  Future<void> _checkInitialKey() async {
    final key = await widget.storageService.getApiKey();
    if ((key == null || key.isEmpty) && mounted) {
      // Prompt user to configure key
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SettingsDialog.show(
          context,
          storageService: widget.storageService,
          radarService: widget.radarService,
        );
      });
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.radarService,
      builder: (context, _) {
        final r = widget.radarService;
        final isScanning = r.status == RadarScanStatus.scanning;
        final isRunning = r.isRunning;
        final candidates = r.candidates;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/radar_logo.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                const Text('Meme Radar',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () {
                  SettingsDialog.show(
                    context,
                    storageService: widget.storageService,
                    radarService: widget.radarService,
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Status & Info Header
              _buildStatusHeader(context, r, isScanning, isRunning),

              // Chain Selector Chips
              _buildChainSelector(context, r),

              const Divider(height: 1),

              // Candidates List / Empty State
              Expanded(
                child: _buildCandidatesList(context, r, candidates, isScanning),
              ),
            ],
          ),
          bottomNavigationBar:
              _buildBottomActionBar(context, r, isRunning, isScanning),
        );
      },
    );
  }

  Widget _buildStatusHeader(
    BuildContext context,
    RadarService r,
    bool isScanning,
    bool isRunning,
  ) {
    final theme = Theme.of(context);
    final statusText = isScanning
        ? '正在扫描...'
        : (isRunning
            ? '等待下轮扫描'
            : (r.status == RadarScanStatus.error ? '异常' : '已停止'));
    final statusColor = isScanning
        ? Colors.amber
        : (isRunning
            ? Colors.green
            : (r.status == RadarScanStatus.error ? Colors.red : Colors.grey));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(40)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: isScanning
                      ? [
                          BoxShadow(
                            color: statusColor.withAlpha(150),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              Text(
                '周期: #${r.scanCount}',
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeaderStat('Scanned', '${r.totalDiscovered}'),
              _buildHeaderStat('Qualified', '${r.marketQualifiedCount}'),
              _buildHeaderStat('Live Candidates', '${r.candidates.length}'),
              _buildHeaderStat('最新时间', _formatTime(r.lastScanTime)),
            ],
          ),
          if (r.lastError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.lastError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildChainSelector(BuildContext context, RadarService r) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: _chains.map((chain) {
          final isSelected = r.activeChain == chain['id'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(chain['name']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  r.setChain(chain['id']!);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCandidatesList(
    BuildContext context,
    RadarService r,
    List<Map<String, dynamic>> candidates,
    bool isScanning,
  ) {
    if (candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.radar,
                size: 64,
                color: Theme.of(context).colorScheme.outline.withAlpha(120),
              ),
              const SizedBox(height: 16),
              Text(
                isScanning ? '正在扫描链上数据并执行多维过滤...' : '暂无候选代币',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isScanning
                    ? '已抓取 ${r.totalDiscovered} 个代币，正在预审过滤'
                    : '点击下方 "Start Radar" 开启前台实时扫描。\n符合发现阈值与风控要求的代币将展示于此。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: candidates.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return CandidateCard(candidate: candidates[index]);
      },
    );
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    RadarService r,
    bool isRunning,
    bool isScanning,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: isRunning
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => r.stopScan(),
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop Radar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => r.startScan(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start Radar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: isScanning ? null : () => r.runSingleCycle(),
              tooltip: '单次扫描刷新',
              icon: isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
