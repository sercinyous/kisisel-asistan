import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/settings/domain/privacy_text.dart';
import 'package:kisisel_asistan/features/settings/domain/terms_text.dart';

/// Markdown belgesini (## başlık + boş satırla ayrılmış paragraflar) bölümlere ayırır.
List<PrivacySection> _parse(String path) {
  final lines = File(path).readAsLinesSync();
  final sections = <PrivacySection>[];
  String? title;
  var paragraphs = <String>[];
  for (final line in lines) {
    if (line.startsWith('## ')) {
      if (title != null) sections.add(PrivacySection(title, paragraphs));
      title = line.substring(3).trim();
      paragraphs = <String>[];
    } else if (title != null && line.trim().isNotEmpty) {
      paragraphs.add(line.trim());
    }
  }
  if (title != null) sections.add(PrivacySection(title, paragraphs));
  return sections;
}

void _expectSame(String path, List<PrivacySection> app) {
  final doc = _parse(path);
  expect(doc.map((s) => s.title).toList(), app.map((s) => s.title).toList(),
      reason: '$path başlıkları uygulama metniyle aynı olmalı');
  for (var i = 0; i < app.length; i++) {
    expect(doc[i].paragraphs, app[i].paragraphs,
        reason: '$path "${app[i].title}" bölümü uygulama metniyle aynı olmalı');
  }
}

void main() {
  test('docs/gizlilik.md uygulama içi gizlilik metniyle aynı', () {
    _expectSame('docs/gizlilik.md', privacySections);
  });

  test('docs/kullanim_kosullari.md uygulama içi koşullarla aynı', () {
    _expectSame('docs/kullanim_kosullari.md', termsSections);
    final text = File('docs/kullanim_kosullari.md').readAsStringSync();
    expect(text.contains('geliştirme aşamasında'), isFalse);
  });
}
