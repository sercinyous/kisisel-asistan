#!/usr/bin/env bash
# iOS projesini HealthKit + yerel bildirimler + Google ile giriş için yapılandırır.
# macOS'ta, proje kökünden çalıştırılır:  bash tool/configure_ios.sh
# Tekrar tekrar çalıştırılabilir (idempotent). Codemagic de her derlemede çağırır.
#
# İsteğe bağlı ortam değişkeni:
#   GOOGLE_IOS_CLIENT_ID  Google Cloud'daki iOS OAuth istemci kimliği
#                         (1234567890-abc...xyz.apps.googleusercontent.com).
#                         Verilirse Info.plist'e GIDClientID ve ters kimlikle
#                         URL şeması yazılır; verilmezse bu adım atlanır.
#   PLISTBUDDY            PlistBuddy yolu (yalnızca testlerde değiştirilir).
set -euo pipefail

PLIST="ios/Runner/Info.plist"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
APP_DELEGATE="ios/Runner/AppDelegate.swift"
ENTITLEMENTS="ios/Runner/Runner.entitlements"
PODFILE="ios/Podfile"
MIN_IOS="15.0"
BUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

if [[ ! -f "$PLIST" || ! -f "$PBXPROJ" ]]; then
  echo "HATA: ios/ klasörü yok." >&2
  echo "Codemagic derlemesi onu kendisi oluşturur (codemagic.yaml, \"iOS projesini oluştur\" adımı)." >&2
  echo "Yerelde (Mac) önce şunu çalıştır; com.ornek yerine Bundle ID'nin son parçası hariç kısmını yaz:" >&2
  echo "  flutter create --no-pub --platforms=ios --org com.ornek --project-name kisisel_asistan ." >&2
  echo "  git checkout -- pubspec.lock   # flutter create kilit dosyasını yeniden yazar" >&2
  echo "  flutter pub get" >&2
  exit 1
fi
if [[ ! -x "$BUDDY" ]]; then
  echo "HATA: Bu script macOS gerektirir (PlistBuddy bulunamadı)." >&2
  exit 1
fi

# --- 1) Info.plist ---------------------------------------------------------
set_string() { # anahtar, değer
  "$BUDDY" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$BUDDY" -c "Add :$1 string $2" "$PLIST"
}
set_bool() { # anahtar, true|false
  "$BUDDY" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$BUDDY" -c "Add :$1 bool $2" "$PLIST"
}
set_array() { # anahtar, öğeler...
  local key="$1"; shift
  "$BUDDY" -c "Delete :$key" "$PLIST" 2>/dev/null || true
  "$BUDDY" -c "Add :$key array" "$PLIST"
  local i=0
  for item in "$@"; do
    "$BUDDY" -c "Add :$key:$i string $item" "$PLIST"
    i=$((i + 1))
  done
}

set_string NSHealthShareUsageDescription "'Adım, uyku, aktif kalori, antrenman, boy ve kilo verilerin günlük kokpitinde gösterilmek ve haftalık raporlara eklenmek için okunur; boy ve kilo yalnızca ilk kurulumda formu doldurmak için okunur.'"
set_string NSHealthUpdateUsageDescription "'Ritim Sağlık verilerine kayıt eklemez; bu izin istenmez.'"
set_string NSPhotoLibraryUsageDescription "'Profil ve ilerleme fotoğrafı seçmek için fotoğraf arşivine erişilir; yalnızca seçtiğin fotoğraf küçültülüp sana özel alana yüklenir.'"
set_string NSCameraUsageDescription "'Profil ve ilerleme fotoğrafı çekmek için kamera kullanılır; fotoğraf yalnızca sana özel alana yüklenir.'"
set_string CFBundleDisplayName "Ritim"
set_string CFBundleName "Ritim"
set_string CFBundleDevelopmentRegion "tr"
set_bool ITSAppUsesNonExemptEncryption false
set_array CFBundleLocalizations tr
set_array UISupportedInterfaceOrientations UIInterfaceOrientationPortrait
# Yalnızca iPhone: iPad yönleri anahtarı kaldırılır.
"$BUDDY" -c "Delete :UISupportedInterfaceOrientations~ipad" "$PLIST" 2>/dev/null || true
echo "✓ Info.plist güncellendi"

