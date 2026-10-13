import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/banner_plate.dart';
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/effect_painters.dart';
import 'package:runover_app/widgets/offer_row.dart';

/// A faixa de fundo do perfil ganhou nove palavras de construção: `plate` diz de
/// que jeito a placa é montada — vidro fosco, gradiente na direção pedida, fibra
/// de carbono, mapa do território, metal escovado por patamar, LED na borda,
/// feixe holográfico, camadas contra o ponteiro e borda que respira
/// (`PLATE_STYLES` em `backend/app/services/shop.py`). Se o app lesse isso como
/// texto de ficha técnica, todas as faixas da loja continuariam o mesmo
/// retângulo de cor.
///
/// Estes testes amarram o contrário: cada palavra vira um desenho próprio e
/// diferente dos outros, o desenho não sai da caixa, só o que o catálogo declara
/// como ritmo se mexe na tela, e uma faixa sem `plate` — ou anterior ao
/// vocabulário — continua o gradiente de sempre.
const Size _side = Size(120, 72);

ShopItem _banner(
  String id, {
  String? plate,
  List<String> colors = const ['#0EA5E9', '#1E3A8A'],
  Map<String, Object?> extra = const {},
}) => ShopItem(
  id: id,
  category: 'banner',
  name: 'Faixa $id',
  price: 200,
  payload: {'plate': ?plate, 'colors': colors, ...extra},
);

/// A palavra do catálogo para o estilo: `split_neon` não cabe num identificador
/// Dart, então é o único nome que difere da propriedade.
String _word(PlateStyle style) => style.word.isEmpty ? style.name : style.word;

/// Uma faixa por estilo, todas com o mesmo `id` e as mesmas cores: assim a
/// diferença medida na tela vem do `plate`, não da semente nem da paleta.
Map<PlateStyle, ShopItem> _galeria() => {
  for (final style in PlateStyle.values)
    style: _banner('banner_galeria', plate: _word(style)),
};

