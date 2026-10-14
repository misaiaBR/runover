import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/team_shop_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/cosmetics.dart';

import 'profile_screen_test.dart' show profileData;

Map<String, dynamic> teamData({bool admin = true}) => {
  'id': 'team-test',
  'name': 'Equipe Teste',
  'photo_url': null,
  'creator_username': 'marina',
  'member_count': 2,
  'territories_count': 1,
  'created_at': '2020-06-06T12:00:00Z',
  'members': [
    {'username': 'marina', 'photo_url': null, 'is_admin': true},
    {'username': 'rival', 'photo_url': null, 'is_admin': false},
  ],
  'total_score': 9000,
  'level': 3,
  'level_progress': 0.5,
  'points_to_next_level': 200,
  'zone_capacity': 37,
  'is_owner': true,
  'is_admin': admin,
  'my_request': null,
  'pending_requests': [],
  'online_count': 1,
  'team_balance': 4000,
  'team_spent': 5000,
  'equipped_avatar': null,
  'equipped_frame': null,
  'equipped_effect': null,
  'equipped_banner': null,
  'equipped_name_style': null,
};

/// Catálogo da loja da equipe que o `MockClient` devolve. `extra` entra no fim
/// da lista: os índices que os outros casos usam continuam os mesmos.
List<Map<String, dynamic>> teamCatalogData({
  List<Map<String, dynamic>> extra = const [],
}) => [
  {
    'id': 'team_frame_ferro',
    'category': 'frame',
    'name': 'Moldura ferro da equipe',
    'price': 5000,
    'scope': 'team',
    'payload': {
      'colors': ['#57534E'],
      'animated': false,
    },
  },
  {
    'id': 'team_banner_bau',
    'category': 'banner',
    'name': 'Faixa baú da equipe',
    'price': 6000,
    'scope': 'team',
    'payload': {
      'colors': ['#92400E', '#F59E0B'],
    },
  },
  ...extra,
];

Map<String, dynamic> teamInventoryData({
  List<String> owned = const [],
  String? frame,
}) => {
  'owned': owned,
  'equipped_avatar': null,
  'equipped_frame': frame,
  'equipped_effect': null,
  'equipped_banner': null,
  'equipped_name_style': null,
};

