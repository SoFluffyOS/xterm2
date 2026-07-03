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

bool paintProceduralGlyph(
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

  void fill(Rect rect) => canvas.drawRect(rect.inflate(overlap), paint);

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
      ..color = paint.color.withValues(alpha: paint.color.a * opacity);
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
    final dotWidth = max(1.0, width * 0.22);
    final dotHeight = max(1.0, height * 0.16);
    const dotColumns = [0, 0, 0, 1, 1, 1, 0, 1];
    const dotRows = [0, 1, 2, 0, 1, 2, 3, 3];

    for (var dot = 0; dot < 8; dot++) {
      if (dots & (1 << dot) == 0) {
        continue;
      }
      final centerX = x + width * (dotColumns[dot] * 0.5 + 0.25);
      final centerY = y + height * (dotRows[dot] * 0.25 + 0.125);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: dotWidth,
          height: dotHeight,
        ),
        paint,
      );
    }
    return true;
  }

  final thin = max(1.0, width * 0.12);
  final heavy = max(2.0, width * 0.22);
  final centerX = x + width / 2;
  final centerY = y + height / 2;

  void horizontal(double start, double end, double thickness) {
    fill(Rect.fromLTRB(
        start, centerY - thickness / 2, end, centerY + thickness / 2));
  }

  void vertical(double start, double end, double thickness) {
    fill(Rect.fromLTRB(
        centerX - thickness / 2, start, centerX + thickness / 2, end));
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

  switch (codePoint) {
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
    default:
      return false;
  }
}
