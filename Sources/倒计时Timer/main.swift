import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

@main
struct TwilightTimerApp: App {
    @NSApplicationDelegateAdaptor(TwilightAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            TimerWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct TimerWindow: View {
    @StateObject private var model = TimerModel()
    @State private var keyMonitor: Any?

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 850, idealWidth: 900, minHeight: 650, idealHeight: 690)
            .onAppear { installKeyboardShortcuts() }
            .onDisappear { removeKeyboardShortcuts() }
    }

    private func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model, event.window === NSApp.keyWindow, !event.isARepeat else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 15 && modifiers == .command {
                model.reset()
                return nil
            }

            let firstResponder = event.window?.firstResponder
            if event.keyCode == 49 && (firstResponder is NSTextField || firstResponder is NSTextView) {
                return event
            }

            if event.keyCode == 49 && modifiers.isEmpty {
                model.toggleRunning()
                return nil
            }

            return event
        }
    }

    private func removeKeyboardShortcuts() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class TwilightAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

struct FavoriteTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var seconds: Int
}

struct BuiltinSound: Identifiable {
    let id: String
    let name: String
    let fileName: String
}

@MainActor
final class TimerModel: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published var hours = 0
    @Published var minutes = 25
    @Published var seconds = 0
    @Published var title = "完成今天最重要的一件事"
    @Published var isRunning = false
    @Published var isFinished = false
    @Published var isAlarmPlaying = false
    @Published var loops = false
    @Published var notificationsEnabled = true
    @Published var volume = 0.78 { didSet { audioPlayer?.volume = Float(volume) } }
    @Published var soundName = "暮色律动"
    @Published var soundURL: URL?
    @Published private(set) var selectedBuiltinSoundID: String?
    @Published var favorites: [FavoriteTimer] = []

    private(set) var remaining = 1500
    private var total = 1500
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let favoritesKey = "twilightFavorites"

    static let builtinSounds = [
        BuiltinSound(id: "warm-groovy", name: "暮色律动", fileName: "01_Warm-groovy-109-bpm-funk-loop.wav"),
        BuiltinSound(id: "notification-beep", name: "轻快提示", fileName: "02_universfield-notification-beep-229154.mp3"),
        BuiltinSound(id: "notification-040", name: "清脆星点", fileName: "03_universfield-new-notification-040-493469.mp3"),
        BuiltinSound(id: "notification-062", name: "柔光提醒", fileName: "04_universfield-new-notification-062-494544.mp3"),
        BuiltinSound(id: "notification-051", name: "双音确认", fileName: "05_universfield-new-notification-051-494246.mp3")
    ]

    private static let defaultFavorites = [
        FavoriteTimer(name: "短暂休息", seconds: 5 * 60),
        FavoriteTimer(name: "番茄单元", seconds: 25 * 60),
        FavoriteTimer(name: "深度专注", seconds: 50 * 60)
    ]

    private static let legacyDefaultFavorites = [
        (name: "晨间整理", seconds: 10 * 60),
        (name: "深度专注", seconds: 25 * 60),
        (name: "起身休息", seconds: 5 * 60 + 5)
    ]

    override init() {
        super.init()
        loadFavorites()
        if let defaultSound = Self.builtinSounds.first {
            selectBuiltinSound(defaultSound, preview: false)
        }
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - Double(remaining) / Double(total)))
    }

    var displayTime: String {
        Self.format(seconds: remaining)
    }

    var configuredTime: String {
        Self.format(seconds: total)
    }

    var statusText: String {
        if isFinished { return "声音正在播放" }
        if isRunning { return "正在专注" }
        if remaining < total { return "已暂停" }
        return remaining == 0 ? "请设置倒计时间" : "准备开始"
    }

    static func format(seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    func syncFromFields() {
        guard !isRunning else { return }
        hours = max(0, min(99, hours))
        minutes = max(0, min(59, minutes))
        seconds = max(0, min(59, seconds))
        remaining = hours * 3600 + minutes * 60 + seconds
        total = remaining
        isFinished = false
        objectWillChange.send()
    }

    func setDuration(_ duration: Int) {
        pause()
        stopSound()
        let safe = max(0, duration)
        hours = min(99, safe / 3600)
        minutes = (safe % 3600) / 60
        seconds = safe % 60
        remaining = hours * 3600 + minutes * 60 + seconds
        total = remaining
        isFinished = false
        objectWillChange.send()
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard remaining > 0 else { return }
        stopSound()
        isFinished = false
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        stopSound()
        remaining = hours * 3600 + minutes * 60 + seconds
        total = remaining
        isFinished = false
        objectWillChange.send()
    }

    func startAnotherRound() {
        stopSound()
        isFinished = false
        remaining = total
        objectWillChange.send()
        start()
    }

    private func tick() {
        guard remaining > 0 else { finish(); return }
        remaining -= 1
        objectWillChange.send()
        if remaining == 0 { finish() }
    }

    private func finish() {
        pause()
        isFinished = true
        playSound(looping: true)
        if notificationsEnabled { notify() }
        if loops {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.stopSound()
                self.remaining = self.total
                self.start()
            }
        }
    }

    func addFavorite(name: String, hours: Int, minutes: Int, seconds: Int) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = max(0, hours) * 3600 + max(0, min(59, minutes)) * 60 + max(0, min(59, seconds))
        guard !trimmed.isEmpty, duration > 0 else { return false }
        favorites.append(FavoriteTimer(name: trimmed, seconds: duration))
        saveFavorites()
        return true
    }

    func deleteFavorite(_ favorite: FavoriteTimer) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }

    func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "选择声音"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedBuiltinSoundID = nil
        soundURL = url
        soundName = url.lastPathComponent
        previewSound()
    }

    func selectBuiltinSound(_ sound: BuiltinSound, preview: Bool = true) {
        guard let url = Self.builtinSoundURL(for: sound) else { return }
        selectedBuiltinSoundID = sound.id
        soundURL = url
        soundName = sound.name
        if preview { previewSound() }
    }

    private static func builtinSoundURL(for sound: BuiltinSound) -> URL? {
        if let resources = Bundle.main.resourceURL {
            let bundledURL = resources.appendingPathComponent("BuiltinSounds").appendingPathComponent(sound.fileName)
            if FileManager.default.fileExists(atPath: bundledURL.path) { return bundledURL }
        }

        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let developmentURL = projectURL.appendingPathComponent("内置铃声确认").appendingPathComponent(sound.fileName)
        return FileManager.default.fileExists(atPath: developmentURL.path) ? developmentURL : nil
    }

    func previewSound() { playSound(looping: false) }

    private func playSound(looping: Bool) {
        stopSound()
        guard let url = soundURL else {
            NSSound.beep()
            isAlarmPlaying = false
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = looping ? -1 : 0
            audioPlayer?.volume = Float(volume)
            audioPlayer?.play()
            isAlarmPlaying = true
        } catch {
            NSSound.beep()
            isAlarmPlaying = false
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard audioPlayer === player else { return }
        audioPlayer = nil
        isAlarmPlaying = false
    }

    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        isAlarmPlaying = false
    }

    private func notify() {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "倒计时结束" : title
        content.body = "时间到了"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoriteTimer].self, from: data) {
            let isUnchangedLegacyDefault = decoded.count == Self.legacyDefaultFavorites.count
                && zip(decoded, Self.legacyDefaultFavorites).allSatisfy {
                    $0.0.name == $0.1.name && $0.0.seconds == $0.1.seconds
                }

            favorites = isUnchangedLegacyDefault ? Self.defaultFavorites : decoded
            if isUnchangedLegacyDefault {
                saveFavorites()
            }
        } else {
            favorites = Self.defaultFavorites
            saveFavorites()
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}

