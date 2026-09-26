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
/// Opening this library only reads. Source and knowledge-page commands are the writers;
/// callers must check freshness again when selecting or dispatching a snapshot.
@MainActor
final class ReadingSourceLibrary: ObservableObject {
    static let maximumSources = 8
    static let maximumTextBytes = 400_000
    static let maximumKnowledgePageVersions = 64
    static let privacyNotice = "Kept sources are local text copies you choose to retain. This library stores no original file locations, does not refresh originals, and does not send or select copies. Forget removes the retained copy from this library."

    @Published private(set) var sources: [ReadingSourceSnapshot] = []
    @Published private(set) var knowledgePages: [KnowledgePage] = []
    @Published private(set) var loadError: String?

    private let url: URL
    private var baselineDigest: String?
    private var requiresRecovery = false
    private static let schema = "archi-reading-sources/v2"
    // Covers worst-case JSON escaping of retained sources and bounded note history.
    private static let maximumArchiveBytes = 8 * 1_024 * 1_024

    private struct Archive: Codable {
        let schema: String
        let sources: [ReadingSourceSnapshot]
        let knowledgePages: [KnowledgePage]
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
                let archive = try Self.decode(bytes)
                sources = archive.sources
                knowledgePages = archive.knowledgePages
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

    var latestKnowledgePages: [KnowledgePage] {
        Self.latestPages(knowledgePages)
    }

    func makeAnchor(sourceID: String, range: NSRange) throws -> KnowledgeAnchor {
        try assertCurrent()
        guard let source = sources.first(where: { $0.id == sourceID }),
              let quote = Self.exactQuote(in: source.text, range: range) else {
            throw ReadingSourceLibraryError.invalid("Select an exact, nonempty passage from a current kept source.")
        }
        return KnowledgeAnchor(source: source.binding, location: range.location, length: range.length,
            quoteDigest: LessonSource.digest(of: quote))
    }

    /// Never substitutes a newer source or returns a historical cached quotation.
    func quote(for anchor: KnowledgeAnchor) -> String? {
        guard isCurrentOnDisk else { return nil }
        return currentQuote(for: anchor)
    }

    /// Eligibility for explicit local use, not a semantic truth judgment.
    func availability(of page: KnowledgePage) -> String? {
        guard isCurrentOnDisk else { return "The source library changed or needs recovery. Reopen before using this page." }
        guard page.isValid, knowledgePages.contains(page) else { return "This exact page version is unavailable." }
        guard latestKnowledgePages.contains(page) else { return "Historical version. A later page revision is retained." }
        guard page.state != .withdrawn else { return "You withdrew this page. Its history is retained." }
        guard page.state == .reviewed else { return "Draft. Review this exact note and its supporting passages before use." }
        guard page.anchors.allSatisfy({ currentQuote(for: $0) != nil }) else {
            return "A supporting source changed or was forgotten. Create a new draft with current passage anchors."
        }
        return nil
    }

    @discardableResult
    func saveKnowledgePage(id: String? = nil, expectedRevision: UInt64? = nil, title: String, body: String,
                           kind: KnowledgePageKind, anchors: [KnowledgeAnchor]) throws -> KnowledgePage {
        try assertCurrent()
        let previous: KnowledgePage?
        if let id {
            guard let expectedRevision else { throw ReadingSourceLibraryError.invalid("Choose the exact current page revision before editing.") }
            previous = try currentPage(id: id, expectedRevision: expectedRevision)
        } else {
            guard expectedRevision == nil else { throw ReadingSourceLibraryError.invalid("A new page cannot claim an earlier revision.") }
            previous = nil
        }
        guard !anchors.isEmpty, anchors.allSatisfy({ currentQuote(for: $0) != nil }) else {
            throw ReadingSourceLibraryError.invalid("Choose current exact passages for every source anchor.")
        }
        let now = max(Date(), previous?.updatedAt ?? .distantPast)
        let page = KnowledgePage(id: previous?.id ?? UUID().uuidString,
            revision: (previous?.revision ?? 0) + 1, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body, kind: kind, anchors: anchors, state: .draft,
            createdAt: previous?.createdAt ?? now, updatedAt: now)
        guard page.isValid else {
            throw ReadingSourceLibraryError.invalid("Use a nonempty title up to 240 UTF-8 bytes, a note up to 8 KB, and one to four distinct exact source passages.")
        }
        if let previous, previous.state == .draft, Self.sameContent(previous, page) {
            return previous
        }
        try persist(sources, pages: knowledgePages + [page])
        return page
    }

