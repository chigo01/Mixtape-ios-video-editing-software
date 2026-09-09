import SwiftUI
import Photos
import UIKit

/// One navigation stack keeps the dashboard bar out of the editor and media picker.
struct DashboardScreen: View {
    @State private var selectedTab: DashboardTab = .projects
    @State private var path: [ProjectListRoute] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var tabSelection

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch selectedTab {
                case .projects: ProjectListScreen()
                case .templates: TemplateGalleryScreen()
                case .settings: DashboardSettingsScreen()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbar(selectedTab == .projects ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(Color.appColors.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.appColors.backgroundColor.ignoresSafeArea())
            .navigationDestination(for: ProjectListRoute.self) { route in
                switch route {
                case .createProject:
                    CreateProjectScreen { path = [.editor($0)] }
                        .toolbar(.visible, for: .navigationBar)
                case .editor(let project):
                    EditorScreen(project: project).id(project.id)
                case .template(let template):
                    TemplateDetailScreen(template: template) { path = [.editor($0)] }
                        .toolbar(.visible, for: .navigationBar)
                }
            }
        }
        .tint(Color.appColors.primaryColor)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if #available(iOS 26.0, *) {
            Group {
                if reduceTransparency {
                    tabItems(floating: true)
                        .background(Color.appColors.backgroundColor, in: Capsule())
                        .overlay { Capsule().strokeBorder(.white.opacity(0.18)) }
                } else {
                    tabItems(floating: true)
                        .glassEffect(.regular.tint(.black.opacity(0.8)), in: Capsule())
                }
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
        } else {
            tabItems(floating: false)
                .background(Color.appColors.backgroundColor.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5) }
        }
    }

    private func tabItems(floating: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                        Text(tab.rawValue).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.appColors.primaryColor : Color.white.opacity(0.65))
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if floating && selectedTab == tab {
                            Capsule().fill(.white.opacity(0.1))
                                .matchedGeometryEffect(id: "selectedTab", in: tabSelection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
    }

}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case projects = "Projects", templates = "Templates", settings = "Settings"
    var id: Self { self }
    var icon: String {
        switch self {
        case .projects: "square.stack.3d.up.fill"
        case .templates: "rectangle.grid.2x2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct TemplateGalleryScreen: View {
    @State private var templates: [EditorProjectTemplate] = []
    @State private var search = ""
    @State private var sortByName = false
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [EditorProjectTemplate] {
        let matches = templates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return sortByName ? matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matches
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your next edit starts here.").font(.title2.bold())
                    Text("Browse your saved styles, explore the details, and make them your own.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your templates", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text("MY TEMPLATES · \(templates.count)").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Sort templates", selection: $sortByName) {
                            Text("Recently saved").tag(false)
                            Text("Name").tag(true)
                        }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                }
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("Save your signature style", systemImage: "rectangle.grid.2x2")
                    } description: {
                        Text("Open a project, choose Templates in the editor, and save your edit with a name. It will appear here with its timing, text, audio, and media slots.")
                    } actions: {
                        NavigationLink("Create a Project", value: ProjectListRoute.createProject)
                            .buttonStyle(.borderedProminent).foregroundStyle(.black)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 340), spacing: 16)], spacing: 22) {
                        ForEach(filtered) { template in
                            NavigationLink(value: ProjectListRoute.template(template)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    TemplateArtwork(template: template)
                                        .aspectRatio(0.8, contentMode: .fit)
                                        .overlay(alignment: .bottomTrailing) {
                                            Text(template.project.formattedDuration)
                                                .font(.caption.monospacedDigit().bold())
                                                .padding(7).background(.black.opacity(0.7), in: Capsule()).padding(10)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                    Text(template.name).font(.headline).lineLimit(2)
                                    Text("\(template.slots.count) slots · \(template.project.canvasSettings.format.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }
        .background(Color.appColors.backgroundColor)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private func reload() { templates = EditorTemplateStore.shared.loadAll() }
}

private struct TemplateArtwork: View {
    let template: EditorProjectTemplate
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color.appColors.primaryColor.opacity(0.35), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film.stack").font(.system(size: 40)).foregroundStyle(Color.appColors.primaryColor)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: template.id) {
            if let url = EditorTemplateStore.shared.thumbnailURL(for: template) {
                image = UIImage(contentsOfFile: url.path)
            }
        }
        .accessibilityLabel("\(template.name) cover image")
    }
}

struct TemplateDetailScreen: View {
    let template: EditorProjectTemplate
    let onCreated: (EditorProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var validation: EditorTemplateValidation?
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TemplateArtwork(template: template)
                    .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.name).font(.largeTitle.bold())
                    Text("\(template.project.formattedDuration) · \(template.project.canvasSettings.format.title)")
                        .foregroundStyle(.secondary)
                    Text("Saved \(template.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Start a new project with this template’s original media and styling. Replace clips in the editor to make it yours.")
                    .foregroundStyle(.secondary)
                if let validation, !validation.isReady {
                    Label("\(validation.issueCount) original assets are unavailable. Restore access in Settings or replace missing media in the editor. Missing audio or graphics may be omitted.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Included in this template").font(.headline)
                    Label("\(template.primarySlotCount) primary clips · \(template.overlaySlotCount) overlays", systemImage: "film.stack")
                    Label("\(template.project.textOverlays.count) text layers · \(template.requiredFontFamilies.count) font styles", systemImage: "textformat")
                    Label("\(template.project.audioClips.count) audio clips", systemImage: "waveform")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                if !template.slots.isEmpty {
                    Text("Media slots").font(.headline)
                    ForEach(template.slots.sorted { $0.order < $1.order }) { slot in
                        HStack {
                            Image(systemName: slot.mediaKind == .image ? "photo" : "film")
                                .foregroundStyle(Color.appColors.primaryColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slot.title)
                                Text("\(slot.role.rawValue.capitalized) · \(slot.mediaKind.rawValue.capitalized)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1fs", slot.targetDuration)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appColors.backgroundColor)
        .navigationTitle("Template details").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Delete Template", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isCreating = true
                do { onCreated(try EditorTemplateStore.shared.createProject(from: template)) }
                catch { self.error = error.localizedDescription }
                isCreating = false
            } label: {
                Label("Use Template", systemImage: "wand.and.stars")
                    .font(.headline).frame(maxWidth: .infinity).padding(10)
            }
            .buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(isCreating)
            .padding().background(.ultraThinMaterial)
        }
        .onAppear { validation = EditorTemplateStore.shared.validation(for: template) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { validation = EditorTemplateStore.shared.validation(for: template) }
        }
        .confirmationDialog("Delete “\(template.name)” ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Template", role: .destructive) {
                do { try EditorTemplateStore.shared.delete(template); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("This removes the saved template. Projects already created from it keep their own assets.") }
        .alert("Couldn’t complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct DashboardSettingsScreen: View {
    @AppStorage("export.defaultResolution") private var resolution = EditorExportResolution.p1080.rawValue
    @AppStorage("export.defaultFrameRate") private var frameRate = EditorExportFrameRate.fps30.rawValue
    @AppStorage("export.defaultQuality") private var quality = EditorExportQuality.balanced.rawValue
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var cacheStats: EditorMediaCacheStats?
    @State private var isClearingCache = false
    @State private var confirmClearCache = false
    @State private var showOnboarding = false
    @State private var cacheMessage: String?


    var body: some View {
        Form {
            Section {
                Label("Make room for your next story.", systemImage: "film.stack.fill")
                    .font(.headline).padding(.vertical, 10)
            }
            Section {
                Picker("Resolution", selection: $resolution) {
                    ForEach(EditorExportResolution.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Frame rate", selection: $frameRate) {
                    ForEach(EditorExportFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0.rawValue) }
                }
                Picker("Quality", selection: $quality) {
                    ForEach(EditorExportQuality.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: { Text("Export defaults") }
            footer: { Text("Used when you open the export screen. You can adjust them for each export.") }

            Section {
                LabeledContent("Photo library", value: photoAccessLabel)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("Manage App Permissions", systemImage: "arrow.up.forward.app") }
            } header: { Text("Permissions") }
            footer: { Text("Mixtape uses your photo library for project media and your microphone for voiceovers. Manage access in iOS Settings.") }

            Section {
                Label("Projects and templates are stored on this device.", systemImage: "internaldrive")
                Text("Templates can reference your original photos and videos. Keep those media available so you can reuse your edits.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Your library") }

            Section {
                LabeledContent("Preview cache", value: cacheStats.map {
                    ByteCountFormatter.string(fromByteCount: $0.totalBytes, countStyle: .file)
                } ?? "Calculating…")
                Button { confirmClearCache = true } label: {
                    HStack {
                        Label("Clear Cache", systemImage: "trash")
                        Spacer()
                        if isClearingCache { ProgressView() }
                    }
                }
                .disabled(isClearingCache || cacheStats == nil || cacheStats?.totalBytes == 0)
            } header: { Text("Storage") }
            footer: { Text("Removes generated proxies and preview renders. They rebuild when needed. Your projects, templates, original media, and downloaded audio are kept.") }

            Section("About") {
                Button { showOnboarding = true } label: {
                    Label("Replay Introduction", systemImage: "play.rectangle")
                }
                LabeledContent("Mixtape", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }
        }
        .scrollContentBackground(.hidden).background(Color.appColors.backgroundColor)
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingScreen { showOnboarding = false }
        }
        .onAppear { refreshAccess() }
        .task { cacheStats = await EditorMediaCache.shared.stats() }
        .confirmationDialog("Clear preview cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) { clearCache() }
        } message: { Text("Generated previews will rebuild the next time you edit. Saved projects and media are kept.") }
        .alert("Cache", isPresented: Binding(get: { cacheMessage != nil }, set: { if !$0 { cacheMessage = nil } })) {
            Button("OK") { cacheMessage = nil }
        } message: { Text(cacheMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshAccess() } }
    }

    private func clearCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        Task {
            do {
                try await EditorMediaCache.shared.clearDisposableCache()
                cacheMessage = "Preview cache cleared."
            } catch {
                cacheMessage = error.localizedDescription
            }
            cacheStats = await EditorMediaCache.shared.stats()
            isClearingCache = false
        }
    }

    private func refreshAccess() { photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    private var photoAccessLabel: String {
        switch photoAccess {
        case .authorized: "Full access"
        case .limited: "Selected photos"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

#Preview { DashboardScreen() }
