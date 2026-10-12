import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/run_store.dart';
import '../services/run_sync.dart';

enum AuthStatus { unknown, signedOut, signedIn, unavailable }

class AppState extends ChangeNotifier {
  final ApiClient api;
  AppState({ApiClient? api}) : api = api ?? ApiClient();
  String? connectionError;
  static const _themeModeKey = 'runover_theme_mode';
  ThemeMode themeMode = ThemeMode.system;

  Future<void> loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_themeModeKey);
      themeMode = switch (savedMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(
        _themeModeKey,
        mode.name,
      );
    } catch (_) {
      // Keep the selected theme active even if preferences are unavailable.
    }
  }

  AuthStatus status = AuthStatus.unknown;
  UserProfile? profile;
  int _runsRevision = 0;

  int get runsRevision => _runsRevision;

  void markRunSaved() {
    _runsRevision++;
    notifyListeners();
  }

  int _tourRequests = 0;

  /// Pedidos de replay do tutorial (drawer "Ver tutorial").
  int get tourRequests => _tourRequests;

  void requestTour() {
    _tourRequests++;
    notifyListeners();
  }

  /// Avisa o back-end que o app está aberto (nunca quebra o fluxo).
  void pingPresence() {
    unawaited(_pingPresence());
  }

  Future<void> _pingPresence() async {
    try {
      await api.heartbeat();
    } catch (_) {}
  }

  Future<void> bootstrap() async {
    status = AuthStatus.unknown;
    connectionError = null;
    notifyListeners();
    try {
      await api.loadToken();
      if (api.isAuthenticated) {
        profile = await api.getMyProfile();
        status = AuthStatus.signedIn;
        pingPresence();
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

  /// Abre a sessão depois de qualquer prova de identidade aceita pelo servidor
  /// (senha, código do e-mail, login social). O perfil é consequência: se a
  /// leitura falhar por outro motivo que não credencial, a pessoa já está
  /// dentro e continua dentro.
  Future<void> _enterAuthenticated() async {
    status = AuthStatus.signedIn;
    pingPresence();
    try {
      profile = await api.getMyProfile();
      unawaited(_retryPendingRunsQuietly());
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      profile = null;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await api.login(email: email, password: password);
    await _enterAuthenticated();
  }

  /// Reativa uma conta desativada temporariamente (volta tudo como estava).
  Future<void> reactivate(String email, String password) async {
    await api.reactivate(email: email, password: password);
    await _enterAuthenticated();
  }

  Future<void> loginWithOAuth(String provider, String idToken) async {
    await api.loginWithOAuth(provider: provider, idToken: idToken);
    await _enterAuthenticated();
  }

  /// Reativa via login social a partir da identidade verificada.
  Future<void> reactivateWithOAuth(String provider, String idToken) async {
    await api.reactivateWithOAuth(provider: provider, idToken: idToken);
    await _enterAuthenticated();
  }

  /// Entrada pelo código que chegou no e-mail: é o portão do cadastro, e o
  /// único caminho para dentro de uma conta recém-criada.
  Future<void> confirmEmail({
    required String email,
    required String code,
  }) async {
    await api.verifyEmail(email: email, code: code);
    await _enterAuthenticated();
  }

  /// Cria a conta. Quando o servidor exige a confirmação do e-mail, devolve o
  /// resultado sem sessão: quem chama leva a pessoa para digitar o código.
  Future<RegistrationResult> register(
    String fullName,
    String username,
    String email,
    String password, {
    String? photoUrl,
  }) async {
    final result = await api.register(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
      photoUrl: photoUrl,
    );
    if (result.requiresVerification) return result;
    await _enterAuthenticated();
    return result;
  }

  void applyUpdatedProfile(UserProfile updated) {
    if (profile?.id != updated.id) return;
    profile = updated;
    notifyListeners();
  }

  int _profileRevision = 0;

  /// Recarregar o perfil só acontece quando algo da conta mudou (loja,
  /// corrida, passe). Quem deriva dados da conta compara este contador para
  /// saber que precisa buscar de novo.
  int get profileRevision => _profileRevision;

  Future<void> refreshProfile() async {
    profile = await api.getMyProfile();
    _profileRevision++;
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
    if (submitted) markRunSaved();
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
