import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/robot_transport.dart';

class PiSocketService implements RobotTransport {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _connections = StreamController<bool>.broadcast();
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<bool> get connections => _connections.stream;

  @override
  Future<void> connect({required String host, required int port}) async {
    final generation = ++_generation;
    await _close();
    if (_disposed || generation != _generation) return;
    final channel = WebSocketChannel.connect(
      Uri(scheme: 'ws', host: host, port: port, path: '/ws'),
    );
    _channel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_disposed || generation != _generation) {
        unawaited(channel.sink.close().catchError((Object _) {}));
        return;
      }
      _connections.add(true);
      _subscription = channel.stream.listen(
        (raw) {
          if (_disposed || generation != _generation) return;
          try {
            final value = jsonDecode(raw.toString());
            if (value is Map<String, dynamic>) _messages.add(value);
          } on FormatException {
            _messages.add({
              'type': 'error',
              'message': 'Invalid robot response',
            });
          }
        },
        onError: (Object error) => _lost(generation),
        onDone: () => _lost(generation),
        cancelOnError: true,
      );
    } catch (_) {
      if (generation == _generation) {
        await _close();
        if (!_disposed) _connections.add(false);
      }
      rethrow;
    }
  }

  void _lost(int generation) {
    if (_disposed || generation != _generation) return;
    ++_generation;
    unawaited(_close());
    _connections.add(false);
  }

  @override
  bool sendCommand(String command, {String? requestId}) {
    if (_disposed || _channel == null) return false;
    try {
      _channel!.sink.add(
        jsonEncode({
          'type': 'command',
          'command': command,
          if (requestId != null) 'request_id': requestId,
        }),
      );
      return true;
    } catch (_) {
      _lost(_generation);
      return false;
    }
  }

  Future<void> _close() async {
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    await subscription?.cancel();
    // Do not let an unresponsive peer block replacement/disposal.
    if (channel != null)
      unawaited(channel.sink.close().catchError((Object _) {}));
  }

  @override
  Future<void> disconnect() async {
    ++_generation;
    await _close();
    if (!_disposed) _connections.add(false);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_close());
    unawaited(_messages.close());
    unawaited(_connections.close());
  }
}
