import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';

void main() {
  test('ParagraphCache evicts the least recently used layout', () {
    final cache = ParagraphCache(2);
    const style = TextStyle();

    cache.performAndCacheLayout('a', style, TextScaler.noScaling, 1);
    cache.performAndCacheLayout('b', style, TextScaler.noScaling, 2);
    expect(cache.getLayoutFromCache(1), isNotNull);

    cache.performAndCacheLayout('c', style, TextScaler.noScaling, 3);

    expect(cache.length, 2);
    expect(cache.getLayoutFromCache(1), isNotNull);
    expect(cache.getLayoutFromCache(2), isNull);
    expect(cache.getLayoutFromCache(3), isNotNull);

    cache.dispose();
    expect(cache.length, 0);
  });
}