# --- 2) HealthKit entitlement ---------------------------------------------
cp ios_setup/Runner.entitlements "$ENTITLEMENTS"
if ! grep -q "CODE_SIGN_ENTITLEMENTS" "$PBXPROJ"; then
  perl -pi -e 's/^(\s*)(ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;)/$1$2\n$1CODE_SIGN_ENTITLEMENTS = Runner\/Runner.entitlements;/' "$PBXPROJ"
fi
if ! grep -q "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;" "$PBXPROJ"; then
  echo "HATA: CODE_SIGN_ENTITLEMENTS project.pbxproj dosyasına eklenemedi." >&2
  echo "Xcode > Runner > Signing & Capabilities > + Capability > HealthKit ile elle ekle." >&2
  exit 1
fi
echo "✓ HealthKit entitlement bağlandı"

# --- iPhone-only (iPad'de uyumluluk modunda çalışır) ------------------------
perl -pi -e 's/TARGETED_DEVICE_FAMILY = "?[0-9,]+"?;/TARGETED_DEVICE_FAMILY = 1;/g' "$PBXPROJ"
if grep -q "TARGETED_DEVICE_FAMILY" "$PBXPROJ" && grep "TARGETED_DEVICE_FAMILY" "$PBXPROJ" | grep -vq "TARGETED_DEVICE_FAMILY = 1;"; then
  echo "HATA: TARGETED_DEVICE_FAMILY 1 değil." >&2
  exit 1
fi
if ! grep -q "TARGETED_DEVICE_FAMILY = 1;" "$PBXPROJ"; then
  perl -pi -e 's/^(\s*)(ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;)/$1$2\n$1TARGETED_DEVICE_FAMILY = 1;/' "$PBXPROJ"
fi
if ! grep -q "TARGETED_DEVICE_FAMILY = 1;" "$PBXPROJ"; then
  echo "HATA: TARGETED_DEVICE_FAMILY = 1 ayarlanamadı." >&2
  exit 1
fi
echo "✓ Yalnızca iPhone (TARGETED_DEVICE_FAMILY = 1)"

# --- 2b) Uygulama ikonu ----------------------------------------------------
# Tek 1024 px ikon (Xcode 14+ "single size"); diğer boyutları Xcode üretir.
ICONSET="ios/Runner/Assets.xcassets/AppIcon.appiconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp ios_setup/AppIcon.appiconset/* "$ICONSET/"
echo "✓ Uygulama ikonu (Ritim topaç)"

# --- 2c) Açılış ekranı ve gizlilik bildirimi ------------------------------
# Siyah zeminli açılış ekranı (varsayılan OLED koyu temayla aynı; beyaz
# flaş olmaz) ve uygulama hedefinin PrivacyInfo.xcprivacy dosyası.
cp ios_setup/LaunchScreen.storyboard ios/Runner/Base.lproj/LaunchScreen.storyboard
cp ios_setup/PrivacyInfo.xcprivacy ios/Runner/PrivacyInfo.xcprivacy
if ! grep -q "PrivacyInfo.xcprivacy in Resources" "$PBXPROJ"; then
  # Runner hedefinin Resources aşamasına dosya referansı ekler (Info.plist
  # ile aynı gruba). Sabit kimlikler yalnızca bu dosyaya aittir.
  perl -0pi -e 's/(\/\* Begin PBXBuildFile section \*\/\n)/$1\t\tA1B2C3D4E5F60718293A4B01 \/\* PrivacyInfo.xcprivacy in Resources \*\/ = {isa = PBXBuildFile; fileRef = A1B2C3D4E5F60718293A4B02 \/\* PrivacyInfo.xcprivacy \*\/; };\n/' "$PBXPROJ"
  perl -0pi -e 's/(\/\* Begin PBXFileReference section \*\/\n)/$1\t\tA1B2C3D4E5F60718293A4B02 \/\* PrivacyInfo.xcprivacy \*\/ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };\n/' "$PBXPROJ"
  perl -0pi -e 's/(\n(\s*)[0-9A-F]{24} \/\* Info\.plist \*\/,\n)/$1$2A1B2C3D4E5F60718293A4B02 \/\* PrivacyInfo.xcprivacy \*\/,\n/' "$PBXPROJ"
  # Yalnızca Runner hedefinin Resources aşaması (LaunchScreen.storyboard'u
  # içeren blok); ilk eşleşme RunnerTests aşaması olabilir.
  perl -0pi -e 's/(\n\s*[0-9A-F]{24} \/\* Resources \*\/ = \{\n\s*isa = PBXResourcesBuildPhase;\n\s*buildActionMask = \d+;\n\s*files = \(\n)(?=(?:[^)]*\n)*?\s*[0-9A-F]{24} \/\* LaunchScreen\.storyboard in Resources \*\/)/$1\t\t\t\tA1B2C3D4E5F60718293A4B01 \/\* PrivacyInfo.xcprivacy in Resources \*\/,\n/' "$PBXPROJ"
