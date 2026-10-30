//
//  ClaudeActivityViewModel.swift
//  DynamicNotch
//
//  Liest den Fortschritt laufender Claude-Code-Sitzungen. Die Dateien schreibt
//  der Hook ClaudeHook/dynamicnotch-claude.py.
//

internal import AppKit
import Combine
import Foundation

struct ClaudeTask: Equatable, Decodable, Sendable {
    let title: String
    let status: String

    var isCompleted: Bool { status == "completed" }
    var isActive: Bool { status == "in_progress" }
}

struct ClaudeAgent: Equatable, Decodable, Sendable {
    let type: String
    let description: String
}

struct ClaudeSession: Identifiable, Equatable, Decodable, Sendable {
    let sessionId: String
    let project: String?
    let status: String
    let prompt: String?
    let currentTool: String?
    let currentDetail: String?
    let tasks: [ClaudeTask]
    let subagents: Int
    /// Ältere Dateien des Hooks kennen nur die Anzahl
    let agents: [ClaudeAgent]?
    let turnStartedAt: Double?
    let updatedAt: Double

    var id: String { sessionId }
    var isWorking: Bool { status == "working" }
    var isWaiting: Bool { status == "waiting" }
    var isDone: Bool { status == "done" }

    var completedCount: Int { tasks.filter(\.isCompleted).count }

    var crew: [ClaudeAgent] {
        agents ?? Array(repeating: ClaudeAgent(type: "general-purpose", description: ""), count: subagents)
    }
    var hasPlan: Bool { !tasks.isEmpty }

    var currentTask: ClaudeTask? {
        tasks.first(where: \.isActive) ?? tasks.first { !$0.isCompleted }
    }

    var currentStepNumber: Int {
        guard let current = currentTask, let index = tasks.firstIndex(of: current) else { return tasks.count }
        return index + 1
    }

    var startedAt: Date? { turnStartedAt.map(Date.init(timeIntervalSince1970:)) }

    var headline: String {
        if let title = currentTask?.title { return title }
        // Systemmeldungen wie <task-notification> sind keine lesbare Überschrift,
        // eingefügter Text steckt in <pasted_content …>-Klammern
        if let prompt, !prompt.hasPrefix("<") {
            let readable = prompt
                .replacingOccurrences(of: "<[^>]*>?", with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !readable.isEmpty { return readable }
        }
        return "Claude arbeitet"
    }
}

enum ClaudeActivityEvent: Equatable {
    case started
    case finished(project: String)
    case stopped
}

@MainActor
final class ClaudeActivityViewModel: ObservableObject {
    static let stateDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DynamicNotch/Claude", isDirectory: true)

    /// Sitzungen, die gerade arbeiten oder auf eine Antwort warten.
    @Published private(set) var activeSessions: [ClaudeSession] = []
    /// Kostüm je Sitzung, passend zum aktuellen Werkzeug
    @Published private(set) var costumes: [String: CrabCostume] = [:]
    @Published var event: ClaudeActivityEvent?
    /// Für die Prüfhilfe (NotchSnapshotDebugger), gesetzt vom Handler
    weak var nowPlayingViewModel: NowPlayingViewModel?
    weak var notchViewModel: NotchViewModel?

    /// Nach so vielen Sekunden ohne Update gilt eine Sitzung als verwaist.
    private let staleInterval: TimeInterval = 20 * 60
    private var timer: Timer?
    private var announcedDone = Set<String>()
    private var costumeChangedAt: [String: Date] = [:]
    /// So lange bleibt ein Kostüm mindestens, sonst flackert die Krabbe bei Lesen/Bearbeiten im Sekundentakt
    private let costumeHold: TimeInterval = 2.5

    /// Mehr Sitzungen passen nicht untereinander in die aufgeklappte Notch
    static let maxVisibleSessions = 3

    var primarySession: ClaudeSession? { activeSessions.first }
    var visibleSessions: [ClaudeSession] { Array(activeSessions.prefix(Self.maxVisibleSessions)) }
    var hiddenSessionCount: Int { max(0, activeSessions.count - Self.maxVisibleSessions) }

    func costume(for session: ClaudeSession) -> CrabCostume {
        costumes[session.id] ?? .forActivity(tool: session.currentTool, isWaiting: session.isWaiting)
    }

    func startMonitoring() {
        guard timer == nil else { return }
        try? FileManager.default.createDirectory(at: Self.stateDirectory, withIntermediateDirectories: true)
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                if let self {
                    NotchSnapshotDebugger.captureIfRequested(claude: self)
                }
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func openClaude() {
        // activate() ignoriert macOS bei Apps im Hintergrund, openApplication holt sie zuverlässig nach vorne
        let identifiers = ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        let running = identifiers.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
        let url = running?.bundleURL
            ?? identifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func reload() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.stateDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ClaudeSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ClaudeSession.self, from: data)
            }
            .filter { now - $0.updatedAt < staleInterval }

        let active = sessions
            .filter { !$0.isDone }
            .sorted { lhs, rhs in
                // Wartende zuerst: dort braucht Claude dich
                if lhs.isWaiting != rhs.isWaiting { return lhs.isWaiting }
                return lhs.updatedAt > rhs.updatedAt
            }

        let wasActive = !activeSessions.isEmpty
        let finished = sessions.filter { $0.isDone && !announcedDone.contains($0.id) && now - $0.updatedAt < 10 }
        let previouslyActiveIDs = Set(activeSessions.map(\.id))

        if active != activeSessions {
            activeSessions = active
        }
        updateCostumes(for: active)

        // Fertig-Meldung nur für Sitzungen, die wir gerade noch arbeiten sahen
        for session in finished where previouslyActiveIDs.contains(session.id) {
            announcedDone.insert(session.id)
            event = .finished(project: session.project ?? "Claude")
        }
        for session in sessions where !session.isDone {
            announcedDone.remove(session.id)
        }

        if active.isEmpty && wasActive {
            event = .stopped
        } else if !active.isEmpty && !wasActive {
            event = .started
        }
    }

    private func updateCostumes(for sessions: [ClaudeSession]) {
        let now = Date()
        let ids = Set(sessions.map(\.id))
        var next = costumes.filter { ids.contains($0.key) }
        costumeChangedAt = costumeChangedAt.filter { ids.contains($0.key) }

        for session in sessions {
            let wanted = CrabCostume.forActivity(tool: session.currentTool, isWaiting: session.isWaiting)
            guard next[session.id] != wanted else { continue }
            let shownFor = costumeChangedAt[session.id].map { now.timeIntervalSince($0) } ?? .infinity
            // Warten auf dich zeigt sie sofort, ebenso das Ende davon
            if shownFor >= costumeHold || wanted == .waving || next[session.id] == .waving {
                next[session.id] = wanted
                costumeChangedAt[session.id] = now
            }
        }

        if next != costumes {
            costumes = next
        }
    }
}
