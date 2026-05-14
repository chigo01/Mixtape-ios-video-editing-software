//
//  SizedBox.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI

struct SizedBox: View {
    var width : CGFloat?
    var height : CGFloat?
    var body: some View {
        Spacer().frame(width: width, height: height)
    }
}


