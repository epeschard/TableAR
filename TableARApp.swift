import SwiftUI

struct ContentView: View {
    @StateObject private var manager = ARManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(manager: manager)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                modePicker

                if !manager.tableDetected {
                    scanPrompt
                } else {
                    switch manager.mode {
                    case .cards:
                        cardsHUD
                    case .dominoes:
                        dominoesHUD
                    }
                }
            }
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.25), value: manager.tableDetected)
            .animation(.easeInOut(duration: 0.2), value: manager.placedCount)
            .animation(.easeInOut(duration: 0.2), value: manager.mode)
            .animation(.easeInOut(duration: 0.2), value: manager.game.phase)
        }
        .onAppear {
            manager.statusLine = "Scan a table, then pick Cards or Dominoes."
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            ForEach(TableMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    private var modeBinding: Binding<TableMode> {
        Binding(
            get: { manager.mode },
            set: { manager.setMode($0) }
        )
    }

    private var scanPrompt: some View {
        VStack(spacing: 10) {
            Text("Scan for Table Surface")
                .font(.title2.bold())
            Text("Point your camera at a flat horizontal surface\nsuch as a table, desk, or countertop.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    private var cardsHUD: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Table Detected")
                        .font(.headline)
                }
                Text("Cards mode — tap to place a labeled plane • drag to slide it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)

            if manager.placedCount > 0 {
                Button(role: .destructive) {
                    manager.clearPlacedPlanes()
                } label: {
                    Label("Clear Cards (\(manager.placedCount))", systemImage: "trash.fill")
                        .font(.callout.bold())
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.85))
                .controlSize(.large)
            }
        }
    }

    private var dominoesHUD: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Dominoes on the shared table")
                        .font(.headline)
                    Spacer()
                }

                Picker("Rules", selection: rulesBinding) {
                    ForEach(DominoRules.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(manager.game.phase == .playing)

                Text(manager.statusLine.isEmpty ? manager.game.status : manager.statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if manager.game.phase == .playing || manager.game.phase == .finished {
                    HStack {
                        Label("You \(manager.game.humanHand.count)", systemImage: "person.fill")
                        Spacer()
                        Label("Boneyard \(manager.game.boneyard.count)", systemImage: "square.stack.3d.up")
                        Spacer()
                        Label("Opp \(manager.game.aiHand.count)", systemImage: "person")
                    }
                    .font(.caption.weight(.semibold))
                }

                HStack(spacing: 10) {
                    Button {
                        manager.dealDominoes()
                    } label: {
                        Label(
                            manager.game.phase == .playing ? "Redeal" : "Deal",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    if manager.game.phase == .playing, manager.game.currentPlayer == .human,
                       manager.game.mustDrawOrPass(player: .human) {
                        if manager.rules == .draw && !manager.game.boneyard.isEmpty {
                            Button("Draw") { manager.humanDraw() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Pass") { manager.humanPass() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }

    private var rulesBinding: Binding<DominoRules> {
        Binding(
            get: { manager.rules },
            set: { newValue in
                manager.rules = newValue
                if manager.game.phase != .playing {
                    manager.game.rules = newValue
                    manager.game.resetBoardKeepingRules()
                    manager.statusLine = manager.game.status
                }
            }
        )
    }
}

@main
struct TableARApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
