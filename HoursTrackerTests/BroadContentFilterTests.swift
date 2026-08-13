import XCTest
@testable import HoursTracker

final class BroadContentFilterTests: XCTestCase {

    private let filter = BroadContentFilter.shared

    private func assertAllowed(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        for name in names {
            XCTAssertEqual(
                filter.validate(name), .allowed,
                "expected \"\(name)\" to be allowed", file: file, line: line
            )
        }
    }

    private func assertBlocked(_ names: [String], reason: ContentFilterReason? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        for name in names {
            switch filter.validate(name) {
            case .allowed:
                XCTFail("expected \"\(name)\" to be blocked", file: file, line: line)
            case .blocked(let actual):
                if let reason {
                    XCTAssertEqual(actual, reason, "wrong reason for \"\(name)\"", file: file, line: line)
                }
            }
        }
    }

    // MARK: - Normal names must pass

    func testOrdinaryNamesPass() {
        assertAllowed([
            "Logan", "RoadWorker", "M340i", "ConstructionGuy", "AsphaltKing",
            "NightShift", "Gamer2026", "ClassyDriver", "GrassWorker",
            "Heather High", "Jacob", "Riley", "Dallas", "Holly",
            "The Highs", "Worker", "Big Rig Bob", "Flagger Dan"
        ])
    }

    // MARK: - False positives: real names containing blocked sequences

    func testNamesEmbeddingTokenTermsPass() {
        assertAllowed([
            "Ishita",        // contains "shit"
            "Yoshita",       // contains "shit"
            "Cassidy",       // contains "ass"
            "Hassan",        // contains "ass"
            "Hancock",       // contains "cock"
            "Babcock",       // contains "cock"
            "Dick",          // legitimate given name, deliberately unlisted
            "Dickens",       // ditto
            "Cooney",        // contains "coon"
            "Raccoon Ray",   // contains "coon" inside a word
            "SpiceGirl",     // contains "spic"
            "Sussex Sam",    // contains "sex" inside a word
            "Middlesex",     // ditto
            "TherapistTom",  // contains "rapist" inside a word
            "Cumberbatch",   // contains "cum" inside a word
            "Cummings",      // surname; "cumming" embedded but tokenized as "cummings"
            "Nudelman",      // contains "nude" inside a word
            "Kikelomo"       // contains "kike" inside a word
            // "Scunthorpe" is deliberately NOT here — see the collisions test.
        ])
    }

    /// "Van Dyke" tokenizes to ["van", "dyke"] and "dyke" is a slur token —
    /// this is a deliberate block despite being a real surname: the term's
    /// abuse potential in a display name outweighs the collision.
    func testKnownDeliberateCollisions() {
        assertBlocked(["Van Dyke"], reason: .hateSpeech)
        // Scunthorpe: "cunt" sits substring-tier because no display-style
        // name legitimately contains it — the town name is the accepted cost.
        assertBlocked(["Scunthorpe"], reason: .profanity)
    }

    func testDoubledLettersInOrdinaryNamesPass() {
        assertAllowed(["Aaron", "Emmett", "Harriett", "BichonLover", "Ballooner", "Anna", "Aaliyah"])
    }

    // MARK: - Profanity

    func testPlainProfanityBlocked() {
        assertBlocked(
            ["fuck", "FuckYou", "fucker", "fucking", "motherfucker", "bitch",
             "bitches", "BitchAss", "asshole", "arsehole", "dickhead",
             "cocksucker", "bastard", "douchebag", "jackass", "twat",
             "wanker", "bullshit", "dipshit", "whore", "PussySlayer"],
            reason: .profanity
        )
    }

    func testTokenProfanityBlocked() {
        assertBlocked(["shit", "shitty guy", "dumb ass", "piss off", "big cock", "prick"], reason: .profanity)
    }

    // MARK: - Separators, casing, leetspeak, repeats, Unicode

    func testSeparatorBypassesBlocked() {
        assertBlocked(["F.U.C.K", "f_u_c_k", "f-u-c-k", "f u c k", "FUCK", "FuCk", "f...u...c...k"])
    }

    func testLeetspeakBypassesBlocked() {
        assertBlocked(["SH1T", "sh!t", "b!tch", "b1tch", "f4gg0t", "n1gga", "5hit", "a$$hole", "pu$$y"])
    }

    func testRepeatedLetterBypassesBlocked() {
        assertBlocked(["fuuuck", "fuuuuuck", "shiiit", "biiitch", "niiigga", "fuuck"])
    }

    func testUnicodeLookalikeBypassesBlocked() {
        // Cyrillic а/у, fullwidth letters, accents.
        assertBlocked(["fuсk", "fаggot", "ｆｕｃｋ", "fúck", "šhit"])
    }

    // MARK: - Sexual content

    func testSexualContentBlocked() {
        assertBlocked(
            ["porn", "porno", "PornHub", "xxx", "nudes4u", "naked",
             "vagina", "PenisMan", "dildo", "cum", "cumming", "blowjob",
             "handjob", "rimjob", "orgasm", "masturbate", "hentai",
             "OnlyFans", "SexyBeast"],
            reason: .sexualContent
        )
    }

    // MARK: - Hate speech

    func testSlursBlocked() {
        assertBlocked(
            ["nigger", "nigga", "faggot", "fag", "chink", "spic", "kike",
             "wetback", "tranny", "retard", "retarded", "n i g g a"],
            reason: .hateSpeech
        )
    }

    // MARK: - Threatening content

    func testThreatsBlocked() {
        assertBlocked(
            ["kill yourself", "killyourself", "kys", "suicide", "murder",
             "rapist", "rape", "k.y.s"],
            reason: .threateningContent
        )
    }

    // MARK: - Reserved / impersonation

    func testReservedNamesBlocked() {
        assertBlocked(
            ["admin", "Admin", "ADMIN", "administrator", "moderator",
             "Hour Tracker Admin", "HourTrackerAdmin", "HourTrackerSupport",
             "hour tracker staff", "official", "support", "staff",
             "developer", "system", "mod", "The Support"],
            reason: .reservedName
        )
    }

    func testReservedEmbeddingsInOrdinaryWordsPass() {
        assertAllowed([
            "Badminton",     // contains "admin"
            "Modena",        // contains "mod"
            "Devon",         // contains "dev"
            "Supportive Sam" // "supportive" is not the token "support"
        ])
    }

    // MARK: - Posts skip the reserved tier

    func testPostTextMayMentionReservedWords() {
        XCTAssertEqual(filter.validatePostText("ask the admin for help"), .allowed)
        XCTAssertEqual(filter.validatePostText("official support said so"), .allowed)
        switch filter.validatePostText("this is fucking great") {
        case .blocked(let reason): XCTAssertEqual(reason, .profanity)
        case .allowed: XCTFail("profanity must still block in posts")
        }
    }

    // MARK: - Severity ordering

    func testWorstReasonWins() {
        // Contains both profanity and a slur — hate speech must be reported.
        assertBlocked(["fucking nigga"], reason: .hateSpeech)
    }

    // MARK: - Documented accepted gaps (change these if the design changes)

    func testKnownAcceptedGaps() {
        // Separator-free compounds of token-tier terms pass the client filter
        // by design — matching them as substrings is what blocks Essex and
        // Therapist. The server publication filter shares the tradeoff.
        assertAllowed(["sexgod", "adminteam"])
    }
}
