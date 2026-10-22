//
//  SettingsShortcutRow.swift
//  DynamicNotch
//

import SwiftUI
internal import AppKit

struct SettingsShortcutRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let keyCode: Int
    let modifiers: Int
    let keyDisplay: String
    let onSave: (Int, Int, String) -> Void
    var onReset: (() -> Void)? = nil

    @State private var isRecording = false
    @State private var localMonitor: Any? = nil

    private var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyDisplay.uppercased()
        return result
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                if let onReset {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(Text("settings.shortcut.resetToDefault"))
                }

                Button(action: toggleRecording) {
                    Group {
                        if isRecording {
                            Text("settings.shortcut.pressShortcut")
                        } else if displayString.isEmpty {
                            Text("settings.shortcut.none")
                        } else {
                            Text(verbatim: displayString)
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Allow Escape to cancel recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty || (event.keyCode >= 96 && event.keyCode <= 122) else {
                return nil
            }

            let keyChar = event.charactersIgnoringModifiers?.uppercased() ?? specialKeyName(for: event.keyCode)
            guard !keyChar.isEmpty else { return nil }

            onSave(Int(event.keyCode), Int(flags.rawValue), keyChar)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func specialKeyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return ""
        }
    }
}
