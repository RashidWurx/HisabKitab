import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/backup_models.dart';
import 'cloud_backup.dart';

/// Adds the OAuth token to every request.
class _BearerClient extends http.BaseClient {
  _BearerClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Google Drive backups in the app's hidden folder (`drive.appdata` scope):
/// the user's own Drive, invisible in the Drive app, deleted with the app's
/// data. Needs a Google Cloud OAuth client (see README).
class GoogleDriveBackupProvider implements CloudBackupProvider {
  /// Passed at build time: `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`
  static const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _scopes = [drive.DriveApi.driveAppdataScope];

  bool _initialised = false;
  GoogleSignInAccount? _user;

  @override
  String get label => 'Google Drive';

  @override
  bool get isConfigured => serverClientId.isNotEmpty;

  @override
  String get setupHint =>
      'Google Drive backup needs a one-time Google Cloud setup. The steps are in the README ("Google Drive setup").';

  Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _initialised = true;
  }

  BackupException _friendly(Object e) {
    if (e is BackupException) return e;
    if (e is GoogleSignInException) {
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled => BackupException('Google sign-in was cancelled.'),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError => BackupException(
          'Google sign-in is not set up correctly for this build. $setupHint',
        ),
        _ => BackupException('Google sign-in failed. Check your internet and try again.'),
      };
    }
    if (e is SocketException || e is http.ClientException || e is TimeoutException) {
      return BackupException('No internet connection. Connect and try again.');
    }
    if (e is drive.DetailedApiRequestError) {
      if (e.status == 403 && (e.message ?? '').toLowerCase().contains('quota')) {
        return BackupException('Not enough storage in your Google Drive.');
      }
      if (e.status == 401) {
        return BackupException('Google Drive access expired. Connect again.');
      }
      return BackupException('Google Drive error (${e.status}). Try again later.');
    }
    return BackupException('Something went wrong with Google Drive. Try again.');
  }

  @override
  Future<void> connect() async {
    if (!isConfigured) throw BackupException(setupHint);
    try {
      await _init();
      _user ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      _user ??= await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    } catch (e) {
      throw _friendly(e);
    }
  }

  Future<drive.DriveApi> _api() async {
    await connect();
    try {
      final client = _user!.authorizationClient;
      final auth =
          await client.authorizationForScopes(_scopes) ??
          await client.authorizeScopes(_scopes);
      return drive.DriveApi(_BearerClient(auth.accessToken));
    } catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<List<CloudBackup>> list() async {
    try {
      final api = await _api();
      final result = await api.files.list(
        spaces: 'appDataFolder',
        q: "name contains 'hisaab_backup_' and trashed = false",
        $fields: 'files(id,name,size,createdTime)',
        orderBy: 'createdTime desc',
        pageSize: 100,
      );
      return [
        for (final f in result.files ?? const <drive.File>[])
          CloudBackup(
            id: f.id!,
            name: f.name ?? 'backup.zip',
            createdAt:
                backupTimeFromName(f.name ?? '') ??
                f.createdTime?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
            sizeBytes: int.tryParse(f.size ?? '') ?? 0,
          ),
      ];
    } catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<CloudBackup> upload(File zip) async {
    try {
      final api = await _api();
      final length = await zip.length();
      final created = await api.files.create(
        drive.File(name: p.basename(zip.path), parents: ['appDataFolder']),
        uploadMedia: drive.Media(zip.openRead(), length),
        $fields: 'id,name,size,createdTime',
      );
      return CloudBackup(
        id: created.id!,
        name: created.name ?? p.basename(zip.path),
        createdAt: backupTimeFromName(created.name ?? '') ?? DateTime.now(),
        sizeBytes: int.tryParse(created.size ?? '') ?? length,
      );
    } catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<File> download(CloudBackup backup, Directory into) async {
    try {
      final api = await _api();
      final media =
          await api.files.get(
                backup.id,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;
      await into.create(recursive: true);
      final file = File(p.join(into.path, backup.name));
      final sink = file.openWrite();
      await media.stream.pipe(sink);
      return file;
    } catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> delete(CloudBackup backup) async {
    try {
      final api = await _api();
      await api.files.delete(backup.id);
    } catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> disconnect() async {
    _user = null;
    if (_initialised) await GoogleSignIn.instance.signOut();
  }
}
