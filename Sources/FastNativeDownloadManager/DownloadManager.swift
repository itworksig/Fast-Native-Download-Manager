import AppKit
import Combine
import CryptoKit
@preconcurrency import Darwin
@preconcurrency import Foundation
import UserNotifications
import SQLite3

final class DownloadItem: ObservableObject, Identifiable, @unchecked Sendable {
    let id: UUID
    let sourceURL: URL?
    let tempURL: URL
    let createdAt: Date

    @Published var fileName: String
    @Published var url: String
    @Published var destinationURL: URL
    @Published var category: Category
    @Published var headers: [String: String]
    @Published var cookie: String?
    @Published var size: String
    @Published var speed: String
    @Published var eta: String
    @Published var connections: Int
    @Published var progress: Double
    @Published var status: DownloadStatus
    @Published var downloadedBytes: Int64
    @Published var totalBytes: Int64?
    @Published var resumeSupported: Bool
    @Published var detail: String
    @Published var segments: [DownloadSegment]
    @Published var updatedAt: Date
    @Published var speedLimitBytesPerSecond: Int64
    @Published var openWhenComplete: Bool
    @Published var revealWhenComplete: Bool
    @Published var sleepWhenComplete: Bool
    @Published var shutdownWhenComplete: Bool
    @Published var verifySHA256WhenComplete: Bool
    @Published var verifyMD5WhenComplete: Bool
    @Published var autoMoveCategoryWhenComplete: Bool
    @Published var runPluginActionWhenComplete: Bool
    @Published var proxyURLString: String
    @Published var retryLimit: Int
    @Published var requestTimeoutSeconds: Int
    @Published var preferredConnectionCount: Int
    @Published var ytdlpFormatCode: String
    @Published var mediaFormatSummary: String
    @Published var logLines: [String]

    init(
        id: UUID = UUID(),
        fileName: String,
        url: String,
        sourceURL: URL?,
        destinationURL: URL,
        tempURL: URL,
        category: Category,
        headers: [String: String] = [:],
        cookie: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        size: String = "--",
        speed: String = "--",
        eta: String = "--",
        connections: Int = 0,
        progress: Double = 0,
        status: DownloadStatus = .queued,
        downloadedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        resumeSupported: Bool = false,
        detail: String = "Queued",
        segments: [DownloadSegment] = [],
        speedLimitBytesPerSecond: Int64 = 0,
        openWhenComplete: Bool = false,
        revealWhenComplete: Bool = false,
        sleepWhenComplete: Bool = false,
        shutdownWhenComplete: Bool = false,
        verifySHA256WhenComplete: Bool = false,
        verifyMD5WhenComplete: Bool = false,
        autoMoveCategoryWhenComplete: Bool = false,
        runPluginActionWhenComplete: Bool = false,
        proxyURLString: String = "",
        retryLimit: Int = 3,
        requestTimeoutSeconds: Int = 30,
        preferredConnectionCount: Int = 8,
        ytdlpFormatCode: String = "",
        mediaFormatSummary: String = "",
        logLines: [String] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.tempURL = tempURL
        self.category = category
        self.headers = headers
        self.cookie = cookie
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.size = size
        self.speed = speed
        self.eta = eta
        self.connections = connections
        self.progress = progress
        self.status = status
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.resumeSupported = resumeSupported
        self.detail = detail
        self.segments = segments
        self.speedLimitBytesPerSecond = speedLimitBytesPerSecond
        self.openWhenComplete = openWhenComplete
        self.revealWhenComplete = revealWhenComplete
        self.sleepWhenComplete = sleepWhenComplete
        self.shutdownWhenComplete = shutdownWhenComplete
        self.verifySHA256WhenComplete = verifySHA256WhenComplete
        self.verifyMD5WhenComplete = verifyMD5WhenComplete
        self.autoMoveCategoryWhenComplete = autoMoveCategoryWhenComplete
        self.runPluginActionWhenComplete = runPluginActionWhenComplete
        self.proxyURLString = proxyURLString
        self.retryLimit = retryLimit
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.preferredConnectionCount = preferredConnectionCount
        self.ytdlpFormatCode = ytdlpFormatCode
        self.mediaFormatSummary = mediaFormatSummary
        self.logLines = logLines
    }
}

struct DownloadSegment: Identifiable, Sendable {
    let id: Int
    let start: Int64
    let end: Int64
    var downloaded: Int64
    var speed: Int64
    var status: DownloadStatus

    var length: Int64 { max(0, end - start + 1) }
    var offset: Int64 { start + downloaded }
    var isComplete: Bool { downloaded >= length }
    var progress: Double {
        guard length > 0 else { return 0 }
        return min(1, Double(downloaded) / Double(length))
    }
}

enum DownloadStatus: String {
    case downloading = "Downloading"
    case paused = "Paused"
    case complete = "Complete"
    case queued = "Queued"
    case verifying = "Verifying"
    case canceled = "Canceled"
    case failed = "Failed"
}

enum Category: String, CaseIterable, Identifiable {
    case all = "All Downloads"
    case active = "Active"
    case unfinished = "Unfinished"
    case finished = "Finished"
    case video = "Video"
    case audio = "Audio"
    case archive = "Archive"
    case app = "App"
    case document = "Document"
    case torrent = "BitTorrent"
    case ed2k = "eD2K"
    case mainDownload = "Main download"
    case synchronization = "Synchronization"
    case queue3 = "Queue # 3"

    var id: String { rawValue }
}

enum DownloadEngineChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Auto"
    case native = "Native"
    case amazon = "Amazon S3"
    case ytdlp = "yt-dlp"
    case ffmpeg = "ffmpeg"
    case bittorrent = "BitTorrent"
    case ed2k = "eD2K"

    var id: String { rawValue }
}

struct DownloadDraftMetadata: Sendable {
    let rawURL: String
    let normalizedURL: URL?
    let fileName: String
    let size: String
    let totalBytes: Int64?
    let category: Category
    let errorMessage: String?
}

struct BrowserDownloadRequest: Codable, Sendable {
    let url: String
    let fileName: String?
    let headers: [String: String]
    let cookie: String?
    let source: String?

    init(url: String, fileName: String? = nil, headers: [String: String] = [:], cookie: String? = nil, source: String? = nil) {
        self.url = url
        self.fileName = fileName
        self.headers = headers
        self.cookie = cookie
        self.source = source
    }
}

struct SiteDownloadPreset: Sendable {
    let name: String
    let engine: DownloadEngineChoice
    let ytdlpFormat: String
}

private struct RuntimePluginManifest: Codable {
    let id: String
    let name: String
    let kind: String?
    let protocols: [String]?
    let fileExtensions: [String]?
    let urlPatterns: [String]?
    let permissions: [String]?
    let allowedCommands: [String]?
    let engineCommand: String?
    let extractorScript: String?
    let completionAction: String?
}

private final class ExternalProcessWaitState: @unchecked Sendable {
    let lock = NSLock()
    var didResume = false
}

private enum RuntimePluginSecurityPolicy {
    static func validate(_ manifest: RuntimePluginManifest, command: String) throws {
        let permissions = Set(manifest.permissions ?? [])
        let isBuiltin = manifest.id.hasPrefix("builtin.")
        guard permissions.contains("external-engine") || isBuiltin else {
            throw DownloadEngineError.externalToolFailed("Plugin \(manifest.name) is blocked: missing external-engine permission.")
        }
        guard permissions.contains("filesystem-write") || isBuiltin else {
            throw DownloadEngineError.externalToolFailed("Plugin \(manifest.name) is blocked: missing filesystem-write permission.")
        }
        if commandNeedsShell(command), !permissions.contains("shell"), !isBuiltin {
            throw DownloadEngineError.externalToolFailed("Plugin \(manifest.name) is blocked: shell operators require shell permission.")
        }
        if let executable = firstExecutableName(in: command),
           let allowed = manifest.allowedCommands,
           !allowed.isEmpty,
           !allowed.contains(executable) {
            throw DownloadEngineError.externalToolFailed("Plugin \(manifest.name) is blocked: \(executable) is not in allowedCommands.")
        }
    }

    static func sanitizedEnvironment(for item: DownloadItem, sourceURL: URL, allowCookies: Bool) -> [String: String] {
        [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "FNDM_URL": sourceURL.absoluteString,
            "FNDM_OUTPUT": item.destinationURL.path,
            "FNDM_OUTPUT_DIR": item.destinationURL.deletingLastPathComponent().path,
            "FNDM_FILE": item.fileName,
            "FNDM_CONNECTIONS": String(max(1, item.preferredConnectionCount)),
            "FNDM_COOKIE": allowCookies ? (item.cookie ?? "") : "",
            "FNDM_HEADERS": Self.loggableHeaders(item.headers),
            "FNDM_FORMAT": item.ytdlpFormatCode,
            "FNDM_COOKIES_FILE": allowCookies ? (UserDefaults.standard.string(forKey: "Options.cookiesFilePath") ?? "") : "",
            "FNDM_COOKIES_FROM_BROWSER": allowCookies ? {
                let value = UserDefaults.standard.string(forKey: "Options.cookiesFromBrowser") ?? ""
                return value == "None" ? "" : value.lowercased()
            }() : ""
        ]
    }

    private static func commandNeedsShell(_ command: String) -> Bool {
        [";", "&&", "||", "|", ">", "<", "`", "$("].contains { command.contains($0) }
    }

    private static func firstExecutableName(in command: String) -> String? {
        command
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .split(separator: "/")
            .last
            .map(String.init)
    }

    private static func loggableHeaders(_ headers: [String: String]) -> String {
        headers
            .filter { key, _ in key.lowercased() != "cookie" && key.lowercased() != "authorization" }
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\\n")
    }
}

