import SwiftUI

struct WidgetSettingsView: View {
    let model: WidgetModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                GroupBox("窗口") {
                    VStack(alignment:.leading,spacing:12) {
                        Toggle("始终置顶",isOn:Binding(get:{model.alwaysOnTop},set:{if $0 != model.alwaysOnTop {model.toggleTop()}}))
                        Toggle("紧凑布局",isOn:Binding(get:{model.compact},set:{if $0 != model.compact {model.toggleCompact()}}))
                        HStack {
                            Text("窗口大小").font(.callout)
                            Button("小") { model.resizeWindow?(CGSize(width:300,height:360)) }
                            Button("标准") { model.resizeWindow?(CGSize(width:354,height:430)) }
                            Button("大") { model.resizeWindow?(CGSize(width:520,height:620)) }
                            Spacer()
                            Button("居中") { model.centerWindow?() }
                            Button("恢复默认") { model.resetWindow?() }
                        }
                        Text("拖动系统标题栏移动；四边和四角均可缩放。红色关闭按钮或⌘W只收起窗口，后台继续同步；菜单栏图标可恢复。⌘Q才会退出程序。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
                }
                GroupBox("外观") {
                    VStack(spacing:14) {
                        HStack {
                            Text("悬浮窗字体")
                            Slider(value:Binding(get:{model.fontScale},set:{model.setFontScale($0)}),in:0.8...1.4,step:0.05)
                                .accessibilityLabel("悬浮窗字体大小")
                                .accessibilityValue("\(Int((model.fontScale*100).rounded()))%")
                            Text("\(Int((model.fontScale*100).rounded()))%")
                                .monospacedDigit().frame(width:44,alignment:.trailing)
                            Button("默认") { model.setFontScale(1) }.disabled(model.fontScale == 1)
                        }
                        Text("拖动滑杆即时调整悬浮窗文字，重启后保留；100%为当前默认大小。")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("深浅色",selection:Binding(get:{model.appearanceMode},set:{model.setAppearance($0)})) {
                            ForEach(AppearanceMode.allCases) { Text($0.name).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth:360)
                        HStack(spacing:8) {
                            ForEach(WidgetTheme.allCases) { value in
                                ThemeSwatch(theme:value,dark:model.palette.dark,selected:model.theme == value) { model.setTheme(value) }
                            }
                        }
                    }.frame(maxWidth:.infinity).padding(8)
                }
                GroupBox("Chrome 配对与本机数据") {
                    VStack(alignment:.leading,spacing:12) {
                        Label(model.connection,systemImage:model.online ? "checkmark.circle.fill":"exclamationmark.circle")
                        HStack {
                            Button("显示扩展文件夹",action:model.revealExtension)
                            Button("复制配对码",action:model.copyToken).disabled(model.store == nil)
                            Spacer()
                            Button("打开数据目录",action:model.revealData)
                        }
                        Text("首次使用：加载 Chrome 扩展 → 粘贴配对码并同步 → 刷新 B站视频页。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error=model.errorMessage { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
                }
                Text("窗口关闭后继续同步，不会删除课程、笔记或统计。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(4)
        }
    }
}
