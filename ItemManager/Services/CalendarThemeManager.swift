//
//  CalendarThemeManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI
import UIKit

protocol CalendarTheme {
    var id: String { get }
    var displayName: String { get }
    var backgroundColor: UIColor { get }
    var accentColor: UIColor { get } // 少女粉、水蓝色等
    var depositColor: UIColor { get } // 定金标记色
    var finalPaymentColor: UIColor { get } // 尾款标记色
    var fontName: String { get }
}

struct MonicaTheme: CalendarTheme {
    let id = "monica"
    let displayName = "莫妮卡 (默认)"
    let backgroundColor = UIColor(red: 1.0, green: 0.94, blue: 0.96, alpha: 1.0) // Lavender Blush
    let accentColor = UIColor(red: 0.85, green: 0.75, blue: 0.85, alpha: 1.0) // Thistle
    let depositColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Gold
    let finalPaymentColor = UIColor(red: 1.0, green: 0.41, blue: 0.71, alpha: 1.0) // Hot Pink
    let fontName = "PingFangSC-Regular"
}

struct CinderellaTheme: CalendarTheme {
    let id = "cinderella"
    let displayName = "灰姑娘"
    let backgroundColor = UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0) // Alice Blue
    let accentColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1.0) // Sky Blue
    let depositColor = UIColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0) // Orange
    let finalPaymentColor = UIColor(red: 0.25, green: 0.41, blue: 0.88, alpha: 1.0) // Royal Blue
    let fontName = "PingFangSC-Regular"
}

struct MatchaTheme: CalendarTheme {
    let id = "matcha"
    let displayName = "抹茶拿铁"
    let backgroundColor = UIColor(red: 0.94, green: 1.0, blue: 0.94, alpha: 1.0) // Honeydew
    let accentColor = UIColor(red: 0.60, green: 0.98, blue: 0.60, alpha: 1.0) // Pale Green
    let depositColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0) // Goldenrod
    let finalPaymentColor = UIColor(red: 0.13, green: 0.55, blue: 0.13, alpha: 1.0) // Forest Green
    let fontName = "PingFangSC-Regular"
}

struct GothicTheme: CalendarTheme {
    let id = "gothic"
    let displayName = "哥特人偶"
    let backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0) // Dark Gray
    let accentColor = UIColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 1.0) // Dark Red
    let depositColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0) // Light Gray
    let finalPaymentColor = UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // Red
    let fontName = "PingFangSC-Regular"
}

@Observable
class CalendarThemeManager {
    static let shared = CalendarThemeManager()
    
    var currentTheme: CalendarTheme
    
    let availableThemes: [CalendarTheme] = [
        MonicaTheme(),
        CinderellaTheme(),
        MatchaTheme(),
        GothicTheme()
    ]
    
    private init() {
        let savedThemeId = UserDefaults.standard.string(forKey: "calendar_theme_id") ?? "monica"
        let themes: [CalendarTheme] = [MonicaTheme(), CinderellaTheme(), MatchaTheme(), GothicTheme()]
        if let theme = themes.first(where: { $0.id == savedThemeId }) {
            self.currentTheme = theme
        } else {
            self.currentTheme = MonicaTheme()
        }
    }
    
    func setTheme(_ theme: CalendarTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: "calendar_theme_id")
    }
}
