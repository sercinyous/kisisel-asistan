import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kisisel_asistan/core/avatar/avatar_image.dart';
import 'package:kisisel_asistan/core/avatar/avatar_spec.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  group('initialsFor', () {
    test('ad soyadın ilk ve son harfi', () {
      expect(initialsFor('Sercan Kılıç'), 'SK');
      expect(initialsFor('ali veli can'), 'AC');
      expect(initialsFor('  ayşe  '), 'A');
    });

    test('Türkçe büyük harf: i → İ, ı → I', () {
      expect(initialsFor('ilker ışık'), 'İI');
      expect(initialsFor('çağla öz'), 'ÇÖ');
    });

    test('ad yoksa e-postanın @ öncesi, o da yoksa ?', () {
      expect(initialsFor(null, email: 'deniz.kaya@example.com'), 'DK');
      expect(initialsFor('', email: 'm***@gmail.com'), 'M');
      expect(initialsFor(null), '?');
      expect(initialsFor('***'), '?');
    });
  });

  group('AvatarChoice', () {
    test('satır yoksa baş harfler', () {
      final c = AvatarChoice.fromMap(const {});
      expect(c.kind, AvatarKind.initials);
      expect(c.version, 0);
      expect(const UserSettings.defaults().avatar, const AvatarChoice());
    });

    test('maskot, renk ve sürüm okunur; bilinmeyen maskot baş harfe düşer', () {
      final c = AvatarChoice.fromMap(const {
        'avatar_kind': 'mascot',
        'avatar_mascot': 'bal_porsugu',
        'avatar_color': 'sleep',
        'avatar_version': 3,
      });
      expect(c.kind, AvatarKind.mascot);
      expect(c.mascot!.name, 'Bal Porsuğu');
      expect(c.color, AvatarColorRole.sleep);
      expect(c.version, 3);
      expect(
        AvatarChoice.fromMap(const {'avatar_kind': 'mascot', 'avatar_mascot': 'ejderha'}).kind,
        AvatarKind.initials,
      );
      expect(AvatarChoice.fromMap(const {'avatar_kind': 'emoji'}).kind,
          AvatarKind.initials);
    });

    test('fotoğraf sürümü artar, kaldırınca renk korunur', () {
      const c = AvatarChoice(color: AvatarColorRole.ops, version: 2);
      final photo = c.withPhoto();
      expect(photo.kind, AvatarKind.photo);
      expect(photo.version, 3);
      final cleared = photo.cleared();
      expect(cleared.kind, AvatarKind.initials);
      expect(cleared.color, AvatarColorRole.ops);
      expect(cleared.version, 3);
      expect(photo.toMap(), {
        'avatar_kind': 'photo',
        'avatar_mascot': null,
        'avatar_color': 'ops',
        'avatar_version': 3,
      });
    });

    test('UserSettings avatarı okur ama toMap yazmaz', () {
      final s = UserSettings.fromMap(const {
        'avatar_kind': 'mascot',
        'avatar_mascot': 'kurt',
      });
      expect(s.avatar.mascotId, 'kurt');
      expect(s.toMap().keys.where((k) => k.startsWith('avatar')), isEmpty);
      expect(s.copyWith(dailySteps: 9000).avatar.mascotId, 'kurt');
    });

    test('16 maskot, kimlikler tekil ve şema check\'ine uyar', () {
      expect(mascots, hasLength(16));
      expect(mascots.map((m) => m.id).toSet(), hasLength(16));
      for (final m in mascots) {
        expect(RegExp(r'^[a-z_]{1,32}$').hasMatch(m.id), isTrue, reason: m.id);
        expect(m.trait, isNotEmpty);
      }
    });
  });

  group('squareAvatarJpeg', () {
    test('ortadan kare kırpar ve 512 piksele küçültür', () {
      final source = img.Image(width: 1200, height: 800);
      img.fill(source, color: img.ColorRgb8(200, 30, 30));
      final png = Uint8List.fromList(img.encodePng(source));
      final out = squareAvatarJpeg(png);
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
    });

    test('okunamayan veri FormatException', () {
      expect(() => squareAvatarJpeg(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });
  });
}
