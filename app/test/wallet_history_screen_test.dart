import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/wallet_history_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

/// As taxas do `/wallet` como o servidor as devolve hoje.
const _rates = {
  'per_km': 10,
  'conquest': 50,
  'daily_first_run': 20,
  'streak_per_day': 5,
  'streak_cap': 35,
};

/// O instante no dia local do teste: a etiqueta do grupo (`Hoje`, `Ontem`)
/// depende do fuso da máquina, e um instante fixo em UTC cairia em outro dia.
String _ago({int days = 0, int hour = 9, int minute = 5}) {
  final now = DateTime.now().subtract(Duration(days: days));
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).toUtc().toIso8601String();
}

Map<String, dynamic> _entry({
  required int delta,
  required String reason,
  required String createdAt,
}) => {
  'delta': delta,
  'reason': reason,
  'created_at': createdAt,
};

/// O payload do `/shop/wallet`, mais recente primeiro (a ordem da rota).
Map<String, dynamic> _wallet({
  int balance = 4517,
  List<Map<String, dynamic>> transactions = const [],
  Map<String, dynamic>? rates,
}) => {
  'balance': balance,
  'transactions': transactions,
  'rates': rates ?? _rates,
};

const _catalogJson = [
  {
    'id': 'avatar_corredor',
    'category': 'avatar',
    'name': 'Corredor',
    'price': 50,
    'payload': {
      'generated': 'adventurer',
      'seed': 'avatar_corredor',
      'animated': false,
      'tier': 1,
    },
  },
];

Future<void> _open(
  WidgetTester tester, {
  Map<String, dynamic>? wallet,
  int failures = 0,
}) async {
  var calls = 0;
  final api = ApiClient(
    client: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/shop/catalog') {
        return http.Response(jsonEncode(_catalogJson), 200);
      }
      if (request.method == 'GET' && path == '/shop/wallet') {
        if (calls++ < failures) return http.Response('{}', 500);
        return http.Response(jsonEncode(wallet ?? _wallet()), 200);
      }
      return http.Response('{}', 404);
    }),
  );
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
        home: const WalletHistoryScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('walletReasonLabel', () {
    final catalog = [
      ShopItem.fromJson({
        'id': 'avatar_corredor',
        'category': 'avatar',
        'name': 'Corredor',
        'price': 50,
        'payload': {
      'generated': 'adventurer',
      'seed': 'avatar_corredor',
      'animated': false,
      'tier': 1,
    },
      }),
    ];

    test('compra resolve o nome do item pelo catálogo', () {
      expect(walletReasonLabel('compra:avatar_corredor', catalog), 'Corredor');
    });

    test('compra de item fora do catálogo nunca expõe o id', () {
      expect(
        walletReasonLabel('compra:name_estilo_067', catalog),
        'Compra no mercado',
      );
    });

    test('passe distingue compra de recompensa por tier', () {
      expect(walletReasonLabel('passe:s9', catalog), 'Compra do passe');
      expect(
        walletReasonLabel('passe:s9:t3:cosmetic', catalog),
        'Recompensa do passe · nível 3',
      );
    });

    test('motivos de ganho têm rótulo legível', () {
      expect(walletReasonLabel('distancia', catalog), 'Distância percorrida');
      expect(
        walletReasonLabel('conquista', catalog),
        'Conquista de território',
      );
      expect(walletReasonLabel('missao_diaria', catalog), 'Missão diária');
      expect(walletReasonLabel('streak', catalog), 'Sequência de dias');
    });

    test('motivo desconhecido cai no genérico, nunca na chave crua', () {
      expect(walletReasonLabel('futuro:motivo:x', catalog), 'Outro movimento');
    });
  });

  testWidgets('o extrato agrupa por dia e mostra o valor com sinal', (
    tester,
  ) async {
    await _open(
      tester,
      wallet: _wallet(
        transactions: [
          _entry(delta: 120, reason: 'distancia', createdAt: _ago(hour: 10)),
          _entry(
            delta: -50,
            reason: 'compra:avatar_corredor',
            createdAt: _ago(hour: 9),
          ),
          _entry(
            delta: 50,
            reason: 'conquista',
            createdAt: _ago(days: 1, hour: 18),
          ),
        ],
      ),
    );

    expect(find.text('4.517 dracmas'), findsOneWidget);
    // `SectionHeader` e `GameButton` desenham o rótulo em caixa alta.
    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('ONTEM'), findsOneWidget);
    expect(find.text('+120'), findsOneWidget);
    expect(find.text('−50'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Distância percorrida'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o extrato fala em dracmas e nunca mostra id interno', (
    tester,
  ) async {
    await _open(
      tester,
      wallet: _wallet(
        transactions: [
          // Registro legado malformado: sem delta numérico não é movimento
          // nenhum e não pode aparecer como linha quebrada na tela.
          <String, dynamic>{
            'delta': 'oops',
            'reason': 'distancia',
            'created_at': _ago(hour: 11),
          },
          _entry(
            delta: -1516,
            reason: 'compra:name_estilo_067',
            createdAt: _ago(hour: 9),
          ),
        ],
      ),
    );

    expect(find.textContaining('compra:'), findsNothing);
    expect(find.text('Compra no mercado'), findsOneWidget);
    expect(find.text('−1.516'), findsOneWidget);
    // A linha quebrada saiu do meio da lista, não do nada: sobra a válida.
    expect(find.text('Outro movimento'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem movimento a tela diz isso em vez de listar nada', (
    tester,
  ) async {
    await _open(tester, wallet: _wallet(balance: 0, transactions: const []));
    expect(find.text('Nenhum movimento ainda.'), findsOneWidget);
    expect(find.textContaining('Mostrando os'), findsNothing);
  });

  testWidgets('falha de leitura tem banner com o botão que refaz a chamada', (
    tester,
  ) async {
    await _open(tester, failures: 1);
    expect(find.text('Não foi possível carregar o extrato.'), findsOneWidget);
    await tester.tap(find.text('TENTAR DE NOVO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Não foi possível carregar o extrato.'), findsNothing);
    expect(find.text('Nenhum movimento ainda.'), findsOneWidget);
  });
}
