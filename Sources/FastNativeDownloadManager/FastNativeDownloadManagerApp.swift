import AppKit
import Network
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct FastNativeDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(FastNativeDownloadManagerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Fast Native Download Manager") {
                    NotificationCenter.default.post(name: .showAboutPanel, object: nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Download") {
                    NotificationCenter.default.post(name: .showAddDownloadSheet, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
    }
}

private enum BrowserCookieSource: String, CaseIterable, Identifiable {
    case none = "None"
    case chrome = "Chrome"
    case chromium = "Chromium"
    case brave = "Brave"
    case edge = "Edge"
    case firefox = "Firefox"
    case safari = "Safari"

    var id: String { rawValue }

    var ytdlpArgument: String {
        switch self {
        case .none: ""
        default: rawValue.lowercased()
        }
    }
}

private final class FastNativeDownloadManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationIcon()
        DefaultPluginInstaller.installBitTorrentPluginIfNeeded()
        DefaultPluginInstaller.installED2KPluginIfNeeded()
        DefaultPluginInstaller.installSiteExtractorPluginsIfNeeded()
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        if AppPreferences.browserBridgeEnabled {
            LocalBrowserBridge.shared.start()
        }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        NotificationCenter.default.post(name: .externalDownloadRequested, object: url)
    }

    @MainActor private func applyApplicationIcon() {
        if let image = AppLogoLoader.image() {
            NSApp.applicationIconImage = image
        }
    }
}

private enum AppPreferences {
    static let saveDirectoryKey = "Options.saveDirectory"
    static let clipboardMonitoringKey = "Options.clipboardMonitoringEnabled"
    static let browserBridgeKey = "Options.browserBridgeEnabled"
    static let showDownloadConfirmationKey = "Options.showDownloadConfirmation"
    static let defaultEngineKey = "Options.defaultEngine"
    static let maximumConcurrentDownloadsKey = "Options.maximumConcurrentDownloads"
    static let cookiesFilePathKey = "Options.cookiesFilePath"
    static let cookiesFromBrowserKey = "Options.cookiesFromBrowser"
    static let cookieProfilesKey = "Options.cookieProfiles"
    static let proxyProfilesKey = "Options.proxyProfiles"
    static let defaultProxyKey = "Options.defaultProxy"
    static let timeLimitEnabledKey = "Options.timeLimitEnabled"
    static let timeLimitStartMinutesKey = "Options.timeLimitStartMinutes"
    static let timeLimitEndMinutesKey = "Options.timeLimitEndMinutes"
    static let timeLimitBytesPerSecondKey = "Options.timeLimitBytesPerSecond"
    static let schedulerEnabledKey = "Scheduler.enabled"
    static let schedulerStartAtKey = "Scheduler.startAt"
    static let schedulerStopEnabledKey = "Scheduler.stopEnabled"
    static let schedulerStopAtKey = "Scheduler.stopAt"
    static let schedulerRepeatsDailyKey = "Scheduler.repeatsDaily"
    static let disabledPluginsKey = "Plugins.disabledIDs"
    static let trustedPluginsKey = "Plugins.trustedIDs"
    static let pluginExecutionTimeoutKey = "Plugins.executionTimeoutSeconds"
    static let confirmPluginTrustKey = "Plugins.confirmTrust"
    static let marketplaceCatalogURLKey = "Plugins.marketplaceCatalogURL"

    static var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: saveDirectoryKey), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
            return downloads.appendingPathComponent("Fast Native Download Manager", isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: saveDirectoryKey)
        }
    }

    static var clipboardMonitoringEnabled: Bool {
        UserDefaults.standard.object(forKey: clipboardMonitoringKey) as? Bool ?? true
    }

    static var browserBridgeEnabled: Bool {
        UserDefaults.standard.object(forKey: browserBridgeKey) as? Bool ?? true
    }

    static var showDownloadConfirmation: Bool {
        UserDefaults.standard.object(forKey: showDownloadConfirmationKey) as? Bool ?? true
    }

    static var defaultEngine: DownloadEngineChoice {
        DownloadEngineChoice(rawValue: UserDefaults.standard.string(forKey: defaultEngineKey) ?? "") ?? .automatic
    }

    static var schedulerStartAt: Date {
        let stored = UserDefaults.standard.double(forKey: schedulerStartAtKey)
        return stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : Date().addingTimeInterval(60 * 5)
    }

    static var schedulerStopAt: Date {
        let stored = UserDefaults.standard.double(forKey: schedulerStopAtKey)
        return stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : Date().addingTimeInterval(60 * 60)
    }

    static var pluginsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return appSupport
            .appendingPathComponent("Fast Native Download Manager", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }
}

private struct CookieProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var browser: String
    var cookiesFilePath: String
}

private struct ProxyProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var proxyURL: String
}

private enum CodableDefaults {
    static func load<T: Decodable>(_ type: T.Type, key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return fallback
        }
        return value
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private struct PluginManifest: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let author: String?
    let description: String?
    let kind: String?
    let entry: String?
    let homepage: String?
    let permissions: [String]?
    let allowedCommands: [String]?
    let protocols: [String]?
    let fileExtensions: [String]?
    let urlPatterns: [String]?
    let engineCommand: String?
    let extractorScript: String?
    let completionAction: String?
    let settingsURL: String?
    let settingsHTML: String?
}

private struct InstalledPlugin: Identifiable, Hashable {
    let manifest: PluginManifest
    let folderURL: URL
    var enabled: Bool
    var trusted: Bool

    var id: String { manifest.id }
}

private struct MarketplacePlugin: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    let kind: String
    let permissions: [String]
    let sourceURL: String?

    static let builtIns: [MarketplacePlugin] = [
        MarketplacePlugin(
            id: "builtin.bittorrent",
            name: "BitTorrent",
            description: "Download .torrent and magnet links through the aria2c bridge with public tracker lists.",
            kind: "engine",
            permissions: ["torrent", "magnet", "external-engine"],
            sourceURL: nil
        ),
        MarketplacePlugin(
            id: "builtin.ed2k",
            name: "eD2K",
            description: "Capture ed2k:// links and submit them to a local eD2K bridge when available.",
            kind: "engine",
            permissions: ["ed2k", "external-engine"],
            sourceURL: nil
        ),
        MarketplacePlugin(
            id: "builtin.extractor.youtube",
            name: "YouTube Extractor",
            description: "Use yt-dlp presets, browser cookies, best MP4 naming, and audio/video merge for YouTube.",
            kind: "extractor",
            permissions: ["site-extractor", "cookies", "external-engine"],
            sourceURL: nil
        ),
        MarketplacePlugin(
            id: "builtin.extractor.bilibili",
            name: "Bilibili Extractor",
            description: "Use yt-dlp presets and browser cookies for Bilibili and b23.tv pages.",
            kind: "extractor",
            permissions: ["site-extractor", "cookies", "external-engine"],
            sourceURL: nil
        ),
        MarketplacePlugin(
            id: "builtin.extractor.tiktok",
            name: "TikTok Extractor",
            description: "Use yt-dlp presets for TikTok pages and related CDN media URLs.",
            kind: "extractor",
            permissions: ["site-extractor", "cookies", "external-engine"],
            sourceURL: nil
        ),
        MarketplacePlugin(
            id: "builtin.extractor.instagram",
            name: "Instagram Extractor",
            description: "Use yt-dlp presets for Instagram posts, reels, and CDN media.",
            kind: "extractor",
            permissions: ["site-extractor", "cookies", "external-engine"],
            sourceURL: nil
        )
    ]
}

private enum PluginSecurityPolicy {
    static func warnings(for manifest: PluginManifest) -> [String] {
        let permissions = Set(manifest.permissions ?? [])
        var warnings: [String] = []
        if manifest.engineCommand?.nilIfEmpty != nil {
            if !permissions.contains("external-engine") {
                warnings.append("engineCommand requires external-engine permission.")
            }
            if !permissions.contains("filesystem-write") && manifest.entry != "builtin" {
                warnings.append("External engine plugins should declare filesystem-write before writing downloads.")
            }
            if commandNeedsShell(manifest.engineCommand ?? ""), !permissions.contains("shell"), manifest.entry != "builtin" {
                warnings.append("Shell operators require shell permission.")
            }
        }
        if manifest.extractorScript?.nilIfEmpty != nil && manifest.extractorScript != "builtin" && !permissions.contains("site-extractor") && !permissions.contains("sniff") {
            warnings.append("extractorScript should declare site-extractor or sniff permission.")
        }
        if (manifest.engineCommand ?? "").contains("cookies") && !permissions.contains("cookies") {
            warnings.append("Cookie access should declare cookies permission.")
        }
        return warnings
    }

    static func commandNeedsShell(_ command: String) -> Bool {
        [";", "&&", "||", "|", ">", "<", "`", "$("].contains { command.contains($0) }
    }
}

private enum DefaultPluginInstaller {
    static func installBitTorrentPluginIfNeeded() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
            let folder = AppPreferences.pluginsDirectory.appendingPathComponent("builtin-bittorrent", isDirectory: true)
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            let manifestURL = folder.appendingPathComponent("plugin.json")

