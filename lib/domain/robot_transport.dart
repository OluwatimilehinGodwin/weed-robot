abstract class RobotTransport {
  Stream<Map<String, dynamic>> get messages;
  Stream<bool> get connections;
  Future<void> connect({required String host, required int port});
  bool sendCommand(String command, {String? requestId});
  Future<void> disconnect();
  void dispose();
}
