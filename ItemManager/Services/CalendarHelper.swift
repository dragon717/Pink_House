//
//  CalendarHelper.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import Foundation

struct CalendarDate: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
}

class CalendarHelper {
    static let shared = CalendarHelper()
    private let calendar = Calendar.current
    
    func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter.string(from: date)
    }

    func completeDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func abbreviatedDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func monthName(_ month: Int, year: Int? = nil) -> String {
        var components = DateComponents()
        components.year = year ?? calendar.component(.year, from: Date())
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components) else {
            return "\(month)"
        }
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
    
    func daysInMonth(_ date: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: date)!
        return range.count
    }
    
    func dayOfMonth(_ date: Date) -> Int {
        let components = calendar.dateComponents([.day], from: date)
        return components.day!
    }
    
    func firstOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)!
    }
    
    func weekDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.weekday], from: date)
        return components.weekday! - 1 // 0 = Sunday, 1 = Monday...
    }
    
    func addMonth(_ date: Date, n: Int) -> Date {
        return calendar.date(byAdding: .month, value: n, to: date)!
    }
    
    func generateDates(for date: Date) -> [CalendarDate] {
        var days = [CalendarDate]()
        
        let firstDayOfMonth = firstOfMonth(date)
        let daysInMonth = daysInMonth(date)
        let startingSpaces = weekDay(firstDayOfMonth)
        
        // Previous month padding
        if let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfMonth) {
            let daysInPrevMonth = self.daysInMonth(prevMonth)
            for i in 0..<startingSpaces {
                let day = daysInPrevMonth - startingSpaces + i + 1
                if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth(prevMonth)) {
                    days.append(CalendarDate(date: date, isCurrentMonth: false, isToday: calendar.isDateInToday(date)))
                }
            }
        }
        
        // Current month
        for i in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: i, to: firstDayOfMonth) {
                days.append(CalendarDate(date: date, isCurrentMonth: true, isToday: calendar.isDateInToday(date)))
            }
        }
        
        // Next month padding (to fill 6 rows = 42 days)
        let remainingSpaces = 42 - days.count
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstDayOfMonth) {
            for i in 0..<remainingSpaces {
                if let date = calendar.date(byAdding: .day, value: i, to: nextMonth) {
                    days.append(CalendarDate(date: date, isCurrentMonth: false, isToday: calendar.isDateInToday(date)))
                }
            }
        }
        
        return days
    }
}