            let manifest = """
            {
              "id": "builtin.bittorrent",
              "name": "BitTorrent",
              "version": "0.1.0",
              "author": "Fast Native Download Manager",
              "description": "Adds .torrent, magnet link, drag-and-drop, and public tracker-list support through the aria2c BitTorrent bridge.",
              "kind": "engine",
              "entry": "builtin",
              "homepage": "https://github.com/itworksig/Fast-Native-Download-Manager",
              "permissions": ["torrent", "magnet", "tracker-list", "external-engine"],
              "allowedCommands": ["aria2c"],
              "protocols": ["magnet"],
              "fileExtensions": ["torrent"],
              "urlPatterns": ["magnet:*", "http://*/*.torrent", "https://*/*.torrent"],
              "engineCommand": "aria2c --enable-dht=true --enable-peer-exchange=true",
              "completionAction": "reveal"
            }
            """
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Fast Native Download Manager default plugin install failed: \(error.localizedDescription)")
        }
    }

    static func installED2KPluginIfNeeded() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
            let folder = AppPreferences.pluginsDirectory.appendingPathComponent("builtin-ed2k", isDirectory: true)
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            let manifestURL = folder.appendingPathComponent("plugin.json")

            let manifest = """
            {
              "id": "builtin.ed2k",
              "name": "eD2K",
              "version": "0.1.0",
              "author": "Fast Native Download Manager",
              "description": "Adds ed2k:// link capture and submits links to a local aMule/eD2K bridge when available.",
              "kind": "engine",
              "entry": "builtin",
              "homepage": "https://github.com/itworksig/Fast-Native-Download-Manager",
              "permissions": ["ed2k", "external-engine"],
              "allowedCommands": ["amulecmd"],
              "protocols": ["ed2k"],
              "fileExtensions": ["ed2k"],
              "urlPatterns": ["ed2k://*"],
              "engineCommand": "amulecmd --command AddLink",
              "completionAction": "reveal"
            }
            """
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Fast Native Download Manager eD2K plugin install failed: \(error.localizedDescription)")
        }
    }

    static func installSiteExtractorPluginsIfNeeded() {
        installYouTubeExtractorPluginIfNeeded()
        installBilibiliExtractorPluginIfNeeded()
        installTikTokExtractorPluginIfNeeded()
        installInstagramExtractorPluginIfNeeded()
    }

    static func installYouTubeExtractorPluginIfNeeded() {
        installYTDLPSitePlugin(
            id: "builtin.extractor.youtube",
            folderName: "builtin-extractor-youtube",
            name: "YouTube Extractor",
            description: "Site-specific yt-dlp extractor preset for YouTube video pages, Shorts, cookies, naming, and MP4 merge.",
            urlPatterns: ["https://www.youtube.com/*", "https://youtube.com/*", "https://youtu.be/*"],
            format: "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"
        )
    }

    static func installBilibiliExtractorPluginIfNeeded() {
        installYTDLPSitePlugin(
            id: "builtin.extractor.bilibili",
            folderName: "builtin-extractor-bilibili",
            name: "Bilibili Extractor",
            description: "Site-specific yt-dlp extractor preset for Bilibili/B23 pages with browser cookies and best media merge.",
            urlPatterns: ["https://www.bilibili.com/*", "https://bilibili.com/*", "https://b23.tv/*"],
            format: "bv*+ba/b"
        )
    }

    static func installTikTokExtractorPluginIfNeeded() {
        installYTDLPSitePlugin(
            id: "builtin.extractor.tiktok",
            folderName: "builtin-extractor-tiktok",
            name: "TikTok Extractor",
            description: "Site-specific yt-dlp extractor preset for TikTok pages and CDN video URLs.",
            urlPatterns: ["https://www.tiktok.com/*", "https://tiktok.com/*", "https://*.tiktokcdn.com/*"],
            format: "bv*+ba/b"
        )
    }

    static func installInstagramExtractorPluginIfNeeded() {
        installYTDLPSitePlugin(
            id: "builtin.extractor.instagram",
            folderName: "builtin-extractor-instagram",
            name: "Instagram Extractor",
            description: "Site-specific yt-dlp extractor preset for Instagram posts, reels, and CDN media.",
            urlPatterns: ["https://www.instagram.com/*", "https://instagram.com/*", "https://*.cdninstagram.com/*"],
            format: "bv*+ba/b"
        )
    }

    private static func installYTDLPSitePlugin(id: String, folderName: String, name: String, description: String, urlPatterns: [String], format: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
            let folder = AppPreferences.pluginsDirectory.appendingPathComponent(folderName, isDirectory: true)
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let escapedPatterns = urlPatterns.map { "\"\($0)\"" }.joined(separator: ", ")
            let manifest = """
            {
              "id": "\(id)",
              "name": "\(name)",
              "version": "0.1.0",
              "author": "Fast Native Download Manager",
              "description": "\(description)",
              "kind": "extractor",
              "entry": "builtin",
              "homepage": "https://github.com/itworksig/Fast-Native-Download-Manager",
              "permissions": ["site-extractor", "cookies", "external-engine", "filesystem-write"],
              "allowedCommands": ["yt-dlp"],
              "protocols": [],
              "fileExtensions": [],
              "urlPatterns": [\(escapedPatterns)],
              "engineCommand": "yt-dlp --newline --progress --merge-output-format mp4 --restrict-filenames --no-part ${FNDM_COOKIES_FILE:+--cookies \\\"$FNDM_COOKIES_FILE\\\"} ${FNDM_COOKIES_FROM_BROWSER:+--cookies-from-browser \\\"$FNDM_COOKIES_FROM_BROWSER\\\"} -f \\\"${FNDM_FORMAT:-\(format)}\\\" -o \\\"${FNDM_OUTPUT_DIR}/%(title).200B.%(ext)s\\\" \\\"${FNDM_URL}\\\"",
              "extractorScript": "builtin",
              "completionAction": "notify"
            }
            """
            try manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        } catch {
            NSLog("Fast Native Download Manager site plugin install failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
private final class PluginManager: ObservableObject {
    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published var statusMessage: String?

    private let fileManager = FileManager.default
    private var disabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: AppPreferences.disabledPluginsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: AppPreferences.disabledPluginsKey) }
    }
    private var trustedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: AppPreferences.trustedPluginsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: AppPreferences.trustedPluginsKey) }
    }

    init() {
        installDefaultPluginsIfNeeded()
        reload()
    }

    func reload() {
        try? fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
        let folders = (try? fileManager.contentsOfDirectory(
            at: AppPreferences.pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let disabled = disabledIDs
        let trusted = trustedIDs
        plugins = folders.compactMap { folder in
            guard let manifest = Self.loadManifest(from: folder) else { return nil }
            return InstalledPlugin(
                manifest: manifest,
                folderURL: folder,
                enabled: !disabled.contains(manifest.id),
                trusted: trusted.contains(manifest.id) || manifest.entry == "builtin"
            )
        }
        .sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    func installFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Install"
        panel.message = "Choose a plugin folder or a plugin.json manifest."
        if panel.runModal() == .OK, let url = panel.url {
            install(from: url)
        }
    }

    func install(from sourceURL: URL) {
        do {
            try fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
            let manifestURL = try manifestURL(for: sourceURL)
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            let warnings = PluginSecurityPolicy.warnings(for: manifest)
            let targetFolder = AppPreferences.pluginsDirectory.appendingPathComponent(Self.safeFolderName(for: manifest.id), isDirectory: true)

            if fileManager.fileExists(atPath: targetFolder.path) {
                try fileManager.removeItem(at: targetFolder)
            }

            if sourceURL.hasDirectoryPath {
                try fileManager.copyItem(at: sourceURL, to: targetFolder)
            } else {
                try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: targetFolder.appendingPathComponent("plugin.json"))
            }

            var disabled = disabledIDs
            disabled.insert(manifest.id)
            disabledIDs = disabled
            var trusted = trustedIDs
            trusted.remove(manifest.id)
            trustedIDs = trusted
            statusMessage = warnings.isEmpty
                ? "Installed \(manifest.name). Review permissions, then Trust and Enable it."
                : "Installed \(manifest.name) with warnings: \(warnings.joined(separator: " "))"
            reload()
        } catch {
            statusMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool, for plugin: InstalledPlugin) {
        if enabled, !plugin.trusted, Self.requiresTrust(plugin.manifest) {
            statusMessage = "Trust \(plugin.manifest.name) before enabling. It can run commands or write files."
            return
        }
        var disabled = disabledIDs
        if enabled {
            disabled.remove(plugin.id)
        } else {
            disabled.insert(plugin.id)
        }
        disabledIDs = disabled
        statusMessage = enabled ? "Enabled \(plugin.manifest.name)." : "Disabled \(plugin.manifest.name)."
        reload()
    }

    func setTrusted(_ trusted: Bool, for plugin: InstalledPlugin) {
        if trusted, shouldConfirmPluginTrust, !confirmTrust(for: plugin) {
            statusMessage = "Trust canceled for \(plugin.manifest.name)."
            return
        }
        var ids = trustedIDs
        if trusted {
            ids.insert(plugin.id)
            statusMessage = "Trusted \(plugin.manifest.name). You can enable it now."
        } else {
            ids.remove(plugin.id)
            var disabled = disabledIDs
            disabled.insert(plugin.id)
            disabledIDs = disabled
            statusMessage = "Untrusted and disabled \(plugin.manifest.name)."
        }
        trustedIDs = ids
        reload()
    }

    private var shouldConfirmPluginTrust: Bool {
        UserDefaults.standard.object(forKey: AppPreferences.confirmPluginTrustKey) as? Bool ?? true
    }

    private func confirmTrust(for plugin: InstalledPlugin) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Trust \(plugin.manifest.name)?"
        let permissions = (plugin.manifest.permissions ?? []).joined(separator: ", ")
        let command = plugin.manifest.engineCommand?.nilIfEmpty ?? "None"
        let extractor = plugin.manifest.extractorScript?.nilIfEmpty ?? "None"
        let warnings = PluginSecurityPolicy.warnings(for: plugin.manifest)
        alert.informativeText = """
        This plugin may run commands or access download context.

        Permissions: \(permissions.isEmpty ? "None declared" : permissions)
        Engine command: \(command)
        Extractor script: \(extractor)
        Security review: \(warnings.isEmpty ? "No warnings" : warnings.joined(separator: " "))
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Trust Plugin")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func remove(_ plugin: InstalledPlugin) {
        do {
            try fileManager.removeItem(at: plugin.folderURL)
            var disabled = disabledIDs
            disabled.remove(plugin.id)
            disabledIDs = disabled
            var trusted = trustedIDs
            trusted.remove(plugin.id)
            trustedIDs = trusted
            statusMessage = "Removed \(plugin.manifest.name)."
            reload()
        } catch {
            statusMessage = "Remove failed: \(error.localizedDescription)"
        }
    }

    func openPluginsFolder() {
        try? fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppPreferences.pluginsDirectory)
    }

    func openAuditLog() {
        try? fileManager.createDirectory(at: AppPreferences.pluginsDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let logURL = AppPreferences.pluginsDirectory.deletingLastPathComponent().appendingPathComponent("plugin-audit.log")
        if !fileManager.fileExists(atPath: logURL.path) {
            try? "Fast Native Download Manager plugin audit log\n".write(to: logURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(logURL)
    }

    func createTemplatePlugin() {
        do {
            try fileManager.createDirectory(at: AppPreferences.pluginsDirectory, withIntermediateDirectories: true)
            let folder = AppPreferences.pluginsDirectory.appendingPathComponent("example-site-extractor", isDirectory: true)
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let manifest = """
            {
              "id": "example-site-extractor",
              "name": "Example Site Extractor",
              "version": "0.1.0",
              "author": "Local",
              "description": "Example plugin manifest for future site sniffing and extractor extensions.",
              "kind": "extractor",
              "entry": "main.js",
              "permissions": ["sniff", "download-request"],
              "allowedCommands": ["yt-dlp"],
              "protocols": [],
              "fileExtensions": ["mp4", "m3u8", "mpd"],
              "urlPatterns": ["https://example.com/*"],
              "engineCommand": "yt-dlp",
              "extractorScript": "main.js",
              "completionAction": "notify"
            }
            """
            try manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
            let script = """
            export function match(url) {
              return url.includes("example.com");
            }

            export async function extract(page) {
              return [];
            }
            """
            try script.write(to: folder.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
            statusMessage = "Template plugin created."
            reload()
            openPluginsFolder()
        } catch {
            statusMessage = "Template failed: \(error.localizedDescription)"
        }
    }

    func installMarketplacePlugins() {
        DefaultPluginInstaller.installSiteExtractorPluginsIfNeeded()
        DefaultPluginInstaller.installBitTorrentPluginIfNeeded()
        DefaultPluginInstaller.installED2KPluginIfNeeded()
        let builtinIDs = [
            "builtin.bittorrent",
            "builtin.ed2k",
            "builtin.extractor.youtube",
            "builtin.extractor.bilibili",
            "builtin.extractor.tiktok",
            "builtin.extractor.instagram"
        ]
        trustedIDs.formUnion(builtinIDs)
        statusMessage = "Marketplace built-ins installed: YouTube, Bilibili, TikTok, Instagram, BitTorrent, and eD2K."
        reload()
    }

    func installMarketplacePlugin(_ plugin: MarketplacePlugin) {
        if let sourceURL = plugin.sourceURL, let url = URL(string: sourceURL) {
            Task {
                await installRemoteMarketplacePlugin(plugin, sourceURL: url)
            }
            return
        }

        switch plugin.id {
        case "builtin.bittorrent":
            DefaultPluginInstaller.installBitTorrentPluginIfNeeded()
        case "builtin.ed2k":
            DefaultPluginInstaller.installED2KPluginIfNeeded()
        case "builtin.extractor.youtube":
            DefaultPluginInstaller.installYouTubeExtractorPluginIfNeeded()
        case "builtin.extractor.bilibili":
            DefaultPluginInstaller.installBilibiliExtractorPluginIfNeeded()
        case "builtin.extractor.tiktok":
            DefaultPluginInstaller.installTikTokExtractorPluginIfNeeded()
        case "builtin.extractor.instagram":
            DefaultPluginInstaller.installInstagramExtractorPluginIfNeeded()
        default:
            statusMessage = "Unknown marketplace plugin: \(plugin.name)"
            return
        }

        var trusted = trustedIDs
        trusted.insert(plugin.id)
        trustedIDs = trusted

        var disabled = disabledIDs
        disabled.remove(plugin.id)
        disabledIDs = disabled

        statusMessage = "Installed and enabled \(plugin.name)."
        reload()
    }

    func installRemoteMarketplacePlugin(_ plugin: MarketplacePlugin, sourceURL: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("fndm-marketplace-\(UUID().uuidString)")
                .appendingPathExtension("json")
            try data.write(to: tempURL, options: .atomic)
            await MainActor.run {
                install(from: tempURL)
                statusMessage = "Installed \(plugin.name) from marketplace. Review permissions before enabling."
            }
        } catch {
            await MainActor.run {
                statusMessage = "Remote install failed for \(plugin.name): \(error.localizedDescription)"
            }
        }
    }

    private func installDefaultPluginsIfNeeded() {
        DefaultPluginInstaller.installBitTorrentPluginIfNeeded()
        DefaultPluginInstaller.installED2KPluginIfNeeded()
        DefaultPluginInstaller.installSiteExtractorPluginsIfNeeded()
    }

    private func manifestURL(for sourceURL: URL) throws -> URL {
        if sourceURL.hasDirectoryPath {
            let candidates = [
                sourceURL.appendingPathComponent("plugin.json"),
                sourceURL.appendingPathComponent("fndm-plugin.json")
            ]
            if let found = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                return found
            }
            throw CocoaError(.fileNoSuchFile)
        }
        return sourceURL
    }

    private static func loadManifest(from folderURL: URL) -> PluginManifest? {
        let candidates = [
            folderURL.appendingPathComponent("plugin.json"),
            folderURL.appendingPathComponent("fndm-plugin.json")
        ]
        guard let manifestURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    private static func safeFolderName(for id: String) -> String {
        id.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        .reduce(into: "") { $0.append($1) }
    }

    private static func requiresTrust(_ manifest: PluginManifest) -> Bool {
        let permissions = Set(manifest.permissions ?? [])
        return manifest.engineCommand?.isEmpty == false
            || manifest.completionAction?.isEmpty == false
            || !permissions.isDisjoint(with: ["external-engine", "filesystem-write", "shell", "cookies"])
    }
}

private struct SniffedResource: Identifiable, Codable, Hashable {
    var id: String { url }
    let url: String
    let host: String
    let type: String
    let title: String
    let quality: String
    let size: String
    let confidence: Double
    let fileName: String?
    let headers: [String: String]
    let cookie: String?

    var downloadRequest: BrowserDownloadRequest {
        BrowserDownloadRequest(url: url, fileName: fileName ?? title, headers: headers, cookie: cookie, source: "grabber")
    }
}

private struct PluginExtractorRequest: Codable {
    let url: String
    let title: String?
}

private enum PluginAuditLog {
    static var url: URL {
        AppPreferences.pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-audit.log")
    }

    static func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            NSLog("Fast Native Download Manager plugin audit failed: \(error.localizedDescription)")
        }
    }
}

private final class PluginProcessWaitState: @unchecked Sendable {
    let lock = NSLock()
    var didResume = false
}

private enum PluginExtractorRunner {
    static func extract(pageURL: String, title: String?) async -> [SniffedResource] {
        guard let url = URL(string: pageURL), DownloadManager.normalizedURL(from: pageURL) != nil else {
            return []
        }

        let plugins = loadEnabledTrustedExtractorPlugins()
            .filter { pluginMatches($0.manifest, url: url) }
        guard !plugins.isEmpty else { return [] }

        var resources: [SniffedResource] = []
        for plugin in plugins {
            if plugin.manifest.extractorScript == "builtin" || plugin.manifest.entry == "builtin" {
                resources.append(builtinResource(for: plugin.manifest, pageURL: url, title: title))
                PluginAuditLog.append("extract builtin plugin=\(plugin.manifest.id) url=\(pageURL)")
            } else if let extracted = await runScriptExtractor(plugin: plugin, pageURL: pageURL, title: title) {
                resources.append(contentsOf: extracted)
            }
        }
        return resources
    }

    private static func loadEnabledTrustedExtractorPlugins() -> [InstalledPlugin] {
        let disabled = Set(UserDefaults.standard.stringArray(forKey: AppPreferences.disabledPluginsKey) ?? [])
        let trusted = Set(UserDefaults.standard.stringArray(forKey: AppPreferences.trustedPluginsKey) ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: AppPreferences.pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders.compactMap { folder in
            let candidates = [
                folder.appendingPathComponent("plugin.json"),
                folder.appendingPathComponent("fndm-plugin.json")
            ]
            guard let manifestURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data),
                  (manifest.kind?.lowercased() == "extractor" || manifest.extractorScript?.isEmpty == false),
                  !disabled.contains(manifest.id),
                  trusted.contains(manifest.id) || manifest.entry == "builtin" else {
                return nil
            }
            return InstalledPlugin(
                manifest: manifest,
                folderURL: folder,
                enabled: true,
                trusted: trusted.contains(manifest.id) || manifest.entry == "builtin"
            )
        }
    }

    private static func pluginMatches(_ manifest: PluginManifest, url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        let urlString = url.absoluteString.lowercased()
        if scheme != "http", scheme != "https",
           manifest.protocols?.map({ $0.lowercased() }).contains(scheme) == true {
            return true
        }
        for pattern in manifest.urlPatterns ?? [] {
            if DownloadManager.urlString(urlString, host: url.host?.lowercased(), matchesPluginPattern: pattern) {
                return true
            }
        }
        return false
    }

    private static func builtinResource(for manifest: PluginManifest, pageURL: URL, title: String?) -> SniffedResource {
        let preset = DownloadManager.sitePreset(for: pageURL)
        let presetName = preset?.name ?? manifest.name.replacingOccurrences(of: " Extractor", with: "").lowercased()
        let fileName = sanitizeFileName(title ?? manifest.name)
        var headers = [
            "User-Agent": "Fast Native Download Manager Plugin Extractor",
            "Referer": pageURL.absoluteString,
            DownloadManager.engineHeaderKey: (preset?.engine ?? .ytdlp).rawValue,
            DownloadManager.sitePresetHeaderKey: presetName
        ]
        if let format = preset?.ytdlpFormat, !format.isEmpty {
            headers[DownloadManager.ytdlpFormatHeaderKey] = format
        }
        return SniffedResource(
            url: pageURL.absoluteString,
            host: pageURL.host ?? "",
            type: presetName.uppercased(),
            title: fileName,
            quality: "plugin extractor",
            size: "--",
            confidence: 0.99,
            fileName: fileName,
            headers: headers,
            cookie: nil
        )
    }

    private static func runScriptExtractor(plugin: InstalledPlugin, pageURL: String, title: String?) async -> [SniffedResource]? {
        let permissions = Set(plugin.manifest.permissions ?? [])
        guard permissions.contains("site-extractor") || permissions.contains("sniff") else {
            PluginAuditLog.append("extract script blocked plugin=\(plugin.manifest.id) reason=missing site-extractor/sniff permission")
            return nil
        }
        guard let script = plugin.manifest.extractorScript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty,
              script != "builtin" else {
            return nil
        }

        let scriptURL = plugin.folderURL.appendingPathComponent(script)
        guard scriptURL.standardizedFileURL.path.hasPrefix(plugin.folderURL.standardizedFileURL.path) else {
            PluginAuditLog.append("extract script blocked plugin=\(plugin.manifest.id) reason=script outside plugin folder")
            return nil
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            PluginAuditLog.append("extract script missing plugin=\(plugin.manifest.id) script=\(script)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", scriptURL.path, pageURL]
        process.currentDirectoryURL = plugin.folderURL
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "FNDM_PAGE_URL": pageURL,
            "FNDM_PAGE_TITLE": title ?? "",
            "FNDM_PLUGIN_ID": plugin.manifest.id
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            PluginAuditLog.append("extract script start plugin=\(plugin.manifest.id) url=\(pageURL)")
            try process.run()
            let timeout = max(30, UserDefaults.standard.object(forKey: AppPreferences.pluginExecutionTimeoutKey) as? Int ?? 1800)
            let timedOut = await waitForProcess(process, timeout: TimeInterval(timeout))
            if timedOut {
                PluginAuditLog.append("extract script timeout plugin=\(plugin.manifest.id) after=\(timeout)s")
                return nil
            }
            await withCheckedContinuation { continuation in
                if !process.isRunning {
                    continuation.resume()
                    return
                }
                process.terminationHandler = { _ in continuation.resume() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            PluginAuditLog.append("extract script end plugin=\(plugin.manifest.id) status=\(process.terminationStatus) output=\(text.prefix(500))")
            guard process.terminationStatus == 0 else { return nil }
            return try? JSONDecoder().decode([SniffedResource].self, from: data)
        } catch {
            PluginAuditLog.append("extract script failed plugin=\(plugin.manifest.id) error=\(error.localizedDescription)")
            return nil
        }
    }

    private static func waitForProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = PluginProcessWaitState()
            @Sendable func resume(_ timedOut: Bool) {
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.didResume else { return }
                state.didResume = true
                continuation.resume(returning: timedOut)
            }

            process.terminationHandler = { _ in
                resume(false)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            process.interrupt()
                        }
                    }
                    resume(true)
                }
            }
        }
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "download"
    }
}

private struct ConnectionSlice: Identifiable {
    let id = UUID()
    let part: Int
    let range: String
    let speed: String
    let progress: Double
}

private struct DeleteConfirmation: Identifiable {
    let id: DownloadItem.ID
    let fileName: String
}

private struct BatchPropertiesRequest: Identifiable {
    let id = UUID()
    let items: [DownloadItem]
}

private struct DownloadConfirmationRequest: Identifiable {
    let id = UUID()
    let url: String
    let fileName: String?
    let headers: [String: String]
    let cookie: String?

    init(url: String, fileName: String? = nil, headers: [String: String] = [:], cookie: String? = nil) {
        self.url = url
        self.fileName = fileName
        self.headers = headers
        self.cookie = cookie
    }
}

private struct DownloadConfirmationResult {
    let url: String
    let fileName: String
    let category: Category
    let saveDirectory: URL
    let headers: [String: String]
    let cookie: String?
    let engine: DownloadEngineChoice
    let startImmediately: Bool
}

private struct PluginPickerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
}

private struct MainWindow: View {
    @StateObject private var manager = DownloadManager()
    @State private var selectedCategory: Category = .all
    @State private var selectedDownloadID: DownloadItem.ID?
    @State private var developmentMessage: String?
    @State private var detailWindowController: DownloadDetailWindowController?
    @State private var downloadConfirmationRequest: DownloadConfirmationRequest?
    @State private var pendingClipboardURL: String?
    @State private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    @State private var lastPromptedClipboardURL = ""
    @State private var deleteConfirmation: DeleteConfirmation?
    @State private var batchPropertiesRequest: BatchPropertiesRequest?
    @State private var sniffedResources: [SniffedResource] = []
    @State private var searchText = ""
    @State private var showingGrabber = false
    @State private var showingOptions = false
    @State private var showingScheduler = false
    @State private var showingTellFriend = false
    @State private var showingAbout = false
    @State private var lastSchedulerStartFireID = ""
    @State private var lastSchedulerStopFireID = ""
    @AppStorage(AppPreferences.clipboardMonitoringKey) private var clipboardMonitoringEnabled = true
    @AppStorage(AppPreferences.browserBridgeKey) private var browserBridgeEnabled = true
    @AppStorage(AppPreferences.showDownloadConfirmationKey) private var showDownloadConfirmation = true
    @AppStorage(AppPreferences.schedulerEnabledKey) private var schedulerEnabled = false

    private let clipboardTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var filteredDownloads: [DownloadItem] {
        let categoryFiltered = manager.downloads.filter { item in
            selectedCategory == .all
                || item.category == selectedCategory
                || selectedCategory == .active && item.status == .downloading
                || selectedCategory == .unfinished && item.status != .complete
                || selectedCategory == .finished && item.status == .complete
                || selectedCategory == .mainDownload && item.status != .complete && item.status != .canceled
                || selectedCategory == .synchronization && false
                || selectedCategory == .queue3 && false
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter { item in
            item.fileName.lowercased().contains(query)
                || item.url.lowercased().contains(query)
                || item.status.rawValue.lowercased().contains(query)
                || item.category.rawValue.lowercased().contains(query)
                || item.detail.lowercased().contains(query)
        }
    }

    private var selectedDownload: DownloadItem? {
        guard let selectedDownloadID else { return nil }
        return manager.downloads.first { $0.id == selectedDownloadID }
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeToolbar(
                onAddURL: { requestDownloadConfirmation("") },
                onResume: { resumeSelectedDownload() },
                onStop: { manager.pause(selectedDownload) },
                onStopAll: { manager.downloads.forEach(manager.pause) },
                onDelete: { deleteSelectedDownload() },
                onDeleteCompleted: manager.removeCompleted,
                onStartQueue: { manager.startQueue() },
                onStopQueue: { manager.stopQueue() },
                onOptions: { showingOptions = true },
                onScheduler: { showingScheduler = true },
                onGrabber: { showingGrabber = true },
                onTellFriend: { showingTellFriend = true },
                onFeature: showInDevelopment
            )

            HSplitView {
                NativeSidebar(selectedCategory: $selectedCategory, downloads: manager.downloads, onFeature: showInDevelopment)
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 310)

                NativeDownloadTable(
                    downloads: filteredDownloads,
                    searchText: $searchText,
                    selectedDownloadID: $selectedDownloadID,
                    onOpenDetails: openDetailsIfAvailable,
                    onDelete: deleteDownload,
                    onCopyURL: copyURL,
                    onCopyFileName: copyFileName,
                    onCopySavePath: copySavePath,
                    onOpenFile: openFile,
                    onRevealInFinder: revealInFinder,
                    onRetryFailed: retryFailedVisibleDownloads,
                    onMoveCompleted: moveCompletedVisibleDownloads,
                    onDeleteFailed: deleteFailedVisibleDownloads,
                    onRestartVisible: restartVisibleDownloads,
                    onDeleteVisible: deleteVisibleDownloads,
                    onEditProperties: editVisibleDownloadProperties
                )
            }

            NativeStatusBar(
                downloads: filteredDownloads,
                resources: sniffedResources,
                totalSpeed: manager.totalSpeedText,
                queueStatus: manager.queueStatusText,
                maximumConcurrentDownloads: $manager.maximumConcurrentDownloads
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $downloadConfirmationRequest) { request in
            AddDownloadSheet(request: request, manager: manager) { result in
                addConfirmedDownload(result)
            }
        }
        .sheet(isPresented: $showingGrabber) {
            GrabberResourcesPanel(
                resources: sniffedResources,
                onDownload: { request in
                    showingGrabber = false
                    requestDownloadConfirmation(request)
                },
                onClear: { sniffedResources.removeAll() }
            )
        }
        .sheet(isPresented: $showingOptions) {
            OptionsPanel(
                manager: manager,
                clipboardMonitoringEnabled: $clipboardMonitoringEnabled,
                browserBridgeEnabled: $browserBridgeEnabled,
                showDownloadConfirmation: $showDownloadConfirmation
            )
        }
        .sheet(isPresented: $showingScheduler) {
            SchedulerPanel(manager: manager)
        }
        .sheet(isPresented: $showingTellFriend) {
            TellFriendPanel()
        }
        .sheet(item: $batchPropertiesRequest) { request in
            BatchPropertiesPanel(downloads: request.items, manager: manager)
        }
        .sheet(isPresented: $showingAbout) {
            AboutPanel()
        }
        .alert("功能开发中", isPresented: Binding(
            get: { developmentMessage != nil },
            set: { if !$0 { developmentMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(developmentMessage ?? "这个功能正在开发中。")
        }
        .alert("Detected downloadable link", isPresented: Binding(
            get: { pendingClipboardURL != nil },
            set: { if !$0 { pendingClipboardURL = nil } }
        )) {
            Button("Download") {
                if let url = pendingClipboardURL {
                    requestDownloadConfirmation(url)
                }
                pendingClipboardURL = nil
            }
            Button("Ignore", role: .cancel) {
                pendingClipboardURL = nil
            }
        } message: {
            Text(pendingClipboardURL ?? "")
        }
        .alert("Delete download record?", isPresented: Binding(
            get: { deleteConfirmation != nil },
            set: { if !$0 { deleteConfirmation = nil } }
        )) {
            Button("Delete", role: .destructive) {
                performConfirmedDelete()
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
        } message: {
            Text("Remove \"\(deleteConfirmation?.fileName ?? "this download")\" from the download list? This only removes the selected record and partial file.")
        }
        .onAppear {
            selectedDownloadID = manager.downloads.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownloadSheet)) { _ in
            requestDownloadConfirmation("")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutPanel)) { _ in
            showingAbout = true
        }
        .onReceive(clipboardTimer) { _ in
            checkClipboardForDownloadableLink()
            checkExternalDownloadInbox()
            checkScheduler()
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalDownloadRequested)) { notification in
            guard let url = notification.object as? URL else { return }
            handleExternalDownloadRequest(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalRawDownloadRequested)) { notification in
            if let request = notification.object as? BrowserDownloadRequest {
                startExternalDownload(request)
            } else if let rawURL = notification.object as? String {
                startExternalDownload(BrowserDownloadRequest(url: rawURL))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sniffedResourcesDetected)) { notification in
            guard let resources = notification.object as? [SniffedResource] else { return }
            mergeSniffedResources(resources)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pluginExtractionRequested)) { notification in
            guard let request = notification.object as? PluginExtractorRequest else { return }
            runPluginExtractors(for: request)
        }
        .onOpenURL { url in
            handleExternalDownloadRequest(url)
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.plainText.identifier], isTargeted: nil) { providers in
            handleDroppedItems(providers)
        }
    }

    private func resumeSelectedDownload() {
        guard let selectedDownload else {
            showInDevelopment("请先选择一个下载任务。")
            return
        }

        guard selectedDownload.sourceURL != nil else {
            showInDevelopment("示例任务不能真实下载。请点 Add URL 添加一个 HTTP/HTTPS 链接来测试下载、暂停和恢复。")
            return
        }

        manager.start(selectedDownload)
        showDetails(for: selectedDownload)
    }

    private func openDetailsIfAvailable(_ item: DownloadItem) {
        selectedDownloadID = item.id
        if item.sourceURL == nil {
            showInDevelopment("这是界面示例任务。真实下载任务会在 Add URL 后弹出原生下载详情窗口。")
            return
        }
        showDetails(for: item)
    }

    private func showDetails(for item: DownloadItem) {
        let controller = DownloadDetailWindowController(
            download: item,
            onResume: { manager.start(item) },
            onPause: { manager.pause(item) },
            onCancel: { manager.cancel(item) },
            onSaveSettings: { manager.saveTaskSettings(item) }
        )
        detailWindowController = controller
        controller.show()
    }

    private func requestDownloadConfirmation(_ url: String) {
        downloadConfirmationRequest = DownloadConfirmationRequest(url: url)
        bringAppToFront()
    }

    private func requestDownloadConfirmation(_ request: BrowserDownloadRequest) {
        downloadConfirmationRequest = DownloadConfirmationRequest(
            url: request.url,
            fileName: request.fileName,
            headers: request.headers,
            cookie: request.cookie
        )
        bringAppToFront()
    }

    private func addConfirmedDownload(_ result: DownloadConfirmationResult) {
        guard let item = manager.addDownload(
            from: result.url,
            fileName: result.fileName,
            category: result.category,
            saveDirectory: result.saveDirectory,
            headers: result.headers,
            cookie: result.cookie,
            engine: result.engine,
            startImmediately: result.startImmediately
        ) else {
            showInDevelopment("这个链接暂时不能下载：\(result.url)")
            return
        }

        selectedDownloadID = item.id
        selectedCategory = .all
        if result.startImmediately {
            showDetails(for: item)
        }
    }

    private func deleteSelectedDownload() {
        guard let selectedDownload else {
            showInDevelopment("请先选择一个下载记录。")
            return
        }
        deleteDownload(selectedDownload)
    }

    private func deleteDownload(_ item: DownloadItem) {
        deleteConfirmation = DeleteConfirmation(id: item.id, fileName: item.fileName)
    }

    private func performConfirmedDelete() {
        guard let confirmation = deleteConfirmation,
              let item = manager.downloads.first(where: { $0.id == confirmation.id }) else {
            deleteConfirmation = nil
            return
        }

        manager.deleteRecord(item)
        if selectedDownloadID == item.id {
            selectedDownloadID = filteredDownloads.first { $0.id != item.id }?.id ?? manager.downloads.first?.id
        }
        deleteConfirmation = nil
    }

    private func copyURL(_ item: DownloadItem) {
        copyToPasteboard(item.url)
    }

    private func copyFileName(_ item: DownloadItem) {
        copyToPasteboard(item.fileName)
    }

    private func copySavePath(_ item: DownloadItem) {
        copyToPasteboard(item.destinationURL.path)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func openFile(_ item: DownloadItem) {
        guard FileManager.default.fileExists(atPath: item.destinationURL.path), item.status == .complete else {
            showInDevelopment("文件尚未下载完成，不能打开。")
            return
        }
        NSWorkspace.shared.open(item.destinationURL)
    }

    private func revealInFinder(_ item: DownloadItem) {
        if FileManager.default.fileExists(atPath: item.destinationURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([item.destinationURL])
        } else {
            NSWorkspace.shared.open(item.destinationURL.deletingLastPathComponent())
        }
    }

    private func retryFailedVisibleDownloads() {
        let failed = filteredDownloads.filter { $0.status == .failed || $0.status == .canceled }
        guard !failed.isEmpty else {
            showInDevelopment("当前列表没有失败或已取消的任务。")
            return
        }
        failed.forEach { manager.start($0) }
    }

    private func moveCompletedVisibleDownloads() {
        let completed = filteredDownloads.filter { $0.status == .complete && FileManager.default.fileExists(atPath: $0.destinationURL.path) }
        guard !completed.isEmpty else {
            showInDevelopment("当前列表没有可移动的已完成文件。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move"
        panel.message = "Choose a folder for completed downloads in the current view."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for item in completed {
            let target = DownloadManager.uniqueDestinationURL(for: folder.appendingPathComponent(item.fileName))
            do {
                try FileManager.default.moveItem(at: item.destinationURL, to: target)
                item.destinationURL = target
                item.fileName = target.lastPathComponent
                item.detail = "Moved to \(target.path)"
                manager.saveTaskSettings(item)
            } catch {
                item.detail = "Move failed: \(error.localizedDescription)"
                manager.saveTaskSettings(item)
            }
        }
    }

    private func deleteFailedVisibleDownloads() {
        let failed = filteredDownloads.filter { $0.status == .failed || $0.status == .canceled }
        guard !failed.isEmpty else {
            showInDevelopment("当前列表没有失败或已取消的任务。")
            return
        }
        failed.forEach(manager.deleteRecord)
        selectedDownloadID = filteredDownloads.first?.id ?? manager.downloads.first?.id
    }

    private func restartVisibleDownloads() {
        let restartable = filteredDownloads.filter { $0.sourceURL != nil && $0.status != .downloading }
        guard !restartable.isEmpty else {
            showInDevelopment("当前列表没有可重新下载的任务。")
            return
        }
        restartable.forEach { manager.restart($0) }
    }

    private func deleteVisibleDownloads() {
        let removable = filteredDownloads
        guard !removable.isEmpty else {
            showInDevelopment("当前列表没有可删除的任务。")
            return
        }
        removable.forEach(manager.deleteRecord)
        selectedDownloadID = manager.downloads.first?.id
    }

    private func editVisibleDownloadProperties() {
        let editable = filteredDownloads.filter { $0.sourceURL != nil }
        guard !editable.isEmpty else {
            showInDevelopment("当前列表没有可编辑的真实下载任务。")
            return
        }
        batchPropertiesRequest = BatchPropertiesRequest(items: editable)
    }

    private func showInDevelopment(_ feature: String) {
        developmentMessage = feature
    }

    private func checkClipboardForDownloadableLink() {
        guard clipboardMonitoringEnabled else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount

        guard let string = pasteboard.string(forType: .string),
              let url = ClipboardDownloadDetector.downloadableURL(in: string),
              url != lastPromptedClipboardURL else {
            return
        }

        lastPromptedClipboardURL = url
        pendingClipboardURL = url
    }

    private func handleExternalDownloadRequest(_ incomingURL: URL) {
        guard let downloadURL = ExternalDownloadRequestParser.downloadURL(from: incomingURL) else {
            showInDevelopment("浏览器扩展发来的链接格式不正确。")
            return
        }

        requestDownloadConfirmation(downloadURL)
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        handleDroppedURL(url)
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let string: String?
                    if let data = item as? Data {
                        string = String(data: data, encoding: .utf8)
                    } else {
                        string = item as? String
                    }
                    guard let string, let url = DownloadManager.normalizedURL(from: string) else { return }
                    DispatchQueue.main.async {
                        handleDroppedURL(url)
                    }
                }
            }
        }
        return accepted
    }

    private func handleDroppedURL(_ url: URL) {
        guard DownloadManager.isBitTorrentSource(url) || DownloadManager.isED2KSource(url) else {
            if let normalized = DownloadManager.normalizedURL(from: url.absoluteString) {
                requestDownloadConfirmation(normalized.absoluteString)
            }
            return
        }

        let engine: DownloadEngineChoice = DownloadManager.isED2KSource(url) ? .ed2k : .bittorrent
        requestDownloadConfirmation(BrowserDownloadRequest(
            url: url.absoluteString,
            fileName: DownloadManager.fileName(for: url),
            headers: [DownloadManager.engineHeaderKey: engine.rawValue],
            source: "drop"
        ))
    }

    private func checkExternalDownloadInbox() {
        for request in ExternalDownloadInbox.consumeRequests() {
            startExternalDownload(request)
        }
    }

    private func startExternalDownload(_ request: BrowserDownloadRequest) {
        if showDownloadConfirmation {
            requestDownloadConfirmation(request)
            return
        }

        let hintedEngine = request.headers[DownloadManager.engineHeaderKey].flatMap(DownloadEngineChoice.init(rawValue:)) ?? AppPreferences.defaultEngine
        guard let item = manager.addDownload(
            from: request.url,
            fileName: request.fileName,
            headers: request.headers,
            cookie: request.cookie,
            engine: hintedEngine,
            startImmediately: true
        ) else {
            showInDevelopment("这个链接暂时不能下载：\(request.url)")
            return
        }
        selectedDownloadID = item.id
        selectedCategory = .all
        showDetails(for: item)
    }

    private func checkScheduler() {
        guard schedulerEnabled else { return }

        let defaults = UserDefaults.standard
        let repeatsDaily = defaults.object(forKey: AppPreferences.schedulerRepeatsDailyKey) as? Bool ?? false
        let startAt = AppPreferences.schedulerStartAt
        let startFireID = schedulerFireID(kind: "start", date: startAt, repeatsDaily: repeatsDaily)
        if shouldFireSchedulerEvent(date: startAt, repeatsDaily: repeatsDaily), lastSchedulerStartFireID != startFireID {
            lastSchedulerStartFireID = startFireID
            manager.startQueue()
        }

        let stopEnabled = defaults.object(forKey: AppPreferences.schedulerStopEnabledKey) as? Bool ?? false
        guard stopEnabled else {
            if !repeatsDaily, Date() > startAt.addingTimeInterval(60), lastSchedulerStartFireID == startFireID {
                schedulerEnabled = false
            }
            return
        }

        let stopAt = AppPreferences.schedulerStopAt
        let stopFireID = schedulerFireID(kind: "stop", date: stopAt, repeatsDaily: repeatsDaily)
        if shouldFireSchedulerEvent(date: stopAt, repeatsDaily: repeatsDaily), lastSchedulerStopFireID != stopFireID {
            lastSchedulerStopFireID = stopFireID
            manager.stopQueue()
            if !repeatsDaily {
                schedulerEnabled = false
            }
        }
    }

    private func shouldFireSchedulerEvent(date: Date, repeatsDaily: Bool) -> Bool {
        let now = Date()
        if !repeatsDaily {
            return now >= date && now.timeIntervalSince(date) < 60
        }

        let calendar = Calendar.current
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let targetParts = calendar.dateComponents([.hour, .minute], from: date)
        return nowParts.hour == targetParts.hour && nowParts.minute == targetParts.minute
    }

    private func schedulerFireID(kind: String, date: Date, repeatsDaily: Bool) -> String {
        if repeatsDaily {
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            return "\(kind)-daily-\(day)-\(parts.hour ?? 0)-\(parts.minute ?? 0)"
        }
        return "\(kind)-once-\(Int(date.timeIntervalSinceReferenceDate))"
    }

    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func mergeSniffedResources(_ resources: [SniffedResource]) {
        var merged = Dictionary(uniqueKeysWithValues: sniffedResources.map { ($0.url, $0) })
        for resource in resources {
            guard !isNoisySniffedResource(resource) else { continue }
            merged[resource.url] = resource
        }
        sniffedResources = merged.values.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private func isNoisySniffedResource(_ resource: SniffedResource) -> Bool {
        let lowerURL = resource.url.lowercased()
        let lowerName = (resource.fileName ?? resource.title).lowercased()
        if lowerURL.contains("generate_204")
            || lowerURL.contains("/ptracking")
            || lowerURL.contains("/api/stats")
            || lowerURL.contains("/log_event")
            || lowerURL.contains("/player_204") {
            return true
        }
        if ["success.mp3", "open.mp3", "no_input.mp3", "failure.mp3"].contains(lowerName) {
            return true
        }
        if lowerURL.contains("googlevideo.com/videoplayback") {
            return resource.type.uppercased() != "YOUTUBE"
        }
        return false
    }

    private func runPluginExtractors(for request: PluginExtractorRequest) {
        Task {
            let resources = await PluginExtractorRunner.extract(pageURL: request.url, title: request.title)
            guard !resources.isEmpty else { return }
            await MainActor.run {
                mergeSniffedResources(resources)
                showingGrabber = true
            }
        }
    }
}

private final class LocalBrowserBridge: @unchecked Sendable {
    static let shared = LocalBrowserBridge()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "FastNativeDownloadManager.LocalBrowserBridge")
    private let port: NWEndpoint.Port = 51237

    private init() {}

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed = state {
                    self.listener = nil
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Fast Native Download Manager local browser bridge failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(from: connection, buffer: Data())
    }

    private func readRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { data, _, isComplete, error in
            guard error == nil else {
                self.respond(connection, status: "400 Bad Request", body: "Bad Request")
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if self.hasCompleteHTTPRequest(nextBuffer) || isComplete {
                guard let request = String(data: nextBuffer, encoding: .utf8) else {
                    self.respond(connection, status: "400 Bad Request", body: "Bad Request")
                    return
                }
                let result = self.handleHTTPRequest(request)
                self.respond(connection, status: result.status, body: result.body)
                return
            }

            self.readRequest(from: connection, buffer: nextBuffer)
        }
    }

    private func hasCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }

        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return false
        }

        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).dropFirst().first?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let bodyStart = headerRange.upperBound
        return data.count - bodyStart >= contentLength
    }

    private func handleHTTPRequest(_ request: String) -> (status: String, body: String) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            return ("400 Bad Request", "Bad Request")
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return ("400 Bad Request", "Bad Request")
        }

        if parts[0] == "OPTIONS" {
            return ("204 No Content", "")
        }

        guard parts[0] == "GET" || parts[0] == "POST",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
              components.path == "/download" || components.path == "/resources" || components.path == "/extract" else {
            return ("400 Bad Request", "Expected /download, /resources, or /extract")
        }

        if components.path == "/resources" {
            guard parts[0] == "POST",
                  let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first,
                  let resources = try? JSONDecoder().decode([SniffedResource].self, from: Data(body.utf8)) else {
                return ("400 Bad Request", "Expected resource JSON")
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sniffedResourcesDetected, object: resources)
            }
            return ("200 OK", "{\"ok\":true}")
        }

        if components.path == "/extract" {
            let extractorRequest: PluginExtractorRequest?
            if parts[0] == "POST",
               let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first,
               !body.isEmpty {
                extractorRequest = try? JSONDecoder().decode(PluginExtractorRequest.self, from: Data(body.utf8))
            } else if let rawURL = components.queryItems?.first(where: { $0.name == "url" })?.value {
                extractorRequest = PluginExtractorRequest(url: rawURL, title: nil)
            } else {
                extractorRequest = nil
            }

            guard let extractorRequest,
                  DownloadManager.normalizedURL(from: extractorRequest.url) != nil else {
                return ("400 Bad Request", "Expected extractor JSON")
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pluginExtractionRequested, object: extractorRequest)
            }
            return ("200 OK", "{\"ok\":true}")
        }

        let downloadRequest: BrowserDownloadRequest?
        if parts[0] == "POST", let body = request.components(separatedBy: "\r\n\r\n").dropFirst().first, !body.isEmpty {
            downloadRequest = try? JSONDecoder().decode(BrowserDownloadRequest.self, from: Data(body.utf8))
        } else if let rawURL = components.queryItems?.first(where: { $0.name == "url" })?.value {
            downloadRequest = BrowserDownloadRequest(url: rawURL)
        } else {
            downloadRequest = nil
        }

        guard let downloadRequest,
              DownloadManager.normalizedURL(from: downloadRequest.url) != nil else {
            return ("400 Bad Request", "Expected a valid download request")
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .externalRawDownloadRequested, object: downloadRequest)
            NSApp.activate()
        }
        return ("200 OK", "{\"ok\":true}")
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json; charset=utf-8\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, X-FNDM-Source\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private enum ExternalDownloadRequestParser {
    static func downloadURL(from incomingURL: URL) -> String? {
        guard incomingURL.scheme?.lowercased() == "fastndm",
              incomingURL.host?.lowercased() == "download",
              let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let rawURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
              DownloadManager.normalizedURL(from: rawURL) != nil else {
            return nil
        }

        return rawURL
    }
}

private enum ExternalDownloadInbox {
    private static var inboxURL: URL {
        URL(fileURLWithPath: "/tmp/fast-native-download-manager-incoming.jsonl")
    }

    static func consumeRequests() -> [BrowserDownloadRequest] {
        guard FileManager.default.fileExists(atPath: inboxURL.path),
              let content = try? String(contentsOf: inboxURL, encoding: .utf8) else {
            return []
        }

        try? FileManager.default.removeItem(at: inboxURL)

        return content
            .split(separator: "\n")
            .compactMap { line -> BrowserDownloadRequest? in
                guard let data = String(line).data(using: .utf8),
                      let request = try? JSONDecoder().decode(BrowserDownloadRequest.self, from: data),
                      DownloadManager.normalizedURL(from: request.url) != nil else {
                    return nil
                }

                return request
            }
    }
}

private func connectionSlices(for download: DownloadItem) -> [ConnectionSlice] {
    if !download.segments.isEmpty {
        return download.segments.map { segment in
            ConnectionSlice(
                part: segment.id + 1,
                range: "\(segment.start)-\(segment.end)",
                speed: segment.speed > 0 ? ByteCountFormatter.string(fromByteCount: segment.speed, countStyle: .file) + "/s" : "--",
                progress: segment.progress
            )
        }
    }

    let activeConnections = max(download.connections, 1)
    return (0..<min(max(activeConnections, 4), 8)).map { index in
        ConnectionSlice(
            part: index + 1,
            range: "Range \(index + 1)",
            speed: download.status == .downloading ? download.speed : "--",
            progress: max(0, min(1, download.progress - Double(index) * 0.06))
        )
    }
}

private final class DownloadDetailWindowController: NSWindowController, NSWindowDelegate {
    init(
        download: DownloadItem,
        onResume: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onSaveSettings: @escaping () -> Void
    ) {
        let rootView = NativeDownloadDetails(
            download: download,
            onResume: onResume,
            onPause: onPause,
            onCancel: onCancel,
            onSaveSettings: onSaveSettings
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = download.fileName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 580))
        window.minSize = NSSize(width: 660, height: 520)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct NativeToolbar: View {
    let onAddURL: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onStopAll: () -> Void
    let onDelete: () -> Void
    let onDeleteCompleted: () -> Void
    let onStartQueue: () -> Void
    let onStopQueue: () -> Void
    let onOptions: () -> Void
    let onScheduler: () -> Void
    let onGrabber: () -> Void
    let onTellFriend: () -> Void
    let onFeature: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            NativeToolbarButton(title: "Add URL", symbol: "plus", tint: .green, enabled: true, action: onAddURL)
            NativeToolbarButton(title: "Resume", symbol: "arrow.clockwise", tint: .blue, enabled: true, action: onResume)
            NativeToolbarButton(title: "Stop", symbol: "stop.fill", tint: .orange, enabled: true, action: onStop)
            NativeToolbarButton(title: "Stop All", symbol: "xmark", tint: .red, enabled: true, action: onStopAll)
            NativeToolbarButton(title: "Delete", symbol: "trash", tint: .red, enabled: true, action: onDelete)
            NativeToolbarButton(title: "Delete Done", symbol: "shippingbox", tint: .indigo, enabled: true, action: onDeleteCompleted)
            NativeToolbarButton(title: "Options", symbol: "slider.horizontal.3", tint: .orange, enabled: true, action: onOptions)
            NativeToolbarButton(title: "Scheduler", symbol: "alarm", tint: .orange, enabled: true, action: onScheduler)
            NativeToolbarButton(title: "Start Queue", symbol: "folder.badge.plus", tint: .green, enabled: true, action: onStartQueue)
            NativeToolbarButton(title: "Stop Queue", symbol: "folder.badge.minus", tint: .red, enabled: true, action: onStopQueue)
            NativeToolbarButton(title: "Grabber", symbol: "scope", tint: .blue, enabled: true, action: onGrabber)
            NativeToolbarButton(title: "Tell a Friend", symbol: "person.wave.2", tint: .cyan, enabled: true, action: onTellFriend)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 86)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }
}

private struct NativeToolbarButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolVariant(.fill)
                    .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.45))
                    .frame(width: 42, height: 36)
                    .background(enabled ? tint.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: 78)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(title)
    }
}

private struct OptionsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: DownloadManager
    @StateObject private var pluginManager = PluginManager()
    @Binding var clipboardMonitoringEnabled: Bool
    @Binding var browserBridgeEnabled: Bool
    @Binding var showDownloadConfirmation: Bool
    @AppStorage(AppPreferences.saveDirectoryKey) private var saveDirectoryPath = AppPreferences.saveDirectory.path
    @AppStorage(AppPreferences.defaultEngineKey) private var defaultEngineRawValue = DownloadEngineChoice.automatic.rawValue
    @AppStorage(AppPreferences.cookiesFilePathKey) private var cookiesFilePath = ""
    @AppStorage(AppPreferences.cookiesFromBrowserKey) private var cookiesFromBrowserRawValue = BrowserCookieSource.none.rawValue
    @AppStorage(AppPreferences.defaultProxyKey) private var defaultProxy = ""
    @AppStorage(AppPreferences.timeLimitEnabledKey) private var timeLimitEnabled = false
    @AppStorage(AppPreferences.timeLimitStartMinutesKey) private var timeLimitStartMinutes = 9 * 60
    @AppStorage(AppPreferences.timeLimitEndMinutesKey) private var timeLimitEndMinutes = 18 * 60
    @AppStorage(AppPreferences.pluginExecutionTimeoutKey) private var pluginExecutionTimeoutSeconds = 1800
    @AppStorage(AppPreferences.confirmPluginTrustKey) private var confirmPluginTrust = true
    @State private var timeLimitBytesPerSecond: Int64 = UserDefaults.standard.object(forKey: AppPreferences.timeLimitBytesPerSecondKey) as? Int64 ?? 1024 * 1024
    @State private var showingPluginMarketplace = false
    @State private var showingPluginAuditLog = false
    @State private var pluginSettingsItem: InstalledPlugin?
    @State private var showingCookieProfiles = false
    @State private var showingProxyProfiles = false

    private var saveDirectory: URL {
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }

    private var defaultEngine: Binding<DownloadEngineChoice> {
        Binding(
            get: { DownloadEngineChoice(rawValue: defaultEngineRawValue) ?? .automatic },
            set: { defaultEngineRawValue = $0.rawValue }
        )
    }

    private var timeLimitSpeedBinding: Binding<Int64> {
        Binding(
            get: { timeLimitBytesPerSecond },
            set: { newValue in
                timeLimitBytesPerSecond = newValue
                UserDefaults.standard.set(newValue, forKey: AppPreferences.timeLimitBytesPerSecondKey)
            }
        )
    }

    private var cookiesFromBrowser: Binding<BrowserCookieSource> {
        Binding(
            get: { BrowserCookieSource(rawValue: cookiesFromBrowserRawValue) ?? .none },
            set: { cookiesFromBrowserRawValue = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options")
                        .font(.title3.weight(.semibold))
                    Text("Download behavior, browser capture, and queue settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            TabView {
                downloadsTab
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                browserTab
                    .tabItem {
                        Label("Browser", systemImage: "globe")
                    }
                queueTab
                    .tabItem {
                        Label("Queue", systemImage: "list.bullet.rectangle")
                    }
                pluginsTab
                    .tabItem {
                        Label("Plugins", systemImage: "puzzlepiece.extension")
                    }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Reset Defaults") {
                    resetDefaults()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 520)
        .onChange(of: browserBridgeEnabled) { _, enabled in
            if enabled {
                LocalBrowserBridge.shared.start()
            } else {
                LocalBrowserBridge.shared.stop()
            }
        }
        .sheet(isPresented: $showingPluginMarketplace) {
            PluginMarketplacePanel(pluginManager: pluginManager)
        }
        .sheet(isPresented: $showingPluginAuditLog) {
            PluginAuditLogPanel()
        }
        .sheet(item: $pluginSettingsItem) { plugin in
            PluginSettingsPanel(plugin: plugin)
        }
        .sheet(isPresented: $showingCookieProfiles) {
            CookieProfilesPanel(
                selectedBrowserRawValue: $cookiesFromBrowserRawValue,
                selectedCookiesFilePath: $cookiesFilePath
            )
        }
        .sheet(isPresented: $showingProxyProfiles) {
            ProxyProfilesPanel(defaultProxy: $defaultProxy)
        }
    }

    private var downloadsTab: some View {
        Form {
            Section("Save Location") {
                HStack(spacing: 8) {
                    Text(saveDirectoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    Button("Browse...") {
                        chooseSaveDirectory()
                    }
                    Button("Open") {
                        NSWorkspace.shared.open(saveDirectory)
                    }
                }
                Text("New downloads and the task database will use this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Engine") {
                Picker("Default engine", selection: defaultEngine) {
                    ForEach(DownloadEngineChoice.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                Text("Browser-detected platform links can still override this with yt-dlp or ffmpeg.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Confirmation") {
                Toggle("Show download confirmation before starting", isOn: $showDownloadConfirmation)
                Text("When disabled, browser and grabber downloads start immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var browserTab: some View {
        Form {
            Section("Capture") {
                Toggle("Enable browser integration bridge", isOn: $browserBridgeEnabled)
                Toggle("Monitor clipboard for downloadable links", isOn: $clipboardMonitoringEnabled)
                Text("The Chrome and Firefox extensions send links to the local bridge on 127.0.0.1:51237.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Extension") {
                HStack {
                    Label(browserBridgeEnabled ? "Bridge is enabled" : "Bridge is disabled", systemImage: browserBridgeEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(browserBridgeEnabled ? .green : .secondary)
                    Spacer()
                    Button("Open Chrome Extensions") {
                        NSWorkspace.shared.open(URL(string: "chrome://extensions")!)
                    }
                    Button("Open Firefox Add-ons") {
                        NSWorkspace.shared.open(URL(string: "about:debugging#/runtime/this-firefox")!)
                    }
                }
            }

            Section("Cookies") {
                Picker("Read cookies from browser", selection: cookiesFromBrowser) {
                    ForEach(BrowserCookieSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 8) {
                    Text(cookiesFilePath.isEmpty ? "No cookies.txt selected" : cookiesFilePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    Button("Import cookies.txt...") {
                        chooseCookiesFile()
                    }
                    Button("Clear") {
                        cookiesFilePath = ""
                    }
                    .disabled(cookiesFilePath.isEmpty)
                }
                Button("Manage Cookie Profiles...") {
                    showingCookieProfiles = true
                }
                Text("yt-dlp will prefer the selected browser cookies and also use cookies.txt when provided.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Proxy") {
                HStack(spacing: 8) {
                    Text(defaultProxy.isEmpty ? "No default proxy" : defaultProxy)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    Button("Use System") {
                        defaultProxy = SystemProxyDetector.currentProxy() ?? ""
                    }
                    Button("Manage Proxies...") {
                        showingProxyProfiles = true
                    }
                    Button("Clear") {
                        defaultProxy = ""
                    }
                    .disabled(defaultProxy.isEmpty)
                }
                Text("New downloads can inherit this default proxy. Per-task proxy still overrides it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var queueTab: some View {
        Form {
            Section("Queue") {
                Stepper("Maximum concurrent downloads: \(manager.maximumConcurrentDownloads)", value: $manager.maximumConcurrentDownloads, in: 1...16)
                Text(manager.queueStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speed Limits") {
                SpeedLimitStepper(
                    title: "Global speed limit",
                    value: $manager.globalSpeedLimitBytesPerSecond
                )
                SpeedLimitStepper(
                    title: "Queue speed limit",
                    value: $manager.queueSpeedLimitBytesPerSecond
                )
                Text("0 means unlimited. Queue limit applies to tasks started through Start Queue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Time Window Speed Limit") {
                Toggle("Enable scheduled speed limit", isOn: $timeLimitEnabled)
                HStack {
                    TimeMinutesStepper(title: "From", minutes: $timeLimitStartMinutes)
                    TimeMinutesStepper(title: "To", minutes: $timeLimitEndMinutes)
                }
                SpeedLimitStepper(
                    title: "Window speed limit",
                    value: timeLimitSpeedBinding
                )
                Text("Applies every day. Windows crossing midnight are supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var pluginsTab: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin System")
                        .font(.headline)
                    Text("Install local plugin folders with a plugin.json manifest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Install...") {
                    pluginManager.installFromPicker()
                }
                Button("Marketplace") {
                    showingPluginMarketplace = true
                }
                Button("Template") {
                    pluginManager.createTemplatePlugin()
                }
                Button("Audit Log") {
                    showingPluginAuditLog = true
                }
                Button("Open Folder") {
                    pluginManager.openPluginsFolder()
                }
            }

            HStack(spacing: 14) {
                Stepper("Plugin timeout: \(pluginExecutionTimeoutSeconds)s", value: $pluginExecutionTimeoutSeconds, in: 30...7200, step: 30)
                Toggle("Ask before trust", isOn: $confirmPluginTrust)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if pluginManager.plugins.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No plugins installed")
                        .font(.headline)
                    Text("Create a template plugin or install a folder containing plugin.json.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pluginManager.plugins) { plugin in
                            PluginRow(
                                plugin: plugin,
                                onToggle: { pluginManager.setEnabled($0, for: plugin) },
                                onTrust: { pluginManager.setTrusted($0, for: plugin) },
                                onSettings: { pluginSettingsItem = plugin },
                                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([plugin.folderURL]) },
                                onRemove: { pluginManager.remove(plugin) }
                            )
                        }
                    }
                    .padding(2)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor))
                }
            }

            if let status = pluginManager.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
            AppPreferences.saveDirectory = url
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func chooseCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, .data]
        panel.prompt = "Import"
        panel.message = "Choose a Netscape cookies.txt file exported from your browser."
        if panel.runModal() == .OK, let url = panel.url {
            cookiesFilePath = url.path
        }
    }

    private func resetDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppPreferences.saveDirectoryKey)
        defaults.set(true, forKey: AppPreferences.clipboardMonitoringKey)
        defaults.set(true, forKey: AppPreferences.browserBridgeKey)
        defaults.set(true, forKey: AppPreferences.showDownloadConfirmationKey)
        defaults.set(DownloadEngineChoice.automatic.rawValue, forKey: AppPreferences.defaultEngineKey)
        defaults.set(2, forKey: AppPreferences.maximumConcurrentDownloadsKey)
        defaults.set(0, forKey: "Options.globalSpeedLimitBytesPerSecond")
        defaults.set(0, forKey: "Options.queueSpeedLimitBytesPerSecond")
        defaults.removeObject(forKey: AppPreferences.cookiesFilePathKey)
        defaults.removeObject(forKey: AppPreferences.cookieProfilesKey)
        defaults.removeObject(forKey: AppPreferences.proxyProfilesKey)
        defaults.removeObject(forKey: AppPreferences.defaultProxyKey)
        defaults.set(BrowserCookieSource.none.rawValue, forKey: AppPreferences.cookiesFromBrowserKey)
        defaults.set(false, forKey: AppPreferences.timeLimitEnabledKey)
        defaults.set(9 * 60, forKey: AppPreferences.timeLimitStartMinutesKey)
        defaults.set(18 * 60, forKey: AppPreferences.timeLimitEndMinutesKey)
        defaults.set(Int64(1024 * 1024), forKey: AppPreferences.timeLimitBytesPerSecondKey)
        defaults.removeObject(forKey: AppPreferences.disabledPluginsKey)
        defaults.set(1800, forKey: AppPreferences.pluginExecutionTimeoutKey)
        defaults.set(true, forKey: AppPreferences.confirmPluginTrustKey)
        defaults.removeObject(forKey: AppPreferences.marketplaceCatalogURLKey)
        saveDirectoryPath = AppPreferences.saveDirectory.path
        clipboardMonitoringEnabled = true
        browserBridgeEnabled = true
        showDownloadConfirmation = true
        defaultEngineRawValue = DownloadEngineChoice.automatic.rawValue
        manager.maximumConcurrentDownloads = 2
        manager.globalSpeedLimitBytesPerSecond = 0
        manager.queueSpeedLimitBytesPerSecond = 0
        cookiesFilePath = ""
        cookiesFromBrowserRawValue = BrowserCookieSource.none.rawValue
        defaultProxy = ""
        timeLimitEnabled = false
        timeLimitStartMinutes = 9 * 60
        timeLimitEndMinutes = 18 * 60
        timeLimitBytesPerSecond = 1024 * 1024
        pluginExecutionTimeoutSeconds = 1800
        confirmPluginTrust = true
        pluginManager.reload()
        LocalBrowserBridge.shared.start()
    }
}

private struct TimeMinutesStepper: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        Stepper("\(title): \(formatted)", value: Binding(
            get: { minutes },
            set: { minutes = max(0, min(23 * 60 + 59, $0)) }
        ), in: 0...(23 * 60 + 59), step: 15)
    }

    private var formatted: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private enum SystemProxyDetector {
    static func currentProxy() -> String? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        if let enabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int,
           enabled == 1,
           let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String {
            let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int ?? 80
            return "http://\(host):\(port)"
        }
        if let enabled = settings[kCFNetworkProxiesHTTPSEnable as String] as? Int,
           enabled == 1,
           let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String {
            let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int ?? 443
            return "https://\(host):\(port)"
        }
        if let enabled = settings[kCFNetworkProxiesSOCKSEnable as String] as? Int,
           enabled == 1,
           let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String {
            let port = settings[kCFNetworkProxiesSOCKSPort as String] as? Int ?? 1080
            return "socks5://\(host):\(port)"
        }
        return nil
    }
}

private struct CookieProfilesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBrowserRawValue: String
    @Binding var selectedCookiesFilePath: String
    @State private var profiles: [CookieProfile] = CodableDefaults.load([CookieProfile].self, key: AppPreferences.cookieProfilesKey, fallback: [])
    @State private var name = ""
    @State private var browser = BrowserCookieSource.chrome
    @State private var cookiesFilePath = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cookie Profiles")
                        .font(.title3.weight(.semibold))
                    Text("Save browser/cookies.txt combinations for yt-dlp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            Form {
                Section("New Profile") {
                    TextField("Name", text: $name)
                    Picker("Browser", selection: $browser) {
                        ForEach(BrowserCookieSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    HStack {
                        Text(cookiesFilePath.isEmpty ? "No cookies.txt selected" : cookiesFilePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") { chooseCookiesFile() }
                    }
                    Button("Add Profile") {
                        addProfile()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Saved Profiles") {
                    if profiles.isEmpty {
                        Text("No cookie profiles yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text("\(profile.browser) \(profile.cookiesFilePath)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button("Use") {
                                    selectedBrowserRawValue = profile.browser
                                    selectedCookiesFilePath = profile.cookiesFilePath
                                }
                                Button(role: .destructive) {
                                    profiles.removeAll { $0.id == profile.id }
                                    persist()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(16)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 620, height: 560)
    }

    private func addProfile() {
        profiles.append(CookieProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            browser: browser.rawValue,
            cookiesFilePath: cookiesFilePath
        ))
        persist()
        name = ""
        browser = .chrome
        cookiesFilePath = ""
    }

    private func persist() {
        CodableDefaults.save(profiles, key: AppPreferences.cookieProfilesKey)
    }

    private func chooseCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, .data]
        if panel.runModal() == .OK, let url = panel.url {
            cookiesFilePath = url.path
        }
    }
}

private struct ProxyProfilesPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var defaultProxy: String
    @State private var profiles: [ProxyProfile] = CodableDefaults.load([ProxyProfile].self, key: AppPreferences.proxyProfilesKey, fallback: [])
    @State private var name = ""
    @State private var proxyURL = ""
    @State private var testStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proxy Profiles")
                        .font(.title3.weight(.semibold))
                    Text("HTTP, HTTPS, and SOCKS5 proxy presets for downloads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import System Proxy") {
                    if let proxy = SystemProxyDetector.currentProxy() {
                        proxyURL = proxy
                        if name.isEmpty { name = "System Proxy" }
                    } else {
                        testStatus = "No enabled system proxy found."
                    }
                }
            }
            .padding(18)
            Divider()

            Form {
                Section("New Profile") {
                    TextField("Name", text: $name)
                    TextField("Proxy URL, e.g. http://127.0.0.1:7890 or socks5://127.0.0.1:1080", text: $proxyURL)
                    HStack {
                        Button("Test") { testProxy(proxyURL) }
                            .disabled(proxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Add Profile") { addProfile() }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || proxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text(testStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved Proxies") {
                    if profiles.isEmpty {
                        Text("No proxy profiles yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text(profile.proxyURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use Default") {
                                    defaultProxy = profile.proxyURL
                                }
                                Button("Test") {
                                    testProxy(profile.proxyURL)
                                }
                                Button(role: .destructive) {
                                    profiles.removeAll { $0.id == profile.id }
                                    persist()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(16)

            Divider()
            HStack {
                Text(defaultProxy.isEmpty ? "Default proxy: none" : "Default proxy: \(defaultProxy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 700, height: 580)
    }

    private func addProfile() {
        profiles.append(ProxyProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyURL: proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        persist()
        name = ""
        proxyURL = ""
    }

    private func persist() {
        CodableDefaults.save(profiles, key: AppPreferences.proxyProfilesKey)
    }

    private func testProxy(_ value: String) {
        guard URL(string: value) != nil else {
            testStatus = "Invalid proxy URL."
            return
        }
        testStatus = "Proxy URL looks valid."
    }
}

private struct FlowLine: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                chipViews
            }
            VStack(alignment: .leading, spacing: 5) {
                chipViews
            }
        }
    }

    @ViewBuilder private var chipViews: some View {
        ForEach(items.prefix(8), id: \.self) { item in
            Text(item)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}

private struct PluginMarketplacePanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var pluginManager: PluginManager
    @AppStorage(AppPreferences.marketplaceCatalogURLKey) private var catalogURLString = ""
    @State private var remotePlugins: [MarketplacePlugin] = []
    @State private var catalogStatus = ""

    private var allPlugins: [MarketplacePlugin] {
        MarketplacePlugin.builtIns + remotePlugins
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin Marketplace")
                        .font(.title3.weight(.semibold))
                    Text("Built-in plugins are trusted by default. External plugins still require manual trust.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Install All") {
                    pluginManager.installMarketplacePlugins()
                }
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Remote catalog JSON URL", text: $catalogURLString)
                        .textFieldStyle(.roundedBorder)
                    Button("Refresh Remote") {
                        refreshRemoteCatalog()
                    }
                }
                Text(catalogStatus.isEmpty ? "Catalog format: JSON array of marketplace plugins with id, name, description, kind, permissions, sourceURL." : catalogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(allPlugins) { plugin in
                        MarketplacePluginRow(
                            plugin: plugin,
                            installed: pluginManager.plugins.contains { $0.id == plugin.id },
                            onInstall: { pluginManager.installMarketplacePlugin(plugin) }
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                if let status = pluginManager.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 640, height: 520)
    }

    private func refreshRemoteCatalog() {
        guard let url = URL(string: catalogURLString), !catalogURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            catalogStatus = "Enter a valid catalog URL."
            return
        }
        catalogStatus = "Loading remote catalog..."
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode([MarketplacePlugin].self, from: data)
                await MainActor.run {
                    remotePlugins = decoded
                    catalogStatus = "Loaded \(decoded.count) remote plugin(s)."
                }
            } catch {
                await MainActor.run {
                    catalogStatus = "Remote catalog failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct MarketplacePluginRow: View {
    let plugin: MarketplacePlugin
    let installed: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(installed ? Color.green : Color.accentColor)
                .frame(width: 36, height: 36)
                .background((installed ? Color.green : Color.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.callout.weight(.semibold))
                    Text(plugin.kind)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .foregroundStyle(.secondary)
                    if installed {
                        Text("installed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    if plugin.sourceURL != nil {
                        Text("remote")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text(plugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLine(items: plugin.permissions.map { "perm:\($0)" })
            }

            Spacer()

            Button(installed ? "Restore" : "Install") {
                onInstall()
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor))
        }
    }

    private var iconName: String {
        switch plugin.kind {
        case "engine": "gearshape.2.fill"
        case "extractor": "scope"
        default: "puzzlepiece.extension"
        }
    }
}

private struct PluginAuditLogPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin Audit Log")
                        .font(.title3.weight(.semibold))
                    Text(PluginAuditLog.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Reload") {
                    load()
                }
                Button("Open File") {
                    NSWorkspace.shared.open(PluginAuditLog.url)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(logText.isEmpty ? "No plugin audit entries yet." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button("Clear") {
                    try? "".write(to: PluginAuditLog.url, atomically: true, encoding: .utf8)
                    load()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 760, height: 520)
        .onAppear(perform: load)
    }

    private func load() {
        logText = (try? String(contentsOf: PluginAuditLog.url, encoding: .utf8)) ?? ""
    }
}

private struct PluginSettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    let plugin: InstalledPlugin

    private var manifestText: String {
        guard let data = try? JSONEncoder.prettyPrinted.encode(plugin.manifest),
              let text = String(data: data, encoding: .utf8) else {
            return "Unable to render plugin manifest."
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.manifest.name)
                        .font(.title3.weight(.semibold))
                    Text(plugin.manifest.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let settingsURL = resolvedSettingsURL {
                    Button("Open Plugin UI") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([plugin.folderURL])
                }
            }
            .padding(20)

            Divider()

            TabView {
                Form {
                    let warnings = PluginSecurityPolicy.warnings(for: plugin.manifest)
                    Section("Runtime") {
                        LabeledContent("Enabled", value: plugin.enabled ? "Yes" : "No")
                        LabeledContent("Trusted", value: plugin.trusted ? "Yes" : "No")
                        LabeledContent("Kind", value: plugin.manifest.kind ?? "--")
                        LabeledContent("Entry", value: plugin.manifest.entry ?? "--")
                        LabeledContent("Extractor", value: plugin.manifest.extractorScript ?? "--")
                        LabeledContent("Settings UI", value: resolvedSettingsURL?.lastPathComponent ?? plugin.manifest.settingsURL ?? "--")
                    }
                    Section("Permissions") {
                        FlowLine(items: plugin.manifest.permissions ?? [])
                    }
                    if !warnings.isEmpty {
                        Section("Security Warnings") {
                            ForEach(warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Section("Matching") {
                        LabeledContent("Protocols", value: (plugin.manifest.protocols ?? []).joined(separator: ", ").nilIfEmpty ?? "--")
                        LabeledContent("Extensions", value: (plugin.manifest.fileExtensions ?? []).joined(separator: ", ").nilIfEmpty ?? "--")
                        Text((plugin.manifest.urlPatterns ?? []).joined(separator: "\n").nilIfEmpty ?? "--")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("Summary", systemImage: "info.circle") }

                ScrollView {
                    Text(manifestText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .tabItem { Label("Manifest", systemImage: "curlybraces") }

                ScrollView {
                    Text(plugin.manifest.engineCommand?.nilIfEmpty ?? "No engine command declared.")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .tabItem { Label("Command", systemImage: "terminal") }
            }
            .padding(20)

            Divider()

            HStack {
                Text("External plugin UI panels can be added later through a plugin-declared settings view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 680, height: 560)
    }

    private var resolvedSettingsURL: URL? {
        if let html = plugin.manifest.settingsHTML?.nilIfEmpty {
            return plugin.folderURL.appendingPathComponent(html)
        }
        guard let value = plugin.manifest.settingsURL?.nilIfEmpty else { return nil }
        if let webURL = URL(string: value), webURL.scheme?.hasPrefix("http") == true {
            return webURL
        }
        return plugin.folderURL.appendingPathComponent(value)
    }
}

private struct PluginRow: View {
    let plugin: InstalledPlugin
    let onToggle: (Bool) -> Void
    let onTrust: (Bool) -> Void
    let onSettings: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pluginIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(plugin.enabled ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
                .background((plugin.enabled ? Color.accentColor : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.manifest.name)
                        .font(.callout.weight(.semibold))
                    Text(plugin.manifest.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let kind = plugin.manifest.kind, !kind.isEmpty {
                        Text(kind)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    }
                    Text(plugin.trusted ? "trusted" : "untrusted")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((plugin.trusted ? Color.green : Color.orange).opacity(0.14), in: Capsule())
                        .foregroundStyle(plugin.trusted ? .green : .orange)
                }

                if let description = plugin.manifest.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Text(plugin.manifest.id)
                    if let author = plugin.manifest.author, !author.isEmpty {
                        Text("by \(author)")
                    }
                    if let protocols = plugin.manifest.protocols, !protocols.isEmpty {
                        Text(protocols.joined(separator: ", "))
                    }
                    if let extensions = plugin.manifest.fileExtensions, !extensions.isEmpty {
                        Text(extensions.map { ".\($0)" }.joined(separator: " "))
                    }
                    if let engineCommand = plugin.manifest.engineCommand, !engineCommand.isEmpty {
                        Text(engineCommand)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if let permissions = plugin.manifest.permissions, !permissions.isEmpty {
                    FlowLine(items: permissions.map { "perm:\($0)" } + (plugin.manifest.urlPatterns ?? []).prefix(2).map { "match:\($0)" })
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.trusted },
                set: { newValue in onTrust(newValue) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(plugin.trusted ? "Trusted plugin" : "Trust plugin before enabling command execution")

            Toggle("", isOn: Binding(
                get: { plugin.enabled },
                set: { newValue in onToggle(newValue) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Menu {
                Button("Settings", action: onSettings)
                Button("Reveal in Finder", action: onReveal)
                if let homepage = plugin.manifest.homepage, let url = URL(string: homepage) {
                    Button("Open Homepage") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pluginIcon: String {
        switch plugin.manifest.kind?.lowercased() {
        case "extractor": "scope"
        case "action": "bolt.fill"
        case "engine": "gearshape.2.fill"
        case "sniffer": "antenna.radiowaves.left.and.right"
        default: "puzzlepiece.extension"
        }
    }
}

private struct SpeedLimitStepper: View {
    let title: String
    @Binding var value: Int64

    private var kilobytes: Binding<Int> {
        Binding(
            get: { Int(value / 1024) },
            set: { value = Int64(max(0, $0)) * 1024 }
        )
    }

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { value > 0 },
                set: { enabled in value = enabled ? max(value, 1024 * 1024) : 0 }
            ))
            Spacer()
            Stepper(value > 0 ? "\(kilobytes.wrappedValue) KB/s" : "Unlimited", value: kilobytes, in: 0...1_048_576, step: 128)
                .disabled(value == 0)
                .frame(width: 180)
        }
    }
}

private struct SchedulerPanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: DownloadManager
    @AppStorage(AppPreferences.schedulerEnabledKey) private var schedulerEnabled = false
    @AppStorage(AppPreferences.schedulerStartAtKey) private var startAtRaw = AppPreferences.schedulerStartAt.timeIntervalSinceReferenceDate
    @AppStorage(AppPreferences.schedulerStopEnabledKey) private var stopEnabled = false
    @AppStorage(AppPreferences.schedulerStopAtKey) private var stopAtRaw = AppPreferences.schedulerStopAt.timeIntervalSinceReferenceDate
    @AppStorage(AppPreferences.schedulerRepeatsDailyKey) private var repeatsDaily = false

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: startAtRaw) },
            set: { startAtRaw = $0.timeIntervalSinceReferenceDate }
        )
    }

    private var stopDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: stopAtRaw) },
            set: { stopAtRaw = $0.timeIntervalSinceReferenceDate }
        )
    }

    private var scheduledSummary: String {
        guard schedulerEnabled else { return "Scheduler is off." }
        let startText = startDate.wrappedValue.formatted(date: repeatsDaily ? .omitted : .abbreviated, time: .shortened)
        if stopEnabled {
            let stopText = stopDate.wrappedValue.formatted(date: repeatsDaily ? .omitted : .abbreviated, time: .shortened)
            return repeatsDaily ? "Every day: start at \(startText), stop at \(stopText)." : "Start at \(startText), stop at \(stopText)."
        }
        return repeatsDaily ? "Every day: start queue at \(startText)." : "Start queue at \(startText)."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduler")
                        .font(.title3.weight(.semibold))
                    Text("Start and stop the download queue automatically")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section("Schedule") {
                    Toggle("Enable scheduler", isOn: $schedulerEnabled)
                    Toggle("Repeat every day", isOn: $repeatsDaily)

                    if repeatsDaily {
                        DatePicker("Start queue at", selection: startDate, displayedComponents: [.hourAndMinute])
                        Toggle("Stop queue automatically", isOn: $stopEnabled)
                        if stopEnabled {
                            DatePicker("Stop queue at", selection: stopDate, displayedComponents: [.hourAndMinute])
                        }
                    } else {
                        DatePicker("Start queue at", selection: startDate, displayedComponents: [.date, .hourAndMinute])
                        Toggle("Stop queue automatically", isOn: $stopEnabled)
                        if stopEnabled {
                            DatePicker("Stop queue at", selection: stopDate, displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }

                Section("Queue") {
                    Stepper("Maximum concurrent downloads: \(manager.maximumConcurrentDownloads)", value: $manager.maximumConcurrentDownloads, in: 1...16)
                    Text(manager.queueStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Status") {
                    Label(scheduledSummary, systemImage: schedulerEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(schedulerEnabled ? .green : .secondary)
                }
            }
            .formStyle(.grouped)
            .padding(20)

            Divider()

            HStack {
                Button("Start Queue Now") {
                    manager.startQueue()
                }
                Button("Stop Queue") {
                    manager.stopQueue()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
    }
}

private struct TellFriendPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private let appName = "Fast Native Download Manager"
    private let shareURL = URL(string: "https://github.com/itworksig/Fast-Native-Download-Manager")!

    private var shareText: String {
        """
        I am using Fast Native Download Manager, a native macOS download manager with browser capture, queue scheduling, segmented downloads, and yt-dlp/ffmpeg support.

        \(shareURL.absoluteString)
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 52, height: 52)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Tell a Friend")
                        .font(.title3.weight(.semibold))
                    Text("Share \(appName) with someone who downloads a lot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Message")
                    .font(.headline)

                Text(shareText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor))
                    }

                HStack(spacing: 10) {
                    Button {
                        copyShareText()
                    } label: {
                        Label(copied ? "Copied" : "Copy Message", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    Button {
                        composeEmail()
                    } label: {
                        Label("Email", systemImage: "envelope")
                    }

                    Button {
                        openSystemShare()
                    } label: {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }

                    Spacer()
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 390)
    }

    private func copyShareText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareText, forType: .string)
        copied = true
    }

    private func composeEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Try \(appName)"),
            URLQueryItem(name: "body", value: shareText)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSystemShare() {
        let picker = NSSharingServicePicker(items: [shareText, shareURL])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
}

