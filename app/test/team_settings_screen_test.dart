import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/team_settings_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

const _teamId = 'team-1';
const _teamPath = '/teams/$_teamId';

/// Emblemas da loja da equipe que o servidor devolve no escopo `team`. Só o
/// suficiente para a prévia achar o item equipado pelo id e desenhar o rosto da
/// API — payload `generated` + `seed`, como no catálogo real.
const teamEmblemCatalog = [
  {
    'id': 'team_avatar_estandarte',
    'category': 'avatar',
    'name': 'Estandarte da equipe',
    'price': 4000,
    'scope': 'team',
    'payload': {
      'generated': 'adventurer',
      'seed': 'team_avatar_estandarte',
      'tier': 2,
    },
  },
  {
    'id': 'team_avatar_coroa',
    'category': 'avatar',
    'name': 'Coroa da equipe',
    'price': 9000,
    'scope': 'team',
    'payload': {
      'generated': 'personas',
      'seed': 'team_avatar_coroa',
      'tier': 3,
    },
  },
];

/// JSON de `TeamDetail` com os padrões de uma equipe de três pessoas, onde
/// `marina` (o perfil do teste) é a dona.
Map<String, dynamic> teamSettingsJson({
  String name = 'RUNOVER',
  String? photoUrl,
  String? equippedAvatar,
  List<String> ownedEmblems = const [],
  bool owner = true,
  bool admin = true,
  int memberCount = 3,
  List<Map<String, dynamic>>? members,
  String joinMode = 'approval',
  bool listed = true,
  bool notifyRisk = true,
  bool notifyRequests = true,
  String? inviteToken,
  List<Map<String, dynamic>> requests = const [],
}) => {
  'id': _teamId,
  'name': name,
  'photo_url': photoUrl,
  'equipped_avatar': equippedAvatar,
  'owned_emblems': ownedEmblems,
  'creator_username': 'marina',
  'member_count': memberCount,
  'members':
      members ??
      [
        {'username': 'marina', 'photo_url': null},
        {'username': 'pedro', 'photo_url': null},
      ],
  'total_score': 320,
  'territories_count': 4,
  'level': 3,
  'level_progress': 0.4,
  'points_to_next_level': 120,
  'zone_capacity': 7,
  'is_owner': owner,
  'is_admin': admin,
  'pending_requests': requests,
  'join_mode': joinMode,
  'listed': listed,
  'notify_risk': notifyRisk,
  'notify_requests': notifyRequests,
  'invite_token': inviteToken,
};

class TeamSettingsCalls {
  final List<String> requests = [];

  /// Query string da última chamada do catálogo, para conferir o escopo pedido.
  String catalogQuery = '';
  Map<String, dynamic>? lastPatch;
  Map<String, dynamic>? lastLeave;
  Map<String, dynamic>? lastEquip;

  bool called(String verbAndPath) => requests.contains(verbAndPath);
}

