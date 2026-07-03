import 'dart:math' show max;
import 'dart:ui';

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
    case 0x250c:
      horizontal(centerX, x + width, thin);
      vertical(centerY, y + height, thin);
      return true;
    case 0x2510:
      horizontal(x, centerX, thin);
      vertical(centerY, y + height, thin);
      return true;
    case 0x2514:
      horizontal(centerX, x + width, thin);
      vertical(y, centerY, thin);
      return true;
    case 0x2518:
      horizontal(x, centerX, thin);
      vertical(y, centerY, thin);
      return true;
    case 0x251c:
      horizontal(centerX, x + width, thin);
      vertical(y, y + height, thin);
      return true;
    case 0x2524:
      horizontal(x, centerX, thin);
      vertical(y, y + height, thin);
      return true;
    case 0x252c:
      horizontal(x, x + width, thin);
      vertical(centerY, y + height, thin);
      return true;
    case 0x2534:
      horizontal(x, x + width, thin);
      vertical(y, centerY, thin);
      return true;
    case 0x253c:
      horizontal(x, x + width, thin);
      vertical(y, y + height, thin);
      return true;
    default:
      return false;
  }
}