private struct AboutPanel: View {
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal], 18)

            Spacer(minLength: 8)

            AppLogoView(size: 92)

            Text("Fast Native Download Manager")
                .font(.title2.weight(.bold))
                .padding(.top, 18)

            Text(versionText)
                .font(.title3)
                .padding(.top, 8)

            Link("github.com/itworksig/Fast-Native-Download-Manager", destination: URL(string: "https://github.com/itworksig/Fast-Native-Download-Manager")!)
                .font(.callout)
                .padding(.top, 14)

            Spacer(minLength: 28)
        }
        .frame(width: 570, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AppLogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = AppLogoLoader.image() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(.linearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: size * 0.48, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

private enum AppLogoLoader {
    static func image() -> NSImage? {
        if let url = Bundle.main.url(forResource: "logo-1024", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "FastNativeDownloadManager", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "FastNativeDownloadManager")
    }
}

private struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: DownloadConfirmationRequest
    @ObservedObject var manager: DownloadManager
    let onAdd: (DownloadConfirmationResult) -> Void

    @State private var url: String
    @State private var fileName = "download"
    @State private var size = "--"
    @State private var category: Category = .all
    @State private var engine: DownloadEngineChoice = .automatic
    @State private var selectedPluginID = ""
    @State private var pluginOptions: [PluginPickerOption] = []
    @State private var saveDirectory = DownloadManager.downloadDirectory()
    @State private var startImmediately = true
    @State private var isChecking = false
    @State private var metadataMessage: String?
    @State private var sitePresetMessage: String?

    init(request: DownloadConfirmationRequest, manager: DownloadManager, onAdd: @escaping (DownloadConfirmationResult) -> Void) {
        self.request = request
        self.manager = manager
        self.onAdd = onAdd
        _url = State(initialValue: request.url)
        let suggestedFileName = request.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        _fileName = State(initialValue: suggestedFileName?.isEmpty == false ? suggestedFileName! : "download")
        if let fileName = suggestedFileName, !fileName.isEmpty {
            _category = State(initialValue: DownloadManager.category(for: fileName))
        }
        if let engineHint = request.headers[DownloadManager.engineHeaderKey],
           let hintedEngine = DownloadEngineChoice(rawValue: engineHint) {
            _engine = State(initialValue: hintedEngine)
        } else {
            _engine = State(initialValue: AppPreferences.defaultEngine)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                Text("Download File Info")
                    .font(.title3.weight(.semibold))
                Spacer()
                if isChecking {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("URL")
                    TextField("https://example.com/file.zip", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 520)
                }
                GridRow {
                    fieldLabel("File name")
                    TextField("File name", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 520)
                }
                GridRow {
                    fieldLabel("Size")
                    Text(size)
                        .foregroundStyle(size == "Unknown" ? .secondary : .primary)
                }
                GridRow {
                    fieldLabel("Category")
                    Picker("", selection: $category) {
                        ForEach(downloadableCategories) { category in
                            Label(category.rawValue, systemImage: category.symbol)
                                .tag(category)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    fieldLabel("Engine")
                    Picker("", selection: $engine) {
                        ForEach(DownloadEngineChoice.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }
                GridRow {
                    fieldLabel("Plugin")
                    Picker("", selection: $selectedPluginID) {
                        Text("Auto by URL").tag("")
                        Divider()
                        ForEach(pluginOptions) { plugin in
                            Text("\(plugin.name) · \(plugin.kind)").tag(plugin.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                    Text(selectedPluginID.isEmpty ? "Strict URL match" : "Manual override")
                        .font(.caption)
                        .foregroundStyle(selectedPluginID.isEmpty ? Color.secondary : Color.orange)
                }
                GridRow {
                    fieldLabel("Save to")
                    HStack(spacing: 8) {
                        Text(saveDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 408, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        Button("Browse...") {
                            chooseSaveDirectory()
                        }
                    }
                }
            }

            if let metadataMessage {
                Text(metadataMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let sitePresetMessage {
                Text(sitePresetMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let cookie = request.cookie, !cookie.isEmpty {
                Text("Browser cookies captured: \(cookie.count) chars. They will be passed to the selected engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("HTTP/HTTPS links are supported. The file can start now or wait in the queue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $startImmediately) {
                Text("Start download now").tag(true)
                Text("Add to queue").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(startImmediately ? "Start Download" : "Add to Queue") {
                    var headers = request.headers
                    if selectedPluginID.isEmpty {
                        headers.removeValue(forKey: DownloadManager.pluginIDHeaderKey)
                    } else {
                        headers[DownloadManager.pluginIDHeaderKey] = selectedPluginID
                    }
                    onAdd(DownloadConfirmationResult(
                        url: url,
                        fileName: fileName,
                        category: category,
                        saveDirectory: saveDirectory,
                        headers: headers,
                        cookie: request.cookie,
                        engine: engine,
                        startImmediately: startImmediately
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirm)
            }
        }
        .padding(22)
        .frame(width: 680)
        .onAppear {
            pluginOptions = loadPluginOptions()
            if !request.url.isEmpty {
                Task { await refreshMetadata(for: request.url) }
            }
        }
        .task(id: url) {
            let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await refreshMetadata(for: trimmedURL)
        }
    }

    private var canConfirm: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var downloadableCategories: [Category] {
        [.video, .audio, .archive, .app, .document, .torrent, .ed2k]
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }

    private func refreshMetadata(for rawURL: String) async {
        await MainActor.run {
            isChecking = true
            metadataMessage = nil
        }

        let draft = await manager.previewDownload(
            from: rawURL,
            headers: request.headers,
            cookie: request.cookie,
            suggestedFileName: request.fileName
        )

        await MainActor.run {
            isChecking = false
            if let normalizedURL = draft.normalizedURL {
                url = normalizedURL.absoluteString
            }
            if fileName == "download" || fileName.isEmpty || fileName == DownloadManager.fileNamePreviewFallback(for: request.url) {
                fileName = draft.fileName
            }
            size = draft.size
            category = draft.category == .all ? category : draft.category
            if draft.category == .torrent {
                engine = .bittorrent
            }
            if draft.category == .ed2k {
                engine = .ed2k
            }
            if let normalizedURL = draft.normalizedURL, let preset = DownloadManager.sitePreset(for: normalizedURL) {
                engine = preset.engine
                sitePresetMessage = "\(preset.name) preset: best quality, cookies, naming, and merge handled by yt-dlp."
            } else {
                if engine == .automatic || engine == .ytdlp {
                    engine = AppPreferences.defaultEngine
                }
                sitePresetMessage = nil
            }
            metadataMessage = draft.errorMessage.map { "Size check unavailable: \($0)" }
        }
    }

    private func loadPluginOptions() -> [PluginPickerOption] {
        let disabled = Set(UserDefaults.standard.stringArray(forKey: AppPreferences.disabledPluginsKey) ?? [])
        let trusted = Set(UserDefaults.standard.stringArray(forKey: AppPreferences.trustedPluginsKey) ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: AppPreferences.pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders.compactMap { folder in
            let manifestURL = folder.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data),
                  !disabled.contains(manifest.id),
                  trusted.contains(manifest.id) || manifest.entry == "builtin",
                  manifest.engineCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return PluginPickerOption(
                id: manifest.id,
                name: manifest.name,
                kind: manifest.kind?.capitalized ?? "Plugin"
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
        }
    }
}

private struct GrabberResourcesPanel: View {
    @Environment(\.dismiss) private var dismiss
    let resources: [SniffedResource]
    let onDownload: (BrowserDownloadRequest) -> Void
    let onClear: () -> Void
    @State private var selectedResourceID: SniffedResource.ID?

    private var selectedResource: SniffedResource? {
        guard let selectedResourceID else { return resources.first }
        return resources.first { $0.id == selectedResourceID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detected resources")
                        .font(.title3.weight(.semibold))
                    Text("\(resources.count) downloadable resource(s) captured from Chrome")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear", action: onClear)
                    .disabled(resources.isEmpty)
                Button("Done") { dismiss() }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            }

            if resources.isEmpty {
                PlaceholderDetailPanel(
                    title: "No resources detected yet",
                    message: "Open a page in Chrome, play media or click the extension icon to scan the page."
                )
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        grabberHeader("Type", width: 74)
                        grabberHeader("File Name", width: 260)
                        grabberHeader("Host", width: 180)
                        grabberHeader("Size", width: 90)
                        grabberHeader("Confidence", width: 110)
                        grabberHeader("URL", width: 330)
                    }
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(resources) { resource in
                                GrabberResourceRow(
                                    resource: resource,
                                    selected: selectedResourceID == resource.id || selectedResourceID == nil && resource.id == resources.first?.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedResourceID = resource.id
                                }
                                .onTapGesture(count: 2) {
                                    onDownload(resource.downloadRequest)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
                .frame(minHeight: 360)
                .overlay {
                    Rectangle().stroke(Color(nsColor: .separatorColor))
                }
                .padding(16)
            }

            HStack {
                Text(selectedResource?.url ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Download Selected") {
                    if let selectedResource {
                        onDownload(selectedResource.downloadRequest)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedResource == nil)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 1080, height: 560)
    }

    private func grabberHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.75)).frame(width: 1)
            }
    }
}

private struct GrabberResourceRow: View {
    let resource: SniffedResource
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            cell(width: 74) {
                Label(resource.type, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(tint)
                    .help(resource.type)
            }
            cell(width: 260) { Text(resource.title).lineLimit(1) }
            cell(width: 180) { Text(resource.host).lineLimit(1) }
            cell(width: 90) { Text(resource.size).lineLimit(1) }
            cell(width: 110) { Text(resource.confidence, format: .percent.precision(.fractionLength(0))).lineLimit(1) }
            cell(width: 330) {
                Text(resource.url)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.callout)
        .frame(height: 32)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.55)).frame(height: 1)
        }
    }

    private func cell<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.45)).frame(width: 1)
            }
    }

    private var symbol: String {
        switch resource.type.uppercased() {
        case "MP4", "M3U8", "MPD": "play.rectangle.fill"
        case "ZIP": "archivebox.fill"
        case "DMG": "shippingbox.fill"
        default: "link"
        }
    }

    private var tint: Color {
        switch resource.type.uppercased() {
        case "MP4", "M3U8", "MPD": .teal
        case "ZIP": .orange
        case "DMG": .indigo
        default: .blue
        }
    }
}

private struct NativeSidebar: View {
    @Binding var selectedCategory: Category
    let downloads: [DownloadItem]
    let onFeature: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    NativeTreeRow(title: "All Downloads", symbol: "folder.fill", tint: .yellow, selected: selectedCategory == .all, count: count(for: .all)) {
                        selectedCategory = .all
                    }
                    NativeTreeChild(title: "Video", symbol: "film.fill", tint: .teal, category: .video, selectedCategory: $selectedCategory, count: count(for: .video))
                    NativeTreeChild(title: "Audio", symbol: "music.note", tint: .pink, category: .audio, selectedCategory: $selectedCategory, count: count(for: .audio))
                    NativeTreeChild(title: "Archive", symbol: "archivebox.fill", tint: .orange, category: .archive, selectedCategory: $selectedCategory, count: count(for: .archive))
                    NativeTreeChild(title: "App", symbol: "app.gift.fill", tint: .indigo, category: .app, selectedCategory: $selectedCategory, count: count(for: .app))
                    NativeTreeChild(title: "Document", symbol: "doc.text.fill", tint: .blue, category: .document, selectedCategory: $selectedCategory, count: count(for: .document))
                    NativeTreeChild(title: "BitTorrent", symbol: "point.3.connected.trianglepath.dotted", tint: .purple, category: .torrent, selectedCategory: $selectedCategory, count: count(for: .torrent))
                    NativeTreeChild(title: "eD2K", symbol: "link.circle.fill", tint: .cyan, category: .ed2k, selectedCategory: $selectedCategory, count: count(for: .ed2k))

                    NativeDivider()
                    NativeTreeRow(title: "Unfinished", symbol: "folder.badge.minus", tint: .orange, selected: selectedCategory == .unfinished, count: count(for: .unfinished)) {
                        selectedCategory = .unfinished
                    }
                    NativeTreeRow(title: "Finished", symbol: "checkmark.seal.fill", tint: .green, selected: selectedCategory == .finished, count: count(for: .finished)) {
                        selectedCategory = .finished
                    }
                    NativeDivider()
                    NativeTreeRow(title: "Queues", symbol: "tray.2.fill", tint: .yellow, selected: selectedCategory == .active, count: count(for: .active)) {
                        selectedCategory = .active
                    }
                    NativeTreeChild(title: "Main download", symbol: "folder.fill", tint: .yellow, category: .mainDownload, selectedCategory: $selectedCategory, count: count(for: .mainDownload))
                    NativeTreeChild(title: "Synchronization", symbol: "arrow.triangle.2.circlepath", tint: .green, category: .synchronization, selectedCategory: $selectedCategory, count: count(for: .synchronization))
                    NativeTreeChild(title: "Queue # 3", symbol: "folder.fill", tint: .green, category: .queue3, selectedCategory: $selectedCategory, count: count(for: .queue3))
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
    }

    private func count(for category: Category) -> Int {
        switch category {
        case .all: downloads.count
        case .active: downloads.filter { $0.status == .downloading }.count
        case .unfinished: downloads.filter { $0.status != .complete }.count
        case .finished: downloads.filter { $0.status == .complete }.count
        case .mainDownload: downloads.filter { $0.status != .complete && $0.status != .canceled }.count
        case .synchronization, .queue3: 0
        default: downloads.filter { $0.category == category }.count
        }
    }
}

private struct NativeTreeChild: View {
    let title: String
    let symbol: String
    let tint: Color
    let category: Category
    @Binding var selectedCategory: Category
    let count: Int

    var body: some View {
        NativeTreeRow(title: title, symbol: symbol, tint: tint, selected: selectedCategory == category, count: count, indent: 28) {
            selectedCategory = category
        }
    }
}

private struct NativeTreeStaticChild: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        NativeTreeRow(title: title, symbol: symbol, tint: tint, selected: false, count: nil, indent: 28, action: action)
    }
}

private struct NativeTreeRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let count: Int?
    var indent: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer().frame(width: indent)
                Image(systemName: indent > 0 ? "plus.square" : "minus.square")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct NativeDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

private struct NativeDownloadTable: View {
    let downloads: [DownloadItem]
    @Binding var searchText: String
    @Binding var selectedDownloadID: DownloadItem.ID?
    let onOpenDetails: (DownloadItem) -> Void
    let onDelete: (DownloadItem) -> Void
    let onCopyURL: (DownloadItem) -> Void
    let onCopyFileName: (DownloadItem) -> Void
    let onCopySavePath: (DownloadItem) -> Void
    let onOpenFile: (DownloadItem) -> Void
    let onRevealInFinder: (DownloadItem) -> Void
    let onRetryFailed: () -> Void
    let onMoveCompleted: () -> Void
    let onDeleteFailed: () -> Void
    let onRestartVisible: () -> Void
    let onDeleteVisible: () -> Void
    let onEditProperties: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let columns = DownloadTableColumns(totalWidth: max(0, proxy.size.width - 1))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search downloads", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                        .frame(height: 18)
                    Menu {
                        Button("Retry Failed", action: onRetryFailed)
                        Button("Restart Visible Downloads", action: onRestartVisible)
                        Button("Move Completed...", action: onMoveCompleted)
                        Button("Edit Properties...", action: onEditProperties)
                        Divider()
                        Button("Delete Visible Downloads", role: .destructive, action: onDeleteVisible)
                        Button("Delete Failed/Canceled", role: .destructive, action: onDeleteFailed)
                    } label: {
                        Label("Batch", systemImage: "checklist")
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                }
                NativeDownloadHeader(columns: columns)
                ZStack(alignment: .topLeading) {
                    DownloadTableGridBackground(columns: columns)

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(downloads) { download in
                                NativeDownloadRow(
                                    download: download,
                                    selected: selectedDownloadID == download.id,
                                    columns: columns,
                                    onDelete: { onDelete(download) },
                                    onProperties: { onOpenDetails(download) },
                                    onCopyURL: { onCopyURL(download) },
                                    onCopyFileName: { onCopyFileName(download) },
                                    onCopySavePath: { onCopySavePath(download) },
                                    onOpenFile: { onOpenFile(download) },
                                    onRevealInFinder: { onRevealInFinder(download) }
                                )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedDownloadID = download.id
                                    }
                                    .onTapGesture(count: 2) {
                                        onOpenDetails(download)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                Rectangle().stroke(Color(nsColor: .separatorColor))
            }
        }
        .padding(10)
    }
}

private struct DownloadTableColumns {
    let total: CGFloat
    let file: CGFloat
    let queue: CGFloat
    let size: CGFloat
    let status: CGFloat
    let timeLeft: CGFloat
    let transferRate: CGFloat
    let description: CGFloat
    let actions: CGFloat

    init(totalWidth: CGFloat) {
        total = max(1, totalWidth)
        queue = min(44, max(32, total * 0.05))
        actions = min(76, max(64, total * 0.07))

        let remaining = max(1, total - queue - actions)
        file = remaining * 0.30
        size = remaining * 0.11
        status = remaining * 0.14
        timeLeft = remaining * 0.11
        transferRate = remaining * 0.16
        description = max(1, remaining - file - size - status - timeLeft - transferRate)
    }

    var verticals: [CGFloat] {
        [
            file,
            file + queue,
            file + queue + size,
            file + queue + size + status,
            file + queue + size + status + timeLeft,
            file + queue + size + status + timeLeft + transferRate,
            file + queue + size + status + timeLeft + transferRate + description
        ]
    }
}

private struct NativeDownloadHeader: View {
    let columns: DownloadTableColumns

    var body: some View {
        HStack(spacing: 0) {
            headerCell("File Name", width: columns.file)
            headerCell("Q", width: columns.queue)
            headerCell("Size", width: columns.size)
            headerCell("Status", width: columns.status)
            headerCell("Time left", width: columns.timeLeft)
            headerCell("Transfer rate", width: columns.transferRate)
            headerCell("Description", width: columns.description)
            headerCell("", width: columns.actions)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(height: 32)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
        .frame(width: columns.total, alignment: .leading)
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.75)).frame(width: 1)
            }
    }
}

private struct NativeDownloadRow: View {
    @ObservedObject var download: DownloadItem
    let selected: Bool
    let columns: DownloadTableColumns
    let onDelete: () -> Void
    let onProperties: () -> Void
    let onCopyURL: () -> Void
    let onCopyFileName: () -> Void
    let onCopySavePath: () -> Void
    let onOpenFile: () -> Void
    let onRevealInFinder: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tableCell(width: columns.file) {
                HStack(spacing: 8) {
                    Image(systemName: download.category.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(download.status.color)
                        .frame(width: 18)
                    Text(download.fileName).lineLimit(1)
                }
            }
            tableCell(width: columns.queue) {
                Image(systemName: download.status == .complete ? "checkmark.square" : "folder.badge.plus")
                    .foregroundStyle(download.status.color)
            }
            tableCell(width: columns.size) { Text(download.size).lineLimit(1) }
            tableCell(width: columns.status) { Text(statusText).lineLimit(1) }
            tableCell(width: columns.timeLeft) { Text(download.eta).lineLimit(1) }
            tableCell(width: columns.transferRate) { Text(download.speed).lineLimit(1) }
            tableCell(width: columns.description) {
                Text(description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            tableCell(width: columns.actions) {
                HStack(spacing: 8) {
                    Menu {
                        Button("Properties", action: onProperties)
                        Divider()
                        Button("Open File", action: onOpenFile)
                        Button("Show in Finder", action: onRevealInFinder)
                        Divider()
                        Button("Copy URL", action: onCopyURL)
                        Button("Copy File Name", action: onCopyFileName)
                        Button("Copy Save Path", action: onCopySavePath)
                        Divider()
                        Button("Delete Record", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("More actions")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete record")
                }
            }
        }
        .font(.callout)
        .frame(height: 32)
        .frame(width: columns.total, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.18) : rowColor)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.55)).frame(height: 1)
        }
        .contextMenu {
            Button("Properties", action: onProperties)
            Divider()
            Button("Open File", action: onOpenFile)
            Button("Show in Finder", action: onRevealInFinder)
            Divider()
            Button("Copy URL", action: onCopyURL)
            Button("Copy File Name", action: onCopyFileName)
            Button("Copy Save Path", action: onCopySavePath)
            Divider()
            Button("Delete Record", role: .destructive, action: onDelete)
        }
    }

    private func tableCell<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.45)).frame(width: 1)
            }
    }

    private var statusText: String {
        switch download.status {
        case .downloading: "\(Int(download.progress * 100))%"
        case .paused, .complete, .queued, .verifying, .canceled, .failed: download.status.rawValue
        }
    }

    private var description: String {
        if download.status == .failed || download.status == .canceled {
            return download.detail
        }

        switch download.category {
        case .video: return "Video download"
        case .audio: return "Audio download"
        case .app: return "Application package, resume capable"
        case .archive: return "Compressed archive"
        case .document: return "Document download"
        case .torrent: return "BitTorrent task"
        case .ed2k: return "eD2K task"
        default: return "Captured download"
        }
    }

    private var rowColor: Color {
        download.status == .complete ? Color.green.opacity(0.05) : Color.clear
    }
}