void main() {
  test('team models parseiam cofre, inventário e escopo', () {
    final wallet = TeamWallet.fromJson({
      'balance': 4000,
      'spent_points': 5000,
      'members_points': 9000,
    });
    expect(wallet.balance, 4000);
    expect(wallet.spentPoints, 5000);
    expect(wallet.membersPoints, 9000);

    final inventory = TeamInventory.fromJson(
      teamInventoryData(owned: ['team_frame_ferro'], frame: 'team_frame_ferro'),
    );
    expect(inventory.owned, ['team_frame_ferro']);
    final item = ShopItem.fromJson(teamCatalogData()[0]);
    expect(item.scope, 'team');
    expect(inventory.isEquipped(item), isTrue);

    // Compatível com respostas antigas sem os campos novos.
    final legacy = TeamDetail.fromJson({
      ...teamData(),
      'team_balance': null,
      'equipped_frame': null,
    }..remove('team_spent'));
    expect(legacy.teamBalance, 0);
    expect(legacy.teamSpent, 0);
    expect(legacy.equippedFrame, isNull);

    // Escopo padrão é pessoal.
    final userItem = ShopItem.fromJson({
      'id': 'frame_bronze',
      'category': 'frame',
      'name': 'Moldura bronze',
      'price': 100,
      'payload': {},
    });
    expect(userItem.scope, 'user');
  });

  /// Avança quadros sem esperar o fim das animações em loop da vitrine.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<List> openTeamShop(
    WidgetTester tester, {
    bool admin = true,
    List<String> owned = const [],
    String? equippedFrame,
    List<Map<String, dynamic>> extra = const [],
  }) async {
    final calls = [];
    var ownedNow = List.of(owned);
    var equippedNow = equippedFrame;
    final api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/teams/team-test') {
          return http.Response(jsonEncode(teamData(admin: admin)), 200);
        }
        if (request.method == 'GET' &&
            path == '/teams/team-test/wallet') {
          return http.Response(
            jsonEncode({
              'balance': 10000,
              'spent_points': 5000,
              'members_points': 15000,
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            path == '/teams/team-test/inventory') {
          return http.Response(
            jsonEncode(
              teamInventoryData(owned: ownedNow, frame: equippedNow),
            ),
            200,
          );
        }
        if (request.method == 'GET' && path == '/shop/catalog') {
          expect(request.url.queryParameters['scope'], 'team');
          return http.Response(
            jsonEncode(teamCatalogData(extra: extra)),
            200,
          );
        }
        if (request.method == 'POST' &&
            path == '/teams/team-test/purchase') {
          final itemId = jsonDecode(request.body)['item_id'];
          calls.add(('purchase', itemId));
          if (!ownedNow.contains(itemId)) ownedNow.add(itemId);
          return http.Response(
            jsonEncode(
              teamInventoryData(owned: ownedNow, frame: equippedNow),
            ),
            200,
          );
        }
        if (request.method == 'POST' &&
            path == '/teams/team-test/equip') {
          final body = jsonDecode(request.body);
          calls.add(('equip', body['category'], body['item_id']));
          equippedNow = body['item_id'];
          return http.Response(
            jsonEncode(
              teamInventoryData(owned: ownedNow, frame: equippedNow),
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileData);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const TeamShopScreen(teamId: 'team-test'),
        ),
      ),
    );
    await settle(tester);
    return calls;
  }

  testWidgets('admin vê cofre, compra e equipa item da equipe', (
    tester,
  ) async {
    final calls = await openTeamShop(tester);
    expect(find.text('Loja da equipe'), findsOneWidget);
    expect(find.text('10.000'), findsOneWidget);
    expect(find.text('Moldura ferro da equipe'), findsOneWidget);
    expect(find.text('Faixa baú da equipe'), findsOneWidget);

    await tester.tap(find.text('5.000').first);
    await settle(tester);
    expect(calls, [('purchase', 'team_frame_ferro')]);
    expect(find.text('Equipar'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não-admin vê aviso e não compra', (tester) async {
    await openTeamShop(tester, admin: false);
    expect(
      find.text('Só o dono ou admins compram e equipam.'),
      findsOneWidget,
    );
    await tester.tap(find.text('5.000').first);
    await settle(tester);
    expect(
      find.text('Só o dono ou admins compram para a equipe.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // A ficha de detalhes do pacote é a outra boca do "Inclui": um `grants` que a
  // loja da equipe não conhece fica de fora em vez de virar id na tela.
  testWidgets('a ficha do pacote da equipe não mostra id interno', (
    tester,
  ) async {
    // A dobra de teste é curta e a lista é preguiçosa: linha do pacote só
    // existe com janela alta.
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openTeamShop(
      tester,
      extra: [
        {
          'id': 'team_bundle_cofre',
          'category': 'bundle',
          'name': 'Cofre da equipe',
          'price': 12000,
          'scope': 'team',
          'payload': {
            'animated': false,
            'grants': ['team_frame_ferro', 'avatar_galeria_001'],
          },
        },
      ],
    );

    await tester.tap(find.text('Cofre da equipe'));
    await settle(tester);

    expect(find.text('Inclui'), findsOneWidget);
    // Uma linha na vitrine, outra dentro da ficha.
    expect(find.text('Moldura ferro da equipe'), findsNWidgets(2));
    expect(find.textContaining('avatar_galeria_001'), findsNothing);
    expect(find.textContaining('team_frame_ferro'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vitrine animada renderiza sem travar', (tester) async {
    final animated = ShopItem.fromJson({
      'id': 'frame_ouro',
      'category': 'frame',
      'name': 'Moldura ouro',
      'price': 500,
      'payload': {
        'colors': ['#FFC93C', '#FF7F4D'],
        'animated': true,
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Column(
            children: [
              FramedAvatar(radius: 24, frame: animated),
              const Breathe(seed: 'frame_ouro', child: Text('Nome')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Nome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
