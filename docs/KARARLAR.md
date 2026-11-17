# Kararlar ve kalıcı notlar

Otomatik hafıza bulut oturumlarında taşınmaz; kalıcı kararlar burada tutulur. Yeni karar
alınınca bir satır eklenir. Şema için tek kaynak `supabase/schema.sql`, mimari için `docs/SPEC_*.md`.

## Ürün
- **Ritim** (Kişisel Asistan): tek kullanıcılı iOS uygulaması. Pusholder operasyonu (editörler Duhan, İlhan,
  Mehmet, Sedat; vardiya ve görevler) ile kişisel sağlık (84,5 → 78 kg hedefi, antrenman, makrolar) bir arada.
- App Store Connect adı "Ritim: Rutin, İş ve Sağlık"; bundle id `com.sercinyous.kisiselasistan`;
  SKU `kisiselasistan-ios`.
- Aylık sabitler (ör. ayın 15'i maaş ödemesi) bitiş gününden 3 gün önce görünür, gün geçince "gecikti" olur,
  ay sonunda "yapılmadı" diye kapanır. Tarih hafta sonuna denk gelse de kaymaz.
- Tek seferlik olaylar (dişçi, kontrol) ayrı görev olarak girilir; rutinler günlük, haftalık ve aylık tekrar eder.
- AI girişi iki ayrı kapı: **İş** ve **Sağlık ve beslenme**. İkisi birbirine karışmaz.
- Kokpit Gün ve Ay görünümü; Ayarlar'da hedefler (kilo, kalori), bildirimler, görünüm, ekip, hesap.
- Günlük ve haftalık raporlar sunucuda otomatik üretilir (Edge Function `generate-reports` + pg_cron).
  Dağıtım (fonksiyon, secret, Vault, `supabase/cron.sql`) kullanıcı tarafında bekliyor; o zamana kadar
  Raporlar sekmesi boş kalır.

## Tasarım
- İki tema: saf OLED siyah (varsayılan) ve açık. Ayrıntı `CLAUDE.md` §2 ve `docs/SPEC_FAZ3.md` §10.
- Alt bar yüzen cam kapsül, etiketsiz, 5 slot. Yeni sekme eklenmez.
- Bir skill'in önerisi `CLAUDE.md` ile çelişirse `CLAUDE.md` kazanır (ör. ham renk ve `Theme.of(context)`
  yerine `AppColors` getter'ları).

## Yapay zeka (Gemini)
- Model `gemini-3.8-flash`, `thinkingLevel: low`, `temperature` verilmez, `responseSchema` kullanılır.
  Model kalkarsa uygulama yeniden yazılmaz: `GEMINI_MODEL` dart-define ile değişir.
- Hata 404 = model bulunamadı. Hata 402 = ön ödemeli bakiye ya da fatura bitti (AI Studio > Billing).

## Dağıtım
- Codemagic: `ios-testflight` (main'e push) ve `ios-adhoc` (elle). `ios/` CI'da `flutter create` ile üretilir,
  `tool/configure_ios.sh` yamalar. Derleme numarası = TestFlight'taki son numara + 1.
- Ortam grubu `app_secrets`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY`, isteğe bağlı `GEMINI_MODEL`,
  `GOOGLE_IOS_CLIENT_ID`. `SUPABASE_URL` yalnızca `https://<ref>.supabase.co` biçiminde olmalı (yol eklenmez).
- App Store Connect bağlantısı: Codemagic'te `kisisel-asistan-asc`.

## Sağlık verisi kaynağı
- Varsayılan Apple Health (HealthKit). Fitbit Web API 2 Kas 2026'da kapandı; halefi Google Health API
  (`https://health.googleapis.com/v4/`). Google OAuth "Testing" modunda yenileme belirteci yaklaşık 7 günde
  biter; uygulama "Google'a yeniden bağlan" durumunu gösterir.
- Aynı anda tek kaynak veri yazar (çift sayım olmasın).

## Güvenlik kuralları
- `service_role` ya da secret anahtar uygulamaya, repoya, sohbete girmez. Yalnızca anon/publishable anahtar.
- `.p8`, `.p12`, parola ve anahtar değerleri sohbete yapıştırılmaz; yalnızca Codemagic'e girilir.
- Gerçek Google client id repoya gömülmez; yalnızca Codemagic'te `GOOGLE_IOS_CLIENT_ID`.
- Supabase MCP salt-okunur ve tek projeye kilitli (`.mcp.json`); yazan araçlar `.claude/settings.json` ile
  engelli. Yalnızca şema, politika, advisor ve log sorgulanır; kullanıcı tablolarında SELECT çalıştırılmaz.
  Salt-okunur kip prompt injection ile veri sızmasını engellemez, bu yüzden bu kural elle uygulanır.

## Süreç
- Hız kuralı: dosya başına analyze/test yok, iş bitince tek seferlik kontrol.
- Son kapsamlı inceleme yapı kurulduktan sonra yapılır.
- Bekleyenler: Gemini faturası, otomatik rapor dağıtımı, özel uygulama ikonu, Google Health PR'ı.
