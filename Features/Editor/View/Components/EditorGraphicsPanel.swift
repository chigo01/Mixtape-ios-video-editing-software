//
//  EditorGraphicsPanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

// MARK: - Stickers and reusable graphics

struct EditorGraphicsPanel: View {
    let vm: EditorViewModel
    @State private var category: GraphicLibraryCategory = .emoji
    @State private var query = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var favoriteIDs = EditorGraphicFavoritesStore.ids
    @State private var importError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let graphic = vm.selectedGraphicOverlay { inspector(graphic) }
                    searchField
                    categoryStrip
                    libraryGrid
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
        .alert("Couldn’t Import Graphic", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? "Unknown error") }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    try vm.importGraphicImageData(data)
                } catch { importError = error.localizedDescription }
                photoItem = nil
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Stickers & Graphics").font(.headline)
                Text("Reusable visual layers").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { vm.commitGraphicEdit(); vm.selectedTool = nil }
                    .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
            }
        }
        .padding(.horizontal, 18).frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(GraphicLibraryCategory.allCases) { item in
                    Button { category = item } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(.caption.bold()).padding(.horizontal, 13).frame(height: 36)
                            .foregroundStyle(category == item ? .black : .white)
                            .background(Capsule().fill(category == item ? Color.appColors.primaryColor : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var libraryGrid: some View {
        if category == .imported {
            VStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Import PNG, photo or artwork", systemImage: "photo.badge.plus")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(.black)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appColors.primaryColor))
                }
                Text("Mixtape copies the graphic into project-safe storage. Transparent PNGs stay transparent.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else if filteredSources.isEmpty {
            ContentUnavailableView(
                category == .favorites ? "No Favorites Yet" : "No Results",
                systemImage: category == .favorites ? "heart" : "magnifyingglass",
                description: Text(category == .favorites ? "Long-press the heart on any graphic to keep it reusable." : "Try another search.")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredSources, id: \.catalogID) { source in graphicCell(source) }
            }
        }
    }

    private func graphicCell(_ source: EditorGraphicSource) -> some View {
        Button { vm.addGraphic(source: source) } label: {
            ZStack(alignment: .topTrailing) {
                graphicPreview(source)
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.07)))
                if favoriteIDs.contains(source.catalogID) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.appColors.primaryColor)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                EditorGraphicFavoritesStore.toggle(source)
                favoriteIDs = EditorGraphicFavoritesStore.ids
            } label: {
                Label(
                    favoriteIDs.contains(source.catalogID) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: favoriteIDs.contains(source.catalogID) ? "heart.slash" : "heart"
                )
            }
        }
        .accessibilityLabel("Add \(source.displayName)")
        .accessibilityHint("Double tap to place on the preview. Long press for favorites.")
    }

    @ViewBuilder
    private func graphicPreview(_ source: EditorGraphicSource) -> some View {
        switch source {
        case let .emoji(value): Text(value).font(.system(size: 34))
        case let .symbol(name): Image(systemName: name).resizable().scaledToFit().padding(20).foregroundStyle(.white)
        case let .image(path):
            if let image = UIImage(contentsOfFile: path) { Image(uiImage: image).resizable().scaledToFit().padding(7) }
        }
    }

    private func inspector(_ graphic: EditorGraphicOverlay) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                graphicPreview(graphic.source).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(graphic.title).font(.subheadline.bold()).lineLimit(1)
                    Text("\(format(graphic.startTime)) – \(format(graphic.endTime))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                inspectorButton(
                    favoriteIDs.contains(graphic.source.catalogID) ? "heart.fill" : "heart",
                    "Favorite"
                ) {
                    EditorGraphicFavoritesStore.toggle(graphic.source)
                    favoriteIDs = EditorGraphicFavoritesStore.ids
                }
                inspectorButton("doc.on.doc", "Duplicate") { vm.duplicateSelectedGraphic() }
                inspectorButton("trash", "Delete", destructive: true) { vm.deleteSelectedGraphic() }
            }
            control("Size", value: Double(graphic.size), range: 40...320) { value in
                vm.updateSelectedGraphic { $0.size = CGFloat(value) }
            }
            control("Scale", value: Double(graphic.scale), range: 0.25...3) { value in
                vm.updateSelectedGraphic { $0.scale = CGFloat(value) }
            }
            control("Rotate", value: graphic.rotationDegrees, range: -180...180) { value in
                vm.updateSelectedGraphic { $0.rotationDegrees = value }
            }
            control("Opacity", value: graphic.opacity, range: 0...1) { value in
                vm.updateSelectedGraphic { $0.opacity = value }
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(EditorGraphicAnimation.allCases) { value in
                        Button(value.title) { vm.updateSelectedGraphic { $0.animation = value }; vm.commitGraphicEdit() }
                    }
                } label: { inspectorMenu("Animation", graphic.animation.title, "waveform.path") }
                Menu {
                    ForEach(EditorGraphicBlendMode.allCases) { value in
                        Button(value.title) { vm.updateSelectedGraphic { $0.blendMode = value }; vm.commitGraphicEdit() }
                    }
                } label: { inspectorMenu("Blend", graphic.blendMode.title, "circle.hexagongrid") }
                Button {
                    vm.updateSelectedGraphic { $0.isFlippedHorizontally.toggle() }; vm.commitGraphicEdit()
                } label: { inspectorMenu("Transform", "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(.plain)
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.055)))
    }

    private func control(_ title: String, value: Double, range: ClosedRange<Double>, update: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: update), in: range, onEditingChanged: { if !$0 { vm.commitGraphicEdit() } })
                .tint(Color.appColors.primaryColor)
            Text(value.formatted(.number.precision(.fractionLength(title == "Opacity" ? 2 : 0))))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }

    private func inspectorButton(_ icon: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 34, height: 34) }
            .buttonStyle(.plain).foregroundStyle(destructive ? .red : Color.appColors.primaryColor)
            .background(Circle().fill(Color.white.opacity(0.07))).accessibilityLabel(label)
    }

    private func inspectorMenu(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.body.bold())
            Text(value).font(.caption2.bold()).lineLimit(1)
        }.frame(maxWidth: .infinity).frame(height: 52)
            .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.07)))
            .accessibilityLabel("\(label): \(value)")
    }

    private var filteredSources: [EditorGraphicSource] {
        let all: [EditorGraphicSource]
        switch category {
        case .emoji: all = EditorGraphicCatalog.emojis.map(EditorGraphicSource.emoji)
        case .symbols: all = EditorGraphicCatalog.symbols.map(EditorGraphicSource.symbol)
        case .favorites:
            all = favoriteIDs.compactMap(EditorGraphicSource.init(catalogID:))
            return all.filter(matches)
        case .imported: return []
        }
        return all.filter(matches)
    }

    private func matches(_ source: EditorGraphicSource) -> Bool {
        query.isEmpty || source.displayName.localizedCaseInsensitiveContains(query)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private enum GraphicLibraryCategory: String, CaseIterable, Identifiable {
    case emoji, symbols, favorites, imported
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .emoji: return "face.smiling"
        case .symbols: return "sparkles"
        case .favorites: return "heart.fill"
        case .imported: return "photo.badge.plus"
        }
    }
}

