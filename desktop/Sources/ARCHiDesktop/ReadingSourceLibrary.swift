import Foundation
import Combine
import CryptoKit
import Darwin

enum ReadingSourceLibraryError: LocalizedError {
    case invalid(String), unreadable, changed, locked, full, missing

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unreadable: return "Kept reading sources could not be read or saved. Existing copies were preserved."
        case .changed: return "Kept reading sources changed outside this session. Reopen ARCHi before changing or using them."
        case .locked: return "Another session is saving reading sources. Try again after it finishes."
        case .full: return "Keep at most eight reading sources with 400 KB of text in total. Forget a copy before adding more."
        case .missing: return "This kept reading source is no longer in the library."
        }
    }
}

/// Explicit local text copies, never a file watcher or a request-selection owner.
/// Opening this library only reads. Keep/replace/forget are the only writers;
/// callers must check freshness again when selecting or dispatching a snapshot.
@MainActor
final class ReadingSourceLibrary: ObservableObject {
    static let maximumSources = 8
    static let maximumTextBytes = 400_000
    static let privacyNotice = "Kept sources are local text copies you choose to retain. This library stores no original file locations, does not refresh originals, and does not send or select copies. Forget removes the retained copy from this library."

    @Published private(set) var sources: [ReadingSourceSnapshot] = []
    @Published private(set) var loadError: String?

    private let url: URL
    private var baselineDigest: String?
    private var requiresRecovery = false
    private static let schema = "archi-reading-sources/v1"
    // JSON escaping can expand the admitted 400 KB of literal source text.
    private static let maximumArchiveBytes = 3 * 1_024 * 1_024

    private struct Archive: Codable {
        let schema: String
        let sources: [ReadingSourceSnapshot]
    }

    init(url: URL, recoveryBlocked: Bool = false) {
        self.url = url
        guard !recoveryBlocked else {
            requiresRecovery = true
            loadError = "Profile recovery must finish before document data can be loaded or changed."
            return
        }
        do {
            if let bytes = try Self.readBounded(url) {
                sources = try Self.decode(bytes).sources
                baselineDigest = Self.digest(bytes)
            }
        } catch {
            requiresRecovery = true
            loadError = ReadingSourceLibraryError.unreadable.localizedDescription
        }
    }

    /// A read-only comparison against the exact loaded/saved journal bytes.
    /// A stale in-memory copy cannot authorize supplying kept text to a request.
    var isCurrentOnDisk: Bool {
        guard !requiresRecovery else { return false }
        do { return try Self.readBounded(url).map(Self.digest) == baselineDigest }
        catch { return false }
    }

    @discardableResult
    func keep(title: String, text: String) throws -> ReadingSourceSnapshot {
        let snapshot = ReadingSourceSnapshot(id: UUID().uuidString, title: title, revision: 1, text: text)
        guard Self.validSnapshot(snapshot) else {
            throw ReadingSourceLibraryError.invalid("A kept source needs a title of at most 240 UTF-8 bytes and 1–100,000 UTF-8 bytes of text.")
        }
        try persist(sources + [snapshot])
        return snapshot
    }

    /// Replacement keeps the source identity and advances its revision. Earlier
    /// request digests remain historical; the old text is not an archive here.
    @discardableResult
    func replace(id: String, title: String, text: String) throws -> ReadingSourceSnapshot {
        guard let index = sources.firstIndex(where: { $0.id == id }) else {
            throw ReadingSourceLibraryError.missing
        }
        guard sources[index].revision < UInt64.max else {
            throw ReadingSourceLibraryError.invalid("The source revision limit was reached. Keep a new copy instead.")
        }
        let snapshot = ReadingSourceSnapshot(id: id, title: title, revision: sources[index].revision + 1, text: text)
        guard Self.validSnapshot(snapshot) else {
            throw ReadingSourceLibraryError.invalid("A kept source needs a title of at most 240 UTF-8 bytes and 1–100,000 UTF-8 bytes of text.")
        }
        var next = sources
        next[index] = snapshot
        try persist(next)
        return snapshot
    }

    func forget(id: String) throws {
        guard sources.contains(where: { $0.id == id }) else { throw ReadingSourceLibraryError.missing }
        try persist(sources.filter { $0.id != id })
    }

