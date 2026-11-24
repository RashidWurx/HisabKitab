# Hisaab

Offline personal money manager for Android and iPhone (Flutter). All data stays on the device in a local SQLite database. The only internet use is the optional manual backup to your own Google Drive (Android) or iCloud (iPhone).

See `docs/` for the spec, decisions and project state.

## Run

```
flutter pub get
flutter run
```

## Backup and restore

Works without any setup:

- **Export backup file** and **Import backup file** (Backup & restore screen). The file is a `.zip` with the database and a manifest.

Cloud backup needs a one-time setup.

### Google Drive setup (Android)

Backups go to the hidden app-data folder of your own Drive (scope `drive.appdata`). Nothing is visible in the Drive app.

1. Open <https://console.cloud.google.com>, create a project.
2. APIs & Services > Library > enable **Google Drive API**.
3. OAuth consent screen: type External, add your Google account as a test user, add the scope `.../auth/drive.appdata`.
4. Credentials > Create credentials > OAuth client ID:
   - **Android** client: package `com.hisaab.hisaab`, SHA-1 of your signing key. Debug key: `cd android && ./gradlew signingReport`. Add the release key's SHA-1 too.
   - **Web application** client: no settings needed. Copy its client ID (`xxxx.apps.googleusercontent.com`). This is the *server client id*.
5. Build with the id:

```
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
```

Without the define, the app shows a setup hint and local export/import still works.

### iCloud setup (iPhone)

Needs a Mac with Xcode and a paid Apple Developer account.

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Runner target > Signing & Capabilities > **+ Capability** > iCloud. Tick **iCloud Documents** and add the container `iCloud.com.hisaab.hisaab`.
3. Make sure `ios/Runner/Runner.entitlements` is set as the target's *Code Signing Entitlements* build setting.
4. On the iPhone, sign in to iCloud and turn on iCloud Drive.

The Swift side (`ICloudBackupPlugin` in `AppDelegate.swift`) stores backups in the container's `Documents/Backups` and is only testable on a real iPhone.

Restoring replaces all data on the device. The latest 10 cloud backups are kept.
