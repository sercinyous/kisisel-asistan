# Faz 4A — Sağlık derinleştirme ve düzenleme (tasarım)

Durum: onay bekliyor. Tarih: 2026-11-17. Sonraki: `2026-11-17-faz4b-cok-kullanicili-design.md`.

## Amaç ve neden
Uygulamanın sahibi günlük sayıların ötesini görmek istiyor: adım, uyku ve kalori hedefini haftalık ve aylık
kaç gün tutturduğunu, grafik olarak; bugün ne kadar yediğini ve yaktığını, genel durumunu ("bugün yağ yaktın",
"yerinde saydın", "biraz kaçırdın, telafi edebilirsin"). Besin girişi yavaş: sık yenen temel gıdaların 100 g
değerleri hazır olsun (manuel giriş de kalsın). Kayıt başlıklarını her listeden düzenleyip silebilmek istiyor.

## Hedefler
1. Adım, uyku, kalori için Hafta/Ay trend ekranı: hedef tutturma sayısı, yüzde, ortalama, seri, çubuk grafik.
2. Paketli temel besin listesi (100 g kcal ve makrolar) + öğün formunda arama ve gram/porsiyon hesabı.
3. Sağlık sekmesinde Enerji dengesi: alınan, yakılan, net; günlük yorum; haftalık/aylık ± grafik.
4. Görev, rutin, not, öğün ve antrenman başlıklarını her listede düzenle/sil.

## Hedef dışı
- Giriş, arkadaşlar, onboarding, taslaklar (Faz 4B).
- Tıbbi tavsiye ya da yağ yakımının kesin ölçümü; yorumlar "tahmini"dir.
- AI ayrıştırıcının besin listesini kullanması; mikro besin, barkod, fotoğraf.
- Raporlar sekmesine ya da sunucu raporlarına denge eklemek.
- Uygulama kapalıyken adım/uyku verisi (mevcut sınır).

## Karşıt hedefler (teknik olarak çalışsa da başarısızlık)
- Verisi olmayan günü "hedefi tutturamadı" saymak ve kullanıcıyı haksız kötü göstermek.
- Çok yüksek kalori açığını övmek.
- Raporlar sekmesindeki sayılarla çelişen ikinci bir hedef tanımı.

