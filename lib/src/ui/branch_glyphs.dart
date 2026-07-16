import 'dart:math' show max, min;
import 'dart:ui';

const _branchArcSpecs = <(bool, bool, int)>[
  (false, false, 8),
  (false, false, 4),
  (false, false, 2),
  (false, false, 1),
  (false, true, 2),
  (false, true, 8),
  (false, false, 10),
  (false, true, 1),
  (false, true, 4),
  (false, false, 5),
  (true, false, 4),
  (true, false, 8),
  (false, false, 12),
  (true, false, 1),
  (true, false, 2),
  (false, false, 3),
  (false, true, 3),
  (false, true, 12),
  (true, false, 5),
  (true, false, 10),
  (false, true, 9),
  (false, true, 6),
  (true, false, 9),
  (true, false, 6),
];

const _branchNodeArms = <int>[
  0,
  2,
  8,
  10,
  4,
  1,
  5,
  6,
  12,
  3,
  9,
  7,
  13,
  14,
  11,
  15,
];

void paintBranchGlyph(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int codePoint,
  Paint paint,
) {
  final x = offset.dx;
  final y = offset.dy;
  final right = x + cellSize.width;
  final bottom = y + cellSize.height;
  final centerX = x + cellSize.width / 2;
  final centerY = y + cellSize.height / 2;
  final thickness = max(1.0, cellSize.width * 0.12);

  if (codePoint == 0xf5d0) {
    _paintHorizontal(canvas, x, right, centerY, thickness, paint);
    return;
  }
  if (codePoint == 0xf5d1) {
    _paintVertical(canvas, y, bottom, centerX, thickness, paint);
    return;
  }
  if (codePoint >= 0xf5d2 && codePoint <= 0xf5d5) {
    _paintFadingBranchLine(
      canvas,
      offset,
      cellSize,
      codePoint,
      thickness,
      paint,
    );
    return;
  }
  if (codePoint >= 0xf5d6 && codePoint <= 0xf5ed) {
    final (horizontal, vertical, arcs) = _branchArcSpecs[codePoint - 0xf5d6];
    final strokePaint = Paint()
      ..color = paint.color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    if (horizontal) {
      _paintHorizontal(canvas, x, right, centerY, thickness, paint);
    }
    if (vertical) {
      _paintVertical(canvas, y, bottom, centerX, thickness, paint);
    }
    for (var corner = 0; corner < 4; corner++) {
      if (arcs & (1 << corner) == 0) continue;
      _paintBranchArc(
        canvas,
        offset,
        cellSize,
        corner,
        strokePaint,
      );
    }
    return;
  }

  final nodeIndex = codePoint - 0xf5ee;
  _paintBranchNode(
    canvas,
    offset,
    cellSize,
    _branchNodeArms[nodeIndex ~/ 2],
    filled: nodeIndex.isEven,
    thickness: thickness,
    paint: paint,
  );
}

void _paintFadingBranchLine(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int codePoint,
  double thickness,
  Paint paint,
) {
  final x = offset.dx;
  final y = offset.dy;
  final right = x + cellSize.width;
  final bottom = y + cellSize.height;
  final centerX = x + cellSize.width / 2;
  final centerY = y + cellSize.height / 2;
  final transparent = paint.color.withValues(alpha: 0);
  final fadesFromStart = codePoint == 0xf5d2 || codePoint == 0xf5d4;
  final colors = switch (fadesFromStart) {
    true => [paint.color, transparent],
    false => [transparent, paint.color],
  };
  final isHorizontal = codePoint == 0xf5d2 || codePoint == 0xf5d3;
  final start = switch (isHorizontal) {
    true => Offset(x, centerY),
    false => Offset(centerX, y),
  };
  final end = switch (isHorizontal) {
    true => Offset(right, centerY),
    false => Offset(centerX, bottom),
  };
  final rect = switch (isHorizontal) {
    true => Rect.fromLTRB(
        x,
        centerY - thickness / 2,
        right,
        centerY + thickness / 2,
      ),
    false => Rect.fromLTRB(
        centerX - thickness / 2,
        y,
        centerX + thickness / 2,
        bottom,
      ),
  };
  canvas.drawRect(
    rect,
    Paint()..shader = Gradient.linear(start, end, colors),
  );
}

