//
//  ProjectCardView.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI

struct ProjectCardView: View {
    var project: ProjectMockModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            Image(project.imageUrl)
                .resizable()
                .aspectRatio(contentMode: .fit)
                //.frame(width: .infinity, height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 8))
             
            
            
            Text(project.legnt)
                .frame(width: 70, height: 30)
                .background(.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(20)
                .padding()
          
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                Text("Edited by \(project.editedBy)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
               
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding()
        
        }
    }
}

