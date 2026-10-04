import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/edit_profile_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

class _FailingLogoutApi extends ApiClient {
  _FailingLogoutApi({required super.client});
  @override
  Future<void> logout() async => throw StateError('Storage unavailable');
}

void main() {
  Future<AppState> open(
    WidgetTester tester, {
    double width = 1100,
    bool failLogout = false,
    Future<http.Response> Function(http.Request)? onPatch,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/users/me');
      return onPatch != null
          ? onPatch(request)
          : http.Response(jsonEncode(profileData), 200);
    });
    final api = failLogout
        ? _FailingLogoutApi(client: client)
        : ApiClient(client: client);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileData)
      ..status = AuthStatus.signedIn;
    addTearDown(api.close);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(profile: state.profile!),
                  ),
                ),
                child: const Text('Abrir editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir editor'));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'editor is a full page with current identity and separate security',
    (tester) async {
      await open(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Foto atual'), findsOneWidget);
      expect(find.text('marina@example.test'), findsOneWidget);
      expect(find.text('Passo a passo'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nova senha'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone keyboard keeps fields and save action scrollable', (
    tester,
  ) async {
    await open(tester, width: 320);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextFormField, 'Nome'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Marina Nova',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Salvar alterações').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'save sends trimmed fields once and applies returned profile without a second request',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      Map<String, dynamic>? payload;
      final state = await open(
        tester,
        onPatch: (request) {
          requests++;
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return response.future;
        },
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        '  Marina Nova  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome de usuário'),
        '  marina_nova  ',
      );
      await tester.ensureVisible(find.text('Perfil público'));
      await tester.tap(find.text('Perfil público'));
      await save(tester);
      expect(find.text('Salvando…'), findsOneWidget);
      await tester.tap(find.text('Salvando…'));
      expect(requests, 1);
      expect(payload!['full_name'], 'Marina Nova');
      expect(payload!['username'], 'marina_nova');
      expect(payload!['photo_url'], isNull);
      expect(payload!['is_public'], false);
      expect(payload!.containsKey('password'), false);
      response.complete(
        http.Response(jsonEncode({...profileData, ...payload!}), 200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(state.profile!.fullName, 'Marina Nova');
      expect(state.profile!.isPublic, false);
      expect(requests, 1);
    },
  );

  testWidgets('server errors keep the form and allow retry', (tester) async {
    var requests = 0;
    await open(
      tester,
      onPatch: (_) async {
        requests++;
        return requests == 1
            ? http.Response(jsonEncode({'detail': 'Nome já utilizado.'}), 400)
            : http.Response(
                jsonEncode({...profileData, 'full_name': 'Marina Nova'}),
                200,
              );
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Marina Nova',
    );
    await save(tester);
    expect(find.text('Nome já utilizado.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Marina Nova'), findsOneWidget);
    await save(tester);
    expect(requests, 2);
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  testWidgets(
    'invalid input is blocked before sending including a collapsed photo field',
    (tester) async {
      var requests = 0;
      await open(
        tester,
        onPatch: (_) async {
          requests++;
          return http.Response('{}', 200);
        },
      );
      await tester.tap(find.text('Alterar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link da foto'),
        'not-a-url',
      );
      await tester.tap(find.text('Alterar foto'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        find.text('Informe um link de imagem começando com https://.'),
        findsOneWidget,
      );
      expect(requests, 0);
    },
  );

  testWidgets(
    'cancel confirms unsaved changes and leaves saved profile unchanged',
    (tester) async {
      final state = await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        'Não salvar',
      );
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(state.profile!.fullName, profileData['full_name']);
    },
  );

  testWidgets(
    'password change requires matching confirmation and ends the session',
    (tester) async {
      Map<String, dynamic>? payload;
      final state = await open(
        tester,
        onPatch: (request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(profileData), 200);
        },
      );
      await tester.ensureVisible(find.text('Alterar senha'));
      await tester.tap(find.text('Alterar senha'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nova senha'),
        'Exemplo123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar nova senha'),
        'Exemplo124',
      );
      await save(tester);
      expect(find.text('As senhas não coincidem.'), findsOneWidget);
      expect(payload, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar nova senha'),
        'Exemplo123',
      );
      await save(tester);
      expect(payload!['password'], 'Exemplo123');
      expect(state.status, AuthStatus.signedOut);
      expect(state.profile, isNull);
      expect(find.byType(EditProfileScreen), findsNothing);
    },
  );
  testWidgets(
    'a saved password is not reported as failed when session cleanup fails',
    (tester) async {
      var requests = 0;
      final state = await open(
        tester,
        failLogout: true,
        onPatch: (_) async {
          requests++;
          return http.Response(jsonEncode(profileData), 200);
        },
      );
      await tester.ensureVisible(find.text('Alterar senha'));
      await tester.tap(find.text('Alterar senha'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nova senha'),
        'Exemplo123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar nova senha'),
        'Exemplo123',
      );
      await save(tester);
      expect(requests, 1);
      expect(state.status, AuthStatus.signedOut);
      expect(state.profile, isNull);
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(
        find.textContaining('Senha alterada. Não foi possível limpar'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'account changes during save are reported and cannot submit into the new account',
    (tester) async {
      var requests = 0;
      final response = Completer<http.Response>();
      final state = await open(
        tester,
        onPatch: (_) {
          requests++;
          return response.future;
        },
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        'Marina Nova',
      );
      await save(tester);
      state.profile = UserProfile.fromJson({
        ...profileData,
        'id': 'other-account',
        'full_name': 'Outra pessoa',
      });
      state.notifyListeners();
      response.complete(
        http.Response(
          jsonEncode({...profileData, 'full_name': 'Marina Nova'}),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sua sessão mudou durante a atualização.'),
        findsOneWidget,
      );
      expect(state.profile!.id, 'other-account');
      expect(state.profile!.fullName, 'Outra pessoa');
      await save(tester);
      expect(requests, 1);
      expect(
        find.textContaining('Sua sessão mudou. Volte ao perfil'),
        findsOneWidget,
      );
    },
  );
}