private enum Palette {
    // Exact light-theme values resolved from visualize.css used by the approved demo.
    static let background = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let night = Color(red: 0.992, green: 0.947, blue: 0.968)       // white 90% + pink 10%
    static let dusk = Color(red: 0.994, green: 0.957, blue: 0.976)        // white 92% + pink 8%
    static let card = Color(red: 0.102, green: 0.110, blue: 0.122)
    static let ink = Color(red: 0.102, green: 0.110, blue: 0.122)         // rgb(26,28,31)
    static let muted = Color(red: 0.102, green: 0.110, blue: 0.122).opacity(0.494)
    static let border = Color(red: 0.102, green: 0.110, blue: 0.122).opacity(0.08)
    static let ember = Color(red: 0.200, green: 0.612, blue: 1.000)       // primary / series 1
    static let gold = Color(red: 0.953, green: 0.533, blue: 0.231)        // series 2
    static let violet = Color(red: 0.922, green: 0.467, blue: 0.694)      // series 4
}

struct ContentView: View {
    @ObservedObject var model: TimerModel
    @State private var showingAddFavorite = false
    @State private var showingHelp = false

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    TimerStage(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, 24).padding(.trailing, 20).padding(.bottom, 24)
                    Divider().overlay(Palette.border).padding(.bottom, 24)
                    SettingsPanel(model: model, showingAddFavorite: $showingAddFavorite)
                        .frame(width: 285).padding(.horizontal, 22).padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showingAddFavorite) { AddFavoriteView(model: model) }
        .sheet(isPresented: $showingHelp) { HelpView().frame(width: 410, height: 330) }
        .onAppear {
            model.syncFromFields()
        }
    }

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                // CSS linear-gradient(150deg, night, background/violet mix)
                LinearGradient(
                    colors: [Palette.night, Palette.dusk],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // CSS radial-gradient at 78% 15%: violet environment light.
                RadialGradient(
                    colors: [Palette.violet.opacity(0.24), .clear],
                    center: UnitPoint(x: 0.78, y: 0.15),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.42
                )

                // CSS radial-gradient at 18% 88%: ember environment light.
                RadialGradient(
                    colors: [Palette.ember.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.18, y: 0.88),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.45
                )

                // Independent ambient sun from the HTML prototype.
                Circle()
                    .fill(RadialGradient(
                        stops: [
                            .init(color: Palette.gold.opacity(0.94), location: 0),
                            .init(color: Palette.gold.opacity(0.88), location: 0.24),
                            .init(color: Palette.ember.opacity(0.80), location: 0.50),
                            .init(color: .clear, location: 0.72)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.42),
                        startRadius: 0,
                        endRadius: 175
                    ))
                    .frame(width: 350, height: 350)
                    .opacity(0.23)
                    .offset(x: proxy.size.width * 0.48, y: -proxy.size.height * 0.21)
                    .allowsHitTesting(false)
            }
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Palette.gold, Palette.ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sun.horizon.fill").foregroundStyle(.white)
            }.frame(width: 37, height: 37).shadow(color: Palette.ember.opacity(0.30), radius: 14, y: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("暮光计时").font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink)
                Text("把专注留在日落之前").font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { showingHelp = true } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(QuietIconButton()).help("使用说明")
        }.padding(.horizontal, 25).padding(.top, 23).padding(.bottom, 20)
    }
}

