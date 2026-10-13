import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/shop_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/offer_row.dart';

import 'profile_screen_test.dart' show profileData;

/// O #120: nada sai cortado de dentro da caixa.
///
/// Os cards do Mercado têm altura e largura definidas por código (o carrossel
/// precisa de altura fixa para rolar na horizontal, e a grade usa
/// `mainAxisExtent`). Quando o conteúdo pede mais que a caixa, o `Clip` do
/// cartão come o que sobra sem avisar: botão, preço e selo somem no meio.
/// Cada teste abaixo mete o pior caso real de conteúdo na caixa e cobra que o
/// último pedaço — o botão, o 'Faltam' — caiba dentro da borda.

MockClient _client(List<Map<String, dynamic>> catalog) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/shop/catalog') {
      final scope = request.url.queryParameters['scope'];
      final items = scope == null
          ? catalog
          : catalog
                .where((item) => (item['scope'] ?? 'user') == scope)
                .toList();
      return http.Response(jsonEncode(items), 200);
    }
    if (request.method == 'GET' && path == '/shop/inventory') {
      return http.Response(
        jsonEncode({
          'owned': <String>[],
          'equipped_avatar': null,
          'equipped_frame': null,
          'equipped_effect': null,
          'equipped_banner': null,
          'equipped_name_style': null,
          'equipped_emoticons': <String>[],
        }),
        200,
      );
    }
    if (request.method == 'GET' && path == '/shop/wallet') {
      return http.Response(
        jsonEncode({
          'balance': 100,
          'transactions': <Map>[],
          'rates': {
            'per_km': 10,
            'conquest': 50,
            'daily_first_run': 20,
            'streak_per_day': 5,
            'streak_cap': 35,
          },
        }),
        200,
      );
    }
    return http.Response('{}', 404);
  });
}

Future<void> _pumpShop(
  WidgetTester tester,
  List<Map<String, dynamic>> catalog, {
  Size size = const Size(390, 1200),
  double scale = 1,
}) async {
  if (scale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(client: _client(catalog));
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
        home: const ShopScreen(),
      ),
    ),
  );
  // A vitrine e as prévias animam em loop: drena o primeiro frame sem
  // esperar o loop terminar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Rect _rect(WidgetTester tester, Finder finder) {
  final box = finder.evaluate().first.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// O que a caixa promete, ela entrega: nenhum dos conteúdos pedidos pode
/// passar da borda do cartão que o envolve.
void _expectInsideCard(
  WidgetTester tester, {
  required Finder card,
  required List<String> reasons,
}) {
  final box = _rect(tester, card);
  for (final reason in reasons) {
    final content = find.descendant(
      of: card,
      matching: find.text(reason),
    );
    expect(content, findsWidgets, reason: reason);
    final r = _rect(tester, content);
    expect(
      r.bottom,
      lessThanOrEqualTo(box.bottom + 0.5),
      reason: '"$reason" passou da borda de baixo do cartão',
    );
    expect(
      r.right,
      lessThanOrEqualTo(box.right + 0.5),
      reason: '"$reason" passou da borda direita do cartão',
    );
  }
  expect(tester.takeException(), isNull);
}

Map<String, dynamic> _item(
  String id,
  String category,
  String name,
  int price, {
  Map<String, Object>? payload,
}) => {
  'id': id,
  'category': category,
  'name': name,
  'price': price,
  'payload': {
    'generated': 'adventurer',
    'seed': id,
    'animated': true,
    'tier': 2,
    ...?payload,
  },
};

/// Pacote cheio: nome de duas linhas, três outorgas no subtítulo, preço e
/// botão — o cartão que apareceu cortado na tela dele.
Map<String, dynamic> _fullBundle({String? name, Map<String, Object>? payload})
=> {
  'id': 'bundle_equipe',
  'category': 'bundle',
  'name': name ?? 'Pacote da equipe relâmpago',
  'price': 80000,
  'payload': {
    'animated': true,
    'grants': ['avatar_corredor', 'frame_olimpico', 'effect_chuva'],
    ...?payload,
  },
};

List<Map<String, dynamic>> _grantable() => [
  _item('avatar_corredor', 'avatar', 'Corredor', 50),
  _item('frame_olimpico', 'frame', 'Moldura olímpica', 400),
  _item('effect_chuva', 'effect', 'Chuva dourada', 900),
];

void main() {
  testWidgets('o card em destaque caiba inteiro na tela do celular', (
    tester,
  ) async {
    await _pumpShop(tester, [..._grantable(), _fullBundle()]);

    // O card não é mais largura fixa: numa tela de 390 ele ocupa a banda e o
    // preço/botão não ficam do lado de fora da dobra.
    final card = find.ancestor(
      of: find.widgetWithText(FilledButton, 'Comprar'),
      matching: find.byType(Card),
    );
    expect(card, findsWidgets);
    expect(_rect(tester, card).width, greaterThan(300));
    _expectInsideCard(tester, card: card, reasons: ['Comprar', '80.000']);
  });

  testWidgets('fonte ampliada não corta o card em destaque', (tester) async {
    await _pumpShop(
      tester,
      [..._grantable(), _fullBundle()],
      scale: 1.6,
    );

    final card = find.ancestor(
      of: find.widgetWithText(FilledButton, 'Comprar'),
      matching: find.byType(Card),
    );
    expect(card, findsWidgets);
    _expectInsideCard(tester, card: card, reasons: ['Comprar', '80.000']);
  });

  testWidgets('o título da vitrine não estoura a largura da tela', (
    tester,
  ) async {
    await _pumpShop(
      tester,
      [..._grantable(), _fullBundle()],
      size: const Size(320, 1200),
      scale: 1.6,
    );

    expect(find.textContaining('Pacotes em'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o card da grade guarda selo, nome e falta dentro da caixa', (
    tester,
  ) async {
    await _pumpShop(
      tester,
      [
        ..._grantable(),
        _fullBundle(
          name: 'Pacote campeão das arenas noturnas do inverno',
          payload: {'collection': 'parceria'},
        ),
      ],
      size: const Size(1400, 1400),
      scale: 1.3,
    );

    final card = find.ancestor(
      of: find.text('Pacote campeão das arenas noturnas do inverno'),
      matching: find.byType(OfferCard),
    );
    expect(card, findsOneWidget);
    // Saldo 100 contra preço 80.000: a linha de falta é a última do cartão e
    // é ela que somia primeiro quando a caixa ficava curta.
    _expectInsideCard(tester, card: card, reasons: [
      'PARCERIA',
      'Faltam 79.900',
      '80.000',
    ]);
  });

  testWidgets('a fileira estreita não corta nome nem preço', (tester) async {
    await _pumpShop(tester, [
      ..._grantable(),
      _fullBundle(
        name: 'Pacote campeão das arenas noturnas do inverno',
        payload: {'collection': 'parceria'},
      ),
    ]);

    final row = find.ancestor(
      of: find.text('Pacote campeão das arenas noturnas do inverno'),
      matching: find.byType(OfferRow),
    );
    expect(row, findsOneWidget);
    _expectInsideCard(tester, card: row, reasons: [
      'Pacote campeão das arenas noturnas do inverno',
      '80.000',
    ]);
  });
}
