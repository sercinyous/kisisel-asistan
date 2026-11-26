import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_quick_add_modal.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
import '../helpers/test_fonts.dart';

ParsedEntry sampleEntry() => ParsedEntry.fromJson(const {
      'tasks': [
        {
          'title': 'Ayşe ile vardiya planı',
          'category': 'Ekip',
          'priority': 'high',
          'assignee': 'Ayşe',
          'due_at': '2099-01-05T15:00:00+03:00',
          'remind_at': '2099-01-05T14:45:00+03:00',
        },
      ],
      'nutrition': [
        {
          'meal_type': 'lunch',
          'food_name': 'Tavuk göğsü',
          'quantity_text': '200 gr',
          'calories': 330,
          'protein_g': 62,
          'carbs_g': 0,
          'fat_g': 7.2,
          'eaten_at': '2026-11-16T13:00:00+03:00',
        },
      ],
      'weights': [
        {'weight_kg': 83.9, 'measured_at': '2026-11-16T08:00:00+03:00'},
      ],
    });

/// Modalı açan tek düğmeli sayfa; modalın döndürdüğü değeri saklar.
class _Host extends StatefulWidget {
  const _Host({required this.mode, this.initialText});

  final QuickAddMode mode;
  final String? initialText;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final value = await AiQuickAddModal.show(
              context,
              mode: widget.mode,
              initialText: widget.initialText,
            );
            setState(() {
              result = value;
              closed = true;
            });
          },
          child: const Text('aç'),
        ),
      ),
    );
  }
}

/// İş alanı yanıtı: bir görev, bir aylık ve bir haftalık rutin.
ParsedEntry workEntry({bool otherDomain = false, String? summary}) =>
    ParsedEntry.fromJson({
      'tasks': [
        {
          'title': 'Ayşe ile vardiya planı',
          'category': 'Ekip',
          'priority': 'medium',
          'due_at': '2099-01-05T15:00:00+03:00',
        },
      ],
      'routines': [
        {
          'title': 'Maaş ödemeleri',
          'scope': 'İş',
          'category': 'finans',
          'frequency': 'monthly',
          'day_of_month': 15,
          'time_of_day': '10:00',
        },
        {
          'title': 'Ekip toplantısı',
          'scope': 'İş',
          'category': 'operasyon',
          'frequency': 'weekly',
          'days_of_week': [1],
          'time_of_day': '11:00',
        },
      ],
      'other_domain': otherDomain,
      'other_domain_summary': summary,
    });

/// Sağlık alanı yanıtı: tek öğün.
ParsedEntry healthEntry({bool otherDomain = false, String? summary}) =>
    ParsedEntry.fromJson({
      'nutrition': [
        {
          'meal_type': 'lunch',
          'food_name': 'Tavuk göğsü',
          'quantity_text': '200 gr',
          'calories': 330,
          'protein_g': 62,
          'carbs_g': 0,
          'fat_g': 7.2,
          'eaten_at': '2026-11-16T13:00:00+03:00',
        },
      ],
      'other_domain': otherDomain,
      'other_domain_summary': summary,
    });

ParsedEntry otherDomainOnly(String summary) => ParsedEntry.fromJson({
      'other_domain': true,
      'other_domain_summary': summary,
    });

