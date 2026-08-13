import Foundation

// MARK: - Broad content filter
//
// Moderation for user-authored text that other users see: display names first
// (all categories, including impersonation), board posts and comments (same
// categories minus reserved names — a post may legitimately mention "admin").
//
// Design notes, in order of importance:
//
// FALSE POSITIVES. Naive `contains` filters block real people — the classic
// "Scunthorpe problem". Every term is therefore assigned a matching tier by
// how distinctive it is:
//   - substring: never occurs inside legitimate text ("faggot", "pornhub").
//   - token: whole-word only, because it lives inside real names or words —
//     "ass" (Hassan, Cassidy), "cock" (Hancock, Babcock), "spic" (Spice),
//     "rapist" (therapist), "coon" (raccoon, Cooney), "kike" (Kikelomo),
//     "cum" (Cumberbatch), "nude" (Nudelman), "shit" (Ishita).
//   - exact: the whole normalized name must equal the term — for strings too
//     short or ambiguous to match any other way ("kys", "xxx", "sex").
//
// BYPASS RESISTANCE. Matching runs on a normalized representation, never the
// raw name: Unicode compatibility-folded (fullwidth, circled), diacritics
// stripped, common Cyrillic/Greek lookalikes mapped to Latin, leetspeak
// digits/symbols folded, then split into letter runs. Separator games
// ("f.u.c.k", "f_u_c_k") die at the collapsed (letters-only) form; repeated-
// letter padding ("fuuuck") is caught by a squeezed pass that collapses
// letter runs on both the text and the terms, gated so it only runs when the
// text actually contains repeats — un-squeezed text is never held against
// squeezed terms (which is what would block "BichonLover" on "bich").
//
// The original string is never modified; normalization exists only for
// moderation. Deliberate accepted gaps, chosen over false positives:
// separator-free compounds of token-tier terms ("sexgod") and reserved words
// embedded without separators ("adminteam") pass the client filter — the
// server-side publication sanitizer is the final authority.
//
// All state is immutable after init, so the shared instance is thread-safe.

enum ContentFilterReason {
    case profanity
    case sexualContent
    case hateSpeech
    case threateningContent
    case reservedName
}

enum ContentFilterResult: Equatable {
    case allowed
    case blocked(reason: ContentFilterReason)

    var isAllowed: Bool { self == .allowed }
}

extension ContentFilterReason: Equatable {}

final class BroadContentFilter {

    static let shared = BroadContentFilter()

    /// The one user-facing string. Deliberately never names the term that
    /// matched — echoing it back is a bypass tutorial.
    static let blockedNameMessage = "This name isn't allowed. Please choose another."

    // MARK: Term sets

    private struct Category {
        let reason: ContentFilterReason
        /// Distinctive terms, matched anywhere in the collapsed text.
        let substrings: [String]
        /// Ambiguous terms, matched as whole tokens only.
        let tokens: Set<String>
        /// Short terms the whole name must equal.
        let exact: Set<String>
        /// Precomputed run-collapsed forms for the squeezed passes.
        let squeezedSubstrings: [String]
        let squeezedTokens: Set<String>

        init(reason: ContentFilterReason, substrings: [String], tokens: Set<String>, exact: Set<String>) {
            self.reason = reason
            self.substrings = substrings
            self.tokens = tokens
            self.exact = exact
            self.squeezedSubstrings = substrings.map { BroadContentFilter.squeezeRuns($0) }
            self.squeezedTokens = Set(tokens.map { BroadContentFilter.squeezeRuns($0) })
        }
    }

    /// Ordered by severity — the reason reported is the worst one matched.
    private let contentCategories: [Category]
    private let reservedCategory: Category

