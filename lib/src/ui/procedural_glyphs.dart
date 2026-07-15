import 'dart:math' show max, min;
import 'dart:ui';

const _singleLineBoxArms = <int>[
  0x44,
  0x48,
  0x84,
  0x88,
  0x41,
  0x42,
  0x81,
  0x82,
  0x14,
  0x18,
  0x24,
  0x28,
  0x11,
  0x12,
  0x21,
  0x22,
  0x54,
  0x58,
  0x64,
  0x94,
  0xa4,
  0x68,
  0x98,
  0xa8,
  0x51,
  0x52,
  0x61,
  0x91,
  0xa1,
  0x62,
  0x92,
  0xa2,
  0x45,
  0x46,
  0x49,
  0x4a,
  0x85,
  0x86,
  0x89,
  0x8a,
  0x15,
  0x16,
  0x19,
  0x1a,
  0x25,
  0x26,
  0x29,
  0x2a,
  0x55,
  0x56,
  0x59,
  0x5a,
  0x65,
  0x95,
  0xa5,
  0x66,
  0x69,
  0x96,
  0x99,
  0x6a,
  0x9a,
  0xa6,
  0xa9,
  0xaa,
];

const _doubleLineBoxArms = <int>[
  0x0a,
  0xa0,
  0x48,
  0x84,
  0x88,
  0x42,
  0x81,
  0x82,
  0x18,
  0x24,
  0x28,
  0x12,
  0x21,
  0x22,
  0x58,
  0xa4,
  0xa8,
  0x52,
  0xa1,
  0xa2,
  0x4a,
  0x85,
  0x8a,
  0x1a,
  0x25,
  0x2a,
  0x5a,
  0xa5,
  0xaa,
];

const _sextantMasks = <int>[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  43,
  44,
  45,
  46,
  47,
  48,
  49,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  58,
  59,
  60,
  61,
  62,
];

bool paintProceduralGlyph(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int codePoint,
  Paint paint,
) {
  if (!_isProceduralGlyph(codePoint)) {
    return false;
  }

  canvas.save();
  canvas.clipRect(offset & cellSize);
  final painted = _paintProceduralGlyph(
    canvas,
    offset,
    cellSize,
    codePoint,
    paint,
  );
  canvas.restore();
  return painted;
}

