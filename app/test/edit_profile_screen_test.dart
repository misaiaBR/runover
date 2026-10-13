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

  Future<void> openConta(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-tab-conta')));
    await tester.pumpAndSettle();
  }

  testWidgets('appearance section switches theme immediately and persists', (
    tester,
  ) async {
    final state = await open(tester);
    await tester.tap(find.byKey(const Key('settings-tab-aparencia')));
    await tester.pumpAndSettle();
    expect(find.text('Tema'), findsOneWidget);
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.dark);
    // A escolha atravessa o fechamento do app: sai da tela e fica no aparelho.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('runover_theme_mode'), 'dark');
    final reloaded = AppState(api: state.api);
    addTearDown(reloaded.dispose);
    await reloaded.loadThemeMode();
    expect(reloaded.themeMode, ThemeMode.dark);
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor is a full page with current identity and separate security',
    (tester) async {
      await open(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Foto atual'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nova senha'), findsNothing);
      // A sidebar do painel de ajustes lista as secções.
      expect(find.byKey(const Key('settings-tab-conta')), findsOneWidget);
      expect(find.byKey(const Key('settings-tab-aparencia')), findsOneWidget);
      expect(find.byKey(const Key('settings-tab-treino')), findsOneWidget);
      await openConta(tester);
      expect(find.text('marina@example.test'), findsOneWidget);
      expect(find.text('Passo a passo'), findsOneWidget);
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
    await openConta(tester);
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
      await openConta(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        '  Marina Nova  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome de usuário'),
        '  marina_nova  ',
      );
      await tester.tap(find.byKey(const Key('settings-tab-privacidade')));
      await tester.pumpAndSettle();
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

  testWidgets('pronouns are sent on save and applied to the profile', (
    tester,
  ) async {
    Map<String, dynamic>? payload;
    final state = await open(
      tester,
      onPatch: (request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({...profileData, ...payload!}),
          200,
        );
      },
    );
    await openConta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ex.: ele/dele'),
      'ele/dele',
    );
    await save(tester);
    expect(payload!['pronouns'], 'ele/dele');
    expect(state.profile!.pronouns, 'ele/dele');
    expect(tester.takeException(), isNull);
  });

  testWidgets('training prefs sections are editable and sent on save', (
    tester,
  ) async {
    Map<String, dynamic>? payload;
    await open(
      tester,
      onPatch: (request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(profileData), 200);
      },
    );
    await tester.tap(find.byKey(const Key('settings-tab-treino')));
    await tester.pumpAndSettle();
    expect(find.text('Unidades'), findsOneWidget);
    expect(find.text('Quilômetros (km)'), findsOneWidget);
    expect(find.text('Milhas (mi)'), findsOneWidget);
    expect(find.text('Metas'), findsOneWidget);
    expect(find.text('Frequência semanal'), findsOneWidget);
    expect(find.text('Nível de atividade atual'), findsOneWidget);
    expect(find.text('Política de Privacidade'), findsOneWidget);

    await tester.tap(find.text('Milhas (mi)'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Qua'));
    await tester.tap(find.text('Qua'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sem meta definida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 dias por semana').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Não informado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cardio').last);
    await tester.pumpAndSettle();

    await save(tester);
    expect(payload!['distance_units'], 'mi');
    expect(payload!['training_days'], ['qua']);
    expect(payload!['weekly_frequency'], 3);
    expect(payload!['activity_level'], 'cardio');
    expect(tester.takeException(), isNull);
  });

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
    await openConta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Marina Nova',
    );
    expect(find.widgetWithText(TextFormField, 'Marina Nova'), findsOneWidget);
    await save(tester);
    expect(find.text('Nome já utilizado.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Marina Nova'), findsOneWidget);
    await save(tester);
    expect(requests, 2);
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  testWidgets(
    'device photo data uri previews avatar and is sent on save',
    (tester) async {
      const dataUri =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      Map<String, dynamic>? payload;
      await open(
        tester,
        onPatch: (request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(profileData), 200);
        },
      );
      await tester.tap(find.text('Alterar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link da foto'),
        dataUri,
      );
      await tester.pumpAndSettle();
      final avatar = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar),
      );
      expect(avatar.foregroundImage, isNotNull);
      await save(tester);
      expect(payload!['photo_url'], dataUri);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unreachable photo link warns instead of failing silently',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Alterar foto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link da foto'),
        'https://example.com/missing-photo.png',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Não foi possível carregar esta imagem'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
      await openConta(tester);
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
      await tester.tap(find.byKey(const Key('settings-tab-seguranca')));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const Key('settings-tab-seguranca')));
      await tester.pumpAndSettle();
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
      await openConta(tester);
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

  testWidgets('delete account asks twice and logs out', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var deletes = 0;
    final client = MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path == '/users/me') {
        deletes++;
        return http.Response('', 204);
      }
      expect(request.method, 'PATCH');
      return http.Response(jsonEncode(profileData), 200);
    });
    final api = ApiClient(client: client);
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

    await tester.tap(find.byKey(const Key('settings-tab-seguranca')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();

    // Diálogo estilo Meta: consequências + ciência explícita.
    expect(find.text('Excluir conta?'), findsOneWidget);
    expect(
      find.text('Entendo que esta ação não pode ser desfeita.'),
      findsOneWidget,
    );
    // Sem ciência, o botão final fica desabilitado.
    final confirm = find.widgetWithText(FilledButton, 'Excluir conta');
    expect(tester.widget<FilledButton>(confirm).enabled, isFalse);

    await tester.tap(
      find.text('Entendo que esta ação não pode ser desfeita.'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).enabled, isTrue);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(deletes, 1);
    // Sessão encerrada: voltou à tela anterior.
    expect(find.text('Abrir editor'), findsOneWidget);
    expect(state.status, AuthStatus.signedOut);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exportar dados compartilha o JSON', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var exports = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/users/me/export') {
        exports++;
        return http.Response(
          jsonEncode({
            'account': {'email': 'marina@example.test'},
            'runs': [],
          }),
          200,
        );
      }
      expect(request.method, 'PATCH');
      return http.Response(jsonEncode(profileData), 200);
    });
    final api = ApiClient(client: client);
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

    await tester.tap(find.byKey(const Key('settings-tab-privacidade')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Baixar meus dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baixar meus dados'));
    // Sem pumpAndSettle: o spinner de envio gira até o share responder.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(exports, 1);
    expect(tester.takeException(), isNull);
  });

  Future<AppState> openGallery(
    WidgetTester tester, {
    List<String> owned = const [],
    String? equipped,
    int balance = 1000,
    bool poor = false,
    required List calls,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var ownedNow = List.of(owned);
    var equippedNow = equipped;
    Map<String, dynamic> inventory() => {
      'owned': ownedNow,
      'equipped_avatar': equippedNow,
      'equipped_frame': null,
      'equipped_effect': null,
      'equipped_banner': null,
      'equipped_name_style': null,
      'equipped_emoticons': <String>[],
    };
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/shop/catalog') {
        // A "Escolha um avatar" é a loja pessoal: emblema da equipe e item do
        // Passe não se compram com a carteira do jogador.
        expect(request.url.queryParameters['scope'], 'user');
        return http.Response(
          jsonEncode([
            {
              'id': 'avatar_corredor',
              'category': 'avatar',
              'name': 'Corredor',
              'price': 50,
              // O catálogo real não tem mais PNG próprio: o rosto vem da API
              // de avatares e a `seed` é o id, para a loja e o perfil desenharem
              // a mesma figura.
              'payload': {
                'generated': 'adventurer',
                'seed': 'avatar_corredor',
                'animated': false,
                'tier': 1,
              },
            },
            {
              'id': 'avatar_gerado_adventurer',
              'category': 'avatar',
              'name': 'Gerado aventureiro',
              'price': 250,
              'payload': {
                'generated': 'adventurer',
                'seed': 'avatar_gerado_adventurer',
                'animated': false,
                'tier': 2,
              },
            },
          ]),
          200,
        );
      }
      if (request.method == 'GET' && path == '/shop/inventory') {
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (request.method == 'GET' && path == '/shop/wallet') {
        return http.Response(
          jsonEncode({'balance': balance, 'transactions': []}),
          200,
        );
      }
      if (request.method == 'POST' && path == '/shop/purchase') {
        final itemId = jsonDecode(request.body)['item_id'];
        calls.add(('purchase', itemId));
        if (poor) {
          return http.Response(
            jsonEncode({'detail': 'Dracmas insuficientes.'}),
            402,
          );
        }
        if (!ownedNow.contains(itemId)) ownedNow.add(itemId);
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (request.method == 'POST' && path == '/shop/equip') {
        final body = jsonDecode(request.body);
        calls.add(('equip', body['item_id']));
        equippedNow = body['item_id'];
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (path == '/users/me') {
        return http.Response(jsonEncode(profileData), 200);
      }
      return http.Response('{}', 404);
    });
    final api = ApiClient(client: client);
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
    await tester.tap(find.text('Avatares'));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('avatar gallery buys and equips through the shop', (
    tester,
  ) async {
    final calls = [];
    await openGallery(tester, calls: calls);
    expect(find.text('Escolha um avatar'), findsOneWidget);
    expect(find.text('Galeria'), findsOneWidget);
    expect(find.text('Gerados'), findsOneWidget);
    expect(
      find.byKey(const Key('preset-avatar-Corredor')),
      findsOneWidget,
    );
    expect(find.text('50 🪙'), findsOneWidget);

    // O rosto é o do item (seed = id), não o de quem está escolhendo: a folha,
    // a vitrine e o perfil de quem equipou desenham a mesma figura.
    final faces = tester
        .widgetList<Image>(find.byType(Image))
        .map((tile) => tile.image)
        .whereType<NetworkImage>()
        .map((image) => image.url)
        .toList();
    expect(
      faces,
      containsAll(<String>[
        'https://api.dicebear.com/7.x/adventurer/png?seed=avatar_corredor',
        'https://api.dicebear.com/7.x/adventurer/png'
            '?seed=avatar_gerado_adventurer',
      ]),
    );

    await tester.tap(find.byKey(const Key('preset-avatar-Corredor')));
    await tester.pumpAndSettle();
    expect(calls, [('purchase', 'avatar_corredor'), ('equip', 'avatar_corredor')]);
    expect(find.text('Escolha um avatar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owned avatar equips without repurchase', (tester) async {
    final calls = [];
    await openGallery(
      tester,
      owned: ['avatar_corredor'],
      calls: calls,
    );
    expect(find.text('Meu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset-avatar-Corredor')));
    await tester.pumpAndSettle();
    expect(calls, [('equip', 'avatar_corredor')]);
    expect(find.text('Escolha um avatar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('insufficient coins keep the gallery open with a warning', (
    tester,
  ) async {
    final calls = [];
    await openGallery(tester, poor: true, calls: calls);

    await tester.tap(find.byKey(const Key('preset-avatar-Corredor')));
    await tester.pumpAndSettle();
    expect(calls, [('purchase', 'avatar_corredor')]);
    expect(find.text('Dracmas insuficientes.'), findsOneWidget);
    expect(find.text('Escolha um avatar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
