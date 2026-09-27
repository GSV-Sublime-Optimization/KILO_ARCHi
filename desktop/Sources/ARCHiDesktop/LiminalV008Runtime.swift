import AppKit
import SwiftUI

/// Bundled qualification is installed with the signed app, never read from a
/// user's profile or inferred from an arbitrary directory name.
@MainActor
enum LiminalV008Runtime {
    struct Qualification: Codable {
        let schemaVersion: Int
        let assetID: String
        let manifestSHA256: String
        let sourceCooked: Bool
        let nativeEndpointsPassed: Bool
        let unityEndpointsPassed: Bool
        let installedWalkthroughPassed: Bool
        var isValid: Bool {
            schemaVersion == 1 && assetID == "liminal-v008" && LiminalKnowledgeBindings.isDigest(manifestSHA256)
                && sourceCooked && nativeEndpointsPassed && unityEndpointsPassed
        }
    }
    static let orbProgress = 107.0 / 119.0
    static let curledProgress = 65.0 / 119.0
    static let standingProgress = 23.0 / 119.0
    static let asset: LiminalPointAsset? = {
        guard Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("LiminalV008", isDirectory: true)
        let receipt = resources.appendingPathComponent("LiminalV008-qualification.json")
        guard let size = try? receipt.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink != true, let count = size.fileSize, count > 0, count <= 4096,
              let data = try? Data(contentsOf: receipt),
              let qualification = try? JSONDecoder().decode(Qualification.self, from: data), qualification.isValid,
              let asset = try? LiminalPointAsset.load(packageURL: root, expectedManifestSHA256: qualification.manifestSHA256),
              [standingProgress, curledProgress, orbProgress].allSatisfy({
                  (try? asset.endpointPNGData(progress: $0)) != nil
              }) else { return nil }
        return asset
    }()

    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        form == .hamptonSeed && family == nil && treatment == .liminalV008 && asset != nil
    }
    static func snapshot(progress: Double, seedColor: CompanionSeedColor = .original) -> NSImage? {
        guard let asset else { return nil }
        if let data = try? LiminalMetalView.snapshotPNGData(asset: asset, progress: progress, seedColor: seedColor) {
            return NSImage(data: data)
        }
        // The authored fallback carries Original colors only. Do not present
        // that image as an exact personal-color capture after a GPU failure.
        guard seedColor == .original, let data = try? asset.endpointPNGData(progress: progress) else { return nil }
        return NSImage(data: data)
    }
}

private struct LiminalProgressKey: EnvironmentKey { static let defaultValue = 107.0 / 119.0 }
extension EnvironmentValues {
    var liminalPointProgress: Double {
        get { self[LiminalProgressKey.self] }
        set { self[LiminalProgressKey.self] = newValue }
    }
}

@MainActor
struct LiminalV008AppearanceCard: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if store.preferences.seedAppearance == .hamptonLiminal {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liminal · living constellation").font(.headline)
                    Text(LiminalV008Runtime.asset == nil
                         ? "The v008 appearance is waiting for its source export and visual checks. Your current Liminal stays in place."
                         : "Your existing Liminal, with the same authored particles in the room and Arena.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Use v008 particles", isOn: Binding(get: { store.preferences.visualTreatment == .liminalV008 }, set: {
                        guard !$0 || LiminalV008Runtime.asset != nil else { return }
                        store.preferences.visualTreatment = $0 ? .liminalV008 : .original
                    }))
                    .disabled(LiminalV008Runtime.asset == nil)
                    .accessibilityIdentifier("liminal-v008.select")
                    if store.preferences.visualTreatment == .liminalV008, LiminalV008Runtime.asset != nil {
                        if let asset = LiminalV008Runtime.asset {
                            LiminalKnowledgePreview(store: store, asset: asset)
                                .frame(height: 300)
                        }
                        Picker("Presentation pose", selection: $store.preferences.liminalPointProgress) {
                            Text("Seed orb").tag(LiminalV008Runtime.orbProgress)
                            Text("Curled").tag(LiminalV008Runtime.curledProgress)
                            Text("Standing").tag(LiminalV008Runtime.standingProgress)
                        }.pickerStyle(.segmented)
                        Text("Pose is a visual choice. Your Seed cursor and saved development stay with you.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Keep this appearance") { store.rememberPreferences = true; store.savePreferences() }
                    }
                }
            }.accessibilityIdentifier("liminal-v008.appearance")
        }
    }
}

@MainActor
private struct LiminalKnowledgePreview: View {
    @ObservedObject var store: CompanionStore
    let asset: LiminalPointAsset
    @State private var inspection = false
    @State private var map: LiminalKnowledgeBindings?
    @State private var sidecar: LiminalKnowledgeBindings.Sidecar?
    @State private var sessionID = UUID().uuidString
    @State private var origin: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let graph = store.companionGraphSnapshot(at: context.date)
            VStack {
                Toggle("Inspect knowledge", isOn: $inspection).toggleStyle(.switch)
                    .accessibilityIdentifier("liminal-v008.inspect")
                LiminalAnimatedPresence(asset: asset, progress: store.preferences.liminalPointProgress,
                    reduceMotion: store.preferences.reduceMotion || store.preferences.quiet || systemReduceMotion,
                    seedColor: store.preferences.seedColor,
                    selectableIDs: inspection ? sidecar?.bindings.map(\.anchorID) ?? [] : [],
                    onSelectArtID: { id in
                        guard inspection, let sidecar,
                              let binding = sidecar.bindings.first(where: { $0.particleIDs.contains(id) }) else { return }
                        _ = store.inspectKnowledgeParticle(nodeID: binding.nodeID, graphDigest: sidecar.graphDigest)
                    })
                Text(inspection ? "Select an anchor to inspect its current source, version and connections."
                     : "Particle density is visual. Each anchor represents one existing record.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: graph, initial: true) { _, graph in refresh(graph) }
            .onChange(of: store.activeQiMon?.originDigest) { _, _ in refresh(graph) }
        }
    }
    private func refresh(_ graph: CompanionGraphSnapshot) {
        guard let digest = store.activeQiMon?.originDigest else { sidecar = nil; return }
        if origin != digest { map = nil; sidecar = nil; sessionID = UUID().uuidString; origin = digest }
        do {
            if map == nil { map = try LiminalKnowledgeBindings(manifestSHA256: asset.manifestSHA256, lowDetailIDs: asset.lowDetailIDs) }
            sidecar = try map?.project(graph, sessionID: sessionID, originDigest: digest)
        } catch { sidecar = nil }
    }
}
