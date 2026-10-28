import SwiftUI
import AppKit
import Observation
import TrackerCore

struct Lesson: Identifiable, Equatable {
    let id: String // BV base URL; one card per multi-part course.
    let video: Video
    let course: Course
    init(id: String, video: Video, course: Course? = nil) {
        self.id = courseID(id) ?? id; self.video = video
        self.course = course ?? Course(title: video.title, selected: video.selected, currentPart: partNumber(id))
    }
    var title: String { course.title.isEmpty ? (video.title.isEmpty ? (URL(string:id)?.lastPathComponent ?? "B站课程") : video.title) : course.title }
    var part: String { "P\(course.currentPart)" }
    var totalText: String { course.totalParts.map { "P\(course.currentPart) / 共 \($0) 集" } ?? "P\(course.currentPart) · 总集数待识别" }
    var url: String { partURL(id, course.currentPart) }
}
@MainActor @Observable final class WidgetModel {
    var lessons: [Lesson] = [] {
        didSet {
            let visible = lessons.filter { $0.course.selected }
            if selected != visible { selected = visible }
            if selectedCount != visible.count { selectedCount = visible.count }
        }
    }
    private(set) var selected: [Lesson] = []
    private(set) var selectedCount = 0
    var connection = "正在启动本机同步…"
    var online = false
    var lastSync: Date?
    var errorMessage: String?
    var alwaysOnTop: Bool
    var compact: Bool
    private(set) var theme: WidgetTheme
    var feedback: String?
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var systemIsDark = false
    private(set) var appearanceMode: AppearanceMode
    var editing: Lesson?
    var palette: ThemePalette { ThemePalette(theme: theme, dark: appearanceMode == .system ? systemIsDark : appearanceMode == .dark) }
    @ObservationIgnored let store: DiskStore?
    @ObservationIgnored var configurePanel: (() -> Void)?
    @ObservationIgnored var showManager: (() -> Void)?
    @ObservationIgnored var themeDidChange: (() -> Void)?
    @ObservationIgnored var hideWidget: (() -> Void)?
    init(store: DiskStore?) {
        self.store = store
        appearanceMode = AppearanceMode(rawValue: WidgetPreferences.defaults.string(forKey:"appearanceMode") ?? "system") ?? .system
        theme = WidgetTheme(rawValue: WidgetPreferences.defaults.string(forKey: "theme") ?? "mint") ?? .mint
        alwaysOnTop = WidgetPreferences.defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        compact = WidgetPreferences.defaults.bool(forKey: "compact")
        refresh()
    }
    func refresh() {
        guard let store else { return }
        var database = store.database; database.migrateCourses()
        let updated = database.courses.map { base, course in
            let url = partURL(base, course.currentPart)
            let knownDuration = course.parts.first { $0.page == course.currentPart }?.duration ?? 0
            let video = database.videos[url] ?? Video(title:course.title, selected:course.selected, duration:knownDuration)
            return Lesson(id:base, video:video, course:course)
        }.sorted {
            if $0.video.updated == $1.video.updated { return $0.id < $1.id }
            return $0.video.updated > $1.video.updated
        }
        if lessons != updated { lessons = updated }
    }
    func setAppearance(_ value: AppearanceMode, persist: Bool = true) {
        appearanceMode = value
        if persist { WidgetPreferences.defaults.set(value.rawValue, forKey:"appearanceMode") }
        themeDidChange?()
    }
    func edit(_ lesson: Lesson) { editing = lesson; showManager?() }
    func saveProgress(_ lesson: Lesson, page: Int, total: Int?, seconds: Double, duration: Double) throws {
        try store?.setManualProgress(base:lesson.id,page:page,total:total,seconds:seconds,duration:duration)
        refresh(); editing = nil
    }
    func resume(_ lesson: Lesson) {
        do { try store?.resumeAutomatic(base:lesson.id); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func select(_ lesson: Lesson) {
        do { try store?.select(lesson.id, value: !lesson.course.selected); refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    func toggleTop() {
        alwaysOnTop.toggle(); WidgetPreferences.defaults.set(alwaysOnTop, forKey: "alwaysOnTop"); configurePanel?()
    }
    func toggleCompact() {
        compact.toggle(); WidgetPreferences.defaults.set(compact, forKey: "compact"); configurePanel?()
    }
    func setTheme(_ value: WidgetTheme, persist: Bool = true) {
        theme = value
        if persist { WidgetPreferences.defaults.set(value.rawValue, forKey: "theme") }
        themeDidChange?()
    }
    func copyToken() {
        guard let token = store?.token else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token, forType: .string)
        feedback = "配对码已复制，请粘贴到 Chrome 扩展选项页。"
    }
    func open(_ lesson: Lesson) {
        guard let url = URL(string:lesson.url), canonicalVideo(lesson.url) != nil else { return }
        NSWorkspace.shared.open(url)
    }
    func revealData() {
        if let url = store?.directory { NSWorkspace.shared.open(url) }
    }
    func revealExtension() {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("extension"), FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            feedback = "在 Chrome 的 chrome://extensions 开启开发者模式，选择“加载已解压的扩展程序”，选中刚显示的 extension 文件夹。"
        } else { feedback = "请在交付包中找到 extension 文件夹，再在 Chrome 中加载。" }
    }
}
