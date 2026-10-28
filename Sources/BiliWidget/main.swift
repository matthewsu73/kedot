import AppKit
import SwiftUI
import TrackerCore
import Observation
import os

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class DragView: NSView {
    private var pointerStart = NSPoint.zero
    private var windowStart = NSPoint.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        pointerStart = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        updatePosition(event)
    }
    private func updatePosition(_ event: NSEvent) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: windowStart.x + point.x - pointerStart.x,
                                      y: windowStart.y + point.y - pointerStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        updatePosition(event)
        guard let window else { return }
        WidgetPreferences.defaults.set(NSStringFromPoint(window.frame.origin), forKey: "widgetOrigin")
    }
}
final class ResizeView: NSView {
    private var start = NSPoint.zero
    private var frameStart = NSRect.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func mouseDown(with event:NSEvent) {
        start = window?.convertPoint(toScreen:event.locationInWindow) ?? .zero
        frameStart = window?.frame ?? .zero
    }
    private func update(_ event:NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen:event.locationInWindow)
        let size = WidgetLayout.bounded(CGSize(width:frameStart.width+point.x-start.x,height:frameStart.height-point.y+start.y))
        window.setFrame(NSRect(x:frameStart.minX,y:frameStart.maxY-size.height,width:size.width,height:size.height),display:true)
    }
    override func mouseDragged(with event:NSEvent) { update(event) }
    override func mouseUp(with event:NSEvent) {
        update(event)
        if let delegate = window?.delegate as? AppDelegate { delegate.clampPanel(); delegate.saveGeometry() }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: FloatingPanel!
    var manager: NSWindow?
    var statusItem: NSStatusItem?
    var model: WidgetModel!
    var api: TrackerAPI?
    let server = LocalServer()
    var preview = ProcessInfo.processInfo.arguments.contains("--preview")
    let preferences = WidgetPreferences.defaults
    var restoring = false
    var lastCompact = false
    var appearanceObservation: NSKeyValueObservation?
    var dragWidth: NSLayoutConstraint?
    var dragHeight: NSLayoutConstraint?
    var dragLeading: NSLayoutConstraint?
    var dragTop: NSLayoutConstraint?
    var geometrySave: DispatchWorkItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = dataDirectory()
        do {
            let store = try DiskStore(directory: directory)
            model = WidgetModel(store:store)
            api = TrackerAPI(store:store, port:serverPort())
        } catch {
            model = WidgetModel(store:nil); model.errorMessage = error.localizedDescription
            model.connection = "启动失败，请打开管理课程查看"
        }
        model.systemIsDark = NSApplication.shared.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        if preview { seedPreview() }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--theme"), arguments.count > index + 1,
           let theme = WidgetTheme(rawValue: arguments[index + 1]) { model.setTheme(theme, persist: false) }
        if let index = arguments.firstIndex(of:"--appearance"), arguments.count > index+1,
           let mode = AppearanceMode(rawValue:arguments[index+1]) { model.setAppearance(mode,persist:false) }
        buildPanel(); buildMenu()
        model.themeDidChange = { [weak self] in self?.applyTheme() }
        applyTheme()
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance,options:[.new]) { [weak self] app,_ in
            DispatchQueue.main.async {
                self?.model.systemIsDark = app.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
                self?.applyTheme()
            }
        }
        NotificationCenter.default.addObserver(self,selector:#selector(updatePowerMode),name:.NSProcessInfoPowerStateDidChange,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(flushForSleep),name:NSWorkspace.willSleepNotification,object:nil)
        model.store?.onPersistenceError = { [weak self] error in self?.model.errorMessage = "最新进度暂未写入磁盘：" + error.localizedDescription }
        model.configurePanel = { [weak self] in self?.configurePanel() }
        model.showManager = { [weak self] in self?.openManager() }
        model.hideWidget = { [weak self] in self?.panel.orderOut(nil) }
        if let api, !preview {
            api.didSync = { [weak self] in
                if let self, self.panel.isVisible || self.manager?.isVisible == true { self.model.refresh() }
                self?.model.lastSync = Date()
                self?.model.connection = "Chrome 已连接 · 播放进度自动保存"
            }
            server.onRequest = { request, respond in respond(api.handle(request)) }
            server.onState = { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.model.online = true; self.model.connection = "本机同步已开启，等待 Chrome 连接"
                case .failure(let error):
                    self.model.online = false
                    self.model.connection = "同步服务无法启动"
                    self.model.errorMessage = "本机端口被占用或不可用：\(error.localizedDescription)。请退出旧 Python 程序或其他实例，再重新打开。"
                    self.openManager()
                }
            }
            do { try server.start(port:serverPort()) }
            catch { model.errorMessage = error.localizedDescription; model.connection = "同步启动失败"; openManager() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector:#selector(showWidget), name:Notification.Name("local.biliwidget.show"), object:nil)
        showWidget()
        if model.errorMessage != nil { openManager() }
        if preview || ProcessInfo.processInfo.arguments.contains("--ui-smoke") {
            DispatchQueue.main.asyncAfter(deadline:.now()+1.5) { [weak self] in self?.smokeAndExport() }
        }
    }
    func buildPanel() {
        panel = FloatingPanel(contentRect: NSRect(x:0,y:0,width:354,height:430), styleMask:[.borderless,.resizable,.nonactivatingPanel], backing:.buffered, defer:false)
        panel.title = "课点 · Kedot"
        panel.minSize = WidgetLayout.minimum; panel.maxSize = WidgetLayout.maximum
        lastCompact = model.compact
        var size = CGSize(width:preferences.double(forKey:"widgetWidth"),height:preferences.double(forKey:"widgetHeight"))
        if size.width == 0 || size.height == 0 { size = CGSize(width:354,height:model.compact ? 350:430) }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of:"--size"),args.count>index+1 {
            let values = args[index+1].split(separator:"x").compactMap { Double($0) }
            if values.count==2 { size = CGSize(width:values[0],height:values[1]) }
        }
        size = WidgetLayout.bounded(size)
        panel.setContentSize(size)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true; panel.isMovable = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: WidgetView(model:model))
        hosting.sizingOptions = []
        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = container
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        // The drag region is a sibling of NSHostingView, outside SwiftUI hit testing.
        let drag = DragView()
        drag.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(drag)
        dragLeading = drag.leadingAnchor.constraint(equalTo:container.leadingAnchor,constant:10)
        dragTop = drag.topAnchor.constraint(equalTo:container.topAnchor,constant:10)
        dragWidth = drag.widthAnchor.constraint(equalToConstant:220)
        dragHeight = drag.heightAnchor.constraint(equalToConstant:74)
        NSLayoutConstraint.activate([dragLeading!,dragTop!,dragWidth!,dragHeight!])
        let resize = ResizeView(); resize.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(resize)
        NSLayoutConstraint.activate([
            resize.trailingAnchor.constraint(equalTo:container.trailingAnchor,constant:-8),
            resize.bottomAnchor.constraint(equalTo:container.bottomAnchor,constant:-8),
            resize.widthAnchor.constraint(equalToConstant:28),resize.heightAnchor.constraint(equalToConstant:28)
        ])
        configurePanel()
        if !preview, let position = preferences.string(forKey:"widgetOrigin") {
            panel.setFrameOrigin(NSPointFromString(position))
        } else if let screen = NSScreen.main {
            let bounds = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x:bounds.maxX-panel.frame.width-28,y:bounds.maxY-panel.frame.height-32))
        }
        clampPanel(); panel.delegate = self
    }
    func applyTheme() {
        let appearance = NSAppearance(named: model.palette.dark ? .darkAqua : .aqua)
        panel?.appearance = appearance
        manager?.appearance = appearance
    }
    func configurePanel() {
        guard panel != nil else { return }
        if lastCompact != model.compact {
            let difference = 80*WidgetLayout.scale(panel.frame.size,compact:lastCompact)
            let top = panel.frame.maxY
            let size = WidgetLayout.bounded(CGSize(width:panel.frame.width,height:panel.frame.height+(model.compact ? -difference:difference)))
            panel.setFrame(NSRect(x:panel.frame.minX,y:top-size.height,width:size.width,height:size.height),display:true)
            lastCompact = model.compact
        }
        panel.level = model.alwaysOnTop ? .floating:.normal
        updateDragRegion(); clampPanel()
    }
    func updateDragRegion() {
        let scale = WidgetLayout.scale(panel.frame.size,compact:model.compact)
        dragLeading?.constant = 10*scale; dragTop?.constant = 10*scale
        dragWidth?.constant = 220*scale; dragHeight?.constant = 74*scale
    }
    func windowDidResize(_ notification:Notification) {
        guard notification.object as? NSWindow === panel else { return }
        updateDragRegion(); geometrySave?.cancel()
        guard !preview else { return }
        let task = DispatchWorkItem { [weak self] in self?.saveGeometry() }
        geometrySave = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:task)
    }
    func saveGeometry() {
        preferences.set(panel.frame.width,forKey:"widgetWidth"); preferences.set(panel.frame.height,forKey:"widgetHeight")
        preferences.set(NSStringFromPoint(panel.frame.origin),forKey:"widgetOrigin")
    }
    func clampPanel() {
        guard panel != nil else { return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let frame = panel.frame
        let screen = screens.max { a,b in a.intersection(frame).width*a.intersection(frame).height < b.intersection(frame).width*b.intersection(frame).height } ?? NSRect(x:0,y:0,width:1440,height:900)
        let x = max(screen.minX,min(frame.minX,screen.maxX-frame.width))
        let y = max(screen.minY,min(frame.minY,screen.maxY-frame.height))
        restoring = true; panel.setFrameOrigin(NSPoint(x:x,y:y)); restoring = false
    }
    func windowDidMove(_ notification: Notification) {
        guard !restoring, !preview, notification.object as? NSWindow === panel else { return }
        preferences.set(NSStringFromPoint(panel.frame.origin),forKey:"widgetOrigin")
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { clampPanel() }
    func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName:"play.rectangle",accessibilityDescription:"课点")
        let menu = NSMenu()
        for (title,action) in [("显示悬浮窗",#selector(showWidget)),("管理课程与配对…",#selector(openManager)),("切换置顶",#selector(toggleTop)),("复制配对码",#selector(copyToken))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self; menu.addItem(entry)
        }
        let themes = NSMenu(title: "主题颜色")
        for theme in WidgetTheme.allCases {
            let entry = NSMenuItem(title: theme.name, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = theme.rawValue; themes.addItem(entry)
        }
        let themeMenu = NSMenuItem(title: "主题颜色", action: nil, keyEquivalent: ""); themeMenu.submenu = themes; menu.addItem(themeMenu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title:"退出 课点",action:#selector(quit),keyEquivalent:"q"); quit.target = self; menu.addItem(quit)
        item.menu = menu; statusItem = item
        let appMenu = NSMenu(); let root = NSMenuItem(); root.submenu = menu.copy() as? NSMenu; appMenu.addItem(root)
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; appMenu.addItem(editItem)
        NSApplication.shared.mainMenu = appMenu
    }
    @objc func showWidget() { if !preview { model.refresh() }; panel.orderFrontRegardless() }
    @objc func chooseTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let theme = WidgetTheme(rawValue: raw) { model.setTheme(theme) }
    }
    @objc func toggleTop() { model.toggleTop() }
    @objc func copyToken() { model.copyToken(); openManager() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    @objc func openManager() {
        if !preview { model.refresh() }
        if manager == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.appearance = NSAppearance(named: model.palette.dark ? .darkAqua : .aqua)
            window.title = "课点 · 课程与配对"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width:620,height:670)
            window.contentView = NSHostingView(rootView:ManagerView(model:model))
            window.center(); manager = window
        }
        NSApplication.shared.activate(ignoringOtherApps:true); manager?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { showWidget(); return true }
    @objc func updatePowerMode() { model.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    @objc func flushForSleep() { do { try model.store?.flush() } catch { model.errorMessage = error.localizedDescription } }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        do { try model.store?.flush(); return .terminateNow }
        catch {
            let alert = NSAlert(); alert.messageText = "最新进度无法保存"; alert.informativeText = error.localizedDescription
            alert.addButton(withTitle:"取消退出"); alert.addButton(withTitle:"仍然退出")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel:.terminateNow
        }
    }
    func applicationWillTerminate(_ notification: Notification) { geometrySave?.cancel(); if !preview { saveGeometry() }; server.stop() }
    func seedPreview() {
        // Demo records live only in memory and are never saved into the user's database.
        model.lessons = [
            Lesson(id:"https://www.bilibili.com/video/BV1234567890?p=12",video:Video(title:"高等数学 · 导数与微分",selected:true,seconds:1522,duration:2400,updated:2),course:Course(title:"高等数学 · 导数与微分",selected:true,currentPart:12,totalParts:60)),
            Lesson(id:"https://www.bilibili.com/video/BV1234567891?p=3",video:Video(title:"Python 入门 · 函数与参数",selected:true,seconds:480,duration:1800,updated:1),course:Course(title:"Python 入门 · 函数与参数",selected:true,currentPart:3,totalParts:24))
        ]
        model.online = true; model.lastSync = Date(); model.connection = "界面演示 · 非真实课程"
    }
    func smokeAndExport() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of:"--manager-snapshot"), args.count > index+1 {
            openManager()
            manager?.contentView?.layoutSubtreeIfNeeded()
            if let view = manager?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: args[index+1])) }
            }
        }
        if let index = args.firstIndex(of:"--snapshot"), args.count > index+1, let view = panel.contentView {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                if let png = bitmap.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:args[index+1])) }
            }
        }
        let oldTop = model.alwaysOnTop, oldCompact = model.compact
        model.toggleTop(); precondition(panel.level == (model.alwaysOnTop ? .floating : .normal))
        let previous = panel.frame.size
        model.toggleCompact()
        precondition(panel.frame.width == previous.width && panel.frame.height >= WidgetLayout.minimum.height)
        let testSize = WidgetLayout.bounded(CGSize(width:520,height:620))
        panel.setContentSize(testSize); updateDragRegion()
        precondition(WidgetLayout.scale(panel.frame.size,compact:model.compact) > 1)
        panel.setContentSize(previous)
        model.alwaysOnTop = oldTop; model.compact = oldCompact
        preferences.set(oldTop,forKey:"alwaysOnTop"); preferences.set(oldCompact,forKey:"compact"); lastCompact = oldCompact; configurePanel()
        openManager(); precondition(manager?.contentView != nil)
        print("PASS UI: panel, SwiftUI view, topmost, compact mode and manager window")
        fflush(stdout)
        NSApplication.shared.terminate(nil)
    }
}
func dataDirectory() -> URL {
    if let path = ProcessInfo.processInfo.environment["BILI_TRACKER_DATA_DIR"] { return URL(fileURLWithPath:path,isDirectory:true) }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bili_course_tracker",isDirectory:true)
}
func serverPort() -> UInt16 { UInt16(ProcessInfo.processInfo.environment["BILI_TRACKER_PORT"] ?? "8765") ?? 8765 }

