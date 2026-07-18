#!/usr/bin/env python3
"""zanzibarr logosundan tüm platform ikonlarını üretir (tek seferlik)."""

from PIL import Image

LOGO = "/Users/enveran/Downloads/zanzibarr/zanzibarr-logo.png"
IOS_BG = (11, 14, 23, 255)  # logo içindeki koyu lacivert zeminle uyumlu

logo = Image.open(LOGO).convert("RGBA")


def resize(size: int) -> Image.Image:
    return logo.resize((size, size), Image.LANCZOS)


def flatten(img: Image.Image) -> Image.Image:
    base = Image.new("RGBA", img.size, IOS_BG)
    base.alpha_composite(img)
    return base.convert("RGB")


# macOS: alfa korunur
for size in (16, 32, 64, 128, 256, 512, 1024):
    resize(size).save(
        f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png"
    )

# Android: alfa korunur
android_sizes = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
for bucket, size in android_sizes.items():
    resize(size).save(f"android/app/src/main/res/mipmap-{bucket}/ic_launcher.png")

# iOS: alfa olmaz — koyu zemine düzleştir
ios_files = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
for name, size in ios_files.items():
    flatten(resize(size)).save(f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}")

# Windows: çok-boyutlu ICO
logo.save(
    "windows/runner/resources/app_icon.ico",
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

print("ikonlar üretildi")