void main() {
  late QuickAddHarness harness;
  late FakeGeminiParserService gemini;
  late RecordingQuickAddRepository repository;
  late FakeNotificationService notifications;
  late List<String> haptics;

  setUpAll(() => initializeDateFormatting(AppDates.locale));

  setUp(() {
    harness = QuickAddHarness(
      work: (_) async => sampleEntry(),
      health: (_) async => healthEntry(),
    );
    // Eski testler iş alanında çalışır; `gemini` o alanın ayrıştırıcısıdır.
    gemini = harness.work;
    repository = harness.repository;
    notifications = harness.notifications;

    // Test motorunda platform kanalı sahte saat içinde yanıt vermez;
    // `await HapticFeedback...` çağrıları takılmasın diye kanalı taklit et.
    haptics = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<_HostState> openModal(
    WidgetTester tester, {
    QuickAddMode mode = QuickAddMode.work,
    String? initialText,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: _Host(mode: mode, initialText: initialText),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    return tester.state<_HostState>(find.byType(_Host));
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> typeAndParse(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
  }

  testWidgets('metin boşken Ayrıştır düğmesi kapalıdır', (tester) async {
    await openModal(tester);

    expect(find.text('İş girişi'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(gemini.inputs, isEmpty);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(gemini.inputs, isEmpty);
  });

  testWidgets('örnek satıra dokununca metin alanı dolar', (tester) async {
    await openModal(tester);
    const example = 'Her pazartesi 11:00 ekip toplantısı';
    await tester.tap(find.text(example));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      example,
    );
  });

  testWidgets('ayrıştır -> önizleme -> kalem çıkar -> kaydet, sayı ile kapanır',
      (tester) async {
    final host = await openModal(tester);
    await typeAndParse(tester, 'Öğlen tavuk yedim, yarın Ayşe ile toplantı');

    expect(gemini.inputs.single, 'Öğlen tavuk yedim, yarın Ayşe ile toplantı');
    expect(find.text('Bunları anladım'), findsOneWidget);
    expect(find.text('Tavuk göğsü · 200 gr'), findsOneWidget);
    expect(find.text('Beslenme · Öğle'), findsOneWidget);
    expect(find.text('Ayşe ile vardiya planı'), findsOneWidget);
    expect(find.text('Görev · Ekip · Yüksek öncelik'), findsOneWidget);
    expect(find.text('83.9 kg'), findsOneWidget);
    expect(find.text('3 kaydı kaydet'), findsOneWidget);

    // İlk kutucuk beslenme kaydıdır; onu çıkar.
    await tester.tap(find.byTooltip('Bu kaydı çıkar').first);
    await tester.pumpAndSettle();
    expect(find.text('Tavuk göğsü · 200 gr'), findsNothing);
    expect(find.text('2 kaydı kaydet'), findsOneWidget);
    expect(repository.saved, isEmpty);

    await tester.tap(find.text('2 kaydı kaydet'));
    await tester.pumpAndSettle();

    expect(find.byType(AiQuickAddModal), findsNothing);
    expect(host.closed, isTrue);
    expect(host.result, 2);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);

    final saved = repository.saved.single;
    expect(saved.nutrition, isEmpty);
    expect(saved.tasks.single.title, 'Ayşe ile vardiya planı');
    expect(saved.weights.single.weightKg, 83.9);

    final reminder = notifications.scheduled.single;
    expect(reminder.taskId, 'task-0');
    expect(reminder.title, 'Ayşe ile vardiya planı');
    expect(reminder.when.toUtc(), DateTime.utc(2099, 1, 5, 11, 45));
  });

  testWidgets(
      'saatli görev, hatırlatma saati yazılmasa da "Hatırlatma açık" görünür',
      (tester) async {
    gemini.handler = (_) async => ParsedEntry.fromJson(const {
          'tasks': [
            {
              'title': 'Ayşe ile vardiya planı',
              'category': 'Ekip',
              'priority': 'medium',
              'due_at': '2099-01-05T15:00:00+03:00',
            },
            {'title': 'Süt al'},
          ],
        });
    await openModal(tester);
    await typeAndParse(tester, 'Ayşe ile toplantı, süt al');

    // Bildirim terminden ayardaki süre kadar önce planlanır; önizleme de
    // bunu söyler. Tarihsiz görevde hatırlatma yoktur.
    expect(find.textContaining('Hatırlatma açık'), findsOneWidget);
    expect(find.text('Tarihsiz görev'), findsOneWidget);

    await tester.tap(find.text('2 kaydı kaydet'));
    await tester.pumpAndSettle();
    final reminder = notifications.scheduled.single;
    expect(reminder.title, 'Ayşe ile vardiya planı');
    expect(reminder.when.toUtc(), DateTime.utc(2099, 1, 5, 11, 30));
  });

  testWidgets('son kalem de çıkarılınca metin girişine döner', (tester) async {
    gemini.handler = (_) async => ParsedEntry.fromJson(const {
          'notes': [
            {'title': 'Tek not', 'content': 'içerik'},
          ],
        });
    await openModal(tester);
    await typeAndParse(tester, 'not al');
    expect(find.text('1 kaydı kaydet'), findsOneWidget);

    await tester.tap(find.byTooltip('Bu kaydı çıkar'));
    await tester.pumpAndSettle();

    expect(find.text('İş girişi'), findsOneWidget);
    expect(find.text('Devam'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'not al',
      reason: 'kullanıcının yazdığı metin korunmalı',
    );
  });

  testWidgets('Düzenle metin girişine döner ve metni korur', (tester) async {
    await openModal(tester);
    await typeAndParse(tester, 'ilk metin');
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();

    expect(find.text('Devam'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ilk metin',
    );
    expect(repository.saved, isEmpty);
  });

  testWidgets('AiParseException mesajı hata bandında gösterilir',
      (tester) async {
    gemini.handler = (_) async => throw const AiParseException(
          'AI şu an çok yoğun. Biraz sonra tekrar dene ya da elle ekle.',
          statusCode: 429,
        );
    final host = await openModal(tester);
    await typeAndParse(tester, 'bir şeyler');

    expect(
      find.text('AI şu an çok yoğun. Biraz sonra tekrar dene ya da elle ekle.'),
      findsOneWidget,
    );
    expect(find.text('Bunları anladım'), findsNothing);
    expect(find.text('Devam'), findsOneWidget);
    expect(host.closed, isFalse);

    // İkinci deneme başarılı olursa hata bandı kaybolur.
    gemini.handler = (_) async => sampleEntry();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kota sınırına'), findsNothing);
    expect(find.text('Bunları anladım'), findsOneWidget);
  });

  testWidgets('beklenmeyen hata genel mesaja çevrilir', (tester) async {
    gemini.handler = (_) async => throw StateError('boom');
    await openModal(tester);
    await typeAndParse(tester, 'bir şeyler');
    expect(
      find.text('Bir şeyler ters gitti. Tekrar dene ya da elle ekle.'),
      findsOneWidget,
    );
  });

  testWidgets('boş sonuç kullanıcıya açıklanır', (tester) async {
    gemini.handler = (_) async => const ParsedEntry();
    await openModal(tester);
    await typeAndParse(tester, 'selam');
    expect(
      find.textContaining('Metinden kaydedilecek bir şey çıkaramadım'),
      findsOneWidget,
    );
    expect(find.text('Devam'), findsOneWidget);
  });

  testWidgets('ayrıştırma sürerken düğme meşgul görünür ve tekrar tetiklenmez',
      (tester) async {
    final gate = Completer<ParsedEntry>();
    gemini.handler = (_) => gate.future;
    await openModal(tester);
    await tester.enterText(find.byType(TextField), 'metin');
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pump();

    expect(find.text('Anlıyorum…'), findsOneWidget);
    await tester.tap(find.text('Anlıyorum…'));
    await tester.pump();
    expect(gemini.inputs, hasLength(1));

    gate.complete(sampleEntry());
    await tester.pumpAndSettle();
    expect(find.text('3 kaydı kaydet'), findsOneWidget);
  });

  testWidgets('kaydetme hatasında önizleme kalır, modal kapanmaz',
      (tester) async {
    repository.error = Exception('ağ yok');
    final host = await openModal(tester);
    await typeAndParse(tester, 'metin');

    await tester.tap(find.text('3 kaydı kaydet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kayıt doğrulanamadı.'), findsOneWidget);
    expect(find.text('3 kaydı kaydet'), findsOneWidget);
    expect(host.closed, isFalse);
    expect(notifications.scheduled, isEmpty);

    // Hata giderilince aynı önizleme yeniden kaydedilebilir.
    repository.error = null;
    await tester.tap(find.text('3 kaydı kaydet'));
    await tester.pumpAndSettle();
    expect(host.result, 3);
  });

  testWidgets('X düğmesi kayıt yapmadan kapatır (null döner)', (tester) async {
    final host = await openModal(tester);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(host.closed, isTrue);
    expect(host.result, isNull);
    expect(repository.saved, isEmpty);
  });

  testWidgets(
    'kaydetme sürerken modal dışına dokunmak kapatmaz; kayıt bitince sayı döner',
    (tester) async {
      repository.gate = Completer<void>();
      final host = await openModal(tester);
      await typeAndParse(tester, 'metin');

      await tester.tap(find.text('3 kaydı kaydet'));
      await tester.pump();
      expect(find.text('Kaydediliyor…'), findsOneWidget);

      // Meşgulken arka plana dokunmak modalı kapatmaz.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 500));
      expect(host.closed, isFalse);
      expect(find.text('Kaydediliyor…'), findsOneWidget);

      repository.gate!.complete();
      await tester.pumpAndSettle();

      expect(host.closed, isTrue);
      expect(host.result, 3);
      expect(repository.saved, hasLength(1));
      expect(
        notifications.scheduled,
        hasLength(1),
        reason: 'modal kapansa bile saatli görevin bildirimi planlanmalı',
      );
    },
  );
  testWidgets('boştayken arka plana dokunmak X gibi kapatır', (tester) async {
    final host = await openModal(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(host.closed, isTrue);
    expect(host.result, isNull);
  });

  group('alanlar', () {
    testWidgets('iş girişi kendi başlığı, kapsamı ve örnekleriyle açılır',
        (tester) async {
      await openModal(tester);

      expect(find.text('İş girişi'), findsOneWidget);
      expect(find.textContaining('Görev, randevu, not ya da tekrarlayan iş.'),
          findsOneWidget);
      expect(find.text('Her ayın 15\'i maaş ödemesi'), findsOneWidget);
      expect(find.textContaining('tavuk göğsü'), findsNothing);
    });

    testWidgets('sağlık girişi kendi başlığı, kapsamı ve örnekleriyle açılır',
        (tester) async {
      await openModal(tester, mode: QuickAddMode.health);

      expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);
      expect(
          find.textContaining('Öğün, antrenman ya da kilo.'), findsOneWidget);
      expect(find.text('Bugün 45 dk ağırlık çalıştım'), findsOneWidget);
      expect(find.textContaining('maaş ödemesi'), findsNothing);
    });

    testWidgets('metin yalnızca açılan alanın ayrıştırıcısına gider',
        (tester) async {
      await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'Öğlen tavuk yedim');

      expect(harness.health.inputs, ['Öğlen tavuk yedim']);
      expect(harness.work.inputs, isEmpty);
      expect(find.text('1 kaydı kaydet'), findsOneWidget);
    });

    testWidgets('initialText metin alanına yazılır', (tester) async {
      await openModal(tester, initialText: 'Her cuma rapor');
      expect(fieldText(tester), 'Her cuma rapor');

      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(harness.work.inputs, ['Her cuma rapor']);
    });
  });

  group('tekrarlayan işler', () {
    setUp(() => harness.work.handler = (_) async => workEntry());

    testWidgets('önizlemede aylık ve haftalık rutin kutucukları görünür',
        (tester) async {
      await openModal(tester);
      await typeAndParse(tester, 'her ayın 15i maaş, her pazartesi toplantı');

      expect(find.text('Aylık iş · İş · Finans'), findsOneWidget);
      expect(find.text('Maaş ödemeleri'), findsOneWidget);
      expect(find.text('Her ayın 15. günü · 10:00'), findsOneWidget);
      expect(find.text('Tekrarlayan iş · İş · İş'), findsOneWidget);
      expect(find.text('Ekip toplantısı'), findsOneWidget);
      expect(find.text('Her Pzt · 11:00'), findsOneWidget);
      expect(find.text('3 kaydı kaydet'), findsOneWidget);
    });

    testWidgets(
        'rutin önizlemeden çıkarılabilir; kalanlar RPC yüküyle kaydedilir',
        (tester) async {
      final host = await openModal(tester);
      await typeAndParse(tester, 'metin');

      // Sıra: görev, aylık rutin, haftalık rutin. İkinci kutucuk aylık iştir.
      await tester.tap(find.byTooltip('Bu kaydı çıkar').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Maaş ödemeleri'), findsNothing);

      await tester.tap(find.text('2 kaydı kaydet'));
      await tester.pumpAndSettle();

      expect(host.result, 2, reason: 'rutin de kaydedilen sayıya girer');
      expect(repository.saved.single.toJson()['routines'], [
        {
          'title': 'Ekip toplantısı',
          'scope': 'İş',
          'category': 'operasyon',
          'frequency': 'weekly',
          'days_of_week': [1],
          'day_of_month': null,
          'time_of_day': '11:00',
        },
      ]);
    });
  });

  group('diğer alan uyarısı', () {
    testWidgets(
        'sağlık girişinde tümüyle iş metni: önizleme yok, uyarı ve geçiş düğmesi',
        (tester) async {
      harness.health.handler =
          (_) async => otherDomainOnly('Yarın 15:00 Ayşe ile toplantı');
      final host = await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'Yarın 15:00 Ayşe ile toplantı var');

      expect(find.text('Bu bir iş kaydı gibi görünüyor.'), findsOneWidget);
      expect(find.text('Yarın 15:00 Ayşe ile toplantı'), findsOneWidget);
      expect(find.text('İş girişine geç'), findsOneWidget);
      expect(find.text('Bunları anladım'), findsNothing);
      expect(find.textContaining('Metinden kaydedilecek'), findsNothing,
          reason: 'yönlendirme bir hata değildir');
      expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);

      await tester.tap(find.text('İş girişine geç'));
      await tester.pumpAndSettle();

      expect(find.text('İş girişi'), findsOneWidget);
      expect(find.text('Sağlık & beslenme girişi'), findsNothing);
      expect(fieldText(tester), 'Yarın 15:00 Ayşe ile toplantı var',
          reason: 'metin diğer alana taşınmalı');
      expect(find.text('Bu bir iş kaydı gibi görünüyor.'), findsNothing);
      expect(harness.work.inputs, isEmpty,
          reason: 'geçiş kendiliğinden ayrıştırmaz');
      expect(repository.saved, isEmpty);

      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(harness.work.inputs, ['Yarın 15:00 Ayşe ile toplantı var']);
      expect(find.text('Bunları anladım'), findsOneWidget);

      await tester.tap(find.text('3 kaydı kaydet'));
      await tester.pumpAndSettle();
      expect(host.result, 3);
      expect(repository.saved, hasLength(1));
    });

    testWidgets(
        'iş girişinde tümüyle sağlık metni: sağlık girişine yönlendirir',
        (tester) async {
      harness.work.handler = (_) async => otherDomainOnly('Öğlen tavuk');
      await openModal(tester);
      await typeAndParse(tester, 'Öğlen 200 gr tavuk yedim');

      expect(find.text('Bu bir sağlık kaydı gibi görünüyor.'), findsOneWidget);
      expect(find.text('Öğlen tavuk'), findsOneWidget);

      await tester.tap(find.text('Sağlık girişine geç'));
      await tester.pumpAndSettle();

      expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);
      expect(fieldText(tester), 'Öğlen 200 gr tavuk yedim');

      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(harness.health.inputs, ['Öğlen 200 gr tavuk yedim']);
      expect(find.text('Tavuk göğsü · 200 gr'), findsOneWidget);
    });

    testWidgets('özet yoksa uyarı yalnızca başlık ve düğmeyle gösterilir',
        (tester) async {
      harness.health.handler =
          (_) async => const ParsedEntry(otherDomain: true);
      await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'toplantı');

      expect(find.text('Bu bir iş kaydı gibi görünüyor.'), findsOneWidget);
      expect(find.text('İş girişine geç'), findsOneWidget);
    });

    testWidgets('uyarıdan sonra metin yeniden ayrıştırılırsa uyarı kalkar',
        (tester) async {
      harness.health.handler = (_) async => otherDomainOnly('toplantı');
      await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'toplantı');
      expect(find.text('Bu bir iş kaydı gibi görünüyor.'), findsOneWidget);

      harness.health.handler = (_) async => healthEntry();
      await typeAndParse(tester, 'Öğlen tavuk yedim');

      expect(find.textContaining('iş kaydı gibi görünüyor'), findsNothing);
      expect(find.text('Bunları anladım'), findsOneWidget);
    });

    testWidgets(
        'karışık metin: bu alanın kayıtları önizlenir, üstte uyarı durur',
        (tester) async {
      harness.health.handler = (_) async => healthEntry(
            otherDomain: true,
            summary: 'Yarın 15:00 Ayşe ile toplantı',
          );
      final host = await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'Öğlen tavuk yedim, yarın Ayşe ile toplantı');

      expect(find.text('Bunları anladım'), findsOneWidget);
      expect(find.text('Tavuk göğsü · 200 gr'), findsOneWidget);
      expect(find.text('Metnin bir kısmı iş kaydı gibi görünüyor.'),
          findsOneWidget);
      expect(find.text('Yarın 15:00 Ayşe ile toplantı'), findsOneWidget);
      expect(find.text('Kaydet ve iş girişine geç'), findsOneWidget);

      // Uyarı önizleme kalemlerinin üstündedir.
      final warningTop = tester
          .getTopLeft(find.text('Metnin bir kısmı iş kaydı gibi görünüyor.'))
          .dy;
      final tileTop = tester.getTopLeft(find.text('Tavuk göğsü · 200 gr')).dy;
      expect(warningTop, lessThan(tileTop));

      // Olağan kaydet yalnızca bu alanı yazar ve sayfayı kapatır.
      await tester.tap(find.text('1 kaydı kaydet'));
      await tester.pumpAndSettle();
      expect(host.result, 1);
      expect(repository.saved.single.nutrition, hasLength(1));
      expect(repository.saved.single.tasks, isEmpty);
    });

    testWidgets(
        'karışık metin: "Kaydet ve iş girişine geç" önce kaydeder, sonra metni taşır',
        (tester) async {
      harness.health.handler =
          (_) async => healthEntry(otherDomain: true, summary: 'toplantı');
      // İş ayrıştırıcısı aynı metnin sağlık kısmını "diğer alan" diye işaretler.
      harness.work.handler =
          (_) async => workEntry(otherDomain: true, summary: 'Öğlen tavuk');
      final host = await openModal(tester, mode: QuickAddMode.health);
      const text = 'Öğlen tavuk yedim, yarın Ayşe ile toplantı';
      await typeAndParse(tester, text);

      await tester.tap(find.text('Kaydet ve iş girişine geç'));
      await tester.pumpAndSettle();

      expect(repository.saved.single.nutrition, hasLength(1));
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      expect(host.closed, isFalse, reason: 'sayfa açık kalır');
      expect(find.text('İş girişi'), findsOneWidget);
      expect(fieldText(tester), text);
      expect(find.textContaining('1 kayıt eklendi.'), findsOneWidget);

      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(harness.work.inputs, [text]);
      expect(find.text('3 kaydı kaydet'), findsOneWidget);
      expect(find.textContaining('sağlık kaydı gibi görünüyor'), findsNothing,
          reason:
              'sağlık kısmı zaten kaydedildi; geri yönlendirme çift kayıt olur');

      await tester.tap(find.text('3 kaydı kaydet'));
      await tester.pumpAndSettle();
      expect(host.closed, isTrue);
      expect(host.result, 4, reason: 'iki alanda kaydedilenlerin toplamı');
      expect(repository.saved, hasLength(2));
    });

    testWidgets('geçişte kayıt başarısız olursa alan değişmez, önizleme kalır',
        (tester) async {
      harness.health.handler =
          (_) async => healthEntry(otherDomain: true, summary: 'toplantı');
      repository.error = Exception('ağ yok');
      await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'metin');

      await tester.tap(find.text('Kaydet ve iş girişine geç'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Kayıt doğrulanamadı.'), findsOneWidget);
      expect(find.text('Bunları anladım'), findsOneWidget);
      expect(find.text('Kaydet ve iş girişine geç'), findsOneWidget);
      expect(find.text('İş girişi'), findsNothing);
    });

    testWidgets('alan değiştirip kaydettikten sonra X toplam sayıyı döndürür',
        (tester) async {
      harness.health.handler =
          (_) async => healthEntry(otherDomain: true, summary: 'toplantı');
      final host = await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'metin');
      await tester.tap(find.text('Kaydet ve iş girişine geç'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(host.closed, isTrue);
      expect(host.result, 1,
          reason: 'ilk alanda kaydedilen kalem bildirilmeli');
    });

    testWidgets('karışık önizlemede son kalem çıkarılırsa uyarı girişte kalır',
        (tester) async {
      harness.health.handler =
          (_) async => healthEntry(otherDomain: true, summary: 'toplantı');
      await openModal(tester, mode: QuickAddMode.health);
      await typeAndParse(tester, 'metin');

      await tester.tap(find.byTooltip('Bu kaydı çıkar'));
      await tester.pumpAndSettle();

      expect(find.text('Devam'), findsOneWidget);
      expect(find.text('Bu bir iş kaydı gibi görünüyor.'), findsOneWidget);
      expect(find.text('İş girişine geç'), findsOneWidget);
    });
  });

  group('dar ekran (375pt) ve metin ölçeği 1.3', () {
    late bool realFonts;

    setUpAll(() async => realFonts = await loadRealFonts());

    Future<void> openNarrow(WidgetTester tester, QuickAddMode mode) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(375, 667) * 2;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openModal(tester, mode: mode);
    }

    testWidgets('giriş + diğer alan uyarısı taşmaz', (tester) async {
      if (!realFonts) return markTestSkipped('Roboto bulunamadı');
      harness.health.handler = (_) async => otherDomainOnly(
            'Yarın 15:00 Ayşe ile vardiya planı görüşmesi ve aylık rapor',
          );
      await openNarrow(tester, QuickAddMode.health);
      await typeAndParse(tester, 'Yarın 15:00 Ayşe ile toplantı');

      expect(find.text('İş girişine geç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('önizleme + karışık uyarı + rutin kutucukları taşmaz',
        (tester) async {
      if (!realFonts) return markTestSkipped('Roboto bulunamadı');
      harness.work.handler = (_) async => workEntry(
            otherDomain: true,
            summary: 'Öğlen 200 gr tavuk göğsü ve 2 dilim tam çavdar ekmeği',
          );
      await openNarrow(tester, QuickAddMode.work);
      await typeAndParse(tester, 'karışık metin');

      expect(find.text('Kaydet ve sağlık girişine geç'), findsOneWidget);
      expect(find.text('3 kaydı kaydet'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Liste sonuna kadar kaydırılınca da taşma olmamalı.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('kaydetme sürerken düğme satırı taşmaz', (tester) async {
      if (!realFonts) return markTestSkipped('Roboto bulunamadı');
      repository.gate = Completer<void>();
      await openNarrow(tester, QuickAddMode.work);
      await typeAndParse(tester, 'metin');
      await tester.tap(find.text('3 kaydı kaydet'));
      await tester.pump();

      expect(find.text('Kaydediliyor…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      repository.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('bildirimler kapalıysa saatli görev için bildirim planlanmaz',
      (tester) async {
    harness.settings.settings =
        const UserSettings.defaults().copyWith(notificationsEnabled: false);
    final host = await openModal(tester);
    // Ayarlar yüklensin diye bir tur bekle.
    await tester.pumpAndSettle();
    await typeAndParse(tester, 'metin');
    await tester.tap(find.text('3 kaydı kaydet'));
    await tester.pumpAndSettle();

    expect(host.result, 3);
    expect(notifications.scheduled, isEmpty);
  });
}
