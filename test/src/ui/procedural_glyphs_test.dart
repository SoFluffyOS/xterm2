import 'dart:math' show max, sqrt;
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

  test('rounded box corners match adjoining line weight', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    const corners = [0x256d, 0x256e, 0x256f, 0x2570];

    for (var index = 0; index < corners.length; index++) {
      final x = index * 20.0;
      paintProceduralGlyph(
        canvas,
        Offset(x, 0),
        const Size(20, 40),
        corners[index],
        paint,
      );
      paintProceduralGlyph(
        canvas,
        Offset(x, 40),
        const Size(20, 40),
        0x2502,
        paint,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 80);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected rounded-corner image bytes');
    }

    for (var index = 0; index < corners.length; index++) {
      final cornerY = switch (corners[index]) {
        0x256d || 0x256e => 35,
        _ => 5,
      };
      final x = index * 20;
      final cornerWeight = _alphaInRow(bytes, 80, cornerY, x, 20);
      final lineWeight = _alphaInRow(bytes, 80, 60, x, 20);
      expect(
        cornerWeight,
        closeTo(lineWeight, 255),
        reason: 'U+${corners[index].toRadixString(16)}',
      );
    }

    image.dispose();
    picture.dispose();
  });

  test('diagonal box lines match straight line weight', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      Offset.zero,
      const Size(20, 40),
      0x2500,
      paint,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(20, 0),
      const Size(20, 40),
      0x2571,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected diagonal-line image bytes');
    }

    final straightWeight = _alphaInRegion(bytes, 40, 0, 0, 20, 40) / 20;
    final diagonalLength = sqrt(20 * 20 + 40 * 40);
    final diagonalWeight =
        _alphaInRegion(bytes, 40, 20, 0, 20, 40) / diagonalLength;
    expect(diagonalWeight, closeTo(straightWeight, 255));

    image.dispose();
    picture.dispose();
  });

  test('heavy box lines are twice the light line weight', () async {
    const sizes = [Size(8, 16), Size(10, 20), Size(12, 24), Size(20, 40)];
    const linePairs = [(0x2500, 0x2501), (0x2502, 0x2503)];

    for (final size in sizes) {
      for (final (light, heavy) in linePairs) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        final paint = Paint()..color = const Color(0xffffffff);
        paintProceduralGlyph(canvas, Offset.zero, size, light, paint);
        paintProceduralGlyph(
          canvas,
          Offset(size.width, 0),
          size,
          heavy,
          paint,
        );

        final picture = recorder.endRecording();
        final imageWidth = (size.width * 2).round();
        final imageHeight = size.height.round();
        final image = await picture.toImage(imageWidth, imageHeight);
        final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        if (bytes == null) {
          fail('Expected heavy-line image bytes');
        }

        final cellWidth = size.width.round();
        final lightWeight =
            _alphaInRegion(bytes, imageWidth, 0, 0, cellWidth, imageHeight);
        final heavyWeight = _alphaInRegion(
          bytes,
          imageWidth,
          cellWidth,
          0,
          cellWidth,
          imageHeight,
        );
        final lineLength = switch (light) {
          0x2500 => cellWidth,
          _ => imageHeight,
        };
        expect(
          heavyWeight,
          closeTo(lightWeight * 2, lineLength * 255),
          reason: '${size.width}x${size.height} U+${heavy.toRadixString(16)}',
        );

        image.dispose();
        picture.dispose();
      }
    }
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

  test('procedural glyph rendering covers corner triangles', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    const codePoints = [
      0x25e2,
      0x25e3,
      0x25e4,
      0x25e5,
      0x25f8,
      0x25f9,
      0x25fa,
      0x25ff,
    ];

    for (var index = 0; index < codePoints.length; index++) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset(index * 20, 0),
          const Size(20, 40),
          codePoints[index],
          paint,
        ),
        isTrue,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(codePoints.length * 20, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected corner-triangle image bytes');
    }

    for (var index = 0; index < codePoints.length; index++) {
      expect(
        _hasAnyAlphaInCell(
            bytes, codePoints.length * 20, index * 20, 0, 20, 40),
        isTrue,
        reason: 'U+${codePoints[index].toRadixString(16)}',
      );
    }

    image.dispose();
    picture.dispose();
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

    final codePoints = [
      for (var codePoint = 0xe0b0; codePoint <= 0xe0bf; codePoint++) codePoint,
      0xe0d2,
      0xe0d4,
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

  test('procedural glyph rendering covers branch graph sprites', () async {
    const firstCodePoint = 0xf5d0;
    const lastCodePoint = 0xf60d;
    const cellWidth = 20;
    const cellHeight = 40;
    const glyphCount = lastCodePoint - firstCodePoint + 1;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    for (var index = 0; index < glyphCount; index++) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset((index * cellWidth).toDouble(), 0),
          const Size(20, 40),
          firstCodePoint + index,
          paint,
        ),
        isTrue,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(glyphCount * cellWidth, cellHeight);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected branch graph image bytes');
    }

    for (var index = 0; index < glyphCount; index++) {
      expect(
        _hasAnyAlphaInCell(
          bytes,
          glyphCount * cellWidth,
          index * cellWidth,
          0,
          cellWidth,
          cellHeight,
        ),
        isTrue,
        reason: 'U+${(firstCodePoint + index).toRadixString(16)}',
      );
    }

    image.dispose();
    picture.dispose();
  });

  test('procedural branch graph sprites fade and distinguish nodes', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      Offset.zero,
      const Size(20, 40),
      0xf5d2,
      paint,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(20, 0),
      const Size(20, 40),
      0xf5ee,
      paint,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(40, 0),
      const Size(20, 40),
      0xf5ef,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(60, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected branch graph detail image bytes');
    }

    int alphaAt(int x, int y) => bytes.getUint8((y * 60 + x) * 4 + 3);
    expect(alphaAt(1, 20), greaterThan(alphaAt(18, 20)));
    expect(alphaAt(30, 20), greaterThan(0));
    expect(alphaAt(50, 20), 0);

    image.dispose();
    picture.dispose();
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

  test('procedural extended powerline separators paint visible pixels',
      () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);
    const codePoints = [0xe0d2, 0xe0d4];

    for (var index = 0; index < codePoints.length; index++) {
      expect(
        paintProceduralGlyph(
          canvas,
          Offset(index * 10, 0),
          const Size(10, 20),
          codePoints[index],
          paint,
        ),
        isTrue,
        reason: 'U+${codePoints[index].toRadixString(16)}',
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(20, 20);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected extended powerline image bytes');
    }

    for (var index = 0; index < codePoints.length; index++) {
      expect(
        _hasAnyAlphaInCell(bytes, 20, index * 10, 0, 10, 20),
        isTrue,
        reason: 'U+${codePoints[index].toRadixString(16)}',
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
      for (var codePoint = 0x1fb00; codePoint <= 0x1fbaf; codePoint++)
        codePoint,
      for (var codePoint = 0x1fbbd; codePoint <= 0x1fbbf; codePoint++)
        codePoint,
      for (var codePoint = 0x1fbce; codePoint <= 0x1fbef; codePoint++)
        codePoint,
      for (var codePoint = 0x1cc1b; codePoint <= 0x1cc1e; codePoint++)
        codePoint,
      for (var codePoint = 0x1cc21; codePoint <= 0x1cc2f; codePoint++)
        codePoint,
      for (var codePoint = 0x1cc30; codePoint <= 0x1cc3f; codePoint++)
        codePoint,
      for (var codePoint = 0x1cd00; codePoint <= 0x1cde5; codePoint++)
        codePoint,
      0x1ce00,
      0x1ce01,
      0x1ce0b,
      0x1ce0c,
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

  test('procedural extended legacy glyphs paint visible pixels', () async {
    final glyphs = <int>[
      0x1fb3c,
      0x1fb41,
      0x1fb52,
      0x1fb67,
      0x1fb68,
      0x1fb6c,
      0x1fb70,
      0x1fb76,
      0x1fb98,
      0x1fb99,
      0x1fb9a,
      0x1fb9c,
      0x1fba0,
      0x1fbae,
      0x1fbaf,
      0x1fbbd,
      0x1fbbf,
      0x1fbce,
      0x1fbcf,
      0x1fbd0,
      0x1fbdf,
      0x1fbe0,
      0x1fbe4,
      0x1fbe8,
      0x1fbef,
      for (var codePoint = 0x1cc30; codePoint <= 0x1cc3f; codePoint++)
        codePoint,
      0x1ce00,
      0x1ce01,
      0x1ce0b,
      0x1ce0c,
    ];

    for (final codePoint in glyphs) {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = const Color(0xffffffff);
      expect(
        paintProceduralGlyph(
          canvas,
          Offset.zero,
          const Size(20, 40),
          codePoint,
          paint,
        ),
        isTrue,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 40);
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (bytes == null) {
        fail('Expected legacy glyph image bytes');
      }
      expect(
        _hasAnyAlpha(bytes, 20, 40),
        isTrue,
        reason: 'U+${codePoint.toRadixString(16)}',
      );
      image.dispose();
      picture.dispose();
    }
  });

  test('procedural negative legacy glyphs carve transparent lines', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      Offset.zero,
      const Size(20, 40),
      0x1fbbd,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(20, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected negative legacy glyph image bytes');
    }

    int alphaAt(int x, int y) => bytes.getUint8((y * 20 + x) * 4 + 3);
    expect(alphaAt(10, 20), 0);
    expect(alphaAt(10, 5), greaterThan(0));

    image.dispose();
    picture.dispose();
  });

  test('procedural octants follow the Unicode 17 cell grid', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      Offset.zero,
      const Size(20, 40),
      0x1cd00,
      paint,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(20, 0),
      const Size(20, 40),
      0x1cde5,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected octant glyph image bytes');
    }

    int alphaAt(int x, int y) => bytes.getUint8((y * 40 + x) * 4 + 3);
    expect(alphaAt(5, 5), 0);
    expect(alphaAt(5, 15), greaterThan(0));
    expect(alphaAt(15, 15), 0);
    expect(alphaAt(25, 5), 0);
    expect(alphaAt(35, 5), greaterThan(0));
    expect(alphaAt(25, 15), greaterThan(0));

    image.dispose();
    picture.dispose();
  });

  test('procedural circle pieces join across cell boundaries', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xffffffff);

    paintProceduralGlyph(
      canvas,
      Offset.zero,
      const Size(20, 40),
      0x1cc30,
      paint,
    );
    paintProceduralGlyph(
      canvas,
      const Offset(20, 0),
      const Size(20, 40),
      0x1cc31,
      paint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 40);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null) {
      fail('Expected circle-piece image bytes');
    }

    int alphaAt(int x, int y) => bytes.getUint8((y * 40 + x) * 4 + 3);
    expect(alphaAt(19, 11), greaterThan(0));
    expect(alphaAt(20, 11), greaterThan(0));

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

int _alphaInRow(ByteData bytes, int imageWidth, int y, int x, int width) {
  var alpha = 0;
  for (var column = x; column < x + width; column++) {
    alpha += bytes.getUint8((y * imageWidth + column) * 4 + 3);
  }
  return alpha;
}

int _alphaInRegion(
  ByteData bytes,
  int imageWidth,
  int x,
  int y,
  int width,
  int height,
) {
  var alpha = 0;
  for (var row = y; row < y + height; row++) {
    alpha += _alphaInRow(bytes, imageWidth, row, x, width);
  }
  return alpha;
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
