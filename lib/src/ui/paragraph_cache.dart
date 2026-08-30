import 'dart:collection';
import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache {
  ParagraphCache(this.maximumSize) {
    if (maximumSize <= 0) {
      throw ArgumentError.value(maximumSize, 'maximumSize');
    }
  }

  final int maximumSize;

  final _cache = <Object, _CachedParagraph>{};
  final _recency = LinkedList<_CachedParagraph>();

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(Object key) {
    final entry = _cache[key];
    if (entry == null) return null;
    // Reordering links avoids deleting and reinserting a hash entry per glyph.
    if (!identical(_recency.last, entry)) {
      entry.unlink();
      _recency.add(entry);
    }
    return entry.paragraph;
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    Object key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final previous = _cache.remove(key);
    previous?.unlink();
    previous?.paragraph.dispose();
    final entry = _CachedParagraph(key, paragraph);
    _cache[key] = entry;
    _recency.add(entry);
    if (_cache.length > maximumSize) {
      final oldest = _recency.first;
      oldest.unlink();
      _cache.remove(oldest.key);
      oldest.paragraph.dispose();
    }
    return paragraph;
  }

  /// Clears the cache. This should be called when the same text and style
  /// pair no longer produces the same layout. For example, when a font is
  /// loaded.
  void clear() {
    for (final entry in _cache.values) {
      entry.paragraph.dispose();
    }
    _recency.clear();
    _cache.clear();
  }

  void dispose() {
    clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}

final class _CachedParagraph extends LinkedListEntry<_CachedParagraph> {
  _CachedParagraph(this.key, this.paragraph);

  final Object key;
  final Paragraph paragraph;
}
