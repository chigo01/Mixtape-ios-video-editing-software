//
//  SequenceStructurePanel.swift
//  Mixtape
//

import SwiftUI
import PhotosUI

struct SequenceSelectionActionBar: View {
    let vm: EditorViewModel
    let onStructure: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { vm.endMultiSelection() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish selecting")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    sequenceAction("GROUP", image: "rectangle.3.group") { vm.groupSelectedItems() }
                        .disabled(!vm.canCreateSequence)
                    sequenceAction("COMPOUND", image: "square.stack.3d.up.fill") { vm.createCompoundClip() }
                        .disabled(!vm.canCreateSequence)
                    sequenceAction("EARLIER", image: "arrow.left") { vm.moveSelectionEarlier() }
                        .disabled(vm.selectionCount == 0)
                    sequenceAction("LATER", image: "arrow.right") { vm.moveSelectionLater() }
                        .disabled(vm.selectionCount == 0)
                    sequenceAction("DUPLICATE", image: "plus.square.on.square") {
                        vm.duplicateSelectedTimelineItems()
                    }
                    .disabled(vm.selectionCount == 0)
                    sequenceAction("STRUCTURE", image: "list.bullet.indent") { onStructure() }
                    sequenceAction("DELETE", image: "trash", destructive: true) {
                        vm.deleteSelectedTimelineItems()
                    }
                    .disabled(vm.selectionCount == 0)
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.leading, 4)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(
            Rectangle().fill(Color.white.opacity(0.02))
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5), alignment: .top)
        )
    }

    private func sequenceAction(
        _ title: String,
        image: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: image).font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5).lineLimit(1).minimumScaleFactor(0.72)
            }
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white)
            .frame(width: 82).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
    }
}

struct SequenceStructurePanel: View {
    let vm: EditorViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Sequence Structure").font(.headline)
                HStack {
                    if vm.activeSequence != nil {
                        Button { vm.exitActiveSequence() } label: {
                            Label("Up", systemImage: "arrow.turn.up.left")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.appColors.primaryColor)
                    }
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
                }
            }
            .padding(.horizontal, 18).frame(height: 48)

            Divider().overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let active = vm.activeSequence {
                        Label("Editing inside \(active.title)", systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline.bold()).foregroundStyle(Color.appColors.primaryColor)
                    }

                    section("SELECTION") {
                        HStack(spacing: 10) {
                            Button("Select All") { vm.selectAllInActiveSequence() }
                                .buttonStyle(.bordered)
                            Button("Select In/Out Range") { vm.selectItemsInExportRange() }
                                .buttonStyle(.bordered)
                                .disabled(!vm.hasSelectionRange)
                            Spacer()
                            Text("\(vm.selectionCount) selected")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }

                    section("GROUPS & COMPOUNDS") {
                        if vm.visibleSequences.isEmpty {
                            Text("Select at least two timeline items, then create a group or compound clip.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.visibleSequences) { sequence in
                                SequenceRenameRow(
                                    sequence: sequence,
                                    range: vm.sequenceTimeRange(id: sequence.id),
                                    isSelected: vm.selectedSequenceID == sequence.id,
                                    onSelect: { vm.selectSequence(sequence.id) },
                                    onEnter: {
                                        vm.selectSequence(sequence.id)
                                        vm.enterSelectedSequence()
                                    },
                                    onRename: { vm.renameSequence(id: sequence.id, title: $0) }
                                )
                            }
                        }

                        if vm.selectedSequence != nil {
                            HStack {
                                Button { vm.enterSelectedSequence() } label: {
                                    Label("Enter", systemImage: "arrow.down.right.and.arrow.up.left")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.appColors.primaryColor).foregroundStyle(.black)
                                Button(role: .destructive) { vm.dissolveSelectedSequence() } label: {
                                    Label("Dissolve", systemImage: "rectangle.3.group")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    section("MARKERS") {
                        Button { vm.addMarkerAtPlayhead() } label: {
                            Label("Add marker at playhead", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appColors.primaryColor).foregroundStyle(.black)

                        ForEach(vm.markers) { marker in
                            MarkerRenameRow(
                                marker: marker,
                                onSeek: { vm.seekTimeline(to: marker.time) },
                                onRename: { vm.renameMarker(id: marker.id, name: $0) },
                                onDelete: { vm.deleteMarker(id: marker.id) }
                            )
                        }
                    }
                }
                .padding(18).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
        }
        .background(Color.appColors.backgroundColor)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }
}

private struct SequenceRenameRow: View {
    let sequence: EditorSequence
    let range: ClosedRange<TimeInterval>?
    let isSelected: Bool
    let onSelect: () -> Void
    let onEnter: () -> Void
    let onRename: (String) -> Void
    @State private var title: String

    init(
        sequence: EditorSequence,
        range: ClosedRange<TimeInterval>?,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onEnter: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.sequence = sequence
        self.range = range
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onEnter = onEnter
        self.onRename = onRename
        _title = State(initialValue: sequence.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: sequence.kind == .compound ? "square.stack.3d.up.fill" : "rectangle.3.group")
                    .foregroundStyle(isSelected ? Color.appColors.primaryColor : .white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(title) }
                .onDisappear { onRename(title) }
            if let range {
                Text(String(format: "%.1f–%.1fs", range.lowerBound, range.upperBound))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button(action: onEnter) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}

private struct MarkerRenameRow: View {
    let marker: EditorTimelineMarker
    let onSeek: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var name: String

    init(
        marker: EditorTimelineMarker,
        onSeek: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.marker = marker
        self.onSeek = onSeek
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: marker.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSeek) {
                Text(String(format: "%.2fs", marker.time))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.appColors.primaryColor)
            }
            .buttonStyle(.plain)
            TextField("Marker name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(name) }
                .onDisappear { onRename(name) }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
        }
    }
}

