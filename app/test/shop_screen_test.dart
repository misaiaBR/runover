import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/shop_screen.dart';
import 'package:runover_app/screens/wallet_history_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/offer_row.dart';
import 'package:runover_app/widgets/runover_ui.dart';

import 'profile_screen_test.dart' show profileData;

MockClient _shopClient(
  List<Map<String, dynamic>> catalog, {
  int balance = 9999,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/shop/catalog') {
      // O servidor devolve só o escopo pedido. Sem este filtro o teste não
      // enxerga vazamento: a tela que pede o catálogo inteiro recebe tudo.
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
          'balance': balance,
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
  int balance = 9999,
}) async {
  final api = ApiClient(client: _shopClient(catalog, balance: balance));
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
  // A vitrine tem brilho animado em loop: drena o primeiro frame sem
  // esperar o loop terminar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Map<String, dynamic> _avatar(String id, String name, int price) => {
      'id': id,
      'category': 'avatar',
      'name': name,
      'price': price,
      // Rosto vem da API de avatares com a seed do próprio item.
      'payload': {
        'generated': 'adventurer',
        'seed': id,
        'animated': false,
        'tier': 1,
      },
    };

void main() {
  testWidgets(
    'o cabeçalho tem o saldo e o cartão de boas-vindas abre as duas '
    'portas da carteira',
    (tester) async {
      await _pumpShop(tester, []);

      expect(find.text('Mercado'), findsOneWidget);
      expect(find.text('9.999'), findsOneWidget);
      expect(find.text('BEM-VINDO AO MERCADO'), findsOneWidget);
      expect(find.text('Como ganhar'), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a barra em gradiente ocupa o cabeçalho', (tester) async {
    await _pumpShop(tester, []);

    // É `Container` e não `DecoratedBox` de propósito: sem filho, o segundo
    // encolhe a zero e o cabeçalho fica sem gradiente nenhum.
    final bar = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).gradient == RGrad.header,
    );
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).height, greaterThan(0));
  });

  testWidgets('Histórico abre o extrato de dracmas', (tester) async {
    await _pumpShop(tester, []);
    await tester.tap(find.text('Histórico'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WalletHistoryScreen), findsOneWidget);
    expect(find.text('Histórico de dracmas'), findsOneWidget);
  });

  testWidgets('a folha "Como ganhar" mostra as taxas que vêm do servidor', (
    tester,
  ) async {
    await _pumpShop(tester, []);
    await tester.tap(find.text('Como ganhar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Distância percorrida'), findsOneWidget);
    expect(find.text('+10 por km'), findsOneWidget);
    expect(find.text('Conquista de território'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Primeira corrida do dia'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('Sequência de dias'), findsOneWidget);
    expect(find.text('+5 por dia, até 35'), findsOneWidget);
  });

  testWidgets('em janela larga os produtos viram cards de grade', (tester) async {
    await _pumpShop(tester, [
      _avatar('avatar_corredor', 'Corredor', 50),
      _avatar('avatar_raio', 'Raio animado', 400),
    ]);

    expect(find.byType(OfferCard), findsNWidgets(2));
    expect(find.byType(OfferRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // O cartão é a cor da raridade, então a raridade tem de estar escrita nele;
  // e com saldo curto ele diz a falta em vez de deixar descobrir no toque.
  testWidgets('o card da grade diz a raridade e quanto falta para o preço', (
    tester,
  ) async {
    await _pumpShop(
      tester,
      [
        _avatar('avatar_corredor', 'Corredor', 50),
        _avatar('avatar_raio', 'Raio animado', 400),
      ],
      balance: 300,
    );

    expect(find.text('COMUM'), findsOneWidget);
    expect(find.text('RARO'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(find.text('Faltam 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('em janela estreita os produtos seguem em fileiras', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpShop(tester, [
      _avatar('avatar_corredor', 'Corredor', 50),
      _avatar('avatar_raio', 'Raio animado', 400),
    ]);

    expect(find.byType(OfferRow), findsNWidgets(2));
    expect(find.byType(OfferCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fonte ampliada não corta o conteúdo do card', (tester) async {
    // Scale por plataforma: não existe setter de textScaler na view de teste.
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    // Janela alta o bastante para a grade (que é lazy) entrar na área útil.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // O scale test value não sai do `view.reset`: sem isto ele vaza para os
    // testes seguintes do arquivo e a grade lazy para de construir o card que
    // eles procuram.
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpShop(tester, [
      {
        'id': 'bundle_grande',
        'category': 'bundle',
        'name': 'Pacote campeão das arenas noturnas do inverno',
        'price': 900,
        'payload': {'animated': true},
      },
    ]);

    // O preço aparece na faixa de destaque e no card da grade.
    expect(find.text('900'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  // São três lojas numa API só: pessoal, equipe e Passe. A vitrine do Mercado é
  // a pessoal — item das outras aparece, o toque chega no servidor e a compra
  // recusa. O filtro é o escopo da requisição, não a categoria do item.
  testWidgets('o Mercado só oferece a loja pessoal', (tester) async {
    await _pumpShop(tester, [
      _avatar('avatar_corredor', 'Corredor', 50),
      {
        ..._avatar('avatar_bandeira', 'Bandeira da equipe', 900),
        'scope': 'team',
      },
      {
        ..._avatar('avatar_heroi', 'Herói da temporada', 1200),
        'scope': 'pass',
      },
    ]);

    expect(find.text('Corredor'), findsWidgets);
    expect(find.text('Bandeira da equipe'), findsNothing);
    expect(find.text('Herói da temporada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // O "Inclui:" do pacote resolve cada `grants` no catálogo. Um id que a loja
  // pessoal não conhece fica de fora: id interno não se mostra na interface.
  testWidgets('pacote não mostra id interno de item fora da loja', (
    tester,
  ) async {
    await _pumpShop(tester, [
      _avatar('avatar_corredor', 'Corredor', 50),
      {
        'id': 'bundle_pacote',
        'category': 'bundle',
        'name': 'Pacote do corredor',
        'price': 300,
        'payload': {
          'animated': true,
          'grants': ['avatar_corredor', 'team_avatar_bandeira'],
        },
      },
    ]);

    expect(find.textContaining('Inclui: Corredor'), findsWidgets);
    expect(find.textContaining('team_avatar_bandeira'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A ficha de detalhes é a segunda boca do mesmo pacote: ela montava a lista
  // "Inclui" direto do payload e, sem match no catálogo, despejava o id cru na
  // tela. Passa pela resolução compartilhada, então o que não tem nome não tem
  // linha.
  testWidgets('a ficha do pacote não mostra id interno na lista "Inclui"', (
    tester,
  ) async {
    await _pumpShop(tester, [
      _avatar('avatar_corredor', 'Corredor', 50),
      {
        'id': 'bundle_pacote',
        'category': 'bundle',
        'name': 'Pacote do corredor',
        'price': 300,
        'payload': {
          'animated': true,
          'grants': ['avatar_corredor', 'team_avatar_bandeira'],
        },
      },
    ]);

    final card = find.byWidgetPredicate(
      (widget) => widget is OfferCard && widget.item.id == 'bundle_pacote',
    );
    // A grade é lazy e a dobra de teste tem 600 px: sem trazer o card para
    // dentro, o toque cai no vazio e a ficha nunca abre.
    await tester.ensureVisible(card);
    await tester.pump();
    // 'Corredor' já é card na vitrine; a linha da ficha é um a mais.
    final naVitrine = find.text('Corredor').evaluate().length;
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A ficha abriu e a seção existe.
    expect(find.byType(BottomSheet), findsOneWidget);
    // O título da seção só existe na ficha.
    expect(find.text('Inclui'), findsOneWidget);
    expect(find.text('Corredor'), findsNWidgets(naVitrine + 1));
    expect(find.textContaining('team_avatar_bandeira'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('grantNames resolve só o que o catálogo conhece', () {
    final catalog = [
      ShopItem.fromJson(_avatar('avatar_corredor', 'Corredor', 50)),
    ];
    ShopItem pacote(List<String> grants) => ShopItem.fromJson({
      'id': 'bundle_pacote',
      'category': 'bundle',
      'name': 'Pacote do corredor',
      'price': 300,
      'payload': {'grants': grants},
    });

    expect(grantNames(pacote(['avatar_corredor']), catalog), ['Corredor']);
    // Na ordem do payload, pulando o que não resolve.
    expect(
      grantNames(pacote(['avatar_corredor', 'team_avatar_bandeira']), catalog),
      ['Corredor'],
    );
    expect(grantNames(pacote(['team_avatar_bandeira']), catalog), isEmpty);
    // Item que não é pacote não tem presentes.
    expect(grantNames(catalog.first, catalog), isEmpty);
  });
}
