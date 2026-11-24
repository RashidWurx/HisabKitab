import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudBackupPlugin") {
      ICloudBackupPlugin.register(with: registrar)
    }
  }
}

/// iCloud Drive backups: stores Hisaab backup zips in the app's own iCloud
/// container (Documents/Backups). Needs the iCloud capability (see README).
/// Dart side: lib/features/backup/data/icloud_backup.dart, channel "hisaab/icloud".
class ICloudBackupPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "hisaab/icloud", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ICloudBackupPlugin(), channel: channel)
  }

  private let fm = FileManager.default

  /// The folder inside the iCloud container. nil when iCloud is unavailable.
  private func backupsDirectory() -> URL? {
    guard fm.ubiquityIdentityToken != nil,
          let container = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
    let dir = container.appendingPathComponent("Documents/Backups", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // The container lookup can be slow the first time: keep it off the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
      let fail: (String, String) -> Void = { code, message in
        DispatchQueue.main.async { result(FlutterError(code: code, message: message, details: nil)) }
      }
      guard let dir = self.backupsDirectory() else {
        if call.method == "isAvailable" { reply(false) } else { fail("unavailable", "iCloud is not available") }
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "isAvailable":
        reply(true)

      case "list":
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? self.fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        var rows: [[String: Any]] = []
        for url in urls {
          var name = url.lastPathComponent
          // Files not downloaded yet appear as ".name.icloud" placeholders.
          if name.hasPrefix(".") && name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(7))
          }
          guard name.hasPrefix("hisaab_backup_") && name.hasSuffix(".zip") else { continue }
          let values = try? url.resourceValues(forKeys: Set(keys))
          rows.append([
            "name": name,
            "size": values?.fileSize ?? 0,
            "modified": Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0),
          ])
        }
        reply(rows)

      case "upload":
        guard let path = args?["path"] as? String, let name = args?["name"] as? String else {
          fail("bad_args", "path and name are required"); return
        }
        let target = dir.appendingPathComponent(name)
        do {
          if self.fm.fileExists(atPath: target.path) { try self.fm.removeItem(at: target) }
          try self.fm.copyItem(at: URL(fileURLWithPath: path), to: target)
          reply(nil)
        } catch {
          let ns = error as NSError
          fail(ns.code == NSFileWriteOutOfSpaceError ? "no_space" : "io", ns.localizedDescription)
        }

      case "download":
        guard let name = args?["name"] as? String, let path = args?["path"] as? String else {
          fail("bad_args", "name and path are required"); return
        }
        let file = dir.appendingPathComponent(name)
        do {
          try self.fm.startDownloadingUbiquitousItem(at: file)
        } catch { /* already local */ }
        // Wait (up to 60 s) for the real file to appear.
        var waited = 0
        while !self.fm.fileExists(atPath: file.path) && waited < 60 {
          Thread.sleep(forTimeInterval: 1)
          waited += 1
        }
        guard self.fm.fileExists(atPath: file.path) else {
          fail("io", "The backup could not be downloaded from iCloud"); return
        }
        do {
          let target = URL(fileURLWithPath: path)
          if self.fm.fileExists(atPath: target.path) { try self.fm.removeItem(at: target) }
          try self.fm.copyItem(at: file, to: target)
          reply(nil)
        } catch {
          fail("io", (error as NSError).localizedDescription)
        }

      case "delete":
        guard let name = args?["name"] as? String else { fail("bad_args", "name is required"); return }
        for candidate in [name, ".\(name).icloud"] {
          let url = dir.appendingPathComponent(candidate)
          if self.fm.fileExists(atPath: url.path) { try? self.fm.removeItem(at: url) }
        }
        reply(nil)

      default:
        DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
      }
    }
  }
}