bool _paintProceduralGlyph(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int codePoint,
  Paint paint,
) {
  final x = offset.dx;
  final y = offset.dy;
  final width = cellSize.width;
  final height = cellSize.height;
  const overlap = 0.5;
  final fillPaint = Paint()
    ..color = paint.color
    ..isAntiAlias = false;

  void fill(Rect rect) => canvas.drawRect(rect.inflate(overlap), fillPaint);

  if (codePoint == 0x2588) {
    fill(Rect.fromLTWH(x, y, width, height));
    return true;
  }
  if (codePoint >= 0x2581 && codePoint <= 0x2587) {
    final fraction = (codePoint - 0x2580) / 8;
    fill(Rect.fromLTWH(
        x, y + height * (1 - fraction), width, height * fraction));
    return true;
  }
  if (codePoint == 0x2580 || codePoint == 0x2584) {
    var top = y + height / 2;
    if (codePoint == 0x2580) {
      top = y;
    }
    fill(Rect.fromLTWH(x, top, width, height / 2));
    return true;
  }
  if (codePoint >= 0x2589 && codePoint <= 0x258f) {
    final fraction = (0x2590 - codePoint) / 8;
    fill(Rect.fromLTWH(x, y, width * fraction, height));
    return true;
  }
  if (codePoint == 0x2590) {
    fill(Rect.fromLTWH(x + width / 2, y, width / 2, height));
    return true;
  }
  if (codePoint >= 0x2591 && codePoint <= 0x2593) {
    final opacity = (codePoint - 0x2590) / 4;
    final shadePaint = Paint()
      ..color = paint.color.withValues(alpha: paint.color.a * opacity)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(x, y, width, height), shadePaint);
    return true;
  }
  if (codePoint == 0x2594) {
    fill(Rect.fromLTWH(x, y, width, height / 8));
    return true;
  }
  if (codePoint == 0x2595) {
    fill(Rect.fromLTWH(x + width * 7 / 8, y, width / 8, height));
    return true;
  }
  if (codePoint >= 0x2596 && codePoint <= 0x259f) {
    const quadrantMasks = [4, 8, 1, 13, 9, 7, 11, 2, 6, 14];
    final quadrants = quadrantMasks[codePoint - 0x2596];
    final halfWidth = width / 2;
    final halfHeight = height / 2;

    if (quadrants & 1 != 0) {
      fill(Rect.fromLTWH(x, y, halfWidth, halfHeight));
    }
    if (quadrants & 2 != 0) {
      fill(Rect.fromLTWH(x + halfWidth, y, halfWidth, halfHeight));
    }
    if (quadrants & 4 != 0) {
      fill(Rect.fromLTWH(x, y + halfHeight, halfWidth, halfHeight));
    }
    if (quadrants & 8 != 0) {
      fill(Rect.fromLTWH(
        x + halfWidth,
        y + halfHeight,
        halfWidth,
        halfHeight,
      ));
    }
    return true;
  }
  if (codePoint >= 0x2800 && codePoint <= 0x28ff) {
    final dots = codePoint - 0x2800;
    final dotRadius = max(0.8, min(width * 0.12, height * 0.09));
    const dotColumns = [0, 0, 0, 1, 1, 1, 0, 1];
    const dotRows = [0, 1, 2, 0, 1, 2, 3, 3];
    const xPositions = [0.32, 0.68];
    const yPositions = [0.16, 0.38, 0.60, 0.82];

    for (var dot = 0; dot < 8; dot++) {
      if (dots & (1 << dot) == 0) {
        continue;
      }
      canvas.drawCircle(
        Offset(
          x + width * xPositions[dotColumns[dot]],
          y + height * yPositions[dotRows[dot]],
        ),
        dotRadius,
        paint,
      );
    }
    return true;
  }

  if (codePoint >= 0xe0b0 && codePoint <= 0xe0b3) {
    final pointsRight = codePoint == 0xe0b0 || codePoint == 0xe0b1;
    final isFilled = codePoint == 0xe0b0 || codePoint == 0xe0b2;
    final baseX = switch (pointsRight) {
      true => x,
      false => x + width,
    };
    final tipX = switch (pointsRight) {
      true => x + width,
      false => x,
    };
    final path = Path()
      ..moveTo(baseX, y)
      ..lineTo(tipX, y + height / 2)
      ..lineTo(baseX, y + height);
    if (isFilled) {
      path.close();
      canvas.drawPath(path, paint);
      return true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..strokeWidth = max(1.0, width * 0.12)
        ..style = PaintingStyle.stroke,
    );
    return true;
  }

  if (codePoint >= 0xe0b4 && codePoint <= 0xe0b7) {
    final opensRight = codePoint == 0xe0b4 || codePoint == 0xe0b5;
    final isFilled = codePoint == 0xe0b4 || codePoint == 0xe0b6;
    final center = Offset(
      switch (opensRight) {
        true => x,
        false => x + width,
      },
      y + height / 2,
    );
    final oval = Rect.fromCenter(
      center: center,
      width: width * 2,
      height: height,
    );
    if (isFilled) {
      canvas.drawOval(oval, paint);
      return true;
    }
    canvas.drawOval(
      oval,
      Paint()
        ..color = paint.color
        ..strokeWidth = max(1.0, width * 0.12)
        ..style = PaintingStyle.stroke,
    );
    return true;
  }

  if (codePoint >= 0xe0b8 && codePoint <= 0xe0bf) {
    final isBottom = codePoint <= 0xe0bb;
    final isLeftAligned = switch (codePoint) {
      0xe0b8 || 0xe0b9 || 0xe0bc || 0xe0bd => true,
      _ => false,
    };
    final isFilled = switch (codePoint) {
      0xe0b8 || 0xe0ba || 0xe0bc || 0xe0be => true,
      _ => false,
    };
    final path = Path();
    if (isBottom) {
      path
        ..moveTo(x, y + height)
        ..lineTo(x + width, y + height)
        ..lineTo(
          switch (isLeftAligned) {
            true => x,
            false => x + width,
          },
          y,
        );
    } else {
      path
        ..moveTo(x, y)
        ..lineTo(x + width, y)
        ..lineTo(
          switch (isLeftAligned) {
            true => x,
            false => x + width,
          },
          y + height,
        );
    }
    if (isFilled) {
      path.close();
      canvas.drawPath(path, paint);
      return true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..strokeWidth = max(1.0, width * 0.12)
        ..style = PaintingStyle.stroke,
    );
    return true;
  }

  if (codePoint == 0xe0d2 || codePoint == 0xe0d4) {
    final pointsRight = codePoint == 0xe0d2;
    final centerX = x + width / 2;
    final edgeX = switch (pointsRight) {
      true => x,
      false => x + width,
    };
    final otherEdgeX = switch (pointsRight) {
      true => x + width,
      false => x,
    };
    final gap = max(1.0, min(width, height) * 0.08);

    final topPath = Path()
      ..moveTo(edgeX, y)
      ..lineTo(otherEdgeX, y)
      ..lineTo(centerX, y + height / 2 - gap)
      ..lineTo(edgeX, y + height / 2 - gap)
      ..close();
    final bottomPath = Path()
      ..moveTo(edgeX, y + height)
      ..lineTo(otherEdgeX, y + height)
      ..lineTo(centerX, y + height / 2 + gap)
      ..lineTo(edgeX, y + height / 2 + gap)
      ..close();
    canvas
      ..drawPath(topPath, paint)
      ..drawPath(bottomPath, paint);
    return true;
  }

  if (codePoint >= 0x1fb00 && codePoint <= 0x1fb3b) {
    final sextants = _sextantMasks[codePoint - 0x1fb00];
    final halfWidth = width / 2;
    final thirdHeight = height / 3;
    for (var sextant = 0; sextant < 6; sextant++) {
      if (sextants & (1 << sextant) == 0) {
        continue;
      }
      final column = sextant & 1;
      final row = sextant >> 1;
      fill(Rect.fromLTWH(
        x + column * halfWidth,
        y + row * thirdHeight,
        halfWidth,
        thirdHeight,
      ));
    }
    return true;
  }

  if (codePoint >= 0x1fb82 && codePoint <= 0x1fb86) {
    const eighths = [2, 3, 5, 6, 7];
    final fraction = eighths[codePoint - 0x1fb82] / 8;
    fill(Rect.fromLTWH(x, y, width, height * fraction));
    return true;
  }

  if (codePoint >= 0x1fb87 && codePoint <= 0x1fb8b) {
    const eighths = [2, 3, 5, 6, 7];
    final fraction = eighths[codePoint - 0x1fb87] / 8;
    final blockWidth = width * fraction;
    fill(Rect.fromLTWH(x + width - blockWidth, y, blockWidth, height));
    return true;
  }

  if (codePoint >= 0x1fb7c && codePoint <= 0x1fb81) {
    final oneEighthWidth = width / 8;
    final oneEighthHeight = height / 8;
    switch (codePoint) {
      case 0x1fb7c:
        fill(Rect.fromLTWH(x, y, oneEighthWidth, height));
        fill(Rect.fromLTWH(
            x, y + height - oneEighthHeight, width, oneEighthHeight));
        return true;
      case 0x1fb7d:
        fill(Rect.fromLTWH(x, y, oneEighthWidth, height));
        fill(Rect.fromLTWH(x, y, width, oneEighthHeight));
        return true;
      case 0x1fb7e:
        fill(Rect.fromLTWH(
            x + width - oneEighthWidth, y, oneEighthWidth, height));
        fill(Rect.fromLTWH(x, y, width, oneEighthHeight));
        return true;
      case 0x1fb7f:
        fill(Rect.fromLTWH(
            x + width - oneEighthWidth, y, oneEighthWidth, height));
        fill(Rect.fromLTWH(
            x, y + height - oneEighthHeight, width, oneEighthHeight));
        return true;
      case 0x1fb80:
        fill(Rect.fromLTWH(x, y, width, oneEighthHeight));
        fill(Rect.fromLTWH(
            x, y + height - oneEighthHeight, width, oneEighthHeight));
        return true;
      case 0x1fb81:
        for (final eighth in [0, 2, 4, 7]) {
          fill(Rect.fromLTWH(
            x,
            y + height * eighth / 8,
            width,
            oneEighthHeight,
          ));
        }
        return true;
    }
  }

  if (codePoint >= 0x1fb8c && codePoint <= 0x1fb97) {
    final halfWidth = width / 2;
    final halfHeight = height / 2;
    final oneQuarterHeight = height / 4;
    final shadedPaint = Paint()
      ..color = paint.color.withValues(alpha: paint.color.a * 0.5);
    switch (codePoint) {
      case 0x1fb8c:
        canvas.drawRect(Rect.fromLTWH(x, y, halfWidth, height), shadedPaint);
        return true;
      case 0x1fb8d:
        canvas.drawRect(
          Rect.fromLTWH(x + halfWidth, y, halfWidth, height),
          shadedPaint,
        );
        return true;
      case 0x1fb8e:
        canvas.drawRect(Rect.fromLTWH(x, y, width, halfHeight), shadedPaint);
        return true;
      case 0x1fb8f:
        canvas.drawRect(
          Rect.fromLTWH(x, y + halfHeight, width, halfHeight),
          shadedPaint,
        );
        return true;
      case 0x1fb90:
        canvas.drawRect(Rect.fromLTWH(x, y, width, height), shadedPaint);
        return true;
      case 0x1fb91:
        canvas.drawRect(Rect.fromLTWH(x, y, width, height), shadedPaint);
        fill(Rect.fromLTWH(x, y, width, halfHeight));
        return true;
      case 0x1fb92:
        canvas.drawRect(Rect.fromLTWH(x, y, width, height), shadedPaint);
        fill(Rect.fromLTWH(x, y + halfHeight, width, halfHeight));
        return true;
      case 0x1fb93:
        return true;
      case 0x1fb94:
        canvas.drawRect(Rect.fromLTWH(x, y, width, height), shadedPaint);
        fill(Rect.fromLTWH(x + halfWidth, y, halfWidth, height));
        return true;
      case 0x1fb95:
      case 0x1fb96:
        final alternate = codePoint == 0x1fb96;
        final cellWidth = width / 2;
        final cellHeight = height / 2;
        for (var row = 0; row < 2; row++) {
          for (var column = 0; column < 2; column++) {
            final draw = ((row + column).isEven) != alternate;
            if (!draw) continue;
            fill(Rect.fromLTWH(
              x + column * cellWidth,
              y + row * cellHeight,
              cellWidth,
              cellHeight,
            ));
          }
        }
        return true;
      case 0x1fb97:
        fill(Rect.fromLTWH(x, y + oneQuarterHeight, width, oneQuarterHeight));
        fill(Rect.fromLTWH(
          x,
          y + oneQuarterHeight * 3,
          width,
          oneQuarterHeight,
        ));
        return true;
    }
  }

  final thin = max(1.0, width * 0.12);
  final heavy = max(2.0, width * 0.22);
  final centerX = x + width / 2;
  final centerY = y + height / 2;

  if (codePoint >= 0x1cc1b && codePoint <= 0x1cc1e) {
    switch (codePoint) {
      case 0x1cc1b:
        fill(Rect.fromLTRB(
          x,
          centerY - thin / 2,
          x + width,
          centerY + thin / 2,
        ));
        fill(Rect.fromLTRB(x + width - thin, y, x + width, centerY));
        return true;
      case 0x1cc1c:
        fill(Rect.fromLTRB(
          x,
          centerY - thin / 2,
          x + width,
          centerY + thin / 2,
        ));
        fill(Rect.fromLTRB(x + width - thin, centerY, x + width, y + height));
        return true;
      case 0x1cc1d:
        fill(Rect.fromLTRB(x, y, x + width, y + thin));
        fill(Rect.fromLTRB(x, y, x + thin, centerY));
        return true;
      case 0x1cc1e:
        fill(Rect.fromLTRB(x, y + height - thin, x + width, y + height));
        fill(Rect.fromLTRB(x, centerY, x + thin, y + height));
        return true;
    }
  }

  if (codePoint >= 0x1cc21 && codePoint <= 0x1cc2f) {
    final quadrants = codePoint - 0x1cc20;
    final gap = max(1.0, width / 12);
    final middleGapX = gap * 2 + width % 2;
    final middleGapY = gap * 2 + height % 2;
    final quadWidth = (width - gap * 2 - middleGapX) / 2;
    final quadHeight = (height - gap * 2 - middleGapY) / 2;
    final rightX = x + gap + quadWidth + middleGapX;
    final bottomY = y + gap + quadHeight + middleGapY;

    if (quadrants & 1 != 0) {
      fill(Rect.fromLTWH(x + gap, y + gap, quadWidth, quadHeight));
    }
    if (quadrants & 2 != 0) {
      fill(Rect.fromLTWH(rightX, y + gap, quadWidth, quadHeight));
    }
    if (quadrants & 4 != 0) {
      fill(Rect.fromLTWH(x + gap, bottomY, quadWidth, quadHeight));
    }
    if (quadrants & 8 != 0) {
      fill(Rect.fromLTWH(rightX, bottomY, quadWidth, quadHeight));
    }
    return true;
  }

  if (codePoint >= 0x1ce16 && codePoint <= 0x1ce19) {
    fill(Rect.fromLTRB(centerX - thin / 2, y, centerX + thin / 2, y + height));
    switch (codePoint) {
      case 0x1ce16:
        fill(Rect.fromLTRB(centerX, y, x + width, y + thin));
        return true;
      case 0x1ce17:
        fill(Rect.fromLTRB(centerX, y + height - thin, x + width, y + height));
        return true;
      case 0x1ce18:
        fill(Rect.fromLTRB(x, y, centerX, y + thin));
        return true;
      case 0x1ce19:
        fill(Rect.fromLTRB(x, y + height - thin, centerX, y + height));
        return true;
    }
  }

  if (codePoint >= 0x1ce51 && codePoint <= 0x1ce8f) {
    final sextants = codePoint - 0x1ce50;
    final gap = max(1.0, width / 12);
    final middleGapX = gap * 2 + width % 2;
    final yExtra = height % 3;
    final middleGapY = gap * 2 + (yExtra / 2).floorToDouble();
    final blockWidth = (width - gap * 2 - middleGapX) / 2;
    final topHeight = ((height - gap * 2 - middleGapY * 2) / 3).floorToDouble();
    final middleHeight = height - gap * 2 - middleGapY * 2 - topHeight * 2;
    final rightX = x + gap + blockWidth + middleGapX;
    final middleY = y + gap + topHeight + middleGapY;
    final bottomY = middleY + middleHeight + middleGapY;

    if (sextants & 1 != 0) {
      fill(Rect.fromLTWH(x + gap, y + gap, blockWidth, topHeight));
    }
    if (sextants & 2 != 0) {
      fill(Rect.fromLTWH(rightX, y + gap, blockWidth, topHeight));
    }
    if (sextants & 4 != 0) {
      fill(Rect.fromLTWH(x + gap, middleY, blockWidth, middleHeight));
    }
    if (sextants & 8 != 0) {
      fill(Rect.fromLTWH(rightX, middleY, blockWidth, middleHeight));
    }
    if (sextants & 16 != 0) {
      fill(Rect.fromLTWH(x + gap, bottomY, blockWidth, topHeight));
    }
    if (sextants & 32 != 0) {
      fill(Rect.fromLTWH(rightX, bottomY, blockWidth, topHeight));
    }
    return true;
  }

  if (codePoint >= 0x1ce90 && codePoint <= 0x1ceaf) {
    final index = codePoint - 0x1ce90;
    const rects = <(int, int, int, int)>[
      (0, 1, 0, 1),
      (1, 2, 0, 1),
      (2, 3, 0, 1),
      (3, 4, 0, 1),
      (0, 1, 1, 2),
      (1, 2, 1, 2),
      (2, 3, 1, 2),
      (3, 4, 1, 2),
      (0, 1, 2, 3),
      (1, 2, 2, 3),
      (2, 3, 2, 3),
      (3, 4, 2, 3),
      (0, 1, 3, 4),
      (1, 2, 3, 4),
      (2, 3, 3, 4),
      (3, 4, 3, 4),
      (2, 4, 3, 4),
      (1, 4, 3, 4),
      (0, 3, 3, 4),
      (0, 2, 3, 4),
      (0, 1, 2, 4),
      (0, 1, 1, 4),
      (0, 1, 0, 3),
      (0, 1, 0, 2),
      (0, 2, 0, 1),
      (0, 3, 0, 1),
      (1, 4, 0, 1),
      (2, 4, 0, 1),
      (3, 4, 0, 2),
      (3, 4, 0, 3),
      (3, 4, 1, 4),
      (3, 4, 2, 4),
    ];
    final rect = rects[index];
    fill(Rect.fromLTRB(
      x + width * rect.$1 / 4,
      y + height * rect.$3 / 4,
      x + width * rect.$2 / 4,
      y + height * rect.$4 / 4,
    ));
    return true;
  }

  final symbolStrokePaint = Paint()
    ..color = paint.color
    ..strokeWidth = max(1.0, min(width, height) * 0.12)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void path(List<Offset> points, {bool close = false}) {
    if (points.isEmpty) {
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) {
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  void strokePath(List<Offset> points) {
    if (points.isEmpty) {
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, symbolStrokePaint);
  }

  void line(Offset start, Offset end) {
    canvas.drawLine(start, end, symbolStrokePaint);
  }

  void circle(double diameterScale, {bool filled = false}) {
    final diameter = min(width, height) * diameterScale;
    final circleRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: diameter,
      height: diameter,
    );
    if (filled) {
      canvas.drawOval(circleRect, paint);
      return;
    }
    canvas.drawOval(
      circleRect,
      Paint()
        ..color = paint.color
        ..strokeWidth = max(1.0, diameter * 0.12)
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );
  }

  void horizontal(double start, double end, double thickness) {
    fill(Rect.fromLTRB(
        start, centerY - thickness / 2, end, centerY + thickness / 2));
  }

  void horizontalAt(
    double start,
    double end,
    double lineY,
    double thickness,
  ) {
    fill(Rect.fromLTRB(
      start,
      lineY - thickness / 2,
      end,
      lineY + thickness / 2,
    ));
  }

  void vertical(double start, double end, double thickness) {
    fill(Rect.fromLTRB(
        centerX - thickness / 2, start, centerX + thickness / 2, end));
  }

  void verticalAt(
    double start,
    double end,
    double lineX,
    double thickness,
  ) {
    fill(Rect.fromLTRB(
      lineX - thickness / 2,
      start,
      lineX + thickness / 2,
      end,
    ));
  }

  void dashedHorizontal(int gaps, double thickness) {
    final gap = max(1.0, width / 8);
    final dash = max(1.0, (width - gap * gaps) / (gaps + 1));
    for (var segment = 0; segment <= gaps; segment++) {
      final start = x + segment * (dash + gap);
      horizontal(start, min(x + width, start + dash), thickness);
    }
  }

  void dashedVertical(int gaps, double thickness) {
    final gap = max(1.0, height / 8);
    final dash = max(1.0, (height - gap * gaps) / (gaps + 1));
    for (var segment = 0; segment <= gaps; segment++) {
      final start = y + segment * (dash + gap);
      vertical(start, min(y + height, start + dash), thickness);
    }
  }

  if (codePoint >= 0x250c && codePoint <= 0x254b) {
    final arms = _singleLineBoxArms[codePoint - 0x250c];
    double thickness(int shift) {
      return switch ((arms >> shift) & 3) {
        1 => thin,
        2 => heavy,
        _ => 0,
      };
    }

    final left = thickness(0);
    final right = thickness(2);
    final top = thickness(4);
    final bottom = thickness(6);
    if (left > 0) {
      horizontal(x, centerX, left);
    }
    if (right > 0) {
      horizontal(centerX, x + width, right);
    }
    if (top > 0) {
      vertical(y, centerY, top);
    }
    if (bottom > 0) {
      vertical(centerY, y + height, bottom);
    }
    return true;
  }

  if (codePoint >= 0x2550 && codePoint <= 0x256c) {
    final arms = _doubleLineBoxArms[codePoint - 0x2550];
    final doubleOffset = max(1.0, thin * 1.5);

    void horizontalArm(double start, double end, int shift) {
      final style = (arms >> shift) & 3;
      if (style == 1) {
        horizontal(start, end, thin);
        return;
      }
      if (style == 2) {
        horizontalAt(start, end, centerY - doubleOffset, thin);
        horizontalAt(start, end, centerY + doubleOffset, thin);
      }
    }

    void verticalArm(double start, double end, int shift) {
      final style = (arms >> shift) & 3;
      if (style == 1) {
        vertical(start, end, thin);
        return;
      }
      if (style == 2) {
        verticalAt(start, end, centerX - doubleOffset, thin);
        verticalAt(start, end, centerX + doubleOffset, thin);
      }
    }

    horizontalArm(x, centerX + doubleOffset, 0);
    horizontalArm(centerX - doubleOffset, x + width, 2);
    verticalArm(y, centerY + doubleOffset, 4);
    verticalArm(centerY - doubleOffset, y + height, 6);
    return true;
  }

  switch (codePoint) {
    case 0x00b0:
      circle(0.42);
      return true;
    case 0x2014:
      line(
        Offset(x + width * 0.12, centerY),
        Offset(x + width * 0.88, centerY),
      );
      return true;
    case 0x2190:
      line(
        Offset(x + width * 0.82, centerY),
        Offset(x + width * 0.22, centerY),
      );
      line(
        Offset(x + width * 0.40, centerY - height * 0.18),
        Offset(x + width * 0.22, centerY),
      );
      line(
        Offset(x + width * 0.40, centerY + height * 0.18),
        Offset(x + width * 0.22, centerY),
      );
      return true;
    case 0x2191:
      line(
        Offset(centerX, y + height * 0.82),
        Offset(centerX, y + height * 0.22),
      );
      line(
        Offset(centerX - width * 0.18, y + height * 0.40),
        Offset(centerX, y + height * 0.22),
      );
      line(
        Offset(centerX + width * 0.18, y + height * 0.40),
        Offset(centerX, y + height * 0.22),
      );
      return true;
    case 0x2192:
      line(
        Offset(x + width * 0.18, centerY),
        Offset(x + width * 0.78, centerY),
      );
      line(
        Offset(x + width * 0.60, centerY - height * 0.18),
        Offset(x + width * 0.78, centerY),
      );
      line(
        Offset(x + width * 0.60, centerY + height * 0.18),
        Offset(x + width * 0.78, centerY),
      );
      return true;
    case 0x2193:
      line(
        Offset(centerX, y + height * 0.18),
        Offset(centerX, y + height * 0.78),
      );
      line(
        Offset(centerX - width * 0.18, y + height * 0.60),
        Offset(centerX, y + height * 0.78),
      );
      line(
        Offset(centerX + width * 0.18, y + height * 0.60),
        Offset(centerX, y + height * 0.78),
      );
      return true;
    case 0x21b5:
      final hookX = x + width * 0.74;
      final hookY = centerY + height * 0.18;
      line(Offset(x + width * 0.16, centerY), Offset(hookX, centerY));
      line(Offset(hookX, y + height * 0.22), Offset(hookX, hookY));
      line(
        Offset(hookX, hookY),
        Offset(hookX - width * 0.18, hookY - height * 0.16),
      );
      line(
        Offset(hookX, hookY),
        Offset(hookX - width * 0.18, hookY + height * 0.16),
      );
      return true;
    case 0x25a0:
      canvas.drawRect(
        Rect.fromLTWH(
            x + width * 0.2, y + height * 0.2, width * 0.6, height * 0.6),
        paint,
      );
      return true;
    case 0x25b2:
      path([
        Offset(centerX, y + height * 0.2),
        Offset(x + width * 0.22, y + height * 0.72),
        Offset(x + width * 0.78, y + height * 0.72),
      ], close: true);
      return true;
    case 0x25b6:
      path([
        Offset(x + width * 0.8, centerY),
        Offset(x + width * 0.28, y + height * 0.22),
        Offset(x + width * 0.28, y + height * 0.78),
      ], close: true);
      return true;
    case 0x25bc:
      path([
        Offset(centerX, y + height * 0.8),
        Offset(x + width * 0.22, y + height * 0.28),
        Offset(x + width * 0.78, y + height * 0.28),
      ], close: true);
      return true;
    case 0x25c9:
    case 0x25cf:
      circle(0.58, filled: true);
      return true;
    case 0x25c0:
      path([
        Offset(x + width * 0.2, centerY),
        Offset(x + width * 0.72, y + height * 0.22),
        Offset(x + width * 0.72, y + height * 0.78),
      ], close: true);
      return true;
    case 0x25cb:
    case 0x25ef:
      circle(0.88);
      return true;
    case 0x25e6:
      circle(0.4);
      return true;
    case 0x2713:
      strokePath([
        Offset(x + width * 0.18, y + height * 0.56),
        Offset(x + width * 0.42, y + height * 0.78),
        Offset(x + width * 0.84, y + height * 0.24),
      ]);
      return true;
    case 0x279c:
      path([
        Offset(x + width * 0.82, centerY),
        Offset(x + width * 0.28, y + height * 0.18),
        Offset(x + width * 0.48, centerY),
        Offset(x + width * 0.28, y + height * 0.82),
      ], close: true);
      return true;
    case 0x2500:
      horizontal(x, x + width, thin);
      return true;
    case 0x2501:
      horizontal(x, x + width, heavy);
      return true;
    case 0x2502:
      vertical(y, y + height, thin);
      return true;
    case 0x2503:
      vertical(y, y + height, heavy);
      return true;
    case 0x2504:
      dashedHorizontal(2, thin);
      return true;
    case 0x2505:
      dashedHorizontal(2, heavy);
      return true;
    case 0x2506:
      dashedVertical(2, thin);
      return true;
    case 0x2507:
      dashedVertical(2, heavy);
      return true;
    case 0x2508:
      dashedHorizontal(3, thin);
      return true;
    case 0x2509:
      dashedHorizontal(3, heavy);
      return true;
    case 0x250a:
      dashedVertical(3, thin);
      return true;
    case 0x250b:
      dashedVertical(3, heavy);
      return true;
    case 0x254c:
      dashedHorizontal(1, thin);
      return true;
    case 0x254d:
      dashedHorizontal(1, heavy);
      return true;
    case 0x254e:
      dashedVertical(1, thin);
      return true;
    case 0x254f:
      dashedVertical(1, heavy);
      return true;
    case 0x256d:
    case 0x256e:
    case 0x256f:
    case 0x2570:
      final isRight = codePoint == 0x256d || codePoint == 0x2570;
      final isDown = codePoint == 0x256d || codePoint == 0x256e;
      final horizontalX = switch (isRight) {
        true => x + width,
        false => x,
      };
      final verticalY = switch (isDown) {
        true => y + height,
        false => y,
      };
      final horizontalEnd = Offset(horizontalX, centerY);
      final verticalEnd = Offset(centerX, verticalY);
      final arcPath = Path()
        ..moveTo(horizontalEnd.dx, horizontalEnd.dy)
        ..quadraticBezierTo(centerX, centerY, verticalEnd.dx, verticalEnd.dy);
      canvas.drawPath(
        arcPath,
        Paint()
          ..color = paint.color
          ..strokeWidth = thin
          ..style = PaintingStyle.stroke,
      );
      return true;
    case 0x2571:
    case 0x2572:
    case 0x2573:
      final strokePaint = Paint()
        ..color = paint.color
        ..strokeWidth = thin
        ..style = PaintingStyle.stroke;
      if (codePoint == 0x2571 || codePoint == 0x2573) {
        canvas.drawLine(
          Offset(x, y + height),
          Offset(x + width, y),
          strokePaint,
        );
      }
      if (codePoint == 0x2572 || codePoint == 0x2573) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + width, y + height),
          strokePaint,
        );
      }
      return true;
    case 0x2574:
      horizontal(x, centerX, thin);
      return true;
    case 0x2575:
      vertical(y, centerY, thin);
      return true;
    case 0x2576:
      horizontal(centerX, x + width, thin);
      return true;
    case 0x2577:
      vertical(centerY, y + height, thin);
      return true;
    case 0x2578:
      horizontal(x, centerX, heavy);
      return true;
    case 0x2579:
      vertical(y, centerY, heavy);
      return true;
    case 0x257a:
      horizontal(centerX, x + width, heavy);
      return true;
    case 0x257b:
      vertical(centerY, y + height, heavy);
      return true;
    case 0x257c:
      horizontal(x, centerX, thin);
      horizontal(centerX, x + width, heavy);
      return true;
    case 0x257d:
      vertical(y, centerY, thin);
      vertical(centerY, y + height, heavy);
      return true;
    case 0x257e:
      horizontal(x, centerX, heavy);
      horizontal(centerX, x + width, thin);
      return true;
    case 0x257f:
      vertical(y, centerY, heavy);
      vertical(centerY, y + height, thin);
      return true;
    default:
      return false;
  }
}

