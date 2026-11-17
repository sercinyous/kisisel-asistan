import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/goal_rules.dart';

/// SQL ↔ Dart eşlik testi (Faz 4B). `supabase/tests/goal_vectors.json`
/// dosyasını `supabase/tests/goal_parity_test.sql` de okur: orada
/// `goal_steps_hit` / `goal_sleep_hit` / `goal_calories_hit` ve uçtan uca
/// `friend_goal_summary` aynı vektörlerle sınanır. Burada `GoalRules` aynı
/// vektörlerle sınanır; bir taraf eşiği kaydırırsa ilgili test kırılır.
void main() {
  final file = File('supabase/tests/goal_vectors.json');
  final vectors = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  List<Map<String, dynamic>> rowsOf(String metric) =>
      (vectors[metric] as List).cast<Map<String, dynamic>>();

  group('SQL eşliği: goal_vectors.json', () {
    test('vektör dosyası üç metriği de kapsar ve tutan/tutmayan örnek içerir', () {
      for (final metric in ['steps', 'sleep', 'calories']) {
        final rows = rowsOf(metric);
        expect(rows.where((r) => r['hit'] == true), isNotEmpty, reason: metric);
        expect(rows.where((r) => r['hit'] == false), isNotEmpty, reason: metric);
      }
    });

    test('adım: GoalRules.stepsHit vektörlerle aynı', () {
      for (final v in rowsOf('steps')) {
        final got = GoalRules.stepsHit(
          (v['value'] as num).toInt(),
          (v['target'] as num).toInt(),
        );
        expect(got, v['hit'], reason: 'stepsHit $v');
      }
    });

    test('uyku: GoalRules.sleepHit vektörlerle aynı', () {
      for (final v in rowsOf('sleep')) {
        final got = GoalRules.sleepHit(
          (v['value'] as num).toInt(),
          (v['target'] as num).toInt(),
        );
        expect(got, v['hit'], reason: 'sleepHit $v');
      }
    });

    test('kalori: GoalRules.caloriesHit vektörlerle aynı', () {
      for (final v in rowsOf('calories')) {
        final got = GoalRules.caloriesHit(
          (v['value'] as num).toDouble(),
          (v['target'] as num).toInt(),
        );
        expect(got, v['hit'], reason: 'caloriesHit $v');
      }
    });

    test('eşik sabitleri SQL işlevlerinin yazdığı yüzdelerle aynı', () {
      // supabase/schema.sql: goal_steps_hit %100, goal_sleep_hit %90,
      // goal_calories_hit %85–%110. Vektörler sınırları sıkıca tuttuğu için
      // sabit değişirse yukarıdaki testler de kırılır; bu test sabitleri açıkça
      // sabitler.
      expect(GoalRules.stepsMinPercent, 100);
      expect(GoalRules.sleepMinPercent, 90);
      expect(GoalRules.caloriesMinPercent, 85);
      expect(GoalRules.caloriesMaxPercent, 110);
    });

    test('schema.sql işlevleri bu yüzdeleri gerçekten kullanır', () {
      final sql = File('supabase/schema.sql').readAsStringSync();
      expect(
        sql,
        contains('p_steps * 100 >= p_target::bigint * ${GoalRules.stepsMinPercent}'),
      );
      expect(
        sql,
        contains('p_minutes * 100 >= p_target::bigint * ${GoalRules.sleepMinPercent}'),
      );
      expect(
        sql,
        contains('p_target::numeric * ${GoalRules.caloriesMinPercent}'),
      );
      expect(
        sql,
        contains('p_target::numeric * ${GoalRules.caloriesMaxPercent}'),
      );
    });
  });
}
