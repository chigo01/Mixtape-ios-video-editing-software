//
//  AudioLibraryPickerView.swift
//  Mixtape
//
//  Sound library browser (Priority 20). Merges the bundled starter SFX pack with a live
//  Freesound search, auditions a clip without touching the project's own playhead/player, and
//  inserts the selected item as a normal `EditorAudioClip` via
//  `EditorViewModel.insertAudioLibraryItem` — downloading + caching remote items first.
//

import SwiftUI

struct AudioLibraryPickerView: View {
    let vm: EditorViewModel
    let insertion: EditorViewModel.AudioInsertion
    var onInsert: () -> Void = {}
    var onCancel: () -> Void = {}

    @State private var library = AudioLibraryViewModel()
    @State private var pendingAttributionItem: EditorAudioLibraryItem?
    @State private var insertErrorMessage: String?

    private var searchTaskID: String {
        "\(library.searchText)|\(library.selectedCategory?.rawValue ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            searchField
                .padding(.top, 10)

            if !library.availableCategories.isEmpty {
                categoryChips
                    .padding(.top, 10)
            }

            content
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(Color.black.ignoresSafeArea())
        .onDisappear { library.stopPreview() }
        .task(id: searchTaskID) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await library.refresh()
        }
        .alert(
            "Attribution required",
            isPresented: Binding(
                get: { pendingAttributionItem != nil },
                set: { if !$0 { pendingAttributionItem = nil } }
            ),
            presenting: pendingAttributionItem
        ) { item in
            Button("Cancel", role: .cancel) {}
            Button("Insert") { insert(item, skipAttributionCheck: true) }
        } message: { item in
            Text(item.license?.attributionText ?? "This sound requires attribution when used.")
        }
        .alert(
            "Couldn't add sound",
            isPresented: Binding(
                get: { insertErrorMessage != nil },
                set: { if !$0 { insertErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(insertErrorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Sound Library")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                library.stopPreview()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            TextField("Search sounds", text: $library.searchText)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .autocorrectionDisabled(true)
            if library.isSearchingRemote {
                ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.7)
            } else if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(title: "All", systemImage: "square.grid.2x2", isSelected: library.selectedCategory == nil) {
                    library.selectedCategory = nil
                }
                ForEach(library.availableCategories) { category in
                    categoryChip(
                        title: category.displayName,
                        systemImage: category.systemImage,
                        isSelected: library.selectedCategory == category
                    ) {
                        library.selectCategory(category)
                    }
                }
            }
        }
    }

    private func categoryChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isSelected ? Color.appColors.primaryColor : .white.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .stroke(isSelected ? Color.appColors.primaryColor : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                sectionHeader("Bundled")
                if library.bundledResults.isEmpty {
                    emptyRow("No bundled sounds match your search.")
                } else {
                    ForEach(library.bundledResults) { item in
                        row(for: item)
                    }
                }

                if let remoteSourceName = library.remoteSourceName {
                    sectionHeader(remoteSourceName)
                        .padding(.top, 8)
                    remoteSection
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var remoteSection: some View {
        if library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyRow("Type to search \(library.remoteSourceName ?? "online") sounds.")
        } else if let message = library.remoteStatusMessage {
            emptyRow(message)
        } else {
            ForEach(library.remoteResults) { item in
                row(for: item)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 2)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private func row(for item: EditorAudioLibraryItem) -> some View {
        AudioLibraryItemRow(
            item: item,
            isPlaying: library.previewingItemID == item.id,
            isFavorite: library.isFavorite(item),
            isResolving: library.resolvingItemID == item.id,
            isCached: library.isCached(item),
            onTogglePreview: { library.togglePreview(item) },
            onToggleFavorite: { library.toggleFavorite(item) },
            onInsert: { insert(item, skipAttributionCheck: false) }
        )
    }

    private func insert(_ item: EditorAudioLibraryItem, skipAttributionCheck: Bool) {
        if !skipAttributionCheck, let license = item.license, license.requiresAttribution {
            pendingAttributionItem = item
            return
        }
        pendingAttributionItem = nil

        Task {
            library.stopPreview()
            do {
                let url = try await library.resolvedLocalURL(for: item)
                vm.insertAudioLibraryItem(
                    title: item.title,
                    fileURL: url,
                    duration: item.durationSeconds,
                    attribution: item.license?.attributionText,
                    insertion: insertion
                )
                onInsert()
            } catch {
                insertErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't add \"\(item.title)\"."
            }
        }
    }
}

private struct AudioLibraryItemRow: View {
    let item: EditorAudioLibraryItem
    let isPlaying: Bool
    let isFavorite: Bool
    let isResolving: Bool
    let isCached: Bool
    let onTogglePreview: () -> Void
    let onToggleFavorite: () -> Void
    let onInsert: () -> Void

    private var durationLabel: String {
        String(format: "%.1fs", item.durationSeconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTogglePreview) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color.appColors.primaryColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let category = item.category {
                        Label(category.displayName, systemImage: category.systemImage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(durationLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    if item.source == .freesound {
                        Image(systemName: isCached ? "checkmark.icloud.fill" : "icloud.and.arrow.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                if let license = item.license {
                    Text(license.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(license.requiresAttribution ? .orange.opacity(0.85) : .white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFavorite ? Color.appColors.primaryColor : .white.opacity(0.4))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Group {
                if isResolving {
                    ProgressView()
                        .tint(.black)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.appColors.primaryColor.opacity(0.6)))
                } else {
                    Button(action: onInsert) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.appColors.primaryColor))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert \(item.title)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}
