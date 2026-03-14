import Foundation
import Observation

enum AudioQuality: String, CaseIterable, Codable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case lossless = "LOSSLESS"
    case hiResLossless = "HI_RES_LOSSLESS"

    var label: String {
        switch self {
        case .low: return "AAC (128 kbps)"
        case .medium: return "AAC (256 kbps)"
        case .high: return "AAC (320 kbps)"
        case .lossless: return "FLAC (Lossless)"
        case .hiResLossless: return "FLAC (Hi-Res)"
        }
    }
}

enum DownloadQuality: String, CaseIterable, Codable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case lossless = "LOSSLESS"
    case hiResLossless = "HI_RES_LOSSLESS"

    var label: String {
        switch self {
        case .low: return "AAC (128 kbps)"
        case .medium: return "AAC (256 kbps)"
        case .high: return "AAC (320 kbps)"
        case .lossless: return "FLAC (Lossless)"
        case .hiResLossless: return "FLAC (Hi-Res)"
        }
    }
}

enum FileNaming: String, CaseIterable, Codable {
    case flat = "FLAT"
    case custom = "CUSTOM"

    var label: String {
        switch self {
        case .flat: return "Flat (no folders)"
        case .custom: return "Custom"
        }
    }
}

@Observable
class SettingsManager {
    static let shared = SettingsManager()

    private let streamQualityKey = "settings_stream_quality"
    private let downloadQualityKey = "settings_download_quality"
    private let fileNamingKey = "settings_file_naming"
    private let customNamingPatternKey = "settings_custom_naming_pattern"

    var streamQuality: AudioQuality {
        didSet {
            UserDefaults.standard.set(streamQuality.rawValue, forKey: streamQualityKey)
        }
    }

    var downloadQuality: DownloadQuality {
        didSet {
            UserDefaults.standard.set(downloadQuality.rawValue, forKey: downloadQualityKey)
        }
    }

    var fileNaming: FileNaming {
        didSet {
            UserDefaults.standard.set(fileNaming.rawValue, forKey: fileNamingKey)
        }
    }

    var customNamingPattern: String {
        didSet {
            UserDefaults.standard.set(customNamingPattern, forKey: customNamingPatternKey)
        }
    }

    private init() {
        let savedStream = UserDefaults.standard.string(forKey: streamQualityKey)
        self.streamQuality = AudioQuality(rawValue: savedStream ?? "HIGH") ?? .high

        let savedDownload = UserDefaults.standard.string(forKey: downloadQualityKey)
        self.downloadQuality = DownloadQuality(rawValue: savedDownload ?? "HI_RES_LOSSLESS") ?? .hiResLossless

        let savedNaming = UserDefaults.standard.string(forKey: fileNamingKey)
        self.fileNaming = FileNaming(rawValue: savedNaming ?? "CUSTOM") ?? .custom

        self.customNamingPattern = UserDefaults.standard.string(forKey: customNamingPatternKey) ?? "{artist}/{album}/{artist} - {title}"
    }

    func sanitizeFileName(_ name: String) -> String {
        // Only `/` and `:` are truly invalid on iOS/macOS (HFS+/APFS)
        let invalidChars = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    func generateFilePath(for track: Track, extension ext: String) -> String {
        let artist = sanitizeFileName(track.artist?.name ?? "Unknown Artist")
        let album = sanitizeFileName(track.album?.title ?? "Unknown Album")
        let title = sanitizeFileName(track.title)
        
        let trackNum = track.trackNumber.map { String($0).padding(toLength: 2, withPad: "0", startingAt: 0) } ?? "01"

        var pattern = ""
        switch fileNaming {
        case .flat:
            pattern = "{artist} - {title}"
        case .custom:
            pattern = customNamingPattern
        }

        var result = pattern
            .replacingOccurrences(of: "{artist}", with: artist)
            .replacingOccurrences(of: "{album}", with: album)
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{track}", with: trackNum)

        return "\(result).\(ext)"
    }
}
