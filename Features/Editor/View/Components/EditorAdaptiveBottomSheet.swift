//
//  EditorAdaptiveBottomSheet.swift
//  Mixtape
//
//  Keeps editor tools non-modal and bottom-attached on iPad while retaining
//  native sheets on iPhone.
//

import SwiftUI
import UIKit

enum EditorSheetHeight {
    case fixed(CGFloat)
    case fraction(CGFloat)

    func resolved(in availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .fixed(let height):
            return min(max(height, 160), availableHeight)
        case .fraction(let fraction):
            return availableHeight * min(max(fraction, 0.2), 1)
        }
    }
}

extension View {
    func editorSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        iPadHeight: EditorSheetHeight,
        allowsBackdropDismiss: Bool = true,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        let usesIPadDrawer = UIDevice.current.userInterfaceIdiom == .pad
        let nativeSheetPresentation = Binding(
            get: { !usesIPadDrawer && isPresented.wrappedValue },
            set: { newValue in
                guard !usesIPadDrawer else { return }
                isPresented.wrappedValue = newValue
            }
        )

        return self
            // Keep the iPhone editor in the same native presentation hierarchy it
            // had before iPad drawers were introduced. A stable modifier chain is
            // important here because rebuilding the editor root also rebuilds its
            // AVPlayer at time zero.
            .sheet(isPresented: nativeSheetPresentation, content: content)
            .overlay(alignment: .bottom) {
                if usesIPadDrawer && isPresented.wrappedValue {
                    EditorIPadBottomSheet(
                        isPresented: isPresented,
                        height: iPadHeight,
                        allowsDragDismiss: allowsBackdropDismiss,
                        content: content
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                .easeOut(duration: 0.22),
                value: usesIPadDrawer && isPresented.wrappedValue
            )
    }
}

private struct EditorIPadBottomSheet<SheetContent: View>: View {
    @Binding var isPresented: Bool
    let height: EditorSheetHeight
    let allowsDragDismiss: Bool
    let content: () -> SheetContent

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(geometry.size.height - geometry.safeAreaInsets.top, 0)
            let sheetHeight = height.resolved(in: availableHeight)

            VStack(spacing: 0) {
                dragHandle
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: sheetHeight)
            .background(Color.appColors.backgroundColor)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    topTrailingRadius: 28
                )
            )
            .shadow(color: .black.opacity(0.4), radius: 28, y: -8)
            .offset(y: dragOffset)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.34))
            .frame(width: 48, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard allowsDragDismiss else { return }
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        guard allowsDragDismiss else { return }
                        if value.translation.height > 110
                            || value.predictedEndTranslation.height > 180 {
                            isPresented = false
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .accessibilityLabel("Dismiss sheet")
    }
}