/// Pinta a placa sobre o gradiente cru da faixa e devolve os pixels em RGBA. É o
/// único jeito de perguntar se o estilo mudou o desenho, se ele continua dentro
/// da caixa e se a placa parada continua a mesma no meio do ciclo.
Future<ByteData> _pixels(
  ShopItem banner, {
  double progress = 0,
  Offset pointer = Offset.zero,
  bool plate = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Offset.zero & _side,
    Paint()..shader = bannerGradient(banner)!.createShader(Offset.zero & _side),
  );
  if (plate) {
    PlatePainter(
      spec: PlateSpec.of(banner)!,
      progress: progress,
      pointer: pointer,
    ).paint(canvas, _side);
  }
  final image = await recorder.endRecording().toImage(
    _side.width.toInt(),
    _side.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

/// Soma da diferença entre duas imagens, em todos os canais de todos os pixels.
int _delta(ByteData a, ByteData b) {
  var total = 0;
  for (var i = 0; i < a.lengthInBytes; i++) {
    total += (a.getUint8(i) - b.getUint8(i)).abs();
  }
  return total;
}

/// Uma digital curta da imagem: basta para saber se dois desenhos são o mesmo.
int _signature(ByteData pixels) {
  var hash = 0x811C9DC5;
  for (var i = 0; i < pixels.lengthInBytes; i++) {
    hash = ((hash ^ pixels.getUint8(i)) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8(((y * _side.width.toInt() + x) * 4) + 3);

/// A placa montada na tela dentro de uma caixa de 120×72. A chave fica fora para
/// [_capture] poder ser chamado mais de uma vez na mesma montagem — a respiração
/// só é visível entre duas capturas de um relógio que não foi reiniciado.
final GlobalKey _plateKey = GlobalKey();

Future<void> _mount(
  WidgetTester tester,
  ShopItem? banner, {
  Widget? child,
  double radius = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _plateKey,
            child: SizedBox(
              width: _side.width,
              height: _side.height,
              child: BannerPlate(
                key: ValueKey('${banner?.id}$radius'),
                banner: banner,
                borderRadius: BorderRadius.circular(radius),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ByteData> _capture(WidgetTester tester) async {
  late ByteData pixels;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_plateKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });
  return pixels;
}

Future<ByteData> _onScreen(
  WidgetTester tester,
  ShopItem? banner, {
  Widget? child,
  double radius = 0,
}) async {
  await _mount(tester, banner, child: child, radius: radius);
  return _capture(tester);
}

List<PlatePainter> _painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<PlatePainter>()
    .toList();

void main() {
  test('as nove palavras do catálogo viram estilo; fora delas, nada', () {
    for (final style in PlateStyle.values) {
      expect(PlateStyle.parse(_word(style)), style);
    }
    expect(PlateStyle.splitNeon.word, 'split_neon');
    // Palavra inventada ou de outra família não vale: o app não desenha
    // estrutura que a loja não vende para a faixa. O identificador Dart também
    // não é vocabulário de loja — `splitNeon` no payload seria um item que
    // nenhuma faixa do catálogo vende.
    expect(PlateStyle.parse('holofote'), isNull);
    expect(PlateStyle.parse('bevel'), isNull);
    expect(PlateStyle.parse('splitNeon'), isNull);
    expect(PlateStyle.parse(null), isNull);
    expect(PlateStyle.parse(7), isNull);

    for (final grade in PlateGrade.values) {
      expect(PlateGrade.parse(grade.name), grade);
    }
    // `prata` é patamar de moldura, não de chapa.
    expect(PlateGrade.parse('prata'), isNull);
    expect(PlateGrade.parse(null), isNull);
  });

  test('a placa só existe quando a faixa declara um estilo conhecido', () {
    expect(PlateSpec.of(null), isNull);
    // Faixa anterior ao vocabulário: cores, mas nenhuma palavra de placa.
    expect(PlateSpec.of(_banner('banner_oceano')), isNull);
    expect(PlateSpec.of(_banner('banner_caótica', plate: 'lava')), isNull);

    final spec = PlateSpec.of(_banner('banner_galeria', plate: 'glass'))!;
    expect(spec.style, PlateStyle.glass);
    expect(spec.item.id, 'banner_galeria');
    expect(spec.colors, cosmeticColors(_banner('comparação')));
    expect(spec.base, const Color(0xFF0EA5E9));
  });

  test('a palavra manda e o número refina: fora dele, o padrão do estilo', () {
    // `blur` e `edge` ausentes em vidro continuam vidro, só que no desfoque
    // médio com a borda puxada ao claro da própria faixa.
    final bare = PlateSpec.of(_banner('a', plate: 'glass'))!;
    expect(bare.blur, 3);
    expect(bare.edge, Color.lerp(bare.base, Colors.white, .62));

    final full = PlateSpec.of(
      _banner('a', plate: 'glass', extra: {'blur': 5, 'edge': '#FFD1A1'}),
    )!;
    expect(full.blur, 5);
    expect(full.edge, cosmeticHexColor('#FFD1A1'));

    // Número mal escrito ou hex fora do lugar não derruba a tela nem inventa
    // material: volta ao padrão do estilo.
    final junk = PlateSpec.of(
      _banner('a', plate: 'glass', extra: {'blur': 'muito', 'edge': '#ZZZZZZ'}),
    )!;
    expect(junk.blur, 3);
    expect(junk.edge, Color.lerp(junk.base, Colors.white, .62));
    // Um `depth` de 900 camadas é borrão infinito: o teto do catálogo segura.
    expect(
      PlateSpec.of(_banner('a', plate: 'parallax', extra: {'depth': 900}))!.depth,
      3,
    );
    expect(
      PlateSpec.of(_banner('a', plate: 'carbon', extra: {'weave': -4}))!.weave,
      1,
    );
    // O `grade` ausente é o aço, não uma aposta em ouro.
    expect(
      PlateSpec.of(_banner('a', plate: 'brushed'))!.grade,
      PlateGrade.aco,
    );
    expect(
      PlateSpec.of(
        _banner('a', plate: 'brushed', extra: {'grade': 'platina'}),
      )!.grade,
      PlateGrade.platina,
    );
    // Os números de outro estilo não atrapalham este: `angle` existe, mas só o
    // gradiente dinâmico o usa.
    final carbon = PlateSpec.of(
      _banner('a', plate: 'carbon', extra: {'weave': 3, 'angle': 120}),
    )!;
    expect(carbon.weave, 3);
    expect(carbon.angle, 120);
  });

  test('só o que o catálogo declara como ritmo tem relógio', () {
    // O milissegundo do payload manda: 2.000 ms é o pulso da faixa do passe.
    expect(
      PlateSpec.of(
        _banner('a', plate: 'split_neon', extra: {'pulse_ms': 2000}),
      )!.period,
      const Duration(milliseconds: 2000),
    );
    expect(
      PlateSpec.of(
        _banner('a', plate: 'shimmer', extra: {'sweep_ms': 2600}),
      )!.period,
      const Duration(milliseconds: 2600),
    );
    expect(
      PlateSpec.of(
        _banner('a', plate: 'pulse', extra: {'period_ms': 1800}),
      )!.period,
      const Duration(milliseconds: 1800),
    );
    // Ciclo sem milissegundo nenhum vem, mas nunca é um flash: o gradiente que
    // gira e o fundo que espera o dedo são matéria, não sinal.
    expect(
      PlateSpec.of(_banner('a', plate: 'gradient'))!.period,
      const Duration(milliseconds: 7000),
    );
    expect(
      PlateSpec.of(_banner('a', plate: 'parallax'))!.period,
      const Duration(milliseconds: 14000),
    );
    // Placa parada não acende um quadro por nada: o perfil de quem tem carbono
    // não anima um desenho que não se move.
    for (final style in const [
      PlateStyle.glass,
      PlateStyle.carbon,
      PlateStyle.territory,
      PlateStyle.brushed,
    ]) {
      expect(
        PlateSpec.of(_banner('a', plate: _word(style)))!.period,
        isNull,
        reason: '${style.name} não tem ciclo',
      );
    }
    // Um `ms` fora da escala razoável volta para o teto, não trava a tela.
    expect(
      PlateSpec.of(
        _banner('a', plate: 'pulse', extra: {'period_ms': 999999}),
      )!.period,
      const Duration(milliseconds: 20000),
    );
  });

  test('a semente é o id da faixa com a região: mesmo item, mesma placa', () {
    PlateSpec seedOf(String id, {String? region}) => PlateSpec.of(
      _banner(id, plate: 'territory', extra: {'region': ?region}),
    )!;
    // Vitrine e perfil leem o mesmo item duas vezes; o mapa não pode mudar de
    // forma entre as duas.
    expect(seedOf('banner_muralha', region: 'Sudeste').seed,
        seedOf('banner_muralha', region: 'Sudeste').seed);
    expect(
      seedOf('banner_muralha', region: 'Sudeste').seed,
      effectSeedOf('banner_muralhaSudeste'),
    );
    // Outra região é outro mapa: duas faixas `territory` do catálogo não podem
    // ser a mesma silhueta.
    expect(seedOf('banner_muralha', region: 'Sudeste').seed,
        isNot(seedOf('banner_muralha', region: 'Pampa').seed));
    expect(seedOf('banner_outra', region: 'Sudeste').seed,
        isNot(seedOf('banner_muralha', region: 'Sudeste').seed));
  });

  test('toda a matriz de estilos e números pinta sem estourar', () {
    for (final style in PlateStyle.values) {
      for (final extra in [
        const <String, Object?>{},
        const {'blur': 5, 'edge': '#FFD1A1', 'angle': 120, 'weave': 3},
        const {'region': 'Cerrado', 'grade': 'platina', 'edge_hue': 300},
        const {'depth': 3, 'pulse_ms': 400, 'sweep_ms': 400, 'period_ms': 400},
      ]) {
        final painter = PlatePainter(
          spec: PlateSpec.of(
            _banner('faixa_matriz', plate: _word(style), extra: extra),
          )!,
          progress: 0.3,
          pointer: const Offset(-0.4, 0.8),
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), _side);
        recorder.endRecording().dispose();
      }
    }
    // E a caixa vazia: um perfil medindo 0×0 não pode lançar exceção.
    final recorder = ui.PictureRecorder();
    PlatePainter(
      spec: PlateSpec.of(_banner('faixa_zero', plate: 'territory'))!,
      progress: 0,
    ).paint(Canvas(recorder), Size.zero);
    recorder.endRecording().dispose();
  });

  testWidgets('cada estilo desenha por cima do gradiente, e nenhum é igual', (
    tester,
  ) async {
    late ByteData cru;
    late Map<PlateStyle, ByteData> pintado;
    await tester.runAsync(() async {
      final galeria = _galeria();
      cru = await _pixels(galeria[PlateStyle.glass]!, plate: false);
      pintado = {
        for (final entry in galeria.entries) entry.key: await _pixels(entry.value),
      };
    });
    for (final style in PlateStyle.values) {
      // O `plate` compra um desenho, não uma nota de rodapé: se o delta for
      // zero, a palavra virou texto de ficha técnica.
      expect(
        _delta(cru, pintado[style]!),
        greaterThan(0),
        reason: '${style.name} não muda o gradiente',
      );
    }
    for (final a in PlateStyle.values) {
      for (final b in PlateStyle.values) {
        if (a.index >= b.index) continue;
        expect(
          _signature(pintado[a]!),
          isNot(_signature(pintado[b]!)),
          reason: '${a.name} e ${b.name} desenharam a mesma placa',
        );
      }
    }
  });

  testWidgets('o que não tem milissegundo declarado fica parado', (
    tester,
  ) async {
    late Map<PlateStyle, int> noMeioCiclo;
    late Map<PlateStyle, int> noUmQuarto;
    await tester.runAsync(() async {
      final galeria = _galeria();
      noMeioCiclo = {};
      noUmQuarto = {};
      for (final entry in galeria.entries) {
        final cru = await _pixels(entry.value);
        noMeioCiclo[entry.key] = _delta(
          cru,
          await _pixels(entry.value, progress: 0.5),
        );
        noUmQuarto[entry.key] = _delta(
          cru,
          await _pixels(entry.value, progress: 0.25),
        );
      }
    });
    for (final style in const [
      PlateStyle.glass,
      PlateStyle.carbon,
      PlateStyle.territory,
      PlateStyle.brushed,
    ]) {
      expect(noMeioCiclo[style], 0, reason: '${style.name} se mexe sem pedir');
    }
    // Os cinco que têm relógio mudam de um quarto de ciclo para o outro — e o
    // pulso ainda é a respiração comprada, não um piscar de luzes.
    for (final style in const [
      PlateStyle.gradient,
      PlateStyle.splitNeon,
      PlateStyle.shimmer,
      PlateStyle.parallax,
      PlateStyle.pulse,
    ]) {
      expect(
        noUmQuarto[style],
        greaterThan(0),
        reason: '${style.name} deveria respirar',
      );
    }
  });

  testWidgets('só o paralaxe responde ao ponteiro', (tester) async {
    late Map<PlateStyle, int> comMao;
    await tester.runAsync(() async {
      comMao = {};
      for (final entry in _galeria().entries) {
        comMao[entry.key] = _delta(
          await _pixels(entry.value),
          await _pixels(entry.value, pointer: const Offset(0.8, -0.6)),
        );
      }
    });
    for (final style in PlateStyle.values) {
      expect(
        comMao[style],
        style == PlateStyle.parallax ? greaterThan(0) : 0,
        reason: '${style.name} não promete profundidade contra a mão',
      );
    }
  });

  testWidgets('a placa animada respira na tela; a parada não', (tester) async {
    // É o teste que pega o relógio morto: um `repeat()` sem nada escutando
    // gasta quadro e deixa a faixa congelada no mesmo desenho.
    await _mount(tester, _banner('a', plate: 'pulse'));
    final vivo = await _capture(tester);
    await tester.pump(const Duration(milliseconds: 550));
    final vivoDepois = await _capture(tester);
    expect(_delta(vivo, vivoDepois), greaterThan(0));

    await _mount(tester, _banner('a', plate: 'glass'));
    final pedra = await _capture(tester);
    await tester.pump(const Duration(milliseconds: 550));
    final pedraDepois = await _capture(tester);
    expect(_delta(pedra, pedraDepois), 0);
  });

  testWidgets('reconstruir a tela não reinicia a respiração da faixa', (
    tester,
  ) async {
    // O perfil reconstrói o cartão a cada `setState` (catálogo, presença, foto).
    // Se a placa voltasse ao zero do ciclo em toda reconstrução, o perfil vivo
    // daria solucos em vez de respirar.
    await _mount(tester, _banner('a', plate: 'pulse'));
    await tester.pump(const Duration(milliseconds: 550));
    final antes = await _capture(tester);
    await _mount(tester, _banner('a', plate: 'pulse'));
    final depois = await _capture(tester);
    expect(_delta(antes, depois), 0);
  });

  testWidgets('nenhum filete sai da faixa, nem no canto arredondado', (
    tester,
  ) async {
    // O mapa do território desenha hexágonos até a borda e o feixe do
    // holográfico entra por fora: sem recorte, o cartão de identidade sangraria
    // para fora da faixa.
    final pixels = await _onScreen(
      tester,
      _banner('mapa', plate: 'territory', extra: {'region': 'Sul'}),
      radius: 10,
    );
    // O canto do retângulo está fora do raio de 10: tinta ali é recorte
    // falhado, não estilo.
    expect(_alphaAt(pixels, 0, 0), 0);
    expect(_alphaAt(pixels, 119, 0), 0);
    expect(_alphaAt(pixels, 0, 71), 0);
    expect(_alphaAt(pixels, 119, 71), 0);
    // E no meio da placa há desenho de verdade.
    expect(_alphaAt(pixels, 60, 36), greaterThan(0));
  });

  testWidgets('a placa ocupa exatamente o espaço da faixa', (tester) async {
    Future<void> wear(ShopItem? banner, {Widget? child}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _side.width,
                height: _side.height,
                child: BannerPlate(banner: banner, child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(BannerPlate)), _side);
    }

    // Nenhuma placa muda a altura que o perfil reserva para a faixa.
    await wear(null);
    await wear(_banner('cru'));
    await wear(_banner('vidro', plate: 'glass'));
    await wear(_banner('carbono', plate: 'carbon'));
    await wear(_banner('paralaxe', plate: 'parallax'));
    // Com conteúdo, a caixa continua a mesma: a faixa do cartão de identidade
    // só existe como fundo; a do ranking veste o nome.
    await wear(_banner('mapa', plate: 'territory'), child: const Text('Nome'));
    expect(_painters(tester), hasLength(1));
  });

  testWidgets('a camada é decoração: quem recebe o toque é o conteúdo', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _side.width,
              height: _side.height,
              child: BannerPlate(
                banner: _banner('mapa', plate: 'territory', extra: {'region': 'Sul'}),
                child: InkWell(
                  onTap: () => tapped++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // O pintor é a camada de baixo do `Stack`: se ficasse por cima, o
    // `CustomPaint` engoliria o toque e a faixa viraria um botão mudo.
    expect(_painters(tester), hasLength(1));
    await tester.tap(find.byType(InkWell));
    expect(tapped, 1);
  });

  testWidgets('só o paralaxe escuta o ponteiro', (tester) async {
    Future<void> wear(String plate) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _side.width,
                height: _side.height,
                child: BannerPlate(banner: _banner('f', plate: plate)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final plateWidget = find.byType(BannerPlate);
      expect(
        find.descendant(
          of: plateWidget,
          matching: find.byType(MouseRegion),
        ),
        plate == 'parallax' ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(of: plateWidget, matching: find.byType(Listener)),
        plate == 'parallax' ? findsOneWidget : findsNothing,
      );
    }

    await wear('glass');
    await wear('shimmer');
    // É o único estilo que promete profundidade contra a mão, e a escuta não
    // trava o gesto de quem toca. O `Listener` procurado é o da placa: a
    // estrutura da tela tem outros escutando toque e cancelamento.
    await wear('parallax');
    await tester.drag(
      find.descendant(
        of: find.byType(BannerPlate),
        matching: find.byType(Listener),
      ),
      const Offset(40, 20),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a vitrine mostra a placa que o item é', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Center(
            child: ShopPreview(
              item: _banner(
                'team_banner_muralha',
                plate: 'territory',
                extra: {'region': 'Sudeste'},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // A prévia era só o retângulo de cor: "faixa de vidro" e "faixa de carbono"
    // com a mesma cara antes do toque.
    expect(find.byType(BannerPlate), findsOneWidget);
    expect(_painters(tester), hasLength(1));
  });

  testWidgets('faixa sem placa continua o gradiente de sempre', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _side.width,
              height: _side.height,
              child: BannerPlate(banner: _banner('banner_oceano')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_painters(tester), isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(BannerPlate),
        matching: find.byType(DecoratedBox),
      ),
    ).decoration as BoxDecoration;
    expect(decorated.gradient, bannerGradient(_banner('banner_oceano')));
  });
}
