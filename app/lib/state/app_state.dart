import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/run_store.dart';
import '../services/run_sync.dart';

enum AuthStatus { unknown, signedOut, signedIn, unavailable }

class AppState extends ChangeNotifier {
  final ApiClient api;
  AppState({ApiClient? api}) : api = api ?? ApiClient();
  String? connectionError;

  AuthStatus status = AuthStatus.unknown;
  UserProfile? profile;

  Future<void> bootstrap() async {
    status = AuthStatus.unknown;
    connectionError = null;
    notifyListeners();
    try {
      await api.loadToken();
      if (api.isAuthenticated) {
        profile = await api.getMyProfile();
        status = AuthStatus.signedIn;
      } else {
        status = AuthStatus.signedOut;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await api.logout();
        status = AuthStatus.signedOut;
      } else {
        connectionError = e.message;
        status = AuthStatus.unavailable;
      }
    } catch (_) {
      connectionError =
          'Não foi possível carregar sua sessão. Tente novamente.';
      status = AuthStatus.unavailable;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await api.login(email: email, password: password);
    status = AuthStatus.signedIn;
    try {
      profile = await api.getMyProfile();
      unawaited(_retryPendingRunsQuietly());
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      profile = null;
    }
    notifyListeners();
  }

  Future<void> loginWithOAuth(String provider, String idToken) async {
    await api.loginWithOAuth(provider: provider, idToken: idToken);
    status = AuthStatus.signedIn;
    try {
      profile = await api.getMyProfile();
      unawaited(_retryPendingRunsQuietly());
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      profile = null;
    }
    notifyListeners();
  }

  Future<void> register(
    String fullName,
    String username,
    String email,
    String password, {
    String? photoUrl,
  }) async {
    await api.register(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
      photoUrl: photoUrl,
    );
    profile = await api.getMyProfile();
    status = AuthStatus.signedIn;
    unawaited(_retryPendingRunsQuietly());
    notifyListeners();
  }

  void applyUpdatedProfile(UserProfile updated) {
    if (profile?.id != updated.id) return;
    profile = updated;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    profile = await api.getMyProfile();
    notifyListeners();
  }

  Future<bool> retryPendingRuns() async {
    if (profile == null) {
      try {
        profile = await api.getMyProfile();
        notifyListeners();
      } catch (_) {
        return false;
      }
    }
    final currentProfile = profile;
    if (currentProfile == null) return false;
    final store = RunStore(currentProfile.id);
    final sync = RunSync(api, store);
    var submitted = false;
    for (final draft in await store.list()) {
      if (!draft.queued) continue;
      try {
        await sync.submit(draft);
        submitted = true;
      } on ApiException catch (error) {
        if (error.statusCode == 401) rethrow;
      }
    }
    try {
      await refreshProfile();
    } catch (_) {
      if (!submitted) rethrow;
    }
    return submitted;
  }

  Future<void> _retryPendingRunsQuietly() async {
    try {
      await retryPendingRuns();
    } catch (_) {}
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } finally {
      profile = null;
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }
}