struct TimerStage: View {
    @ObservedObject var model: TimerModel

    var body: some View {
        VStack(spacing: 19) {
            TextField("给这个计时器命名", text: $model.title)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink)
                .padding(.bottom, 9).overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
                .frame(maxWidth: 330).disabled(model.isRunning)

            if model.isFinished {
                finishedContent
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            } else {
                activeContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.isFinished)
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Palette.card.opacity(0.045), Palette.card.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(LinearGradient(colors: [Palette.border.opacity(0.72), Palette.ember.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.09), radius: 35, y: 22)
        )
    }

    private var activeContent: some View {
        Group {
            ZStack {
                Circle().stroke(Palette.border.opacity(0.55), lineWidth: 13)
                Circle().trim(from: 0, to: model.progress)
                    .stroke(AngularGradient(colors: [Palette.gold, Palette.ember, Palette.gold], center: .center), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Palette.ember.opacity(0.38), radius: 16)
                    .animation(.easeInOut(duration: 0.35), value: model.progress)
                Circle().fill(RadialGradient(colors: [Palette.ember.opacity(0.08), Palette.night.opacity(0.78)], center: .bottom, startRadius: 0, endRadius: 150)).padding(15)
                Text(model.displayTime)
                    .font(.custom("Avenir Next", size: 48, relativeTo: .largeTitle).weight(.medium))
                    .monospacedDigit().foregroundStyle(Palette.ink)
                    .shadow(color: Palette.gold.opacity(0.14), radius: 22)
            }.frame(width: 282, height: 282)

            HStack(spacing: 7) {
                Circle().fill(model.isRunning ? Palette.gold : Palette.muted).frame(width: 6, height: 6)
                Text(model.statusText).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.muted)
            }.frame(height: 20)

            HStack(alignment: .bottom, spacing: 9) {
                TimeInput(label: "小时", value: $model.hours, enabled: !model.isRunning)
                Text(":").font(.title3).foregroundStyle(Palette.muted).padding(.bottom, 10)
                TimeInput(label: "分钟", value: $model.minutes, enabled: !model.isRunning)
                Text(":").font(.title3).foregroundStyle(Palette.muted).padding(.bottom, 10)
                TimeInput(label: "秒", value: $model.seconds, enabled: !model.isRunning)
            }
            .onChange(of: model.hours) { _ in model.syncFromFields() }
            .onChange(of: model.minutes) { _ in model.syncFromFields() }
            .onChange(of: model.seconds) { _ in model.syncFromFields() }

            HStack(spacing: 10) {
                Button { model.toggleRunning() } label: {
                    Label(model.isRunning ? "暂停一下" : (model.remaining < model.hours * 3600 + model.minutes * 60 + model.seconds ? "继续专注" : "开始专注"), systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(SunsetButton()).disabled(model.remaining == 0)
                Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 42, height: 38) }
                    .buttonStyle(QuietIconButton()).help("重置")
            }.frame(maxWidth: 345)
        }
    }

    private var finishedContent: some View {
        Group {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(colors: [Palette.ember, Palette.gold, Palette.violet, Palette.ember], center: .center),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Palette.ember.opacity(0.27), radius: 22, y: 10)
                Circle()
                    .fill(RadialGradient(colors: [Palette.violet.opacity(0.10), Palette.night.opacity(0.84)], center: .center, startRadius: 0, endRadius: 145))
                    .padding(15)
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Palette.gold, Palette.ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "checkmark").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                    }.frame(width: 55, height: 55).shadow(color: Palette.ember.opacity(0.24), radius: 14, y: 7)
                    Text("倒计时完成")
                        .font(.system(size: 19, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink)
                    Text("\(model.configuredTime) 已结束")
                        .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(Palette.muted)
                }
            }.frame(width: 282, height: 282)

            HStack(spacing: 7) {
                Image(systemName: model.isAlarmPlaying ? "speaker.wave.2.fill" : "checkmark.circle.fill")
                Text(model.isAlarmPlaying ? "提醒声音正在播放" : "提醒已停止")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(model.isAlarmPlaying ? Palette.ember : Palette.muted)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(model.isAlarmPlaying ? Palette.ember.opacity(0.10) : Palette.ink.opacity(0.045)))

            Spacer(minLength: 42)

            HStack(spacing: 10) {
                Button { model.stopSound() } label: {
                    Label("停止提醒", systemImage: "speaker.slash.fill").frame(maxWidth: .infinity)
                }.buttonStyle(SunsetButton()).disabled(!model.isAlarmPlaying)
                Button { model.startAnotherRound() } label: {
                    Label("再来一轮", systemImage: "arrow.counterclockwise")
                }.buttonStyle(SoftButton())
            }.frame(maxWidth: 365)
        }
    }
}

