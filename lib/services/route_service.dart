import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../models/route_models.dart';

class RouteService {
  final String host;
  final int port;

  final http.Client _client = http.Client();

  RouteService({required this.host, required this.port});

  String get _baseUrl {
    return Uri(scheme: 'http', host: host, port: port).toString();
  }

  void close() {
    _client.close();
  }

  Future<List<RouteSummary>> getRoutes() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/routes'))
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not load recorded fields.');

    final data = jsonDecode(response.body) as List;

    return data
        .map((item) => RouteSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<SavedRoute?> getRecordingRoute() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/routes/recording'))
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not check active field recording.');

    final body = Map<String, dynamic>.from(jsonDecode(response.body));

    final active = body['active'] == true;

    if (!active || body['route'] == null) {
      return null;
    }

    return SavedRoute.fromJson(Map<String, dynamic>.from(body['route']));
  }

  Future<SavedRoute> getRoute(int routeId) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/routes/$routeId'))
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not load recorded field.');

    return _savedRoute(response);
  }

  Future<SavedRoute> startRoute(String name) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/routes/start'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name}),
        )
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not start field recording.');

    return _savedRoute(response);
  }

  Future<SavedRoute> finishRoute(int routeId) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/routes/'
            '$routeId/finish',
          ),
        )
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not finish field recording.');

    return _savedRoute(response);
  }

  Future<void> discardRoute(int routeId) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/routes/'
            '$routeId/discard',
          ),
        )
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not discard field recording.');
  }

  Future<void> addEvent(int routeId, String event) async {
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/routes/'
            '$routeId/events',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'event_type': event}),
        )
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not save field event.');
  }

  Future<void> deleteRoute(int routeId) async {
    final response = await _client
        .delete(Uri.parse('$_baseUrl/routes/$routeId'))
        .timeout(AppConfig.requestTimeout);

    _requireOk(response, 'Could not delete recorded field.');
  }

  SavedRoute _savedRoute(http.Response response) {
    return SavedRoute.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body)),
    );
  }

  void _requireOk(http.Response response, String fallback) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String? detail;

    try {
      final body = jsonDecode(response.body);

      if (body is Map && body['detail'] != null) {
        final rawDetail = body['detail'];

        if (rawDetail is Map && rawDetail['message'] != null) {
          detail = rawDetail['message'].toString();
        } else {
          detail = rawDetail.toString();
        }
      }
    } catch (_) {}

    throw Exception(detail ?? fallback);
  }
}
