#!/usr/bin/env bash
# Jalankan di folder netlayer_diag: bash setup.sh
set -e
if [ ! -d android ]; then
  echo "Membuat scaffold Android..."
  tmp=$(mktemp -d)
  flutter create --org com.ghani --project-name netlayer_diag --platforms android "$tmp/netlayer_diag"
  cp -rn "$tmp/netlayer_diag/android" ./android
  cp -n "$tmp/netlayer_diag/.metadata" ./.metadata 2>/dev/null || true
  rm -rf "$tmp"
fi
python3 - << 'PY'
p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
"""
if "ACCESS_WIFI_STATE" not in s:
    s = s.replace("<application", perms + "    <application", 1)
    open(p, "w", encoding="utf-8").write(s)
    print("Izin ditambahkan ke AndroidManifest.xml")
PY
flutter pub get
echo "Selesai. Jalankan: flutter run   atau   flutter build apk --release"
