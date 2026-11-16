# Kişisel Asistan & Operasyon Merkezi

## 1. Teknoloji ve mimari
- Flutter (Dart) + Riverpod 2.x (kod üretimi yok) + Supabase + Gemini Flash API.
- Tek kullanıcılı iOS kişisel asistan uygulaması; Ad-Hoc dağıtım, Codemagic.
- Klasör yapısı feature-first: `lib/features/<özellik>/{domain,data,presentation}`, ortak kod `lib/core/`.
- Ayrıntılı sözleşme: `docs/SPEC_FAZ2.md`.

## 2. Tasarım dili
- İki tema: saf OLED siyah (`#000000`) koyu tema **varsayılandır**; açık (beyaz) tema da desteklenir.
  Tercih Ayarlar > Görünüm'den seçilir (Sistem / Açık / Koyu) ve cihazda saklanır (`docs/SPEC_FAZ3.md` §9).
- Renkler yalnızca `AppColors.<rol>` getter'larından okunur; değerleri etkin palete (`AppPalette.dark` /
  `AppPalette.light`) göre değişir. Bu yüzden bir `AppColors` başvurusu **asla `const` içine alınmaz**
  (`const Icon(..., color: AppColors.x)` derlenmez) ve `static final`/`late final` alanda saklanmaz;
  her build'de yeniden okunur. Yeni renk gerekirse iki palete birden rol olarak eklenir.
- `Colors.black` / `Colors.white` / `Color(0x...)` yazılmaz; dolgu üstü işaret için `AppColors.onAccent`,
  karartma için `AppColors.scrim`, gölge için `AppColors.shadow` kullanılır.
- Bento Grid kartlar: `lib/core/widgets/bento.dart` içindeki `BentoGrid` ve `BentoCard` kullanılır;
  elle `Container` + kenarlık yazılmaz.
- Alt navigasyon: Instagram'ın güncel barı gibi yüzen cam kapsül (bulanık, yarı saydam, tam yuvarlak),
  etiketsiz, 5 slot (`lib/core/widgets/app_bottom_bar.dart`). Seçili sekme ikonun arkasındaki yarı saydam
  kapsülle belirtilir. Slotlar: Kokpit, Operasyon, **+** (AI giriş), Sağlık, Raporlar. Yeni sekme eklenmez.
  İçerik barın arkasından akar; kaydırılan ekranlar altta en az 120 boşluk bırakır.
- Renk, yarıçap ve boşluklar yalnızca `lib/core/theme/app_theme.dart` içindeki
  `AppColors`, `AppRadii`, `AppSpacing` üzerinden; bileşenlerde ham hex yazılmaz.
- UI metinleri Türkçe.

## 3. Hız kuralı
- Her dosyadan sonra `flutter analyze` ya da `flutter test` ÇALIŞTIRMA.
- Önce istenen tüm dosyaları art arda oluştur; yalnızca görevin tamamı bittiğinde
  tek seferlik `flutter analyze` ile hata kontrolü yap.

## 4. Yanıt biçimi
- Uzun açıklama ve adım adım anlatım yok.
- Yalnızca oluşturulan/değişen dosya yollarını listele ve sonraki adıma geç.

## 5. Tam kod
- Hiçbir dosyada `// TODO` ya da yer tutucu bırakma; doğrudan çalışır production kodu yaz.
