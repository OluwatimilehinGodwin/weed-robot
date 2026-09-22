import 'package:flutter/material.dart';

import '../widgets/responsive_page.dart';
import '../theme/app_colors.dart';
import '../widgets/neu_button.dart';
import '../widgets/neu_card.dart';

class ConnectionScreen extends StatefulWidget {
  final bool connected;
  final String initialHost;
  final int initialPort;
  final String lastMessage;

  final Future<void> Function(String host, int port) onConnect;

  final Future<void> Function() onDisconnect;

  const ConnectionScreen({
    super.key,
    required this.connected,
    required this.initialHost,
    required this.initialPort,
    required this.lastMessage,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  State<ConnectionScreen> createState() {
    return _ConnectionScreenState();
  }
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final TextEditingController _hostController;

  late final TextEditingController _portController;

  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _hostController = TextEditingController(text: widget.initialHost);

    _portController = TextEditingController(
      text: widget.initialPort.toString(),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();

    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();

    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty ||
        host.contains('/') ||
        host.contains(' ') ||
        port == null ||
        port < 1 ||
        port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid Pi IP address and port.')),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await widget.onConnect(host, port);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to Raspberry Pi.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connection',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'Connect to your Raspberry Pi',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 30),
          NeuCard(
            child: Column(
              children: [
                TextField(
                  controller: _hostController,
                  enabled: !widget.connected,
                  decoration: const InputDecoration(
                    labelText: 'Raspberry Pi IP',
                    hintText: '192.168.1.50',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  enabled: !widget.connected,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '8000',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: NeuButton(
                    label: widget.connected
                        ? 'DISCONNECT'
                        : _loading
                            ? 'CONNECTING'
                            : 'CONNECT',
                    icon: widget.connected ? Icons.link_off : Icons.link,
                    filled: !widget.connected,
                    accentColor:
                        widget.connected ? AppColors.brown : AppColors.green,
                    onTap: _loading
                        ? null
                        : widget.connected
                            ? () {
                                widget.onDisconnect();
                              }
                            : _connect,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          NeuCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.connected
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: widget.connected ? AppColors.green : AppColors.brown,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.connected ? 'Pi connected' : 'Pi offline',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.lastMessage,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
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