fi
if [[ "$(grep -c "A1B2C3D4E5F60718293A4B0" "$PBXPROJ")" -lt 4 ]] || ! perl -0ne 'exit((/files = \(\n(?:[^)]*\n)*?\s*A1B2C3D4E5F60718293A4B01 [^\n]*\n(?:[^)]*\n)*?[^\n]*LaunchScreen\.storyboard in Resources/ || /files = \(\n(?:[^)]*\n)*?[^\n]*LaunchScreen\.storyboard in Resources[^\n]*\n(?:[^)]*\n)*?\s*A1B2C3D4E5F60718293A4B01 /) ? 0 : 1)' "$PBXPROJ"; then
  echo "HATA: PrivacyInfo.xcprivacy Runner hedefine eklenemedi." >&2
  exit 1
fi
echo "✓ Açılış ekranı (siyah) ve PrivacyInfo.xcprivacy"

# --- 3) En düşük iOS sürümü ------------------------------------------------
perl -pi -e "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = ${MIN_IOS};/" "$PBXPROJ"
if [[ -f "$PODFILE" ]]; then
  perl -pi -e "s/^#?\s*platform :ios, '[0-9.]+'/platform :ios, '${MIN_IOS}'/" "$PODFILE"
fi
echo "✓ Deployment target iOS ${MIN_IOS}"

# --- 4) Ön plandayken bildirim gösterimi ----------------------------------
if [[ -f "$APP_DELEGATE" ]] && ! grep -q "UNUserNotificationCenter.current().delegate" "$APP_DELEGATE"; then
  perl -pi -e 's/^(\s*)(return super\.application\(application, didFinishLaunchingWithOptions: launchOptions\))/$1UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n$1$2/' "$APP_DELEGATE"
  if ! grep -q "^import UserNotifications" "$APP_DELEGATE"; then
    perl -pi -e 's/^(import UIKit)$/$1\nimport UserNotifications/' "$APP_DELEGATE"
  fi
fi
if [[ -f "$APP_DELEGATE" ]] && ! grep -q "UNUserNotificationCenter.current().delegate" "$APP_DELEGATE"; then
  echo "UYARI: AppDelegate.swift otomatik düzenlenemedi. didFinishLaunching içine şu satırı ekle:" >&2
  echo "  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate" >&2
else
  echo "✓ AppDelegate bildirim delegesi ayarlı"
fi

# --- 4b) Bildirim eylemleri ("Yaptım") arka planda -------------------------
# Uygulama kapalıyken bildirimdeki eyleme basılınca flutter_local_notifications
# arka plan isolate'inde eklentileri kaydedebilsin diye registrant geri çağrısı.
if [[ -f "$APP_DELEGATE" ]] && ! grep -q "setPluginRegistrantCallback" "$APP_DELEGATE"; then
  perl -0pi -e 's/^(\s*)(return super\.application\(application, didFinishLaunchingWithOptions: launchOptions\))/$1FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in\n$1  GeneratedPluginRegistrant.register(with: registry)\n$1}\n$1$2/m' "$APP_DELEGATE"
  if ! grep -q "^import flutter_local_notifications" "$APP_DELEGATE"; then
    perl -pi -e 's/^(import Flutter)$/$1\nimport flutter_local_notifications/' "$APP_DELEGATE"
  fi
fi
if [[ -f "$APP_DELEGATE" ]] && grep -q "setPluginRegistrantCallback" "$APP_DELEGATE"; then
  echo "✓ Bildirim eylemleri için eklenti kaydı ayarlı"
