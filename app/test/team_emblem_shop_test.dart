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