private struct DownloadTableGridBackground: View {
    let columns: DownloadTableColumns

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let rowHeight: CGFloat = 32
            var y = rowHeight
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += rowHeight
            }

            for x in columns.verticals {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            context.stroke(path, with: .color(Color(nsColor: .separatorColor).opacity(0.35)), lineWidth: 1)
        }
    }
}

private struct NativeDownloadDetails: View {
    @ObservedObject var download: DownloadItem
    let onResume: () -> Void
    let onPause: () -> Void
    let onCancel: () -> Void
    let onSaveSettings: () -> Void
    @State private var selectedTab = "Download status"

    private var connections: [ConnectionSlice] {
        connectionSlices(for: download)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $selectedTab) {
                Text("Download status").tag("Download status")
                Text("Speed Limiter").tag("Speed Limiter")
                Text("Options on completion").tag("Options on completion")
                Text("Request Options").tag("Request Options")
                Text("Media Formats").tag("Media Formats")
                Text("Logs").tag("Logs")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 650, alignment: .leading)

            Group {
                switch selectedTab {
                case "Speed Limiter":
                    SpeedLimiterPanel(download: download, onSave: onSaveSettings)
                case "Options on completion":
                    CompletionActionsPanel(download: download, onSave: onSaveSettings)
                case "Request Options":
                    RequestOptionsPanel(download: download, onSave: onSaveSettings)
                case "Media Formats":
                    MediaFormatsPanel(download: download, onSave: onSaveSettings)
                case "Logs":
                    DownloadLogsPanel(download: download)
                default:
                    DownloadStatusPanel(download: download, connections: connections, onResume: onResume, onPause: onPause, onCancel: onCancel)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DownloadStatusPanel: View {
    @ObservedObject var download: DownloadItem
    let connections: [ConnectionSlice]
    let onResume: () -> Void
    let onPause: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                    GridRow {
                        Text("")
                        Text(download.url)
                            .lineLimit(1)
                    }
                    detailRow("Status", download.detail, highlight: download.status == .downloading)
                    detailRow("File size", download.size)
                    detailRow("Downloaded", "\(ByteCountFormatter.string(fromByteCount: download.downloadedBytes, countStyle: .file)) [ \(Int(download.progress * 100))% ]")
                    detailRow("Transfer rate", download.speed)
                    detailRow("Time left", download.eta)
                    detailRow("Resume capability", download.resumeSupported ? "Yes" : "Unknown")
                    detailRow("Save to", download.destinationURL.deletingLastPathComponent().path)
                }
                .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
            }

            NativeSegmentedProgress(value: download.progress)
                .frame(height: 18)

            HStack {
                Button("<< Hide details") { }
                    .buttonStyle(.bordered)
                Spacer()
                Button(download.status == .paused ? "Resume" : "Pause") {
                    download.status == .paused ? onResume() : onPause()
                }
                .buttonStyle(.bordered)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }

            Text("Start positions and download progress by connections")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            NativeConnectionStripe(progress: download.progress)
                .frame(height: 22)

            VStack(spacing: 0) {
                HStack {
                    Text("N.").frame(width: 70, alignment: .leading)
                    Text("Downloaded").frame(width: 150, alignment: .leading)
                    Text("Info")
                    Spacer()
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color(nsColor: .controlBackgroundColor))

                ForEach(connections) { connection in
                    HStack {
                        Text("\(connection.part)").frame(width: 70, alignment: .leading)
                        Text(connection.progress, format: .percent.precision(.fractionLength(0))).frame(width: 150, alignment: .leading)
                        Text(connection.speed == "--" ? download.status.rawValue : "Receiving data... \(connection.speed)")
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.6)).frame(height: 1)
                    }
                }
            }
            .frame(minHeight: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .foregroundStyle(highlight ? Color.accentColor : Color.primary)
                .lineLimit(1)
        }
    }
}

