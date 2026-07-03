import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/procedural_glyphs.dart';

void main() {
  test('procedural box lines join without transparent seams', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    expect(
      paintProceduralGlyph(
        canvas,
        Offset.zero,
        const Size(10, 10),
        0x2500,
        paint,
      ),
      isTrue,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(10, 0),
      const Size(10, 10),
      0x2500,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(20, 10);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    int alphaAt(int x, int y) => bytes!.getUint8((y * 20 + x) * 4 + 3);
    expect(alphaAt(9, 5), greaterThan(0));
    expect(alphaAt(10, 5), greaterThan(0));

    image.dispose();
    picture.dispose();
  });

  test('procedural glyph rendering falls back for regular text', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    expect(
      paintProceduralGlyph(
        canvas,
        Offset.zero,
        const Size(10, 10),
        'A'.codeUnitAt(0),
        Paint(),
      ),
      isFalse,
    );

    recorder.endRecording().dispose();
  });

  test('procedural glyph rendering covers every block element', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var codePoint = 0x2580; codePoint <= 0x259f; codePoint++) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset.zero,
          const Size(10, 20),
          codePoint,
          paint,
        ),
        isTrue,
        reason: 'U+${codePoint.toRadixString(16)}',
      );
    }

    recorder.endRecording().dispose();
  });

  test('procedural braille blank has no visible dots', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    expect(
      paintProceduralGlyph(
        canvas,
        Offset.zero,
        const Size(10, 20),
        0x2800,
        Paint()..color = const Color(0xffffffff),
      ),
      isTrue,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 20);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected braille image bytes');
    }

    expect(_hasAnyAlpha(bytes, 10, 20), isFalse);

    image.dispose();
    picture.dispose();
  });

  test('procedural braille renders all eight dots', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    expect(
      paintProceduralGlyph(
        canvas,
        Offset.zero,
        const Size(20, 40),
        0x28ff,
        Paint()..color = const Color(0xffffffff),
      ),
      isTrue,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(20, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected braille image bytes');
    }

    for (final x in [5, 15]) {
      for (final y in [5, 15, 25, 35]) {
        expect(_alphaNear(bytes, 20, 40, x, y), greaterThan(0));
      }
    }

    image.dispose();
    picture.dispose();
  });
}

bool _hasAnyAlpha(ByteData bytes, int width, int height) {
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint8((y * width + x) * 4 + 3) != 0) {
        return true;
      }
    }
  }
  return false;
}

int _alphaNear(ByteData bytes, int width, int height, int x, int y) {
  var maximum = 0;
  for (var offsetY = -2; offsetY <= 2; offsetY++) {
    for (var offsetX = -2; offsetX <= 2; offsetX++) {
      final sampleX = x + offsetX;
      final sampleY = y + offsetY;
      if (sampleX < 0 || sampleX >= width || sampleY < 0 || sampleY >= height) {
        continue;
      }
      final alpha = bytes.getUint8((sampleY * width + sampleX) * 4 + 3);
      maximum = max(maximum, alpha);
    }
  }
  return maximum;
}