final class DownloadManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [DownloadItem] = []
    static let engineHeaderKey = "X-FNDM-Engine"
    static let mediaVariantURLHeaderKey = "X-FNDM-Media-Variant-URL"
    static let mediaAudioURLHeaderKey = "X-FNDM-Media-Audio-URL"
    static let mediaSubtitleURLHeaderKey = "X-FNDM-Media-Subtitle-URL"
    static let ytdlpFormatHeaderKey = "X-FNDM-YTDLP-Format"
    static let sitePresetHeaderKey = "X-FNDM-Site-Preset"
    static let pluginIDHeaderKey = "X-FNDM-Plugin-ID"
    @Published var maximumConcurrentDownloads = max(1, min(16, UserDefaults.standard.object(forKey: "Options.maximumConcurrentDownloads") as? Int ?? 2)) {
        didSet {
            UserDefaults.standard.set(maximumConcurrentDownloads, forKey: "Options.maximumConcurrentDownloads")
            scheduleQueue()
        }
    }
    @Published var globalSpeedLimitBytesPerSecond = max(0, UserDefaults.standard.object(forKey: "Options.globalSpeedLimitBytesPerSecond") as? Int64 ?? 0) {
        didSet { UserDefaults.standard.set(globalSpeedLimitBytesPerSecond, forKey: "Options.globalSpeedLimitBytesPerSecond") }
    }
    @Published var queueSpeedLimitBytesPerSecond = max(0, UserDefaults.standard.object(forKey: "Options.queueSpeedLimitBytesPerSecond") as? Int64 ?? 0) {
        didSet { UserDefaults.standard.set(queueSpeedLimitBytesPerSecond, forKey: "Options.queueSpeedLimitBytesPerSecond") }
    }
    @Published private(set) var queueRunning = false

    private let maximumRetryAttempts = 3
    private let requestTimeout: TimeInterval = 30
    private let resourceTimeout: TimeInterval = 60 * 60 * 6

    private lazy var session: URLSession = {
        URLSession(configuration: defaultSessionConfiguration(), delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private let store = DownloadTaskStore()
    private var segmentTransfers: [Int: SegmentTransfer] = [:]
    private var activeTasksByItemID: [UUID: Set<URLSessionDataTask>] = [:]
    private var fileHandlesByItemID: [UUID: Int32] = [:]
    private var metadataByItemID: [UUID: DownloadMetadata] = [:]
    private var retryAttemptsBySegment: [SegmentRetryKey: Int] = [:]
    private var queuedItemIDs: Set<UUID> = []
    private var externalProcessesByItemID: [UUID: Process] = [:]
    private var sessionsByProxy: [String: URLSession] = [:]

    override init() {
        super.init()
        let persisted = store.loadDownloads()
        downloads = persisted.isEmpty ? Self.sampleDownloads() : persisted
        queuedItemIDs = Set(downloads.filter { $0.sourceURL != nil && $0.status == .queued }.map(\.id))
    }

    private func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    private func session(for item: DownloadItem) -> URLSession {
        let proxy = item.proxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proxy.isEmpty, let proxyURL = URL(string: proxy), let host = proxyURL.host else {
            return session
        }

        if let cached = sessionsByProxy[proxy] {
            return cached
        }

        let configuration = defaultSessionConfiguration()
        let port = proxyURL.port ?? (proxyURL.scheme?.lowercased().contains("https") == true ? 443 : 80)
        let scheme = proxyURL.scheme?.lowercased() ?? "http"
        var proxyDictionary: [AnyHashable: Any] = [:]
        if scheme.hasPrefix("socks") {
            proxyDictionary[kCFStreamPropertySOCKSProxyHost as String] = host
            proxyDictionary[kCFStreamPropertySOCKSProxyPort as String] = port
        } else {
            proxyDictionary[kCFNetworkProxiesHTTPEnable as String] = true
            proxyDictionary[kCFNetworkProxiesHTTPProxy as String] = host
            proxyDictionary[kCFNetworkProxiesHTTPPort as String] = port
            proxyDictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            proxyDictionary[kCFNetworkProxiesHTTPSProxy as String] = host
            proxyDictionary[kCFNetworkProxiesHTTPSPort as String] = port
        }
        configuration.connectionProxyDictionary = proxyDictionary
        let proxiedSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        sessionsByProxy[proxy] = proxiedSession
        return proxiedSession
    }

    @discardableResult
    func addDownload(
        from rawURL: String,
        fileName customFileName: String? = nil,
        category customCategory: Category? = nil,
        saveDirectory: URL? = nil,
        headers customHeaders: [String: String] = [:],
        cookie customCookie: String? = nil,
        engine: DownloadEngineChoice = .automatic,
        startImmediately: Bool = true
    ) -> DownloadItem? {
        guard let sourceURL = Self.normalizedURL(from: rawURL) else { return nil }

        let sourceExtension = sourceURL.pathExtension.lowercased()
        let engineHint: DownloadEngineChoice
        if engine == .automatic, shouldUseYTDLP(for: sourceURL) {
            engineHint = .ytdlp
        } else if engine == .automatic, ["m3u8", "mpd"].contains(sourceExtension) {
            engineHint = .ffmpeg
        } else {
            engineHint = engine
        }
        let rawFileName = Self.sanitizedFileName(customFileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Self.fileName(for: sourceURL))
        let fileName = Self.fileNameWithDefaultExtension(rawFileName, sourceURL: sourceURL, engine: engineHint)
        let resolvedCategory = customCategory ?? Self.category(for: Self.isBitTorrentSource(sourceURL) ? "\(fileName).torrent" : fileName)
        let destinationURL = resolvedCategory == .torrent || resolvedCategory == .ed2k
            ? (saveDirectory ?? Self.downloadDirectory())
            : (saveDirectory ?? Self.downloadDirectory()).appendingPathComponent(fileName)
        var headers = customHeaders
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = "FastNativeDownloadManager/0.2"
        }
        headers[Self.engineHeaderKey] = engine.rawValue
        if let preset = Self.sitePreset(for: sourceURL) {
            headers[Self.sitePresetHeaderKey] = preset.name
            if headers[Self.engineHeaderKey] == DownloadEngineChoice.automatic.rawValue {
                headers[Self.engineHeaderKey] = preset.engine.rawValue
            }
            headers[Self.ytdlpFormatHeaderKey] = headers[Self.ytdlpFormatHeaderKey] ?? preset.ytdlpFormat
        }
        let cookie = customCookie?.nilIfEmpty ?? HTTPCookieStorage.shared.cookies(for: sourceURL)?.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        let uniqueDestinationURL = resolvedCategory == .torrent || resolvedCategory == .ed2k
            ? destinationURL
            : Self.uniqueDestinationURL(for: destinationURL)
        let uniqueFileName = resolvedCategory == .torrent || resolvedCategory == .ed2k
            ? fileName
            : uniqueDestinationURL.lastPathComponent
        let uniqueTempURL = Self.partialDirectory().appendingPathComponent("\(uniqueFileName).part")
        let item = DownloadItem(
            fileName: uniqueFileName,
            url: sourceURL.absoluteString,
            sourceURL: sourceURL,
            destinationURL: uniqueDestinationURL,
            tempURL: uniqueTempURL,
            category: resolvedCategory,
            headers: headers,
            cookie: cookie,
            detail: startImmediately ? "Ready" : "Queued",
            proxyURLString: UserDefaults.standard.string(forKey: "Options.defaultProxy") ?? "",
            ytdlpFormatCode: headers[Self.ytdlpFormatHeaderKey] ?? ""
        )
        appendLog(item, "Created task for \(sourceURL.absoluteString)")
        if let preset = headers[Self.sitePresetHeaderKey] {
            appendLog(item, "Applied site preset: \(preset)")
        }

        downloads.insert(item, at: 0)
        store.upsert(item)
        if startImmediately {
            queueRunning = true
            start(item)
        } else {
            queuedItemIDs.insert(item.id)
            item.status = .queued
            item.detail = "Queued. Press Start Queue to begin."
            item.updatedAt = Date()
            store.upsert(item)
            objectWillChange.send()
        }
        return item
    }

    func previewDownload(from rawURL: String, headers: [String: String] = [:], cookie: String? = nil, suggestedFileName: String? = nil) async -> DownloadDraftMetadata {
        guard let sourceURL = Self.normalizedURL(from: rawURL) else {
            return DownloadDraftMetadata(rawURL: rawURL, normalizedURL: nil, fileName: "download", size: "--", totalBytes: nil, category: .all, errorMessage: "Invalid download URL")
        }

        let fallbackFileName = Self.sanitizedFileName(suggestedFileName?.nilIfEmpty ?? Self.fileName(for: sourceURL))
        if Self.isBitTorrentSource(sourceURL) || Self.isED2KSource(sourceURL) {
            return DownloadDraftMetadata(
                rawURL: sourceURL.absoluteString,
                normalizedURL: sourceURL,
                fileName: fallbackFileName,
                size: Self.isED2KSource(sourceURL) ? Self.ed2kSizeText(sourceURL) : "Torrent metadata",
                totalBytes: nil,
                category: Self.isED2KSource(sourceURL) ? .ed2k : .torrent,
                errorMessage: nil
            )
        }

        var requestHeaders = headers
        if requestHeaders["User-Agent"] == nil {
            requestHeaders["User-Agent"] = "FastNativeDownloadManager/0.2"
        }
        do {
            let metadata = try await previewProbe(sourceURL: sourceURL, headers: requestHeaders, cookie: cookie)
            let contentDisposition = metadata.responseHeaders["Content-Disposition"] ?? metadata.responseHeaders["content-disposition"] ?? ""
            let responseFileName = Self.fileName(fromContentDisposition: contentDisposition)
            let rawFileName = Self.sanitizedFileName(responseFileName?.nilIfEmpty ?? fallbackFileName)
            let engineHint = shouldUseYTDLP(for: sourceURL) ? DownloadEngineChoice.ytdlp : DownloadEngineChoice.automatic
            let fileName = Self.fileNameWithDefaultExtension(rawFileName, sourceURL: sourceURL, engine: engineHint)
            return DownloadDraftMetadata(
                rawURL: sourceURL.absoluteString,
                normalizedURL: sourceURL,
                fileName: fileName,
                size: metadata.contentLength > 0 ? Self.byteCount(metadata.contentLength) : "Unknown",
                totalBytes: metadata.contentLength > 0 ? metadata.contentLength : nil,
                category: Self.category(for: fileName),
                errorMessage: nil
            )
        } catch {
            let fileName = Self.fileNameWithDefaultExtension(fallbackFileName, sourceURL: sourceURL, engine: shouldUseYTDLP(for: sourceURL) ? .ytdlp : .automatic)
            return DownloadDraftMetadata(
                rawURL: sourceURL.absoluteString,
                normalizedURL: sourceURL,
                fileName: fileName,
                size: "Unknown",
                totalBytes: nil,
                category: Self.category(for: fileName),
                errorMessage: error.localizedDescription
            )
        }
    }

    func start(_ item: DownloadItem?) {
        guard let item, let sourceURL = item.sourceURL, item.status != .complete else { return }

        if item.requestTimeoutSeconds <= 0 {
            item.requestTimeoutSeconds = Int(requestTimeout)
        }
        if item.retryLimit < 0 {
            item.retryLimit = maximumRetryAttempts
        }
        if item.preferredConnectionCount <= 0 {
            item.preferredConnectionCount = 8
        }

        lock.lock()
        let alreadyRunning = activeTasksByItemID[item.id]?.isEmpty == false
        lock.unlock()
        guard !alreadyRunning else { return }

        if activeDownloadCount >= maximumConcurrentDownloads {
            queuedItemIDs.insert(item.id)
            item.status = .queued
            item.speed = "--"
            item.eta = "Queued"
            item.detail = "Queued. Waiting for an available download slot."
            item.updatedAt = Date()
            store.upsert(item)
            objectWillChange.send()
            return
        }

        item.status = .downloading
        item.detail = "Preparing segmented download..."
        item.speed = "Starting..."
        item.updatedAt = Date()
        store.upsert(item)
        objectWillChange.send()

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.prepareAndStart(item, sourceURL: sourceURL)
        }
    }

    func pause(_ item: DownloadItem?) {
        pause(item, keepInQueue: false)
        scheduleQueue()
    }

    func startQueue() {
        queueRunning = true
        for item in downloads where queuedItemIDs.contains(item.id) && item.sourceURL != nil && item.status == .paused {
            item.status = .queued
            item.speed = "--"
            item.eta = "Queued"
            item.detail = "Queued. Waiting for Start Queue scheduler."
            item.updatedAt = Date()
            store.upsert(item)
        }
        scheduleQueue()
        objectWillChange.send()
    }

    func stopQueue() {
        queueRunning = false
        let queueDownloads = downloads.filter { queuedItemIDs.contains($0.id) && $0.status == .downloading }
        for item in queueDownloads {
            pause(item, keepInQueue: true)
            item.detail = "Queue stopped. Segment progress saved for resume."
            item.updatedAt = Date()
            store.upsert(item)
        }
        objectWillChange.send()
    }

    private func pause(_ item: DownloadItem?, keepInQueue: Bool) {
        guard let item else { return }
        if !keepInQueue {
            queuedItemIDs.remove(item.id)
        }
        cancelTasks(for: item, closingAs: .paused, removePartial: false)
        item.speed = "--"
        item.eta = "--"
        item.detail = keepInQueue ? "Queue stopped. Segment progress saved for resume." : "Paused. Segment progress saved for Range resume."
        item.updatedAt = Date()
        store.upsert(item)
        store.saveSegments(item)
        objectWillChange.send()
    }

    func cancel(_ item: DownloadItem?) {
        guard let item else { return }
        queuedItemIDs.remove(item.id)
        cancelTasks(for: item, closingAs: .canceled, removePartial: true)
        item.downloadedBytes = 0
        item.progress = 0
        item.speed = "--"
        item.eta = "--"
        item.connections = 0
        item.segments = item.segments.map {
            DownloadSegment(id: $0.id, start: $0.start, end: $0.end, downloaded: 0, speed: 0, status: .canceled)
        }
        item.detail = "Canceled. Partial file removed."
        item.updatedAt = Date()
        store.upsert(item)
        store.saveSegments(item)
        objectWillChange.send()
        scheduleQueue()
    }

    func restart(_ item: DownloadItem?) {
        guard let item, item.sourceURL != nil else { return }
        queuedItemIDs.remove(item.id)
        cancelTasks(for: item, closingAs: .queued, removePartial: true)
        try? FileManager.default.removeItem(at: item.destinationURL)
        item.downloadedBytes = 0
        item.totalBytes = nil
        item.progress = 0
        item.size = "--"
        item.speed = "--"
        item.eta = "--"
        item.connections = 0
        item.resumeSupported = false
        item.segments = []
        item.detail = "Restart requested. Starting from byte 0."
        item.updatedAt = Date()
        appendLog(item, "Restart requested. Partial and destination files were cleared.")
        store.upsert(item)
        store.saveSegments(item)
        objectWillChange.send()
        start(item)
    }

    func deleteRecord(_ item: DownloadItem?) {
        guard let item else { return }
        queuedItemIDs.remove(item.id)
        cancelTasks(for: item, closingAs: .canceled, removePartial: true)
        store.delete(itemID: item.id)
        downloads.removeAll { $0.id == item.id }
        objectWillChange.send()
        scheduleQueue()
    }

    func removeCompleted() {
        downloads.removeAll { item in
            let removable = item.status == .complete || item.status == .canceled
            if removable {
                queuedItemIDs.remove(item.id)
                store.delete(itemID: item.id)
            }
            return removable
        }
        scheduleQueue()
    }

    var totalSpeedText: String {
        let total = downloads
            .filter { $0.status == .downloading }
            .flatMap(\.segments)
            .map(\.speed)
            .reduce(0, +)
        return total > 0 ? Self.byteCount(total) + "/s" : "--"
    }

    var queueStatusText: String {
        let queuedCount = downloads.filter { item in
            queuedItemIDs.contains(item.id)
                && item.sourceURL != nil
                && (item.status == .queued || item.status == .paused)
        }.count

        return queueRunning
            ? "Queue: On · \(activeDownloadCount)/\(maximumConcurrentDownloads) active · \(queuedCount) waiting"
            : "Queue: Stopped · max \(maximumConcurrentDownloads)"
    }

    private var activeDownloadCount: Int {
        downloads.filter { item in
            item.sourceURL != nil && (item.status == .downloading || item.status == .verifying)
        }.count
    }

    private func scheduleQueue() {
        guard queueRunning else { return }
        let availableSlots = max(0, maximumConcurrentDownloads - activeDownloadCount)
        guard availableSlots > 0 else { return }

        let candidates = downloads.reversed().filter { item in
            queuedItemIDs.contains(item.id)
                && item.sourceURL != nil
                && (item.status == .queued || item.status == .paused)
        }

        for item in candidates.prefix(availableSlots) {
            start(item)
        }
    }

    private func prepareAndStart(_ item: DownloadItem, sourceURL: URL) async {
        do {
            try FileManager.default.createDirectory(at: item.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.partialDirectory(), withIntermediateDirectories: true)

            let effectiveSourceURL = item.headers[Self.mediaVariantURLHeaderKey].flatMap(URL.init(string:)) ?? sourceURL
            let engine = DownloadEngineChoice(rawValue: item.headers[Self.engineHeaderKey] ?? "") ?? .automatic
            appendLog(item, "Starting with engine \(engine.rawValue). URL: \(effectiveSourceURL.absoluteString)")
            appendLog(item, "Headers: \(Self.loggableHeaders(item.headers))")
            if let cookie = item.cookie, !cookie.isEmpty {
                appendLog(item, "Cookie: present (\(cookie.count) chars)")
            }

            if engine == .bittorrent || (engine == .automatic && Self.isBitTorrentSource(effectiveSourceURL)) {
                appendLog(item, "Dispatching to BitTorrent plugin bridge.")
                try await downloadWithBitTorrent(item: item, sourceURL: effectiveSourceURL)
                return
            }

            if engine == .ed2k || (engine == .automatic && Self.isED2KSource(effectiveSourceURL)) {
                appendLog(item, "Dispatching to eD2K plugin bridge.")
                try await downloadWithED2K(item: item, sourceURL: effectiveSourceURL)
                return
            }

            if let pluginID = item.headers[Self.pluginIDHeaderKey]?.nilIfEmpty,
               let plugin = pluginEngine(id: pluginID) {
                appendLog(item, "Dispatching to manually selected plugin \(plugin.name).")
                try await runPluginEngine(plugin, item: item, sourceURL: effectiveSourceURL)
                return
            }

            if (engine == .automatic || engine == .ytdlp),
               item.headers[Self.sitePresetHeaderKey]?.nilIfEmpty != nil,
               let plugin = pluginEngine(for: effectiveSourceURL) {
                appendLog(item, "Dispatching to plugin engine \(plugin.name).")
                try await runPluginEngine(plugin, item: item, sourceURL: effectiveSourceURL)
                return
            }

            if engine == .ytdlp {
                try await downloadWithYTDLP(item: item, sourceURL: effectiveSourceURL)
                return
            }

            if engine == .ffmpeg {
                try await downloadWithFFmpeg(item: item, sourceURL: effectiveSourceURL)
                return
            }

            if engine == .automatic, shouldUseYTDLP(for: effectiveSourceURL), Self.executablePath(named: "yt-dlp") != nil {
                try await downloadWithYTDLP(item: item, sourceURL: effectiveSourceURL)
                return
            }

            if effectiveSourceURL.pathExtension.lowercased() == "m3u8" {
                if engine == .automatic, Self.executablePath(named: "ffmpeg") != nil {
                    try await downloadWithFFmpeg(item: item, sourceURL: effectiveSourceURL)
                    return
                }
                try await downloadHLS(item: item, playlistURL: effectiveSourceURL)
                return
            }

            if effectiveSourceURL.pathExtension.lowercased() == "mpd" {
                if engine == .automatic, Self.executablePath(named: "ffmpeg") != nil {
                    try await downloadWithFFmpeg(item: item, sourceURL: effectiveSourceURL)
                    return
                }
                try await downloadDASH(item: item, manifestURL: effectiveSourceURL)
                return
            }

            if let expiredMessage = Self.expiredSignedURLMessage(for: effectiveSourceURL) {
                throw DownloadEngineError.http(expiredMessage)
            }

            let avoidRangeRequests = engine == .amazon || Self.shouldAvoidRangeRequests(for: effectiveSourceURL)
            let metadata = avoidRangeRequests
                ? DownloadMetadata(contentLength: 0, acceptsRanges: false, responseHeaders: [:])
                : try await probe(sourceURL: effectiveSourceURL, headers: item.headers, cookie: item.cookie, item: item)
            appendLog(item, "HTTP probe: size \(metadata.contentLength), ranges \(metadata.acceptsRanges ? "yes" : "no").")
            if avoidRangeRequests {
                appendLog(item, "Amazon/Signed URL mode: skipping HEAD probe and using one plain GET connection.")
            }
            let resumeSupported = metadata.acceptsRanges && metadata.contentLength > 0 && !avoidRangeRequests
            if !resumeSupported {
                try? FileManager.default.removeItem(at: item.tempURL)
            }
            let existingSegments = item.segments.filter { $0.length > 0 }
            let segments = resumeSupported
                ? (existingSegments.isEmpty ? Self.makeSegments(totalBytes: metadata.contentLength, preferredCount: item.preferredConnectionCount) : existingSegments)
                : [DownloadSegment(id: 0, start: 0, end: metadata.contentLength > 0 ? metadata.contentLength - 1 : Int64.max - 1, downloaded: 0, speed: 0, status: .queued)]

            let fd = open(item.tempURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else {
                throw POSIXError(.EIO)
            }

            if metadata.contentLength > 0 {
                try Self.preallocate(fileDescriptor: fd, size: metadata.contentLength)
            }

            DispatchQueue.main.async {
                item.totalBytes = metadata.contentLength > 0 ? metadata.contentLength : nil
                item.size = metadata.contentLength > 0 ? Self.byteCount(metadata.contentLength) : "Unknown"
                item.resumeSupported = resumeSupported
                item.segments = segments
                item.connections = resumeSupported ? segments.count : 1
                item.downloadedBytes = segments.map(\.downloaded).reduce(0, +)
                item.progress = metadata.contentLength > 0 ? min(1, Double(item.downloadedBytes) / Double(metadata.contentLength)) : 0
                item.status = .downloading
                item.detail = resumeSupported
                    ? "Receiving data with \(segments.count) HTTP Range connections..."
                    : (avoidRangeRequests ? "Amazon/Signed URL mode; downloading with one plain connection." : "Server does not support Range; downloading with one connection.")
                item.updatedAt = Date()
                self.store.upsert(item)
                self.store.saveSegments(item)
                self.objectWillChange.send()
            }

            registerPreparedItem(item, fileDescriptor: fd, metadata: metadata)

            for segment in segments where !segment.isComplete {
                startSegment(segment, item: item, sourceURL: effectiveSourceURL, fileDescriptor: fd, resumeSupported: resumeSupported)
            }
        } catch {
            DispatchQueue.main.async {
                self.fail(item, message: error.localizedDescription)
            }
        }
    }

    private func downloadWithYTDLP(item: DownloadItem, sourceURL: URL) async throws {
        guard let toolPath = Self.executablePath(named: "yt-dlp") else {
            throw DownloadEngineError.externalToolMissing("yt-dlp is not installed.")
        }

        let outputTemplate = Self.externalOutputTemplate(for: item.destinationURL, preferredExtension: "mp4")
        var arguments = [
            "--no-playlist",
            "--newline",
            "--progress",
            "--merge-output-format", "mp4",
            "--restrict-filenames",
            "--no-part",
            "-o", outputTemplate,
            sourceURL.absoluteString
        ]
        let selectedFormat = item.ytdlpFormatCode.trimmingCharacters(in: .whitespacesAndNewlines)
        arguments.insert(contentsOf: ["-f", selectedFormat.isEmpty ? "bv*+ba/b" : selectedFormat], at: arguments.count - 1)
        if let cookie = item.cookie, !cookie.isEmpty {
            arguments.insert(contentsOf: ["--add-header", "Cookie:\(cookie)"], at: arguments.count - 1)
        }
        if let cookiesFile = UserDefaults.standard.string(forKey: "Options.cookiesFilePath"),
           !cookiesFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.fileExists(atPath: cookiesFile) {
            arguments.insert(contentsOf: ["--cookies", cookiesFile], at: arguments.count - 1)
            appendLog(item, "yt-dlp cookies file: \(cookiesFile)")
        }
        if let browserCookies = UserDefaults.standard.string(forKey: "Options.cookiesFromBrowser"),
           !browserCookies.isEmpty,
           browserCookies != "None" {
            arguments.insert(contentsOf: ["--cookies-from-browser", browserCookies.lowercased()], at: arguments.count - 1)
            appendLog(item, "yt-dlp cookies from browser: \(browserCookies)")
        }
        if let userAgent = item.headers["User-Agent"] {
            arguments.insert(contentsOf: ["--user-agent", userAgent], at: arguments.count - 1)
        }
        if let referer = item.headers["Referer"] {
            arguments.insert(contentsOf: ["--referer", referer], at: arguments.count - 1)
        }
        let ytdlpLimitCandidates: [Int64] = [
            item.speedLimitBytesPerSecond,
            globalSpeedLimitBytesPerSecond,
            queueSpeedLimitBytesPerSecond > 0 && queuedItemIDs.contains(item.id) ? queueSpeedLimitBytesPerSecond : 0,
            Self.timeWindowSpeedLimitBytesPerSecond()
        ]
        let ytdlpLimit = ytdlpLimitCandidates.filter { $0 > 0 }.min() ?? 0
        if ytdlpLimit > 0 {
            arguments.insert(contentsOf: ["--limit-rate", "\(ytdlpLimit)"], at: arguments.count - 1)
        }
        if !item.proxyURLString.isEmpty {
            arguments.insert(contentsOf: ["--proxy", item.proxyURLString], at: arguments.count - 1)
        }

        try await runExternalMediaTool(
            item: item,
            executablePath: toolPath,
            arguments: arguments,
            label: "yt-dlp",
            preferredExtension: "mp4",
            progressParser: Self.parseYTDLPProgress
        )
    }

    private func downloadWithFFmpeg(item: DownloadItem, sourceURL: URL) async throws {
        guard let toolPath = Self.executablePath(named: "ffmpeg") else {
            throw DownloadEngineError.externalToolMissing("ffmpeg is not installed.")
        }

        var headerLines = item.headers
            .filter { !Self.isInternalHeader($0.key) }
            .map { "\($0.key): \($0.value)" }
        if let cookie = item.cookie, !cookie.isEmpty {
            headerLines.append("Cookie: \(cookie)")
        }

        var arguments = ["-y", "-hide_banner", "-stats", "-loglevel", "info"]
        if !item.proxyURLString.isEmpty {
            arguments.append(contentsOf: ["-http_proxy", item.proxyURLString])
        }
        if !headerLines.isEmpty {
            arguments.append(contentsOf: ["-headers", headerLines.joined(separator: "\r\n") + "\r\n"])
        }
        let outputURL = item.destinationURL.pathExtension.isEmpty
            ? item.destinationURL.appendingPathExtension("mp4")
            : item.destinationURL
        if outputURL != item.destinationURL {
            DispatchQueue.main.sync {
                item.destinationURL = outputURL
                item.fileName = outputURL.lastPathComponent
                self.store.upsert(item)
            }
        }
        let audioURL = item.headers[Self.mediaAudioURLHeaderKey].flatMap(URL.init(string:))
        let subtitleURL = item.headers[Self.mediaSubtitleURLHeaderKey].flatMap(URL.init(string:))
        arguments.append(contentsOf: ["-i", sourceURL.absoluteString])
        if let audioURL {
            arguments.append(contentsOf: ["-i", audioURL.absoluteString])
        }
        if let subtitleURL {
            arguments.append(contentsOf: ["-i", subtitleURL.absoluteString])
        }
        if audioURL != nil || subtitleURL != nil {
            arguments.append(contentsOf: ["-map", "0:v?"])
            if audioURL != nil {
                arguments.append(contentsOf: ["-map", "1:a?"])
            } else {
                arguments.append(contentsOf: ["-map", "0:a?"])
            }
            if subtitleURL != nil {
                arguments.append(contentsOf: ["-map", audioURL == nil ? "1:s?" : "2:s?", "-c:s", "mov_text"])
            } else {
                arguments.append(contentsOf: ["-map", "0:s?"])
            }
        }
        arguments.append(contentsOf: ["-c", "copy", outputURL.path])

        try await runExternalMediaTool(
            item: item,
            executablePath: toolPath,
            arguments: arguments,
            label: "ffmpeg",
            preferredExtension: "mp4",
            progressParser: Self.parseFFmpegProgress
        )
    }

    private func downloadWithBitTorrent(item: DownloadItem, sourceURL: URL) async throws {
        guard let toolPath = Self.executablePath(named: "aria2c") else {
            throw DownloadEngineError.externalToolMissing("aria2c is not installed. Install aria2 to enable the BitTorrent plugin.")
        }

        let outputDirectory = item.destinationURL
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let sourceArgument = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
        let trackers = await Self.loadBitTorrentTrackers().joined(separator: ",")
        var arguments = [
            "--dir=\(outputDirectory.path)",
            "--seed-time=0",
            "--follow-torrent=mem",
            "--enable-dht=true",
            "--enable-peer-exchange=true",
            "--bt-enable-lpd=true",
            "--continue=true",
            "--summary-interval=1",
            "--show-console-readout=true",
            "--console-log-level=notice"
        ]
        if !trackers.isEmpty {
            arguments.append("--bt-tracker=\(trackers)")
        }
        arguments.append(sourceArgument)

        try await runExternalBitTorrentTool(
            item: item,
            outputDirectory: outputDirectory,
            executablePath: toolPath,
            arguments: arguments
        )
    }

    private func runExternalBitTorrentTool(
        item: DownloadItem,
        outputDirectory: URL,
        executablePath: String,
        arguments: [String]
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = outputDirectory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        lock.withLock {
            externalProcessesByItemID[item.id] = process
        }

        DispatchQueue.main.async {
            item.resumeSupported = true
            item.connections = 1
            item.detail = "Using BitTorrent plugin with aria2c and public tracker subscriptions..."
            item.speed = "Starting..."
            item.eta = "--"
            item.updatedAt = Date()
            self.store.upsert(item)
            self.objectWillChange.send()
        }

        let startSnapshot = Self.directorySnapshot(outputDirectory)
        let readability = outputPipe.fileHandleForReading
        readability.readabilityHandler = { [weak self, weak item] handle in
            guard let self, let item else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline).map(String.init) {
                if let progress = Self.parseAria2Progress(line) {
                    DispatchQueue.main.async {
                        item.progress = max(item.progress, progress.percent ?? item.progress)
                        item.speed = progress.speed ?? item.speed
                        item.eta = progress.eta ?? item.eta
                        item.detail = "BitTorrent: \(line)"
                        item.updatedAt = Date()
                        self.store.upsert(item)
                        self.objectWillChange.send()
                    }
                }
            }
        }

        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        readability.readabilityHandler = nil

        lock.withLock {
            externalProcessesByItemID[item.id] = nil
        }

        guard process.terminationStatus == 0 else {
            throw DownloadEngineError.externalToolFailed("BitTorrent plugin exited with code \(process.terminationStatus).")
        }

        let finishedSnapshot = Self.directorySnapshot(outputDirectory)
        let downloadedSize = Self.snapshotGrowth(from: startSnapshot, to: finishedSnapshot)

        DispatchQueue.main.async {
            item.status = .complete
            item.progress = 1
            if downloadedSize > 0 {
                item.downloadedBytes = downloadedSize
                item.totalBytes = downloadedSize
                item.size = Self.byteCount(downloadedSize)
            }
            item.speed = "--"
            item.eta = "--"
            item.connections = 0
            item.detail = "BitTorrent plugin saved files to \(outputDirectory.path)"
            item.updatedAt = Date()
            self.queuedItemIDs.remove(item.id)
            self.store.upsert(item)
            self.objectWillChange.send()
            self.runCompletionActions(for: item)
            self.scheduleQueue()
        }
    }

    private func downloadWithED2K(item: DownloadItem, sourceURL: URL) async throws {
        if let ed2kTool = Self.ed2kToolPath() {
            try await runED2KSubmitter(
                item: item,
                executablePath: ed2kTool,
                arguments: [sourceURL.absoluteString],
                label: "ed2k"
            )
            return
        }

        if let amulecmd = Self.executablePath(named: "amulecmd") {
            try await runED2KSubmitter(
                item: item,
                executablePath: amulecmd,
                arguments: ["-c", "Add \(sourceURL.absoluteString)"],
                label: "amulecmd"
            )
            return
        }

        throw DownloadEngineError.externalToolMissing("eD2K plugin needs an installed aMule/eD2K bridge. Install aMule or provide an executable named ed2k/amulecmd.")
    }

    private func runED2KSubmitter(
        item: DownloadItem,
        executablePath: String,
        arguments: [String],
        label: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = item.destinationURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        DispatchQueue.main.async {
            item.status = .downloading
            item.progress = 0
            item.resumeSupported = true
            item.connections = 1
            item.speed = "Submitting..."
            item.eta = "--"
            item.detail = "Submitting eD2K link to \(label)..."
            item.updatedAt = Date()
            self.store.upsert(item)
            self.objectWillChange.send()
        }

        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw DownloadEngineError.externalToolFailed("eD2K plugin failed via \(label): \(output.nilIfEmpty ?? "exit \(process.terminationStatus)")")
        }

        DispatchQueue.main.async {
            item.status = .queued
            item.progress = 0
            item.speed = "--"
            item.eta = "External"
            item.detail = "eD2K link submitted to \(label). Download progress is managed by the eD2K client."
            item.updatedAt = Date()
            self.queuedItemIDs.remove(item.id)
            self.store.upsert(item)
            self.objectWillChange.send()
            self.scheduleQueue()
        }
    }

    private func pluginEngine(for sourceURL: URL) -> RuntimePluginManifest? {
        let pluginFolder = Self.pluginDirectory()
        let disabledIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.disabledIDs") ?? [])
        let trustedIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.trustedIDs") ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(at: pluginFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(RuntimePluginManifest.self, from: data),
                  !disabledIDs.contains(manifest.id),
                  trustedIDs.contains(manifest.id) || manifest.id.hasPrefix("builtin."),
                  manifest.engineCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  plugin(manifest, matches: sourceURL) else {
                continue
            }
            return manifest
        }
        return nil
    }

    private func pluginEngine(id pluginID: String) -> RuntimePluginManifest? {
        let pluginFolder = Self.pluginDirectory()
        let disabledIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.disabledIDs") ?? [])
        let trustedIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.trustedIDs") ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(at: pluginFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(RuntimePluginManifest.self, from: data),
                  manifest.id == pluginID,
                  !disabledIDs.contains(manifest.id),
                  trustedIDs.contains(manifest.id) || manifest.id.hasPrefix("builtin."),
                  manifest.engineCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }
            return manifest
        }
        return nil
    }

    private func plugin(_ manifest: RuntimePluginManifest, matches sourceURL: URL) -> Bool {
        let ext = sourceURL.pathExtension.lowercased()
        let scheme = sourceURL.scheme?.lowercased() ?? ""
        let urlString = sourceURL.absoluteString.lowercased()

        let patternMatches = (manifest.urlPatterns ?? []).contains {
            Self.urlString(urlString, host: sourceURL.host?.lowercased(), matchesPluginPattern: $0)
        }

        if manifest.kind?.lowercased() == "extractor" {
            return patternMatches
        }

        if manifest.kind?.lowercased() == "engine", scheme == "http" || scheme == "https" {
            return !ext.isEmpty && manifest.fileExtensions?.map({ $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }).contains(ext) == true
        }

        if scheme != "http", scheme != "https",
           manifest.protocols?.map({ $0.lowercased() }).contains(scheme) == true {
            return true
        }

        if !ext.isEmpty, manifest.fileExtensions?.map({ $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }).contains(ext) == true {
            return true
        }

        return patternMatches
    }

    private func runPluginEngine(_ plugin: RuntimePluginManifest, item: DownloadItem, sourceURL: URL) async throws {
        guard let command = plugin.engineCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw DownloadEngineError.externalToolMissing("Plugin \(plugin.name) has no engineCommand.")
        }
        try RuntimePluginSecurityPolicy.validate(plugin, command: command)
        appendPluginAudit("engine start plugin=\(plugin.id) item=\(item.id.uuidString) url=\(sourceURL.absoluteString) command=\(command)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = item.destinationURL.deletingLastPathComponent()
        process.environment = RuntimePluginSecurityPolicy.sanitizedEnvironment(
            for: item,
            sourceURL: sourceURL,
            allowCookies: Set(plugin.permissions ?? []).contains("cookies") || plugin.id.hasPrefix("builtin.")
        )
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        lock.withLock {
            externalProcessesByItemID[item.id] = process
        }

        DispatchQueue.main.async {
            item.status = .downloading
            item.detail = "Plugin \(plugin.name) running..."
            item.speed = "Plugin"
            self.appendLog(item, "Plugin \(plugin.name) engine command: \(command)")
            self.store.upsert(item)
        }

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self, weak item] readable in
            guard let self, let item else { return }
            let data = readable.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                for line in text.split(whereSeparator: \.isNewline).map(String.init) {
                    self.appendLog(item, "Plugin \(plugin.name): \(line)")
                    self.appendPluginAudit("engine output plugin=\(plugin.id) item=\(item.id.uuidString) line=\(line)")
                    item.detail = "Plugin \(plugin.name): \(line)"
                }
                self.objectWillChange.send()
            }
        }

        try process.run()
        let timeout = max(30, UserDefaults.standard.object(forKey: "Plugins.executionTimeoutSeconds") as? Int ?? 1800)
        let timedOut = await waitForExternalProcess(process, timeout: TimeInterval(timeout))
        lock.withLock {
            externalProcessesByItemID[item.id] = nil
        }
        handle.readabilityHandler = nil

        if timedOut {
            appendPluginAudit("engine timeout plugin=\(plugin.id) item=\(item.id.uuidString) after=\(timeout)s")
            throw DownloadEngineError.externalToolFailed("Plugin \(plugin.name) timed out after \(timeout) seconds.")
        }

        guard process.terminationStatus == 0 else {
            appendPluginAudit("engine failed plugin=\(plugin.id) item=\(item.id.uuidString) status=\(process.terminationStatus)")
            throw DownloadEngineError.externalToolFailed("Plugin \(plugin.name) exited with code \(process.terminationStatus).")
        }
        appendPluginAudit("engine complete plugin=\(plugin.id) item=\(item.id.uuidString)")

        let finalSize = Self.fileSize(at: item.destinationURL)
        DispatchQueue.main.async {
            item.status = finalSize > 0 ? .complete : .queued
            item.progress = finalSize > 0 ? 1 : item.progress
            item.downloadedBytes = max(item.downloadedBytes, finalSize)
            item.totalBytes = finalSize > 0 ? finalSize : item.totalBytes
            item.size = finalSize > 0 ? Self.byteCount(finalSize) : item.size
            item.speed = "--"
            item.eta = "--"
            item.detail = finalSize > 0 ? "Plugin \(plugin.name) saved to \(item.destinationURL.path)" : "Plugin \(plugin.name) completed. External engine may still be running."
            self.appendLog(item, item.detail)
            self.queuedItemIDs.remove(item.id)
            self.store.upsert(item)
            self.objectWillChange.send()
            if item.status == .complete {
                self.runCompletionActions(for: item)
            }
            self.scheduleQueue()
        }
    }

    private func waitForExternalProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = ExternalProcessWaitState()

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

    private func appendPluginAudit(_ message: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let folder = appSupport.appendingPathComponent("Fast Native Download Manager", isDirectory: true)
        let url = folder.appendingPathComponent("plugin-audit.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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

    private func runExternalMediaTool(
        item: DownloadItem,
        executablePath: String,
        arguments: [String],
        label: String,
        preferredExtension: String? = nil,
        progressParser: @escaping @Sendable (String) -> ExternalToolProgress?
    ) async throws {
        try? FileManager.default.removeItem(at: item.destinationURL)
        let startingSnapshot = Self.directorySnapshot(item.destinationURL.deletingLastPathComponent())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = item.destinationURL.deletingLastPathComponent()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        lock.withLock {
            externalProcessesByItemID[item.id] = process
        }

        DispatchQueue.main.async {
            item.resumeSupported = false
            item.connections = 1
            item.detail = "Using \(label) bridge..."
            item.speed = "Starting..."
            item.eta = "--"
            item.updatedAt = Date()
            self.appendLog(item, "\(label) command: \(executablePath) \(arguments.joined(separator: " "))")
            self.store.upsert(item)
            self.objectWillChange.send()
        }

        let readability = outputPipe.fileHandleForReading
        readability.readabilityHandler = { [weak self, weak item] handle in
            guard let self, let item else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline).map(String.init) {
                if let progress = progressParser(line) {
                    DispatchQueue.main.async {
                        item.progress = max(item.progress, progress.percent ?? item.progress)
                        item.speed = progress.speed ?? item.speed
                        item.eta = progress.eta ?? item.eta
                        item.detail = "\(label): \(line)"
                        self.appendLog(item, "\(label): \(line)")
                        item.updatedAt = Date()
                        self.store.upsert(item)
                        self.objectWillChange.send()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.appendLog(item, "\(label): \(line)")
                    }
                }
            }
        }

        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        readability.readabilityHandler = nil

        lock.withLock {
            externalProcessesByItemID[item.id] = nil
        }

        guard process.terminationStatus == 0 else {
            DispatchQueue.main.async {
                self.appendLog(item, "\(label) exited with code \(process.terminationStatus)")
            }
            throw DownloadEngineError.externalToolFailed("\(label) exited with code \(process.terminationStatus).")
        }

        var finalURL = Self.resolveExternalOutputURL(
            preferred: item.destinationURL,
            directory: item.destinationURL.deletingLastPathComponent(),
            before: startingSnapshot,
            preferredExtension: preferredExtension
        )
        if finalURL.pathExtension.isEmpty, let preferredExtension {
            let renamedURL = finalURL.appendingPathExtension(preferredExtension)
            if !FileManager.default.fileExists(atPath: renamedURL.path) {
                try? FileManager.default.moveItem(at: finalURL, to: renamedURL)
                finalURL = renamedURL
            }
        }

        let finalSize = Self.fileSize(at: finalURL)
        guard finalSize > 0 else {
            throw DownloadEngineError.externalToolFailed("\(label) finished but no output file was created.")
        }

        DispatchQueue.main.async {
            item.destinationURL = finalURL
            item.fileName = finalURL.lastPathComponent
            item.status = .complete
            item.progress = 1
            item.downloadedBytes = finalSize
            item.totalBytes = finalSize
            item.size = Self.byteCount(finalSize)
            item.speed = "--"
            item.eta = "--"
            item.connections = 0
            item.detail = "\(label) bridge saved to \(finalURL.path)"
            item.updatedAt = Date()
            self.queuedItemIDs.remove(item.id)
            self.store.upsert(item)
            self.objectWillChange.send()
            self.runCompletionActions(for: item)
            self.scheduleQueue()
        }
    }

    private func probe(sourceURL: URL, headers: [String: String], cookie: String?, item: DownloadItem? = nil) async throws -> DownloadMetadata {
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = requestTimeout
        headers
            .filter { !Self.isInternalHeader($0.key) }
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (_, response) = try await (item.map { session(for: $0) } ?? URLSession.shared).data(for: request)
            return try Self.parseMetadataResponse(response, sourceURL: sourceURL)
        } catch let error as DownloadEngineError {
            throw error
        } catch {
            throw DownloadEngineError.network(Self.networkFailureMessage(error, context: "Metadata probe"))
        }
    }

    private func previewProbe(sourceURL: URL, headers: [String: String], cookie: String?) async throws -> DownloadMetadata {
        guard Self.shouldUseAmazonS3Mode(for: sourceURL) else {
            return try await probe(sourceURL: sourceURL, headers: headers, cookie: cookie)
        }
        if let expirationMessage = Self.expiredSignedURLMessage(for: sourceURL) {
            throw DownloadEngineError.http(expirationMessage)
        }
        if let metadata = try? await rangePreviewProbe(sourceURL: sourceURL, headers: headers, cookie: cookie) {
            return metadata
        }
        return DownloadMetadata(contentLength: 0, acceptsRanges: false, responseHeaders: [:])
    }

    private func rangePreviewProbe(sourceURL: URL, headers: [String: String], cookie: String?) async throws -> DownloadMetadata {
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        headers
            .filter { !Self.isInternalHeader($0.key) }
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let response = try await Self.headerOnlyResponse(for: request)
            return try Self.parseMetadataResponse(response, sourceURL: sourceURL)
        } catch let error as DownloadEngineError {
            throw error
        } catch {
            throw DownloadEngineError.network(Self.networkFailureMessage(error, context: "Range metadata probe"))
        }
    }

    private func downloadHLS(item: DownloadItem, playlistURL: URL) async throws {
        let mediaPlaylist = try await resolveHLSMediaPlaylist(from: playlistURL, item: item)
        let segmentURLs = try Self.hlsSegmentURLs(from: mediaPlaylist.text, baseURL: mediaPlaylist.url)
        guard !segmentURLs.isEmpty else {
            throw DownloadEngineError.mediaManifest("HLS playlist does not contain downloadable media segments.")
        }

        try? FileManager.default.removeItem(at: item.tempURL)
        FileManager.default.createFile(atPath: item.tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: item.tempURL)
        defer { try? handle.close() }

        DispatchQueue.main.async {
            item.totalBytes = nil
            item.size = "HLS stream"
            item.resumeSupported = false
            item.connections = 1
            item.detail = "Parsing HLS playlist. \(segmentURLs.count) segment(s) queued for merge."
            item.updatedAt = Date()
            self.store.upsert(item)
            self.objectWillChange.send()
        }

        var downloadedBytes: Int64 = 0
        for (index, segmentURL) in segmentURLs.enumerated() {
            try Task.checkCancellation()
            guard item.status == .downloading else { throw DownloadEngineError.mediaManifest("HLS download stopped.") }
            let data = try await mediaData(from: segmentURL, item: item)
            try handle.write(contentsOf: data)
            downloadedBytes += Int64(data.count)
            let currentBytes = downloadedBytes

            DispatchQueue.main.async {
                item.downloadedBytes = currentBytes
                item.progress = Double(index + 1) / Double(segmentURLs.count)
                item.size = Self.byteCount(currentBytes)
                item.speed = "Merging"
                item.eta = "\(segmentURLs.count - index - 1) segment(s)"
                item.detail = "Downloading HLS segment \(index + 1)/\(segmentURLs.count)..."
                item.updatedAt = Date()
                self.store.upsert(item)
                self.objectWillChange.send()
            }
        }

        try finishMergedMedia(item: item, downloadedBytes: downloadedBytes, detail: "HLS segments merged and saved to \(item.destinationURL.path)")
    }

    private func resolveHLSMediaPlaylist(from playlistURL: URL, item: DownloadItem) async throws -> (url: URL, text: String) {
        let text = try await mediaText(from: playlistURL, item: item)
        if text.localizedCaseInsensitiveContains("#EXT-X-KEY"), !text.localizedCaseInsensitiveContains("METHOD=NONE") {
            throw DownloadEngineError.protectedMedia("Encrypted HLS playlist detected. DRM/encrypted media is not supported.")
        }

        let variants = Self.hlsVariants(from: text, baseURL: playlistURL)
        guard let bestVariant = variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
            return (playlistURL, text)
        }

        let mediaText = try await mediaText(from: bestVariant.url, item: item)
        if mediaText.localizedCaseInsensitiveContains("#EXT-X-KEY"), !mediaText.localizedCaseInsensitiveContains("METHOD=NONE") {
            throw DownloadEngineError.protectedMedia("Encrypted HLS variant detected. DRM/encrypted media is not supported.")
        }
        return (bestVariant.url, mediaText)
    }

    private func downloadDASH(item: DownloadItem, manifestURL: URL) async throws {
        let manifest = try await mediaText(from: manifestURL, item: item)
        if manifest.localizedCaseInsensitiveContains("ContentProtection") {
            throw DownloadEngineError.protectedMedia("DASH ContentProtection detected. DRM media is not supported.")
        }

        let segmentURLs = try Self.dashSegmentURLs(from: manifest, baseURL: manifestURL)
        guard !segmentURLs.isEmpty else {
            throw DownloadEngineError.mediaManifest("This MPD uses a DASH layout that is not supported yet. SegmentList/BaseURL is supported in this build.")
        }

        try? FileManager.default.removeItem(at: item.tempURL)
        FileManager.default.createFile(atPath: item.tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: item.tempURL)
        defer { try? handle.close() }

        var downloadedBytes: Int64 = 0
        for (index, segmentURL) in segmentURLs.enumerated() {
            try Task.checkCancellation()
            guard item.status == .downloading else { throw DownloadEngineError.mediaManifest("DASH download stopped.") }
            let data = try await mediaData(from: segmentURL, item: item)
            try handle.write(contentsOf: data)
            downloadedBytes += Int64(data.count)
            let currentBytes = downloadedBytes

            DispatchQueue.main.async {
                item.downloadedBytes = currentBytes
                item.progress = Double(index + 1) / Double(segmentURLs.count)
                item.size = Self.byteCount(currentBytes)
                item.speed = "Merging"
                item.eta = "\(segmentURLs.count - index - 1) segment(s)"
                item.detail = "Downloading DASH segment \(index + 1)/\(segmentURLs.count)..."
                item.updatedAt = Date()
                self.store.upsert(item)
                self.objectWillChange.send()
            }
        }

        try finishMergedMedia(item: item, downloadedBytes: downloadedBytes, detail: "DASH fragments merged and saved to \(item.destinationURL.path)")
    }

    private func mediaText(from url: URL, item: DownloadItem) async throws -> String {
        let data = try await mediaData(from: url, item: item)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw DownloadEngineError.mediaManifest("Media manifest is not valid text: \(url.absoluteString)")
        }
        return text
    }

    private func mediaData(from url: URL, item: DownloadItem) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(max(1, item.requestTimeoutSeconds))
        item.headers
            .filter { !Self.isInternalHeader($0.key) }
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookie = item.cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session(for: item).data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw DownloadEngineError.http(Self.httpFailureMessage(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, url: url))
            }
            return data
        } catch let error as DownloadEngineError {
            throw error
        } catch {
            throw DownloadEngineError.network(Self.networkFailureMessage(error, context: "Media segment"))
        }
    }

    private func finishMergedMedia(item: DownloadItem, downloadedBytes: Int64, detail: String) throws {
        if FileManager.default.fileExists(atPath: item.destinationURL.path) {
            try FileManager.default.removeItem(at: item.destinationURL)
        }
        try FileManager.default.moveItem(at: item.tempURL, to: item.destinationURL)

        DispatchQueue.main.async {
            item.status = .complete
            item.progress = 1
            item.downloadedBytes = downloadedBytes
            item.totalBytes = downloadedBytes
            item.size = Self.byteCount(downloadedBytes)
            item.speed = "--"
            item.eta = "--"
            item.connections = 0
            item.detail = detail
            item.updatedAt = Date()
            self.queuedItemIDs.remove(item.id)
            self.store.upsert(item)
            self.objectWillChange.send()
            self.scheduleQueue()
        }
    }

    private static func parseMetadataResponse(_ response: URLResponse, sourceURL: URL) throws -> DownloadMetadata {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadEngineError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DownloadEngineError.http(Self.httpFailureMessage(statusCode: httpResponse.statusCode, url: sourceURL))
        }

        let contentLength = Self.contentLength(from: httpResponse, fallback: response.expectedContentLength)
        let acceptsRanges = (httpResponse.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
        let responseHeaders = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
        return DownloadMetadata(contentLength: contentLength, acceptsRanges: acceptsRanges, responseHeaders: responseHeaders)
    }

    private static func contentLength(from response: HTTPURLResponse, fallback: Int64) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let totalText = contentRange.split(separator: "/").last,
           totalText != "*",
           let total = Int64(totalText) {
            return total
        }
        return Int64(response.value(forHTTPHeaderField: "Content-Length") ?? "") ?? max(0, fallback)
    }

    private static func headerOnlyResponse(for request: URLRequest) async throws -> URLResponse {
        let delegate = HeaderOnlyProbeDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.setContinuation(continuation)
            session.dataTask(with: request).resume()
        }
    }

    private func startSegment(_ segment: DownloadSegment, item: DownloadItem, sourceURL: URL, fileDescriptor: Int32, resumeSupported: Bool) {
        guard !segment.isComplete else { return }

        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(max(1, item.requestTimeoutSeconds))
        item.headers
            .filter { !Self.isInternalHeader($0.key) }
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let cookie = item.cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let start = segment.offset
        if resumeSupported {
            request.setValue("bytes=\(start)-\(segment.end)", forHTTPHeaderField: "Range")
        }

        let task = session(for: item).dataTask(with: request)
        let transfer = SegmentTransfer(
            item: item,
            segment: segment,
            fileDescriptor: fileDescriptor,
            resumeSupported: resumeSupported,
            limitProvider: { [weak self, weak item] in
                guard let self, let item else { return 0 }
                return self.effectiveSpeedLimit(for: item)
            }
        )

        lock.lock()
        segmentTransfers[task.taskIdentifier] = transfer
        activeTasksByItemID[item.id, default: []].insert(task)
        lock.unlock()

        task.resume()
    }

    private func registerPreparedItem(_ item: DownloadItem, fileDescriptor: Int32, metadata: DownloadMetadata) {
        lock.lock()
        fileHandlesByItemID[item.id] = fileDescriptor
        metadataByItemID[item.id] = metadata
        activeTasksByItemID[item.id] = []
        lock.unlock()
    }

    private func cancelTasks(for item: DownloadItem, closingAs status: DownloadStatus, removePartial: Bool) {
        lock.lock()
        let tasks = activeTasksByItemID[item.id] ?? []
        activeTasksByItemID[item.id] = nil
        let externalProcess = externalProcessesByItemID[item.id]
        externalProcessesByItemID[item.id] = nil
        for task in tasks {
            segmentTransfers[task.taskIdentifier]?.close()
            segmentTransfers[task.taskIdentifier] = nil
        }
        let fd = fileHandlesByItemID[item.id]
        fileHandlesByItemID[item.id] = nil
        metadataByItemID[item.id] = nil
        retryAttemptsBySegment = retryAttemptsBySegment.filter { $0.key.itemID != item.id }
        lock.unlock()

        tasks.forEach { $0.cancel() }
        externalProcess?.terminate()
        if let fd {
            close(fd)
        }
        if removePartial {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
        item.status = status
        item.connections = 0
    }

    private func finishIfNeeded(for item: DownloadItem) {
        guard let totalBytes = item.totalBytes, totalBytes > 0, item.segments.allSatisfy(\.isComplete) else {
            return
        }

        lock.lock()
        let tasks = activeTasksByItemID[item.id] ?? []
        let fd = fileHandlesByItemID[item.id]
        activeTasksByItemID[item.id] = nil
        fileHandlesByItemID[item.id] = nil
        metadataByItemID[item.id] = nil
        lock.unlock()

        guard tasks.isEmpty else { return }
        if let fd {
            fsync(fd)
            close(fd)
        }

        do {
            item.status = .verifying
            item.speed = "Verifying"
            item.eta = "--"
            item.detail = "Verifying downloaded file size..."
            item.updatedAt = Date()
            store.upsert(item)
            objectWillChange.send()

            let actualPartialSize = Self.fileSize(at: item.tempURL)
            guard actualPartialSize == totalBytes else {
                throw DownloadEngineError.sizeMismatch(expected: totalBytes, actual: actualPartialSize, path: item.tempURL.path)
            }

            if FileManager.default.fileExists(atPath: item.destinationURL.path) {
                try FileManager.default.removeItem(at: item.destinationURL)
            }
            try FileManager.default.moveItem(at: item.tempURL, to: item.destinationURL)
            let finalSize = Self.fileSize(at: item.destinationURL)
            guard finalSize == totalBytes else {
                throw DownloadEngineError.sizeMismatch(expected: totalBytes, actual: finalSize, path: item.destinationURL.path)
            }

            item.status = .complete
            item.progress = 1
            item.downloadedBytes = totalBytes
            item.speed = "--"
            item.eta = "--"
            item.connections = 0
            item.detail = "Merged and saved to \(item.destinationURL.path)"
            item.updatedAt = Date()
            queuedItemIDs.remove(item.id)
            retryAttemptsBySegment = retryAttemptsBySegment.filter { $0.key.itemID != item.id }
            appendLog(item, "Complete. Saved to \(item.destinationURL.path)")
            store.upsert(item)
            store.saveSegments(item)
            objectWillChange.send()
            runCompletionActions(for: item)
            scheduleQueue()
        } catch {
            fail(item, message: error.localizedDescription)
        }
    }

    private func finishSingleConnectionDownload(for item: DownloadItem) {
        lock.lock()
        let tasks = activeTasksByItemID[item.id] ?? []
        let fd = fileHandlesByItemID[item.id]
        activeTasksByItemID[item.id] = nil
        fileHandlesByItemID[item.id] = nil
        metadataByItemID[item.id] = nil
        lock.unlock()

        guard tasks.isEmpty else { return }
        if let fd {
            fsync(fd)
            close(fd)
        }

        do {
            let actualPartialSize = Self.fileSize(at: item.tempURL)
            if let expected = item.totalBytes, expected > 0, actualPartialSize != expected {
                throw DownloadEngineError.sizeMismatch(expected: expected, actual: actualPartialSize, path: item.tempURL.path)
            }
            if FileManager.default.fileExists(atPath: item.destinationURL.path) {
                try FileManager.default.removeItem(at: item.destinationURL)
            }
            try FileManager.default.moveItem(at: item.tempURL, to: item.destinationURL)
            let finalSize = Self.fileSize(at: item.destinationURL)

            item.status = .complete
            item.progress = 1
            item.downloadedBytes = finalSize
            item.totalBytes = finalSize
            item.size = Self.byteCount(finalSize)
            item.speed = "--"
            item.eta = "--"
            item.connections = 0
            item.detail = "Saved to \(item.destinationURL.path)"
            item.updatedAt = Date()
            queuedItemIDs.remove(item.id)
            retryAttemptsBySegment = retryAttemptsBySegment.filter { $0.key.itemID != item.id }
            appendLog(item, "Complete. Saved to \(item.destinationURL.path)")
            store.upsert(item)
            store.saveSegments(item)
            objectWillChange.send()
            runCompletionActions(for: item)
            scheduleQueue()
        } catch {
            fail(item, message: error.localizedDescription)
        }
    }

    private func fail(_ item: DownloadItem, message: String) {
        queuedItemIDs.remove(item.id)
        cancelTasks(for: item, closingAs: .failed, removePartial: false)
        item.speed = "--"
        item.eta = "--"
        item.detail = "Failed: \(message)"
        appendLog(item, "Failed: \(message)")
        item.updatedAt = Date()
        store.upsert(item)
        store.saveSegments(item)
        notify(title: "Download Failed", body: "\(item.fileName): \(message)", identifier: "\(item.id.uuidString)-failed")
        objectWillChange.send()
        scheduleQueue()
    }

    private func retryOrFail(_ transfer: SegmentTransfer, message: String, retryable: Bool) {
        let item = transfer.item
        let segmentID = transfer.segmentID
        let snapshot = transfer.snapshot()

        guard retryable, item.status == .downloading || item.status == .verifying else {
            DispatchQueue.main.async {
                self.fail(item, message: message)
            }
            return
        }

        let key = SegmentRetryKey(itemID: item.id, segmentID: segmentID)
        lock.lock()
        let attempt = (retryAttemptsBySegment[key] ?? 0) + 1
        retryAttemptsBySegment[key] = attempt
        let fd = fileHandlesByItemID[item.id]
        lock.unlock()

        let retryLimit = max(0, item.retryLimit)
        guard attempt <= retryLimit, let fd, let sourceURL = item.sourceURL else {
            DispatchQueue.main.async {
                self.fail(item, message: "\(message). Retried \(min(attempt - 1, retryLimit)) time(s).")
            }
            return
        }

        let delay = min(8.0, pow(2.0, Double(attempt - 1)))
        DispatchQueue.main.async {
            if let index = item.segments.firstIndex(where: { $0.id == segmentID }) {
                item.segments[index].downloaded = snapshot.downloaded
                item.segments[index].speed = 0
                item.segments[index].status = .queued
            }
            item.downloadedBytes = item.segments.map(\.downloaded).reduce(0, +)
            if let totalBytes = item.totalBytes, totalBytes > 0 {
                item.progress = min(1, Double(item.downloadedBytes) / Double(totalBytes))
            }
            item.status = .downloading
            item.speed = "Retrying..."
            item.detail = "Retrying connection \(segmentID + 1)/\(item.segments.count) in \(Self.timeText(seconds: delay)) after: \(message) (attempt \(attempt)/\(retryLimit))"
            self.appendLog(item, "Retry \(attempt)/\(retryLimit) for connection \(segmentID + 1): \(message)")
            item.updatedAt = Date()
            self.store.upsert(item)
            self.store.saveSegments(item)
            self.objectWillChange.send()
        }

        Task.detached(priority: .userInitiated) { [weak self, weak item] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, let item, item.status == .downloading else { return }
            DispatchQueue.main.async {
                guard let currentSegment = item.segments.first(where: { $0.id == segmentID }), !currentSegment.isComplete else {
                    self.finishIfNeeded(for: item)
                    return
                }
                self.startSegment(currentSegment, item: item, sourceURL: sourceURL, fileDescriptor: fd, resumeSupported: transfer.resumeSupported)
            }
        }
    }

    func saveTaskSettings(_ item: DownloadItem) {
        item.updatedAt = Date()
        store.upsert(item)
        objectWillChange.send()
    }

    func appendLog(_ item: DownloadItem, _ message: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak item] in
                guard let self, let item else { return }
                self.appendLog(item, message)
            }
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        if item.logLines.count > 400 {
            item.logLines.removeFirst(item.logLines.count - 400)
        }
        item.logLines.append(line)
    }

    private func effectiveSpeedLimit(for item: DownloadItem) -> Int64 {
        let candidates = [
            item.speedLimitBytesPerSecond,
            globalSpeedLimitBytesPerSecond,
            queueSpeedLimitBytesPerSecond > 0 && queuedItemIDs.contains(item.id) ? queueSpeedLimitBytesPerSecond : 0,
            Self.timeWindowSpeedLimitBytesPerSecond()
        ].filter { $0 > 0 }
        guard let minimum = candidates.min() else { return 0 }
        let activeConnections = downloads
            .filter { $0.status == .downloading }
            .map { max(1, $0.connections) }
            .reduce(0, +)
        return max(1, minimum / Int64(max(1, activeConnections)))
    }

    private static func timeWindowSpeedLimitBytesPerSecond(now: Date = Date()) -> Int64 {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "Options.timeLimitEnabled") else { return 0 }
        let rawLimit = defaults.object(forKey: "Options.timeLimitBytesPerSecond")
        let limit = (rawLimit as? Int64) ?? Int64(rawLimit as? Int ?? 0)
        guard limit > 0 else { return 0 }

        let startMinutes = defaults.integer(forKey: "Options.timeLimitStartMinutes")
        let endMinutes = defaults.integer(forKey: "Options.timeLimitEndMinutes")
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if startMinutes <= endMinutes {
            return (current >= startMinutes && current <= endMinutes) ? limit : 0
        }
        return (current >= startMinutes || current <= endMinutes) ? limit : 0
    }

    private func runCompletionActions(for item: DownloadItem) {
        guard item.status == .complete else { return }

        if item.verifySHA256WhenComplete, FileManager.default.fileExists(atPath: item.destinationURL.path) {
            Task.detached(priority: .utility) { [weak self, weak item] in
                guard let self, let item else { return }
                let hash = Self.sha256Hex(at: item.destinationURL) ?? "unavailable"
                DispatchQueue.main.async {
                    item.detail += " · SHA256: \(hash)"
                    self.store.upsert(item)
                    self.objectWillChange.send()
                }
            }
        }

        if item.verifyMD5WhenComplete, FileManager.default.fileExists(atPath: item.destinationURL.path) {
            Task.detached(priority: .utility) { [weak self, weak item] in
                guard let self, let item else { return }
                let hash = Self.md5Hex(at: item.destinationURL) ?? "unavailable"
                DispatchQueue.main.async {
                    item.detail += " · MD5: \(hash)"
                    self.store.upsert(item)
                    self.objectWillChange.send()
                }
            }
        }

        if item.autoMoveCategoryWhenComplete {
            autoMoveCompletedFile(item)
        }

        if item.revealWhenComplete {
            NSWorkspace.shared.activateFileViewerSelecting([item.destinationURL])
        }

        if item.openWhenComplete {
            NSWorkspace.shared.open(item.destinationURL)
        }

        if item.runPluginActionWhenComplete {
            runPluginCompletionActions(for: item)
            item.detail += " · Plugin completion actions checked."
            store.upsert(item)
        }

        notify(title: "Download Complete", body: item.fileName, identifier: item.id.uuidString)

        if item.sleepWhenComplete {
            runSystemCommand("/usr/bin/pmset", arguments: ["sleepnow"])
        }

        if item.shutdownWhenComplete {
            runSystemCommand("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to shut down"])
        }
    }

    private func autoMoveCompletedFile(_ item: DownloadItem) {
        guard item.category != .all, item.category != .torrent, item.category != .ed2k else { return }
        let targetDirectory = Self.downloadDirectory().appendingPathComponent(item.category.rawValue, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let targetURL = Self.uniqueDestinationURL(for: targetDirectory.appendingPathComponent(item.destinationURL.lastPathComponent))
            try FileManager.default.moveItem(at: item.destinationURL, to: targetURL)
            item.destinationURL = targetURL
            item.fileName = targetURL.lastPathComponent
            item.detail = "Moved to \(targetURL.path)"
            store.upsert(item)
        } catch {
            item.detail += " · Auto move failed: \(error.localizedDescription)"
            store.upsert(item)
        }
    }

    private func runSystemCommand(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }

    private func notify(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func transfer(for taskIdentifier: Int) -> SegmentTransfer? {
        lock.lock()
        defer { lock.unlock() }
        return segmentTransfers[taskIdentifier]
    }

    private func removeTransfer(task: URLSessionTask) -> SegmentTransfer? {
        lock.lock()
        let transfer = segmentTransfers[task.taskIdentifier]
        if let transfer {
            segmentTransfers[task.taskIdentifier] = nil
            activeTasksByItemID[transfer.item.id]?.remove(task as! URLSessionDataTask)
        }
        lock.unlock()
        return transfer
    }
}

