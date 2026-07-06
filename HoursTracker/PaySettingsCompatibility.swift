import Foundation

// This file ONLY adds backwards-compatible aliases to PaySettings.
// It fixes errors like: "PaySettings has no member 'hourlyWage'".

extension PaySettings {

    // Old name used in older UI code
    var hourlyWage: Double {
        get { hourlyRate }
        set { hourlyRate = newValue }
    }

    // Old name used in older UI code
    var userEmail: String {
        get { email }
        set { email = newValue }
    }
}
