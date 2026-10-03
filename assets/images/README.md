# SwidShop image assets

- `swidshop_logo.png` — official logo (mark + "SwidShop" wordmark), transparent
  background, cropped. Used on the splash and auth screens.
- `swidshop_mark.png` — the infinity/gavel/bag mark only, square, transparent.
  Source for the launcher icon (`flutter_launcher_icons` block in `pubspec.yaml`).

Both were cut from the original 1254×1254 artwork on its `#FCF8F4` background.
After changing either file, regenerate the launcher icons:

```bash
dart run flutter_launcher_icons
```