/// Abre a tela de configurações contra um `MockClient` que registra as chamadas
/// e devolve a equipe informada (com o link de convite renovado quando o
/// servidor é chamado para regenerar). Atende também a Loja da equipe —
/// catálogo de avatares, cofre, inventário, compra e equipamento — porque a
/// tela lê o emblema equipado para desenhar a prévia.
///
/// `failOn` faz falhar com 409 a chamada cujo `MÉTODO /caminho` contém o texto.
/// `routed` abre a tela por dentro de um `Navigator`, como o painel faz: só
/// assim dá para ver se uma ação que falhou fechou a tela na mesma.
Future<TeamSettingsCalls> openTeamSettings(
  WidgetTester tester,
  Map<String, dynamic> teamJson, {
  String? failOn,
  bool routed = false,
  Size size = const Size(560, 2200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final calls = TeamSettingsCalls();
  // O que a equipe tem da loja: o inventário devolvido abaixo acompanha a última
  // compra/equipamento, que é exatamente o que a prévia da tela relê depois.
  final owned = <String>{
    for (final id in (teamJson['owned_emblems'] as List?) ?? const []) '$id',
  };
  String? equipped = teamJson['equipped_avatar'] as String?;
  Map<String, dynamic> inventory() => {
    'owned': owned.toList(),
    'equipped_avatar': equipped,
    'equipped_frame': null,
    'equipped_effect': null,
    'equipped_banner': null,
    'equipped_name_style': null,
  };
  final api = ApiClient(
    client: MockClient((request) async {
      final method = request.method;
      final path = request.url.path;
      calls.requests.add('$method $path');
      if (failOn != null && '$method $path'.contains(failOn)) {
        return http.Response(jsonEncode({'detail': 'Ação indisponível.'}), 409);
      }
      if (method == 'GET' && path == '/shop/catalog') {
        calls.catalogQuery = request.url.query;
        return http.Response(jsonEncode(teamEmblemCatalog), 200);
      }
      if (method == 'GET' && path == '$_teamPath/inventory') {
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (method == 'GET' && path == _teamPath) {
        // A Loja da equipe inteira, aberta por cima destes ajustes, pede a
        // equipe para saber se quem está ali pode comprar e equipar.
        return http.Response(jsonEncode(teamJson), 200);
      }
      if (method == 'GET' && path == '$_teamPath/wallet') {
        return http.Response(
          jsonEncode({
            'balance': 20000,
            'spent_points': 0,
            'members_points': 20000,
          }),
          200,
        );
      }
      if (method == 'POST' && path == '$_teamPath/purchase') {
        owned.add('${jsonDecode(request.body)['item_id']}');
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (method == 'POST' && path == '$_teamPath/equip') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calls.lastEquip = body;
        equipped = body['item_id'] as String?;
        return http.Response(jsonEncode(inventory()), 200);
      }
      if (method == 'PATCH' && path == _teamPath) {
        calls.lastPatch = jsonDecode(request.body) as Map<String, dynamic>;
        final saved = Map<String, dynamic>.from(teamJson);
        final body = calls.lastPatch!;
        if (body['name'] != null) saved['name'] = body['name'];
        return http.Response(jsonEncode(saved), 200);
      }
      if (path.endsWith('/invite/regenerate')) {
        return http.Response(
          jsonEncode({...teamJson, 'invite_token': 'novo-token'}),
          200,
        );
      }
      if (path.contains('/requests/')) {
        return http.Response(
          jsonEncode({...teamJson, 'pending_requests': <String>[]}),
          200,
        );
      }
      if (method == 'POST' && path == '/teams/leave') {
        calls.lastLeave = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 204);
      }
      if (method == 'DELETE' && path == _teamPath) {
        return http.Response('', 204);
      }
      return http.Response('{}', 200);
    }),
  );
  addTearDown(api.close);

  final state = AppState(api: api)
    ..profile = UserProfile.fromJson(profileData);
  addTearDown(state.dispose);

  final screen = TeamSettingsScreen(
    team: TeamDetail.fromJson(teamJson),
    onChanged: () {},
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildRunoverTheme(),
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => screen),
                      ),
                      child: const Text('Abrir ajustes'),
                    ),
                  ),
                ),
              )
            : screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (routed) {
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pumpAndSettle();
  }
  return calls;
}

/// A tela é uma `ListView`: itens de baixo só entram na árvore depois de rolar.
/// A chave pega a lista da tela, não uma das listas internas.
final _settingsList = find.byKey(const Key('team-settings-list'));

Future<void> scrollTo(WidgetTester tester, String text) async {
  final target = find.text(text);
  for (var i = 0; i < 16 && target.evaluate().isEmpty; i++) {
    await tester.drag(_settingsList, const Offset(0, -420));
    await tester.pump();
  }
}

