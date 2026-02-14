# Splash Screen Rebuild Commands

## Run these commands in order:

```bash
# Step 1: Clean previous builds
flutter clean

# Step 2: Get dependencies (flutter_native_splash already installed)
flutter pub get

# Step 3: Rebuild and run on Samsung A7
flutter run -d R9ZX80AFYBF
```

## What Was Fixed:

✅ Installed `flutter_native_splash` package
✅ Configured black background (#101316)
✅ Changed splash image from `center` to `fill` gravity
✅ Image now fills entire screen - NO white borders
✅ Works on both legacy Android and Android 12+ APIs
✅ Dark mode support included

## Expected Result:

- Native splash screen shows black background
- Your icon image fills the ENTIRE screen
- NO white borders or centered scaling
- Seamless transition to Flutter splash screen