struct TimeInput: View {
    let label: String
    @Binding var value: Int
    let enabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.muted)
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.ink).frame(width: 62, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.ink.opacity(0.045)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border)))
                .disabled(!enabled)
        }
    }
}

struct SettingsPanel: View {
    @ObservedObject var model: TimerModel
    @Binding var showingAddFavorite: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                soundSection
                Divider().overlay(Palette.border)
                completionSection
                Divider().overlay(Palette.border)
                favoritesSection
            }.padding(.top, 5)
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("结束声音").sectionTitle(); Spacer(); Text("5 种内置").tinyBadge() }
            Waveform(isActive: model.isAlarmPlaying)
            HStack(spacing: 10) {
                Image(systemName: "music.note").foregroundStyle(Palette.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.soundName).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(model.selectedBuiltinSoundID == nil ? "本地音频 · 到点循环" : "内置铃声 · 到点循环").font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { model.previewSound() } label: { Image(systemName: "headphones") }.buttonStyle(QuietIconButton()).help("试听")
            }.padding(.vertical, 9).overlay(alignment: .top) { Divider().overlay(Palette.border) }.overlay(alignment: .bottom) { Divider().overlay(Palette.border) }
            Menu {
                ForEach(TimerModel.builtinSounds) { sound in
                    Button { model.selectBuiltinSound(sound) } label: {
                        if model.selectedBuiltinSoundID == sound.id {
                            Label(sound.name, systemImage: "checkmark")
                        } else {
                            Text(sound.name)
                        }
                    }
                }
                Divider()
                Button { model.chooseSound() } label: {
                    Label("选择本地音频…", systemImage: "folder")
                }
            } label: {
                Label("选择提醒声音", systemImage: "chevron.up.chevron.down")
            }
            .menuStyle(.button)
            .buttonStyle(SoftButton())
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1").foregroundStyle(Palette.muted)
                Slider(value: $model.volume, in: 0...1).tint(Palette.ember)
                Text("\(Int(model.volume * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 30)
            }
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("完成后").sectionTitle()
            alignedSwitch("自动开始下一轮", isOn: $model.loops)
            alignedSwitch("显示系统通知", isOn: $model.notificationsEnabled)
        }.font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.ink)
    }

    private func alignedSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Palette.ember)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("常用").sectionTitle()
                Spacer()
                Button { showingAddFavorite = true } label: { Label("添加", systemImage: "plus") }.buttonStyle(SoftButton())
            }
            if model.favorites.isEmpty {
                Text("还没有常用计时，点击“添加”保存一个。")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Palette.muted).padding(.vertical, 8)
            } else {
                ForEach(model.favorites) { favorite in
                    HStack(spacing: 7) {
                        Button {
                            model.setDuration(favorite.seconds)
                            model.title = favorite.name
                        } label: {
                            HStack {
                                Text(favorite.name).lineLimit(1)
                                Spacer()
                                Text(TimerModel.format(seconds: favorite.seconds)).monospacedDigit().foregroundStyle(Palette.muted)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { model.deleteFavorite(favorite) } label: { Image(systemName: "trash").foregroundStyle(Palette.muted) }
                            .buttonStyle(.plain).help("删除 \(favorite.name)")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink)
                    .padding(.vertical, 8).overlay(alignment: .bottom) { Divider().overlay(Palette.border) }
                }
            }
        }
    }
}

