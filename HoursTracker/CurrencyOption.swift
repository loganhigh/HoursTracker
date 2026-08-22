import Foundation

/// Curated list of currencies the user can pick from. Each entry is the ISO-4217 code.
/// The display name is resolved from `Locale.current.localizedString(forCurrencyCode:)`,
/// and the symbol is resolved through `NumberFormatter` so it matches what's shown elsewhere.
struct CurrencyOption: Identifiable, Hashable {
    let code: String
    var id: String { code }

    /// Localized currency name (e.g. "US Dollar", "Canadian Dollar"). Falls back to the code.
    var displayName: String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// Currency symbol (e.g. "$", "£", "€", "¥"). Falls back to the code if no symbol available.
    var symbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.currencySymbol ?? code
    }
}

enum CurrencyCatalog {
    /// Common currencies surfaced in pickers. Ordered to put the most popular ones first.
    static let common: [CurrencyOption] = [
        "USD", "CAD", "EUR", "GBP", "AUD", "NZD",
        "MXN", "BRL", "ARS", "CLP", "COP", "PEN",
        "JPY", "CNY", "HKD", "KRW", "SGD", "TWD", "INR", "THB", "MYR", "IDR", "PHP", "VND",
        "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "ISK",
        "RUB", "UAH", "TRY", "AED", "SAR", "QAR", "ILS", "EGP",
        "ZAR", "NGN", "KES", "GHS"
    ].map { CurrencyOption(code: $0) }

    /// Returns the option matching the given code, or USD as a safe fallback.
    static func option(for code: String) -> CurrencyOption {
        if let match = common.first(where: { $0.code == code }) {
            return match
        }
        // The user may have a code that isn't in the curated list — surface it anyway.
        return CurrencyOption(code: code)
    }
}

// MARK: - Cheque amount parsing

/// Parses a cheque total typed off a paystub. Swift's `Double("…")` only
/// understands `.` as the decimal point, so the old `remove(",")` pre-pass
/// turned a French-Canadian "1540,25" into 154025 — a 100× error that then
/// trained the pay projection on every device. Separators are resolved from
/// the text itself first and the locale only as a tie-breaker.
enum ChequeAmountParser {
    static func parse(_ raw: String, locale: Locale = .current) -> Double? {
        // A cheque can't pay a negative amount; don't let the digit filter
        // below quietly turn "-50" into 50.
        guard !raw.contains("-") else { return nil }
        let allowed = Set("0123456789.,")
        let kept = String(raw.filter { allowed.contains($0) })
        guard !kept.isEmpty else { return nil }

        let commas = kept.filter { $0 == "," }.count
        let dots = kept.filter { $0 == "." }.count
        let localeDecimal = Character(locale.decimalSeparator ?? ".")

        let normalized: String
        switch (commas, dots) {
        case (0, 0):
            normalized = kept
        case (_, 0), (0, _):
            // One separator kind. Repeated → grouping ("1,234,567").
            // Single → decimal unless it reads as a thousands group
            // ("1,540" in an en locale), which the locale disambiguates.
            let sep: Character = commas > 0 ? "," : "."
            let count = commas > 0 ? commas : dots
            if count > 1 {
                normalized = kept.replacingOccurrences(of: String(sep), with: "")
            } else {
                let parts = kept.split(separator: sep, omittingEmptySubsequences: false)
                let trailing = parts.count == 2 ? parts[1].count : 0
                let isGrouping = trailing == 3 && sep != localeDecimal
                normalized = isGrouping
                    ? kept.replacingOccurrences(of: String(sep), with: "")
                    : kept.replacingOccurrences(of: String(sep), with: ".")
            }
        default:
            // Both present: the last one is the decimal point, the other groups.
            let lastComma = kept.lastIndex(of: ",")!
            let lastDot = kept.lastIndex(of: ".")!
            let decimalIsComma = lastComma > lastDot
            normalized = kept
                .replacingOccurrences(of: decimalIsComma ? "." : ",", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }

        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}
