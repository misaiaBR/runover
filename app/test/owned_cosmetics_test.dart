import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/widgets/owned_cosmetics.dart';

const _catalog = [
  {
    'id': 'frame_neon',
    'category': 'frame',
    'name': 'Moldura neon',
    'price': 120,
    'scope': 'user',
    'payload': <String, dynamic>{},
  },
  {
    'id': 'frame_gold',
    'category': 'frame',
    'name': 'Moldura ouro',
    'price': 300,
    'scope': 'user',
    'payload': <String, dynamic>{},
  },
  {
    'id': 'banner_sol',
    'category': 'banner',
    'name': 'Banner sol',
    'price': 200,
    'scope': 'user',
    'payload': <String, dynamic>{},
  },
];

Map<String, dynamic> _inventory({String? frame}) => {
  'owned': ['frame_neon', 'banner_sol'],
  'equipped_frame': frame,
};

Future<List<Map<String, dynamic>>> openPanel(
  WidgetTester tester, {
  String? equippedFrame,
  List<String>? refreshes,
}) async {
  final equips = <Map<String, dynamic>>[];
  var frameNow = equippedFrame;
  final api = ApiClient(
    client: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/shop/catalog') {
        return http.Response(jsonEncode(_catalog), 200);
      }
      if (request.method == 'GET' && path == '/shop/inventory') {
        return http.Response(jsonEncode(_inventory(frame: frameNow)), 200);
      }
      if (request.method == 'POST' && path == '/shop/equip') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        equips.add(body);
        frameNow = body['item_id'] as String?;
        return http.Response(jsonEncode(_inventory(frame: frameNow)), 200);
      }
      return http.Response('{}', 404);
    }),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OwnedCosmeticsPanel(
            api: api,
            onChanged: () async => refreshes?.add('perfil'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return equips;
}

void main() {
  testWidgets('lista só o que o usuário já comprou', (tester) async {
    await openPanel(tester);

    expect(find.text('Moldura neon'), findsOneWidget);
    expect(find.text('Banner sol'), findsOneWidget);
    // Comprado não é catálogo inteiro: o que ele não pagou fica de fora.
    expect(find.text('Moldura ouro'), findsNothing);
    // Nenhuma categoria sem item comprado aparece.
    expect(find.text('Emoticons'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar equipa a categoria certa e recarrega o inventário', (
    tester,
  ) async {
    final refreshes = <String>[];
    final equips = await openPanel(tester, refreshes: refreshes);

    await tester.tap(find.text('Moldura neon'));
    await tester.pumpAndSettle();

    expect(equips, [
      {'category': 'frame', 'item_id': 'frame_neon'},
    ]);
    expect(refreshes, ['perfil']);
    // O chip passa a selecionado e oferece o "Nenhum" para tirar.
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Moldura neon'))
          .selected,
      isTrue,
    );
    expect(find.text('Nenhum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Nenhum" desequipa mandando item_id nulo', (tester) async {
    final equips = await openPanel(tester, equippedFrame: 'frame_neon');

    expect(find.text('Nenhum'), findsOneWidget);
    await tester.tap(find.text('Nenhum'));
    await tester.pumpAndSettle();

    expect(equips.last, {'category': 'frame', 'item_id': null});
    expect(find.text('Nenhum'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
