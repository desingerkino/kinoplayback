#!/usr/bin/env python3
"""Idempotent patcher for the Flutter-generated ios/ and android/ folders.

Run after `flutter create --platforms=ios,android .` (CI does this when the
folders are missing). Safe to run repeatedly: every edit checks first.

What it sets up:
  Android: permissions (camera, mic, LAN, multicast for mDNS, legacy storage
           for gallery saves on API <= 29), minSdk 24, app label.
  iOS:     usage descriptions (camera, mic, local network, Photos),
           Bonjour service type, all orientations, Files-app access to takes,
           deployment target 15.0, permission_handler macros in Podfile.
"""
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BONJOUR_TYPE = "_kinoplayback._tcp"
APP_NAME = "KINO PLAYBACK"
IOS_TARGET = "15.0"
ANDROID_MIN_SDK = 24

changed = []


def log(msg):
    changed.append(msg)
    print("  +", msg)


# ---------------------------------------------------------------- Android ---
def patch_android():
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        print("android manifest not found, skipping android")
        return
    text = manifest.read_text()
    perms = [
        "android.permission.INTERNET",
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
        "android.permission.MODIFY_AUDIO_SETTINGS",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.CHANGE_WIFI_MULTICAST_STATE",
        "android.permission.WAKE_LOCK",
    ]
    lines = []
    for p in perms:
        if p not in text:
            lines.append(f'    <uses-permission android:name="{p}" />')
    if "WRITE_EXTERNAL_STORAGE" not in text:
        lines.append('    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />')
    if "android.hardware.camera" not in text:
        lines.append('    <uses-feature android:name="android.hardware.camera" android:required="false" />')
        lines.append('    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />')
    if lines:
        text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n" + "\n".join(lines), text, count=1)
        log("android: permissions/features")
    if "requestLegacyExternalStorage" not in text:
        text = text.replace("<application", '<application\n        android:requestLegacyExternalStorage="true"', 1)
        log("android: requestLegacyExternalStorage")
    text2 = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', text, count=1)
    if text2 != text:
        text = text2
        log("android: label")
    manifest.write_text(text)

    for name in ("build.gradle.kts", "build.gradle"):
        g = ROOT / "android/app" / name
        if not g.exists():
            continue
        s = g.read_text()
        s2 = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", f"minSdk = {ANDROID_MIN_SDK}", s)
        s2 = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", f"minSdkVersion {ANDROID_MIN_SDK}", s2)
        if s2 != s:
            g.write_text(s2)
            log(f"android: minSdk {ANDROID_MIN_SDK} in {name}")


# -------------------------------------------------------------------- iOS ---
def patch_ios():
    plist_path = ROOT / "ios/Runner/Info.plist"
    if not plist_path.exists():
        print("ios Info.plist not found, skipping ios")
        return
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    want = {
        "CFBundleDisplayName": APP_NAME,
        "NSCameraUsageDescription": "Камера нужна в режиме CAMERA: для предпросмотра, записи оригинала и передачи изображения на монитор PLAYBACK.",
        "NSMicrophoneUsageDescription": "Микрофон нужен, чтобы записывать звук в оригинал и передавать его на монитор PLAYBACK.",
        "NSLocalNetworkUsageDescription": "Локальная сеть нужна, чтобы находить устройства KINO PLAYBACK и передавать видео напрямую по Wi-Fi без интернета.",
        "NSPhotoLibraryAddUsageDescription": "Записанные дубли сохраняются в Фото.",
        "NSPhotoLibraryUsageDescription": "Записанные дубли сохраняются в Фото.",
        "NSBonjourServices": [BONJOUR_TYPE],
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        "UIRequiresFullScreen": False,
        "UIStatusBarHidden": False,
        "UIViewControllerBasedStatusBarAppearance": True,
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
    }
    dirty = False
    for k, v in want.items():
        if pl.get(k) != v:
            pl[k] = v
            dirty = True
    if dirty:
        with open(plist_path, "wb") as f:
            plistlib.dump(pl, f)
        log("ios: Info.plist keys")

    pbx = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    if pbx.exists():
        s = pbx.read_text()
        s2 = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_TARGET};", s)
        s2 = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = com\.desingerkino\.kinoplayback;",
                    "PRODUCT_BUNDLE_IDENTIFIER = com.desingerkino.kinoplayback;", s2)
        if s2 != s:
            pbx.write_text(s2)
            log(f"ios: deployment target {IOS_TARGET}")

    podfile = ROOT / "ios/Podfile"
    if podfile.exists():
        s = podfile.read_text()
        s2 = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", f"platform :ios, '{IOS_TARGET}'", s, flags=re.M)
        if "PERMISSION_CAMERA" not in s2:
            hook = """
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '%s'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
        'PERMISSION_PHOTOS=1',
        'PERMISSION_PHOTOS_ADD_ONLY=1',
      ]
    end""" % IOS_TARGET
            s2 = s2.replace("flutter_additional_ios_build_settings(target)",
                            "flutter_additional_ios_build_settings(target)" + hook, 1)
        if s2 != s:
            podfile.write_text(s2)
            log("ios: Podfile platform + permission macros")


if __name__ == "__main__":
    print("patch_platforms:")
    patch_android()
    patch_ios()
    print(f"done, {len(changed)} change(s)")
    sys.exit(0)
