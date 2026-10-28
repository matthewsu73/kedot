import SwiftUI
import TrackerCore

struct WidgetView: View {
    let model: WidgetModel
    var body: some View {
        GeometryReader { proxy in
            let scale = WidgetLayout.scale(proxy.size, compact:model.compact)
            WidgetContent(model:model)
                .frame(width:proxy.size.width/scale,height:proxy.size.height/scale)
                .scaleEffect(scale,anchor:.topLeading)
        }
    }
}
struct WidgetContent: View {
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"play.rectangle.fill").font(.system(size:19,weight:.semibold))
                    .foregroundStyle(theme.accent).frame(width:38,height:38)
                    .background(theme.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:3) {
                    Text("我的网课").font(.system(size:17,weight:.semibold))
                    Text("COURSE PROGRESS").font(.system(size:8,weight:.medium,design:.monospaced)).tracking(1.8).foregroundStyle(theme.faint)
                }
                Spacer(minLength:0)
                Button(action:model.toggleTop) {
                    Image(systemName:model.alwaysOnTop ? "pin.fill":"pin.slash").font(.system(size:12))
                        .foregroundStyle(model.alwaysOnTop ? theme.accent:theme.muted).frame(width:28,height:28)
                }.buttonStyle(.plain).help("切换置顶").accessibilityLabel("切换置顶")
                Menu {
                    Button("管理课程…") { model.showManager?() }
                    Menu("主题颜色") {
                        ForEach(WidgetTheme.allCases) { value in
                            Button { model.setTheme(value) } label: {
                                if model.theme == value { Label(value.name,systemImage:"checkmark") } else { Text(value.name) }
                            }
                        }
                    }
                    Menu("深浅色模式") {
                        ForEach(AppearanceMode.allCases) { value in
                            Button { model.setAppearance(value) } label: {
                                if model.appearanceMode == value { Label(value.name,systemImage:"checkmark") } else { Text(value.name) }
                            }
                        }
                    }
                    Button("复制配对码",action:model.copyToken)
                    Button(model.compact ? "展开卡片":"紧凑模式",action:model.toggleCompact)
                    Divider()
                    Button("隐藏悬浮窗") { model.hideWidget?() }
                    Button("退出程序") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName:"ellipsis").font(.system(size:15,weight:.bold)).frame(width:24,height:28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多操作")
            }.padding(.horizontal,20).padding(.top,19).padding(.bottom,17)
            Rectangle().fill(theme.border).frame(height:1).padding(.horizontal,20)
            if model.selected.isEmpty {
                VStack(spacing:12) {
                    Image(systemName:"rectangle.stack.badge.plus").font(.system(size:29,weight:.light)).foregroundStyle(theme.accent)
                    Text("把想学的课程放在这里").font(.system(size:14,weight:.medium))
                    Text("连接 Chrome，在发现的视频中\n选择你要追踪的课程。")
                        .font(.system(size:12)).foregroundStyle(theme.muted).multilineTextAlignment(.center).lineSpacing(5)
                    Button("选择课程") { model.showManager?() }.buttonStyle(.plain)
                        .font(.system(size:12,weight:.semibold)).foregroundStyle(theme.background)
                        .padding(.horizontal,18).padding(.vertical,9).background(theme.accent,in:Capsule())
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing:12) {
                        ForEach(model.selected) { lesson in
                            LessonCard(lesson:lesson,theme:theme,open:{model.open(lesson)},edit:{model.edit(lesson)},resume:{model.resume(lesson)})
                        }
                    }.padding(16)
                }.scrollIndicators(.hidden).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            HStack(spacing:6) {
                Circle().fill(model.online ? theme.accent:Color.orange).frame(width:5,height:5)
                Text(model.online ? (model.lastSync == nil ? "等待 Chrome 同步":"已连接 · 自动保存") : model.connection)
                    .font(.system(size:10)).foregroundStyle(theme.muted).lineLimit(1)
                Spacer()
                Text("\(model.selected.count) 门课程").font(.system(size:10,design:.monospaced)).foregroundStyle(theme.faint)
                Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:9)).foregroundStyle(theme.faint)
                    .accessibilityHidden(true)
            }.padding(.horizontal,20).padding(.bottom,17).padding(.top,2)
        }
        .foregroundStyle(theme.foreground)
        .background {
            if model.lowPower { RoundedRectangle(cornerRadius:25,style:.continuous).fill(theme.background) }
            else {
                RoundedRectangle(cornerRadius:25,style:.continuous).fill(.ultraThinMaterial)
                    .overlay { RoundedRectangle(cornerRadius:25).fill(theme.background.opacity(0.95)) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:25,style:.continuous))
        .overlay { RoundedRectangle(cornerRadius:25).strokeBorder(theme.border,lineWidth:1) }
        .padding(10).environment(\.colorScheme,theme.colorScheme)
    }
}
struct ProgressTrack: View {
    let value: Double
    let theme: ThemePalette
    var body: some View {
        GeometryReader { g in
            ZStack(alignment:.leading) {
                Capsule().fill(theme.border)
                Capsule().fill(theme.accent).frame(width:g.size.width*max(0,min(1,value)))
            }
        }.frame(height:4).accessibilityLabel("课程位置进度").accessibilityValue("\(Int(value*100))%")
    }
}
struct LessonCard: View {
    let lesson: Lesson
    let theme: ThemePalette
    let open: () -> Void
    let edit: () -> Void
    let resume: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top,spacing:8) {
                Button(action:open) {
                    Text(lesson.title).font(.system(size:12,weight:.semibold)).lineLimit(2)
                        .multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
                }.buttonStyle(.plain).help("打开当前分 P")
                Button(action:edit) {
                    Image(systemName:"slider.horizontal.3").font(.system(size:12)).foregroundStyle(theme.muted).frame(width:24,height:22)
                }.buttonStyle(.plain).help("手动调整进度").accessibilityLabel("调整"+lesson.title+"的进度")
            }
            HStack {
                Text(lesson.totalText).font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(theme.accent)
                Spacer(minLength:0)
                if lesson.course.manualProgress { Image(systemName:"hand.raised.fill").font(.system(size:9)).foregroundStyle(theme.accent).help("手动记录，自动覆盖已暂停") }
            }
            if let position = lesson.course.positionFraction(video:lesson.video) {
                ProgressTrack(value:position,theme:theme)
                HStack {
                    Text("课程位置 \(Int(position*100))%")
                    Spacer()
                    Text(lesson.course.manualProgress ? "手动记录":"自动同步")
                }.font(.system(size:9)).foregroundStyle(theme.faint)
            }
            HStack {
                Text(lesson.video.duration > 0 ? "本集 \(formattedTime(lesson.video.seconds)) / \(formattedTime(lesson.video.duration))":"本集尚无播放进度")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(theme.muted)
                Spacer()
                Text(lesson.video.duration > 0 ? "\(Int(lesson.video.fraction*100))%":"—")
                    .font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(theme.accent)
            }
        }.padding(13).background(theme.card,in:RoundedRectangle(cornerRadius:15))
            .overlay { RoundedRectangle(cornerRadius:15).strokeBorder(theme.accent.opacity(hovered ? 0.38:0.07),lineWidth:1) }
            .onHover { hovered = $0 }.animation(reduceMotion ? nil:.easeOut(duration:0.16),value:hovered)
            .contextMenu {
                Button("调整进度",action:edit)
                if lesson.course.manualProgress { Button("恢复自动同步",action:resume) }
                Button("打开当前分 P",action:open)
            }
    }
}
struct ManagerView: View {
    let model: WidgetModel
    @State private var search = ""
    @State private var onlySelected = false
    private var filtered: [Lesson] {
        model.lessons.filter { (!onlySelected || $0.course.selected) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.id.contains(search)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("管理你的网课").font(.title2.bold())
                    Text("选择的课程会出现在桌面悬浮窗中；同一视频的分 P 合并为一门课程。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.selected.count) 已选").foregroundStyle(.secondary)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.connection, systemImage: model.online ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.online ? .green : .orange)
                    Text("首次使用：加载 Chrome 扩展 → 复制配对码 → 在扩展选项页粘贴并同步 → 刷新 B站视频页。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("显示扩展文件夹", action: model.revealExtension)
                        Button("复制配对码", action: model.copyToken).disabled(model.store == nil)
                        Spacer()
                        Button("打开数据目录", action: model.revealData)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("外观主题") {
                VStack(spacing: 8) {
                    Picker("外观模式", selection: Binding(get:{ model.appearanceMode },set:{ model.setAppearance($0) })) {
                        ForEach(AppearanceMode.allCases) { Text($0.name).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 330)
                    HStack(spacing: 8) {
                    ForEach(WidgetTheme.allCases) { value in
                        ThemeSwatch(theme: value, dark: model.palette.dark, selected: model.theme == value) { model.setTheme(value) }
                    }
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            HStack {
                TextField("搜索课程标题或视频地址", text: $search).textFieldStyle(.roundedBorder)
                Toggle("仅已选", isOn: $onlySelected).toggleStyle(.checkbox)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(model.lessons.isEmpty ? "还没有发现视频" : "没有匹配的课程").font(.headline)
                    Text("配对成功后可导入 Chrome 历史；播放视频后才会有进度。")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { lesson in
                    HStack(spacing: 12) {
                        Button { model.select(lesson) } label: {
                            Image(systemName: lesson.course.selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22)).foregroundStyle(lesson.course.selected ? model.palette.accent : Color.secondary)
                        }.buttonStyle(.plain).accessibilityLabel(lesson.course.selected ? "移除课程" : "加入课程")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(lesson.title).lineLimit(2)
                            Text("\(lesson.totalText) · " + (lesson.video.duration > 0 ? "\(formattedTime(lesson.video.seconds)) / \(formattedTime(lesson.video.duration))" : "尚无播放进度"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lesson.course.manualProgress { Button("恢复自动") { model.resume(lesson) } }
                        Button("调整进度") { model.edit(lesson) }
                        Button("打开") { model.open(lesson) }
                    }.padding(.vertical, 5)
                }.listStyle(.inset)
            }
            Text("本机保存 · 不读取 B站账号密码 · 播放时约每 2 秒同步 · 暂停立即保存").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(minWidth: 600, minHeight: 620)
        .background(model.palette.background).foregroundStyle(model.palette.foreground)
        .tint(model.palette.accent).preferredColorScheme(model.palette.colorScheme)
        .sheet(item:Binding(get:{ model.editing },set:{ model.editing = $0 })) { lesson in
            ProgressEditor(model:model, lesson:lesson)
        }
        .alert("提示", isPresented: Binding(get: { model.feedback != nil }, set: { if !$0 { model.feedback = nil } })) {
            Button("好") { model.feedback = nil }
        } message: { Text(model.feedback ?? "") }
    }
}

struct ThemeSwatch: View {
    let theme: WidgetTheme
    let dark: Bool
    let selected: Bool
    private var colors: ThemePalette { ThemePalette(theme:theme,dark:dark) }
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(colors.background)
                    HStack(spacing: 3) {
                        Capsule().fill(colors.accent).frame(width: 16, height: 4)
                        Capsule().fill(colors.foreground.opacity(0.12)).frame(width: 8, height: 4)
                    }
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.background, colors.accent).offset(x: 19, y: -12)
                    }
                }.frame(width: 56, height: 38)
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? colors.accent : Color.secondary.opacity(0.18), lineWidth: selected ? 2 : 1) }
                Text(theme.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }.padding(.horizontal, 7).padding(.vertical, 4)
        }.buttonStyle(.plain).help("切换为" + theme.name)
            .accessibilityLabel(theme.name + "主题").accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct ProgressEditor: View {
    let model: WidgetModel
    let lesson: Lesson
    @State private var page: Int
    @State private var total: String
    @State private var seconds: Double
    @State private var duration: Double
    @State private var error: String?
    init(model: WidgetModel, lesson: Lesson) {
        self.model = model; self.lesson = lesson
        _page = State(initialValue:lesson.course.currentPart)
        _total = State(initialValue:lesson.course.totalParts.map(String.init) ?? "")
        _seconds = State(initialValue:lesson.video.seconds); _duration = State(initialValue:lesson.video.duration)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("调整观看进度").font(.title2.bold())
            Text(lesson.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Form {
                Stepper("目前看到 P\(page)",value:$page,in:1...100000)
                TextField("总集数（未知可留空）",text:$total)
                TextField("本集时长（秒）",value:$duration,format:.number.precision(.fractionLength(0...1)))
                TextField("本集已看到（秒）",value:$seconds,format:.number.precision(.fractionLength(0...1)))
                Slider(value:$seconds,in:0...max(1,duration)).disabled(duration<=0).accessibilityLabel("本集观看进度")
                Text("\(formattedTime(seconds)) / \(formattedTime(duration))").font(.caption.monospacedDigit())
            }.textFieldStyle(.roundedBorder)
            Text("保存后暂停这门课的自动覆盖。需要继续跟随播放器时，点击“恢复自动同步”。本操作只修改桌面记录，不会跳转浏览器播放头。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if lesson.course.manualProgress { Button("恢复自动同步") { model.resume(lesson); model.editing = nil } }
                Spacer()
                Button("取消") { model.editing = nil }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:440).tint(model.palette.accent)
            .preferredColorScheme(model.palette.colorScheme)
            .onChange(of:page) { _,value in
                let known = model.store?.database.videos[partURL(lesson.id,value)]
                seconds = known?.seconds ?? 0
                duration = known?.duration ?? lesson.course.parts.first(where:{$0.page==value})?.duration ?? 0
            }
    }
    private func save() {
        let text = total.trimmingCharacters(in:.whitespacesAndNewlines)
        let count = text.isEmpty ? nil:Int(text)
        if !text.isEmpty && count == nil { error = "总集数请输入整数。"; return }
        do { try model.saveProgress(lesson,page:page,total:count,seconds:seconds,duration:duration) }
        catch { self.error = error.localizedDescription }
    }
}
