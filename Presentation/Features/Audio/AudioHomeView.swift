//
//  AudioHomeView.swift
//  Mixtape
//

import SwiftUI

struct AudioHomeView: View {
    var body: some View {
        ZStack {
            AppTheme.secondary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {}) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.neutral)
                    }
                    
                    Spacer()
                    
                    Text("MIXTAPE")
                        .font(AppTheme.Typography.headlineMedium)
                        .fontWeight(.black)
                        .foregroundColor(AppTheme.primary)
                    
                    Spacer()
                    
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan) // Placeholder for avatar
                        .background(Circle().fill(Color.white))
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        colors: [AppTheme.tertiary, AppTheme.secondary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(AppTheme.neutral)
                            
                            TextField("Search audio, moods, or genres...", text: .constant(""))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .font(AppTheme.Typography.bodyDefault)
                            
                            Image(systemName: "mic.fill")
                                .foregroundColor(AppTheme.neutral)
                        }
                        .padding()
                        .background(AppTheme.tertiary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.primary.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // Top Tabs
                        HStack(spacing: 0) {
                            TabButton(title: "Music", isSelected: true)
                            TabButton(title: "SFX", isSelected: false)
                            TabButton(title: "My Audio", isSelected: false)
                        }
                        .background(AppTheme.tertiary)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Categories Pill List
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                CategoryPill(title: "Cinematic", isSelected: true)
                                CategoryPill(title: "Vlog", isSelected: false)
                                CategoryPill(title: "Upbeat", isSelected: false)
                                CategoryPill(title: "Lo-Fi", isSelected: false)
                                CategoryPill(title: "Ambient", isSelected: false)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Trending Collections
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Trending Collections")
                                .font(AppTheme.Typography.headlineMedium)
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    CollectionCard(tag: "NEW", title: "Festival Hype", imageColor: Color.blue.opacity(0.3))
                                    CollectionCard(tag: "ESSENTIALS", title: "Analog Synths", imageColor: Color.purple.opacity(0.3))
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Audio Track List
                        VStack(spacing: 12) {
                            AudioTrackRow(
                                title: "Neon Nights",
                                duration: "2:45",
                                isPlaying: true,
                                isAdded: true
                            )
                            AudioTrackRow(
                                title: "Urban Drift",
                                duration: "1:12",
                                isPlaying: false,
                                isAdded: false
                            )
                            AudioTrackRow(
                                title: "Deep Space Drone",
                                duration: "3:05",
                                isPlaying: false,
                                isAdded: false
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 100) // Space for bottom tab bar
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

// MARK: - Components

struct TabButton: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(AppTheme.Typography.bodyDefault.weight(isSelected ? .semibold : .medium))
            .foregroundColor(isSelected ? AppTheme.Colors.textPrimary : AppTheme.neutral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? AppTheme.secondary : Color.clear)
            .cornerRadius(10)
            .padding(4)
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(AppTheme.Typography.bodyDefault)
            .foregroundColor(isSelected ? AppTheme.primary : AppTheme.neutral)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.clear)
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.primary : AppTheme.neutral.opacity(0.5), lineWidth: 1)
            )
    }
}

struct CollectionCard: View {
    let tag: String
    let title: String
    let imageColor: Color
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [imageColor, AppTheme.tertiary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 180, height: 100)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tag)
                    .font(AppTheme.Typography.labelCaps)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary)
                
                Text(title)
                    .font(AppTheme.Typography.bodyDefault)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            .padding(12)
        }
    }
}

struct AudioTrackRow: View {
    let title: String
    let duration: String
    let isPlaying: Bool
    let isAdded: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause Button
            Button(action: {}) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isPlaying ? AppTheme.primary : AppTheme.neutral)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.secondary)
                    .clipShape(Circle())
            }
            
            // Track Info & Waveform
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Typography.bodyDefault.weight(.semibold))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                // Soundwave Placeholder
                HStack(spacing: 3) {
                    ForEach(0..<12) { i in
                        Capsule()
                            .fill(isPlaying ? AppTheme.primary : AppTheme.neutral.opacity(0.3))
                            .frame(width: 3, height: isPlaying ? CGFloat.random(in: 4...12) : 4)
                    }
                }
            }
            
            Spacer()
            
            // Duration
            Text(duration)
                .font(AppTheme.Typography.bodyDefault)
                .foregroundColor(AppTheme.neutral)
            
            // Add Button
            Button(action: {}) {
                if isAdded {
                    Text("ADD")
                        .font(AppTheme.Typography.labelCaps.weight(.bold))
                        .foregroundColor(AppTheme.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.neutral)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.neutral.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .background(AppTheme.tertiary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPlaying ? AppTheme.primary : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    AudioHomeView()
}
