import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runover_app/services/profile_image_provider.dart';

/// JPEG grande estilo "foto de câmera", que no web chegava sem
/// redimensionamento e estourava o teto da API.
Uint8List _cameraJpeg() {
  final photo = img.Image(width: 1200, height: 900);
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      photo.setPixelRgb(
        x,
        y,
        (x * 255 ~/ photo.width),
        (y * 255 ~/ photo.height),
        ((x + y) % 256),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 100));
}

void main() {
  test('foto pequena passa intacta', () {
    final raw = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final avatar = fitAvatarPhoto(raw)!;
    expect(avatar.mimeType, 'image/png');
    expect(avatar.bytes, raw);
  });

  test('foto de câmera é reduzida para o teto da API', () {
    final avatar = fitAvatarPhoto(_cameraJpeg())!;
    expect(avatar.mimeType, 'image/jpeg');
    expect(avatar.bytes.length, lessThanOrEqualTo(maxAvatarBytes));
    final decoded = img.decodeImage(avatar.bytes)!;
    expect(decoded.width, lessThanOrEqualTo(512));
    expect(decoded.height, lessThanOrEqualTo(512));
    // A data URI resultante passa na validação do app.
    final uri = 'data:${avatar.mimeType};base64,${base64Encode(avatar.bytes)}';
    expect(isProfilePhotoDataUri(uri), isTrue);
    expect(profileImageProvider(uri), isNotNull);
  });

  test('conteúdo inválido é recusado', () {
    expect(fitAvatarPhoto(Uint8List(0)), isNull);
    expect(fitAvatarPhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(
      fitAvatarPhoto(Uint8List.fromList('not an image'.codeUnits)),
      isNull,
    );
  });

  test('galeria tem 12 avatares únicos', () {
    expect(presetAvatars, hasLength(12));
    expect(
      presetAvatars.map((p) => p.asset).toSet(),
      hasLength(12),
    );
    expect(
      presetAvatars.map((p) => p.label).toSet(),
      hasLength(12),
    );
  });
}
