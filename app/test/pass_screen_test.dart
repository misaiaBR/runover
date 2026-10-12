import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/season_pass_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

Map<String, dynamic> passStatus({
  bool premium = false,
  bool claimedFree = false,
}) => {
  'season_id': '2026-10',
  'ends_at': '2026-11-01T00:00:00+00:00',
  'seasonal_points': 250,
  'unlocked_tier': 1,
  'premium_unlocked': premium,
  'premium_price_coins': 1000,
  'tiers': [
    {
      'tier': 1,
      'threshold': 200,
      'unlocked': true,
      'free': {
        'coins': 10,
        'item_id': null,
        'claimed': claimedFree,
      },
      'premium': {'coins': 25, 'item_id': null, 'claimed': false},
    },
    {
      'tier': 2,
      'threshold': 400,
      'unlocked': false,
      'free': {
        'coins': 20,
        'item_id': null,
        'claimed': false,
      },
      'premium': {'coins': 50, 'item_id': null, 'claimed': false},
    },
  ],
};

/// A tela vista pelo teste: estado do servidor, chamadas registradas e o
/// `AppState` que a tela observa.
class _PassFixture {
  _PassFixture({
    this.serverPremium = false,
    this.serverClaimedFree = false,
    this.claimFails = false,
    this.profileFails = false,
    this.noTiers = false,
  });

  final List calls = [];
  int passFetches = 0;
  bool serverPremium;
  bool serverClaimedFree;
  bool claimFails;

  /// O `GET /users/me` que fecha a escrita falha: a gravação já vale no
  /// servidor, então a tela não pode desfazê-la nem mostrar erro.
  bool profileFails;

  /// Resposta do passe sem nenhum tier: payload quebrado, não um estado entre
  /// temporadas. A tela tem que avisar em vez de montar uma trilha vazia.
  bool noTiers;

  /// Quando definido, o resgate fica pendurado até o teste completar este
  /// future — serve para agir enquanto o painel está ocupado.
  Completer<void>? holdClaim;

  late final AppState state;

  /// Algo mudou a conta fora do painel (compra na loja, corrida sincronizada):
  /// o app recarrega o perfil e avisa quem observa o estado.
  Future<void> accountChanged() => state.refreshProfile();
}