## Kısıtlar
`CLAUDE.md` kuralları (iki tema, `AppColors` getter'ları, Bento, 5 slotlu bar, Türkçe, hız kuralı, TODO yok).
Riverpod 2 (kod üretimi yok), `fl_chart`. `schema.sql` tek, idempotent betik; RLS ve yetkiler korunur. Mevcut
788 test geçmeli; web demo (`lib/main_demo.dart`) derlenmeli ve yeni ekranları sahte veriyle göstermeli.

## Tasarım

### 1. Trendler
- Giriş: Sağlık sekmesindeki Adım kartı (var) ve yeni Uyku ile Kalori kartları → "Trend" sayfası.
- Sayfa: metrik sekmesi (Adım | Uyku | Kalori), dönem anahtarı (Hafta | Ay), önceki/sonraki dönem okları.
- İçerik: "5/7 gün hedef" + yüzde + ortalama + önceki döneme göre fark; günlük çubuk grafik ve hedef çizgisi
  (tutan gün vurgulu, tutmayan soluk, verisiz gün boş); mevcut seri ve dönem içi en uzun seri.
  Kalori sekmesinde ikincil satır: protein tutturulan gün sayısı.
- Hedef kuralları (raporlarla aynı eşikler, `docs/SPEC_FAZ3.md` §2): adım ≥ `daily_steps`; uyku ≥ `sleep_minutes`;
  kalori hedefin %85–%110'u; protein ≥ hedefin %90'ı.
- Verisiz gün paydaya girmez ve "veri yok" diye ayrı sayılır (benim kararım). Raporların kendi paydası değişmez;
  fark README'de not edilir.
- Veri: `daily_health_metrics` (adım, uyku) ve `nutrition_logs` günlük toplamı (kalori, protein). Hesap saf
  Dart sınıflarıyla (`TrendStats`), testlenebilir. Gün sınırı cihaz yerel günü (mevcut Kokpit kuralı).

### 2. Besin listesi
- Paketli `assets/data/foods_tr.json`: ~150 temel gıda; alanlar: ad, takma adlar, kategori, 100 g için kcal,
  protein, karbonhidrat, yağ, porsiyonlar (ör. "1 adet" = 50 g), kaynak notu. Çiğ ve pişmiş ayrı satır.
  Sunucu tablosu yok: çevrimdışı çalışır, demoda ve testte aynı dosya kullanılır, sürümle güncellenir.
- Değerler USDA FoodData Central ve Türkiye Gıda Kompozisyon Veri Tabanı gibi iki kaynakla çapraz doğrulanır;
  doğrulanamayan satır listeye girmez. Otomatik tutarlılık testi: kcal ≈ 4·protein + 4·karb + 9·yağ (±%15).
- Öğün formunda "Besin ara": yazdıkça filtre (Türkçe karakter ve takma ad duyarsız); seçince gram alanı
  (varsayılan 100 g) ve porsiyon çipleri; kcal ve makrolar forma dolar, kullanıcı hâlâ elle düzenler.
  Kayıt `source = 'manual'` kalır; `quantity_text` "2 adet · 100 g". Elle giriş her zaman çalışır.

### 3. Enerji dengesi (Sağlık sekmesi)
- Profil: `user_settings`'e `height_cm`, `birth_year`, `sex` ('female'/'male'/null) eklenir (idempotent).
  Ayarlar > Profil'de doldurulur; Faz 4B onboarding'i aynı alanları sorar.
- Bazal yakım: Mifflin-St Jeor, 10·kg + 6,25·cm − 5·yaş + (erkek +5, kadın −161, belirtmeyen −78);
  kg = son tartı, yoksa `start_weight_kg`.
- Yakılan = bazal + `active_kcal` (kaynak Apple Health ya da Google Health). Antrenman kalorisi aktif
  kalorinin içinde sayılır; `active_kcal` 0 iken antrenman kaydı varsa onun kalorisi yedek olarak kullanılır
  (çift sayım yok). Bugün için bazal, geçen gün oranıyla işler ("şu ana kadar").
- Net = alınan − yakılan. Yorum bantları (sabitler tek yerde): net ≤ −1000 "çok yüksek açık" uyarısı (övgü
  değil); −1000…−150 "yağ yaktın" (haftalık tahmini değişim = Σnet ÷ 7700 kg); ±150 "yerinde saydın, yağ almadın";
  +150…+500 "biraz kaçırdın, telafi edebilirsin" + telafi (yaklaşık yürüyüş dakikası: 3,5 MET, kilo ile; ya da
  yarın bu kadar az); ≥ +500 "bugün fazla geçti, bir günle bozulmaz, yarın toparla".
- 18 yaşından küçükse yorum ve açık hedefi gösterilmez, yalnızca sayılar. Profil eksikse kart "Dengeyi hesaplamak
  için boy, yaş ve cinsiyet gerekli" der ve Ayarlar > Profil'e götürür.
- Gösterim: Kilo kartının altında "Enerji dengesi" kartı (alınan / yakılan / net, yorum, telafi satırı). Dokununca
  detay: günlük net çubuk grafiği (sıfır çizgisi, aşağı = açık mint, yukarı = fazla amber), "Alınan / Yakılan"
  çizgi görünümü anahtarı, hafta/ay toplam net ve tahmini yağ değişimi.

### 4. Düzenle / sil
- Bugün: Operasyon listelerinde (görev, rutin, not) üç nokta menüsü var; Kokpit'te ve ay günü listesinde yok.
- Eklenen: her liste satırında uzun basış menüsü (Düzenle / Sil) ve sola kaydırarak sil (onay ya da geri al
  çubuğu). Kapsam: görev, rutin, not başlıkları; Kokpit gün ve ay görünümü; öğün ve antrenman satırları.
  Ortak bileşen `lib/core/widgets/`. Rutin silinince tamamlama geçmişi de gider (mevcut cascade).
- "Görev başlıkları" burada başlığı (title) düzenleme ve silme olarak yorumlandı (benim yorumum).

## Yaklaşımlar
- Trend yeri: (a) Sağlık kartlarından açılan tek sayfa, segmentli — **seçildi**; (b) Raporlar sekmesine koymak:
  raporlar sunucu üretimi ve günlük, trend canlı veri; (c) Sağlık kartlarını büyütmek: grafik sığmaz.
- Besin kaynağı: (a) sunucu tablosu; (b) paketli JSON — **seçildi** (sunucusuz, çevrimdışı, test edilir);
  (c) dış API (Open Food Facts/USDA): Türkçe kapsamı zayıf, ağ bağımlı.
- Denge: (a) bazal formül + aktif kalori — **seçildi**; (b) HealthKit bazal enerji: Google kaynağında yok;
  (c) sabit çarpanlı TDEE: aktif kalori zaten ölçülüyor, çift sayım olur.

## Kullanıcının kararları
Trend, besin 100 g listesi, denge ve yorum, düzenle/sil istekleri; "denge için gereken alanları sisteme ekle,
kullanıcı doldurur"; manuel besin girişi kalsın.

## Benim kararlarım (itiraz edilebilir)
Yorum eşikleri ve 7700 kcal/kg; paketli JSON; verisiz gün paydada yok; kaydırma ve uzun basış kalıbı;
bazal formül ve "belirtmeyen" katsayısı; 18 yaş altı kuralı.

## Builder'a bırakılan
Grafik görünümü ve renk tonları, kart yerleşimi, tam Türkçe metinler, dosya düzeni, besin listesinin tam
içeriği (kurallara uygun), test yazımı.

## Doğrulama
`flutter analyze` 0 hata/uyarı; mevcut + yeni testler; besin tutarlılık testi; SQL testleri (profil sütunları);
web demo derlemesi. Gerçek cihazda denenmeden bitmiş sayılmaz: ilk TestFlight yapısında sayılar Fitbit/Sağlık
uygulamasıyla karşılaştırılır.
