//
//  RococoSmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/12/26.
//

import SwiftUI

struct RococoSmallWorldView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    @Namespace private var animation
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case both = "并排显示"
        case upper = "显示上层"
        case lower = "显示下层"
        
        var id: String { rawValue }
    }
    
    @State private var viewMode: ViewMode = .both
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                
                ZStack {
                    // App Global Background
                    LiquidBackground()
                    
                    Group {
                        switch viewMode {
                        case .both:
                            if isLandscape {
                                // Landscape: Side by Side (Left: Floor 1, Right: Floor 2)
                                HStack(spacing: 0) {
                                    roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width / 2, height: geometry.size.height)
                                        .matchedGeometryEffect(id: "room1", in: animation)
                                    roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width / 2, height: geometry.size.height)
                                        .matchedGeometryEffect(id: "room2", in: animation)
                                }
                            } else {
                                // Portrait: Stacked (Top: Floor 1, Bottom: Floor 2)
                                VStack(spacing: -80) { // Negative spacing to bring them closer
                                    roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width, height: geometry.size.height / 2)
                                        .matchedGeometryEffect(id: "room1", in: animation)
                                    roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width, height: geometry.size.height / 2)
                                        .matchedGeometryEffect(id: "room2", in: animation)
                                }
                            }
                        case .upper:
                            roomView(imageName: "small_world_rococo_1", geometry: geometry, width: geometry.size.width, height: geometry.size.height)
                                .matchedGeometryEffect(id: "room1", in: animation)
                        case .lower:
                            roomView(imageName: "small_world_rococo_2", geometry: geometry, width: geometry.size.width, height: geometry.size.height)
                                .matchedGeometryEffect(id: "room2", in: animation)
                        }
                    }
                    .transition(.opacity)
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isLandscape)
                .animation(.easeInOut, value: viewMode)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("视图模式", selection: $viewMode) {
                                ForEach(ViewMode.allCases) { mode in
                                    Label(mode.rawValue, systemImage: iconForMode(mode)).tag(mode)
                                }
                            }
                        } label: {
                            if #available(iOS 26.0, *) {
                                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                            } else {
                                Image(systemName: "line.3.horizontal.circle")
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
    
    private func iconForMode(_ mode: ViewMode) -> String {
        switch mode {
        case .both: return "rectangle.split.1x2"
        case .upper: return "rectangle.topthird.inset.filled"
        case .lower: return "rectangle.bottomthird.inset.filled"
        }
    }
    
    @ViewBuilder
    private func roomView(imageName: String, geometry: GeometryProxy, width: CGFloat, height: CGFloat) -> some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .clipped()
            // Placeholder for future interactions
            .overlay(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Handle tap
                        print("Tapped on \(imageName)")
                    }
            )
    }
}
