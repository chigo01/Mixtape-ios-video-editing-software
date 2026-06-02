//
//  ProjectListScreen.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import SwiftUI

struct ProjectListScreen: View {
    var body: some View {
        AppGlobalBackgroundScaffold {
    
                NavigationStack {
                    
                    SizedBox(height: 20)
                    
                                Text("Studio WorkSpace").font(.custom( "", size: 18))
                    SizedBox(height: 12)
                    Text("Manage and curate your visual narratives")
                        .font(.custom("", size: 15))
                        .foregroundStyle(Color.appColors.darkPrimary)
                    
                    SizedBox(height: 12)
                

                    NavigationLink(destination: CreateProjectScreen()) {
                        HStack {

                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.black)


                            Text("New Project")
                                .font(.title2)
                                .kerning(2)

                                .fontWeight(.regular)
                                .foregroundColor(.black)

                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.appColors.primaryColor.opacity(0.8))

                        .cornerRadius(8)

                    }
                    SizedBox(height: 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(projectMockModels) { project in
                                ProjectCardView(project: project)




                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                }
            
//            .padding(
//                
//            )
            .padding(.horizontal)
        }
        }
    }



#Preview {
    NavigationStack {
        ProjectListScreen()
    }
}




