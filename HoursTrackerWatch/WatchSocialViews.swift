import SwiftUI
import WatchKit

// MARK: - Leaderboard, Board Chat and messages
//
// Quick check-ins, not the full phone experience: your rank and the people
// around you, the latest chat with one-tap replies, and your messages. Each
// screen asks the phone when it opens and every 20 seconds while it stays
// open, and keeps the last answer so it still shows with the phone away.

enum WatchCache {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        WatchCoding.decode(type, from: UserDefaults.standard.data(forKey: key))
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        UserDefaults.standard.set(WatchCoding.encode(value), forKey: key)
    }
}

/// "Couldn't reach your iPhone" footer shown under cached content.
private struct PhoneAwayNote: View {
    var body: some View {
        Label("Showing the last update — bring your iPhone near to refresh.", systemImage: "iphone.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// MARK: Leaderboard

struct WatchBoardView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var board = WatchCache.load(WatchBoard.self, key: "watch_board_v1")
    @State private var phoneAway = false

    var body: some View {
        List {
            if let board {
                Section {
                    VStack(spacing: 2) {
                        Text(board.myRank.map { "#\($0)" } ?? "—")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(WatchStyle.accent)
                        Text(board.myRank == nil ? "Not ranked yet" : "of \(board.totalRanked) · \(WatchStyle.hours(board.myHours))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Top 10") {
                    ForEach(board.top) { row($0) }
                }
                if !board.aroundMe.isEmpty {
                    Section("Around you") {
                        ForEach(board.aroundMe) { row($0) }
                    }
                }
                if phoneAway { PhoneAwayNote().listRowBackground(Color.clear) }
            } else if phoneAway {
                PhoneAwayNote()
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Leaderboard")
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private func row(_ row: WatchBoardRow) -> some View {
        HStack(spacing: 6) {
            Text("\(row.rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(rankColor(row.rank))
                .frame(minWidth: 22, alignment: .leading)
            Text("@\(row.username)")
                .font(.footnote.weight(row.isMe ? .bold : .semibold))
                .foregroundStyle(row.isMe ? WatchStyle.accent : .primary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(row.hoursHidden ? "—" : WatchStyle.hours(row.hours))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.79, blue: 0.28)
        case 2: return Color(red: 0.75, green: 0.79, blue: 0.85)
        case 3: return Color(red: 0.83, green: 0.55, blue: 0.35)
        default: return .secondary
        }
    }

    private func refresh() async {
        guard let answer = await session.request(.requestBoard, as: WatchBoard.self), let value = answer.value else {
            phoneAway = true
            return
        }
        phoneAway = false
        board = value
        WatchCache.save(value, key: "watch_board_v1")
    }
}

// MARK: Board Chat

struct WatchChatView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var chat = WatchCache.load(WatchChat.self, key: "watch_chat_v1")
    @State private var phoneAway = false
    @State private var composePrefix: String?
    @State private var status: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    NavigationLink {
                        WatchInboxView()
                    } label: {
                        HStack {
                            Label("Messages", systemImage: "paperplane.fill")
                            Spacer()
                            if let unread = chat?.unreadMessages, unread > 0 {
                                Text("\(unread)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .background(Capsule().fill(.red))
                            }
                        }
                    }
                }
                if let chat {
                    ForEach(chat.lines) { line in
                        Button {
                            composePrefix = line.isMine ? "" : "@\(line.username) "
                        } label: {
                            chatLine(line, myUsername: chat.myUsername)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(line.mentionsMe ? Color.yellow.opacity(0.18) : Color.gray.opacity(0.18))
                        )
                        .id(line.id)
                    }
                } else if !phoneAway {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
                if phoneAway { PhoneAwayNote().listRowBackground(Color.clear) }
                Button {
                    composePrefix = ""
                } label: {
                    Label("Reply", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.accent)
                .id("compose")
            }
            .onChange(of: chat?.lines.last?.id) { _, _ in proxy.scrollTo("compose", anchor: .bottom) }
            .onAppear { proxy.scrollTo("compose", anchor: .bottom) }
        }
        .navigationTitle("Board Chat")
        .overlay(alignment: .top) { statusBanner }
        .sheet(item: Binding(get: { composePrefix.map(ComposeTarget.init) }, set: { composePrefix = $0?.prefix })) { target in
            WatchComposeView(title: "Board Chat", prefix: target.prefix) { text in
                Task { await send(text) }
            }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let status {
            Text(status)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.85)))
        }
    }

    private func chatLine(_ line: WatchChatLine, myUsername: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.isMine ? "You" : "@\(line.username)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(line.isMine ? WatchStyle.accent : .secondary)
            Text(WatchChatFormat.attributed(line.text, myUsername: myUsername))
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func refresh() async {
        guard let answer = await session.request(.requestChat, as: WatchChat.self), let value = answer.value else {
            phoneAway = true
            return
        }
        phoneAway = false
        chat = value
        WatchCache.save(value, key: "watch_chat_v1")
    }

    private func send(_ text: String) async {
        guard let answer = await session.request(.sendChat(text: text), as: WatchChat.self) else {
            show("Couldn't reach your iPhone")
            return
        }
        if let value = answer.value {
            chat = value
            WatchCache.save(value, key: "watch_chat_v1")
        }
        show(answer.result.isEmpty ? "Sent" : answer.result)
    }

    private func show(_ text: String) {
        withAnimation { status = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { if status == text { status = nil } }
        }
    }
}

private struct ComposeTarget: Identifiable {
    let prefix: String
    var id: String { prefix }
}

enum WatchChatFormat {
    static func attributed(_ text: String, myUsername: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_])@[A-Za-z][A-Za-z0-9_]{2,19}") else { return result }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            let isMe = String(text[range].dropFirst()).lowercased() == myUsername?.lowercased()
            result[lower..<upper].foregroundColor = isMe ? .yellow : WatchStyle.accent
        }
        return result
    }
}

// MARK: Messages

struct WatchInboxView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var threads = WatchCache.load([WatchThreadSummary].self, key: "watch_inbox_v1")
    @State private var phoneAway = false

    var body: some View {
        List {
            if let threads, !threads.isEmpty {
                ForEach(threads) { thread in
                    NavigationLink {
                        WatchThreadView(otherUid: thread.otherUid, otherUsername: thread.otherUsername)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("@\(thread.otherUsername)")
                                    .font(.footnote.weight(.bold))
                                    .lineLimit(1)
                                Spacer()
                                if thread.unread > 0 {
                                    Circle().fill(WatchStyle.accent).frame(width: 8, height: 8)
                                }
                            }
                            Text(thread.lastText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else if threads != nil {
                Text("No messages yet. Start one from someone's profile on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !phoneAway {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            if phoneAway { PhoneAwayNote().listRowBackground(Color.clear) }
        }
        .navigationTitle("Messages")
        .task {
            guard let answer = await session.request(.requestInbox, as: [WatchThreadSummary].self),
                  let value = answer.value else {
                phoneAway = true
                return
            }
            threads = value
            WatchCache.save(value, key: "watch_inbox_v1")
        }
    }
}

struct WatchThreadView: View {
    @EnvironmentObject private var session: WatchSession
    let otherUid: String
    let otherUsername: String

    @State private var lines: [WatchChatLine] = []
    @State private var loaded = false
    @State private var phoneAway = false
    @State private var composing = false
    @State private var status: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(lines) { line in
                    HStack {
                        if line.isMine { Spacer(minLength: 16) }
                        Text(line.text)
                            .font(.footnote)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(line.isMine ? WatchStyle.accent : Color.gray.opacity(0.3)))
                        if !line.isMine { Spacer(minLength: 16) }
                    }
                    .listRowBackground(Color.clear)
                    .id(line.id)
                }
                if !loaded && !phoneAway {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
                if phoneAway { PhoneAwayNote().listRowBackground(Color.clear) }
                Button {
                    composing = true
                } label: {
                    Label("Reply", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.accent)
                .id("compose")
            }
            .onChange(of: lines.last?.id) { _, _ in proxy.scrollTo("compose", anchor: .bottom) }
        }
        .navigationTitle("@\(otherUsername)")
        .overlay(alignment: .top) {
            if let status {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.85)))
            }
        }
        .sheet(isPresented: $composing) {
            WatchComposeView(title: "@\(otherUsername)", prefix: "") { text in
                Task { await send(text) }
            }
        }
        .task {
            while !Task.isCancelled {
                await load(.requestThread(otherUid: otherUid))
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private func load(_ command: WatchCommand) async {
        guard let answer = await session.request(command, as: WatchThreadMessages.self) else {
            phoneAway = true
            return
        }
        phoneAway = false
        loaded = true
        if let value = answer.value { lines = value.lines }
        if case .sendDirect = command {
            status = answer.result.isEmpty ? "Sent" : answer.result
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            status = nil
        }
    }

    private func send(_ text: String) async {
        await load(.sendDirect(otherUid: otherUid, otherUsername: otherUsername, text: text))
    }
}

// MARK: Compose

/// Dictate, scribble or type — or tap a quick reply to send it at once.
struct WatchComposeView: View {
    let title: String
    let prefix: String
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        List {
            Section {
                TextField(prefix.isEmpty ? "Message" : prefix, text: $text)
                Button {
                    send(text)
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.accent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Quick replies") {
                ForEach(WatchQuickReplies.all, id: \.self) { reply in
                    Button(reply) { send(reply) }
                }
            }
        }
        .navigationTitle(title)
    }

    private func send(_ body: String) {
        let message = (prefix + body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        WKHaptics.success()
        onSend(message)
        dismiss()
    }
}

enum WKHaptics {
    static func success() { WKInterfaceDevice.current().play(.success) }
}