/// Toca um controle da lista levando a linha para o meio da dobra: rolada só
/// até aparecer, a linha pode ficar na beirada de baixo e o toque não alcança.
Future<void> tapRow(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 24 && finder.evaluate().isEmpty; i++) {
    await tester.drag(_settingsList, const Offset(0, -240));
    await tester.pump();
  }
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 8; i++) {
    // Arrastar move o conteúdo junto com o dedo: para a linha descer do topo
    // para o meio, o deslocamento é o próprio (meio - posição atual).
    final delta = (height / 2 - tester.getTopLeft(finder).dy).clamp(
      -300.0,
      300.0,
    );
    if (delta.abs() < 16) break;
    await tester.drag(_settingsList, Offset(0, delta));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quem edita vê todas as seções de ajuste', (tester) async {
    await openTeamSettings(tester, teamSettingsJson(inviteToken: 'tok'));
    for (final section in [
      'PERFIL DA EQUIPE',
      'QUEM PODE ENTRAR',
      'CONVITES',
      'PEDIDOS DE ENTRADA',
      'AVISOS DA EQUIPE',
      'ZONA DE RISCO',
    ]) {
      await scrollTo(tester, section);
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  testWidgets('em janela larga as seções dividem a tela em duas colunas', (
    tester,
  ) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(inviteToken: 'tok'),
      size: const Size(1280, 900),
    );

    final columns = find.byKey(const Key('team-settings-columns'));
    expect(columns, findsOneWidget);
    // O miolo é o máximo da tela (1000) menos o respiro da lista (16 de cada
    // lado): as duas colunas preenchem o espaço, não sobra meio mundo de vazio.
    expect(tester.getSize(columns).width, 1000 - 32);

    // As duas colunas são desenhadas de uma vez: nenhuma seção espera rolagem
    // para existir, nem fica espremida numa faixa estreita no centro.
    const sections = [
      'PERFIL DA EQUIPE',
      'QUEM PODE ENTRAR',
      'CONVITES',
      'PEDIDOS DE ENTRADA',
      'AVISOS DA EQUIPE',
      'ZONA DE RISCO',
    ];
    for (final section in sections) {
      expect(find.text(section), findsOneWidget, reason: section);
    }

    // Cada título começa na beira de uma das duas colunas, e as duas colunas
    // têm a mesma largura: nada de uma seção no meio da tela ou de meia faixa.
    final band = tester.getRect(columns);
    final columnWidth = (band.width - 16) / 2;
    final starts = <double>{
      for (final section in sections)
        tester.getTopLeft(find.text(section)).dx,
    }.toList()
      ..sort();
    expect(starts.length, 2);
    expect(starts.first, greaterThanOrEqualTo(band.left));
    // O salto de uma coluna para a outra é a largura de uma coluna inteira.
    expect(starts.last - starts.first, closeTo(columnWidth + 16, 8));
    // A coluna da direita chega à beira direita do miolo: não sobra metade.
    expect(band.right - starts.last, closeTo(columnWidth, 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no celular a tela continua de uma coluna', (tester) async {
    await openTeamSettings(tester, teamSettingsJson(inviteToken: 'tok'));
    expect(find.byKey(const Key('team-settings-columns')), findsNothing);
    await scrollTo(tester, 'ZONA DE RISCO');
    expect(find.text('ZONA DE RISCO'), findsOneWidget);
  });

  testWidgets('membro sem cargo não recebe controle de edição', (tester) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(owner: false, admin: false, memberCount: 3),
    );
    expect(find.text('Você é membro: estes dados são da equipe e você pode sair.'), findsOneWidget);
    await scrollTo(tester, 'QUEM PODE ENTRAR');
    // O membro lê o modo escolhido, sem poder escolher.
    expect(find.text('Por aprovação'), findsOneWidget);
    expect(find.text('Aberta'), findsNothing);
    for (final hidden in [
      'CONVITES',
      'PEDIDOS DE ENTRADA',
      'AVISOS DA EQUIPE',
      'Escolher emblema na loja',
      'Salvar alterações',
      'Dissolver',
    ]) {
      await scrollTo(tester, hidden);
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('salvar envia nome, entrada, listagem e avisos', (tester) async {
    final calls = await openTeamSettings(tester, teamSettingsJson());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome da equipe'),
      'RUNOVER 2',
    );
    await tester.pump();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(calls.lastPatch, {
      'name': 'RUNOVER 2',
      'join_mode': 'approval',
      'listed': true,
      'notify_risk': true,
      'notify_requests': true,
    });
    expect(find.text('Alterações salvas'), findsOneWidget);
  });

  testWidgets('nome de uma letra não sai do aparelho', (tester) async {
    final calls = await openTeamSettings(tester, teamSettingsJson());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome da equipe'),
      'A',
    );
    await tester.pump();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(find.text('O nome precisa de pelo menos 2 letras'), findsOneWidget);
    expect(calls.called('PATCH $_teamPath'), isFalse);
  });

  testWidgets('trocar o modo de entrada marca como alterado', (tester) async {
    await openTeamSettings(tester, teamSettingsJson());
    await tester.tap(find.text('Aberta'));
    await tester.pump();
    final cancel = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Cancelar'),
    );
    expect(cancel.onPressed, isNotNull);
  });

  testWidgets('gerar link chama o servidor e mostra o link novo', (tester) async {
    final calls = await openTeamSettings(tester, teamSettingsJson());
    await scrollTo(tester, 'Gere um link para convidar');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Gerar'));
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar'));
    await tester.pumpAndSettle();
    expect(calls.called('POST $_teamPath/invite/regenerate'), isTrue);
    expect(find.text('/teams/join/novo-token'), findsOneWidget);
  });

  testWidgets('aceitar pedido decide no servidor e some da lista', (tester) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(
        requests: [
          {
            'id': 'req-1',
            'username': 'zoe',
            'photo_url': null,
            'created_at': '2026-10-10T12:00:00Z',
          },
        ],
      ),
    );
    await scrollTo(tester, '@zoe');
    expect(find.text('@zoe'), findsOneWidget);
    await tapRow(tester, find.byTooltip('Aceitar pedido'));
    expect(calls.called('POST $_teamPath/requests/req-1/approve'), isTrue);
    expect(find.text('@zoe'), findsNothing);
  });

  testWidgets('dissolver é do dono e pede o nome digitado', (tester) async {
    final calls = await openTeamSettings(tester, teamSettingsJson());
    await scrollTo(tester, 'Dissolver equipe');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Dissolver'));
    expect(find.text('Dissolver equipe?'), findsOneWidget);
    // Sem o nome, nada de confirmar.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dissolver')).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, 'RUNOVER');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Dissolver'));
    await tester.pumpAndSettle();
    expect(calls.called('DELETE $_teamPath'), isTrue);
  });

  testWidgets('link atual continua quando a regeneração falha', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(inviteToken: 'tok'),
      failOn: 'invite/regenerate',
    );
    await scrollTo(tester, 'Gere um link para convidar');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Gerar'));
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar'));
    await tester.pumpAndSettle();
    expect(calls.called('POST $_teamPath/invite/regenerate'), isTrue);
    expect(find.text('Ação indisponível.'), findsOneWidget);
    // O servidor não gerou nada: o link que já existia não pode sumir da tela.
    expect(find.text('/teams/join/tok'), findsOneWidget);
  });

  testWidgets('pedido que o servidor recusa continua na lista', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(
        requests: [
          {
            'id': 'req-1',
            'username': 'zoe',
            'photo_url': null,
            'created_at': '2026-10-10T12:00:00Z',
          },
        ],
      ),
      failOn: '/requests/',
    );
    await scrollTo(tester, '@zoe');
    await tapRow(tester, find.byTooltip('Recusar pedido'));
    expect(calls.called('POST $_teamPath/requests/req-1/reject'), isTrue);
    expect(find.text('Ação indisponível.'), findsOneWidget);
    // A decisão não aconteceu: esconder o pedido faria a tela prometer algo que
    // o servidor ainda tem pendurado.
    expect(find.text('@zoe'), findsOneWidget);
  });

  testWidgets('dissolver de verdade fecha a tela de ajustes', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(),
      routed: true,
    );
    await scrollTo(tester, 'Dissolver equipe');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Dissolver'));
    await tester.enterText(find.byType(TextField).last, 'RUNOVER');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Dissolver'));
    await tester.pumpAndSettle();
    expect(calls.called('DELETE $_teamPath'), isTrue);
    expect(find.widgetWithText(AppBar, 'Configurações'), findsNothing);
    expect(find.text('Abrir ajustes'), findsOneWidget);
  });

  testWidgets('dissolver recusado deixa a tela de ajustes aberta', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(),
      failOn: 'DELETE $_teamPath',
      routed: true,
    );
    await scrollTo(tester, 'Dissolver equipe');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Dissolver'));
    await tester.enterText(find.byType(TextField).last, 'RUNOVER');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Dissolver'));
    await tester.pumpAndSettle();
    expect(calls.called('DELETE $_teamPath'), isTrue);
    expect(find.text('Ação indisponível.'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Configurações'), findsOneWidget);
  });

  testWidgets('admin sem a posse não dissolve a equipe', (tester) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(owner: false, admin: true, memberCount: 3),
    );
    await scrollTo(tester, 'ZONA DE RISCO');
    expect(find.text('Dissolver'), findsNothing);
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('dono que sai escolhe o sucessor', (tester) async {
    final calls = await openTeamSettings(tester, teamSettingsJson());
    await scrollTo(tester, 'ZONA DE RISCO');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Sair'));
    expect(find.text('Passar a posse ou dissolver?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Transferir e sair'));
    await tester.pumpAndSettle();
    expect(calls.lastLeave?['successor_username'], 'pedro');
  });

  testWidgets('admin que sai só confirma', (tester) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(owner: false, admin: true),
    );
    await scrollTo(tester, 'ZONA DE RISCO');
    await tapRow(tester, find.widgetWithText(OutlinedButton, 'Sair'));
    expect(find.text('Sair da equipe?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
    await tester.pumpAndSettle();
    expect(calls.lastLeave, isNotNull);
    expect(calls.lastLeave!.containsKey('successor_username'), isFalse);
  });

  // #120: a caixa é o que ela mostra. O bloco de perfil tem prévia, aviso,
  // botão de loja e campo de nome; com nome comprido e fonte ampliada nada
  // pode sair pela borda — o `Clip` do cartão cortaria em silêncio.
  for (final (label, size) in [
    ('no celular', const Size(390, 2600)),
    ('na janela larga', const Size(1280, 1600)),
  ]) {
    testWidgets('a caixa de perfil caiba o nome comprido $label', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const name = 'Corredores da madrugada infinita';
      await openTeamSettings(
        tester,
        teamSettingsJson(name: name, inviteToken: 'tok'),
        size: size,
      );

      final nameField = find.widgetWithText(TextFormField, 'Nome da equipe');
      final box = find.ancestor(of: nameField, matching: find.byType(Card));
      expect(box, findsOneWidget);
      Rect rect(Finder finder) {
        final render = finder.evaluate().first.renderObject! as RenderBox;
        return render.localToGlobal(Offset.zero) & render.size;
      }

      final card = rect(box);
      expect(tester.widget<TextFormField>(nameField).controller!.text, name);
      for (final control in [
        find.byKey(const Key('team-pick-emblem')),
        nameField,
      ]) {
        expect(control, findsOneWidget, reason: '$control');
        final r = rect(control);
        expect(
          r.right,
          lessThanOrEqualTo(card.right + 0.5),
          reason: '$control passou da borda direita da caixa',
        );
        expect(
          r.bottom,
          lessThanOrEqualTo(card.bottom + 0.5),
          reason: '$control passou da borda de baixo da caixa',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
