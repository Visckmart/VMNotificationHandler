//
//  Extensions.swift
//  TemplatesAndSnippetsPlayground
//
//  Created by Victor Martins on 01/09/23.
//

import Foundation
import UserNotifications

extension UNCalendarNotificationTrigger {
    convenience init(fromSpecificDate date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond],
                                                         from: date)
        self.init(dateMatching: components, repeats: false)
    }
}

extension UNAuthorizationStatus: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unable to provide a description"
        }
    }
}
