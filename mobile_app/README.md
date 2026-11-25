# Smart System Timesheet (Android / Flutter)

Mobile client for the **ss_portal** Django timesheet. Same accounts, same roles, same report formulas as the web portal.

## 1. Server side (Django) — deploy first

The app talks to a small JSON API that lives **inside** the existing project (no new packages, no migrations):

| File | Purpose |
|---|---|
| `app/api_auth.py` | Signed-token auth (`django.core.signing`), login throttling, helpers |
| `app/api_views.py` | Endpoints — each one mirrors an existing view in `app/views.py` |
| `app/api_urls.py` | Routes |
| `config/urls.py` | one added line: `path('api/v1/', include('app.api_urls'))` |

Deploy (Ubuntu / Gunicorn / Nginx):

```bash
cd /path/to/ss_portal && git pull
sudo systemctl restart gunicorn   # or your service name
curl -s https://selfservice.smartsystemme.com/api/v1/auth/me/   # -> {"detail": "Authentication credentials were not provided."}
```

Tokens expire after 30 days and are revoked automatically when the user changes the password.

## 2. Build the app

Requirements: Flutter (stable), Android SDK, JDK 17.

```bat
cd mobile_app
setup_android.bat          REM Windows  (macOS/Linux: ./setup_android.sh)
flutter run                REM phone / emulator
flutter build apk --release
```

`setup_android.bat` generates `android/` for **your** Flutter version, then copies `android_overrides/`
(manifest with INTERNET permission, app name, launcher icons, network-security config).

APK: `build/app/outputs/flutter-apk/app-release.apk`

Default server: `https://selfservice.smartsystemme.com` (from `ALLOWED_HOSTS`). Change it on the login screen
(“Server: …”) or at build time: `flutter build apk --dart-define=SS_BASE_URL=https://smartsystem.pythonanywhere.com`.

## 3. Roles → navigation

| Who (server rule) | Bottom navigation |
|---|---|
| admin / project-manager / delivery-manager / top-manager / ceo / leader | Home · Review · Reports · Missions · More |
| everyone else (engineer, developer, sales …) | Home · Timesheets · Missions · Leave · More |

Leaders only see their own team (same as the portal). Capabilities are computed by the server, so the app never
shows an action the API would refuse.

## 4. Reports (identical math to the portal)

Man-days & overtime · Last timesheet · Monthly man-days · Utilization · Employee activity · Project costs.
PDF export reuses the portal's own WeasyPrint templates.

## 5. CI

`.github/workflows/mobile_app.yml` builds, analyzes, tests and uploads the APK as an artifact on every push to `mobile_app/**`.