struct Waveform: View {
    let isActive: Bool
    private let heights: [CGFloat] = [12, 22, 32, 17, 27, 35, 20, 30, 15, 25, 33, 18]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !isActive)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 4)
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    let animatedHeight = isActive && (index + phase).isMultiple(of: 3) ? height * 0.65 : height
                    Capsule().fill(LinearGradient(colors: [Palette.ember, Palette.gold], startPoint: .bottom, endPoint: .top))
                        .frame(maxWidth: .infinity).frame(height: max(8, animatedHeight))
                }
            }.frame(height: 38)
        }
    }
}

struct AddFavoriteView: View {
    @ObservedObject var model: TimerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hours = 0
    @State private var minutes = 25
    @State private var seconds = 0
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("添加常用计时").font(.system(size: 20, weight: .medium, design: .rounded))
            TextField("名称，例如：阅读", text: $name).textFieldStyle(.roundedBorder)
            HStack(alignment: .bottom, spacing: 9) {
                FavoriteTimeField(label: "小时", value: $hours)
                Text(":").padding(.bottom, 9)
                FavoriteTimeField(label: "分钟", value: $minutes)
                Text(":").padding(.bottom, 9)
                FavoriteTimeField(label: "秒", value: $seconds)
            }
            if showError { Text("请输入名称，并设置大于 0 秒的时长。").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存到常用") {
                    if model.addFavorite(name: name, hours: hours, minutes: minutes, seconds: seconds) { dismiss() } else { showError = true }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 390)
    }
}

struct FavoriteTimeField: View {
    let label: String
    @Binding var value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number).textFieldStyle(.roundedBorder).frame(width: 85)
        }
    }
}

struct SunsetButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Color(red: 0.25, green: 0.07, blue: 0.04))
            .frame(height: 40).background(RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Palette.gold, Palette.ember], startPoint: .leading, endPoint: .trailing)).opacity(configuration.isPressed ? 0.75 : 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SoftButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
            configuration.label.font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 10).frame(height: 29).background(RoundedRectangle(cornerRadius: 8).fill(Palette.ink.opacity(configuration.isPressed ? 0.10 : 0.045)))
    }
}

struct QuietIconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Palette.ink.opacity(0.82)).frame(width: 34, height: 31)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.ink.opacity(configuration.isPressed ? 0.10 : 0.045)))
    }
}

extension Text {
    func sectionTitle() -> some View { self.font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Palette.ink) }
    func tinyBadge() -> some View { self.font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Palette.gold).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Palette.ember.opacity(0.13))) }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("暮光计时").font(.title2.weight(.medium))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(QuietIconButton())
                    .help("关闭说明")
                }
                Text("输入小时、分钟和秒，点击 “开始专注”。进入倒计时。\n\n任选内置的提示音，也可以选择本地音频自定义提示音。\n\n支持把常用计时保存到右侧，一键载入或删除。\n\n自定义声音与常用计时只保存在本机。\n\n快捷键：空格 开始 / 暂停；⌘R 重置；⌘N新建；ESC退出本说明。\n\n\n鸣谢：暮色律动提示音来自Orange Free Sounds, licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)\n\nFrom Estellla")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .onExitCommand { dismiss() }
    }
}