    private init() {
        contentCategories = [
            Category(
                reason: .hateSpeech,
                substrings: [
                    "nigger", "nigga", "faggot", "wetback", "retard",
                    "raghead", "porchmonkey", "towelhead", "goatfucker"
                ],
                tokens: [
                    // Each of these lives inside real names — see header.
                    "fag", "fags", "dyke", "coon", "coons", "spic", "spics",
                    "kike", "kikes", "chink", "chinks", "gook", "gooks",
                    "beaner", "beaners", "tranny", "trannies",
                    "nazi", "nazis", "hitler"
                ],
                exact: []
            ),
            Category(
                reason: .threateningContent,
                substrings: ["killyourself", "killurself", "suicide", "murder"],
                tokens: ["rape", "raped", "rapes", "rapist", "rapists", "molester", "pedophile", "pedo"],
                exact: ["kys"]
            ),
            Category(
                reason: .sexualContent,
                substrings: [
                    "porn", "sexy", "blowjob", "handjob", "rimjob", "dildo",
                    "hentai", "onlyfans", "masturbat", "orgasm", "fellatio", "penis",
                    "deepthroat", "gangbang", "vagina", "bukkake", "milf"
                ],
                tokens: [
                    "sex", "nude", "nudes", "naked", "semen", "cum",
                    "cums", "cumming", "jizz", "anal", "tits", "boobs",
                    "boobies", "titties", "hoe", "hoes", "thot", "thots",
                    // "Cumming" is a real surname (Alan Cumming); blocking it
                    // is the deliberate cost of blocking the term.
                    "clit", "smut"
                ],
                exact: ["xxx"]
            ),
            Category(
                reason: .profanity,
                substrings: [
                    "fuck", "fuk", "cunt", "asshole", "arsehole", "bitch",
                    "pussy", "whore", "wanker", "bastard", "motherfuck",
                    "dickhead", "cocksuck", "bollock", "jackass", "dumbass",
                    "bullshit", "dipshit", "horseshit", "douche", "shithead",
                    "numbnut", "pissoff", "fucc", "phuck"
                ],
                tokens: [
                    "shit", "shits", "shitty", "ass", "arse", "piss", "pissed",
                    "cock", "cocks", "twat", "twats", "wank", "prick",
                    "pricks", "slut", "sluts", "skank"
                    // "dick" is deliberately absent everywhere: it is a
                    // legitimate given name. "damn"/"crap" are deliberately
                    // unlisted — mild enough that blocking them punishes more
                    // ordinary names than it protects anyone.
                ],
                exact: []
            )
        ]

        reservedCategory = Category(
            reason: .reservedName,
            // Any embedding of the app's name reads as an official account.
            substrings: ["hourtracker", "hourstracker"],
            tokens: [
                "admin", "admins", "administrator", "administrators",
                "moderator", "moderators", "modteam", "support", "official",
                "staff", "developer", "developers", "system", "sysadmin",
                "helpdesk", "customerservice"
            ],
            exact: ["mod", "mods", "dev", "devs"]
        )
    }

    // MARK: Public API

    /// Full check for display names: content categories plus impersonation.
    func validate(_ name: String) -> ContentFilterResult {
        let normalized = Normalized(name)
        for category in contentCategories {
            if matches(category, normalized) {
                return .blocked(reason: category.reason)
            }
        }
        if matches(reservedCategory, normalized) {
            return .blocked(reason: .reservedName)
        }
        return .allowed
    }

    /// Check for posts and comments: same content categories, but reserved
    /// names are fine in running text.
    func validatePostText(_ text: String) -> ContentFilterResult {
        let normalized = Normalized(text)
        for category in contentCategories {
            if matches(category, normalized) {
                return .blocked(reason: category.reason)
            }
        }
        return .allowed
    }

    // MARK: Matching

    private func matches(_ category: Category, _ n: Normalized) -> Bool {
        for variant in n.variants where matches(category, variant) {
            return true
        }
        return false
    }

