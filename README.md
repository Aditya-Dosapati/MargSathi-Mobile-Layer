# MargSathi Mobile Layer

Cross-platform Flutter app for smart navigation: routing, parking prediction, sign translation, and a profile dashboard.

## Features
- Smart routing with live events and eco impact considerations.
- Parking availability prediction by area and time.
- Sign translation (camera/gallery) surface.
- Profile page with preferences (notifications, live updates, compact cards, location access).

## Project Structure
- `lib/main.dart` – app entry, routes.
- `lib/features/home/` – home screen, info banners, profile link.
- `lib/features/routing/` – smart routing flows.
- `lib/features/parking/` – parking prediction page.
- `lib/features/sign_translation/` – sign translation surface.
- `assets/images/` – banner imagery.

## Prerequisites
- Flutter SDK (3.x recommended)
- Android Studio / Xcode for platform builds
- Device/emulator/simulator available

## Setup
```bash
flutter pub get
```

## Run
```bash
flutter run
```

## Build
- Android: `flutter build apk`
- iOS: `flutter build ios` (requires macOS + Xcode)

## Notes
- Assets are referenced under `assets/images/`; ensure they remain in sync with `pubspec.yaml`.
- Profile actions that change data are placeholder/snackbars until backend wiring is added.
