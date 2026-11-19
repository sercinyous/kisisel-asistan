# Apple inceleyici demo hesabı

App Store incelemesi için giriş yapılabilen, kişisel veri içermeyen bir demo hesabı.
Depoda gerçek e-posta ya da şifre **yoktur**; aşağıdaki yer tutucuları yalnızca
Supabase Dashboard'da ve App Store Connect'te kendin doldur.

## 1. Demo hesabını aç (Supabase Dashboard)

Kayıt kapısı (`signup_invite_gate`) davetsiz e-postayla hesap açılmasını engeller ve
Dashboard'dan da kapatılamaz. Bu yüzden önce o e-posta için bekleyen bir davet eklenir.

1. Kullanacağın adresi seç (ör. senin kontrolündeki bir alias: `DEMO_EPOSTA`).
   Güçlü, rastgele bir şifre üret (`DEMO_SIFRE`); bir parola yöneticisinde sakla.
2. **SQL Editor**'da kendi hesabınla (sahip) bekleyen davet ekle:

   ```sql
   insert into public.friend_requests (from_user, target_email)
   select id, lower('DEMO_EPOSTA') from auth.users where email = 'SAHIP_EPOSTA';
   ```

3. **Authentication > Users > Add user > Create new user**: e-posta `DEMO_EPOSTA`,
   şifre `DEMO_SIFRE`, **Auto Confirm User** işaretli.
4. Davet artık gerekmez; inceleyicinin seni arkadaş listesinde görmemesi için sil:

   ```sql
   delete from public.friend_requests
   where target_email = lower('DEMO_EPOSTA') and status = 'pending';
   ```

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
- Sağ üstteki profil ikonu > Hesap: Yardım ve gizlilik ile Sorun bildir satırları;
  Hesabımı sil, Profil ve hedefler sayfasının en altında görünmeli
  (demo hesabında **Hesabımı sil**'i deneme; denersen 1–2. adımları tekrarla).
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
This is a private personal-assistant app for a small invite-only group. Sign-up
is restricted to invited e-mail addresses, so please use the demo account
provided above (e-mail + password on the sign-in screen; do not use "Sign in
with Google").

The demo account is pre-filled with sample, non-personal data (tasks, notes,
routines, meals, workouts and 14 days of step/sleep/energy summaries).

Health data: the app reads steps, sleep, active energy, height and weight from
Apple Health only after the user grants permission and confirms import for the
account (Health tab). It never writes to Apple Health. Health data is not used
for advertising and is not shared with third parties.

AI quick add (center "+" button): the text the user types is sent through our
server function to Google Gemini to turn it into a task/meal/note.

Account deletion: Settings (gear icon on Kokpit) > "Hesabımı sil", type SİL to
confirm. This permanently deletes the account and all its data on the server.
Privacy policy: Settings > "Gizlilik". Feedback: Settings > "Sorun bildir".

The UI is in Turkish.
```

**Privacy Policy URL**: `docs/gizlilik.md` içeriğini herkese açık bir sayfada
yayınla (ör. GitHub Pages ya da Notion herkese açık sayfa) ve o adresi gir.
