import Foundation
import AVFoundation

class AudioMetadataEmbedder {

    static let shared = AudioMetadataEmbedder()

    struct Metadata {
        let title: String
        let artist: String
        let album: String
        let trackNumber: Int?
        let totalTracks: Int?
        let year: String?
        let coverData: Data?
    }

    func embed(at fileURL: URL, metadata: Metadata) {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "flac":
            embedFLAC(at: fileURL, metadata: metadata)
        case "mp3":
            embedID3(at: fileURL, metadata: metadata)
        case "m4a", "aac", "mp4":
            embedM4A(at: fileURL, metadata: metadata)
        default:
            print("[Metadata] Unsupported format: \(ext)")
        }
    }

    // MARK: - FLAC

    private func embedFLAC(at fileURL: URL, metadata: Metadata) {
        guard let readHandle = try? FileHandle(forReadingFrom: fileURL) else {
            print("[Metadata] FLAC: cannot open file")
            return
        }

        // Verify "fLaC" magic
        let magic = readHandle.readData(ofLength: 4)
        guard magic.count == 4,
              magic[0] == 0x66, magic[1] == 0x4C, magic[2] == 0x61, magic[3] == 0x43 else {
            readHandle.closeFile()
            print("[Metadata] FLAC: invalid magic")
            return
        }

        // Parse existing metadata blocks — keep STREAMINFO and SEEKTABLE
        var streaminfoData: Data?
        var seektableData: Data?
        var audioDataOffset: UInt64 = 4

        while true {
            let hdr = readHandle.readData(ofLength: 4)
            guard hdr.count == 4 else { break }
            let isLast = (hdr[0] & 0x80) != 0
            let blockType = hdr[0] & 0x7F
            let length = Int(hdr[1]) << 16 | Int(hdr[2]) << 8 | Int(hdr[3])
            audioDataOffset += 4

            if blockType == 0 {
                streaminfoData = readHandle.readData(ofLength: length)
            } else if blockType == 3 {
                seektableData = readHandle.readData(ofLength: length)
            } else {
                readHandle.seek(toFileOffset: readHandle.offsetInFile + UInt64(length))
            }
            audioDataOffset += UInt64(length)
            if isLast { break }
        }

        guard let streaminfo = streaminfoData else {
            readHandle.closeFile()
            print("[Metadata] FLAC: no STREAMINFO")
            return
        }

        // Build native FLAC metadata blocks
        let vorbisComment = buildVorbisComment(metadata)
        var flacMeta = Data()

        // STREAMINFO (type 0)
        writeBlockHeader(&flacMeta, type: 0, length: streaminfo.count, isLast: false)
        flacMeta.append(streaminfo)

        // SEEKTABLE (type 3)
        if let seektable = seektableData {
            writeBlockHeader(&flacMeta, type: 3, length: seektable.count, isLast: false)
            flacMeta.append(seektable)
        }

        // VORBIS_COMMENT (type 4)
        writeBlockHeader(&flacMeta, type: 4, length: vorbisComment.count, isLast: metadata.coverData == nil)
        flacMeta.append(vorbisComment)

        // PICTURE (type 6)
        if let coverData = metadata.coverData {
            let picture = buildFLACPicture(coverData)
            writeBlockHeader(&flacMeta, type: 6, length: picture.count, isLast: true)
            flacMeta.append(picture)
        }

        // Build ID3v2.3 tag (prepended before fLaC — makes covers visible on macOS/Windows)
        let id3Tag = buildID3Tag(metadata)

        // Write: ID3v2.3 + fLaC + metadata blocks + audio data
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("temp_\(UUID().uuidString).flac")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let writeHandle = try? FileHandle(forWritingTo: tempURL) else {
            readHandle.closeFile()
            return
        }

        writeHandle.write(id3Tag)
        writeHandle.write(magic)
        writeHandle.write(flacMeta)

        // Stream audio data in chunks
        readHandle.seek(toFileOffset: audioDataOffset)
        while true {
            let chunk = readHandle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            writeHandle.write(chunk)
        }
        writeHandle.closeFile()
        readHandle.closeFile()

        // Replace original
        do {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            print("[Metadata] FLAC tagged: \(metadata.title)")
        } catch {
            print("[Metadata] FLAC error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func writeBlockHeader(_ data: inout Data, type: UInt8, length: Int, isLast: Bool) {
        data.append((isLast ? 0x80 : 0x00) | type)
        data.append(UInt8((length >> 16) & 0xFF))
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
    }

    private func buildVorbisComment(_ m: Metadata) -> Data {
        var comments: [String] = []
        comments.append("TITLE=\(m.title)")
        comments.append("ARTIST=\(m.artist)")
        comments.append("ALBUM=\(m.album)")
        if let n = m.trackNumber { comments.append("TRACKNUMBER=\(n)") }
        if let t = m.totalTracks { comments.append("TOTALTRACKS=\(t)") }
        if let y = m.year { comments.append("DATE=\(y)") }

        var data = Data()
        let vendor = "monochrome-ios"
        appendLE32(&data, UInt32(vendor.utf8.count))
        data.append(Data(vendor.utf8))
        appendLE32(&data, UInt32(comments.count))
        for c in comments {
            let utf8 = Data(c.utf8)
            appendLE32(&data, UInt32(utf8.count))
            data.append(utf8)
        }
        return data
    }

    private func buildFLACPicture(_ imageData: Data) -> Data {
        var data = Data()
        let mime = Data("image/jpeg".utf8)

        appendBE32(&data, 3)                       // front cover
        appendBE32(&data, UInt32(mime.count))
        data.append(mime)
        appendBE32(&data, 0)                       // no description
        appendBE32(&data, 0)                       // width
        appendBE32(&data, 0)                       // height
        appendBE32(&data, 0)                       // color depth
        appendBE32(&data, 0)                       // colors
        appendBE32(&data, UInt32(imageData.count))
        data.append(imageData)
        return data
    }

    // MARK: - ID3v2.3 Tag Builder (used for both MP3 and FLAC)

    private func buildID3Tag(_ metadata: Metadata) -> Data {
        var frames = Data()
        appendTextFrame(&frames, id: "TIT2", text: metadata.title)
        appendTextFrame(&frames, id: "TPE1", text: metadata.artist)
        appendTextFrame(&frames, id: "TALB", text: metadata.album)

        if let n = metadata.trackNumber {
            let val = metadata.totalTracks != nil ? "\(n)/\(metadata.totalTracks!)" : "\(n)"
            appendTextFrame(&frames, id: "TRCK", text: val)
        }
        if let y = metadata.year {
            appendTextFrame(&frames, id: "TYER", text: y)
        }

        // APIC frame (cover art)
        if let coverData = metadata.coverData {
            var apic = Data()
            apic.append(0x03)                        // UTF-8 encoding
            apic.append(Data("image/jpeg".utf8))
            apic.append(0x00)                        // null terminator
            apic.append(0x03)                        // front cover
            apic.append(0x00)                        // empty description
            apic.append(coverData)

            frames.append(Data("APIC".utf8))
            appendBE32(&frames, UInt32(apic.count))
            frames.append(contentsOf: [0x00, 0x00])  // flags
            frames.append(apic)
        }

        // ID3v2.3 header
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x03, 0x00])          // version 2.3.0
        tag.append(0x00)                              // flags
        tag.append(contentsOf: intToSyncsafe(frames.count))
        tag.append(frames)
        return tag
    }

    // MARK: - MP3

    private func embedID3(at fileURL: URL, metadata: Metadata) {
        guard let readHandle = try? FileHandle(forReadingFrom: fileURL) else { return }

        // Skip existing ID3v2 tag
        let header = readHandle.readData(ofLength: 10)
        var audioStart: UInt64 = 0
        if header.count >= 10,
           header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
            audioStart = UInt64(10 + syncsafeToInt(header[6], header[7], header[8], header[9]))
        }
        readHandle.closeFile()

        let tag = buildID3Tag(metadata)

        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("temp_\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let writeHandle = try? FileHandle(forWritingTo: tempURL),
              let readHandle2 = try? FileHandle(forReadingFrom: fileURL) else { return }

        writeHandle.write(tag)
        readHandle2.seek(toFileOffset: audioStart)
        while true {
            let chunk = readHandle2.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            writeHandle.write(chunk)
        }
        writeHandle.closeFile()
        readHandle2.closeFile()

        do {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            print("[Metadata] MP3 tagged: \(metadata.title)")
        } catch {
            print("[Metadata] MP3 error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func appendTextFrame(_ data: inout Data, id: String, text: String) {
        let encoded = Data(text.utf8)
        data.append(Data(id.utf8))
        appendBE32(&data, UInt32(encoded.count + 1))
        data.append(contentsOf: [0x00, 0x00])
        data.append(0x03) // UTF-8
        data.append(encoded)
    }

    // MARK: - M4A (AVFoundation passthrough)

    private func embedM4A(at fileURL: URL, metadata: Metadata) {
        let asset = AVURLAsset(url: fileURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }

        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("temp_\(UUID().uuidString).\(fileURL.pathExtension)")
        session.outputURL = tempURL
        session.outputFileType = .m4a

        var items: [AVMutableMetadataItem] = []

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = metadata.title as NSString
        items.append(titleItem)

        let artistItem = AVMutableMetadataItem()
        artistItem.identifier = .commonIdentifierArtist
        artistItem.value = metadata.artist as NSString
        items.append(artistItem)

        let albumItem = AVMutableMetadataItem()
        albumItem.identifier = .commonIdentifierAlbumName
        albumItem.value = metadata.album as NSString
        items.append(albumItem)

        if let n = metadata.trackNumber {
            // iTunes trkn atom uses packed binary: 2 bytes padding + UInt16 track + UInt16 total + 2 bytes padding
            var trknData = Data(count: 8)
            let trackBE = UInt16(n).bigEndian
            let totalBE = UInt16(metadata.totalTracks ?? 0).bigEndian
            withUnsafeBytes(of: trackBE) { trknData.replaceSubrange(2..<4, with: $0) }
            withUnsafeBytes(of: totalBE) { trknData.replaceSubrange(4..<6, with: $0) }

            let trackItem = AVMutableMetadataItem()
            trackItem.identifier = .iTunesMetadataTrackNumber
            trackItem.value = trknData as NSData
            trackItem.dataType = kCMMetadataBaseDataType_RawData as String
            items.append(trackItem)
        }

        if let y = metadata.year {
            let yearItem = AVMutableMetadataItem()
            yearItem.keySpace = .iTunes
            yearItem.key = "©day" as NSString
            yearItem.value = y as NSString
            items.append(yearItem)
        }

        if let coverData = metadata.coverData {
            let artItem = AVMutableMetadataItem()
            artItem.identifier = .commonIdentifierArtwork
            artItem.value = coverData as NSData
            artItem.dataType = kCMMetadataBaseDataType_JPEG as String
            items.append(artItem)
        }

        // Strip existing metadata so our values take precedence over Tidal's defaults
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        session.metadata = items

        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously { semaphore.signal() }
        semaphore.wait()

        if session.status == .completed {
            do {
                try FileManager.default.removeItem(at: fileURL)
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
                print("[Metadata] M4A tagged: \(metadata.title)")
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
            }
        } else {
            print("[Metadata] M4A failed: \(session.error?.localizedDescription ?? "unknown")")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Binary Helpers

    private func appendLE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func appendBE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private func syncsafeToInt(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Int {
        Int(b0) << 21 | Int(b1) << 14 | Int(b2) << 7 | Int(b3)
    }

    private func intToSyncsafe(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ]
    }
}