let args = ProcessInfo.processInfo.arguments
if args.contains("--feature-checks") {
    guard ProcessInfo.processInfo.environment["BILI_TRACKER_PREFERENCES_SUITE"] != nil,
          ProcessInfo.processInfo.environment["BILI_TRACKER_DATA_DIR"] != nil else { exit(1) }
    MainActor.assumeIsolated {
        let model = WidgetModel(store:nil)
        model.setAppearance(.system); model.systemIsDark = false; precondition(!model.palette.dark)
        model.systemIsDark = true; precondition(model.palette.dark)
        model.setAppearance(.light); precondition(!model.palette.dark)
        model.systemIsDark = false; model.setAppearance(.dark); precondition(model.palette.dark)
        precondition(WidgetModel(store:nil).appearanceMode == .dark)
        let small = WidgetLayout.scale(CGSize(width:282,height:310),compact:false)
        let large = WidgetLayout.scale(CGSize(width:600,height:730),compact:false)
        precondition(large > small && small >= 0.78)
        precondition(WidgetLayout.bounded(CGSize(width:1,height:1)) == WidgetLayout.minimum)
        precondition(WidgetLayout.bounded(CGSize(width:9999,height:9999)) == WidgetLayout.maximum)
        var first = Lesson(id:"https://www.bilibili.com/video/BV1234567890", video:Video(seconds:10,duration:100), course:Course(selected:true))
        model.lessons = [first]
        precondition(model.selectedCount == 1 && model.selected.first?.video.seconds == 10)
        let countInvalidated = OSAllocatedUnfairLock(initialState:false)
        withObservationTracking { _ = model.selectedCount } onChange: { countInvalidated.withLock { $0 = true } }
        first = Lesson(id:first.id,video:Video(seconds:20,duration:100),course:first.course)
        model.lessons = [first]
        precondition(!countInvalidated.withLock { $0 } && model.selected.first?.video.seconds == 20)
        model.lessons = []
        precondition(countInvalidated.withLock { $0 } && model.selectedCount == 0 && model.selected.isEmpty)
        for value in [Double.nan, Double.infinity, -Double.infinity, -100, 0, 0.5, 100000] {
            let upper = ProgressInput.sliderUpperBound(value)
            let current = ProgressInput.sliderSeconds(value,duration:value)
            precondition(upper.isFinite && upper >= 1 && current.isFinite && current >= 0 && current <= upper)
            precondition((0...1).contains(ProgressInput.fraction(value)))
        }
        precondition(ProgressInput.sliderSeconds(120,duration:60) == 60)
        // A repeated read must not invalidate an otherwise unchanged lesson list.
        let refreshModel = WidgetModel(store:try! DiskStore(directory:dataDirectory()))
        let listInvalidated = OSAllocatedUnfairLock(initialState:false)
        withObservationTracking { _ = refreshModel.lessons } onChange: { listInvalidated.withLock { $0 = true } }
        refreshModel.refresh()
        precondition(!listInvalidated.withLock { $0 })
        print("PASS selection-count observation isolation, unchanged refresh and invalid slider draft bounds")
        print("PASS system light/dark following, explicit overrides, appearance persistence and adaptive scaling bounds")
    }
} else if args.contains("--theme-checks") {
    guard ProcessInfo.processInfo.environment["BILI_TRACKER_PREFERENCES_SUITE"] != nil else {
        fputs("Theme checks require an isolated BILI_TRACKER_PREFERENCES_SUITE.\n", stderr); exit(1)
    }
    MainActor.assumeIsolated {
        for theme in WidgetTheme.allCases {
            let model = WidgetModel(store: nil); model.setTheme(theme)
            precondition(WidgetModel(store: nil).theme == theme, "Theme did not persist")
            print("PASS saved theme: \(theme.rawValue)")
        }
        WidgetPreferences.defaults.set("obsolete-theme", forKey: "theme")
        precondition(WidgetModel(store: nil).theme == .mint, "Unknown theme should fall back safely")
        WidgetModel(store: nil).setTheme(.cream)
        WidgetPreferences.defaults.synchronize()
        print("PASS unknown theme fallback; stored cream for cross-process verification")
    }
} else if args.contains("--print-theme") {
    MainActor.assumeIsolated { print(WidgetModel(store: nil).theme.rawValue) }
} else if args.contains("--headless") {
    do {
        let store = try DiskStore(directory:dataDirectory())
        let api = TrackerAPI(store:store,port:serverPort())
        let server = LocalServer()
        server.onRequest = { request, respond in respond(api.handle(request)) }
        server.onState = { result in
            switch result {
            case .success: print("READY \(serverPort())"); fflush(stdout)
            case .failure(let error): fputs("Server failure: \(error)\n",stderr); exit(1)
            }
        }
        try server.start(port:serverPort())
        withExtendedLifetime((store,api,server)) { RunLoop.main.run() }
    } catch { fputs("Startup failure: \(error.localizedDescription)\n",stderr); exit(1) }
} else {
    let app = NSApplication.shared
    if !args.contains("--preview"), !args.contains("--ui-smoke"), let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier:id).contains(where: { $0.processIdentifier != getpid() }) {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.biliwidget.show"),object:nil,userInfo:nil,deliverImmediately:true)
        exit(0)
    }
    MainActor.assumeIsolated {
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
