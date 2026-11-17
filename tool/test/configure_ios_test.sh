#!/usr/bin/env bash
# tool/configure_ios.sh'in Info.plist düzenlemelerini (özellikle Google ile
# giriş: GIDClientID ve ters istemci kimliğiyle URL şeması) macOS olmadan sınar.
# Gerçek bir `flutter create --platforms=ios` projesinin kopyasında, PlistBuddy
# yerine tool/test/plistbuddy_stub.py (plistlib) ile çalışır.
#
# Kullanım (PATH'te flutter, python3 ve perl olmalı):
#   bash tool/test/configure_ios_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/kasist-ios.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "== flutter create --platforms=ios (geçici kopya: $WORK) =="
(cd "$WORK" && flutter create --no-pub --platforms=ios --org com.sercinyous \
  --project-name kisisel_asistan app >/dev/null 2>&1)
APP="$WORK/app"
cp -R "$ROOT/tool" "$ROOT/ios_setup" "$APP/"
PLIST="$APP/ios/Runner/Info.plist"

cat > "$WORK/PlistBuddy" <<STUB
#!/usr/bin/env bash
exec python3 "$ROOT/tool/test/plistbuddy_stub.py" "\$@"
STUB
chmod +x "$WORK/PlistBuddy"
export PLISTBUDDY="$WORK/PlistBuddy"

# Info.plist'ten bir değeri JSON olarak okur (yoksa null).
value() {
  python3 - "$PLIST" "$1" <<'PY'
import json, plistlib, sys
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
print(json.dumps(data.get(sys.argv[2]), ensure_ascii=False, sort_keys=True))
PY
}

fail() { echo "BAŞARISIZ: $*" >&2; exit 1; }
configure() { (cd "$APP" && bash tool/configure_ios.sh); }

ID_A="123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com"
REV_A="com.googleusercontent.apps.123456789012-abcdefghijklmnopqrstuvwxyz012345"
ID_B="987654321098-zyxwvutsrqponmlkjihgfedcba987654.apps.googleusercontent.com"
REV_B="com.googleusercontent.apps.987654321098-zyxwvutsrqponmlkjihgfedcba987654"

echo "== 1) GOOGLE_IOS_CLIENT_ID yok: Google adımı atlanır =="
out="$(env -u GOOGLE_IOS_CLIENT_ID bash -c "cd '$APP' && bash tool/configure_ios.sh")"
grep -q "GOOGLE_IOS_CLIENT_ID verilmedi" <<<"$out" || fail "atlama mesajı yok"
[[ "$(value GIDClientID)" == "null" ]] || fail "GIDClientID yazılmamalıydı"
[[ "$(value CFBundleURLTypes)" == "null" ]] || fail "URL şeması yazılmamalıydı"
[[ "$(value CFBundleDisplayName)" == '"Ritim"' ]] || fail "diğer anahtarlar yazılmadı"
echo "tamam"

echo "== 2) istemci kimliği verilince GIDClientID + ters kimlikli URL şeması =="
GOOGLE_IOS_CLIENT_ID="  $ID_A " configure >/dev/null
[[ "$(value GIDClientID)" == "\"$ID_A\"" ]] || fail "GIDClientID: $(value GIDClientID)"
expected="[{\"CFBundleTypeRole\": \"Editor\", \"CFBundleURLName\": \"GoogleSignIn\", \"CFBundleURLSchemes\": [\"$REV_A\"]}]"
[[ "$(value CFBundleURLTypes)" == "$expected" ]] || fail "URL türleri: $(value CFBundleURLTypes)"
echo "tamam"

echo "== 3) yeniden çalıştırma kopya üretmez (idempotent) =="
GOOGLE_IOS_CLIENT_ID="$ID_A" configure >/dev/null
GOOGLE_IOS_CLIENT_ID="$ID_A" configure >/dev/null
[[ "$(value CFBundleURLTypes)" == "$expected" ]] || fail "tekrar sonrası: $(value CFBundleURLTypes)"
echo "tamam"

echo "== 4) kimlik değişince eski Google girişi gider, başka URL türü kalır =="
"$PLISTBUDDY" -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
"$PLISTBUDDY" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
"$PLISTBUDDY" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ritim" "$PLIST"
GOOGLE_IOS_CLIENT_ID="$ID_B" configure >/dev/null
[[ "$(value GIDClientID)" == "\"$ID_B\"" ]] || fail "GIDClientID güncellenmedi"
expected_b="[{\"CFBundleURLSchemes\": [\"ritim\"]}, {\"CFBundleTypeRole\": \"Editor\", \"CFBundleURLName\": \"GoogleSignIn\", \"CFBundleURLSchemes\": [\"$REV_B\"]}]"
[[ "$(value CFBundleURLTypes)" == "$expected_b" ]] || fail "URL türleri: $(value CFBundleURLTypes)"
echo "tamam"

echo "== 5) biçimi bozuk kimlik derlemeyi durdurur, plist değişmez =="
before="$(value CFBundleURLTypes)"
if GOOGLE_IOS_CLIENT_ID="abc.apps.googleusercontent.com" configure >/dev/null 2>&1; then
  fail "geçersiz kimlik kabul edildi"
fi
[[ "$(value CFBundleURLTypes)" == "$before" ]] || fail "geçersiz kimlikte plist değişti"
echo "tamam"

echo "TÜM configure_ios TESTLERİ GEÇTİ"
