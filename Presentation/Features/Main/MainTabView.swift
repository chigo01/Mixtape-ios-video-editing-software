//
//  MainTabView.swift
//  Mixtape
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                AudioHomeView()
                    .tag(0)
                
                Color.black // Transitions Placeholder
                    .tag(1)
                
                Color.black // Settings Placeholder
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Hide default tab view
            .ignoresSafeArea()

            CustomTabBar(selectedTab: $selectedTab)
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.neutral.opacity(0.3))
            
            HStack {
                TabBarItem(
                    iconName: "music.note.list",
                    title: "AUDIO",
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }
                
                Spacer()
                
                TabBarItem(
                    iconName: "circle.grid.cross",
                    title: "TRANSITIONS",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
                
                Spacer()
                
                TabBarItem(
                    iconName: "gearshape.fill",
                    title: "SETTINGS",
                    isSelected: selectedTab == 2
                ) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
        }
        .background(
            AppTheme.tertiary.ignoresSafeArea(edges: .bottom)
        )
    }
}

struct TabBarItem: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                Text(title)
                    .font(AppTheme.Typography.labelCaps)
            }
            .foregroundColor(isSelected ? AppTheme.primary : AppTheme.neutral)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    MainTabView()
}
