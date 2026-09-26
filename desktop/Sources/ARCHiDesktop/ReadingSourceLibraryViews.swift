import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension CompanionStore {
    var currentReadingReferences: [ReadingSourceSnapshot] {
        readingSources.sources.filter { selectedReadingSourceIDs.contains($0.id) }.sorted { $0.id < $1.id }
    }

    func readingDependenciesAreCurrent(_ dependencies: [ReadingSourceBinding]?) -> Bool {
        guard let dependencies else { return true }
        guard ReadingSourceBinding.valid(dependencies), readingSources.isCurrentOnDisk else { return false }
        return dependencies.allSatisfy { dependency in readingSources.sources.contains { $0.binding == dependency } }
    }

    func readingReferencesAreCurrent(_ references: [ReadingSourceSnapshot]) -> Bool {
        if references.isEmpty { return true }
        return readingDependenciesAreCurrent(references.map(\.binding))
            && references.allSatisfy { readingSources.sources.contains($0) }
    }

    func selectReadingSource(_ id: String, selected: Bool) {
        guard !isShuttingDown, readingSources.isCurrentOnDisk,
              readingSources.sources.contains(where: { $0.id == id }) else { return }
        guard !selected || selectedReadingSourceIDs.contains(id) || selectedReadingSourceIDs.count < 4 else {
            documentReadingMessage = "Choose up to four kept copies for one reading."; return
        }
        guard selected != selectedReadingSourceIDs.contains(id) else { return }
        invalidateReadingContext(reason: "Reading sources changed. Earlier answers and temporary context were cleared.")
        if selected { selectedReadingSourceIDs.insert(id) } else { selectedReadingSourceIDs.remove(id) }
    }

    func keepCurrentReadingSource() {
        guard !isShuttingDown, profileRecoveryBlock == nil, let name = sourceName else { return }
        retainReadingSource(title: name, text: sharedText)
    }

    private func retainReadingSource(title: String, text: String) {
        do {
            let source = try readingSources.keep(title: title, text: text)
            if selectedReadingSourceIDs.count < 4 { selectReadingSource(source.id, selected: true) }
            documentReadingMessage = "Copy kept on this Mac. Select it to use with the current document."
        } catch { documentReadingMessage = error.localizedDescription }
    }

    func importReadingSource() {
        guard !isShuttingDown, profileRecoveryBlock == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Keep a reading copy"
        panel.message = "Choose a UTF-8 text or Markdown file, up to 100 KB. This saves a local copy; it does not send it."
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 100_000 else {
                documentReadingMessage = "Choose a text file no larger than 100 KB."; return
            }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 100_001) ?? Data()
            guard data.count <= 100_000, let text = String(data: data, encoding: .utf8) else {
                documentReadingMessage = "Choose a UTF-8 text file no larger than 100 KB."; return
            }
            retainReadingSource(title: url.lastPathComponent, text: text)
        } catch { documentReadingMessage = "This copy could not be read. No source was added." }
    }

    func replaceReadingSource(_ id: String) {
        guard !isShuttingDown, profileRecoveryBlock == nil, let name = sourceName else { return }
        do {
            _ = try readingSources.replace(id: id, title: name, text: sharedText)
            invalidateReadingContext(reason: "Reading copy updated. Dependent lessons and earlier answers need fresh review.")
        } catch { documentReadingMessage = error.localizedDescription }
    }

    func forgetReadingSource(_ id: String) {
        guard !isShuttingDown, profileRecoveryBlock == nil else { return }
        do {
            try readingSources.forget(id: id)
            selectedReadingSourceIDs.remove(id)
            invalidateReadingContext(reason: "Reading copy forgotten. Dependent lessons remain visible but cannot be reused.")
        } catch { documentReadingMessage = error.localizedDescription }
    }
}

@MainActor
struct ReadingSourceLibraryView: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        DisclosureGroup("Reading library · \(store.readingSources.sources.count) kept · \(store.selectedReadingSourceIDs.count) selected") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep documents or meeting notes to read together. Select up to four copies alongside your current document; selections last for this visit.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Keep current copy") { store.keepCurrentReadingSource() }
                        .disabled(store.sourceName == nil || store.sharedText.isEmpty || store.isWorking)
                        .accessibilityIdentifier("work.reading.keep")
                    Button("Add text file…") { store.importReadingSource() }
                        .disabled(store.isWorking).accessibilityIdentifier("work.reading.import")
                }
                if let error = store.readingSources.loadError { Text(error).foregroundStyle(.orange) }
                ForEach(store.readingSources.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(get: { store.selectedReadingSourceIDs.contains(source.id) },
                                             set: { store.selectReadingSource(source.id, selected: $0) })) {
                            Text(source.title + " · v\(source.revision)")
                        }.toggleStyle(.checkbox)
                            .accessibilityIdentifier("work.reading.source.\(source.id)")
                        DisclosureGroup("Inspect kept copy") { Text(source.text).textSelection(.enabled) }
                        HStack {
                            Button("Replace with current copy") { store.replaceReadingSource(source.id) }
                                .disabled(store.sourceName == nil || store.isWorking)
                            Button("Forget", role: .destructive) { store.forgetReadingSource(source.id) }
                                .disabled(store.isWorking)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 3)
                }
                Text("Copies are stored as text on this Mac, outside companion recovery packages. Originals are not watched. Replace a copy deliberately when its source changes. Forgetting a copy does not erase lessons you explicitly kept from it; those lessons become unavailable for reuse.")
                    .foregroundStyle(.secondary)
                if !store.selectedReadingSourceIDs.isEmpty {
                    Text("Selected copies use local Qwen only. External fallback is disabled for this reading.")
                        .foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
        }.font(.caption2).accessibilityIdentifier("work.reading.library")
    }
}