extension DownloadManager: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .allow
        }
        guard let transfer = transfer(for: dataTask.taskIdentifier) else {
            return .cancel
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = Self.httpFailureMessage(statusCode: httpResponse.statusCode, url: transfer.item.sourceURL)
            transfer.markFailure(message, retryable: Self.isRetryableHTTPStatus(httpResponse.statusCode))
            dataTask.cancel()
            return .cancel
        }

        if transfer.resumeSupported, httpResponse.statusCode != 206 {
            transfer.markFailure("Server ignored Range request; segmented download stopped to avoid corrupting the file.", retryable: false)
            dataTask.cancel()
            return .cancel
        }

        if !transfer.resumeSupported {
            let contentLength = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "") ?? max(0, response.expectedContentLength)
            if contentLength > 0 {
                DispatchQueue.main.async {
                    let item = transfer.item
                    item.totalBytes = contentLength
                    item.size = Self.byteCount(contentLength)
                    if let index = item.segments.firstIndex(where: { $0.id == transfer.segmentID }) {
                        let current = item.segments[index]
                        item.segments[index] = DownloadSegment(
                            id: current.id,
                            start: current.start,
                            end: contentLength - 1,
                            downloaded: min(current.downloaded, contentLength),
                            speed: current.speed,
                            status: current.status
                        )
                    }
                    self.store.upsert(item)
                    self.store.saveSegments(item)
                    self.objectWillChange.send()
                }
            }
        }

        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfer(for: dataTask.taskIdentifier) else { return }

        do {
            try transfer.write(data)
        } catch {
            dataTask.cancel()
            DispatchQueue.main.async {
                self.fail(transfer.item, message: error.localizedDescription)
            }
            return
        }

        let snapshot = transfer.snapshot()
        DispatchQueue.main.async {
            let item = transfer.item
            guard let index = item.segments.firstIndex(where: { $0.id == snapshot.segmentID }) else { return }
            item.segments[index].downloaded = snapshot.downloaded
            item.segments[index].speed = snapshot.bytesPerSecond
            item.segments[index].status = .downloading
            item.downloadedBytes = item.segments.map(\.downloaded).reduce(0, +)

            if let totalBytes = item.totalBytes, totalBytes > 0 {
                item.progress = min(1, Double(item.downloadedBytes) / Double(totalBytes))
                let remaining = max(0, totalBytes - item.downloadedBytes)
                let totalSpeed = item.segments.map(\.speed).reduce(0, +)
                item.speed = totalSpeed > 0 ? Self.byteCount(totalSpeed) + "/s" : "--"
                item.eta = totalSpeed > 0 ? Self.timeText(seconds: Double(remaining) / Double(totalSpeed)) : "--"
            }

            item.status = .downloading
            item.detail = "Receiving data..."
            item.updatedAt = Date()
            self.store.upsert(item)
            self.store.saveSegments(item)
            self.objectWillChange.send()
        }
    }

    private func runPluginCompletionActions(for item: DownloadItem) {
        let pluginFolder = Self.pluginDirectory()
        let disabledIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.disabledIDs") ?? [])
        let trustedIDs = Set(UserDefaults.standard.stringArray(forKey: "Plugins.trustedIDs") ?? [])
        let folders = (try? FileManager.default.contentsOfDirectory(at: pluginFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(RuntimePluginManifest.self, from: data),
                  let action = manifest.completionAction?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !action.isEmpty,
                  !["reveal", "notify"].contains(action.lowercased()),
                  !disabledIDs.contains(manifest.id),
                  trustedIDs.contains(manifest.id) || manifest.id.hasPrefix("builtin.") else {
                continue
            }

            let permissions = Set(manifest.permissions ?? [])
            let isCompletionPlugin = manifest.kind?.lowercased() == "completion" || permissions.contains("completion-action")
            guard isCompletionPlugin else {
                continue
            }

            let process = Process()
            process.currentDirectoryURL = folder
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", action]
            let sourceURL = item.sourceURL ?? URL(string: item.url) ?? item.destinationURL
            process.environment = RuntimePluginSecurityPolicy.sanitizedEnvironment(
                for: item,
                sourceURL: sourceURL,
                allowCookies: permissions.contains("cookies") || manifest.id.hasPrefix("builtin.")
            ).merging([
                "FNDM_FILE": item.destinationURL.path,
                "FNDM_OUTPUT": item.destinationURL.path,
                "FNDM_OUTPUT_DIR": item.destinationURL.deletingLastPathComponent().path,
                "FNDM_URL": item.url,
                "FNDM_NAME": item.fileName,
                "FNDM_CATEGORY": item.category.rawValue
            ], uniquingKeysWith: { _, new in new })
            do {
                appendLog(item, "Plugin \(manifest.name) completion action: \(action)")
                try process.run()
            } catch {
                appendLog(item, "Plugin \(manifest.name) action failed: \(error.localizedDescription)")
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let transfer = removeTransfer(task: task) else { return }

        if let failure = transfer.failure() {
            transfer.close()
            retryOrFail(transfer, message: failure.message, retryable: failure.retryable)
            return
        }

        if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled {
            return
        }

        if let error {
            transfer.close()
            retryOrFail(transfer, message: Self.networkFailureMessage(error, context: "Connection \(transfer.segmentID + 1)"), retryable: Self.isRetryableNetworkError(error))
            return
        }

        let snapshot = transfer.snapshot()
        transfer.close()
        DispatchQueue.main.async {
            let item = transfer.item
            self.lock.lock()
            self.retryAttemptsBySegment[SegmentRetryKey(itemID: item.id, segmentID: snapshot.segmentID)] = nil
            self.lock.unlock()

            if !transfer.resumeSupported {
                self.finishSingleConnectionDownload(for: item)
                return
            }

            if let index = item.segments.firstIndex(where: { $0.id == snapshot.segmentID }) {
                item.segments[index].downloaded = item.segments[index].length
                item.segments[index].speed = 0
                item.segments[index].status = .complete
            }
            item.downloadedBytes = item.segments.map(\.downloaded).reduce(0, +)
            if let totalBytes = item.totalBytes, totalBytes > 0 {
                item.progress = min(1, Double(item.downloadedBytes) / Double(totalBytes))
            }
            item.updatedAt = Date()
            self.store.upsert(item)
            self.store.saveSegments(item)
            self.finishIfNeeded(for: item)
        }
    }
}

private final class SegmentTransfer: @unchecked Sendable {
    let item: DownloadItem
    let segmentID: Int
    let fileDescriptor: Int32
    let resumeSupported: Bool

    private let lock = NSLock()
    private var segment: DownloadSegment
    private var recentBytes: Int64 = 0
    private var recentDate = Date()
    private var currentSpeed: Int64 = 0
    private let mappedAddress: UnsafeMutableRawPointer?
    private let mappedLength: Int
    private var failureMessage: String?
    private var failureRetryable = false
    private let limitProvider: () -> Int64

    init(item: DownloadItem, segment: DownloadSegment, fileDescriptor: Int32, resumeSupported: Bool, limitProvider: @escaping () -> Int64) {
        self.item = item
        self.segment = segment
        self.segmentID = segment.id
        self.fileDescriptor = fileDescriptor
        self.resumeSupported = resumeSupported
        self.limitProvider = limitProvider
        if let totalBytes = item.totalBytes, totalBytes > 0, totalBytes <= Int64(Int.max) {
            let length = Int(totalBytes)
            let address = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
            if address == MAP_FAILED {
                self.mappedAddress = nil
                self.mappedLength = 0
            } else {
                self.mappedAddress = address
                self.mappedLength = length
            }
        } else {
            self.mappedAddress = nil
            self.mappedLength = 0
        }
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            if let mappedAddress, segment.offset + Int64(data.count) <= Int64(mappedLength), segment.offset <= Int64(Int.max) {
                memcpy(mappedAddress.advanced(by: Int(segment.offset)), baseAddress, data.count)
                return
            }

            var written = 0
            while written < data.count {
                let offset = segment.offset + Int64(written)
                let result = pwrite(fileDescriptor, baseAddress.advanced(by: written), data.count - written, off_t(offset))
                if result < 0 {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += result
            }
        }

        lock.lock()
        let count = Int64(data.count)
        segment.downloaded = min(segment.length, segment.downloaded + count)
        recentBytes += count
        let now = Date()
        let elapsed = now.timeIntervalSince(recentDate)
        if elapsed >= 0.35 {
            currentSpeed = Int64(Double(recentBytes) / elapsed)
            recentBytes = 0
            recentDate = now
        }
        lock.unlock()
        applySpeedLimitIfNeeded(bytesWritten: count)
    }

    private func applySpeedLimitIfNeeded(bytesWritten: Int64) {
        let limit = limitProvider()
        guard limit > 0, bytesWritten > 0 else { return }
        let expected = Double(bytesWritten) / Double(max(1, limit))
        if expected > 0.002 {
            Thread.sleep(forTimeInterval: min(0.25, expected))
        }
    }

    func snapshot() -> SegmentSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SegmentSnapshot(segmentID: segment.id, downloaded: segment.downloaded, bytesPerSecond: currentSpeed)
    }

    func markFailure(_ message: String, retryable: Bool) {
        lock.lock()
        failureMessage = message
        failureRetryable = retryable
        lock.unlock()
    }

    func failure() -> SegmentFailure? {
        lock.lock()
        defer { lock.unlock() }
        guard let failureMessage else { return nil }
        return SegmentFailure(message: failureMessage, retryable: failureRetryable)
    }

    func close() {
        if let mappedAddress, mappedLength > 0 {
            msync(mappedAddress, mappedLength, MS_ASYNC)
            munmap(mappedAddress, mappedLength)
        }
    }
}

private struct SegmentSnapshot {
    let segmentID: Int
    let downloaded: Int64
    let bytesPerSecond: Int64
}

private struct SegmentFailure {
    let message: String
    let retryable: Bool
}

private struct SegmentRetryKey: Hashable {
    let itemID: UUID
    let segmentID: Int
}

struct ExternalToolProgress: Sendable {
    let percent: Double?
    let speed: String?
    let eta: String?
}

private struct DownloadMetadata: Sendable {
    let contentLength: Int64
    let acceptsRanges: Bool
    let responseHeaders: [String: String]
}

private final class HeaderOnlyProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?

    func setContinuation(_ continuation: CheckedContinuation<URLResponse, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        finish(with: .success(response))
        return .cancel
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<URLResponse, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum DownloadEngineError: LocalizedError {
    case invalidResponse
    case http(String)
    case network(String)
    case allocationFailed(String)
    case sizeMismatch(expected: Int64, actual: Int64, path: String)
    case mediaManifest(String)
    case protectedMedia(String)
    case externalToolMissing(String)
    case externalToolFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid HTTP response"
        case .http(let message): message
        case .network(let message): message
        case .allocationFailed(let message): message
        case .sizeMismatch(let expected, let actual, let path):
            "File size verification failed for \(path). Expected \(DownloadManager.byteCount(expected)), got \(DownloadManager.byteCount(actual))."
        case .mediaManifest(let message): message
        case .protectedMedia(let message): message
        case .externalToolMissing(let message): message
        case .externalToolFailed(let message): message
        }
    }
}

