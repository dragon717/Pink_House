//
//  CalendarSettingsView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI

struct CalendarSettingsView: View {
    @Environment(CalendarThemeManager.self) private var themeManager
    
    var body: some View {
        AdaptiveSettingsView(title: "日历设置") {
            AdaptiveSection(header: "日历主题") {
                ForEach(themeManager.availableThemes, id: \.id) { theme in
                    HStack {
                        Circle()
                            .fill(Color(uiColor: theme.accentColor))
                            .frame(width: 20, height: 20)
                        
                        Text(theme.displayName)
                            .font(.custom(theme.fontName, size: 16))
                        
                        Spacer()
                        
                        if themeManager.currentTheme.id == theme.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(uiColor: theme.accentColor))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            themeManager.setTheme(theme)
                        }
                    }
                    .adaptiveRow(showDivider: theme.id != themeManager.availableThemes.last?.id)
                }
            }
            
            AdaptiveSection(header: "预览") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("日历配色预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 20) {
                        ColorPreviewCircle(color: Color(uiColor: themeManager.currentTheme.backgroundColor), name: "背景")
                        ColorPreviewCircle(color: Color(uiColor: themeManager.currentTheme.accentColor), name: "强调")
                        ColorPreviewCircle(color: Color(uiColor: themeManager.currentTheme.depositColor), name: "定金")
                        ColorPreviewCircle(color: Color(uiColor: themeManager.currentTheme.finalPaymentColor), name: "尾款")
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}

struct ColorPreviewCircle: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .shadow(radius: 2)
            
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
