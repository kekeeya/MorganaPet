//
//  PetSettingsView.swift
//  Mona
//

import AppKit
import ServiceManagement
import SwiftUI

/// The settings window.
///
/// Split where the two halves stop having anything to do with each other: the
/// menu-bar icon is a thing you glance at while working, and Mona himself is a
/// thing that lives on your desktop and talks to you. Nothing on one tab changes
/// anything on the other.
struct PetSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            PetBehaviourSettingsView()
                .tabItem { Label("桌宠", systemImage: "pawprint") }
            CalendarSettingsView()
                .tabItem { Label("日历", systemImage: "calendar") }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The desktop calendar sticker.
///
/// Size and position are the only things worth adjusting — the design itself is
/// fixed artwork. The coordinate field is an escape hatch rather than the normal
/// path: left empty, the weather follows the system location, and failing that
/// the IP address.
private struct CalendarSettingsView: View {
    @AppStorage(PetPreferences.calendarVisibleKey) private var visible = false
    @AppStorage(PetPreferences.calendarWidthKey) private var width = 320.0
    @AppStorage(PetPreferences.calendarAlwaysOnTopKey) private var alwaysOnTop = true
    @AppStorage(PetPreferences.calendarCityKey) private var city = CalendarCity.defaultID

    var body: some View {
        Form {
            Section("显示") {
                Toggle("在桌面显示日历", isOn: $visible)
                Toggle("永远置顶", isOn: $alwaysOnTop)
            }

            Section {
                Slider(value: $width, in: 200...760, step: 20) {
                    Text("日历大小")
                } minimumValueLabel: {
                    Text("小").font(.caption)
                } maximumValueLabel: {
                    Text("大").font(.caption)
                }
            }

            Section("天气") {
                VStack(alignment: .leading, spacing: 6) {
                    CalendarCityPicker(raw: $city)
                    Text("根据选择城市从 Open-Meteo 获取，每半小时刷新一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // GeoNames ships under CC BY 4.0, which asks for this.
                    Text("城市数据 © GeoNames，CC BY 4.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .onChange(of: width) { _, _ in notifyChanged() }
        .onChange(of: visible) { _, _ in notifyChanged() }
        .onChange(of: alwaysOnTop) { _, _ in notifyChanged() }
        .onChange(of: city) { _, _ in notifyChanged() }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: PetPreferences.calendarSettingsChanged,
                                        object: nil)
    }
}

/// The menu-bar icon, and whether Mona comes back by itself.
///
/// The run direction is pure taste, so it says what it does and leaves it at
/// that. The login item is the one switch in the app that can be refused by
/// something outside it, which is why it has so much more to say underneath.
private struct GeneralSettingsView: View {
    @AppStorage(PetPreferences.statusRunReversedKey) private var runReversed = false

    /// Read from the system on open rather than stored, because it can change
    /// without us — see `LaunchAtLogin`.
    @State private var loginStatus = LaunchAtLogin.status
    @State private var loginFailure: String?

    var body: some View {
        Form {
            Section("状态栏奔跑动画") {
                Toggle("反转奔跑", isOn: $runReversed)
            }

            Section("启动") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("开机时自动启动 Mona", isOn: launchAtLogin)

                    // Only `.requiresApproval` gets said out loud. The other two
                    // off states are both just "not a login item" — `.notFound`
                    // means the system has no record of this bundle at all,
                    // which is simply what never having registered looks like,
                    // and warning about it told people something was wrong when
                    // nothing was.
                    if loginStatus == .requiresApproval {
                        Label("系统那边还要放行一次——在「登录项与扩展」里把 Mona 打开。",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("打开登录项设置") { LaunchAtLogin.openLoginItemsSettings() }
                    }

                    // A real failure, on the other hand, is worth every word:
                    // this is the only place the reason ever appears.
                    if let loginFailure {
                        Label(loginFailure, systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        // The pane can be changed from System Settings while this window is only
        // hidden, so the status is re-read rather than trusted from last time.
        .onAppear { loginStatus = LaunchAtLogin.status }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { wanted in
                do {
                    try LaunchAtLogin.set(wanted)
                    loginFailure = nil
                } catch {
                    loginFailure = error.localizedDescription
                }
                // Read back rather than assumed: asking for it is not the same
                // as getting it, and `.requiresApproval` is exactly that gap.
                loginStatus = LaunchAtLogin.status
            }
        )
    }
}

/// What he does on the desktop: whether he speaks up on his own, which lookups
/// appear when you right-click him, and where the two of them read from.
///
/// `@AppStorage` rather than a store object, so a change here rewrites the
/// context menu without anything having to notice and forward it.
private struct PetBehaviourSettingsView: View {
    @AppStorage(PetPreferences.petVisibleKey) private var visible = false
    @AppStorage(PetQuietHours.disabledKey) private var neverSpeaksFirst = false
    @AppStorage(PetPreferences.showsCodexUsageKey) private var showsCodexUsage = true
    @AppStorage(PetPreferences.showsClaudeUsageKey) private var showsClaudeUsage = true
    @AppStorage(PetPreferences.showsMachineStatusKey) private var showsMachineStatus = true
    @AppStorage(PetPreferences.codexHomeKey) private var codexHome = ""
    @AppStorage(PetPreferences.claudeStatusLineKey) private var claudeStatusLine = ""

    /// Re-probed whenever a path changes or the window comes back, because the
    /// answer depends on files that move underneath us.
    @State private var codexStatus: (ok: Bool, detail: String) = (false, "")
    @State private var claudeStatus: (ok: Bool, detail: String) = (false, "")
    @State private var didCopySnippet = false
    @State private var settingsState = ClaudeUsageReader.SettingsState.missing

    var body: some View {
        Form {
            Section("显示") {
                Toggle("在桌面显示桌宠", isOn: $visible)
            }

            Section("对话") {
                Toggle("从不主动说话", isOn: $neverSpeaksFirst)
            }

            Section("右键菜单") {
                Toggle("查看 Codex 用量", isOn: $showsCodexUsage)
                Toggle("查看 Claude 额度", isOn: $showsClaudeUsage)
                Toggle("查看本机状态", isOn: $showsMachineStatus)
            }

            // Where each one reads from only matters if you are using it, so the
            // section goes away with the switch above rather than sitting there
            // asking to be configured for something you turned off.
            if showsCodexUsage {
                Section {
                    PathRow(
                        label: "目录",
                        placeholder: "~/.codex",
                        path: $codexHome,
                        chooseDirectories: true,
                        status: codexStatus
                    )
                } header: {
                    SectionHeader(title: "Codex 额度读取", explanation: Self.codexExplanation)
                }
            }

            if showsClaudeUsage {
                Section {
                    // Configuring Claude Code comes first: until that is done there
                    // is no file for the path below to point at. Always shown rather
                    // than only when broken — a tick is worth as much as an
                    // instruction, and the snippet stays available to paste again.
                    ClaudeSetupHint(state: settingsState, didCopy: $didCopySnippet)

                    PathRow(
                        label: "额度文件",
                        placeholder: "~/.claude/statusline.json",
                        path: $claudeStatusLine,
                        chooseDirectories: false,
                        status: claudeStatus
                    )
                } header: {
                    SectionHeader(title: "Claude 额度读取", explanation: Self.claudeExplanation)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: codexHome) { refresh() }
        .onChange(of: claudeStatusLine) { refresh() }
        .onChange(of: showsCodexUsage) { refresh() }
        .onChange(of: showsClaudeUsage) { refresh() }
        // The window it shows lives in the app delegate, so the change is
        // announced rather than applied — same arrangement as the calendar's.
        .onChange(of: visible) { _, _ in
            NotificationCenter.default.post(name: PetPreferences.petSettingsChanged,
                                            object: nil)
        }
    }

    private func refresh() {
        codexStatus = CodexUsageReader.probe()
        claudeStatus = ClaudeUsageReader.probe()
        settingsState = ClaudeUsageReader.settingsState()
    }

    private static let codexExplanation = """
    你每次用 Codex，它都会把这次用掉多少额度记在 ~/.codex \
    下（Codex 的默认主目录，未设置 CODEX_HOME 时使用，否则在下面填新路径即可）。\
    Mona 读的就是这个文件。

    • 不联网，不上传任何东西
    • 完全不碰你的 Codex 登录信息
    • 不读你和 Codex 聊了什么，只取额度信息
    • 只读，不会改动或删除任何文件

    数据只在 Codex 开着的时候更新，关掉之后 Mona 看到的是最后一次的数字。
    """

    private static let claudeExplanation = """
    Claude Code 知道你还剩多少额度，但它只放在自己的内存里，不会存成文件，所以 Mona \
    没法直接看到。

    办法是通过 ~/.claude/settings.json 里加配置，让 Claude 把\
    额度数字写进 statusline.json。Mona 读的就是这个文件。\
    （~/.claude 是 Claude Code 的默认主目录。）

    • 不联网，不上传任何东西
    • 完全不碰你的 Claude 登录信息
    • 不读你和 Claude 聊了什么，只取额度信息
    • 只读，不会改动或删除任何文件

    数据只在 Claude Code 开着的时候更新，关掉之后 Mona 看到的是最后一次的数字。
    """
}

/// A section title with a question mark that opens the explanation.
///
/// Written for someone who has no idea what a status line is and reasonably
/// wants to know what a desktop pet is doing with their files. The answer —
/// reads two local files, sends nothing — is short enough to give in full, so it
/// is given in full rather than summarised into "your privacy is important".
private struct SectionHeader: View {
    let title: String
    let explanation: String
    @State private var isShowing = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button {
                isShowing = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 360, alignment: .leading)
                    .padding(16)
            }
            Spacer()
        }
    }
}

/// What to do about a Claude window that is not reporting anything.
///
/// The instruction lives next to the failure rather than in the README, because
/// this is where you are standing when you find out. The snippet is built from
/// the configured path, so moving the file does not silently invalidate it.
private struct ClaudeSetupHint: View {
    let state: ClaudeUsageReader.SettingsState
    @Binding var didCopy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(headline, systemImage: state.isConfigured ? "checkmark.circle.fill" : "info.circle")
                .font(.caption)
                // Not green. Green is reserved for the line below, which reports
                // whether data is actually arriving; this one only says the
                // plumbing is in place, and two greens would read as two results.
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(didCopy ? "已复制 ✓" : "复制配置") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        ClaudeUsageReader.statusLineSnippet, forType: .string
                    )
                    didCopy = true
                }
                Button("打开 ~/.claude") {
                    NSWorkspace.shared.selectFile(
                        nil,
                        inFileViewerRootedAtPath: FileManager.default
                            .homeDirectoryForCurrentUser
                            .appendingPathComponent(".claude").path
                    )
                }
            }

            Text("只对 Claude.ai 的 Pro / Max 订阅有效；用 API key 的没有这两个窗口。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var headline: String {
        switch state {
        case let .configured(destination):
            return "已在 ~/.claude/settings.json 里配置好，额度会写到 \(destination)。"
        case let .takenBySomethingElse(command):
            return "~/.claude/settings.json 里的 statusLine 写的是别的地方"
                + "（statusLine 全局只有一个，可能被别的工具占用了）：\(command)"
        case .missing:
            return "Claude Code 不会把额度写到磁盘上，需要在 ~/.claude/settings.json"
                + " 里加一段 statusLine 配置，让它顺手存一份。"
        }
    }
}

/// A path field with a picker and, underneath, whether that path currently has
/// anything in it.
///
/// The status line is the point of the row. Both readers fail the same way from
/// the outside — he says he cannot see — and without this you cannot tell a
/// wrong path from a tool that has never run.
private struct PathRow: View {
    let label: String
    let placeholder: String
    @Binding var path: String
    let chooseDirectories: Bool
    let status: (ok: Bool, detail: String)

    /// Bound straight through again.
    ///
    /// Committing only on Return or on losing focus sounded safer, but clicking
    /// elsewhere in a settings window does not reliably take focus away from a
    /// text field — so a typed path simply never took effect. What that guard was
    /// protecting against is now handled at the two points that actually matter:
    /// nothing holds the keyboard when the window opens, so a stray keystroke has
    /// nowhere to land, and a value that cannot be a path is ignored and said so.

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(label, text: $path, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                Button("选择…", action: choose)
                if !path.isEmpty {
                    Button("默认") { path = "" }
                }
            }

            if !PetPreferences.isUsablePath(path) {
                // Said here rather than swallowed: an unusable value is ignored,
                // and without this the field would look set while nothing uses it.
                Label("要填绝对路径（以 / 或 ~ 开头），这个会被忽略",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            } else {
                Label(status.detail,
                      systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.caption)
                    // Green for a working source, matching the tick above it: the
                    // two lines answer the same question — is this one live? — so
                    // they should be readable at the same glance.
                    .foregroundStyle(status.ok ? Color.green : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = chooseDirectories
        panel.canChooseFiles = !chooseDirectories
        panel.allowsMultipleSelection = false
        // Both live under dot-directories, which the panel hides by default —
        // a picker that cannot reach ~/.claude would be worse than no picker.
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Store it back as ~/… when it is inside the home directory, so the field
        // stays readable and keeps working if the account is ever renamed.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        path = url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
    }
}