struct HLSVariant {
    let url: URL
    let bandwidth: Int
}

extension DownloadManager {
    static func makeSegments(totalBytes: Int64, preferredCount: Int) -> [DownloadSegment] {
        guard totalBytes > 0 else { return [] }
        let count = max(1, min(preferredCount, Int(totalBytes / 1_048_576) + 1))
        let chunk = Int64(ceil(Double(totalBytes) / Double(count)))
        return (0..<count).map { index in
            let start = Int64(index) * chunk
            let end = min(totalBytes - 1, start + chunk - 1)
            return DownloadSegment(id: index, start: start, end: end, downloaded: 0, speed: 0, status: .queued)
        }
    }

    static func preallocate(fileDescriptor fd: Int32, size: Int64) throws {
        guard size > 0 else { return }

        var store = fstore_t(
            fst_flags: UInt32(F_ALLOCATECONTIG),
            fst_posmode: Int32(F_PEOFPOSMODE),
            fst_offset: 0,
            fst_length: off_t(size),
            fst_bytesalloc: 0
        )

        if fcntl(fd, F_PREALLOCATE, &store) == -1 {
            store.fst_flags = UInt32(F_ALLOCATEALL)
            _ = fcntl(fd, F_PREALLOCATE, &store)
        }

        if ftruncate(fd, off_t(size)) != 0 {
            throw DownloadEngineError.allocationFailed("ftruncate failed: \(String(cString: strerror(errno)))")
        }
    }

