//
//  File.swift
//  Mixtape
//
//  Created by Favour Baruch on 07/05/2026.
//

import Foundation

struct ProjectMockModel: Identifiable {
    var id: UUID
    var title: String
    var imageUrl: String
    var editedBy: String
    var legnt: String
}

let projectMockModels: [ProjectMockModel] = [
    ProjectMockModel(
        id: UUID(),
        title: "Summer Beats",
        imageUrl: "DemoPhoto",
        editedBy: "DJ Flow",
        legnt: "3:45"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Night Vibes",
        imageUrl: "DemoPhoto",
        editedBy: "MC Chill",
        legnt: "4:12"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Golden Hour",
        imageUrl: "DemoPhoto",
        editedBy: "Sunset Sounds",
        legnt: "2:59"
    ),
    
    
    ProjectMockModel(
        id: UUID(),
        title: "Summer Beats",
        imageUrl: "DemoPhoto",
        editedBy: "DJ Flow",
        legnt: "3:45"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Night Vibes",
        imageUrl: "DemoPhoto",
        editedBy: "MC Chill",
        legnt: "4:12"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Golden Hour",
        imageUrl: "DemoPhoto",
        editedBy: "Sunset Sounds",
        legnt: "2:59"
    ),
    
    
    ProjectMockModel(
        id: UUID(),
        title: "Summer Beats",
        imageUrl: "DemoPhoto",
        editedBy: "DJ Flow",
        legnt: "3:45"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Night Vibes",
        imageUrl: "DemoPhoto",
        editedBy: "MC Chill",
        legnt: "4:12"
    ),
    ProjectMockModel(
        id: UUID(),
        title: "Golden Hour",
        imageUrl: "DemoPhoto",
        editedBy: "Sunset Sounds",
        legnt: "2:59"
    )
]
