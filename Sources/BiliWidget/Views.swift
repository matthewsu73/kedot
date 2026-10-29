import SwiftUI
import TrackerCore

private struct WidgetFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
extension EnvironmentValues {
    var widgetFontScale: CGFloat {
        get { self[WidgetFontScaleKey.self] }
        set { self[WidgetFontScaleKey.self] = newValue }
    }
}

struct WidgetView: View {
    let model: WidgetModel
    var body: some View {
        GeometryReader { proxy in
            let scale = WidgetLayout.scale(proxy.size, compact:model.compact)
            WidgetContent(model:model)
                .environment(\.widgetFontScale,CGFloat(model.fontScale))
                .frame(width:proxy.size.width/scale,height:proxy.size.height/scale)
                .scaleEffect(scale,anchor:.topLeading)
        }
    }
}
struct WidgetContent: View {
    let model: WidgetModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var theme: ThemePalette { model.palette }
    var body: some View {
        VStack(spacing:0) {
            WidgetHeader(model:model)
            Rectangle().fill(theme.border).frame(height:1).padding(.horizontal,20)
            SelectedCourses(model:model)
            WidgetStatus(model:model)
        }
        .foregroundStyle(theme.foreground)
        .background {
            if model.lowPower || reduceTransparency { RoundedRectangle(cornerRadius:25,style:.continuous).fill(theme.background) }
            else {
                RoundedRectangle(cornerRadius:25,style:.continuous).fill(.ultraThinMaterial)
                    .overlay { RoundedRectangle(cornerRadius:25).fill(theme.background.opacity(0.95)) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:25,style:.continuous))
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
                Capsule().fill(theme.accent).frame(width:g.size.width*ProgressInput.fraction(value))
            }
        }.frame(height:4).accessibilityElement(children:.ignore).accessibilityLabel("课程位置进度").accessibilityValue("\(Int(ProgressInput.fraction(value)*100))%")
    }
}
struct LessonCard: View {
    @Environment(\.widgetFontScale) private var fontScale
    let lesson: Lesson
    let theme: ThemePalette
    let open: () -> Void
    let edit: () -> Void
    let resume: () -> Void
    let inspect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top,spacing:8) {
                Button(action:open) {
                    Text(lesson.title).font(.system(size:14*fontScale,weight:.semibold)).lineLimit(2)
                        .multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
                }.buttonStyle(.plain).help("打开当前分 P").accessibilityLabel("打开"+lesson.title).accessibilityHint("在浏览器打开当前分集")
                Button(action:edit) {
                    Image(systemName:"slider.horizontal.3").font(.system(size:12*fontScale)).foregroundStyle(theme.muted).frame(width:24,height:22)
                }.buttonStyle(.plain).help("手动调整进度").accessibilityLabel("调整"+lesson.title+"的进度")
            }
            HStack {
                Text(lesson.totalText).font(.system(size:13*fontScale,weight:.semibold,design:.rounded)).foregroundStyle(theme.accent)
                Spacer(minLength:0)
                if lesson.course.manualProgress { Image(systemName:"hand.raised.fill").font(.system(size:11*fontScale)).foregroundStyle(theme.accent).help("手动记录，自动覆盖已暂停").accessibilityLabel("手动记录，自动覆盖已暂停") }
            }
            if let position = lesson.course.positionFraction(video:lesson.video) {
                ProgressTrack(value:position,theme:theme)
                HStack {
                    Text("课程位置 \(Int(position*100))%")
                    Spacer()
                    Text(lesson.course.manualProgress ? "手动记录":"自动同步")
                }.font(.system(size:11*fontScale)).foregroundStyle(theme.faint)
            }
            Button("分集与笔记", action:inspect).buttonStyle(.plain).font(.system(size:12*fontScale,weight:.medium)).foregroundStyle(theme.accent)
            HStack {
                Text(lesson.video.duration > 0 ? "本集 \(formattedTime(lesson.video.seconds)) / \(formattedTime(lesson.video.duration))":"本集尚无播放进度")
                    .font(.system(size:12*fontScale,design:.monospaced)).foregroundStyle(theme.muted)
                Spacer()
                Text(lesson.video.duration > 0 ? "\(Int(lesson.video.fraction*100))%":"—")
                    .font(.system(size:13*fontScale,weight:.semibold,design:.rounded)).foregroundStyle(theme.accent)
            }
        }.padding(13).background(theme.card,in:RoundedRectangle(cornerRadius:15))
            .overlay { RoundedRectangle(cornerRadius:15).strokeBorder(theme.accent.opacity(hovered ? 0.38:0.07),lineWidth:1) }
            .onHover { hovered = $0 }.animation(reduceMotion ? nil:.easeOut(duration:0.16),value:hovered)
            .contextMenu {
                Button("分集与笔记",action:inspect)
                Button("调整进度",action:edit)
                if lesson.course.manualProgress { Button("恢复自动同步",action:resume) }
                Button("打开当前分 P",action:open)
            }
    }
}
struct ManagerView: View {
    let model: WidgetModel
    var body: some View {
        @Bindable var model=model
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("课点控制中心").font(.title2.bold())
                Text("2.3.0 · 正式版").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.selectedCount) 门已选").font(.callout).foregroundStyle(.secondary)
            }
            Picker("导航",selection:$model.managerSection) {
                ForEach(ManagerSection.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            switch model.managerSection {
            case .courses:
                CourseBrowser(model:model)
                Text("勾选课程显示在桌面；分集、笔记和进度操作集中在对应课程中。")
                    .font(.caption).foregroundStyle(.secondary)
            case .statistics:
                LearningStatsView(model:model,embedded:true)
            case .settings:
                WidgetSettingsView(model:model)
            }
        }.padding(20).frame(minWidth:700,minHeight:690)
        .background(model.palette.background).foregroundStyle(model.palette.foreground)
        .tint(model.palette.accent).preferredColorScheme(model.palette.colorScheme)
        .sheet(item:Binding(get:{ model.editing },set:{ model.editing=$0 })) { lesson in
            ProgressEditor(model:model,lesson:lesson)
        }
        .sheet(item:Binding(get:{ model.detail },set:{ model.detail=$0 })) { lesson in
            CourseDetailsView(model:model,lesson:lesson)
        }
        .alert("提示",isPresented:Binding(get:{model.feedback != nil},set:{if !$0 {model.feedback=nil}})) {
            Button("好") { model.feedback=nil }
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
            .accessibilityLabel(theme.name + "主题").accessibilityValue(selected ? "已选择" : "未选择").accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
