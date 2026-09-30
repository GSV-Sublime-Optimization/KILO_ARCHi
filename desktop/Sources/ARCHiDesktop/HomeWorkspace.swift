import SwiftUI

/// Home reads existing owners. Connections, play and changes still require an
/// explicit action; simply visiting this page creates no companion or save.
@MainActor
struct HomeWorkspace: View {
    @ObservedObject var store: CompanionStore
    @State private var showsShowcase = false
    @State private var showsAllFeatures = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var companionName: String { store.activeQiMon?.name ?? "ARCHi" }
    private var still: Bool { systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet }

    static func chatStatus(_ state: AssistantConnectionState) -> String {
        switch state {
        case .disconnected: "Set up chat"
        case .connecting: "Connecting…"
        case .ready: "Ready to chat"
        case .failed: "Chat needs attention"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    companionStage
                    HomeMemoryMapCard(store: store, onExplore: { store.openMemoryMap() },
                                      onShowcase: { showsShowcase = true })
                    contextPanel
                    HStack(alignment: .top, spacing: 16) {
                        HomeUnityDestination(store: store)
                        HomeMarketplaceDestination(store: store)
                    }
                    DisclosureGroup(isExpanded: $showsAllFeatures) {
                        HomeFeatureDirectory(store: store).padding(.top, 16)
                    } label: {
                        Label("Explore all features", systemImage: "square.grid.2x2")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .tint(WorkspaceTheme.accent)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("home.features-disclosure")
                }
                .frame(maxWidth: 1080)
                .padding(geometry.size.width < 800 ? 20 : 28)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showsShowcase) {
            VStack(spacing: 0) {
                HStack {
                    Label("Your local memory", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.muted)
                    Spacer()
                    Button("Close", systemImage: "xmark") { showsShowcase = false }
                        .keyboardShortcut("w", modifiers: .command)
                        .accessibilityIdentifier("home.showcase-close")
                }.padding(.horizontal, 20).padding(.vertical, 12)
                CompanionGraphWorkspace(store: store, initialShowcase: true)
            }
            .frame(minWidth: 720, idealWidth: 1040, minHeight: 560, idealHeight: 740)
            .background(WorkspaceTheme.background)
        }
        .onChange(of: store.section) { _, section in
            if section != .home { showsShowcase = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.workspace")
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Here, with you.").font(.system(size: 27, weight: .medium, design: .rounded))
                Text("A place to think, remember, and create together.")
                    .font(.system(size: 13)).foregroundStyle(WorkspaceTheme.muted)
            }
            Spacer(minLength: 8)
            Button { store.open(.connections) } label: {
                HStack(spacing: 7) {
                    Circle().fill(store.connectionState == .ready ? WorkspaceTheme.positive : WorkspaceTheme.muted)
                        .frame(width: 6, height: 6)
                    Text(Self.chatStatus(store.connectionState))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
            .accessibilityLabel("Chat connection")
            .accessibilityValue(Self.chatStatus(store.connectionState))
            .accessibilityIdentifier("home.connections")
            .help("Manage your chat connection")
        }
    }

    private var companionStage: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(WorkspaceTheme.accent.opacity(0.06)).frame(width: 84, height: 84)
                CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                    size: 82, reduceMotion: still,
                    treatment: store.preferences.visualTreatment, recipe: store.presentationRecipe,
                    naturalVariation: store.presentationNaturalVariation, equipment: store.preferences.equipment,
                    lightExpression: store.kinLightExpression, seedColor: store.preferences.seedColor)
                    .accessibilityLabel("\(companionName), current companion appearance")
            }.frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 8) {
                Text(companionName).font(.system(size: 24, weight: .medium, design: .rounded))
                Text(store.isVisible ? "Your companion on the desktop" : "Your companion is taking a break")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if store.assistantActivity != .idle {
                    Text(store.assistantActivity.title)
                        .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 12) {
                Button { store.open(.assistant) } label: {
                    Label("Let's talk", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .accessibilityLabel("Talk with \(companionName)")
                .accessibilityIdentifier("home.ask")
                Button("Customize", systemImage: "slider.horizontal.3") { store.open(.appearance) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.accent)
                    .accessibilityIdentifier("home.appearance")
                    .help("Your companion's appearance and growth")
            }
        }
        .padding(18)
        .background {
            RadialGradient(colors: [WorkspaceTheme.accent.opacity(0.09), .clear],
                           center: .leading, startRadius: 20, endRadius: 380)
        }
        .modifier(WorkspaceSurface(emphasis: true))
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceTheme.corner))
    }

    private var contextPanel: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text").font(.system(size: 21, weight: .light))
                .foregroundStyle(WorkspaceTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.sourceName == nil ? "Work together" : "Continue together")
                    .font(.system(size: 15, weight: .medium))
                Text(store.sourceName ?? "Bring a document. Read, write, and refine with ARCHi.")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.muted).lineLimit(2)
                    .help(store.sourceName ?? "Choose a document to read or refine")
            }
            Spacer(minLength: 0)
            Button(store.sourceName == nil ? "Choose a document" : "Open document", systemImage: "arrow.right") {
                store.open(.context)
            }
            .buttonStyle(WorkspaceActionStyle())
            .accessibilityIdentifier("home.document")
        }.padding(18).modifier(WorkspaceSurface())
    }
}
