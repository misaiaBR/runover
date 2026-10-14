import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_settings_screen_test.dart'
    show openTeamSettings, scrollTo, teamSettingsJson;

// O emblema da equipe é item da Loja da equipe: a tela de ajustes não tem campo
// de foto, não oferece avatar local e não sobe imagem do aparelho. Estes casos
// seguram essa regra e a prévia que mostra o rosto do item equipado.

const _estandarteUrl =
    'https://api.dicebear.com/7.x/adventurer/png?seed=team_avatar_estandarte';
const _coroaUrl =
    'https://api.dicebear.com/7.x/personas/png?seed=team_avatar_coroa';

/// A prévia do bloco de perfil: único `CircleAvatar` da tela enquanto não há
/// pedido de entrada.
String? _previewUrl(WidgetTester tester) {
  final image = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first)
      .foregroundImage;
  return image is NetworkImage ? image.url : null;
}

/// A Loja da equipe tem vitrine em loop (moldura pulsando, `Breathe`):
/// `pumpAndSettle` nunca termina ali. São quadros com duração, sempre.
Future<void> _frames(WidgetTester tester, {int vezes = 8}) async {
  for (var i = 0; i < vezes; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('o bloco de perfil não tem campo de foto nem avatar local', (
    tester,
  ) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(photoUrl: 'https://exemplo.run/antiga.png'),
    );
    await scrollTo(tester, 'Escolher emblema na loja');
    expect(find.text('Escolher emblema na loja'), findsOneWidget);

    // O que existia antes saiu junto: caixa de link, botão de link, remover
    // foto e a faixa de avatares prontos. Só sobra o campo de nome.
    expect(find.widgetWithText(TextFormField, 'Nome da equipe'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Link da foto'), findsNothing);
    expect(find.text('Usar link'), findsNothing);
    expect(find.text('Remover foto'), findsNothing);
    expect(find.byKey(const Key('team-photo-Corredor')), findsNothing);
    expect(find.text('Foto da equipe'), findsNothing);
  });

  testWidgets('a prévia é o rosto do emblema que a equipe equipou', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(equippedAvatar: 'team_avatar_coroa'),
    );
    // Catálogo e inventário do escopo da equipe — não os da loja pessoal.
    expect(calls.catalogQuery, contains('scope=team'));
    expect(calls.catalogQuery, contains('category=avatar'));
    expect(calls.called('GET /teams/team-1/inventory'), isTrue);

    expect(_previewUrl(tester), _coroaUrl);
  });

  testWidgets('sem emblema comprado a prévia fica na foto que já existia', (
    tester,
  ) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(
        photoUrl: 'https://exemplo.run/antiga.png',
        equippedAvatar: null,
      ),
    );
    expect(_previewUrl(tester), 'https://exemplo.run/antiga.png');
  });

  testWidgets('a folha da equipe compra e equipa em pontos do cofre', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(equippedAvatar: 'team_avatar_coroa'),
    );
    await scrollTo(tester, 'Escolher emblema na loja');
    await tester.tap(find.text('Escolher emblema na loja'));
    await tester.pumpAndSettle();

    expect(find.text('Escolha o emblema'), findsOneWidget);
    expect(
      find.text('Tudo custa pontos do cofre — a equipe ganha correndo.'),
      findsOneWidget,
    );
    // O saldo mostrado é o cofre, em pontos, formatado em pt-BR.
    expect(find.text('20.000 pontos'), findsOneWidget);
    expect(find.text('Emblemas'), findsOneWidget);
    expect(find.text('4.000 pts'), findsOneWidget);
    // A folha da equipe não oferece a galeria pessoal.
    expect(find.text('Escolha um avatar'), findsNothing);
    expect(find.text('Galeria'), findsNothing);
    expect(find.text('Gerados'), findsNothing);

    await tester.tap(find.byKey(const Key('preset-avatar-Estandarte da equipe')));
    await tester.pumpAndSettle();

    expect(calls.called('POST /teams/team-1/purchase'), isTrue);
    expect(calls.lastEquip, {'category': 'avatar', 'item_id': 'team_avatar_estandarte'});
    // A folha fecha e a prévia da tela já mostra o emblema novo.
    expect(find.text('Escolha o emblema'), findsNothing);
    expect(_previewUrl(tester), _estandarteUrl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voltar da Loja da equipe atualiza a prévia do emblema', (
    tester,
  ) async {
    final calls = await openTeamSettings(
      tester,
      teamSettingsJson(equippedAvatar: 'team_avatar_coroa'),
      routed: true,
    );
    expect(_previewUrl(tester), _coroaUrl);

    // A loja inteira, aberta pela rota da lista — não a folha do emblema.
    await scrollTo(tester, 'Loja da equipe');
    await tester.tap(find.text('Loja da equipe'));
    await _frames(tester);
    expect(find.text('COFRE · RUNOVER'), findsOneWidget);

    await tester.tap(find.text('4.000'));
    await _frames(tester, vezes: 12);
    expect(find.text('Equipar'), findsOneWidget);
    await tester.tap(find.text('Equipar'));
    await _frames(tester, vezes: 12);
    expect(
      calls.lastEquip,
      {'category': 'avatar', 'item_id': 'team_avatar_estandarte'},
    );

    // Volta pelos ajustes, como o botão de voltar faz.
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    for (var i = 0; i < 12 && find.text('COFRE · RUNOVER').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('COFRE · RUNOVER'), findsNothing);
    // A recarga da prévia é pedida à rede depois do retorno; os quadros acima
    // não bastam porque a rota ainda estava fechando.
    await _frames(tester, vezes: 6);

    // O emblema que a equipe equipou na loja é o rosto dos ajustes agora.
    expect(_previewUrl(tester), _estandarteUrl);
    // E foi lido do servidor depois do retorno, não adivinhado na tela.
    expect(
      calls.requests.where((r) => r == 'GET /teams/team-1/inventory').length,
      greaterThan(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('membro sem cargo não alcança a folha da loja', (tester) async {
    await openTeamSettings(
      tester,
      teamSettingsJson(owner: false, admin: false, memberCount: 3),
    );
    expect(
      find.text('O emblema é item da Loja da equipe. Só o dono ou admins mudam.'),
      findsOneWidget,
    );
    expect(find.text('Escolher emblema na loja'), findsNothing);
  });
}