void main() {
  Future<_PassFixture> openPass(
    WidgetTester tester, {
    bool premium = false,
    bool claimedFree = false,
    bool claimFails = false,
    bool profileFails = false,
    bool noTiers = false,
  }) async {
    final fixture = _PassFixture(
      serverPremium: premium,
      serverClaimedFree: claimedFree,
      claimFails: claimFails,
      profileFails: profileFails,
      noTiers: noTiers,
    );
    final api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/pass') {
          fixture.passFetches++;
          final status = passStatus(
            premium: fixture.serverPremium,
            claimedFree: fixture.serverClaimedFree,
          );
          if (fixture.noTiers) status.remove('tiers');
          return http.Response(jsonEncode(status), 200);
        }
        if (request.method == 'GET' && path == '/shop/catalog') {
          // O handler roda durante o pumpAndSettle da recarga, então a
          // checagem não pode usar a API protegida `expect`.
          expectSync(request.url.queryParameters['scope'], 'pass');
          return http.Response(jsonEncode([]), 200);
        }
        if (request.method == 'POST' && path == '/pass/claim') {
          final body = jsonDecode(request.body);
          fixture.calls.add(('claim', body['tier'], body['track']));
          final hold = fixture.holdClaim;
          if (hold != null) await hold.future;
          if (fixture.claimFails) {
            return http.Response(jsonEncode({'detail': 'Resgate indisponível.'}), 500);
          }
          if (body['track'] == 'free') fixture.serverClaimedFree = true;
          return http.Response(
            jsonEncode(
              passStatus(
                premium: fixture.serverPremium,
                claimedFree: fixture.serverClaimedFree,
              ),
            ),
            200,
          );
        }
        if (request.method == 'POST' && path == '/pass/premium') {
          fixture.calls.add(('premium',));
          fixture.serverPremium = true;
          return http.Response(
            jsonEncode(
              passStatus(
                premium: fixture.serverPremium,
                claimedFree: fixture.serverClaimedFree,
              ),
            ),
            200,
          );
        }
        if (path == '/users/me') {
          if (fixture.profileFails) {
            return http.Response(
              jsonEncode({'detail': 'Perfil indisponível.'}),
              500,
            );
          }
          return http.Response(jsonEncode(profileData), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    fixture.state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileData);
    addTearDown(fixture.state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: fixture.state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const SeasonPassScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  /// O painel de destaque é quem age: o botão do estado da recompensa aberta.
  Future<void> tapPanelButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  /// Seleciona a recompensa da faixa do passe no painel.
  Future<void> selectPassReward(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Requer passe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requer passe'));
    await tester.pumpAndSettle();
  }

  Future<void> claimFreeReward(WidgetTester tester) async {
    await tapPanelButton(tester, 'Resgatar');
  }

  /// Abre o passe pela faixa violeta e confirma na conversa.
  Future<void> openPremiumDialog(WidgetTester tester) async {
    await selectPassReward(tester);
    await tapPanelButton(tester, 'Ativar passe · 1.000 dracmas');
  }

  testWidgets('mostra temporada, níveis e resgata a faixa grátis', (
    tester,
  ) async {
    final pass = await openPass(tester);
    expect(find.text('Passe de Temporada'), findsOneWidget);
    expect(find.text('outubro de 2026'), findsOneWidget);
    expect(find.text('Nível 1'), findsOneWidget);
    expect(find.text('250 / 400 pts'), findsOneWidget);
    // A trilha horizontal: um nó por nível, rótulos fixos à esquerda.
    expect(find.text('Grátis'), findsOneWidget);
    expect(find.text('Passe'), findsOneWidget);
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('Requer passe'), findsOneWidget);
    expect(find.text('NÍVEL 2'), findsNWidgets(2));

    final fetches = pass.passFetches;
    await claimFreeReward(tester);
    expect(pass.calls, [('claim', 1, 'free')]);
    expect(find.text('Recompensa resgatada!'), findsOneWidget);
    // O resgate já recarrega: a revisão que ele mesmo provocou não gera uma
    // segunda busca.
    expect(pass.passFetches, fetches + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium desbloqueia com confirmação', (tester) async {
    final pass = await openPass(tester);
    // O painel abre no resgate pendente; o passe entra em cena pela faixa
    // violeta, onde o preço é do lado do botão.
    expect(find.textContaining('Ativar passe'), findsNothing);
    await selectPassReward(tester);
    expect(find.textContaining('Só itens visuais'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Ativar passe · 1.000 dracmas'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trilha premium?'), findsOneWidget);
    // "por 1.000 dracmas" é a frase da confirmação; o botão do painel mostra o
    // preço, mas solto.
    expect(find.textContaining('por 1.000 dracmas'), findsOneWidget);
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    expect(pass.calls, [('premium',)]);
    expect(find.text('Trilha premium desbloqueada!'), findsOneWidget);
    // Com o passe, o painel para de oferecê-lo: o selo da barra é o aviso.
    expect(find.textContaining('Ativar passe'), findsNothing);
    expect(find.text('Passe ativo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o cartão "Requer passe" leva ao botão que ativa o passe', (
    tester,
  ) async {
    final pass = await openPass(tester);
    // O nível 1 já foi alcançado: o cartão do passe é um caminho de verdade,
    // não um aviso mudo. A trilha pode estar abaixo da dobra na janela do
    // teste — primeiro vem à vista.
    await selectPassReward(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Ativar passe · 1.000 dracmas'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trilha premium?'), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    // Recusar não compra: nenhuma escrita saiu e o painel continua oferecendo.
    expect(pass.calls, isEmpty);
    expect(
      find.widgetWithText(FilledButton, 'Ativar passe · 1.000 dracmas'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recarrega quando a conta muda longe do painel', (
    tester,
  ) async {
    final pass = await openPass(tester);
    expect(find.text('+10'), findsOneWidget);
    final fetches = pass.passFetches;

    // A loja liberou o premium; o painel não viu a compra acontecer.
    pass.serverPremium = true;
    await pass.accountChanged();
    await tester.pumpAndSettle();

    expect(pass.passFetches, fetches + 1);
    expect(find.text('Passe ativo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não perde a mudança externa que chega durante um resgate', (
    tester,
  ) async {
    final pass = await openPass(tester, claimFails: true);
    final fetches = pass.passFetches;

    pass.holdClaim = Completer<void>();
    await claimFreeReward(tester);
    await tester.pump();

    // A conta mudou enquanto o resgate estava em voo: ocupado, o painel espera.
    pass.serverPremium = true;
    await pass.accountChanged();
    await tester.pump();
    expect(pass.passFetches, fetches);

    pass.holdClaim!.complete();
    await tester.pumpAndSettle();

    // O resgate falhou, então a recarga é o flush do fim da operação.
    expect(pass.passFetches, fetches + 1);
    expect(find.text('Passe ativo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resgate persistido recarrega quando o perfil falha', (
    tester,
  ) async {
    final pass = await openPass(tester, profileFails: true);
    final fetches = pass.passFetches;

    await claimFreeReward(tester);
    await tester.pumpAndSettle();

    // O POST aceitou o resgate: a recarga traz a verdade do servidor e nada
    // reoferta o botão (o servidor responderia 409). A falha é só do perfil.
    expect(pass.calls, [('claim', 1, 'free')]);
    expect(find.text('Perfil indisponível.'), findsOneWidget);
    expect(find.text('Resgatar'), findsNothing);
    expect(pass.passFetches, fetches + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passe comprado recarrega quando o perfil falha', (
    tester,
  ) async {
    final pass = await openPass(tester, profileFails: true);
    final fetches = pass.passFetches;

    await openPremiumDialog(tester);
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();

    // Mesmo caso do resgate: a compra vale, então o painel não fica
    // oferecendo o desbloqueio de novo.
    expect(pass.calls, [('premium',)]);
    expect(find.text('Perfil indisponível.'), findsOneWidget);
    expect(find.textContaining('Ativar passe'), findsNothing);
    expect(pass.passFetches, fetches + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resposta sem níveis avisa em vez de montar trilha vazia', (
    tester,
  ) async {
    final pass = await openPass(tester, noTiers: true);
    // O conversor aceita um payload sem `tiers`; a tela não pode procurar o
    // nível em destaque numa trilha que não existe.
    expect(find.text('Não foi possível carregar o passe.'), findsOneWidget);
    expect(find.text('Grátis'), findsNothing);
    expect(tester.takeException(), isNull);

    final fetches = pass.passFetches;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(pass.passFetches, fetches + 1);
    expect(find.text('Não foi possível carregar o passe.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