else
  echo "UYARI: AppDelegate.swift'e setPluginRegistrantCallback eklenemedi; kapalı uygulamada 'Yaptım' çalışmayabilir." >&2
fi

# --- 5) Google ile giriş (google_sign_in) ----------------------------------
# GIDClientID: istemci kimliği. CFBundleURLTypes: Google girişinin uygulamaya
# dönüş adresi, ters çevrilmiş istemci kimliği (com.googleusercontent.apps.…).
# Bu betiğin eklediği giriş "GoogleSignIn" adını taşır; her çalıştırmada eski
# Google girişleri silinip tek giriş yeniden yazılır (kimlik değişse de kopya
# kalmaz).
GOOGLE_CLIENT_ID="$(printf '%s' "${GOOGLE_IOS_CLIENT_ID:-}" | tr -d '[:space:]')"
GOOGLE_URL_NAME="GoogleSignIn"
GOOGLE_SUFFIX=".apps.googleusercontent.com"
if [[ -z "$GOOGLE_CLIENT_ID" ]]; then
  echo "• GOOGLE_IOS_CLIENT_ID verilmedi: Google ile giriş yapılandırılmadı (uygulamada Google Health seçeneği kapalı kalır)."
else
  if [[ ! "$GOOGLE_CLIENT_ID" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
    echo "HATA: GOOGLE_IOS_CLIENT_ID beklenen biçimde değil." >&2
    echo "Google Cloud > APIs & Services > Credentials'taki iOS istemcisinin" >&2
    echo "'Client ID' değerini (…${GOOGLE_SUFFIX} ile biten) olduğu gibi gir." >&2
    exit 1
  fi
  GOOGLE_REVERSED="com.googleusercontent.apps.${GOOGLE_CLIENT_ID%"$GOOGLE_SUFFIX"}"
  set_string GIDClientID "$GOOGLE_CLIENT_ID"

  if ! "$BUDDY" -c "Print :CFBundleURLTypes" "$PLIST" >/dev/null 2>&1; then
    "$BUDDY" -c "Add :CFBundleURLTypes array" "$PLIST"
  fi
  # Girişleri say; sondan başa doğru Google girişlerini sil (indeks kaymasın).
  count=0
  while "$BUDDY" -c "Print :CFBundleURLTypes:$count" "$PLIST" >/dev/null 2>&1; do
    count=$((count + 1))
  done
  for ((i = count - 1; i >= 0; i--)); do
    name="$("$BUDDY" -c "Print :CFBundleURLTypes:$i:CFBundleURLName" "$PLIST" 2>/dev/null || true)"
    schemes="$("$BUDDY" -c "Print :CFBundleURLTypes:$i:CFBundleURLSchemes" "$PLIST" 2>/dev/null || true)"
    if [[ "$name" == "$GOOGLE_URL_NAME" || "$schemes" == *com.googleusercontent.apps.* ]]; then
      "$BUDDY" -c "Delete :CFBundleURLTypes:$i" "$PLIST"
      count=$((count - 1))
    fi
  done
  "$BUDDY" -c "Add :CFBundleURLTypes:$count dict" "$PLIST"
  "$BUDDY" -c "Add :CFBundleURLTypes:$count:CFBundleTypeRole string Editor" "$PLIST"
  "$BUDDY" -c "Add :CFBundleURLTypes:$count:CFBundleURLName string $GOOGLE_URL_NAME" "$PLIST"
  "$BUDDY" -c "Add :CFBundleURLTypes:$count:CFBundleURLSchemes array" "$PLIST"
  "$BUDDY" -c "Add :CFBundleURLTypes:$count:CFBundleURLSchemes:0 string $GOOGLE_REVERSED" "$PLIST"
  if [[ "$("$BUDDY" -c "Print :CFBundleURLTypes:$count:CFBundleURLSchemes:0" "$PLIST")" != "$GOOGLE_REVERSED" ]]; then
    echo "HATA: Google URL şeması Info.plist'e yazılamadı." >&2
    exit 1
  fi
  echo "✓ Google ile giriş: GIDClientID ve URL şeması ($GOOGLE_REVERSED)"
fi

echo "iOS yapılandırması tamam."
