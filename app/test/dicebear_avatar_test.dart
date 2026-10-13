import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/services/profile_image_provider.dart';
import 'package:runover_app/widgets/cosmetics.dart';

ShopItem avatarItem(String id, Map<String, dynamic> payload) => ShopItem(
  id: id,
  category: 'avatar',
  name: id,
  price: 100,
  payload: payload,
);

void main() {
  test('url usa estilo, seed e versão', () {
    expect(
      diceBearAvatarUrl('misaia'),
      'https://api.dicebear.com/7.x/adventurer/png?seed=misaia',
    );
    expect(
      diceBearAvatarUrl('misaia', style: 'pixel-art'),
      'https://api.dicebear.com/7.x/pixel-art/png?seed=misaia',
    );
  });

  test('estilo inválido cai no padrão e seed vazia usa runover', () {
    expect(
      diceBearAvatarUrl('', style: 'nao-existe'),
      'https://api.dicebear.com/7.x/adventurer/png?seed=runover',
    );
  });

  test('seed com espaço é codificada', () {
    expect(diceBearAvatarUrl('misa ia'), contains('seed=misa%20ia'));
  });

  test('todos os estilos anunciados geram url válida', () {
    for (final style in diceBearAvatarStyles) {
      expect(
        diceBearAvatarUrl('misaia', style: style),
        startsWith('https://api.dicebear.com/'),
      );
    }
  });

  test('avatar da API usa a seed do item, não a de quem equipou', () {
    final provider = profileAvatarImage(
      null,
      avatarItem('avatar_gerado_bottts', {
        'generated': 'bottts',
        'seed': 'avatar_gerado_bottts',
      }),
    );
    expect(provider, isA<NetworkImage>());
    expect(
      (provider as NetworkImage).url,
      'https://api.dicebear.com/7.x/bottts/png?seed=avatar_gerado_bottts',
    );
  });

  test('seed ausente no payload cai no id do item', () {
    expect(avatarSeed(avatarItem('avatar_corredor', {'generated': 'thumbs'})),
        'avatar_corredor');
    expect(
      avatarSeed(
        avatarItem('avatar_corredor', {'seed': '', 'generated': 'thumbs'}),
      ),
      'avatar_corredor',
    );
    expect(
      avatarSeed(
        avatarItem('avatar_corredor', {
          'generated': 'thumbs',
          'seed': 'rosto_do_item',
        }),
      ),
      'rosto_do_item',
    );
  });

  test('rosto do item tem prioridade sobre a foto enviada', () {
    final provider = profileAvatarImage(
      'https://example.com/foto.jpg',
      avatarItem('avatar_coroa', {'generated': 'personas'}),
    );
    expect(provider, isA<NetworkImage>());
    expect(
      (provider as NetworkImage).url,
      contains('seed=avatar_coroa'),
    );
  });

  test('sem item, a foto passa direto; sem nada, null', () {
    final provider = profileAvatarImage(
      'https://example.com/foto.jpg',
      null,
    );
    expect(provider, isA<NetworkImage>());
    expect((provider as NetworkImage).url, 'https://example.com/foto.jpg');
    expect(profileAvatarImage(null, null), isNull);
  });

  test('generated desconhecido é ignorado', () {
    expect(
      profileAvatarImage(
        null,
        avatarItem('x', {'generated': 'nao-existe'}),
      ),
      isNull,
    );
    final fallback = profileAvatarImage(
      'https://example.com/foto.jpg',
      avatarItem('x', {'generated': 'nao-existe'}),
    );
    expect((fallback as NetworkImage).url, 'https://example.com/foto.jpg');
  });
}
