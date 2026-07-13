import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/procedural_glyphs.dart';

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

  test('procedural glyphs do not bleed outside their cell', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      const Offset(10, 0),
      const Size(10, 10),
      0x2588,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 10);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected block image bytes');
    }

    int alphaAt(int x, int y) => bytes.getUint8((y * 30 + x) * 4 + 3);
    expect(alphaAt(9, 5), 0);
    expect(alphaAt(10, 5), greaterThan(0));
    expect(alphaAt(19, 5), greaterThan(0));
    expect(alphaAt(20, 5), 0);

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

  test('procedural glyph rendering covers dashed and diagonal box lines', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    const codePoints = [
      0x2504,
      0x2505,
      0x2506,
      0x2507,
      0x2508,
      0x2509,
      0x250a,
      0x250b,
      0x254c,
      0x254d,
      0x254e,
      0x254f,
      0x2571,
      0x2572,
      0x2573,
    ];

    for (final codePoint in codePoints) {
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

  test('procedural glyph rendering covers light and heavy box joins', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var codePoint = 0x250c; codePoint <= 0x254b; codePoint++) {
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

  test('procedural glyph rendering covers the full box drawing block', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var codePoint = 0x2500; codePoint <= 0x257f; codePoint++) {
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

    for (final x in [6, 14]) {
      for (final y in [6, 15, 24, 33]) {
        expect(_alphaNear(bytes, 20, 40, x, y), greaterThan(0));
      }
    }

    image.dispose();
    picture.dispose();
  });

  test('procedural glyph rendering covers powerline separators', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var codePoint = 0xe0b0; codePoint <= 0xe0bf; codePoint++) {
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

  test('procedural powerline triangle separators paint visible pixels',
      () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var index = 0; index < 8; index++) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset(index * 10, 0),
          const Size(10, 20),
          0xe0b8 + index,
          paint,
        ),
        isTrue,
        reason: 'U+${(0xe0b8 + index).toRadixString(16)}',
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 20);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected powerline image bytes');
    }

    for (var index = 0; index < 8; index++) {
      expect(
        _hasAnyAlphaInCell(bytes, 80, index * 10, 0, 10, 20),
        isTrue,
        reason: 'U+${(0xe0b8 + index).toRadixString(16)}',
      );
    }

    image.dispose();
    picture.dispose();
  });

  test('procedural glyph rendering covers prompt symbol glyphs', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    const codePoints = [
      0x00b0,
      0x2014,
      0x2190,
      0x2191,
      0x2192,
      0x2193,
      0x21b5,
      0x25a0,
      0x25b2,
      0x25b6,
      0x25bc,
      0x25c0,
      0x25c9,
      0x25cb,
      0x25cf,
      0x25e6,
      0x25ef,
      0x2713,
      0x279c,
    ];

    for (final codePoint in codePoints) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset.zero,
          const Size(20, 40),
          codePoint,
          paint,
        ),
        isTrue,
        reason: 'U+${codePoint.toRadixString(16)}',
      );
    }

    recorder.endRecording().dispose();
  });

  test('procedural prompt symbol glyphs paint visible pixels', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    expect(
      paintProceduralGlyph(
        canvas,
        Offset.zero,
        const Size(20, 40),
        0x279c,
        paint,
      ),
      isTrue,
    );
    expect(
      paintProceduralGlyph(
        canvas,
        const Offset(20, 0),
        const Size(20, 40),
        0x2713,
        paint,
      ),
      isTrue,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected prompt symbol image bytes');
    }

    expect(_hasAnyAlphaInCell(bytes, 40, 0, 0, 20, 40), isTrue);
    expect(_hasAnyAlphaInCell(bytes, 40, 20, 0, 20, 40), isTrue);

    image.dispose();
    picture.dispose();
  });

  test('procedural glyph rendering covers legacy computing blocks', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    final codePoints = <int>[
      for (var codePoint = 0x1fb00; codePoint <= 0x1fb3b; codePoint++)
        codePoint,
      for (var codePoint = 0x1fb82; codePoint <= 0x1fb8b; codePoint++)
        codePoint,
      for (var codePoint = 0x1cc1b; codePoint <= 0x1cc1e; codePoint++)
        codePoint,
      for (var codePoint = 0x1cc21; codePoint <= 0x1cc2f; codePoint++)
        codePoint,
      for (var codePoint = 0x1ce16; codePoint <= 0x1ce19; codePoint++)
        codePoint,
      for (var codePoint = 0x1ce51; codePoint <= 0x1ce8f; codePoint++)
        codePoint,
      for (var codePoint = 0x1ce90; codePoint <= 0x1ceaf; codePoint++)
        codePoint,
    ];

    for (final codePoint in codePoints) {
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

bool _hasAnyAlphaInCell(
  ByteData bytes,
  int imageWidth,
  int left,
  int top,
  int width,
  int height,
) {
  for (var y = top; y < top + height; y++) {
    for (var x = left; x < left + width; x++) {
      if (bytes.getUint8((y * imageWidth + x) * 4 + 3) != 0) {
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
