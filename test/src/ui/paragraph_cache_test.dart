import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/paragraph_cache.dart';

void main() {
  test('replacement, eviction and disposal release native paragraphs', () {
    final cache = ParagraphCache(2);
    const style = TextStyle();
    final first =
        cache.performAndCacheLayout('a', style, TextScaler.noScaling, ('a', 1));
    final replacement =
        cache.performAndCacheLayout('b', style, TextScaler.noScaling, ('a', 1));
    expect(first.debugDisposed, isTrue);
    expect(cache.getLayoutFromCache(('a', 1)), same(replacement));
    final second =
        cache.performAndCacheLayout('c', style, TextScaler.noScaling, ('c', 1));
    cache.getLayoutFromCache(('a', 1));
    cache.performAndCacheLayout('d', style, TextScaler.noScaling, ('d', 1));
    expect(second.debugDisposed, isTrue);
    expect(replacement.debugDisposed, isFalse);
    cache.dispose();
    expect(replacement.debugDisposed, isTrue);
  });

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
