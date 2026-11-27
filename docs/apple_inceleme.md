# Apple inceleyici demo hesabı

App Store incelemesi için giriş yapılabilen, kişisel veri içermeyen bir demo hesabı.
Depoda gerçek e-posta ya da şifre **yoktur**; aşağıdaki yer tutucuları yalnızca
Supabase Dashboard'da ve App Store Connect'te kendin doldur.

## 1. Demo hesabını aç (Supabase Dashboard)

1. Kullanacağın adresi seç (ör. senin kontrolündeki bir alias: `DEMO_EPOSTA`).
   Güçlü, rastgele bir şifre üret (`DEMO_SIFRE`); bir parola yöneticisinde sakla.
2. **Authentication > Users > Add user > Create new user**: e-posta `DEMO_EPOSTA`,
   şifre `DEMO_SIFRE`, **Auto Confirm User** işaretli.

## 2. Demo verisini yükle

1. `supabase/seed_review_demo.sql` dosyasını aç, en üstteki
   `'demo-inceleme@ornek.invalid'` değerini `DEMO_EPOSTA` ile değiştir (dosyayı
   depoya bu hâliyle **kaydetme**; yalnızca SQL Editor'a yapıştır).
2. SQL Editor'da çalıştır. "Demo verisi yüklendi" bildirimi görülür.
   Son 14 günün adım/uyku/kalori özetleri, öğünler, antrenmanlar, görevler,
   notlar ve rutinler yüklenir; profil "ilk kurulum tamamlandı" olur.
3. Tekrar çalıştırmak güvenlidir (demo kullanıcının bu satırları yenilenir).

## 3. Uygulamada kontrol

- iPhone'da `DEMO_EPOSTA` / `DEMO_SIFRE` ile giriş yap; Kokpit, İşler,
  Sağlık ve İçgörü dolu görünmeli.
- Sağ üstteki profil ikonu > Hesap: Gizlilik ve koşullar (en üstte AI onayı
  anahtarı), Sorun bildir ve kartın en altında Hesabımı sil satırları görünmeli
  (Hesabımı sil, Profil ve hedefler sayfasının en altında da var; demo hesabında
  **Hesabımı sil**'i deneme; denersen 1–2. adımları tekrarla).
- Demo hesabında AI onayı boştur: ilk "+" kullanımında onay sayfası çıkmalı.
- İçgörü sekmesinde "Raporu yeniden oluştur" bir kez denenebilir.

## 4. App Store Connect

**App Information / App Review Information > Sign-In Information**
(Sign-in required: açık)

```
User name: DEMO_EPOSTA
Password: DEMO_SIFRE
```

**Review Notes** (aynen yapıştır, yer tutucu yok):

```
Ritim is a Turkish personal assistant (tasks, routines, reminders, meals and
health goals). Anyone can sign up; please use the demo account provided above
(e-mail + password on the sign-in screen, after tapping "E-posta ile giriş").

Sign-in options (Guideline 4.8): e-mail, Sign in with Apple ("Apple ile devam
et", shown first on iOS) and Google. Sign in with Apple only asks for name and
e-mail (the user may hide the e-mail). Account deletion (Hesap > Hesabımı sil)
asks Apple users to re-confirm with Apple and then revokes the app's Apple
token via Apple's REST API before deleting all data (Guideline 5.1.1(v)).

The demo account is pre-filled with sample, non-personal data (tasks, notes,
routines, meals, workouts and 14 days of step/sleep/energy summaries).

Health data: the app reads steps, sleep, active energy, workouts, height and weight from
Apple Health only after the user grants permission and confirms import for the
account (Sağlık tab). It never writes to Apple Health. Health data is not used
for advertising and is not shared with third parties.

Health calculations and citations (Guideline 1.4.1): calorie, protein, water
and fiber targets are informational, not medical advice, and the app gives no
supplement dosing. Sources with links are listed at Sağlık > Plan >
"Kaynaklar" and at Hesap > "Gizlilik ve koşullar" > "Sağlık hesaplarının
kaynakları" (Mifflin-St Jeor 1990, ISSN protein 2017, Hall 2008, CDC, EFSA).

AI (third-party data sharing, explicit consent): the first time the user taps
the center "+" button, a consent sheet explains that the typed text is sent to
Google Gemini; nothing is sent unless the user taps "Kabul ediyorum". Report
comments use only computed numbers and are also skipped without consent.
Consent can be withdrawn at: profile avatar (top right of Kokpit) > Hesap >
"Gizlilik ve koşullar" > "AI özellikleri (Google Gemini)" switch.

Account deletion (two taps from the home screen): profile avatar (top right of
Kokpit) > Hesap > "Hesabımı sil" (last row of the bottom card). Type SİL or SIL
(either spelling works with an English keyboard) and tap "Hesabımı kalıcı
olarak sil". This permanently deletes the account and all its data on the
server. It is also reachable during first-run setup ("Hesabı sil" at the top).

Friends and stories (user-generated content, Guideline 1.2): friends are added
by e-mail invite and see only what the user turns on (goal-hit day counts,
optional stories that last 24 hours). Display names, profile photos and
stories are visible only to accepted friends. Hesap > "Arkadaşlar": each friend
row and each incoming request has "Engelle" (block; a blocked user cannot send
requests again), "Bildir" (report, reviewed within 24 hours) and remove
friend. The Terms forbid abusive content.

Body progress photos (Sağlık > Vücut) are private: stored in a per-user
private bucket, never shown to friends. Camera and photo library are used only
for the profile photo and progress photos.

Notifications are local only (task, routine and reminder alerts, optional
health nudges); they can be turned off at Hesap > "Bildirimler". No push
server, no marketing messages. The app is not a medical device and makes no
diagnostic claims.

Terms and privacy are linked on the sign-in screen before an account is
created, and in the app at Hesap > "Kullanım koşulları" and Hesap >
"Gizlilik ve koşullar".
Feedback: Hesap > "Sorun bildir".

The UI is in Turkish.
```

**Privacy Policy URL**: `docs/gizlilik.md` içeriğini herkese açık bir sayfada
yayınla (ör. GitHub Pages ya da Notion herkese açık sayfa) ve o adresi gir.
