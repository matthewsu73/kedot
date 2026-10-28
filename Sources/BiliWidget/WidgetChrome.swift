import SwiftUI

// Keep connection ticks, header preferences, and playback list updates in separate
// observation boundaries. The chrome does not read the live lesson array.
struct WidgetHeader: View {
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
            HStack(spacing:10) {
                Image(systemName:"play.rectangle.fill").accessibilityHidden(true).font(.system(size:19,weight:.semibold))
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
                }.buttonStyle(.plain).help("切换置顶").accessibilityLabel("切换置顶").accessibilityValue(model.alwaysOnTop ? "已置顶" : "未置顶")
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
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多操作").accessibilityLabel("更多操作")
            }.padding(.horizontal,20).padding(.top,19).padding(.bottom,17)
    }
}
struct WidgetStatus: View {
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
            HStack(spacing:6) {
                Circle().fill(model.online ? theme.accent:Color.orange).frame(width:5,height:5).accessibilityHidden(true)
                Text(model.online ? (model.lastSync == nil ? "等待 Chrome 同步":"已连接 · 自动保存") : model.connection)
                    .font(.system(size:10)).foregroundStyle(theme.muted).lineLimit(1)
                Spacer()
                Text("\(model.selectedCount) 门课程").font(.system(size:10,design:.monospaced)).foregroundStyle(theme.faint)
                Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:9)).foregroundStyle(theme.faint)
                    .accessibilityHidden(true)
            }.padding(.horizontal,20).padding(.bottom,17).padding(.top,2)
    }
}
struct SelectedCourses: View {
    let model: WidgetModel
    private var theme: ThemePalette { model.palette }
    var body: some View {
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
    }
}

