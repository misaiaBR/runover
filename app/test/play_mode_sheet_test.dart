import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/play_mode_sheet.dart';

Future<PlayMode?> openSheet(WidgetTester tester) async {
  PlayMode? selected;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(),
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showPlayModeSheet(
            context,
            onSelect: (mode) => selected = mode,
          ),
          child: const Text('Jogar'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Jogar'));
  await tester.pumpAndSettle();
  return selected;
}

void main() {
  testWidgets('mostra as três mecânicas em português', (tester) async {
    await openSheet(tester);
    expect(find.text('Como quer jogar?'), findsOneWidget);
    expect(find.text('Laço livre'), findsOneWidget);
    expect(find.text('Caçar selvagem'), findsOneWidget);
    expect(find.text('Desafiar dono'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada opção devolve a mecânica escolhida', (tester) async {
    PlayMode? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showPlayModeSheet(
              context,
              onSelect: (mode) => selected = mode,
            ),
            child: const Text('Jogar'),
          ),
        ),
      ),
    );
    for (final (label, mode) in const [
      ('Laço livre', PlayMode.freeLoop),
      ('Caçar selvagem', PlayMode.huntWild),
      ('Desafiar dono', PlayMode.challenge),
    ]) {
      await tester.tap(find.text('Jogar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(selected, mode);
    }
    expect(tester.takeException(), isNull);
  });

  test('escolher uma mecânica é intenção de conquistar', () {
    // A folha promete território nas três opções; a corrida aberta por qualquer
    // uma delas tem de começar com o alternador ligado.
    expect(conquestIntended(mode: PlayMode.freeLoop), isTrue);
    expect(conquestIntended(mode: PlayMode.huntWild), isTrue);
    expect(conquestIntended(mode: PlayMode.challenge), isTrue);
    expect(conquestIntended(target: const Object()), isTrue);
    expect(conquestIntended(challengeTarget: const Object()), isTrue);
    expect(conquestIntended(), isFalse);
  });
}
