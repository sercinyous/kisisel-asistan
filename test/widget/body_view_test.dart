import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/body_repository.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/body/body_format.dart';
import 'package:kisisel_asistan/features/health/presentation/body/body_view.dart';
import 'package:kisisel_asistan/features/health/presentation/body/checkin_flow.dart';
import 'package:kisisel_asistan/features/health/presentation/body/measurement_form_sheet.dart';
import 'package:kisisel_asistan/features/health/presentation/body/measurements_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/body/photo_capture.dart';
import 'package:kisisel_asistan/features/health/presentation/body/photos_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/body_providers.dart'
    show photoUrlProvider;
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Fotoğraf destekleyen bellek deposu (yükleme satırı yazar).
class _PhotoRepo extends MemoryBodyRepository {
  _PhotoRepo({super.measurements, super.photos});

  int uploads = 0;

  @override
  bool get photosSupported => true;

  @override
  Future<ProgressPhoto> uploadPhoto({
    required DateTime takenOn,
    required PhotoPose pose,
    required Uint8List imageBytes,
  }) async {
    uploads++;
    final p = ProgressPhoto(
      id: 'up$uploads',
      takenOn: takenOn,
      pose: pose,
      storagePath: progressPhotoPath('u1', takenOn, pose),
    );
    photos.add(p);
    return p;
  }
}

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

DateTime get _today => AppDates.startOfDay(DateTime.now());

BodyMeasurement _m(int daysAgo, Map<BodyField, double> values) =>
    BodyMeasurement(
      id: 'm$daysAgo',
      measuredOn: AppDates.addDays(_today, -daysAgo),
      values: values,
    );

ProgressPhoto _p(int daysAgo, PhotoPose pose) {
  final d = AppDates.addDays(_today, -daysAgo);
  return ProgressPhoto(
    id: '${pose.name}$daysAgo',
    takenOn: d,
    pose: pose,
    storagePath: progressPhotoPath('u1', d, pose),
  );
}

