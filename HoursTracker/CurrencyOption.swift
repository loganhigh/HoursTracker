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