    @discardableResult
    func reviewKnowledgePage(id: String, expectedRevision: UInt64) throws -> KnowledgePage {
        try assertCurrent()
        let previous = try currentPage(id: id, expectedRevision: expectedRevision)
        guard previous.state != .withdrawn else {
            throw ReadingSourceLibraryError.invalid("Create a new draft before reviewing a withdrawn page.")
        }
        guard previous.anchors.allSatisfy({ currentQuote(for: $0) != nil }) else {
            throw ReadingSourceLibraryError.invalid("A source passage changed. Save a new draft with current anchors before review.")
        }
        if previous.state == .reviewed { return previous }
        let next = transition(previous, to: .reviewed)
        try persist(sources, pages: knowledgePages + [next])
        return next
    }

    @discardableResult
    func withdrawKnowledgePage(id: String, expectedRevision: UInt64) throws -> KnowledgePage {
        try assertCurrent()
        let previous = try currentPage(id: id, expectedRevision: expectedRevision)
        if previous.state == .withdrawn { return previous }
        let next = transition(previous, to: .withdrawn)
        try persist(sources, pages: knowledgePages + [next])
        return next
    }

    /// Portable note text and currently available quotes; never original paths.
    /// Unavailable anchors remain explicit references, never reconstructed text.
    func markdown(for page: KnowledgePage) -> String {
        guard knowledgePages.contains(page) else { return "Page version unavailable." }
        var lines = ["# \(page.title)", "", "\(page.kind.title) · \(page.state.title) · revision \(page.revision)",
            "Page: \(page.id)", "", page.body, "", "## Supporting passages", ""]
        if let reason = availability(of: page) { lines += ["Availability: \(reason)", ""] }
        lines += ["Reviewed records a user review; it does not establish that a claim is true.", ""]
        for (index, anchor) in page.anchors.enumerated() {
            lines += ["### Source \(index + 1)", "",
                "Source: \(anchor.source.id) · revision \(anchor.source.revision)",
                "Source SHA-256: \(anchor.source.digest)",
                "UTF-16 range: \(anchor.location), \(anchor.length)", "Quote SHA-256: \(anchor.quoteDigest)", ""]
            if let current = quote(for: anchor) {
                lines += current.components(separatedBy: .newlines).map { "> " + $0 }
            } else { lines.append("Exact passage unavailable from the current retained source.") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func currentPage(id: String, expectedRevision: UInt64) throws -> KnowledgePage {
        guard let previous = latestKnowledgePages.first(where: { $0.id == id }),
              previous.revision == expectedRevision, previous.revision < UInt64.max else {
            throw ReadingSourceLibraryError.invalid("The page changed. Review its exact current revision before continuing.")
        }
        return previous
    }

    private func transition(_ previous: KnowledgePage, to state: KnowledgePageState) -> KnowledgePage {
        let now = max(Date(), previous.updatedAt)
        return KnowledgePage(id: previous.id, revision: previous.revision + 1, title: previous.title,
            body: previous.body, kind: previous.kind, anchors: previous.anchors, state: state,
            createdAt: previous.createdAt, updatedAt: now, review: KnowledgePageReview(state: state, recordedAt: now))
    }

    private func currentQuote(for anchor: KnowledgeAnchor) -> String? {
        guard anchor.isValid, let source = sources.first(where: { $0.binding == anchor.source }),
              let quote = Self.exactQuote(in: source.text, range: anchor.range) else { return nil }
        return LessonSource.digest(of: quote) == anchor.quoteDigest ? quote : nil
    }

    private static func exactQuote(in text: String, range: NSRange) -> String? {
        let units = Array(text.utf16)
        guard range.location >= 0, range.location < units.count, range.length > 0,
              range.length <= units.count - range.location else { return nil }
        let end = range.location + range.length
        func splitsSurrogatePair(at index: Int) -> Bool {
            index > 0 && index < units.count
                && (0xD800...0xDBFF).contains(units[index - 1])
                && (0xDC00...0xDFFF).contains(units[index])
        }
        // Some Foundation runtimes permit Range(NSRange,in:) within a surrogate
        // pair. Validate scalar boundaries before decoding the selected units.
        guard !splitsSurrogatePair(at: range.location), !splitsSurrogatePair(at: end) else { return nil }
        return String(decoding: units[range.location..<end], as: UTF16.self)
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

    private func persist(_ next: [ReadingSourceSnapshot], pages: [KnowledgePage]? = nil) throws {
        guard !requiresRecovery, url.isFileURL else { throw ReadingSourceLibraryError.unreadable }
        let nextPages = pages ?? knowledgePages
        guard next.allSatisfy(Self.validSnapshot), Self.uniqueIDs(next) else {
            throw ReadingSourceLibraryError.invalid("Invalid kept reading source identities or revisions.")
        }
        guard Self.withinCapacity(next) else { throw ReadingSourceLibraryError.full }
        guard Self.validPageHistory(nextPages) else { throw ReadingSourceLibraryError.invalid("Invalid knowledge page history.") }
        // Reserve one append slot for withdrawing every active head. A full
        // ordinary history must never prevent the user from withdrawing a note.
        guard nextPages.count + Self.latestPages(nextPages).filter({ $0.state != .withdrawn }).count <= Self.maximumKnowledgePageVersions else {
            throw ReadingSourceLibraryError.invalid("The 64-version page history is full; reserved slots remain available for withdrawals. Existing history is preserved.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(schema: Self.schema, sources: next, knowledgePages: nextPages))
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
        knowledgePages = nextPages
        loadError = nil
    }

    private static func decode(_ data: Data) throws -> Archive {
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schema"] as? String,
              [schema, "archi-reading-sources/v1"].contains(version),
              Set(object.keys) == (version == schema ? ["schema", "sources", "knowledgePages"] : ["schema", "sources"]),
              let rows = object["sources"] as? [[String: Any]], rows.count <= maximumSources,
              rows.allSatisfy({ Set($0.keys) == ["id", "title", "revision", "text"] }) else {
            throw ReadingSourceLibraryError.unreadable
        }
        let archive: Archive
        if version == schema {
            guard let pages = object["knowledgePages"] as? [[String: Any]], pages.count <= maximumKnowledgePageVersions else {
                throw ReadingSourceLibraryError.unreadable
            }
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } else {
            archive = Archive(schema: version,
                sources: try JSONDecoder().decode([ReadingSourceSnapshot].self, from: JSONSerialization.data(withJSONObject: rows)),
                knowledgePages: [])
        }
        guard archive.sources.allSatisfy(validSnapshot), uniqueIDs(archive.sources), withinCapacity(archive.sources),
              validPageHistory(archive.knowledgePages),
              archive.knowledgePages.count + latestPages(archive.knowledgePages).filter({ $0.state != .withdrawn }).count <= maximumKnowledgePageVersions else {
            throw ReadingSourceLibraryError.unreadable
        }
        return archive
    }

    private static func latestPages(_ pages: [KnowledgePage]) -> [KnowledgePage] {
        pages.filter { page in !pages.contains { $0.id == page.id && $0.revision > page.revision } }
    }

    private static func sameContent(_ lhs: KnowledgePage, _ rhs: KnowledgePage) -> Bool {
        lhs.title.utf8.elementsEqual(rhs.title.utf8) && lhs.body.utf8.elementsEqual(rhs.body.utf8)
            && lhs.kind == rhs.kind && lhs.anchors == rhs.anchors
    }

    private static func validPageHistory(_ pages: [KnowledgePage]) -> Bool {
        guard pages.count <= maximumKnowledgePageVersions else { return false }
        var latest: [UUID: KnowledgePage] = [:]
        var reviews = Set<UUID>()
        for page in pages {
            guard page.isValid, let id = UUID(uuidString: page.id) else { return false }
            if let review = page.review {
                guard let reviewID = UUID(uuidString: review.id), reviews.insert(reviewID).inserted else { return false }
            }
            if let previous = latest[id] {
                guard previous.id == page.id, previous.revision < UInt64.max,
                      page.revision == previous.revision + 1, page.createdAt == previous.createdAt,
                      page.updatedAt >= previous.updatedAt else { return false }
                switch page.state {
                case .draft: break
                case .reviewed:
                    guard previous.state == .draft, sameContent(previous, page) else { return false }
                case .withdrawn:
                    guard previous.state != .withdrawn, sameContent(previous, page) else { return false }
                }
            } else {
                guard page.revision == 1, page.state == .draft else { return false }
            }
            latest[id] = page
        }
        return true
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
