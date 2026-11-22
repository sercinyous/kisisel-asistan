import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kisisel_asistan/core/avatar/avatar_photo_store.dart';
import 'package:kisisel_asistan/core/avatar/avatar_spec.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/widgets/ritim_avatar.dart';
import 'package:kisisel_asistan/features/friends/data/friends_repository.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_button.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_screen.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_friends_row.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/avatar_picker_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

/// Bellekte fotoğraf deposu: yüklenen baytları ve imzalı adres isteklerini tutar.
class _MemoryPhotoStore implements AvatarPhotoStore {
  _MemoryPhotoStore({this.url});

  final String? url;
  final List<Uint8List> uploads = [];
  final List<(String, int)> urlRequests = [];
  int removes = 0;

  @override
  bool get supported => true;

  @override
  Future<void> upload(Uint8List jpeg) async => uploads.add(jpeg);

  @override
  Future<void> remove() async => removes++;

  @override
  Future<String?> signedUrl(String userId, int version) async {
    urlRequests.add((userId, version));
    return url;
  }
}

Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(20, 120, 220));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late FakeSettingsRepository settings;
  late _MemoryPhotoStore store;
  Uint8List? picked;
  final pickedSources = <AvatarPhotoSource>[];

  setUp(() {
    settings = FakeSettingsRepository(
      settings: const UserSettings.defaults().copyWith(displayName: 'Ayşe Demir'),
    );
    store = _MemoryPhotoStore();
    picked = null;
    pickedSources.clear();
  });

  List<Override> overrides({bool photo = true}) => [
        settingsRepositoryProvider.overrideWithValue(settings),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        avatarPhotoStoreProvider.overrideWithValue(store),
        avatarPhotoSupportedProvider.overrideWithValue(photo),
        avatarImagePickerProvider.overrideWithValue((source) async {
          pickedSources.add(source);
          return picked;
        }),
        friendsRepositoryProvider.overrideWithValue(DemoFriendsRepository()),
      ];

  Future<void> pump(WidgetTester tester, Widget child, {bool photo = true}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(photo: photo),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('RitimAvatar', () {
    testWidgets('baş harfler, renk rolü ve erişilebilirlik etiketi',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const Center(
          child: RitimAvatar(
            choice: AvatarChoice(color: AvatarColorRole.sleep),
            name: 'ilker Işık',
            size: 64,
          ),
        ),
      );
      expect(find.text('İI'), findsOneWidget);
      final box = tester.widget<ColoredBox>(find.descendant(
        of: find.byType(RitimAvatar),
        matching: find.byType(ColoredBox),
      ));
      expect(box.color, AppColors.sleep);
      expect(tester.getSize(find.byType(RitimAvatar)), const Size(64, 64));
      expect(find.bySemanticsLabel('ilker Işık, avatar: baş harfler'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('maskot SVG olarak çizilir', (tester) async {
      await pump(
        tester,
        const RitimAvatar(
          choice: AvatarChoice(kind: AvatarKind.mascot, mascotId: 'kurt'),
          name: 'Ayşe',
          size: 48,
        ),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.bySemanticsLabel('Ayşe, avatar: Kurt'), findsOneWidget);
    });

    testWidgets('fotoğraf: imzalı adres (kullanıcı, sürüm) için istenir; '
        'adres yoksa baş harfler', (tester) async {
      await pump(
        tester,
        const RitimAvatar(
          choice: AvatarChoice(kind: AvatarKind.photo, version: 4),
          name: 'Ayşe',
          userId: 'u-1',
        ),
      );
      expect(store.urlRequests, [('u-1', 4)]);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('fotoğraf adresi varsa ağ resmi çizilir', (tester) async {
      store = _MemoryPhotoStore(url: 'https://example.invalid/a.jpg');
      await pump(
        tester,
        const RitimAvatar(
          choice: AvatarChoice(kind: AvatarKind.photo, version: 1),
          name: 'Ayşe',
          userId: 'u-1',
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('Avatar seçim sayfası', () {
    testWidgets('16 maskot adlarıyla; seçim kaydedilir, Kaldır baş harflere '
        'döner', (tester) async {
      await pump(tester, const AvatarPickerSheet());
      expect(find.text('Maskot seç'), findsOneWidget);
      for (final m in mascots) {
        expect(find.byKey(Key('mascot-${m.id}')), findsOneWidget, reason: m.id);
      }
      expect(find.text('Bal Porsuğu'), findsOneWidget);
      expect(find.byKey(const Key('avatar-remove')), findsNothing);

      await tester.tap(find.byKey(const Key('mascot-bal_porsugu')));
      await tester.pumpAndSettle();
      expect(settings.savedAvatars.last.kind, AvatarKind.mascot);
      expect(settings.savedAvatars.last.mascotId, 'bal_porsugu');

      await tester.ensureVisible(find.byKey(const Key('avatar-color-water')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-color-water')));
      await tester.pumpAndSettle();
      expect(settings.savedAvatars.last.color, AvatarColorRole.water);
      expect(settings.savedAvatars.last.mascotId, 'bal_porsugu');

      await tester.ensureVisible(find.byKey(const Key('avatar-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-remove')));
      await tester.pumpAndSettle();
      expect(settings.savedAvatars.last.kind, AvatarKind.initials);
      expect(settings.savedAvatars.last.color, AvatarColorRole.water);
      expect(store.removes, 0, reason: 'fotoğraf yoktu');
      expect(find.byKey(const Key('avatar-remove')), findsNothing);
    });

    testWidgets('galeriden seçilen fotoğraf kare 512 JPEG olarak yüklenir, '
        'sürüm artar', (tester) async {
      picked = _png(900, 600);
      await pump(tester, const AvatarPickerSheet());
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('avatar-gallery')));
        for (var i = 0; i < 50 && settings.savedAvatars.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(pickedSources, [AvatarPhotoSource.gallery]);
      expect(store.uploads, hasLength(1));
      final jpeg = img.decodeJpg(store.uploads.single)!;
      expect((jpeg.width, jpeg.height), (512, 512));
      expect(settings.savedAvatars.single.kind, AvatarKind.photo);
      expect(settings.savedAvatars.single.version, 1);

      // Kaldır fotoğrafı depodan da siler.
      await tester.tap(find.byKey(const Key('avatar-remove')));
      await tester.pumpAndSettle();
      expect(store.removes, 1);
      expect(settings.savedAvatars.last.kind, AvatarKind.initials);
    });

    testWidgets('kamerada vazgeçilirse hiçbir şey yazılmaz', (tester) async {
      await pump(tester, const AvatarPickerSheet());
      await tester.tap(find.byKey(const Key('avatar-camera')));
      await tester.pumpAndSettle();
      expect(pickedSources, [AvatarPhotoSource.camera]);
      expect(store.uploads, isEmpty);
      expect(settings.savedAvatars, isEmpty);
    });

    testWidgets('fotoğraf desteklenmiyorsa (web demosu) yalnızca maskot',
        (tester) async {
      await pump(tester, const AvatarPickerSheet(), photo: false);
      expect(find.byKey(const Key('avatar-camera')), findsNothing);
      expect(find.byKey(const Key('avatar-gallery')), findsNothing);
      expect(find.byKey(const Key('mascot-kurt')), findsOneWidget);
    });
  });

  group('Arkadaşların avatarları', () {
    testWidgets('arkadaş listesi her satırda avatarı gösterir', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(800, 1700);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(theme: AppTheme.dark, home: const FriendsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final elif = tester.widget<RitimAvatar>(
          find.byKey(const ValueKey('friend-avatar-f-1')));
      expect(elif.choice.mascotId, 'tilki');
      final masked = tester.widget<RitimAvatar>(
          find.byKey(const ValueKey('friend-avatar-f-2')));
      expect(masked.choice.kind, AvatarKind.initials);
      expect(masked.choice.color, AvatarColorRole.sleep);
      expect(find.byKey(const ValueKey('friend-avatar-me')), findsOneWidget);
    });

    testWidgets('Kokpit profil düğmesi avatarı ve davet rozetini gösterir',
        (tester) async {
      settings.settings = settings.settings!.copyWith(
        avatar: const AvatarChoice(kind: AvatarKind.mascot, mascotId: 'aslan'),
      );
      await pump(tester, const Center(child: FriendsButton()));
      final avatar = tester.widget<RitimAvatar>(find.descendant(
        of: find.byKey(const Key('kokpit-avatar')),
        matching: find.byType(RitimAvatar),
      ));
      expect(avatar.choice.mascotId, 'aslan');
      expect(find.text('1'), findsOneWidget, reason: 'bekleyen davet rozeti');
      expect(find.byTooltip('Hesap (1 davet)'), findsOneWidget);
    });

    testWidgets('İçgörü arkadaş satırı arkadaş avatarlarını üst üste gösterir',
        (tester) async {
      await pump(tester, const ReportsFriendsRow());
      expect(find.byKey(const ValueKey('reports-friend-avatar-f-1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('reports-friend-avatar-f-2')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('reports-friend-avatar-me')),
          findsNothing);
    });
  });
}
