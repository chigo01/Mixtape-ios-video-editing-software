//
//  AppGlobalBackgroundScaffold.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI

struct AppGlobalBackgroundScaffold<Content: View>: View {
   
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack(alignment:.leading,  ) {
            Color.appColors.backgroundColor.ignoresSafeArea()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Example preview:
//#Preview {
//    AppGlobalBackgroundScaffold {
//        Text("Hello, World!")
//            .padding()
//    }
//}
