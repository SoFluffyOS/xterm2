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
}
