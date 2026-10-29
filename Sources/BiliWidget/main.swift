import AppKit
import SwiftUI
import TrackerCore
import Observation
import os

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
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
        model.hideWidget = { [weak self] in self?.panel.performClose(nil) }
        model.resetWindow = { [weak self] in self?.resetWindow() }
        model.centerWindow = { [weak self] in self?.centerWindow() }
        model.resizeWindow = { [weak self] size in self?.resizeWindow(size) }
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
        panel = FloatingPanel(contentRect: NSRect(x:0,y:0,width:354,height:430), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        panel.title = "课点 2.3 · 正式版"
        panel.contentMinSize = WidgetLayout.minimum; panel.contentMaxSize = WidgetLayout.maximum
        panel.tabbingMode = .disallowed
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
        panel.isOpaque = true; panel.backgroundColor = NSColor(model.palette.background)
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
        panel?.backgroundColor = NSColor(model.palette.background)
        manager?.appearance = appearance
    }
    func configurePanel() {
        guard panel != nil else { return }
        if lastCompact != model.compact {
            let content = panel.contentRect(forFrameRect:panel.frame).size
            let difference = 80*WidgetLayout.scale(content,compact:lastCompact)
            resizeWindow(CGSize(width:content.width,height:content.height+(model.compact ? -difference:difference)))
            lastCompact = model.compact
        }
        panel.level = model.alwaysOnTop ? .floating:.normal
        clampPanel()
    }
    func scheduleGeometrySave() {
        guard !preview else { return }
        geometrySave?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveGeometry() }
        geometrySave=task; DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:task)
    }
    func windowDidResize(_ notification:Notification) {
        guard notification.object as? NSWindow === panel else { return }
        scheduleGeometrySave()
    }
    func windowDidEndLiveResize(_ notification:Notification) {
        guard notification.object as? NSWindow === panel else { return }
        clampPanel(); if !preview { saveGeometry() }
    }
    func resizeWindow(_ requested: CGSize) {
        guard panel != nil else { return }
        let size=WidgetLayout.bounded(requested)
        let frameSize=panel.frameRect(forContentRect:NSRect(origin:.zero,size:size)).size
        panel.setFrame(NSRect(x:panel.frame.minX,y:panel.frame.maxY-frameSize.height,width:frameSize.width,height:frameSize.height),display:true)
        clampPanel(); scheduleGeometrySave()
    }
    @objc func resetWindow() { resizeWindow(CGSize(width:354,height:model.compact ? 350:430)); centerWindow() }
    @objc func centerWindow() {
        guard panel != nil else { return }
        let screen=panel.screen ?? NSScreen.main
        if let bounds=screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x:bounds.midX-panel.frame.width/2,y:bounds.midY-panel.frame.height/2))
        }
        clampPanel(); scheduleGeometrySave()
    }
    func windowWillUseStandardFrame(_ window:NSWindow,defaultFrame:NSRect) -> NSRect {
        guard window === panel else { return defaultFrame }
        let size=panel.frameRect(forContentRect:NSRect(origin:.zero,size:CGSize(width:520,height:620))).size
        return WindowPlacement.clamp(NSRect(x:window.frame.minX,y:window.frame.maxY-size.height,width:size.width,height:size.height),screens:NSScreen.screens.map(\.visibleFrame))
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool {
        guard sender === panel else { return true }
        do { try model.store?.flush() }
        catch { model.errorMessage="无法保存最新进度："+error.localizedDescription; openManager(); return false }
        if !preview { saveGeometry() }
        panel.orderOut(nil)
        return false
    }
    func saveGeometry() {
        let size=panel.contentRect(forFrameRect:panel.frame).size
        preferences.set(size.width,forKey:"widgetWidth"); preferences.set(size.height,forKey:"widgetHeight")
        preferences.set(NSStringFromPoint(panel.frame.origin),forKey:"widgetOrigin")
    }
    func clampPanel() {
        guard panel != nil else { return }
        let frame=WindowPlacement.clamp(panel.frame,screens:NSScreen.screens.map(\.visibleFrame))
        restoring=true; panel.setFrame(frame,display:true); restoring=false
    }
    func windowDidMove(_ notification: Notification) {
        guard !restoring, notification.object as? NSWindow === panel else { return }
        scheduleGeometrySave()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) { clampPanel() }
    func buildMenu() {
        let item=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image=NSImage(systemSymbolName:"play.rectangle",accessibilityDescription:"课点")
        let menu=NSMenu(); menu.delegate=self
        func entry(_ title:String,_ action:Selector,_ key:String="") -> NSMenuItem {
            let value=NSMenuItem(title:title,action:action,keyEquivalent:key); value.target=self; return value
        }
        menu.addItem(entry("显示悬浮窗",#selector(toggleWidget)))
        menu.addItem(entry("课程管理…",#selector(openCourses),"1"))
        menu.addItem(entry("学习统计…",#selector(openStatistics),"2"))
        menu.addItem(entry("设置…",#selector(openSettings),","))
        menu.addItem(.separator())
        menu.addItem(entry("恢复默认窗口",#selector(resetWindow)))
        menu.addItem(entry("退出课点",#selector(quit),"q"))
        item.menu=menu; statusItem=item
        let main=NSMenu()
        let appItem=NSMenuItem(title:"课点",action:nil,keyEquivalent:"")
        let appMenu=NSMenu()
        appMenu.addItem(entry("设置…",#selector(openSettings),","))
        appMenu.addItem(.separator()); appMenu.addItem(entry("退出课点",#selector(quit),"q"))
        appItem.submenu=appMenu; main.addItem(appItem)
        let edit=NSMenu(title:"编辑")
        for (title,action,key) in [("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:Selector(action),keyEquivalent:key))
        }
        let editItem=NSMenuItem(title:"编辑",action:nil,keyEquivalent:""); editItem.submenu=edit; main.addItem(editItem)
        let windows=NSMenu(title:"窗口")
        let close=NSMenuItem(title:"关闭当前窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"); windows.addItem(close)
        windows.addItem(entry("显示悬浮窗",#selector(showWidget)))
        windows.addItem(entry("课程管理…",#selector(openCourses),"1"))
        windows.addItem(entry("学习统计…",#selector(openStatistics),"2"))
        windows.addItem(entry("恢复默认窗口",#selector(resetWindow)))
        let windowItem=NSMenuItem(title:"窗口",action:nil,keyEquivalent:""); windowItem.submenu=windows; main.addItem(windowItem)
        NSApplication.shared.mainMenu=main
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.items.first?.title = panel.isVisible && !panel.isMiniaturized ? "收起悬浮窗" : "显示悬浮窗"
    }
    @objc func toggleWidget() {
        if panel.isVisible && !panel.isMiniaturized { panel.performClose(nil) } else { showWidget() }
    }
    @objc func openCourses() { model.managerSection = .courses; openManager() }
    @objc func openStatistics() { model.managerSection = .statistics; openManager() }
    @objc func openSettings() { model.managerSection = .settings; openManager() }
    @objc func showWidget() { if !preview { model.refresh() }; if panel.isMiniaturized { panel.deminiaturize(nil) }; clampPanel(); panel.orderFrontRegardless() }
    @objc func chooseTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let theme = WidgetTheme(rawValue: raw) { model.setTheme(theme) }
    }
    @objc func toggleTop() { model.toggleTop() }
    @objc func copyToken() { model.copyToken(); openSettings() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    @objc func openManager() {
        if !preview { model.refresh() }
        if manager == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:740,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.appearance = NSAppearance(named: model.palette.dark ? .darkAqua : .aqua)
            window.title = "课点 2.3 · 控制中心"; window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width:700,height:690)
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
        var demo=Database()
        for lesson in model.lessons {
            demo.courses[lesson.id]=lesson.course; demo.videos[lesson.url]=lesson.video
            demo.courses[lesson.id]?.parts=(1...min(60,lesson.course.totalParts ?? 1)).map { PartInfo(page:$0,title:"第\($0)集",duration:2400) }
            for page in 1...3 { demo.finished.insert(partURL(lesson.id,page)) }
        }
        if let first=model.lessons.first {
            demo.notes=[StudyNote(course:first.id,page:12,seconds:515,text:"链式求导法则：先求外层，再乘以内层导数。")]
            for offset in -13...0 {
                let date=Calendar.current.date(byAdding:.day,value:offset,to:Date())!
                demo.studyDays[StudyRecorder.dayKey(date)]=[first.id:Double(abs(offset)%4+1)*420]
            }
        }
        model.library=demo
        model.online = true; model.lastSync = Date(); model.connection = "界面演示 · 非真实课程"
    }
    func exportLearningView<Content: View>(_ view: Content, size: NSSize, path: URL) {
        let host=NSHostingView(rootView:view)
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.appearance=NSAppearance(named:model.palette.dark ? .darkAqua : .aqua)
        window.contentView=host
        window.orderFrontRegardless()
        RunLoop.main.run(until:Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let png=bitmap.representation(using:.png,properties:[:]) { try? png.write(to:path) }
        }
        window.orderOut(nil)

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
        if let index=args.firstIndex(of:"--learning-snapshots"), args.count>index+1, let lesson=model.lessons.first {
            let directory=URL(fileURLWithPath:args[index+1],isDirectory:true)
            try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            exportLearningView(CourseDetailsView(model:model,lesson:lesson),size:NSSize(width:680,height:560),path:directory.appendingPathComponent("parts.png"))
            exportLearningView(CourseDetailsView(model:model,lesson:lesson,initialSection:1),size:NSSize(width:680,height:560),path:directory.appendingPathComponent("notes.png"))
            exportLearningView(LearningStatsView(model:model),size:NSSize(width:660,height:610),path:directory.appendingPathComponent("statistics.png"))
            if let note=model.library.notes.first { exportLearningView(NoteEditor(model:model,note:note),size:NSSize(width:544,height:390),path:directory.appendingPathComponent("note-editor.png")) }
        }
        if let index=args.firstIndex(of:"--learning-snapshots"),args.count>index+1 {
            let directory=URL(fileURLWithPath:args[index+1],isDirectory:true)
            for section in ManagerSection.allCases {
                model.managerSection=section
                exportLearningView(ManagerView(model:model),size:NSSize(width:740,height:740),path:directory.appendingPathComponent("center-"+section.rawValue+".png"))
            }
        }
        let oldTop = model.alwaysOnTop, oldCompact = model.compact
        model.toggleTop(); precondition(panel.level == (model.alwaysOnTop ? .floating : .normal))
        let previous = panel.contentRect(forFrameRect:panel.frame).size
        model.toggleCompact()
        precondition(panel.frame.width == previous.width && panel.frame.height >= WidgetLayout.minimum.height)
        let testSize = WidgetLayout.bounded(CGSize(width:520,height:620))
        panel.setContentSize(testSize)
        precondition(WidgetLayout.scale(panel.frame.size,compact:model.compact) > 1)
        panel.setContentSize(previous)
        model.alwaysOnTop = oldTop; model.compact = oldCompact
        preferences.set(oldTop,forKey:"alwaysOnTop"); preferences.set(oldCompact,forKey:"compact"); lastCompact = oldCompact; configurePanel()
        openManager(); precondition(manager?.contentView != nil)
        panel.performClose(nil); precondition(!panel.isVisible)
        showWidget(); precondition(panel.isVisible)
        resetWindow(); precondition(abs(panel.contentRect(forFrameRect:panel.frame).width-354) < 1)
        print("PASS UI: native panel, resize, topmost, compact, hide/restore, reset and control center")
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
        let originalFontScale=model.fontScale
        model.setFontScale(1.25); precondition(model.fontScale == 1.25 && WidgetModel(store:nil).fontScale == 1.25)
        model.setFontScale(99); precondition(model.fontScale == 1.4)
        model.setFontScale(-1); precondition(model.fontScale == 0.8)
        model.setFontScale(.nan); precondition(model.fontScale == 1)
        model.setFontScale(originalFontScale)
        print("PASS widget font scale persistence, reset and safe bounds")
        let small = WidgetLayout.scale(CGSize(width:282,height:310),compact:false)
        let large = WidgetLayout.scale(CGSize(width:600,height:730),compact:false)
        precondition(large > small && small >= 0.78)
        let screens=[CGRect(x:-1440,y:0,width:1440,height:900),CGRect(x:0,y:0,width:1512,height:940)]
        precondition(WindowPlacement.clamp(CGRect(x:-1400,y:100,width:354,height:430),screens:screens).minX == -1400)
        precondition(WindowPlacement.clamp(CGRect(x:9999,y:9999,width:354,height:430),screens:screens).maxX <= 1512)
        precondition(WindowPlacement.clamp(CGRect(x:0,y:0,width:9999,height:9999),screens:screens).width <= 1512)
        precondition(WindowPlacement.clamp(CGRect(x:CGFloat.nan,y:0,width:354,height:430),screens:screens).minX.isFinite)
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
