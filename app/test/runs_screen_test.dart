import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/runs_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O sorteio do dia não mora mais no aparelho: a tela desenha o que
/// `GET /runs/challenges` devolve. Este é o payload do servidor usado nos
/// testes de widget.
Map<String, dynamic> _challengesPayload({bool done = false, bool claimed = false}) =>
    {
      'day': '2026-10-12',
      'challenges': [
        {
          'id': 'km-3',
          'title': 'Três quilômetros',
          'detail': 'Curta distância para manter o hábito',
          'unit': 'km',
          'target': 3,
          'rarity': 'comum',
          'kind': 'distance',
          'value': done ? 3.4 : 0,
          'done': done,
          'points': 20,
          'coins': 0,
          'claimed': claimed,
        },
        {
          'id': 'min-20',
          'title': 'Vinte minutos em movimento',
          'detail': 'No seu ritmo, sem pressa',
          'unit': 'min',
          'target': 20,
          'rarity': 'raro',
          'kind': 'duration',
          'value': 12,
          'done': false,
          'points': 40,
          'coins': 30,
          'claimed': false,
        },
      ],
    };

void main() {
  test('featured goal is the open goal closest to completion', () {
    const goals = [
      WeeklyGoal(name: 'km', value: 2, target: 10, unit: 'km'),
      WeeklyGoal(name: 'dias', value: 2, target: 3, unit: 'dias'),
      WeeklyGoal(name: 'feita', value: 3, target: 3, unit: 'conquistas'),
    ];
    expect(WeeklyGoal.featured(goals)?.name, 'dias');
    expect(goals.first.missing, 'Faltam 8 km');
  });

  test('week time left counts down to the end of the local week', () {
    final now = DateTime.utc(2026, 10, 4, 18, 22);
    expect(weekTimeLeft('2026-09-28T03:00:00Z', now), '8h 38min restantes');
    expect(weekTimeLeft('2026-09-21T03:00:00Z', now), isNull);
    expect(weekTimeLeft('2026-10-01T03:00:00Z', now), '3d 8h restantes');
  });

  test('the draw rolls over at local midnight', () {
    expect(timeUntilMidnight(DateTime(2026, 10, 12, 17, 36)), '6h 24min');
    expect(timeUntilMidnight(DateTime(2026, 10, 12, 23, 40)), '20min');
  });

  Future<void> openScreen(
    WidgetTester tester,
    Size size, {
    List<Map<String, dynamic>> runs = const [],
    /// O que o servidor devolve quando a pedida traz `since` (o mês). Sem
    /// isto, o mês responde o mesmo histórico inteiro.
    List<Map<String, dynamic>>? monthRuns,
    Map<String, dynamic> progress = const {},
    Map<String, dynamic> Function(String method)? challengesFor,
    void Function(String url, String method)? onRequest,
    /// Atraso que o servidor finge ter, por caminho e query. É como o teste
    /// faz duas leituras chegarem fora de ordem.
    Duration Function(String path, Map<String, String> query)? delayFor,
    // Cada abertura num mesmo teste precisa de chave própria: sem ela o
    // `pumpWidget` reaproveita o State, a aba escolhida e a carga anterior.
    Key? screenKey,
    /// Desenha a tela empurrada por cima de outra rota, como o atalho do perfil
    /// a desenhava antes de virar troca de aba: ali não há menu, e a seta de
    /// voltar é a única saída.
    bool pushed = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // O servidor devolve o dia inteiro no GET e de novo depois do resgate, então
    // o payload depende do método. Sem `challengesFor`, o desafio é cumprido e
    // pago na hora do resgate.
    final payloadFor =
        challengesFor ??
        (method) => method == 'POST'
            ? _challengesPayload(done: true, claimed: true)
            : _challengesPayload();

    final api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        // Caminho com a query: é assim que o teste vê o `since` do filtro.
        final query = request.url.query;
        onRequest?.call(query.isEmpty ? path : '$path?$query', request.method);
        final delay =
            delayFor?.call(path, request.url.queryParameters) ?? Duration.zero;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (path == '/runs/progress') {
          return http.Response(
            jsonEncode({
              'week_start': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'runs_count': 4,
              'distance_km': 18.5,
              'longest_run_km': 7.2,
              'daily_bonus': 20,
              'daily_bonus_pending': true,
              'goals': [
                {
                  'name': 'Correr 10 km nesta semana',
                  'value': 3.4,
                  'target': 10,
                  'unit': 'km',
                },
                {
                  'name': 'Correr em 3 dias nesta semana',
                  'value': 2,
                  'target': 3,
                  'unit': 'dias',
                },
              ],
              'badges': [
                {'name': 'Primeira corrida', 'earned': true},
                {'name': '10 corridas', 'earned': false},
              ],
              'team': null,
              ...progress,
            }),
            200,
          );
        }
        if (path == '/runs') {
          // O servidor corta o mês no parâmetro `since`; o mock decide pelo
          // parâmetro, não pela data, para o teste não depender do dia de hoje.
          final month = request.url.queryParameters['since'] != null;
          return http.Response(
            jsonEncode(month ? (monthRuns ?? runs) : runs),
            200,
            // Sem o charset explícito o corpo é Latin-1: o travessão de um
            // `claim_error` chegava quebrado na tela.
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path == '/runs/challenges') {
          return http.Response(jsonEncode(payloadFor('GET')), 200);
        }
        if (path == '/runs/challenges/claim') {
          return http.Response(jsonEncode(payloadFor('POST')), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson({
        'id': '1',
        'full_name': 'Marina Oliveira',
        'username': 'marina',
        'email': 'marina@example.com',
        'total_score': 0,
        'territories_count': 0,
      });
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: pushed
              ? Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RunsScreen(key: screenKey),
                          ),
                        ),
                        child: const Text('abrir corridas'),
                      ),
                    ),
                  ),
                )
              : RunsScreen(key: screenKey),
        ),
      ),
    );
    if (pushed) {
      await tester.tap(find.text('abrir corridas'));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openChallengesTab(WidgetTester tester) async {
    await tester.tap(find.text('DESAFIOS'));
    await tester.pumpAndSettle();
  }

  testWidgets('history shows the numbers, the period filter and the run rows', (
    tester,
  ) async {
    await openScreen(
      tester,
      const Size(390, 2400),
      runs: [
        {
          'id': 'r1',
          'name': 'Volta no parque',
          'started_at': '2026-10-03T10:00:00Z',
          'distance_m': 5200,
          'duration_seconds': 1725,
          'pace_seconds_per_km': 330,
        },
        {
          'id': 'r2',
          'name': 'Laço da praça',
          // O instante atual garante o rótulo "Hoje" em qualquer fuso.
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'distance_m': 1800,
          'claim': {
            'created_new': true,
            'points_awarded': 120,
            'challenge': null,
            'challenge_won': null,
            'territory': {'name': 'Praça Seca'},
          },
        },
        {
          'id': 'r3',
          'name': 'Volta pela metade',
          'started_at': '2026-10-01T09:00:00Z',
          'distance_m': 900,
          'claim_error': 'Percurso não fechado — faltam ~480m.',
        },
      ],
    );

    // Resumo do servidor em número pt-BR.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('18,5 km'), findsWidgets);
    expect(find.text('7,2 km'), findsWidgets);
    // 'CORRIDAS' é o título da barra e o selo do primeiro cartão.
    expect(find.text('CORRIDAS'), findsNWidgets(2));
    expect(find.text('DISTÂNCIA TOTAL'), findsOneWidget);
    expect(find.text('MAIOR CORRIDA'), findsOneWidget);

    // Filtro de período no lugar dos chips de modo, e nenhum nome de modo na
    // tela: a linha mostra a data e o que a corrida rendeu.
    expect(find.text('Este mês'), findsOneWidget);
    expect(find.text('Tudo'), findsOneWidget);
    expect(find.text('Dominação'), findsNothing);
    expect(find.text('Desafio'), findsNothing);

    expect(find.text('5,2 km'), findsOneWidget);
    expect(find.text('28:45 · ritmo 5\'30"/km'), findsOneWidget);
    expect(find.text('3 OUT'), findsOneWidget);
    // A corrida com conquista mostra o território e o XP ganho.
    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('+1 território'), findsOneWidget);
    expect(find.text('+120 XP'), findsOneWidget);
    // O motivo de não ter conquistado continua na linha da lista.
    expect(find.textContaining('Percurso não fechado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o filtro de período corta no servidor e recomeça a paginação', (
    tester,
  ) async {
    final requested = <String>[];
    await openScreen(
      tester,
      const Size(390, 2400),
      onRequest: (url, method) => requested.add('$method $url'),
      runs: [
        {
          'id': 'r1',
          'name': 'Volta no parque',
          'started_at': '2026-08-03T10:00:00Z',
          'distance_m': 5200,
        },
      ],
      monthRuns: [
        {
          'id': 'r2',
          'name': 'Corrida do mês',
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'distance_m': 2400,
        },
      ],
    );

    expect(find.text('5,2 km'), findsOneWidget);
    // Aberto em "Tudo": a primeira pedida não leva corte nenhum.
    expect(requested, contains('GET /runs?offset=0&limit=20'));

    await tester.tap(find.text('Este mês'));
    await tester.pumpAndSettle();

    // O corte sai como parâmetro — filtrar a lista já carregada mostraria um
    // mês pela metade numa paginação de 20.
    final monthCall = requested.lastWhere((r) => r.startsWith('GET /runs?'));
    expect(monthCall, startsWith('GET /runs?offset=0&limit=20&since='));
    // Hora com dois-pontos escapada: a query é montada codificada.
    expect(monthCall, contains('%3A'));
    expect(find.text('2,4 km'), findsOneWidget);
    expect(find.text('5,2 km'), findsNothing);

    await tester.tap(find.text('Tudo'));
    await tester.pumpAndSettle();
    expect(
      requested.lastWhere((r) => r.startsWith('GET /runs?')),
      'GET /runs?offset=0&limit=20',
    );
    expect(find.text('5,2 km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mês vazio avisa em vez de oferecer a primeira corrida', (
    tester,
  ) async {
    await openScreen(
      tester,
      const Size(390, 2400),
      runs: [
        {
          'id': 'r1',
          'name': 'Volta no parque',
          'started_at': '2026-08-03T10:00:00Z',
          'distance_m': 5200,
        },
      ],
      monthRuns: [],
    );

    await tester.tap(find.text('Este mês'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma corrida neste mês.'), findsOneWidget);
    // O convite ao que ainda não correu é estado vazio de conta, não de mês.
    expect(find.text('Nenhuma corrida ainda'), findsNothing);
    // Sem página seguinte: o mês veio vazio, então não há mais o que carregar.
    expect(find.text('CARREGAR MAIS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Este mês" com página cheia continua paginável, com o corte', (
    tester,
  ) async {
    final requested = <String>[];
    await openScreen(
      tester,
      const Size(390, 2400),
      onRequest: (url, method) => requested.add('$method $url'),
      // "Tudo" vem vazio de propósito: o botão só pode aparecer do lado do
      // mês, e é justamente ali que ele tinha sido escondido.
      runs: const [],
      monthRuns: [
        for (var i = 0; i < 20; i++)
          {
            'id': 'm$i',
            'name': 'Corrida $i',
            'started_at': DateTime.now().toUtc().toIso8601String(),
            'distance_m': 1000 + i,
          },
      ],
    );

    await tester.tap(find.text('Este mês'));
    await tester.pumpAndSettle();

    // Vinte corridas é uma página inteira: há uma segunda página de mês, e
    // escondê-la deixava o resto da história inacessível. A lista é preguiçosa,
    // então o botão precisa entrar na tela antes de ser procurado.
    final loadMore = find.text('CARREGAR MAIS');
    await tester.scrollUntilVisible(loadMore, 300);
    expect(loadMore, findsOneWidget);

    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    final next = requested.lastWhere((r) => r.startsWith('GET /runs?'));
    expect(next, contains('offset=20'));
    // A página seguinte continua dentro do período escolhido.
    expect(next, contains('since='));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leitura do período anterior não escreve por cima da escolha nova', (
    tester,
  ) async {
    await openScreen(
      tester,
      const Size(390, 2400),
      runs: [
        {
          'id': 'r1',
          'name': 'Volta no parque',
          'started_at': '2026-08-03T10:00:00Z',
          'distance_m': 5200,
        },
      ],
      monthRuns: [
        {
          'id': 'r2',
          'name': 'Corrida do mês',
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'distance_m': 2400,
        },
      ],
      // O mês demora; "Tudo" responde na hora. É o caso em que a resposta
      // velha chega por último.
      delayFor: (path, query) =>
          path == '/runs' && query.containsKey('since')
          ? const Duration(milliseconds: 400)
          : Duration.zero,
    );

    await tester.tap(find.text('Este mês'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.text('Tudo'));
    await tester.pump(const Duration(milliseconds: 1));
    // Tempo suficiente para as duas respostas chegarem, a lenta inclusive.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    // O que está na tela é o período escolhido por último, não o que chegou
    // por último.
    expect(find.text('5,2 km'), findsOneWidget);
    expect(find.text('2,4 km'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a corrida com desafio continua dourada sem dizer o modo', (
    tester,
  ) async {
    await openScreen(
      tester,
      const Size(390, 2400),
      runs: [
        {
          'id': 'r2',
          'name': 'Retomada marcada',
          'started_at': '2026-10-02T10:00:00Z',
          'distance_m': 2400,
          'claim': {
            'points_awarded': 90,
            'challenge': 'pace',
            'challenge_won': true,
            'territory': {'name': 'Praça Seca'},
          },
        },
      ],
    );

    // A cor e as pílulas contam o que aconteceu; o nome do modo saiu da tela.
    expect(find.text('2,4 km'), findsOneWidget);
    expect(find.text('+1 território'), findsOneWidget);
    expect(find.text('+90 XP'), findsOneWidget);
    expect(find.text('DESAFIO'), findsNothing);
    expect(find.text('DOMINAÇÃO'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty history offers the coming mode and the real bonus', (
    tester,
  ) async {
    await openScreen(tester, const Size(390, 2600), runs: []);

    expect(find.text('Nenhuma corrida ainda'), findsOneWidget);
    expect(
      find.textContaining('mesmo sem conquistar um território'),
      findsOneWidget,
    );
    // Um cartão só: o modo ainda em desenvolvimento, com o mesmo texto da home.
    // Os outros dois modos já têm entrada na home e não se repetem aqui.
    expect(find.text('DESAFIO DE VELOCIDADE'), findsOneWidget);
    expect(
      find.text('Voltas cronometradas. Bata seu recorde e suba no ranking.'),
      findsOneWidget,
    );
    expect(find.text('DOMINAÇÃO'), findsNothing);
    expect(find.text('PIT STOP'), findsNothing);
    expect(find.text('ENTRAR'), findsNothing);
    expect(find.text('EM BREVE'), findsOneWidget);
    expect(find.text('JOGAR'), findsOneWidget);
    // Sem pílulas: não há o que prometer de um modo que ainda não tem regra.
    expect(find.text('Território dominado'), findsNothing);
    // O bônus é o número do servidor, não o XP do mock.
    expect(find.textContaining('Bônus do dia: +20 dracmas'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Botão desativado de verdade: tocar não abre diálogo nem tela.
    await tester.tap(find.text('JOGAR'));
    await tester.pump();
    expect(find.text('Entendi'), findsNothing);
    expect(find.text('MAPA'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the daily challenges come from the server and pay on claim', (
    tester,
  ) async {
    final requested = <String>[];
    await openScreen(
      tester,
      const Size(390, 2600),
      onRequest: (path, method) => requested.add('$method $path'),
    );
    // A pedida leva o fuso do aparelho na query: o sorteio é do dia local.
    expect(
      requested.any((r) => r.startsWith('GET /runs/challenges')),
      isTrue,
    );

    await openChallengesTab(tester);
    expect(find.text('DESAFIOS DO DIA'), findsOneWidget);
    expect(
      find.text('Sorteio pessoal de @marina · muda à meia-noite'),
      findsOneWidget,
    );
    expect(find.textContaining('troca em'), findsOneWidget);
    expect(find.text('Três quilômetros'), findsOneWidget);
    expect(find.text('COMUM'), findsOneWidget);
    expect(find.text('RARO'), findsOneWidget);
    expect(find.text('+40 XP'), findsOneWidget);
    expect(find.text('12 / 20 min'), findsOneWidget);
    expect(find.text('RESGATAR'), findsNothing);

    // A meta em aberto mais próxima vem do /progress e paga o resgate. As
    // outras metas seguem como linhas próprias, então cada nome aparece uma vez.
    expect(find.text('Próxima meta'), findsOneWidget);
    expect(find.text('Correr em 3 dias nesta semana'), findsOneWidget);
    expect(find.text('Correr 10 km nesta semana'), findsOneWidget);
    expect(find.text('METAS DA SEMANA'), findsOneWidget);
    expect(find.text('Falta 1 dia'), findsOneWidget);
  });

  testWidgets('a finished challenge pays through the server and locks', (
    tester,
  ) async {
    final requested = <String>[];
    // O desafio já nasce cumprido; depois do POST o servidor o devolve
    // resgatado — é o que a tela relê ao recarregar o dia.
    var claimed = false;
    await openScreen(
      tester,
      const Size(390, 2600),
      challengesFor: (method) {
        if (method == 'POST') claimed = true;
        return _challengesPayload(done: true, claimed: claimed);
      },
      onRequest: (path, method) => requested.add('$method $path'),
    );
    await openChallengesTab(tester);

    // O desafio cumprido vira botão; o outro segue mostrando a recompensa.
    expect(find.text('RESGATAR'), findsOneWidget);
    expect(find.text('3,4 / 3 km'), findsOneWidget);
    expect(find.text('+40 XP'), findsOneWidget);

    await tester.tap(find.text('RESGATAR'));
    await tester.pumpAndSettle();

    expect(requested, contains('POST /runs/challenges/claim'));
    expect(find.text('RESGATADO'), findsOneWidget);
    expect(find.textContaining('Três quilômetros resgatado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history fits a small phone, a standard phone and a desktop', (
    tester,
  ) async {
    for (final size in const [Size(320, 740), Size(390, 844), Size(1280, 800)]) {
      await openScreen(
        tester,
        size,
        screenKey: ValueKey(size),
        runs: [
          {
            'id': 'r1',
            'name': 'Volta no parque',
            'started_at': '2026-10-03T10:00:00Z',
            'distance_m': 5200,
            'duration_seconds': 1725,
            'pace_seconds_per_km': 330,
            'claim': {
              'points_awarded': 120,
              'challenge': null,
              'territory': {'name': 'Praça Seca'},
            },
          },
        ],
      );
      expect(find.text('Volta no parque'), findsNothing);
      expect(find.text('5,2 km'), findsOneWidget);
      expect(find.text('+120 XP'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A aba de desafios percorre as mesmas larguras. Só o topo é montado
      // abaixo da dobra, então a checagem fica no primeiro cartão.
      await tester.tap(find.text('DESAFIOS'));
      await tester.pumpAndSettle();
      expect(find.text('DESAFIOS DO DIA'), findsOneWidget);
      expect(find.text('Três quilômetros'), findsOneWidget);
      expect(find.text('COMUM'), findsOneWidget);
      expect(find.text('0 / 3 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  // Corridas não é porta de menu: o canto de cima fica limpo e quem navega
  // para fora da aba é a barra de baixo. Atualizar também não tem botão aqui —
  // puxar a lista recarrega as duas abas, o filtro de período e o resgate de um
  // desafio também, e a falha tem o "Tentar novamente" do banner.
  testWidgets('corridas não tem botão de menu nem de atualizar no cabeçalho', (
    tester,
  ) async {
    await openScreen(tester, const Size(390, 844));
    expect(find.byTooltip('Menu'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
  // Sem o botão de atualizar, recarregar no desktop é puxar a lista com o
  // rato — e o rato não arrasta lista nenhuma por padrão.
  testWidgets('a lista de corridas aceita arrastão de rato', (tester) async {
    await openScreen(tester, const Size(1280, 900));
    final behavior = ScrollConfiguration.of(
      tester.element(find.byType(ListView).first),
    );
    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
  });

  // Empilhada por cima de outra rota não há casca nem barra embaixo: a seta é
  // a única saída da tela. Sem ela, o atalho "Minhas corridas" do perfil
  // levava a uma Corridas sem porta de volta.
  testWidgets(
    'a Corridas empilhada tem porta de voltar no cabeçalho',
    (tester) async {
      await openScreen(tester, const Size(390, 844), pushed: true);
      expect(find.byTooltip('Voltar'), findsOneWidget);
      // Fora da casca não há menu a abrir: o botão não aparece decorativo.
      expect(find.byTooltip('Menu'), findsNothing);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('abrir corridas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a Corridas aba da casca não tem seta de voltar', (tester) async {
    await openScreen(tester, const Size(390, 844));
    // Aqui quem navega é a barra de baixo: a seta seria decorativa.
    expect(find.byTooltip('Voltar'), findsNothing);
  });
}
