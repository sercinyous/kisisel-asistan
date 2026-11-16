#!/usr/bin/env bash
# iOS projesini HealthKit + yerel bildirimler için yapılandırır.
# macOS'ta, proje kökünden çalıştırılır:  bash tool/configure_ios.sh
# Tekrar tekrar çalıştırılabilir (idempotent). Codemagic de her derlemede çağırır.
set -euo pipefail

PLIST="ios/Runner/Info.plist"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
APP_DELEGATE="ios/Runner/AppDelegate.swift"
ENTITLEMENTS="ios/Runner/Runner.entitlements"
PODFILE="ios/Podfile"
MIN_IOS="15.0"
BUDDY="/usr/libexec/PlistBuddy"

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

set_string NSHealthShareUsageDescription "'Adım, uyku ve aktif kalori verilerin günlük kokpitinde gösterilmek ve haftalık raporlara eklenmek için okunur.'"
set_string NSHealthUpdateUsageDescription "'Bu uygulama Sağlık verilerine yazmaz; yalnızca okuma yapar.'"
set_string CFBundleDisplayName "Operasyon"
set_string CFBundleDevelopmentRegion "tr"
set_bool ITSAppUsesNonExemptEncryption false
set_array CFBundleLocalizations tr
set_array UISupportedInterfaceOrientations UIInterfaceOrientationPortrait
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

echo "iOS yapılandırması tamam."
