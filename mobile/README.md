# Companion Ranchi — Mobile (Flutter)

The customer + companion Flutter app for **Companion Ranchi**, a premium,
**non-adult** companionship marketplace (Ranchi, India). Users book verified
companions for social activities only — coffee, movies, shopping, events, city
tours, networking and conversation. **Meetings are public-places-only, users are
18+, and this is not an escort/adult service** (see `../docs/SAFETY.md`).

- **Material 3** with a clean white + purple-gradient (`#6D28D9`) brand look,
  light & dark themes.
- **Riverpod** for state, **go_router** for navigation (with an auth redirect),
  **Dio** for networking (JWT inject + refresh), **Socket.IO** for realtime chat.

## Requirements

- Flutter **3.27+** (Dart 3.6+) — uses the wide-gamut `Color.withValues` API.
- Android Studio / Xcode for device emulators
- A running backend (see `../backend`) — defaults assume `localhost:4000`.

## Setup

```bash
cd mobile
flutter pub get
flutter run
```

### Backend base URL

The app talks to `${API_BASE_URL}/api`. Defaults are configured in
`lib/core/env/env.dart` and can be overridden at build time with `--dart-define`:

| Target                | Base URL                  |
|-----------------------|---------------------------|
| **Android emulator**  | `http://10.0.2.2:4000`    |
| iOS simulator / web   | `http://localhost:4000`   |
| Physical device       | `http://<your-LAN-ip>:4000` |

The Android emulator maps host `10.0.2.2` to your machine's `localhost`, so the
**default** already points there. To override:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:4000 \
  --dart-define=SOCKET_URL=http://10.0.2.2:4000
```

In development the backend prints OTPs to its console (`OTP_CONSOLE=true`), so no
SMS provider is needed — just read the code from the backend logs.

## Project structure

```
lib/
  core/
    auth/        authControllerProvider (OTP -> verify -> register), currentUserProvider
    constants/   categories, durations, public place types, activities (mirrors backend)
    env/         Env.apiBaseUrl, Env.socketUrl
    models/      UserModel, CompanionModel, BookingModel, ... (match docs/API.md JSON)
    network/     ApiClient (Dio) + ApiException
    router/      Routes (path constants), goRouterProvider, MainShell (bottom nav)
    socket/      SocketClient (chat/presence/notifications)
    storage/     TokenStorage (flutter_secure_storage)
    theme/       AppTheme.light/dark, AppColors, AppGradients, themeModeProvider
    utils/       Formatters (₹ money, dates, relative time)
  shared/widgets/  AppButton, GradientButton, CompanionCard, RatingStars,
                   VerifiedBadge, OnlineDot, SectionHeader, AppTextField,
                   LoadingView, EmptyView, ErrorView, CategoryChip, ...
  features/<name>/
    presentation/  screens
    application/   Riverpod controllers/providers
    data/          repositories calling ApiClient -> models
  app.dart       MaterialApp.router (router + theme)
  main.dart      ProviderScope + runApp
```

### Conventions

- Always use **package imports**: `import 'package:companion_ranchi/...';`.
- Feature screens live under `lib/features/<name>/presentation` with the class
  names registered in `lib/core/router/app_router.dart`.
- Reuse the shared `core/` and `shared/widgets/` modules — do **not** redefine
  the API client, models, theme, router or widgets.
- Money is INR; format with `Formatters.money(...)`. Never trust client-side age
  — the backend enforces 18+.

## Realtime (Socket.IO)

`SocketClient` (`socketClientProvider`) connects with the JWT and exposes streams
for `message:new`, `message:sent`, `typing`, `message:read`, `presence:update`
and `notification:new`, plus emitters for `message:send`, `typing:start/stop`,
`message:read` and `presence:ping` (see `../docs/API.md` §9).

## Push notifications (FCM)

`firebase_core` / `firebase_messaging` are included. Generate `firebase_options.dart`
with `flutterfire configure` and call `Firebase.initializeApp` from the
notifications feature before using FCM. The skeleton intentionally does **not**
initialise Firebase in `main()` so it runs without that config file.

## Analyze & test

```bash
flutter analyze
flutter test
```