    static func hlsVariants(from playlist: String, baseURL: URL) -> [HLSVariant] {
        let lines = playlist.split(whereSeparator: \.isNewline).map(String.init)
        var variants: [HLSVariant] = []
        for index in lines.indices where lines[index].hasPrefix("#EXT-X-STREAM-INF") {
            let bandwidth = attribute("BANDWIDTH", in: lines[index]).flatMap(Int.init) ?? 0
            guard index + 1 < lines.count,
                  let url = URL(string: lines[index + 1], relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            variants.append(HLSVariant(url: url, bandwidth: bandwidth))
        }
        return variants
    }

    static func hlsSegmentURLs(from playlist: String, baseURL: URL) throws -> [URL] {
        playlist
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
    }

    static func dashSegmentURLs(from manifest: String, baseURL: URL) throws -> [URL] {
        let base = firstRegexCapture("<BaseURL>([^<]+)</BaseURL>", in: manifest)
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL } ?? baseURL
        var urls: [URL] = []

        for value in regexCaptures(#"sourceURL="([^"]+)""#, in: manifest) {
            if let url = URL(string: value, relativeTo: base)?.absoluteURL {
                urls.append(url)
            }
        }

        for value in regexCaptures(#"media="([^"]+)""#, in: manifest) {
            guard !value.contains("$Number$"), let url = URL(string: value, relativeTo: base)?.absoluteURL else {
                continue
            }
            urls.append(url)
        }

        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }

