import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/config/app_targets.dart';
import 'package:kisisel_asistan/core/templates/meal_templates.dart';
import 'package:kisisel_asistan/core/templates/routine_templates.dart';
import 'package:kisisel_asistan/core/templates/task_templates.dart';
import 'package:kisisel_asistan/core/templates/template_chips.dart';
import 'package:kisisel_asistan/core/templates/workout_templates.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

void main() {
  group('Görev şablonları', () {
    test('en az 8 tane; etiketler tekil; randevu, ödeme, telefon, alışveriş var',
        () {
      final labels = TaskTemplates.all.map((t) => t.label).toList();
      expect(labels.length, greaterThanOrEqualTo(8));
      expect(labels.toSet().length, labels.length);
      expect(labels, containsAll(['Randevu', 'Ödeme', 'Telefon', 'Alışveriş']));
    });

    test('başlık 1..300, kategori ve öncelik geçerli, açıklama ≤ 2000', () {
      for (final t in TaskTemplates.all) {
        expect(t.title.trim(), isNotEmpty, reason: t.label);
        expect(t.title.runes.length, lessThanOrEqualTo(300), reason: t.label);
        expect(AppTargets.taskCategories, contains(t.category), reason: t.label);
        expect(['low', 'medium', 'high'], contains(t.priority), reason: t.label);
        expect((t.description ?? '').runes.length, lessThanOrEqualTo(2000));
      }
    });

    test('sahibe özel ad içermez', () {
      for (final t in TaskTemplates.all) {
        expect('${t.label} ${t.title} ${t.description}'.toLowerCase(),
            isNot(contains('pusholder')));
      }
    });
  });

  group('Rutin şablonları', () {
    test('kimlikler ve başlıklar tekil; rutin ve ay sabitleri var', () {
      final ids = RoutineTemplates.all.map((t) => t.id).toList();
      final titles = RoutineTemplates.all.map((t) => t.title).toList();
      expect(ids.toSet().length, ids.length);
      expect(titles.toSet().length, titles.length);
      expect(ids, containsAll(['su', 'yuruyus', 'vitamin', 'haftalik-plan']));
      expect(RoutineTemplates.all.where((t) => t.isMonthly), isNotEmpty);
    });

    test('alanlar veritabanı kurallarına uyar', () {
      for (final t in RoutineTemplates.all) {
        expect(t.title.trim(), isNotEmpty, reason: t.id);
        expect(t.title.runes.length, lessThanOrEqualTo(200), reason: t.id);
        expect(Routine.categories, contains(t.category), reason: t.id);
        expect(t.daysOfWeek, isNotEmpty, reason: t.id);
        expect(t.daysOfWeek.every((d) => d >= 1 && d <= 7), isTrue, reason: t.id);
        if (t.isMonthly) {
          expect(t.dayOfMonth, inInclusiveRange(1, 31), reason: t.id);
        } else {
          expect(t.dayOfMonth, isNull, reason: t.id);
        }
        if (t.hasTime) {
          expect(t.hour, inInclusiveRange(0, 23), reason: t.id);
          expect(t.minute, inInclusiveRange(0, 59), reason: t.id);
        }
      }
    });

    test('toRoutine: kişisel kapsamlı, kaydedilmemiş taslak', () {
      final walk = RoutineTemplates.byId('yuruyus')!.toRoutine(sortOrder: 3);
      expect(walk.id, isEmpty);
      expect(walk.scope, Routine.scopePersonal);
      expect(walk.category, 'spor');
      expect(walk.sortOrder, 3);
      expect(walk.timeLabel, '18:30');
      expect(walk.isDaily, isTrue);
      expect(walk.notify, isTrue);

      final rent = RoutineTemplates.byId('kira')!.toRoutine();
      expect(rent.isMonthly, isTrue);
      expect(rent.dayOfMonth, 1);
      expect(rent.hasTime, isFalse);
      // Kayda yazılabilir: haftalık gün listesi boş olamaz.
      final map = rent.toInsertMap();
      expect(map['frequency'], 'monthly');
      expect(map['day_of_month'], 1);
      expect(map['days_of_week'], Routine.everyDay);
      expect(map['scope'], Routine.scopePersonal);
    });

    test('starters yalnızca başlangıç işaretlileri; byId bilinmeyende null', () {
      final starters = RoutineTemplates.starters;
      expect(starters, isNotEmpty);
      expect(starters.every((t) => t.starter), isTrue);
      expect(starters.length, lessThan(RoutineTemplates.all.length));
      expect(RoutineTemplates.byId('yok'), isNull);
    });

    test('scheduleLabel okunur Türkçe', () {
      expect(RoutineTemplates.byId('yuruyus')!.scheduleLabel, 'Her gün · 18:30');
      expect(RoutineTemplates.byId('su')!.scheduleLabel, 'Her gün');
      expect(
        RoutineTemplates.byId('haftalik-plan')!.scheduleLabel,
        'Pazar · 20:00',
      );
      expect(
        RoutineTemplates.byId('antrenman')!.scheduleLabel,
        'Pzt, Çar, Cum · 19:00',
      );
      expect(
        RoutineTemplates.byId('kira')!.scheduleLabel,
        'Her ay · ayın 1. günü',
      );
    });
  });

  group('Öğün şablonları', () {
    test('yumurta + ekmek var; alanlar öğün formunun sınırlarında', () {
      expect(MealTemplates.all.map((t) => t.label), contains('Yumurta + ekmek'));
      final labels = MealTemplates.all.map((t) => t.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final t in MealTemplates.all) {
        expect(NutritionLog.mealTypes, contains(t.mealType), reason: t.label);
        expect(t.foodName.trim(), isNotEmpty, reason: t.label);
        expect(t.foodName.runes.length,
            lessThanOrEqualTo(NutritionLog.foodNameMaxLength));
        expect(t.quantityText.runes.length, lessThanOrEqualTo(100));
        expect(t.calories, inInclusiveRange(1, NutritionLog.caloriesMax));
        for (final g in [t.proteinG, t.carbsG, t.fatG]) {
          expect(g, inInclusiveRange(0, NutritionLog.macroMax), reason: t.label);
        }
      }
    });

    test('makrolar kaloriyle kabaca tutarlı (Atwater, ±%15)', () {
      for (final t in MealTemplates.all) {
        final atwater = 4 * t.proteinG + 4 * t.carbsG + 9 * t.fatG;
        expect((atwater - t.calories).abs(),
            lessThanOrEqualTo(t.calories * 0.15 + 10),
            reason: '${t.label}: $atwater vs ${t.calories}');
      }
    });
  });

  group('Antrenman şablonları', () {
    test('yürüyüş, ağırlık, koşu, yoga, bisiklet var', () {
      final titles = WorkoutTemplates.all.map((t) => t.title).join(' ');
      for (final word in ['Yürüyüş', 'Ağırlık', 'Koşu', 'Yoga', 'Bisiklet']) {
        expect(titles, contains(word));
      }
    });

    test('tür ve süre veritabanı sınırlarında; etiketler tekil', () {
      final labels = WorkoutTemplates.all.map((t) => t.label).toList();
      expect(labels.toSet().length, labels.length);
      for (final t in WorkoutTemplates.all) {
        expect(WorkoutLog.workoutTypes, contains(t.workoutType), reason: t.label);
        expect(
          t.durationMin,
          inInclusiveRange(WorkoutLog.durationMinMin, WorkoutLog.durationMinMax),
          reason: t.label,
        );
        expect(t.title.trim(), isNotEmpty);
      }
    });
  });

  group('TemplateChips', () {
    testWidgets('çipler gösterilir ve dokunulan şablonu bildirir', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TemplateChips<TaskTemplate>(
              templates: TaskTemplates.all,
              labelOf: (t) => t.label,
              onSelected: (t) => picked.add(t.title),
              hint: 'Düzenlenebilir.',
            ),
          ),
        ),
      );
      expect(find.text('Şablondan başla'), findsOneWidget);
      expect(find.text('Düzenlenebilir.'), findsOneWidget);
      expect(find.text('Randevu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('template-0')));
      await tester.pump();
      expect(picked, ['Randevu']);
      await tester.tap(find.widgetWithText(ActionChip, 'Ödeme'));
      await tester.pump();
      expect(picked, ['Randevu', 'Ödeme yap']);
    });
  });
}
