//
//  Date+smartString.swift
//  EagleViewer
//
//  Created on 2025/09/28
//

import Foundation

extension Date {
    /// Example outputs:
    /// - Today: "3:46"
    /// - Yesterday: "Yesterday"
    /// - Within ±2 days: "2 days ago" / "in 2 days"
    /// - Otherwise: "2025/09/16"
    func smartString(
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        // Today → show only the time
        if calendar.isDate(self, inSameDayAs: now) {
            return self.formatted(.dateTime.hour().minute().locale(locale))
        }

        // Yesterday / Tomorrow → use localized relative date formatting
        let df = DateFormatter()
        df.locale = locale
        df.calendar = calendar
        df.timeStyle = .none
        df.dateStyle = .medium
        df.doesRelativeDateFormatting = true
        if calendar.isDateInYesterday(self) || calendar.isDateInTomorrow(self) {
            return df.string(from: self)
        }

        // Within ±2 days → use relative description (e.g. "2 days ago" / "in 2 days")
        let startSelf = calendar.startOfDay(for: self)
        let startNow = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: startSelf, to: startNow).day,
           abs(days) <= 2
        {
            let rel = RelativeDateTimeFormatter()
            rel.locale = locale
            rel.unitsStyle = .full // e.g. "2 days ago"
            rel.dateTimeStyle = .named
            // Note: in Japanese, this usually becomes "2日前" instead of "一昨日"
            return rel.localizedString(for: self, relativeTo: now)
        }

        // Otherwise → show absolute date (e.g. "2025/09/16")
        return self.formatted(
            .dateTime.year().month().day().locale(locale)
        )
    }
}