/// Bugün ölçü günü olmayan haftalık ayar.
UserSettings _offDay() => const UserSettings.defaults()
    .copyWith(checkinWeekday: _today.weekday % 7 + 1);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  MemoryBodyRepository? body,
  UserSettings? settings,
  List<WeightEntry> weights = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bodyRepositoryProvider.overrideWithValue(body ?? MemoryBodyRepository()),
        healthRepositoryProvider
            .overrideWithValue(FakeHealthRepository(weights: [...weights])),
        settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(settings: settings ?? _offDay())),
        bodyImagePickerProvider.overrideWithValue((_) async => _png),
        // Gerçek sağlayıcı 9 dakikalık yenileme zamanlayıcısı kurar.
        photoUrlProvider.overrideWith((ref, path) async => null),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _inList(Widget child) => Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [child],
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('BodyFormat', () {
    test('delta ve özet satırı', () {
      expect(BodyFormat.delta(-4), '−4');
      expect(BodyFormat.delta(0.5), '+0,5');
      expect(BodyFormat.delta(0), '0');
      const s = BodyFieldSummary(
        field: BodyField.waist,
        last: 88,
        fromStart: -4,
        fromPrevious: -0.5,
      );
      expect(BodyFormat.summaryLine(s),
          'Bel 88 cm · −4 başlangıçtan · −0,5 geçen');
    });

    test('en yakın kilo ±3 gün', () {
      final day = DateTime(2026, 11, 10);
      final entries = [
        WeightEntry(id: 'a', weightKg: 80, loggedAt: DateTime(2026, 11, 2, 8)),
        WeightEntry(id: 'b', weightKg: 79, loggedAt: DateTime(2026, 11, 12, 8)),
      ];
      expect(nearestWeight(entries, day)?.id, 'b');
      expect(nearestWeight(entries, DateTime(2026, 10, 1)), isNull);
    });

    test('renk: bel azalınca vurgu, göğüs nötr', () {
      expect(bodyDeltaColor(BodyField.waist, -1), AppColors.accent);
      expect(bodyDeltaColor(BodyField.waist, 1), AppColors.warning);
      expect(bodyDeltaColor(BodyField.chest, -1), AppColors.textSecondary);
    });
  });

  testWidgets('BodyView boş durumları ve sonraki ölçü günü', (tester) async {
    await _pump(tester, _inList(const BodyView()));
    expect(find.text('Henüz ölçüm yok.'), findsOneWidget);
    expect(find.text('İlk ölçümü ekle'), findsOneWidget);
    expect(find.textContaining('Henüz fotoğraf yok.'), findsOneWidget);
    expect(find.byKey(const Key('checkin-schedule')), findsOneWidget);
    expect(find.textContaining('Sonraki ölçü günü'), findsOneWidget);
    expect(find.byKey(const Key('checkin-banner')), findsNothing);
  });

  testWidgets('BodyView ölçü satırları farkları gösterir', (tester) async {
    final repo = MemoryBodyRepository(measurements: [
      _m(14, {BodyField.waist: 92, BodyField.hip: 104}),
      _m(7, {BodyField.waist: 88.5}),
      _m(0, {BodyField.waist: 88}),
    ]);
    await _pump(tester, _inList(const BodyView()), body: repo);
    expect(find.text('88 cm'), findsOneWidget);
    expect(find.text('−4 başlangıçtan'), findsOneWidget);
    expect(find.text('−0,5 geçen'), findsOneWidget);
    expect(find.byKey(const Key('body-field-hip')), findsOneWidget);
  });

  testWidgets('Kilo kartı son kilo ve 7 gün farkı', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      _inList(const BodyView()),
      weights: [
        WeightEntry(
            id: 'w1',
            weightKg: 85,
            loggedAt: now.subtract(const Duration(days: 8))),
        WeightEntry(
            id: 'w2',
            weightKg: 84.2,
            loggedAt: now.subtract(const Duration(hours: 1))),
      ],
    );
    expect(find.textContaining('84,2', findRichText: true), findsOneWidget);
    expect(find.textContaining('−0,8 kg · 7 gün'), findsOneWidget);
  });

  testWidgets('Ölçü günü banner\'ı açılır ve bugün için kapatılır',
      (tester) async {
    await _pump(
      tester,
      _inList(const BodyView()),
      settings: const UserSettings.defaults()
          .copyWith(checkinWeekday: _today.weekday),
    );
    expect(find.text('Bugün ölçü ve fotoğraf günü'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkin-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-banner')), findsNothing);
    expect(find.byKey(const Key('checkin-schedule')), findsOneWidget);
  });

  testWidgets('Banner Başla kontrol akışını açar', (tester) async {
    await _pump(
      tester,
      _inList(const BodyView()),
      settings: const UserSettings.defaults()
          .copyWith(checkinWeekday: _today.weekday),
    );
    await tester.tap(find.byKey(const Key('checkin-start')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckinFlowScreen), findsOneWidget);
    expect(find.byKey(const Key('checkin-step-weigh')), findsOneWidget);
  });

  testWidgets('Ölçü formu kaydeder', (tester) async {
    final repo = MemoryBodyRepository();
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => MeasurementFormSheet.show(context),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
      body: repo,
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('Bel: göbek hizası, nefes verince'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('measurement-waist')), '87,4');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.measurements, hasLength(1));
    expect(repo.measurements.single[BodyField.waist], 87.4);
    expect(repo.measurements.single.measuredOn, _today);
  });

  testWidgets('Ölçü formu: alan yoksa hata, 5 cm farkta onay', (tester) async {
    final repo = MemoryBodyRepository(measurements: [
      _m(7, {BodyField.waist: 90}),
    ]);
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => MeasurementFormSheet.show(context),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
      body: repo,
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('Önceki: 90'), findsOneWidget);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('En az bir ölçü gir.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('measurement-waist')), '80');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Yanlış girmiş olabilir misin?'), findsOneWidget);
    await tester.tap(find.text('Düzelt'));
    await tester.pumpAndSettle();
    expect(repo.measurements, hasLength(1));

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('measurement-confirm')));
    await tester.pumpAndSettle();
    expect(repo.measurements, hasLength(2));
  });

  testWidgets('Ölçüler ekranı tablo, alan ve aralık seçimi', (tester) async {
    final repo = MemoryBodyRepository(measurements: [
      for (var w = 20; w >= 0; w -= 4)
        _m(w * 7 ~/ 4, {BodyField.waist: 90 - (20 - w) / 4, BodyField.arm: 35}),
    ]);
    await _pump(tester, const MeasurementsScreen(), body: repo);
    expect(find.text('Başlangıç'), findsOneWidget);
    expect(find.byKey(const Key('table-row-waist')), findsOneWidget);
    expect(find.byKey(const Key('table-row-arm')), findsOneWidget);
    expect(find.byKey(const Key('table-row-hip')), findsNothing);
    expect(find.byKey(const Key('chart-change')), findsOneWidget);

    await tester.tap(find.byKey(const Key('range-all')));
    await tester.pumpAndSettle();
    expect(find.text('−5 cm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('field-chip-arm')));
    await tester.pumpAndSettle();
    expect(find.text('0 cm'), findsOneWidget);
  });

  testWidgets('Kontrol akışı: tüm adımlar atlanır', (tester) async {
    await _pump(tester, const CheckinFlowScreen());
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('checkin-skip')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('checkin-done')), findsOneWidget);
    expect(find.text('Bugün atlandı'), findsOneWidget);
  });

  testWidgets('Kontrol akışı: fotoğraf adımı yükler ve biter',
      (tester) async {
    final repo = _PhotoRepo(photos: [_p(7, PhotoPose.front)]);
    await _pump(tester, const CheckinFlowScreen(), body: repo);
    await tester.tap(find.byKey(const Key('checkin-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkin-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-step-photo')), findsOneWidget);

    await tester.tap(find.text('Ön').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-ghost')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture-save')));
    await tester.pumpAndSettle();
    expect(repo.uploads, 1);

    await tester.tap(find.text('Bitir (1/3)'));
    await tester.pumpAndSettle();
    expect(find.text('Kontrol tamam'), findsOneWidget);
  });

  testWidgets('Fotoğraflar: hafta ızgarası, gizleme ve karşılaştırma',
      (tester) async {
    final repo = _PhotoRepo(
      measurements: [
        _m(28, {BodyField.waist: 92}),
        _m(0, {BodyField.waist: 88}),
      ],
      photos: [
        for (final pose in PhotoPose.values) _p(28, pose),
        _p(0, PhotoPose.front),
      ],
    );
    await _pump(
      tester,
      const PhotosScreen(),
      body: repo,
      settings: _offDay().copyWith(hidePhotos: true),
    );
    expect(
        find.byKey(Key('photo-week-${dateOnlyIso(_today)}')), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);

    await tester.tap(find.text('Karşılaştır'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compare-diff')), findsOneWidget);
    expect(find.textContaining('Bel −4 cm'), findsOneWidget);
    expect(find.textContaining('4 hafta'), findsOneWidget);

    await tester.tap(find.text('Yan'));
    await tester.pumpAndSettle();
    expect(find.text('Yan yok'), findsOneWidget);
  });
}
