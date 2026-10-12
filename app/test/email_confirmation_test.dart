import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/screens/email_confirmation_screen.dart';
import 'package:runover_app/screens/login_screen.dart';
import 'package:runover_app/screens/register_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_screen_test.dart' show profileData;

/// O portão do cadastro: a conta existe, mas o aplicativo só abre com o código
/// que chegou no e-mail. Nenhum teste aqui espera caixa de correio — o MockClient
/// devolve exatamente o que a API devolve.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<AppState> openGate(
    WidgetTester tester,
    List<String> calls, {
    required Future<http.Response> Function(String path, String body) reply,
    Widget? home,
    String email = 'novo@example.com',
    int? expiresInMinutes,
    int? resendAfterSeconds,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        calls.add(request.url.path);
        return reply(request.url.path, request.body);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home:
              home ??
              EmailConfirmationScreen(
                email: email,
                expiresInMinutes: expiresInMinutes,
                resendAfterSeconds: resendAfterSeconds,
              ),
        ),
      ),
    );
    return state;
  }

  http.Response json(Object? body, int status) =>
      http.Response(jsonEncode(body), status);

  /// Quantos segundos faltam no botão de reenvio, lidos da própria tela.
  int resendCountdown(WidgetTester tester) {
    final label =
        tester.widget<Text>(find.textContaining('Reenviar código em')).data!;
    return int.parse(RegExp(r'(\d+)s').firstMatch(label)!.group(1)!);
  }

  testWidgets('a tela mostra o e-mail e a espera que o servidor mandou', (
    tester,
  ) async {
    await openGate(
      tester,
      [],
      reply: (_, _) async => json({}, 404),
      expiresInMinutes: 30,
      resendAfterSeconds: 90,
    );
    await tester.pump();

    expect(find.textContaining('novo@example.com'), findsOneWidget);
    expect(find.textContaining('30 minutos'), findsOneWidget);
    // A contagem começa no número do servidor e desce segundo a segundo.
    expect(find.text('Reenviar código em 90s'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reenviar código em 89s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Reenviar código em 87s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem os tempos do servidor a tela não inventa contagem', (
    tester,
  ) async {
    await openGate(tester, [], reply: (_, _) async => json({}, 404));
    await settle(tester);

    expect(find.textContaining('expira em'), findsNothing);
    expect(find.text('Reenviar código'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('o código troca por sessão e fecha o portão', (tester) async {
    final calls = <String>[];
    final state = await openGate(
      tester,
      calls,
      home: const Scaffold(body: Center(child: Text('primeira rota'))),
      reply: (path, body) async {
        if (path == '/auth/verify-email') {
          expect(
            jsonDecode(body),
            {'email': 'novo@example.com', 'code': '123456789012'},
          );
          return json({'access_token': 'token-novo', 'token_type': 'bearer'}, 200);
        }
        if (path == '/users/me') return json(profileData, 200);
        return json({}, 404);
      },
    );
    await settle(tester);
    // O portão é sempre empurrado por cima da primeira rota.
    Navigator.of(tester.element(find.text('primeira rota'))).push(
      MaterialPageRoute(
        builder: (_) =>
            const EmailConfirmationScreen(email: 'novo@example.com'),
      ),
    );
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Código recebido por e-mail'),
      '123456789012',
    );
    await tester.tap(find.text('Entrar'));
    await settle(tester);

    expect(calls, contains('/auth/verify-email'));
    expect(state.status, AuthStatus.signedIn);
    expect(state.profile?.username, 'marina');
    expect(state.api.isAuthenticated, isTrue);
    // Sem tela por cima: quem deriva a rota do estado vê o aplicativo.
    expect(find.byType(EmailConfirmationScreen), findsNothing);
    expect(find.text('primeira rota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('código errado fica na tela com a frase do servidor', (
    tester,
  ) async {
    final calls = <String>[];
    final state = await openGate(
      tester,
      calls,
      resendAfterSeconds: 60,
      reply: (path, _) async {
        if (path == '/auth/verify-email') {
          return json({'detail': 'Código inválido, expirado ou já utilizado.'}, 400);
        }
        return json({}, 404);
      },
    );

    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Código recebido por e-mail'),
      '000000000000',
    );
    await tester.tap(find.text('Entrar'));
    await settle(tester);

    expect(find.text('Código inválido, expirado ou já utilizado.'), findsOneWidget);
    expect(find.byType(EmailConfirmationScreen), findsOneWidget);
    expect(state.status, isNot(AuthStatus.signedIn));
    expect(state.api.isAuthenticated, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reenviar usa a espera que o servidor respondeu', (
    tester,
  ) async {
    final calls = <String>[];
    await openGate(
      tester,
      calls,
      reply: (path, _) async {
        if (path == '/auth/resend-verification') {
          return json({
            'message': 'Se esse e-mail estiver cadastrado, enviaremos um novo código.',
            'resend_after_seconds': 45,
          }, 200);
        }
        return json({}, 404);
      },
    );

    await settle(tester);
    await tester.tap(find.text('Reenviar código'));
    await settle(tester);

    expect(calls, contains('/auth/resend-verification'));
    expect(
      find.text('Se esse e-mail estiver cadastrado, enviaremos um novo código.'),
      findsOneWidget,
    );
    // A contagem recomeça do número que o servidor acabou de responder.
    expect(resendCountdown(tester), inInclusiveRange(43, 45));
    expect(find.text('Reenviar código'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login barrado pelo portão abre a tela do código, não reativar', (
    tester,
  ) async {
    final calls = <String>[];
    final state = await openGate(
      tester,
      calls,
      home: const LoginScreen(),
      reply: (path, _) async {
        if (path == '/auth/login') {
          return json({
            'detail': {
              'message': 'Confirme seu e-mail para entrar.',
              'code': 'email_verification_required',
            },
          }, 403);
        }
        return json({}, 404);
      },
    );
    await settle(tester);
    // Transiente de primeiro frame da tela de login (pré-existente).
    tester.takeException();

    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'),
      'novo@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'original123');
    await tester.tap(find.text('Entrar'));
    await settle(tester);

    expect(find.byType(EmailConfirmationScreen), findsOneWidget);
    expect(find.text('Reativar conta?'), findsNothing);
    expect(find.text('Confirme seu e-mail para entrar.'), findsNothing);
    expect(state.status, isNot(AuthStatus.signedIn));
    expect(state.api.isAuthenticated, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conta desativada continua oferecendo reativar', (tester) async {
    final calls = <String>[];
    await openGate(
      tester,
      calls,
      home: const LoginScreen(),
      reply: (path, _) async {
        if (path == '/auth/login') {
          return json({
            'detail': 'Esta conta está desativada. Reative-a para continuar.',
          }, 403);
        }
        return json({}, 404);
      },
    );
    await settle(tester);
    tester.takeException();

    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'),
      'marina@example.test',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Senha'), 'original123');
    await tester.tap(find.text('Entrar'));
    await settle(tester);

    expect(find.text('Reativar conta?'), findsOneWidget);
    expect(find.byType(EmailConfirmationScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o cadastro leva para o portão em vez de entrar', (
    tester,
  ) async {
    final calls = <String>[];
    final state = await openGate(
      tester,
      calls,
      home: const RegisterScreen(),
      reply: (path, _) async {
        if (path == '/auth/register') {
          return json({
            'email': 'novo@example.com',
            'expires_in_minutes': 30,
            'resend_after_seconds': 60,
            'message': 'Conta criada.',
            'requires_verification': true,
            'debug_code': null,
          }, 201);
        }
        return json({}, 404);
      },
    );
    await settle(tester);
    tester.takeException();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome completo'),
      'Novo Corredor',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Nickname'), 'novo');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'novo@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'Corridas123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirme a senha'),
      'Corridas123',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await settle(tester);
    await tester.tap(find.text('Confirmar'));
    await settle(tester);

    expect(calls, contains('/auth/register'));
    expect(find.byType(EmailConfirmationScreen), findsOneWidget);
    // Nada de sessão antes do código: nem o app abre nem o token aparece.
    expect(state.status, isNot(AuthStatus.signedIn));
    expect(state.api.isAuthenticated, isFalse);
    expect(resendCountdown(tester), inInclusiveRange(58, 60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('backend antigo que devolve token entra direto', (tester) async {
    final calls = <String>[];
    final state = await openGate(
      tester,
      calls,
      home: const RegisterScreen(),
      reply: (path, _) async {
        if (path == '/auth/register') {
          return json({'access_token': 'token-antigo', 'token_type': 'bearer'}, 200);
        }
        if (path == '/users/me') return json(profileData, 200);
        return json({}, 404);
      },
    );
    await settle(tester);
    tester.takeException();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome completo'),
      'Novo Corredor',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Nickname'), 'novo');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'novo@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'Corridas123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirme a senha'),
      'Corridas123',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await settle(tester);
    await tester.tap(find.text('Confirmar'));
    await settle(tester);

    // Janela de implantação: o app sobe antes do backend e ainda funciona.
    expect(find.byType(EmailConfirmationScreen), findsNothing);
    expect(state.status, AuthStatus.signedIn);
    expect(tester.takeException(), isNull);
  });
}
