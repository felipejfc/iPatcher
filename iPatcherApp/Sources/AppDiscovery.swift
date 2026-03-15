import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Discovers installed apps on the device.
class AppDiscovery: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false

    private let store = PatchStore.shared
    private let logger = AppLogger.shared
    private static let prefersFilesystemDiscovery =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26

    func refresh(includeSystemApps: Bool = false) {
        isLoading = true
        logger.log("Refreshing app list (includeSystemApps=\(includeSystemApps))")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let discovered = Self.discoverApps(includeSystemApps: includeSystemApps)
            DispatchQueue.main.async {
                guard let self else { return }
                self.apps = discovered.map { app in
                    var a = app
                    a.patchCount = self.store.profile(for: a.bundleID)?.patches.count ?? 0
                    return a
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.isLoading = false
                self.logger.log("App discovery completed with \(self.apps.count) entries")
            }
        }
    }

    // MARK: - Private API (LSApplicationWorkspace)

    private static func discoverApps(includeSystemApps: Bool) -> [InstalledApp] {
        if prefersFilesystemDiscovery {
            return discoverFromFilesystem()
        }

        if let apps = discoverViaLSWorkspace(includeSystemApps: includeSystemApps), !apps.isEmpty {
            return apps
        }
        return discoverFromFilesystem()
    }

    private static func discoverViaLSWorkspace(includeSystemApps: Bool) -> [InstalledApp]? {
        guard let wsClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let wsObj = wsClass.perform(NSSelectorFromString("defaultWorkspace"))?
                  .takeUnretainedValue() as? NSObject,
              let proxiesRaw = wsObj.perform(NSSelectorFromString("allApplications"))?
                  .takeUnretainedValue(),
              let proxies = proxiesRaw as? [NSObject]
        else { return nil }

        return proxies.compactMap { proxy -> InstalledApp? in
            guard let bid = proxy.perform(NSSelectorFromString("applicationIdentifier"))?
                    .takeUnretainedValue() as? String
            else { return nil }

            if !includeSystemApps && bid.hasPrefix("com.apple.") {
                return nil
            }

            let name = (proxy.perform(NSSelectorFromString("localizedName"))?
                .takeUnretainedValue() as? String) ?? bid
            let ver  = (proxy.perform(NSSelectorFromString("shortVersionString"))?
                .takeUnretainedValue() as? String) ?? "?"
            var iconPath: String? = nil
            let bundleSel = NSSelectorFromString("bundleURL")
            if proxy.responds(to: bundleSel),
               let url = proxy.perform(bundleSel)?.takeUnretainedValue() as? URL {
                iconPath = url.appendingPathComponent("AppIcon60x60@2x.png").path
            }

            return InstalledApp(
                name: name, bundleID: bid, version: ver,
                iconPath: iconPath
            )
        }
    }

    // MARK: - Filesystem fallback

    private static func discoverFromFilesystem() -> [InstalledApp] {
        let base = "/var/containers/Bundle/Application"
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: base) else { return [] }

        return uuids.compactMap { uuid -> InstalledApp? in
            let dir = "\(base)/\(uuid)"
            guard let contents = try? fm.contentsOfDirectory(atPath: dir),
                  let appBundle = contents.first(where: { $0.hasSuffix(".app") })
            else { return nil }

            let bundlePath = "\(dir)/\(appBundle)"
            let plistPath  = "\(bundlePath)/Info.plist"

            guard let plist = NSDictionary(contentsOfFile: plistPath),
                  let bid = plist["CFBundleIdentifier"] as? String
            else { return nil }

            let name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? bid
            let ver = (plist["CFBundleShortVersionString"] as? String) ?? "?"

            return InstalledApp(
                name: name, bundleID: bid, version: ver,
                iconPath: "\(bundlePath)/AppIcon60x60@2x.png"
            )
        }
    }
}
