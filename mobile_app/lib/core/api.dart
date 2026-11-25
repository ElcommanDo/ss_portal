import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error returned by the server (or by the network layer) in a form
/// that can be shown to the user directly.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? field;

  ApiException(this.message, {this.statusCode, this.field});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

typedef UnauthorizedHandler = void Function(String message);

class ApiClient {
  ApiClient({required this.baseUrl, this.token, this.onUnauthorized});

  String baseUrl;
  String? token;
  UnauthorizedHandler? onUnauthorized;

  final http.Client _http = http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    var uri = Uri.parse('$cleanBase${AppConfig.apiPrefix}$cleanPath');
    if (query != null) {
      final q = <String, String>{};
      query.forEach((key, value) {
        if (value == null) return;
        final s = value.toString();
        if (s.isEmpty) return;
        q[key] = s;
      });
      if (q.isNotEmpty) {
        uri = uri.replace(queryParameters: q);
      }
    }
    return uri;
  }

  Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json; charset=utf-8';
    final t = token;
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Token $t';
      h['X-Auth-Token'] = t; // fallback for hosts that strip Authorization
    }
    return h;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _send(() => _http.get(_uri(path, query), headers: _headers(json: false)));
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) {
    return _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? <String, dynamic>{})));
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) {
    return _send(() => _http.put(_uri(path), headers: _headers(), body: jsonEncode(body)));
  }

  Future<dynamic> delete(String path) {
    return _send(() => _http.delete(_uri(path), headers: _headers(json: false)));
  }

  /// Downloads a binary file (used for the PDF reports).
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    final response = await _raw(() => _http.get(_uri(path, query), headers: _headers(json: false)));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw _errorFrom(response);
  }

  Future<http.Response> _raw(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long to respond. Please try again.');
    } on SocketException {
      throw ApiException('No connection to the server. Check your internet connection.');
    } on HandshakeException {
      throw ApiException('Secure connection to the server failed.');
    } on http.ClientException catch (e) {
      throw ApiException('Connection error: ${e.message}');
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final response = await _raw(call);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return <String, dynamic>{};
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiException('Unexpected response from the server.', statusCode: response.statusCode);
      }
    }
    final error = _errorFrom(response);
    if (error.isUnauthorized && token != null) {
      onUnauthorized?.call(error.message);
    }
    throw error;
  }

  ApiException _errorFrom(http.Response response) {
    final code = response.statusCode;
    String? message;
    String? field;
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map) {
        if (data['detail'] != null) message = data['detail'].toString();
        if (data['field'] != null) field = data['field'].toString();
      }
    } catch (_) {
      // HTML error page (e.g. DEBUG=False 404/500) -> friendly message below
    }
    message ??= switch (code) {
      401 => 'Please sign in again.',
      403 => 'You do not have permission to do this.',
      404 => 'Not found on the server. Make sure the portal is updated with the mobile API (/api/v1/).',
      429 => 'Too many attempts. Please wait and try again.',
      >= 500 => 'Server error ($code). Please try again later.',
      _ => 'Request failed ($code).',
    };
    return ApiException(message, statusCode: code, field: field);
  }
}