void _paintBranchArc(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int corner,
  Paint strokePaint,
) {
  final x = offset.dx;
  final y = offset.dy;
  final right = x + cellSize.width;
  final bottom = y + cellSize.height;
  final centerX = x + cellSize.width / 2;
  final centerY = y + cellSize.height / 2;
  final radius = min(cellSize.width, cellSize.height) / 2;
  const controlScale = 0.25;
  final path = Path();

  switch (corner) {
    case 0:
      path
        ..moveTo(centerX, y)
        ..lineTo(centerX, centerY - radius)
        ..cubicTo(
          centerX,
          centerY - controlScale * radius,
          centerX - controlScale * radius,
          centerY,
          centerX - radius,
          centerY,
        )
        ..lineTo(x, centerY);
      break;
    case 1:
      path
        ..moveTo(centerX, y)
        ..lineTo(centerX, centerY - radius)
        ..cubicTo(
          centerX,
          centerY - controlScale * radius,
          centerX + controlScale * radius,
          centerY,
          centerX + radius,
          centerY,
        )
        ..lineTo(right, centerY);
      break;
    case 2:
      path
        ..moveTo(centerX, bottom)
        ..lineTo(centerX, centerY + radius)
        ..cubicTo(
          centerX,
          centerY + controlScale * radius,
          centerX - controlScale * radius,
          centerY,
          centerX - radius,
          centerY,
        )
        ..lineTo(x, centerY);
      break;
    case 3:
      path
        ..moveTo(centerX, bottom)
        ..lineTo(centerX, centerY + radius)
        ..cubicTo(
          centerX,
          centerY + controlScale * radius,
          centerX + controlScale * radius,
          centerY,
          centerX + radius,
          centerY,
        )
        ..lineTo(right, centerY);
      break;
  }

  canvas.drawPath(path, strokePaint);
}

void _paintBranchNode(
  Canvas canvas,
  Offset offset,
  Size cellSize,
  int arms, {
  required bool filled,
  required double thickness,
  required Paint paint,
}) {
  final x = offset.dx;
  final y = offset.dy;
  final right = x + cellSize.width;
  final bottom = y + cellSize.height;
  final centerX = x + cellSize.width / 2;
  final centerY = y + cellSize.height / 2;
  final radius = min(cellSize.width, cellSize.height) / 2;
  final connection = radius - thickness / 2;

  if (arms & 1 != 0) {
    _paintVertical(
      canvas,
      y,
      centerY - connection,
      centerX,
      thickness,
      paint,
    );
  }
  if (arms & 2 != 0) {
    _paintHorizontal(
      canvas,
      centerX + connection,
      right,
      centerY,
      thickness,
      paint,
    );
  }
  if (arms & 4 != 0) {
    _paintVertical(
      canvas,
      centerY + connection,
      bottom,
      centerX,
      thickness,
      paint,
    );
  }
  if (arms & 8 != 0) {
    _paintHorizontal(
      canvas,
      x,
      centerX - connection,
      centerY,
      thickness,
      paint,
    );
  }

  final circleRadius = switch (filled) {
    true => radius,
    false => radius - thickness / 2,
  };
  if (filled) {
    canvas.drawCircle(Offset(centerX, centerY), circleRadius, paint);
    return;
  }
  canvas.drawCircle(
    Offset(centerX, centerY),
    circleRadius,
    Paint()
      ..color = paint.color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke,
  );
}

void _paintHorizontal(
  Canvas canvas,
  double start,
  double end,
  double y,
  double thickness,
  Paint paint,
) {
  if (end <= start) return;
  canvas.drawRect(
    Rect.fromLTRB(start, y - thickness / 2, end, y + thickness / 2),
    paint,
  );
}

void _paintVertical(
  Canvas canvas,
  double start,
  double end,
  double x,
  double thickness,
  Paint paint,
) {
  if (end <= start) return;
  canvas.drawRect(
    Rect.fromLTRB(x - thickness / 2, start, x + thickness / 2, end),
    paint,
  );
}
