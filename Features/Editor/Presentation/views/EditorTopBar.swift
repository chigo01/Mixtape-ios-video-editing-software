//
//  EditorTopBar.swift
//  Mixtape
//
//  Created by Favour Baruch on 14/05/2026.
//

import SwiftUI

struct EditorTopBar: View {
    var onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.appColors.primaryColor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
