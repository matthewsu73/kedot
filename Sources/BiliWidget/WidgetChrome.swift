import SwiftUI

// Keep connection ticks, header preferences, and playback list updates in separate
// observation boundaries. The chrome does not read the live lesson array.
struct WidgetHeader: View {
    @Environment(\.widgetFontScale) private var fontScale
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
            HStack(spacing:10) {
                Image(systemName:"play.rectangle.fill").accessibilityHidden(true).font(.system(size:19*fontScale,weight:.semibold))
                    .foregroundStyle(theme.accent).frame(width:38,height:38)
                    .background(theme.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:3) {
                    Text("我的网课").font(.system(size:19*fontScale,weight:.semibold))
                    Text("2.3 · 正式版").font(.system(size:9*fontScale,weight:.medium,design:.monospaced)).tracking(0.8).foregroundStyle(theme.faint)
                }
                Spacer(minLength:0)
                Button(action:model.toggleTop) {
                    Image(systemName:model.alwaysOnTop ? "pin.fill":"pin.slash").font(.system(size:12*fontScale))
                        .foregroundStyle(model.alwaysOnTop ? theme.accent:theme.muted).frame(width:30,height:30)
                }.buttonStyle(.plain).help("切换置顶").accessibilityLabel("切换置顶").accessibilityValue(model.alwaysOnTop ? "已置顶" : "未置顶")
                Menu {
                    Button("课程管理…") { model.openCenter(.courses) }
                    Button("学习统计…") { model.openCenter(.statistics) }
                    Button("设置…") { model.openCenter(.settings) }
                    Divider()
                    Button("恢复默认窗口") { model.resetWindow?() }
                } label: { Image(systemName:"ellipsis").font(.system(size:15*fontScale,weight:.bold)).frame(width:30,height:30) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("课程、统计与设置").accessibilityLabel("课程、统计与设置")

            }.padding(.horizontal,20).padding(.top,19).padding(.bottom,17)
    }
}
struct WidgetStatus: View {
    @Environment(\.widgetFontScale) private var fontScale
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
            HStack(spacing:6) {
                Circle().fill(model.online ? theme.accent:Color.orange).frame(width:5,height:5).accessibilityHidden(true)
                Text(model.online ? (model.lastSync == nil ? "等待 Chrome 同步":"已连接 · 自动保存") : model.connection)
                    .font(.system(size:12*fontScale)).foregroundStyle(theme.muted).lineLimit(1)
                Spacer()
                Text("\(model.selectedCount) 门课程").font(.system(size:12*fontScale,design:.monospaced)).foregroundStyle(theme.faint)
            }.padding(.horizontal,20).padding(.bottom,17).padding(.top,2)
    }
}
struct SelectedCourses: View {
    @Environment(\.widgetFontScale) private var fontScale
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
            if model.selected.isEmpty {
                VStack(spacing:12) {
                    Image(systemName:"rectangle.stack.badge.plus").font(.system(size:29*fontScale,weight:.light)).foregroundStyle(theme.accent)
                    Text("把想学的课程放在这里").font(.system(size:16*fontScale,weight:.medium))
                    Text("连接 Chrome，在发现的视频中\n选择你要追踪的课程。")
                        .font(.system(size:12*fontScale)).foregroundStyle(theme.muted).multilineTextAlignment(.center).lineSpacing(5)
                    Button("选择课程") { model.openCenter(.courses) }.buttonStyle(.plain)
                        .font(.system(size:14*fontScale,weight:.semibold)).foregroundStyle(theme.background)
                        .padding(.horizontal,18).padding(.vertical,9).background(theme.accent,in:Capsule())
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing:12) {
                        ForEach(model.selected) { lesson in
                            LessonCard(lesson:lesson,theme:theme,open:{model.open(lesson)},edit:{model.edit(lesson)},resume:{model.resume(lesson)},inspect:{model.inspect(lesson)})
                        }
                    }.padding(16)
                }.scrollIndicators(.hidden).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
    }
}