    static func attribute(_ name: String, in line: String) -> String? {
        firstRegexCapture("\(name)=([^,]+)", in: line)
    }

    static func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        regexCaptures(pattern, in: text).first
    }

    static func regexCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    static func executablePath(named name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func shouldUseYTDLP(for url: URL) -> Bool {
        Self.shouldUseYTDLPHost(url)
    }

    static func shouldUseYTDLPHost(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        if host == "imdb.com" || host.hasSuffix(".imdb.com") {
            return isIMDbVideoURL(url)
        }
        let mediaHosts = [
            "youtube.com", "youtu.be", "bilibili.com", "vimeo.com",
            "x.com", "twitter.com", "instagram.com", "tiktok.com",
            "facebook.com", "fb.watch", "twitch.tv", "dailymotion.com", "dai.ly",
            "reddit.com", "redd.it", "soundcloud.com", "pinterest.com", "linkedin.com"
        ]
        return mediaHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func isIMDbVideoURL(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        guard host == "imdb.com" || host.hasSuffix(".imdb.com") else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/video/") || path.hasPrefix("/videoplayer/")
    }

    static func parseYTDLPProgress(_ line: String) -> ExternalToolProgress? {
        guard line.contains("[download]") || line.contains("ETA") else { return nil }
        let percent = firstRegexCapture(#"(\d+(?:\.\d+)?)%"#, in: line).flatMap(Double.init).map { $0 / 100.0 }
        let speed = firstRegexCapture(#"at\s+([^\s]+/s)"#, in: line)
        let eta = firstRegexCapture(#"ETA\s+([^\s]+)"#, in: line)
        return ExternalToolProgress(percent: percent, speed: speed, eta: eta)
    }

    static func parseFFmpegProgress(_ line: String) -> ExternalToolProgress? {
        guard line.contains("time=") || line.contains("speed=") else { return nil }
        let speed = firstRegexCapture(#"speed=\s*([^\s]+)"#, in: line).map { "speed \($0)" }
        let eta = firstRegexCapture(#"time=\s*([^\s]+)"#, in: line)
        return ExternalToolProgress(percent: nil, speed: speed, eta: eta)
    }

    static func parseAria2Progress(_ line: String) -> ExternalToolProgress? {
        guard line.contains("[#") || line.localizedCaseInsensitiveContains("download complete") else { return nil }
        let percent = firstRegexCapture(#"\((\d+(?:\.\d+)?)%\)"#, in: line).flatMap(Double.init).map { $0 / 100.0 }
        let speed = firstRegexCapture(#"DL:([^\s\]]+)"#, in: line).map { "\($0)/s" }
        let eta = firstRegexCapture(#"ETA:([^\s\]]+)"#, in: line)
        if percent == nil, speed == nil, eta == nil {
            return line.localizedCaseInsensitiveContains("download complete")
                ? ExternalToolProgress(percent: 1, speed: nil, eta: "--")
                : nil
        }
        return ExternalToolProgress(percent: percent, speed: speed, eta: eta)
    }

    static func fileNameWithDefaultExtension(_ fileName: String, sourceURL: URL, engine: DownloadEngineChoice) -> String {
        let sanitized = sanitizedFileName(fileName)
        guard URL(fileURLWithPath: sanitized).pathExtension.isEmpty else {
            return sanitized
        }

        if isBitTorrentSource(sourceURL) {
            return sanitized.hasSuffix(".torrent") ? sanitized : "\(sanitized).torrent"
        }

        if isED2KSource(sourceURL) {
            return sanitized
        }

        if engine == .ytdlp || shouldUseYTDLPHost(sourceURL) {
            return "\(sanitized).mp4"
        }

        let ext = sourceURL.pathExtension.lowercased()
        if engine == .ffmpeg || ["m3u8", "mpd"].contains(ext) {
            return "\(sanitized).mp4"
        }

        return sanitized
    }

    static func sitePreset(for url: URL) -> SiteDownloadPreset? {
        let host = url.host?.lowercased() ?? ""
        if shouldUseAmazonS3Mode(for: url) {
            return SiteDownloadPreset(name: "Amazon S3", engine: .amazon, ytdlpFormat: "")
        }
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return SiteDownloadPreset(name: "YouTube", engine: .ytdlp, ytdlpFormat: "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b")
        }
        if host.contains("bilibili.com") || host.contains("b23.tv") {
            return SiteDownloadPreset(name: "Bilibili", engine: .ytdlp, ytdlpFormat: "bv*+ba/b")
        }
        if host.contains("tiktok.com") || host.contains("tiktokv.com") || host.contains("tiktokcdn.com") {
            return SiteDownloadPreset(name: "TikTok", engine: .ytdlp, ytdlpFormat: "bv*+ba/b")
        }
        if isIMDbVideoURL(url) {
            return SiteDownloadPreset(name: "IMDb", engine: .ytdlp, ytdlpFormat: "bv*+ba/b")
        }
        if host.contains("instagram.com") || host.contains("cdninstagram.com") {
            return SiteDownloadPreset(name: "Instagram", engine: .ytdlp, ytdlpFormat: "bv*+ba/b")
        }
        return nil
    }

    static func urlString(_ urlString: String, host: String?, matchesPluginPattern pattern: String) -> Bool {
        let lowered = pattern.lowercased()
        let regex = "^" + NSRegularExpression
            .escapedPattern(for: lowered)
            .replacingOccurrences(of: "\\*", with: ".*") + "$"
        return urlString.range(of: regex, options: [.regularExpression]) != nil
    }

    static func loggableHeaders(_ headers: [String: String]) -> String {
        headers
            .filter { key, _ in key.lowercased() != "cookie" }
            .map { key, value in
                let redacted = key.lowercased().contains("authorization") ? "<redacted>" : value
                return "\(key): \(redacted)"
            }
            .sorted()
            .joined(separator: "; ")
    }

    static func externalOutputTemplate(for destinationURL: URL, preferredExtension: String) -> String {
        destinationURL.pathExtension.isEmpty ? destinationURL.path + ".%(ext)s" : destinationURL.path
    }

    static func resolveExternalOutputURL(
        preferred: URL,
        directory: URL,
        before: [String: Int64],
        preferredExtension: String?
    ) -> URL {
        if FileManager.default.fileExists(atPath: preferred.path), fileSize(at: preferred) > 0 {
            return preferred
        }

        let preferredBase = preferred.deletingPathExtension().lastPathComponent
        let preferredName = preferred.lastPathComponent
        let after = directorySnapshot(directory)
        let candidates = after.compactMap { path, size -> (url: URL, size: Int64, growth: Int64)? in
            guard size > 0 else { return nil }
            let growth = max(0, size - (before[path] ?? 0))
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let matchesName = name == preferredName || name.hasPrefix("\(preferredName).") || name.hasPrefix("\(preferredBase).")
            let matchesExtension = preferredExtension.map { url.pathExtension.caseInsensitiveCompare($0) == .orderedSame } ?? false
            guard matchesName || (matchesExtension && growth > 0) else { return nil }
            return (url, size, growth)
        }

        return candidates
            .sorted { left, right in
                if left.growth != right.growth { return left.growth > right.growth }
                return left.size > right.size
            }
            .first?.url ?? preferred
    }

    static func sampleDownloads() -> [DownloadItem] {
        let base = downloadDirectory()
        let partial = partialDirectory()
        return [
            DownloadItem(fileName: "Xcode_26.0_beta.xip", url: "https://developer.apple.com/download/all", sourceURL: nil, destinationURL: base.appendingPathComponent("Xcode_26.0_beta.xip"), tempURL: partial.appendingPathComponent("Xcode_26.0_beta.xip.part"), category: .app, size: "13.2 GB", speed: "48.6 MB/s", eta: "03:42", connections: 8, progress: 0.72, status: .downloading, downloadedBytes: 9_660_000_000, totalBytes: 13_200_000_000, resumeSupported: true, detail: "Preview task", segments: makeSegments(totalBytes: 13_200_000_000, preferredCount: 8).enumerated().map { index, segment in DownloadSegment(id: index, start: segment.start, end: segment.end, downloaded: Int64(Double(segment.length) * 0.72), speed: 6_000_000, status: .downloading) }),
            DownloadItem(fileName: "WWDC26-session-1080p.mp4", url: "https://videos.example-cdn.com/hls/master.m3u8", sourceURL: nil, destinationURL: base.appendingPathComponent("WWDC26-session-1080p.mp4"), tempURL: partial.appendingPathComponent("WWDC26-session-1080p.mp4.part"), category: .video, size: "2.8 GB", speed: "22.1 MB/s", eta: "01:18", connections: 8, progress: 0.54, status: .downloading, downloadedBytes: 1_512_000_000, totalBytes: 2_800_000_000, resumeSupported: true, detail: "Preview task"),
            DownloadItem(fileName: "Design-System-Assets.zip", url: "https://assets.company.com/releases/latest", sourceURL: nil, destinationURL: base.appendingPathComponent("Design-System-Assets.zip"), tempURL: partial.appendingPathComponent("Design-System-Assets.zip.part"), category: .archive, size: "940 MB", eta: "--", connections: 0, progress: 0.31, status: .paused, downloadedBytes: 291_000_000, totalBytes: 940_000_000, resumeSupported: true, detail: "Preview task"),
            DownloadItem(fileName: "Research-paper.pdf", url: "https://arxiv.org/pdf/2605.10231", sourceURL: nil, destinationURL: base.appendingPathComponent("Research-paper.pdf"), tempURL: partial.appendingPathComponent("Research-paper.pdf.part"), category: .document, size: "18 MB", eta: "--", progress: 1, status: .complete, downloadedBytes: 18_000_000, totalBytes: 18_000_000, resumeSupported: true, detail: "Preview task"),
            DownloadItem(fileName: "NativeDM-nightly.dmg", url: "https://releases.fastdm.app/mac/nightly", sourceURL: nil, destinationURL: base.appendingPathComponent("NativeDM-nightly.dmg"), tempURL: partial.appendingPathComponent("NativeDM-nightly.dmg.part"), category: .app, size: "124 MB", speed: "Verifying", eta: "--", connections: 1, progress: 0.96, status: .verifying, downloadedBytes: 119_000_000, totalBytes: 124_000_000, resumeSupported: true, detail: "Preview task"),
            DownloadItem(fileName: "Dataset-part-07.tar.zst", url: "https://storage.example.org/public/dataset", sourceURL: nil, destinationURL: base.appendingPathComponent("Dataset-part-07.tar.zst"), tempURL: partial.appendingPathComponent("Dataset-part-07.tar.zst.part"), category: .archive, size: "4.6 GB", speed: "--", eta: "Queued", connections: 0, progress: 0, status: .queued, downloadedBytes: 0, totalBytes: 4_600_000_000, resumeSupported: true, detail: "Preview task")
        ]
    }

    static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("magnet:") {
            return URL(string: trimmed)
        }
        if trimmed.lowercased().hasPrefix("ed2k://") {
            return URL(string: trimmed)
        }
        if trimmed.lowercased().hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.pathExtension.lowercased() == "torrent" else { return nil }
            return url
        }
        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed)
            return fileURL.pathExtension.lowercased() == "torrent" ? fileURL : nil
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    static func fileName(for url: URL) -> String {
        if url.scheme?.lowercased() == "magnet" {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let displayName = queryItems.first(where: { $0.name == "dn" })?.value, !displayName.isEmpty {
                return sanitizedFileName(displayName.hasSuffix(".torrent") ? displayName : "\(displayName).torrent")
            }
            if let hash = queryItems.first(where: { $0.name == "xt" })?.value?.split(separator: ":").last {
                return sanitizedFileName("magnet-\(hash.prefix(12)).torrent")
            }
            return "magnet-download.torrent"
        }
        if url.scheme?.lowercased() == "ed2k" {
            return sanitizedFileName(ed2kFileName(url) ?? "ed2k-download")
        }
        if url.isFileURL {
            return sanitizedFileName(url.lastPathComponent.isEmpty ? "local.torrent" : url.lastPathComponent)
        }
        if let fileName = contentDispositionFileName(in: url) {
            return sanitizedFileName(fileName)
        }
        let candidate = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !candidate.isEmpty, candidate != "/" {
            return sanitizedFileName(candidate)
        }
        return sanitizedFileName(url.host ?? "download")
    }

    static func fileNamePreviewFallback(for string: String) -> String {
        guard let url = normalizedURL(from: string) else { return "download" }
        return fileName(for: url)
    }

    static func contentDispositionFileName(in url: URL) -> String? {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let values = queryItems
            .filter { ["response-content-disposition", "rscd"].contains($0.name.lowercased()) }
            .compactMap(\.value)
        for value in values {
            if let fileName = fileName(fromContentDisposition: value) { return fileName }
        }
        return nil
    }

    static func fileName(fromContentDisposition value: String) -> String? {
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for part in parts {
            let lowercased = part.lowercased()
            if lowercased.hasPrefix("filename*="), let range = part.range(of: "''") {
                return String(part[range.upperBound...]).removingPercentEncoding
            }
            if lowercased.hasPrefix("filename=") {
                let rawValue = part.dropFirst("filename=".count)
                return rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "download" : cleaned
    }

    static func category(for fileName: String) -> Category {
        switch fileName.lowercased().split(separator: ".").last.map(String.init) {
        case "torrent": .torrent
        case "ed2k": .ed2k
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst": .archive
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "ppt", "pptx", "epub": .document
        case "mp4", "m4v", "mov", "mkv", "webm", "m3u8", "mpd", "m4s", "avi", "flv": .video
        case "mp3", "flac", "aac", "m4a", "wav", "ogg", "opus": .audio
        case "dmg", "pkg", "app", "xip", "exe", "msi": .app
        default: .all
        }
    }

    static func isBitTorrentSource(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "magnet" {
            return true
        }
        return url.pathExtension.lowercased() == "torrent"
    }

    static func isED2KSource(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "ed2k"
    }

    static func ed2kFileName(_ url: URL) -> String? {
        let parts = url.absoluteString.components(separatedBy: "|")
        guard parts.count >= 4, parts[1].lowercased() == "file" else { return nil }
        return parts[2].removingPercentEncoding
    }

    static func ed2kSizeText(_ url: URL) -> String {
        let parts = url.absoluteString.components(separatedBy: "|")
        guard parts.count >= 4, let size = Int64(parts[3]) else { return "eD2K metadata" }
        return byteCount(size)
    }

    static func ed2kToolPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/ed2k",
            "/usr/local/bin/ed2k",
            "/usr/bin/ed2k",
            "/Applications/aMule.app/Contents/MacOS/ed2k"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func defaultBitTorrentTrackerSources() -> [String] {
        [
            "https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/best.txt",
            "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt"
        ]
    }

    static func fallbackBitTorrentTrackerSources() -> [String] {
        [
            "https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all.txt",
            "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
        ]
    }

    static func loadBitTorrentTrackers() async -> [String] {
        var trackers: [String] = []
        for source in defaultBitTorrentTrackerSources() {
            guard let url = URL(string: source),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            trackers.append(contentsOf: parseTrackerList(text))
        }

        if trackers.count < 20 {
            for source in fallbackBitTorrentTrackerSources() {
                guard let url = URL(string: source),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                      let text = String(data: data, encoding: .utf8) else {
                    continue
                }
                trackers.append(contentsOf: parseTrackerList(text))
            }
        }

        let uniqueTrackers = Array(NSOrderedSet(array: trackers).compactMap { $0 as? String }).prefix(220)
        if !uniqueTrackers.isEmpty {
            return Array(uniqueTrackers)
        }

        return [
            "udp://tracker.opentrackr.org:1337/announce",
            "udp://open.stealth.si:80/announce",
            "udp://tracker.torrent.eu.org:451/announce",
            "udp://tracker.openbittorrent.com:6969/announce",
            "https://tracker.lilithraws.org:443/announce"
        ]
    }

    static func parseTrackerList(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n\r,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tracker in
                guard let scheme = URL(string: tracker)?.scheme?.lowercased() else { return false }
                return ["http", "https", "udp", "ws", "wss"].contains(scheme)
            }
    }

    static func uniqueDestinationURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 1...9999 {
            let candidateName = ext.isEmpty ? "\(baseName) (\(index))" : "\(baseName) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }

    static func sha256Hex(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func md5Hex(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func directorySnapshot(_ directory: URL) -> [String: Int64] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var snapshot: [String: Int64] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            snapshot[url.path] = Int64(values.fileSize ?? 0)
        }
        return snapshot
    }

    static func snapshotGrowth(from before: [String: Int64], to after: [String: Int64]) -> Int64 {
        after.reduce(Int64(0)) { total, entry in
            total + max(0, entry.value - (before[entry.key] ?? 0))
        }
    }

    static func downloadDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "Options.saveDirectory"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return downloads.appendingPathComponent("Fast Native Download Manager", isDirectory: true)
    }

    static func partialDirectory() -> URL {
        downloadDirectory().appendingPathComponent(".partial", isDirectory: true)
    }

    static func databaseURL() -> URL {
        downloadDirectory().appendingPathComponent("tasks.sqlite")
    }

    static func pluginDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? downloadDirectory()
        return support
            .appendingPathComponent("Fast Native Download Manager", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    static func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func timeText(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func httpFailureMessage(statusCode: Int, url: URL?) -> String {
        if statusCode == 618, let url, let expiration = signedURLExpiration(in: url) {
            if expiration <= Date() {
                return "HTTP 618: this signed GitHub asset URL expired at \(signedURLExpirationText(expiration)). Open the release page and copy a fresh download link."
            }
            return "HTTP 618: this signed GitHub asset URL was rejected before its expiry at \(signedURLExpirationText(expiration)). Open the release page and copy a fresh download link."
        }
        if [401, 403].contains(statusCode), let url, let expiration = signedURLExpiration(in: url) {
            if expiration <= Date() {
                return "HTTP \(statusCode): this signed download URL expired at \(signedURLExpirationText(expiration)). Copy a fresh link from the source page."
            }
            return "HTTP \(statusCode): the server rejected this signed download URL before its expiry at \(signedURLExpirationText(expiration)). Copy a fresh link from the source page."
        }
        return "HTTP \(statusCode)"
    }

    static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
    }

    static func isRetryableNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return true }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed,
             NSURLErrorSecureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func networkFailureMessage(_ error: Error, context: String) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "\(context) timed out after waiting for the server."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "\(context) failed because the host could not be resolved."
            case NSURLErrorCannotConnectToHost:
                return "\(context) failed because the host refused the connection."
            case NSURLErrorNetworkConnectionLost:
                return "\(context) lost the network connection."
            case NSURLErrorNotConnectedToInternet:
                return "\(context) failed because the Mac is offline."
            case NSURLErrorSecureConnectionFailed:
                return "\(context) failed because HTTPS negotiation failed."
            default:
                return "\(context) failed: \(error.localizedDescription)"
            }
        }
        return "\(context) failed: \(error.localizedDescription)"
    }

    static func expiredSignedURLMessage(for url: URL, now: Date = Date()) -> String? {
        guard let expiration = signedURLExpiration(in: url), expiration <= now else {
            return nil
        }
        return "Signed download URL expired at \(signedURLExpirationText(expiration)). Copy a fresh link from the source page."
    }

    static func shouldAvoidRangeRequests(for url: URL) -> Bool {
        shouldUseAmazonS3Mode(for: url) || isAzureSignedURL(url)
    }

    static func isInternalHeader(_ name: String) -> Bool {
        name.lowercased().hasPrefix("x-fndm-")
    }

    static func shouldUseAmazonS3Mode(for url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "s3.amazonaws.com" || host.hasSuffix(".s3.amazonaws.com") || host.contains(".s3.") {
            return true
        }
        if host.hasSuffix(".r2.cloudflarestorage.com") || host.hasSuffix(".r2.dev") {
            return true
        }
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        let names = Set(queryItems.map { $0.name.lowercased() })
        if names.contains("awsaccesskeyid") && names.contains("signature") {
            return true
        }
        if names.contains("x-amz-signature") || names.contains("x-amz-credential") || names.contains("x-amz-security-token") {
            return true
        }
        return false
    }

    static func isAzureSignedURL(_ url: URL) -> Bool {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        let names = Set(queryItems.map { $0.name.lowercased() })
        if names.contains("se") && (names.contains("sig") || names.contains("sp") || names.contains("sv")) {
            return true
        }
        return false
    }

    static func signedURLExpiration(in url: URL) -> Date? {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        func queryValue(_ name: String) -> String? {
            queryItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        if let value = queryValue("Expires"), let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let dateValue = queryValue("X-Amz-Date"),
           let validSecondsValue = queryValue("X-Amz-Expires"),
           let validSeconds = TimeInterval(validSecondsValue) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if let start = formatter.date(from: dateValue) {
                return start.addingTimeInterval(validSeconds)
            }
        }

        guard let value = queryValue("se") else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func signedURLExpirationText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private final class DownloadTaskStore {
    private let lock = NSLock()
    private var db: OpaquePointer?

    init() {
        try? FileManager.default.createDirectory(at: DownloadManager.downloadDirectory(), withIntermediateDirectories: true)
        sqlite3_open(DownloadManager.databaseURL().path, &db)
        execute("""
        CREATE TABLE IF NOT EXISTS downloads (
          id TEXT PRIMARY KEY,
          url TEXT,
          file_name TEXT,
          status TEXT,
          progress REAL,
          downloaded INTEGER,
          total INTEGER,
          connections INTEGER,
          resume_supported INTEGER,
          destination TEXT,
          temp TEXT,
          headers TEXT,
          cookie TEXT,
          resume_data TEXT,
          created_at REAL,
          updated_at REAL
        );
        """)
        execute("ALTER TABLE downloads ADD COLUMN resume_data TEXT DEFAULT ''")
        execute("ALTER TABLE downloads ADD COLUMN speed_limit INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN open_on_complete INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN reveal_on_complete INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN sleep_on_complete INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN shutdown_on_complete INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN verify_sha256 INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN auto_move_category INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN run_plugin_action INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN verify_md5 INTEGER DEFAULT 0")
        execute("ALTER TABLE downloads ADD COLUMN proxy TEXT DEFAULT ''")
        execute("ALTER TABLE downloads ADD COLUMN retry_limit INTEGER DEFAULT 3")
        execute("ALTER TABLE downloads ADD COLUMN request_timeout INTEGER DEFAULT 30")
        execute("ALTER TABLE downloads ADD COLUMN preferred_connections INTEGER DEFAULT 8")
        execute("ALTER TABLE downloads ADD COLUMN ytdlp_format TEXT DEFAULT ''")
        execute("ALTER TABLE downloads ADD COLUMN media_format_summary TEXT DEFAULT ''")
        execute("ALTER TABLE downloads ADD COLUMN category TEXT DEFAULT ''")
        execute("""
        CREATE TABLE IF NOT EXISTS segments (
          download_id TEXT,
          idx INTEGER,
          start INTEGER,
          end INTEGER,
          downloaded INTEGER,
          status TEXT,
          PRIMARY KEY(download_id, idx)
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    func loadDownloads() -> [DownloadItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
        SELECT id,url,file_name,status,progress,downloaded,total,connections,resume_supported,
               destination,temp,headers,cookie,created_at,updated_at,
               speed_limit,open_on_complete,reveal_on_complete,sleep_on_complete,shutdown_on_complete,
               verify_sha256,auto_move_category,run_plugin_action,verify_md5,proxy,retry_limit,request_timeout,preferred_connections,
               ytdlp_format,media_format_summary,category
        FROM downloads ORDER BY updated_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var items: [DownloadItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)),
                  let sourceURL = URL(string: text(statement, 1)) else { continue }

            let fileName = text(statement, 2)
            let status = DownloadStatus(rawValue: text(statement, 3)) ?? .queued
            let progress = sqlite3_column_double(statement, 4)
            let downloaded = sqlite3_column_int64(statement, 5)
            let totalValue = sqlite3_column_int64(statement, 6)
            let total = totalValue > 0 ? totalValue : nil
            let connections = Int(sqlite3_column_int(statement, 7))
            let resumeSupported = sqlite3_column_int(statement, 8) == 1
            let destination = URL(fileURLWithPath: text(statement, 9))
            let temp = URL(fileURLWithPath: text(statement, 10))
            let headers = decodeDictionary(text(statement, 11))
            let cookie = text(statement, 12).isEmpty ? nil : text(statement, 12)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 13))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 14))
            let speedLimit = sqlite3_column_int64(statement, 15)
            let openWhenComplete = sqlite3_column_int(statement, 16) == 1
            let revealWhenComplete = sqlite3_column_int(statement, 17) == 1
            let sleepWhenComplete = sqlite3_column_int(statement, 18) == 1
            let shutdownWhenComplete = sqlite3_column_int(statement, 19) == 1
            let verifySHA256WhenComplete = sqlite3_column_int(statement, 20) == 1
            let autoMoveCategoryWhenComplete = sqlite3_column_int(statement, 21) == 1
            let runPluginActionWhenComplete = sqlite3_column_int(statement, 22) == 1
            let verifyMD5WhenComplete = sqlite3_column_int(statement, 23) == 1
            let proxyURLString = text(statement, 24)
            let retryLimit = Int(sqlite3_column_int(statement, 25))
            let requestTimeoutSeconds = Int(sqlite3_column_int(statement, 26))
            let preferredConnectionCount = Int(sqlite3_column_int(statement, 27))
            let ytdlpFormatCode = text(statement, 28)
            let mediaFormatSummary = text(statement, 29)
            let storedCategory = Category(rawValue: text(statement, 30))
            let segments = loadSegmentsUnlocked(downloadID: id)

            items.append(DownloadItem(
                id: id,
                fileName: fileName,
                url: sourceURL.absoluteString,
                sourceURL: sourceURL,
                destinationURL: destination,
                tempURL: temp,
                category: storedCategory ?? DownloadManager.category(for: fileName),
                headers: headers,
                cookie: cookie,
                createdAt: createdAt,
                updatedAt: updatedAt,
                size: total.map(DownloadManager.byteCount) ?? "Unknown",
                speed: "--",
                eta: status == .complete ? "--" : "Resume ready",
                connections: connections,
                progress: progress,
                status: status == .downloading ? .paused : status,
                downloadedBytes: downloaded,
                totalBytes: total,
                resumeSupported: resumeSupported,
                detail: status == .complete ? "Saved to \(destination.path)" : "Restored from SQLite",
                segments: segments,
                speedLimitBytesPerSecond: speedLimit,
                openWhenComplete: openWhenComplete,
                revealWhenComplete: revealWhenComplete,
                sleepWhenComplete: sleepWhenComplete,
                shutdownWhenComplete: shutdownWhenComplete,
                verifySHA256WhenComplete: verifySHA256WhenComplete,
                verifyMD5WhenComplete: verifyMD5WhenComplete,
                autoMoveCategoryWhenComplete: autoMoveCategoryWhenComplete,
                runPluginActionWhenComplete: runPluginActionWhenComplete,
                proxyURLString: proxyURLString,
                retryLimit: retryLimit,
                requestTimeoutSeconds: requestTimeoutSeconds,
                preferredConnectionCount: preferredConnectionCount,
                ytdlpFormatCode: ytdlpFormatCode,
                mediaFormatSummary: mediaFormatSummary
            ))
        }
        return items
    }

    func upsert(_ item: DownloadItem) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let sql = """
        INSERT INTO downloads (
          id,url,file_name,status,progress,downloaded,total,connections,resume_supported,
          destination,temp,headers,cookie,resume_data,created_at,updated_at,
          speed_limit,open_on_complete,reveal_on_complete,sleep_on_complete,shutdown_on_complete,
          verify_sha256,auto_move_category,run_plugin_action,verify_md5,proxy,retry_limit,request_timeout,preferred_connections,
          ytdlp_format,media_format_summary,category
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          url=excluded.url,file_name=excluded.file_name,status=excluded.status,progress=excluded.progress,
          downloaded=excluded.downloaded,total=excluded.total,connections=excluded.connections,
          resume_supported=excluded.resume_supported,destination=excluded.destination,temp=excluded.temp,
          headers=excluded.headers,cookie=excluded.cookie,resume_data=excluded.resume_data,updated_at=excluded.updated_at,
          speed_limit=excluded.speed_limit,open_on_complete=excluded.open_on_complete,
          reveal_on_complete=excluded.reveal_on_complete,sleep_on_complete=excluded.sleep_on_complete,
          shutdown_on_complete=excluded.shutdown_on_complete,verify_sha256=excluded.verify_sha256,
          auto_move_category=excluded.auto_move_category,run_plugin_action=excluded.run_plugin_action,
          verify_md5=excluded.verify_md5,proxy=excluded.proxy,retry_limit=excluded.retry_limit,request_timeout=excluded.request_timeout,
          preferred_connections=excluded.preferred_connections,ytdlp_format=excluded.ytdlp_format,
          media_format_summary=excluded.media_format_summary,category=excluded.category;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, item.id.uuidString)
        bind(statement, 2, item.url)
        bind(statement, 3, item.fileName)
        bind(statement, 4, item.status.rawValue)
        sqlite3_bind_double(statement, 5, item.progress)
        sqlite3_bind_int64(statement, 6, item.downloadedBytes)
        sqlite3_bind_int64(statement, 7, item.totalBytes ?? 0)
        sqlite3_bind_int(statement, 8, Int32(item.connections))
        sqlite3_bind_int(statement, 9, item.resumeSupported ? 1 : 0)
        bind(statement, 10, item.destinationURL.path)
        bind(statement, 11, item.tempURL.path)
        bind(statement, 12, encodeDictionary(item.headers))
        bind(statement, 13, item.cookie ?? "")
        bind(statement, 14, encodeResumeData(item.segments))
        sqlite3_bind_double(statement, 15, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 16, item.updatedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 17, item.speedLimitBytesPerSecond)
        sqlite3_bind_int(statement, 18, item.openWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 19, item.revealWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 20, item.sleepWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 21, item.shutdownWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 22, item.verifySHA256WhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 23, item.autoMoveCategoryWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 24, item.runPluginActionWhenComplete ? 1 : 0)
        sqlite3_bind_int(statement, 25, item.verifyMD5WhenComplete ? 1 : 0)
        bind(statement, 26, item.proxyURLString)
        sqlite3_bind_int(statement, 27, Int32(item.retryLimit))
        sqlite3_bind_int(statement, 28, Int32(item.requestTimeoutSeconds))
        sqlite3_bind_int(statement, 29, Int32(item.preferredConnectionCount))
        bind(statement, 30, item.ytdlpFormatCode)
        bind(statement, 31, item.mediaFormatSummary)
        bind(statement, 32, item.category.rawValue)
        sqlite3_step(statement)
    }

    func saveSegments(_ item: DownloadItem) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        executeUnlocked("BEGIN TRANSACTION")
        for segment in item.segments {
            let sql = """
            INSERT INTO segments VALUES (?,?,?,?,?,?)
            ON CONFLICT(download_id,idx) DO UPDATE SET
              start=excluded.start,end=excluded.end,downloaded=excluded.downloaded,status=excluded.status;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            bind(statement, 1, item.id.uuidString)
            sqlite3_bind_int(statement, 2, Int32(segment.id))
            sqlite3_bind_int64(statement, 3, segment.start)
            sqlite3_bind_int64(statement, 4, segment.end)
            sqlite3_bind_int64(statement, 5, segment.downloaded)
            bind(statement, 6, segment.status.rawValue)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        executeUnlocked("COMMIT")
    }

    func delete(itemID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        executeUnlocked("DELETE FROM segments WHERE download_id='\(itemID.uuidString)'")
        executeUnlocked("DELETE FROM downloads WHERE id='\(itemID.uuidString)'")
    }

    private func loadSegmentsUnlocked(downloadID: UUID) -> [DownloadSegment] {
        guard let db else { return [] }
        let sql = "SELECT idx,start,end,downloaded,status FROM segments WHERE download_id=? ORDER BY idx"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, downloadID.uuidString)
        var segments: [DownloadSegment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            segments.append(DownloadSegment(
                id: Int(sqlite3_column_int(statement, 0)),
                start: sqlite3_column_int64(statement, 1),
                end: sqlite3_column_int64(statement, 2),
                downloaded: sqlite3_column_int64(statement, 3),
                speed: 0,
                status: DownloadStatus(rawValue: text(statement, 4)) ?? .queued
            ))
        }
        return segments
    }

    private func execute(_ sql: String) {
        lock.lock()
        defer { lock.unlock() }
        executeUnlocked(sql)
    }

    private func executeUnlocked(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func encodeDictionary(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dictionary) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decodeDictionary(_ string: String) -> [String: String] {
        guard let data = string.data(using: .utf8),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dictionary
    }

    private func encodeResumeData(_ segments: [DownloadSegment]) -> String {
        let payload = segments.map {
            [
                "index": Int64($0.id),
                "start": $0.start,
                "end": $0.end,
                "downloaded": $0.downloaded
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