    private func matches(_ category: Category, _ n: Normalized.Variant) -> Bool {
        for term in category.substrings where n.collapsed.contains(term) {
            return true
        }
        // Squeezed pass — only when the text actually had letter runs, so
        // ordinary text is never compared against squeezed (shortened) terms.
        if n.hadRepeats {
            for squeezed in category.squeezedSubstrings where n.squeezedCollapsed.contains(squeezed) {
                return true
            }
        }
        for token in n.tokens where category.tokens.contains(token) {
            return true
        }
        // "shiiit": a token containing a ≥3 letter run is an evasion signal —
        // compare its squeezed form against the terms (and their squeezed
        // forms, for double-letter terms). The ≥3 gate keeps ordinary names
        // with doubled letters ("Aaron") out of this pass entirely.
        for squeezedToken in n.squeezedLongRunTokens {
            if category.tokens.contains(squeezedToken) { return true }
            if category.squeezedTokens.contains(squeezedToken) { return true }
        }
        if category.exact.contains(n.collapsed) { return true }
        return false
    }

    // MARK: Normalization

    /// Matching runs against two variants: leet-folded ("sh1t" → "shit") and
    /// unfolded. Both are needed because leet folding destroys legitimate
    /// digit boundaries — "nudes4u" folds to "nudesau", hiding the token
    /// "nudes" that the unfolded form exposes.
    private struct Normalized {
        struct Variant {
            let tokens: [String]
            let collapsed: String
            let squeezedCollapsed: String
            let hadRepeats: Bool
            /// Squeezed forms of only those tokens that contained a run of 3+
            /// of the same letter — the ≥3 gate keeps "Aaron" out of it.
            let squeezedLongRunTokens: [String]

            init(_ folded: String) {
                let tokens = folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
                self.tokens = tokens
                let collapsed = String(folded.filter { $0.isLetter })
                self.collapsed = collapsed
                let squeezed = BroadContentFilter.squeezeRuns(collapsed)
                self.squeezedCollapsed = squeezed
                self.hadRepeats = squeezed != collapsed
                self.squeezedLongRunTokens = tokens
                    .filter { BroadContentFilter.hasRun(ofAtLeast: 3, in: $0) }
                    .map { BroadContentFilter.squeezeRuns($0) }
            }
        }

        let variants: [Variant]

        init(_ raw: String) {
            let base = BroadContentFilter.fold(raw)
            let leeted = String(base.map { BroadContentFilter.leet[$0] ?? $0 })
            var variants = [Variant(base)]
            if leeted != base {
                variants.append(Variant(leeted))
            }
            self.variants = variants
        }
    }

    /// Unicode → lowercase Latin skeleton: NFKC compatibility mapping folds
    /// fullwidth/stylized forms, diacritic folding strips accents, and the
    /// confusables table maps common Cyrillic/Greek lookalikes. Leet digits
    /// are folded separately, per variant.
    private static func fold(_ raw: String) -> String {
        let compat = raw.precomposedStringWithCompatibilityMapping
        let folded = compat.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return String(folded.map { confusables[$0] ?? $0 })
    }

    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
        "8": "b", "@": "a", "$": "s", "!": "i", "+": "t", "€": "e", "£": "l"
    ]

    /// Common Cyrillic and Greek characters that render like Latin ones.
    private static let confusables: [Character: Character] = [
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y",
        "х": "x", "і": "i", "ѕ": "s", "ј": "j", "ԁ": "d", "к": "k",
        "м": "m", "т": "t", "в": "b", "н": "h",
        "α": "a", "β": "b", "ε": "e", "ι": "i", "κ": "k", "ν": "v",
        "ο": "o", "ρ": "p", "τ": "t", "υ": "u", "χ": "x", "ѡ": "w"
    ]

    /// "fuuuck" → "fuck": collapses every run of a repeated letter to one.
    private static func squeezeRuns(_ text: String) -> String {
        var out = ""
        var last: Character?
        for ch in text where ch != last {
            out.append(ch)
            last = ch
        }
        return out
    }

    private static func hasRun(ofAtLeast n: Int, in text: String) -> Bool {
        var count = 0
        var last: Character?
        for ch in text {
            count = (ch == last) ? count + 1 : 1
            if count >= n { return true }
            last = ch
        }
        return false
    }
}

