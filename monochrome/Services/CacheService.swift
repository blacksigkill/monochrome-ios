import Foundation
import Observation

@Observable
class CacheService {
    static let shared = CacheService()

    // MARK: - Settings (persisted)

    var maxAge: TimeInterval {
        didSet { UserDefaults.standard.set(maxAge, forKey: "cache_maxAge") }
    }

    var maxSizeMB: Int {
        didSet { UserDefaults.standard.set(maxSizeMB, forKey: "cache_maxSizeMB") }
    }

    // MARK: - In-Memory Cache (excluded from observation tracking)

    @ObservationIgnored
    private var memory: [String: MemoryEntry] = [:]

    private struct MemoryEntry {
        let data: Data
        let timestamp: Date
    }

    // MARK: - Disk Cache

    private let diskDir: URL

    private struct DiskEntry: Codable {
        let data: Data
        let timestamp: Date
    }

    // MARK: - Encoder / Decoder (handle NaN / Infinity from API)

    @ObservationIgnored
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return e
    }()

    @ObservationIgnored
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return d
    }()

    // MARK: - TTL / Size Options

    static let ttlOptions: [(label: String, value: TimeInterval)] = [
        ("1 hour", 3600),
        ("6 hours", 6 * 3600),
        ("24 hours", 24 * 3600),
        ("7 days", 7 * 24 * 3600),
        ("30 days", 30 * 24 * 3600),
    ]

    static let sizeOptions: [(label: String, value: Int)] = [
        ("50 MB", 50),
        ("100 MB", 100),
        ("250 MB", 250),
        ("500 MB", 500),
        ("1 GB", 1024),
    ]

    var ttlLabel: String {
        Self.ttlOptions.first { $0.value == maxAge }?.label ?? "\(Int(maxAge / 3600))h"
    }

    var sizeLimitLabel: String {
        Self.sizeOptions.first { $0.value == maxSizeMB }?.label ?? "\(maxSizeMB) MB"
    }

    // MARK: - Init

    init() {
        let savedAge = UserDefaults.standard.double(forKey: "cache_maxAge")
        self.maxAge = savedAge > 0 ? savedAge : 24 * 3600

        let savedSize = UserDefaults.standard.integer(forKey: "cache_maxSizeMB")
        self.maxSizeMB = savedSize > 0 ? savedSize : 100

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskDir = caches.appendingPathComponent("MonochromeAPICache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    // MARK: - Age (seconds since entry was cached, nil if not cached)

    func age(forKey key: String) -> TimeInterval? {
        if let entry = memory[key] {
            return Date().timeIntervalSince(entry.timestamp)
        }

        let file = diskDir.appendingPathComponent(diskName(key))
        guard let raw = try? Data(contentsOf: file),
              let diskEntry = try? decoder.decode(DiskEntry.self, from: raw) else {
            return nil
        }

        return Date().timeIntervalSince(diskEntry.timestamp)
    }

    // MARK: - Get

    func get<T: Codable>(forKey key: String) -> T? {
        // Memory check
        if let entry = memory[key] {
            if Date().timeIntervalSince(entry.timestamp) < maxAge {
                if let decoded: T = try? decoder.decode(T.self, from: entry.data) {
                    return decoded
                }
                // Decode failed — remove corrupted entry, fall through to disk
                memory.removeValue(forKey: key)
            } else {
                memory.removeValue(forKey: key)
            }
        }

        // Disk check
        let file = diskDir.appendingPathComponent(diskName(key))
        guard let raw = try? Data(contentsOf: file),
              let diskEntry = try? decoder.decode(DiskEntry.self, from: raw) else {
            return nil
        }

        if Date().timeIntervalSince(diskEntry.timestamp) >= maxAge {
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        guard let decoded: T = try? decoder.decode(T.self, from: diskEntry.data) else {
            // Corrupted disk entry — remove it
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        // Promote to memory
        memory[key] = MemoryEntry(data: diskEntry.data, timestamp: diskEntry.timestamp)
        return decoded
    }

    // MARK: - Set

    func set<T: Codable>(forKey key: String, value: T) {
        guard let data = try? encoder.encode(value) else {
            print("[Cache] encode failed for \(key)")
            return
        }

        memory[key] = MemoryEntry(data: data, timestamp: Date())

        let diskEntry = DiskEntry(data: data, timestamp: Date())
        if let encoded = try? encoder.encode(diskEntry) {
            try? encoded.write(to: diskDir.appendingPathComponent(diskName(key)))
        }

        evictIfNeeded()
    }

    // MARK: - Clear

    func clearAll() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    // MARK: - Stats

    var totalSizeBytes: Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
    }

    var entryCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: diskDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    var formattedSize: String {
        let bytes = totalSizeBytes
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    // MARK: - Private

    private func diskName(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    private func evictIfNeeded() {
        let maxBytes = maxSizeMB * 1024 * 1024
        var current = totalSizeBytes
        guard current > maxBytes else { return }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let sorted = files.sorted { a, b in
            let dA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dA < dB
        }

        // Build a set of evicted file names so we can remove matching memory entries
        var evictedKeys: Set<String> = []

        for file in sorted {
            guard current > maxBytes else { break }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            evictedKeys.insert(file.lastPathComponent)
            try? FileManager.default.removeItem(at: file)
            current -= size
        }

        // Only remove memory entries whose disk file was evicted
        if !evictedKeys.isEmpty {
            let keysToRemove = memory.keys.filter { evictedKeys.contains(diskName($0)) }
            for key in keysToRemove {
                memory.removeValue(forKey: key)
            }
        }
    }
}