@pragma('vm:prefer-inline')
bool _isProceduralGlyph(int codePoint) {
  if (_isTerminalSymbolGlyph(codePoint)) {
    return true;
  }
  if (codePoint >= 0x2500 && codePoint <= 0x259f) {
    return true;
  }
  if (codePoint >= 0x2800 && codePoint <= 0x28ff) {
    return true;
  }
  if (codePoint >= 0xe0b0 && codePoint <= 0xe0bf) {
    return true;
  }
  if (codePoint == 0xe0d2 || codePoint == 0xe0d4) {
    return true;
  }
  if (codePoint >= 0x1fb00 && codePoint <= 0x1fb3b) {
    return true;
  }
  if (codePoint >= 0x1fb7c && codePoint <= 0x1fb97) {
    return true;
  }
  if (codePoint >= 0x1cc1b && codePoint <= 0x1cc1e) {
    return true;
  }
  if (codePoint >= 0x1cc21 && codePoint <= 0x1cc2f) {
    return true;
  }
  if (codePoint >= 0x1ce16 && codePoint <= 0x1ce19) {
    return true;
  }
  if (codePoint >= 0x1ce51 && codePoint <= 0x1ce8f) {
    return true;
  }
  if (codePoint >= 0x1ce90 && codePoint <= 0x1ceaf) {
    return true;
  }
  return false;
}

bool _isTerminalSymbolGlyph(int codePoint) {
  return switch (codePoint) {
    0x00b0 ||
    0x2014 ||
    0x2190 ||
    0x2191 ||
    0x2192 ||
    0x2193 ||
    0x21b5 ||
    0x25a0 ||
    0x25b2 ||
    0x25b6 ||
    0x25bc ||
    0x25c0 ||
    0x25c9 ||
    0x25cb ||
    0x25cf ||
    0x25e6 ||
    0x25ef ||
    0x2713 ||
    0x279c =>
      true,
    _ => false,
  };
}