private struct PlaceholderDetailPanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
        }
    }
}

private struct SpeedLimiterPanel: View {
    @ObservedObject var download: DownloadItem
    let onSave: () -> Void
    @State private var limitKB: Int = 1024

    private var limitEnabled: Binding<Bool> {
        Binding(
            get: { download.speedLimitBytesPerSecond > 0 },
            set: { enabled in
                download.speedLimitBytesPerSecond = enabled ? Int64(max(64, limitKB) * 1024) : 0
                onSave()
            }
        )
    }

    var body: some View {
        Form {
            Section("Per-task speed limit") {
                Toggle("Enable speed limit for this task", isOn: limitEnabled)
                Stepper("Limit: \(limitKB) KB/s", value: $limitKB, in: 64...1_048_576, step: 64)
                    .disabled(download.speedLimitBytesPerSecond == 0)
                    .onChange(of: limitKB) { _, newValue in
                        guard download.speedLimitBytesPerSecond > 0 else { return }
                        download.speedLimitBytesPerSecond = Int64(max(64, newValue) * 1024)
                        onSave()
                    }
                Text(download.speedLimitBytesPerSecond > 0 ? "Effective limit: \(ByteCountFormatter.string(fromByteCount: download.speedLimitBytesPerSecond, countStyle: .file))/s." : "No limit is applied to this task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Queue behavior") {
                Text("Queue concurrency is controlled in Options > Queue. This per-task limiter is applied while each segment writes data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            limitKB = max(64, Int(download.speedLimitBytesPerSecond / 1024))
        }
    }
}

private struct CompletionActionsPanel: View {
    @ObservedObject var download: DownloadItem
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("After download completes") {
                Toggle("Open file", isOn: $download.openWhenComplete)
                Toggle("Reveal in Finder", isOn: $download.revealWhenComplete)
                Toggle("Verify SHA256", isOn: $download.verifySHA256WhenComplete)
                Toggle("Verify MD5", isOn: $download.verifyMD5WhenComplete)
                Toggle("Move into category folder", isOn: $download.autoMoveCategoryWhenComplete)
                Toggle("Run plugin completion action", isOn: $download.runPluginActionWhenComplete)
            }

            Section("System action") {
                Toggle("Sleep Mac after this task completes", isOn: $download.sleepWhenComplete)
                Toggle("Shut down Mac after this task completes", isOn: $download.shutdownWhenComplete)
                Text("Sleep and shutdown are only attempted after a successful completed status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save Actions", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .onChange(of: download.openWhenComplete) { _, _ in onSave() }
        .onChange(of: download.revealWhenComplete) { _, _ in onSave() }
        .onChange(of: download.verifySHA256WhenComplete) { _, _ in onSave() }
        .onChange(of: download.verifyMD5WhenComplete) { _, _ in onSave() }
        .onChange(of: download.autoMoveCategoryWhenComplete) { _, _ in onSave() }
        .onChange(of: download.runPluginActionWhenComplete) { _, _ in onSave() }
        .onChange(of: download.sleepWhenComplete) { _, _ in onSave() }
        .onChange(of: download.shutdownWhenComplete) { _, _ in onSave() }
    }
}

private struct RequestOptionsPanel: View {
    @ObservedObject var download: DownloadItem
    let onSave: () -> Void
    @State private var headerText = ""
    @State private var cookie = ""
    @State private var referer = ""
    @State private var userAgent = ""
    @State private var proxy = ""
    @State private var retryLimit = 3
    @State private var timeout = 30
    @State private var connections = 8

    var body: some View {
        Form {
            Section("HTTP request") {
                TextEditor(text: $headerText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 78)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
                    }
                Text("Headers use one line per key: value. Referer and User-Agent below override matching header lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Cookie", text: $cookie)
                TextField("Referer", text: $referer)
                TextField("User-Agent", text: $userAgent)
            }

            Section("Network") {
                TextField("Proxy, e.g. http://127.0.0.1:7890 or socks5://127.0.0.1:1080", text: $proxy)
                HStack {
                    Button("Use System Proxy") {
                        proxy = SystemProxyDetector.currentProxy() ?? ""
                    }
                    Button("Use Default Proxy") {
                        proxy = UserDefaults.standard.string(forKey: AppPreferences.defaultProxyKey) ?? ""
                    }
                    Button("Clear Proxy") {
                        proxy = ""
                    }
                }
                Stepper("Connections: \(connections)", value: $connections, in: 1...16)
                Stepper("Retry attempts: \(retryLimit)", value: $retryLimit, in: 0...20)
                Stepper("Timeout: \(timeout) seconds", value: $timeout, in: 5...300, step: 5)
            }

            Section {
                Button("Save Request Options") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        let headers = download.headers
        referer = headers["Referer"] ?? headers["referer"] ?? ""
        userAgent = headers["User-Agent"] ?? headers["user-agent"] ?? ""
        headerText = headers
            .filter { key, _ in !["referer", "user-agent"].contains(key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        cookie = download.cookie ?? ""
        proxy = download.proxyURLString
        retryLimit = max(0, download.retryLimit)
        timeout = max(5, download.requestTimeoutSeconds)
        connections = max(1, download.preferredConnectionCount)
    }

    private func save() {
        var headers: [String: String] = [:]
        for line in headerText.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                headers[key] = value
            }
        }
        if !referer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers["Referer"] = referer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers["User-Agent"] = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        download.headers = headers
        download.cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cookie
        download.proxyURLString = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        download.retryLimit = retryLimit
        download.requestTimeoutSeconds = timeout
        download.preferredConnectionCount = connections
        onSave()
    }
}

private struct BatchPropertiesPanel: View {
    @Environment(\.dismiss) private var dismiss
    let downloads: [DownloadItem]
    @ObservedObject var manager: DownloadManager
    @State private var applyHeaders = false
    @State private var headerText = ""
    @State private var applyCookie = false
    @State private var cookie = ""
    @State private var applyProxy = false
    @State private var proxy = ""
    @State private var applyConnections = false
    @State private var connections = 8
    @State private var applyRetry = false
    @State private var retryLimit = 3
    @State private var applyTimeout = false
    @State private var timeout = 30
    @State private var applySpeedLimit = false
    @State private var speedLimitBytesPerSecond: Int64 = 0
    @State private var applyEngine = false
    @State private var engine = DownloadEngineChoice.automatic
    @State private var applyFormat = false
    @State private var ytdlpFormat = ""
    @State private var applyCategory = false
    @State private var category = Category.video

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Properties")
                        .font(.title3.weight(.semibold))
                    Text("\(downloads.count) task(s) in current view")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            Form {
                Section("Request") {
                    Toggle("Apply headers", isOn: $applyHeaders)
                    TextEditor(text: $headerText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 76)
                        .disabled(!applyHeaders)
                    Toggle("Apply cookie", isOn: $applyCookie)
                    TextField("Cookie", text: $cookie)
                        .disabled(!applyCookie)
                    Toggle("Apply proxy", isOn: $applyProxy)
                    TextField("http://127.0.0.1:7890 or socks5://127.0.0.1:1080", text: $proxy)
                        .disabled(!applyProxy)
                }

                Section("Engine") {
                    Toggle("Apply engine", isOn: $applyEngine)
                    Picker("Engine", selection: $engine) {
                        ForEach(DownloadEngineChoice.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .disabled(!applyEngine)
                    Toggle("Apply yt-dlp format", isOn: $applyFormat)
                    TextField("bv*+ba/b or 137+140", text: $ytdlpFormat)
                        .disabled(!applyFormat)
                }

                Section("Category") {
                    Toggle("Apply category", isOn: $applyCategory)
                    Picker("Category", selection: $category) {
                        ForEach([Category.video, .audio, .archive, .app, .document, .torrent, .ed2k]) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                    .disabled(!applyCategory)
                }

                Section("Network") {
                    Toggle("Apply connections", isOn: $applyConnections)
                    Stepper("Connections: \(connections)", value: $connections, in: 1...16)
                        .disabled(!applyConnections)
                    Toggle("Apply retry attempts", isOn: $applyRetry)
                    Stepper("Retry attempts: \(retryLimit)", value: $retryLimit, in: 0...20)
                        .disabled(!applyRetry)
                    Toggle("Apply timeout", isOn: $applyTimeout)
                    Stepper("Timeout: \(timeout) seconds", value: $timeout, in: 5...300, step: 5)
                        .disabled(!applyTimeout)
                    Toggle("Apply speed limit", isOn: $applySpeedLimit)
                    SpeedLimitStepper(title: "Task speed limit", value: $speedLimitBytesPerSecond)
                        .disabled(!applySpeedLimit)
                }
            }
            .formStyle(.grouped)
            .padding(16)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply") {
                    apply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 640, height: 680)
    }

    private func apply() {
        let parsedHeaders = parseHeaders(headerText)
        for item in downloads {
            if applyHeaders {
                item.headers.merge(parsedHeaders) { _, new in new }
            }
            if applyCookie {
                item.cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if applyProxy {
                item.proxyURLString = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if applyConnections {
                item.preferredConnectionCount = connections
            }
            if applyRetry {
                item.retryLimit = retryLimit
            }
            if applyTimeout {
                item.requestTimeoutSeconds = timeout
            }
            if applySpeedLimit {
                item.speedLimitBytesPerSecond = speedLimitBytesPerSecond
            }
            if applyEngine {
                item.headers[DownloadManager.engineHeaderKey] = engine.rawValue
            }
            if applyFormat {
                item.ytdlpFormatCode = ytdlpFormat.trimmingCharacters(in: .whitespacesAndNewlines)
                item.headers[DownloadManager.ytdlpFormatHeaderKey] = item.ytdlpFormatCode
                item.mediaFormatSummary = item.ytdlpFormatCode.isEmpty ? "" : "yt-dlp format \(item.ytdlpFormatCode)"
            }
            if applyCategory {
                item.category = category
            }
            manager.saveTaskSettings(item)
        }
    }

    private func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                headers[key] = value
            }
        }
        return headers
    }
}

private struct MediaFormatsPanel: View {
    @ObservedObject var download: DownloadItem
    let onSave: () -> Void
    @State private var isLoading = false
    @State private var selectedFormatCode = ""
    @State private var selectedVariantURL = ""
    @State private var selectedAudioURL = ""
    @State private var selectedSubtitleURL = ""
    @State private var output = "Use yt-dlp format list for platform videos, or inspect HLS/DASH URLs before starting the final media download."
    @State private var formats: [YTDLPFormatRow] = []
    @State private var manifestChoices: [ManifestChoiceRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(isLoading ? "Loading..." : "Load yt-dlp Formats") {
                    loadFormats()
                }
                .disabled(isLoading || download.sourceURL == nil)
                Button(isLoading ? "Parsing..." : "Parse HLS/DASH") {
                    loadManifestVariants()
                }
                .disabled(isLoading || download.sourceURL == nil)
                Button("Copy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(download.url, forType: .string)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("yt-dlp format")
                        .foregroundStyle(.secondary)
                    TextField("bestvideo+bestaudio/best or 137+140", text: $selectedFormatCode)
                    Button("Save") {
                        download.ytdlpFormatCode = selectedFormatCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        download.headers[DownloadManager.ytdlpFormatHeaderKey] = download.ytdlpFormatCode
                        download.mediaFormatSummary = download.ytdlpFormatCode.isEmpty ? "" : "yt-dlp format \(download.ytdlpFormatCode)"
                        onSave()
                    }
                }
                GridRow {
                    Text("HLS/DASH variant")
                        .foregroundStyle(.secondary)
                    TextField("variant playlist or manifest URL", text: $selectedVariantURL)
                    Button("Use") {
                        let trimmed = selectedVariantURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            download.headers.removeValue(forKey: DownloadManager.mediaVariantURLHeaderKey)
                            download.mediaFormatSummary = ""
                        } else {
                            download.headers[DownloadManager.mediaVariantURLHeaderKey] = trimmed
                            download.headers[DownloadManager.engineHeaderKey] = DownloadEngineChoice.ffmpeg.rawValue
                            download.mediaFormatSummary = "Variant \(trimmed)"
                        }
                        onSave()
                    }
                    Button("Use Manifest") {
                        download.headers[DownloadManager.mediaVariantURLHeaderKey] = download.url
                        download.headers[DownloadManager.engineHeaderKey] = DownloadEngineChoice.ffmpeg.rawValue
                        download.mediaFormatSummary = "Manifest \(download.url)"
                        selectedVariantURL = download.url
                        onSave()
                    }
                }
                GridRow {
                    Text("Audio track")
                        .foregroundStyle(.secondary)
                    TextField("optional audio rendition URL", text: $selectedAudioURL)
                    Button("Use") {
                        let trimmed = selectedAudioURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            download.headers.removeValue(forKey: DownloadManager.mediaAudioURLHeaderKey)
                        } else {
                            download.headers[DownloadManager.mediaAudioURLHeaderKey] = trimmed
                            download.headers[DownloadManager.engineHeaderKey] = DownloadEngineChoice.ffmpeg.rawValue
                        }
                        updateMediaSummary()
                        onSave()
                    }
                }
                GridRow {
                    Text("Subtitle track")
                        .foregroundStyle(.secondary)
                    TextField("optional subtitle rendition URL", text: $selectedSubtitleURL)
                    Button("Use") {
                        let trimmed = selectedSubtitleURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            download.headers.removeValue(forKey: DownloadManager.mediaSubtitleURLHeaderKey)
                        } else {
                            download.headers[DownloadManager.mediaSubtitleURLHeaderKey] = trimmed
                            download.headers[DownloadManager.engineHeaderKey] = DownloadEngineChoice.ffmpeg.rawValue
                        }
                        updateMediaSummary()
                        onSave()
                    }
                }
            }
            .font(.callout)

            if !formats.isEmpty {
                HStack {
                    Button("Best MP4") { selectFormat("bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]") }
                    Button("Best Quality") { selectFormat("bv*+ba/b") }
                    Button("Audio Only") { selectFormat("ba/bestaudio") }
                    Spacer()
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("ID").frame(width: 70, alignment: .leading)
                        Text("Ext").frame(width: 46, alignment: .leading)
                        Text("Resolution").frame(width: 110, alignment: .leading)
                        Text("FPS").frame(width: 50, alignment: .leading)
                        Text("Size").frame(width: 78, alignment: .leading)
                        Text("Codecs").frame(width: 150, alignment: .leading)
                        Text("Note").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color(nsColor: .controlBackgroundColor))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(formats) { format in
                                Button {
                                    selectFormat(format.id)
                                } label: {
                                    HStack {
                                        Text(format.id).frame(width: 70, alignment: .leading)
                                        Text(format.ext).frame(width: 46, alignment: .leading)
                                        Text(format.resolution).frame(width: 110, alignment: .leading)
                                        Text(format.fps).frame(width: 50, alignment: .leading)
                                        Text(format.size).frame(width: 78, alignment: .leading)
                                        Text(format.codecs).frame(width: 150, alignment: .leading)
                                        Text(format.note).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(selectedFormatCode == format.id ? Color.accentColor.opacity(0.14) : Color.clear)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.45)).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
                }
            }

            if !manifestChoices.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Type").frame(width: 74, alignment: .leading)
                        Text("Name").frame(width: 160, alignment: .leading)
                        Text("Quality").frame(width: 130, alignment: .leading)
                        Text("URL / Info").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color(nsColor: .controlBackgroundColor))

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manifestChoices) { choice in
                                Button {
                                    applyManifestChoice(choice)
                                } label: {
                                    HStack {
                                        Text(choice.type).frame(width: 74, alignment: .leading)
                                        Text(choice.name).frame(width: 160, alignment: .leading)
                                        Text(choice.quality).frame(width: 130, alignment: .leading)
                                        Text(choice.url ?? choice.info).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(choice.url == nil)
                                .background(selectedVariantURL == choice.url ? Color.accentColor.opacity(0.14) : Color.clear)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.45)).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
                }
            }

            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedFormatCode = download.ytdlpFormatCode
            selectedVariantURL = download.headers[DownloadManager.mediaVariantURLHeaderKey] ?? ""
            selectedAudioURL = download.headers[DownloadManager.mediaAudioURLHeaderKey] ?? ""
            selectedSubtitleURL = download.headers[DownloadManager.mediaSubtitleURLHeaderKey] ?? ""
        }
    }

    private func applyManifestChoice(_ choice: ManifestChoiceRow) {
        guard let url = choice.url else { return }
        switch choice.type.uppercased() {
        case "AUDIO":
            selectedAudioURL = url
            download.headers[DownloadManager.mediaAudioURLHeaderKey] = url
        case "SUBTITLES", "CLOSED-CAPTIONS":
            selectedSubtitleURL = url
            download.headers[DownloadManager.mediaSubtitleURLHeaderKey] = url
        default:
            selectedVariantURL = url
            download.headers[DownloadManager.mediaVariantURLHeaderKey] = url
        }
        download.headers[DownloadManager.engineHeaderKey] = DownloadEngineChoice.ffmpeg.rawValue
        updateMediaSummary()
        onSave()
    }

    private func updateMediaSummary() {
        var parts: [String] = []
        if let video = download.headers[DownloadManager.mediaVariantURLHeaderKey], !video.isEmpty {
            parts.append("video")
        }
        if let audio = download.headers[DownloadManager.mediaAudioURLHeaderKey], !audio.isEmpty {
            parts.append("audio")
        }
        if let subtitle = download.headers[DownloadManager.mediaSubtitleURLHeaderKey], !subtitle.isEmpty {
            parts.append("subtitle")
        }
        download.mediaFormatSummary = parts.isEmpty ? "" : "ffmpeg " + parts.joined(separator: "+")
    }

    private func loadFormats() {
        guard let sourceURL = download.sourceURL else { return }
        isLoading = true
        output = "Loading formats..."
        let formatURL = sourceURL.absoluteString
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["yt-dlp", "-F", formatURL]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    output = text.isEmpty ? "yt-dlp returned no format list." : text
                    formats = Self.parseFormats(text)
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    output = "yt-dlp is not available or failed to run: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func selectFormat(_ code: String) {
        selectedFormatCode = code
        download.ytdlpFormatCode = code
        download.headers[DownloadManager.ytdlpFormatHeaderKey] = code
        download.mediaFormatSummary = "yt-dlp format \(code)"
        onSave()
    }

    private func loadManifestVariants() {
        guard let sourceURL = download.sourceURL else { return }
        isLoading = true
        output = "Parsing media manifest..."
        let timeout = download.requestTimeoutSeconds
        let headers = download.headers
        let cookie = download.cookie
        Task {
            var request = URLRequest(url: sourceURL)
            request.timeoutInterval = TimeInterval(max(5, timeout))
            headers
                .filter { ![DownloadManager.engineHeaderKey, DownloadManager.ytdlpFormatHeaderKey, DownloadManager.mediaVariantURLHeaderKey].contains($0.key) }
                .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            if let cookie {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let text = String(data: data, encoding: .utf8) else {
                    output = "Manifest is not UTF-8 text."
                    isLoading = false
                    return
                }
                let lowerPath = sourceURL.pathExtension.lowercased()
                if text.contains("#EXTM3U") || lowerPath == "m3u8" {
                    output = Self.hlsVariantSummary(text: text, baseURL: sourceURL)
                    manifestChoices = Self.hlsManifestChoices(text: text, baseURL: sourceURL)
                } else if text.localizedCaseInsensitiveContains("<MPD") || lowerPath == "mpd" {
                    output = Self.dashVariantSummary(text: text)
                    manifestChoices = Self.dashManifestChoices(text: text)
                } else if let httpResponse = response as? HTTPURLResponse {
                    output = "HTTP \(httpResponse.statusCode). This does not look like an HLS or DASH manifest."
                    manifestChoices = []
                } else {
                    output = "This does not look like an HLS or DASH manifest."
                    manifestChoices = []
                }
            } catch {
                output = "Failed to load manifest: \(error.localizedDescription)"
                manifestChoices = []
            }
            isLoading = false
        }
    }

    nonisolated private static func hlsManifestChoices(text: String, baseURL: URL) -> [ManifestChoiceRow] {
        var choices: [ManifestChoiceRow] = []
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var pendingInfo: String?
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingInfo = line
            } else if line.hasPrefix("#EXT-X-MEDIA") {
                let type = line.firstMatch(pattern: #"TYPE=([^,]+)"#) ?? "TRACK"
                let name = line.firstMatch(pattern: #"NAME="([^"]+)""#) ?? "--"
                let language = line.firstMatch(pattern: #"LANGUAGE="([^"]+)""#) ?? "--"
                let uri = line.firstMatch(pattern: #"URI="([^"]+)""#).map { URL(string: $0, relativeTo: baseURL)?.absoluteURL.absoluteString ?? $0 }
                choices.append(ManifestChoiceRow(type: type, name: name, quality: language, url: uri, info: line))
            } else if let info = pendingInfo, !line.isEmpty, !line.hasPrefix("#") {
                let url = URL(string: line, relativeTo: baseURL)?.absoluteURL.absoluteString ?? line
                let resolution = info.firstMatch(pattern: #"RESOLUTION=([^,]+)"#) ?? "--"
                let bandwidth = info.firstMatch(pattern: #"BANDWIDTH=([^,]+)"#) ?? "--"
                choices.append(ManifestChoiceRow(type: "VIDEO", name: "HLS variant", quality: "\(resolution) \(bandwidth)", url: url, info: info))
                pendingInfo = nil
            }
        }
        return choices
    }

    nonisolated private static func dashManifestChoices(text: String) -> [ManifestChoiceRow] {
        let pattern = #"<Representation([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).prefix(100).enumerated().map { index, match in
            let attrs = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let id = attrs.firstMatch(pattern: #"id="([^"]*)""#) ?? "#\(index + 1)"
            let bandwidth = attrs.firstMatch(pattern: #"bandwidth="([^"]*)""#) ?? "--"
            let width = attrs.firstMatch(pattern: #"width="([^"]*)""#) ?? "--"
            let height = attrs.firstMatch(pattern: #"height="([^"]*)""#) ?? "--"
            let mime = attrs.firstMatch(pattern: #"mimeType="([^"]*)""#) ?? ""
            let type = mime.localizedCaseInsensitiveContains("audio") ? "AUDIO" : "VIDEO"
            return ManifestChoiceRow(type: type, name: id, quality: "\(width)x\(height) \(bandwidth)", url: nil, info: attrs)
        }
    }

    nonisolated private static func hlsVariantSummary(text: String, baseURL: URL) -> String {
        var rows: [String] = []
        var audioRows: [String] = []
        var subtitleRows: [String] = []
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var pendingInfo: String?
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingInfo = line
            } else if line.hasPrefix("#EXT-X-MEDIA") {
                let type = line.firstMatch(pattern: #"TYPE=([^,]+)"#) ?? "--"
                let name = line.firstMatch(pattern: #"NAME="([^"]+)""#) ?? "--"
                let group = line.firstMatch(pattern: #"GROUP-ID="([^"]+)""#) ?? "--"
                let language = line.firstMatch(pattern: #"LANGUAGE="([^"]+)""#) ?? "--"
                let uri = line.firstMatch(pattern: #"URI="([^"]+)""#).map { URL(string: $0, relativeTo: baseURL)?.absoluteURL.absoluteString ?? $0 } ?? "--"
                let row = "\(type) \(name) lang \(language) group \(group)\n  \(uri)"
                if type.localizedCaseInsensitiveContains("AUDIO") {
                    audioRows.append(row)
                } else if type.localizedCaseInsensitiveContains("SUBTITLES") || type.localizedCaseInsensitiveContains("CLOSED-CAPTIONS") {
                    subtitleRows.append(row)
                }
            } else if let info = pendingInfo, !line.isEmpty, !line.hasPrefix("#") {
                let absolute = URL(string: line, relativeTo: baseURL)?.absoluteURL.absoluteString ?? line
                let resolution = info.firstMatch(pattern: #"RESOLUTION=([^,]+)"#) ?? "--"
                let bandwidth = info.firstMatch(pattern: #"BANDWIDTH=([^,]+)"#) ?? "--"
                let codecs = info.firstMatch(pattern: #"CODECS="([^"]+)""#) ?? "--"
                rows.append("VIDEO \(resolution) bandwidth \(bandwidth) codecs \(codecs)\n  \(absolute)")
                pendingInfo = nil
            }
        }
        var sections: [String] = []
        sections.append(rows.isEmpty ? "Video variants: none found. This may already be a media playlist." : "Video variants\n" + rows.joined(separator: "\n\n"))
        if !audioRows.isEmpty {
            sections.append("Audio tracks\n" + audioRows.joined(separator: "\n\n"))
        }
        if !subtitleRows.isEmpty {
            sections.append("Subtitle tracks\n" + subtitleRows.joined(separator: "\n\n"))
        }
        return "Copy a video variant URL into HLS/DASH variant, then press Use. ffmpeg will merge default audio/subtitle renditions when the playlist exposes them.\n\n" + sections.joined(separator: "\n\n")
    }

    nonisolated private static func dashVariantSummary(text: String) -> String {
        let pattern = #"<Representation[^>]*(?:id="([^"]*)")?[^>]*(?:bandwidth="([^"]*)")?[^>]*(?:width="([^"]*)")?[^>]*(?:height="([^"]*)")?[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return "Unable to parse DASH representations."
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        let rows = matches.prefix(80).enumerated().map { index, match -> String in
            func value(_ i: Int) -> String {
                guard match.range(at: i).location != NSNotFound, let range = Range(match.range(at: i), in: text) else { return "--" }
                return String(text[range])
            }
            let id = value(1)
            let bandwidth = value(2)
            let width = value(3)
            let height = value(4)
            return "DASH #\(index + 1) id \(id) \(width)x\(height) bandwidth \(bandwidth)"
        }
        let adaptationPattern = #"<AdaptationSet[^>]*(?:contentType="([^"]*)")?[^>]*(?:mimeType="([^"]*)")?[^>]*(?:lang="([^"]*)")?[^>]*>"#
        var trackRows: [String] = []
        if let adaptationRegex = try? NSRegularExpression(pattern: adaptationPattern, options: [.caseInsensitive]) {
            let matches = adaptationRegex.matches(in: text, range: nsRange)
            trackRows = matches.prefix(80).map { match in
                func value(_ i: Int) -> String {
                    guard match.range(at: i).location != NSNotFound, let range = Range(match.range(at: i), in: text) else { return "--" }
                    return String(text[range])
                }
                return "TRACK type \(value(1)) mime \(value(2)) lang \(value(3))"
            }
        }
        if rows.isEmpty && trackRows.isEmpty {
            return "No DASH Representation or AdaptationSet entries found."
        }
        return (rows.isEmpty ? "" : "Representations\n" + rows.joined(separator: "\n"))
            + (trackRows.isEmpty ? "" : "\n\nAudio/subtitle/video tracks\n" + trackRows.joined(separator: "\n"))
    }

    nonisolated private static func parseFormats(_ text: String) -> [YTDLPFormatRow] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            guard !line.hasPrefix("["),
                  !line.lowercased().contains("format code"),
                  let first = line.split(separator: " ", maxSplits: 1).first,
                  !first.isEmpty,
                  first.rangeOfCharacter(from: .alphanumerics) != nil else {
                return nil
            }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { return nil }
            let id = parts[0]
            let ext = parts.count > 1 ? parts[1] : "--"
            let resolution = parts.count > 2 ? parts[2] : "--"
            let fps = parts.first(where: { $0.hasSuffix("fps") })?.replacingOccurrences(of: "fps", with: "") ?? "--"
            let size = parts.first(where: { $0.contains("MiB") || $0.contains("GiB") || $0.contains("KiB") }) ?? "--"
            let codecs = parts.filter { $0.hasPrefix("avc") || $0.hasPrefix("vp") || $0.hasPrefix("av01") || $0.hasPrefix("mp4a") || $0.hasPrefix("opus") }.prefix(2).joined(separator: "+")
            let note = parts.dropFirst(3).joined(separator: " ")
            return YTDLPFormatRow(id: id, ext: ext, resolution: resolution, fps: fps, size: size, codecs: codecs.isEmpty ? "--" : codecs, note: note)
        }
    }
}

private struct YTDLPFormatRow: Identifiable, Hashable {
    let id: String
    let ext: String
    let resolution: String
    let fps: String
    let size: String
    let codecs: String
    let note: String
}

private struct ManifestChoiceRow: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let name: String
    let quality: String
    let url: String?
    let info: String
}

private struct DownloadLogsPanel: View {
    @ObservedObject var download: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Task Logs")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(download.logLines.joined(separator: "\n"), forType: .string)
                }
            }
            ScrollView {
                Text(download.logLines.isEmpty ? "No logs yet. Start or resume this task to collect request, retry, and engine output logs." : download.logLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..<endIndex, in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[range])
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private struct NativeSegmentedProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green)
                    .frame(width: proxy.size.width * value)
                HStack(spacing: 3) {
                    ForEach(0..<44, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor))
            }
        }
    }
}

private struct NativeConnectionStripe: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(index) / 12.0 < progress ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(2)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
        }
    }
}

private struct NativeStatusBar: View {
    let downloads: [DownloadItem]
    let resources: [SniffedResource]
    let totalSpeed: String
    let queueStatus: String
    @Binding var maximumConcurrentDownloads: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(downloads.count) downloads")
            Divider()
            Text("Detected resources: \(resources.count)")
            Divider()
            Text("Total speed: \(totalSpeed)")
            Divider()
            Text(queueStatus)
            Stepper("Max: \(maximumConcurrentDownloads)", value: $maximumConcurrentDownloads, in: 1...16)
                .help("Maximum concurrent downloads")
            Spacer()
            Text("HTTP/HTTPS + Range resume engine")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }
}

private enum ClipboardDownloadDetector {
    private static let downloadableExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "m3u8", "avi", "flv",
        "mp3", "flac", "aac", "m4a", "wav", "ogg", "opus",
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst",
        "dmg", "pkg", "xip", "exe", "msi", "app",
        "pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "ppt", "pptx", "epub",
        "torrent", "ed2k"
    ]

    static func downloadableURL(in text: String) -> String? {
        for token in tokens(in: text) {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"' \n\t"))
            guard let url = DownloadManager.normalizedURL(from: cleaned),
                  looksDownloadable(url) else {
                continue
            }
            return url.absoluteString
        }
        return nil
    }

    private static func tokens(in text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter {
                $0.localizedCaseInsensitiveContains("http")
                    || $0.localizedCaseInsensitiveContains("magnet:")
                    || $0.localizedCaseInsensitiveContains("ed2k://")
                    || $0.localizedCaseInsensitiveContains(".torrent")
            }
    }

    private static func looksDownloadable(_ url: URL) -> Bool {
        if DownloadManager.isBitTorrentSource(url) {
            return true
        }
        if DownloadManager.isED2KSource(url) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if downloadableExtensions.contains(ext) {
            return true
        }

        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }

        return queryItems.contains { item in
            ["filename", "response-content-disposition", "rscd"].contains(item.name.lowercased())
                || downloadableExtensions.contains(URL(fileURLWithPath: item.value ?? "").pathExtension.lowercased())
        }
    }
}

