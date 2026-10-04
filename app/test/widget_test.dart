import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runover_app/screens/login_screen.dart';
import 'package:runover_app/screens/profile_screen.dart';
import 'package:runover_app/screens/register_screen.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

void main() {
  testWidgets('a tela de login mostra a marca e os acessos de entrada/cadastro',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(theme: buildRunoverTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
    expect(find.text('Esqueceu a senha?'), findsOneWidget);
    expect(find.text('Domine territórios correndo.'), findsOneWidget);

    await tester.ensureVisible(find.text('Criar conta'));
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  test('RF19 — tempo de jogo é formatado em horas e minutos', () {
    expect(ProfileScreen.formatPlaytime(0), '0min');
    expect(ProfileScreen.formatPlaytime(90), '1min');
    expect(ProfileScreen.formatPlaytime(3600), '1h');
    expect(ProfileScreen.formatPlaytime(3600 + 25 * 60), '1h 25min');
  });
}
