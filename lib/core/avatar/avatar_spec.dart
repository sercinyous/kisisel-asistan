import 'dart:ui' show Color;

import '../theme/app_theme.dart';

/// Profil avatarının türü (`user_settings.avatar_kind`).
enum AvatarKind {
  initials('initials'),
  mascot('mascot'),
  photo('photo');

  const AvatarKind(this.dbValue);
  final String dbValue;

  static AvatarKind fromDb(Object? value) {
    for (final k in values) {
      if (k.dbValue == value) return k;
    }
    return AvatarKind.initials;
  }
}

/// Uygulamadaki 16 maskot (`assets/mascots/<id>.svg`).
class Mascot {
  const Mascot(this.id, this.name, this.trait);

  final String id;
  final String name;

  /// Tek satırlık kişilik.
  final String trait;

  String get assetPath => 'assets/mascots/$id.svg';
}

const List<Mascot> mascots = [
  Mascot('kurt', 'Kurt', 'Sürüsüne sadık, hedefine kararlı.'),
  Mascot('bal_porsugu', 'Bal Porsuğu', 'Korkusuz; zor işten kaçmaz.'),
  Mascot('baykus', 'Baykuş', 'Gece kuşu, bilge planlayıcı.'),
  Mascot('ahtapot', 'Ahtapot', 'Sekiz kolla çoklu görev ustası.'),
  Mascot('kirpi', 'Kirpi', 'Küçük ama sınırlarını iyi korur.'),
  Mascot('penguen', 'Penguen', 'Soğukkanlı bir ekip oyuncusu.'),
  Mascot('tavsan', 'Tavşan', 'Hızlı başlar, enerjisi bitmez.'),
  Mascot('tilki', 'Tilki', 'Her işe kurnaz bir kısayol bulur.'),
  Mascot('kaplumbaga', 'Kaplumbağa', 'Yavaş ama istikrarlı kazanır.'),
  Mascot('panda', 'Panda', 'Sakin, dengeli, keyfine düşkün.'),
  Mascot('ari', 'Arı', 'Çalışkan, düzenli, üretken.'),
  Mascot('yunus', 'Yunus', 'Neşeli ve sosyal; herkesle anlaşır.'),
  Mascot('aslan', 'Aslan', 'Cesur bir lider, sözünün eri.'),
  Mascot('kedi', 'Kedi', 'Bağımsız ama rutinlerine bağlı.'),
  Mascot('tembel_hayvan', 'Tembel Hayvan', 'Acele etmez, dinlenmeyi bilir.'),
  Mascot('kartal', 'Kartal', 'Büyük resmi görür, hedefe odaklanır.'),
];

Mascot? mascotById(String? id) {
  for (final m in mascots) {
    if (m.id == id) return m;
  }
  return null;
}

/// Baş harf avatarının arka planı: `AppColors` rol adları.
enum AvatarColorRole {
  accent('accent', 'Vurgu'),
  ops('ops', 'Operasyon'),
  fitness('fitness', 'Spor'),
  nutrition('nutrition', 'Beslenme'),
  sleep('sleep', 'Uyku'),
  water('water', 'Su'),
  warning('warning', 'Turuncu'),
  danger('danger', 'Kırmızı');

  const AvatarColorRole(this.dbValue, this.label);
  final String dbValue;
  final String label;

  /// Etkin paletten okunur; her build'de yeniden çağrılmalıdır.
  Color get color => switch (this) {
        AvatarColorRole.accent => AppColors.accent,
        AvatarColorRole.ops => AppColors.ops,
        AvatarColorRole.fitness => AppColors.fitness,
        AvatarColorRole.nutrition => AppColors.nutrition,
        AvatarColorRole.sleep => AppColors.sleep,
        AvatarColorRole.water => AppColors.water,
        AvatarColorRole.warning => AppColors.warning,
        AvatarColorRole.danger => AppColors.danger,
      };

  static AvatarColorRole? fromDb(Object? value) {
    for (final r in values) {
      if (r.dbValue == value) return r;
    }
    return null;
  }
}

/// Kişinin avatar seçimi (`user_settings.avatar_*` sütunları).
class AvatarChoice {
  const AvatarChoice({
    this.kind = AvatarKind.initials,
    this.mascotId,
    this.color,
    this.version = 0,
  });

  /// Satırdaki alanlar; maskot kimliği tanınmıyorsa baş harflere düşer.
  factory AvatarChoice.fromMap(Map<String, dynamic> map) {
    var kind = AvatarKind.fromDb(map['avatar_kind']);
    final mascot = mascotById(map['avatar_mascot'] as String?);
    if (kind == AvatarKind.mascot && mascot == null) kind = AvatarKind.initials;
    return AvatarChoice(
      kind: kind,
      mascotId: mascot?.id,
      color: AvatarColorRole.fromDb(map['avatar_color']),
      version: (map['avatar_version'] as num?)?.toInt() ?? 0,
    );
  }

  final AvatarKind kind;
  final String? mascotId;
  final AvatarColorRole? color;

  /// Her fotoğraf yüklemesinde artar (imzalı adres önbelleğini kırar).
  final int version;

  Mascot? get mascot => mascotById(mascotId);

  Map<String, dynamic> toMap() => {
        'avatar_kind': kind.dbValue,
        'avatar_mascot': mascotId,
        'avatar_color': color?.dbValue,
        'avatar_version': version,
      };

  AvatarChoice withMascot(String id) => AvatarChoice(
        kind: AvatarKind.mascot,
        mascotId: id,
        color: color,
        version: version,
      );

  AvatarChoice withPhoto() => AvatarChoice(
        kind: AvatarKind.photo,
        mascotId: mascotId,
        color: color,
        version: version + 1,
      );

  AvatarChoice withColor(AvatarColorRole role) => AvatarChoice(
        kind: kind,
        mascotId: mascotId,
        color: role,
        version: version,
      );

  AvatarChoice cleared() => AvatarChoice(color: color, version: version);

  @override
  bool operator ==(Object other) =>
      other is AvatarChoice &&
      other.kind == kind &&
      other.mascotId == mascotId &&
      other.color == color &&
      other.version == version;

  @override
  int get hashCode => Object.hash(kind, mascotId, color, version);
}

/// Addan (yoksa e-postanın @ öncesinden) en çok iki baş harf; Türkçe büyük
/// harf kuralıyla (i → İ, ı → I). Hiçbiri yoksa '?'.
String initialsFor(String? name, {String? email}) {
  String source = (name ?? '').trim();
  if (source.isEmpty) source = (email ?? '').trim();
  if (source.contains('@')) source = source.split('@').first;
  final parts = source
      .split(RegExp(r'[\s._\-]+'))
      .where((p) => p.isNotEmpty && RegExp(r'\w', unicode: true).hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  String first(String p) => String.fromCharCode(p.runes.first);
  final letters = parts.length > 1
      ? first(parts.first) + first(parts.last)
      : first(parts.first);
  return _upperTr(letters);
}

String _upperTr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(switch (c) {
      'i' => 'İ',
      'ı' => 'I',
      _ => c.toUpperCase(),
    });
  }
  return b.toString();
}
