import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

final _profilePhotoDataUri = RegExp(
  r'^data:image/(?:jpeg|png|webp);base64,([A-Za-z0-9+/]*={0,2})$',
);

bool isProfilePhotoDataUri(String value) =>
    _profilePhotoDataUri.hasMatch(value);

String? profilePhotoMimeType(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

ImageProvider? profileImageProvider(String? value) {
  final photo = value?.trim();
  if (photo == null || photo.isEmpty) return null;
  if (photo.startsWith('data:')) {
    final match = _profilePhotoDataUri.firstMatch(photo);
    if (match == null) return null;
    try {
      return MemoryImage(Uint8List.fromList(base64Decode(match.group(1)!)));
    } on FormatException {
      return null;
    }
  }
  return NetworkImage(photo);
}

/// Teto da API para a foto de perfil (backend: `ProfileUpdateRequest`).
const maxAvatarBytes = 400 * 1024;

/// Maior lado aceito sem redimensionar.
const maxAvatarSide = 512;

/// Foto pronta para `photo_url`.
class AvatarPhoto {
  const AvatarPhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Prepara bytes brutos para o avatar: mantém o original quando já cabe
/// nos limites da API, senão redimensiona e recodifica em JPEG.
/// Devolve null quando o conteúdo não é JPG, PNG ou WebP válido.
///
/// O redimensionamento acontece dentro do app porque o `image_picker`
/// ignora `maxWidth`/`imageQuality` no web: sem isso, uma foto de câmera
/// escolhida no navegador estourava os 400 KB e a API recusava.
AvatarPhoto? fitAvatarPhoto(Uint8List raw) {
  if (raw.isEmpty) return null;
  final mime = profilePhotoMimeType(raw);
  if (mime == null) return null;
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  if (raw.length <= maxAvatarBytes &&
      decoded.width <= maxAvatarSide &&
      decoded.height <= maxAvatarSide) {
    return AvatarPhoto(bytes: raw, mimeType: mime);
  }
  img.Image resized = _resized(decoded, maxAvatarSide);
  var quality = 85;
  var out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  while (out.length > maxAvatarBytes && quality > 40) {
    quality -= 15;
    out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
  if (out.length > maxAvatarBytes) {
    resized = _resized(decoded, 256);
    out = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  }
  return AvatarPhoto(bytes: out, mimeType: 'image/jpeg');
}

img.Image _resized(img.Image source, int side) {
  if (source.width >= source.height) {
    return img.copyResize(source, width: side);
  }
  return img.copyResize(source, height: side);
}

/// Avatares prontos embutidos no app (gerados por tools/gen_preset_avatars.py).
///
/// A loja não desenha mais estes PNGs — o rosto de cada item vem da API de
/// avatares. Eles ficam por duas razões: o cartão de equipe no painel sorteia um
/// destes rostos quando a equipe não tem emblema comprado, e a folha de escolha
/// usa o nome para achar o item histórico `avatar_<nome>` no catálogo.
class PresetAvatar {
  const PresetAvatar(this.asset, this.label);

  final String asset;
  final String label;
}

const presetAvatars = [
  PresetAvatar('assets/avatars/avatar_corredor.png', 'Corredor'),
  PresetAvatar('assets/avatars/avatar_raio.png', 'Raio'),
  PresetAvatar('assets/avatars/avatar_pico.png', 'Pico'),
  PresetAvatar('assets/avatars/avatar_estrela.png', 'Estrela'),
  PresetAvatar('assets/avatars/avatar_bandeira.png', 'Bandeira'),
  PresetAvatar('assets/avatars/avatar_chama.png', 'Chama'),
  PresetAvatar('assets/avatars/avatar_onda.png', 'Onda'),
  PresetAvatar('assets/avatars/avatar_sol.png', 'Sol'),
  PresetAvatar('assets/avatars/avatar_lua.png', 'Lua'),
  PresetAvatar('assets/avatars/avatar_cometa.png', 'Cometa'),
  PresetAvatar('assets/avatars/avatar_escudo.png', 'Escudo'),
  PresetAvatar('assets/avatars/avatar_coroa.png', 'Coroa'),
];

/// Avatares gerados via DiceBear (gratuito, sem chave de API): únicos por
/// seed — na loja a seed é o id do item (`avatarSeed`), para que vitrine, folha
/// e perfil de quem equipou desenhem o mesmo rosto. PNG direto, sem SVG.
/// Na loja, cada estilo é um item pago (`payload['generated']`).
const diceBearApiVersion = '7.x';
const diceBearAvatarStyles = [
  'adventurer',
  'avataaars',
  'bottts',
  'personas',
  'notionists',
  'thumbs',
  'pixel-art',
  'lorelei',
];

String diceBearAvatarUrl(String seed, {String style = 'adventurer'}) {
  final clean = seed.trim();
  final useStyle =
      diceBearAvatarStyles.contains(style) ? style : 'adventurer';
  return 'https://api.dicebear.com/$diceBearApiVersion/$useStyle/png'
      '?seed=${Uri.encodeComponent(clean.isEmpty ? 'runover' : clean)}';
}
