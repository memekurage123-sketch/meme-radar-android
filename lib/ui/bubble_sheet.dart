import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../radar_core/ave.dart';

class BubbleSheet extends StatefulWidget {
  final String chain;
  final String address;
  final String? symbol;

  const BubbleSheet({
    super.key,
    required this.chain,
    required this.address,
    this.symbol,
  });

  static Future<void> show(
    BuildContext context, {
    required String chain,
    required String address,
    String? symbol,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => BubbleSheet(
        chain: chain,
        address: address,
        symbol: symbol,
      ),
    );
  }

  @override
  State<BubbleSheet> createState() => _BubbleSheetState();
}

class _BubbleSheetState extends State<BubbleSheet> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _progress = 0;
  String? _errorMessage;
  late final String _bubbleUrl;

  @override
  void initState() {
    super.initState();
    final lowerChain = widget.chain.toLowerCase();
    final apiChain = aveChains[lowerChain] ?? lowerChain;
    _bubbleUrl =
        'https://bubble.aveai.trade/?token_id=${widget.address}-$apiChain';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF151821))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _progress = progress;
              });
            }
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = error.description;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_bubbleUrl));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displaySymbol = widget.symbol?.toUpperCase() ?? 'TOKEN';
    final displayChain = widget.chain.toUpperCase();

    return FractionallySizedBox(
      heightFactor: 0.50,
      child: Column(
        children: [
          // Drag handle and top bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E222D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2E39), width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pill
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.blue.withAlpha(100), width: 0.8),
                      ),
                      child: Text(
                        displayChain,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$displaySymbol · 气泡图',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 20, color: Colors.white70),
                      tooltip: '刷新',
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _controller.reload();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_browser,
                          size: 20, color: Colors.white70),
                      tooltip: '浏览器打开',
                      onPressed: () async {
                        final uri = Uri.parse(_bubbleUrl);
                        try {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 20, color: Colors.white70),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Loading Progress Bar
          if (_isLoading && _progress < 100)
            LinearProgressIndicator(
              value: _progress / 100.0,
              backgroundColor: const Color(0xFF151821),
              color: theme.colorScheme.primary,
              minHeight: 2,
            ),

          // WebView content area
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading && _errorMessage == null)
                  Container(
                    color: const Color(0xFF151821),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '正在加载 AVE 气泡图 ($_progress%)...',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_errorMessage != null)
                  Container(
                    color: const Color(0xFF151821),
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded,
                              size: 40, color: Colors.redAccent),
                          const SizedBox(height: 12),
                          Text(
                            '气泡图加载失败\n$_errorMessage',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('重试'),
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = null;
                              });
                              _controller.loadRequest(Uri.parse(_bubbleUrl));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