private extension Category {
    var symbol: String {
        switch self {
        case .all: "tray.full.fill"
        case .active: "bolt.fill"
        case .unfinished: "hourglass"
        case .finished: "checkmark.seal.fill"
        case .video: "play.rectangle.fill"
        case .audio: "music.note"
        case .archive: "archivebox.fill"
        case .document: "doc.text.fill"
        case .torrent: "point.3.connected.trianglepath.dotted"
        case .ed2k: "link.circle.fill"
        case .app: "shippingbox.fill"
        case .mainDownload: "folder.fill"
        case .synchronization: "arrow.triangle.2.circlepath"
        case .queue3: "folder.fill"
        }
    }
}

private extension DownloadStatus {
    var color: Color {
        switch self {
        case .downloading: .accentColor
        case .paused: .orange
        case .complete: .green
        case .queued: .secondary
        case .verifying: .purple
        case .canceled: .red
        case .failed: .red
        }
    }
}

private extension Notification.Name {
    static let showAboutPanel = Notification.Name("showAboutPanel")
    static let showAddDownloadSheet = Notification.Name("showAddDownloadSheet")
    static let externalDownloadRequested = Notification.Name("externalDownloadRequested")
    static let externalRawDownloadRequested = Notification.Name("externalRawDownloadRequested")
    static let sniffedResourcesDetected = Notification.Name("sniffedResourcesDetected")
    static let pluginExtractionRequested = Notification.Name("pluginExtractionRequested")
}