    private func assertCurrent() throws {
        guard !requiresRecovery else { throw ReadingSourceLibraryError.unreadable }
        let actual: String?
        do { actual = try Self.readBounded(url).map(Self.digest) }
        catch {
            requiresRecovery = true
            loadError = ReadingSourceLibraryError.unreadable.localizedDescription
            throw ReadingSourceLibraryError.unreadable
        }
        guard actual == baselineDigest else {
            requiresRecovery = true
            loadError = ReadingSourceLibraryError.changed.localizedDescription
            throw ReadingSourceLibraryError.changed
        }
    }

    private func persist(_ next: [ReadingSourceSnapshot]) throws {
        guard !requiresRecovery, url.isFileURL else { throw ReadingSourceLibraryError.unreadable }
        guard next.allSatisfy(Self.validSnapshot), Self.uniqueIDs(next) else {
            throw ReadingSourceLibraryError.invalid("Invalid kept reading source identities or revisions.")
        }
        guard Self.withinCapacity(next) else { throw ReadingSourceLibraryError.full }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(schema: Self.schema, sources: next))
        guard bytes.count <= Self.maximumArchiveBytes else { throw ReadingSourceLibraryError.full }

        try assertCurrent()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let lock = Darwin.open(url.appendingPathExtension("lock").path,
                               O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw ReadingSourceLibraryError.locked }
        defer { _ = Darwin.close(lock) }
        var information = stat()
        guard fstat(lock, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw ReadingSourceLibraryError.locked }
        defer { _ = flock(lock, LOCK_UN) }
        try assertCurrent()

        let temporary = url.deletingLastPathComponent().appendingPathComponent(".reading-source-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ReadingSourceLibraryError.unreadable }
        var isOpen = true
        defer {
            if isOpen { _ = Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw ReadingSourceLibraryError.unreadable }
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw ReadingSourceLibraryError.unreadable }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw ReadingSourceLibraryError.unreadable }
        let closeResult = Darwin.close(descriptor)
        isOpen = false
        guard closeResult == 0 else { throw ReadingSourceLibraryError.unreadable }
        try assertCurrent()
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw ReadingSourceLibraryError.unreadable }
        baselineDigest = Self.digest(bytes)
        sources = next
        loadError = nil
    }

    private static func decode(_ data: Data) throws -> Archive {
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema", "sources"],
              let rows = object["sources"] as? [[String: Any]], rows.count <= maximumSources,
              rows.allSatisfy({ Set($0.keys) == ["id", "title", "revision", "text"] }) else {
            throw ReadingSourceLibraryError.unreadable
        }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.schema == schema, archive.sources.allSatisfy(validSnapshot),
              uniqueIDs(archive.sources), withinCapacity(archive.sources) else {
            throw ReadingSourceLibraryError.unreadable
        }
        return archive
    }

    private static func validSnapshot(_ value: ReadingSourceSnapshot) -> Bool {
        // The shared model also represents the current transient shared-copy.
        // Only actual UUID-backed copies can enter this persistent library.
        value.isValid && UUID(uuidString: value.id) != nil
            && value.revision > 0 && value.title.utf8.count <= 240
            && (1...100_000).contains(value.text.utf8.count)
    }

    private static func uniqueIDs(_ values: [ReadingSourceSnapshot]) -> Bool {
        let ids = values.compactMap { UUID(uuidString: $0.id) }
        return ids.count == values.count && Set(ids).count == values.count
    }

    private static func withinCapacity(_ values: [ReadingSourceSnapshot]) -> Bool {
        guard values.count <= maximumSources else { return false }
        var total = 0
        for value in values {
            let size = value.text.utf8.count
            guard size <= maximumTextBytes - total else { return false }
            total += size
        }
        return true
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readBounded(_ url: URL) throws -> Data? {
        guard url.isFileURL else { throw ReadingSourceLibraryError.unreadable }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ReadingSourceLibraryError.unreadable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0, information.st_size <= maximumArchiveBytes else {
            throw ReadingSourceLibraryError.unreadable
        }
        var bytes = Data()
        while bytes.count <= maximumArchiveBytes {
            guard let part = try handle.read(upToCount: maximumArchiveBytes + 1 - bytes.count), !part.isEmpty else { break }
            bytes.append(part)
        }
        guard bytes.count <= maximumArchiveBytes else { throw ReadingSourceLibraryError.unreadable }
        return bytes
    }
}
