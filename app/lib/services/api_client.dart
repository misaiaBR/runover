import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool retryable;
  ApiException(this.message, {this.statusCode, this.retryable = false});
  @override
  String toString() => message;

  bool get isRetryable =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode! >= 500;
}

class NetworkUnavailableException extends ApiException {
  NetworkUnavailableException()
    : super(
        'Sem conexão com o servidor. A corrida ficou salva neste aparelho para tentar novamente.',
        retryable: true,
      );
}

class ApiClient {
  ApiClient({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 15),
    Duration? timeout,
  }) : _http = client ?? http.Client(),
       _requestTimeout = timeout ?? requestTimeout;

  final http.Client _http;
  final Duration _requestTimeout;
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://runover.onrender.com',
  );
  static const _tokenKey = 'runover_token';
  String? _token;

  Future<void> loadToken() async {
    _token = (await SharedPreferences.getInstance()).getString(_tokenKey);
  }

  bool get isAuthenticated => _token != null;
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_tokenKey, token)) {
      throw ApiException('Não foi possível salvar a sessão.');
    }
    _token = token;
  }

  Future<void> logout() async {
    _token = null;
    await (await SharedPreferences.getInstance()).remove(_tokenKey);
  }

  void close() => _http.close();

  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async {
        final stream = await _http.send(request);
        return http.Response.fromStream(stream);
      })().timeout(_requestTimeout);
      dynamic data;
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body);
        } on FormatException {
          throw ApiException(
            'O servidor respondeu de forma inesperada. Tente novamente.',
            statusCode: response.statusCode,
            retryable: response.statusCode >= 500,
          );
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) return data;
      var message = response.statusCode == 401
          ? 'Sua sessão expirou. Entre novamente.'
          : 'Não foi possível concluir (${response.statusCode}).';
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String) message = detail;
        if (detail is List) {
          message = detail.map((e) => e is Map ? e['msg'] : e).join('\n');
        }
      }
      throw ApiException(
        message,
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    } on TimeoutException {
      throw NetworkUnavailableException();
    } on http.ClientException {
      throw NetworkUnavailableException();
    }
  }

  Future<void> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    String? photoUrl,
  }) async {
    final data = await _request('POST', '/auth/register', {
      'full_name': fullName,
      'username': username,
      'email': email,
      'password': password,
      'photo_url': photoUrl,
      'accept_terms': true,
    });
    await _saveToken(data['access_token']);
  }

  Future<void> login({required String email, required String password}) async {
    final data = await _request('POST', '/auth/login', {
      'email': email,
      'password': password,
    });
    await _saveToken(data['access_token']);
  }

  Future<void> loginWithOAuth({
    required String provider,
    required String idToken,
  }) async {
    final data = await _request('POST', '/auth/oauth/$provider', {
      'id_token': idToken,
    });
    await _saveToken(data['access_token']);
  }

  Future<void> requestPasswordReset(String email) async {
    await _request('POST', '/auth/forgot-password', {'email': email});
  }

  Future<void> resetPassword({
    required String email,
    required String resetCode,
    required String newPassword,
  }) async {
    await _request('POST', '/auth/reset-password', {
      'email': email,
      'reset_code': resetCode,
      'new_password': newPassword,
    });
  }

  Future<UserProfile> getMyProfile() async =>
      UserProfile.fromJson(await _request('GET', '/users/me'));
  Future<UserProfile> updateProfile({
    String? fullName,
    String? username,
    String? password,
    String? photoUrl,
    bool? isPublic,
  }) async => UserProfile.fromJson(
    await _request('PATCH', '/users/me', {
      'full_name': ?fullName,
      'username': ?username,
      'password': ?password,
      if (photoUrl != null) 'photo_url': photoUrl.isEmpty ? null : photoUrl,
      'is_public': ?isPublic,
    }),
  );
  Future<List<HistoryEntry>> getMyHistory() async =>
      (await _request('GET', '/users/me/history') as List)
          .map((e) => HistoryEntry.fromJson(e))
          .toList();
  Future<PublicProfile> getPublicProfile(String username) async =>
      PublicProfile.fromJson(
        await _request('GET', '/users/${Uri.encodeComponent(username)}'),
      );
  Future<List<Territory>> listTerritories() async =>
      (await _request('GET', '/territories') as List)
          .map((e) => Territory.fromJson(e))
          .toList();
  Future<TerritoryDetail> getTerritory(String id) async =>
      TerritoryDetail.fromJson(await _request('GET', '/territories/$id'));
  Future<List<RankingEntry>> getRanking() async =>
      (await _request('GET', '/ranking') as List)
          .map((e) => RankingEntry.fromJson(e))
          .toList();
  Future<List<TeamSummary>> listTeams() async =>
      (await _request('GET', '/teams') as List)
          .map((e) => TeamSummary.fromJson(e))
          .toList();
  Future<TeamDetail> createTeam(String name) async =>
      TeamDetail.fromJson(await _request('POST', '/teams', {'name': name}));
  Future<TeamDetail?> getMyTeam() async {
    try {
      return TeamDetail.fromJson(await _request('GET', '/teams/mine'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<TeamDetail> joinTeam(String id) async =>
      TeamDetail.fromJson(await _request('POST', '/teams/$id/join'));
  Future<void> leaveTeam() async {
    await _request('POST', '/teams/leave');
  }

  Future<List<NotificationEntry>> getNotifications() async =>
      (await _request('GET', '/notifications') as List)
          .map((e) => NotificationEntry.fromJson(e))
          .toList();
  Future<void> markNotificationRead(String id) async {
    await _request('PATCH', '/notifications/$id/read');
  }

  Future<void> pingLocation(double lat, double lng) async {
    await _request('POST', '/location', {'lat': lat, 'lng': lng});
  }

  Future<Map<String, dynamic>> saveRun(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _request('POST', '/runs', payload));
  Future<List<Map<String, dynamic>>> listRuns({int offset = 0}) async =>
      (await _request('GET', '/runs?offset=$offset&limit=20') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<Map<String, dynamic>> getRun(String id) async =>
      Map<String, dynamic>.from(await _request('GET', '/runs/$id'));
  Future<Map<String, dynamic>> getProgress() async =>
      Map<String, dynamic>.from(await _request('GET', '/runs/progress'));
}
