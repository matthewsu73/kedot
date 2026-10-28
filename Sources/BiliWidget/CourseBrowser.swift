import SwiftUI
import TrackerCore

struct CourseBrowser: View {
    let model: WidgetModel
    @State private var search = ""
    @State private var onlySelected = false
    private var filtered: [Lesson] {
        model.lessons.filter { (!onlySelected || $0.course.selected) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.id.contains(search)) }
    }
    var body: some View {
        let matches = filtered
        VStack(alignment:.leading, spacing:12) {
            HStack {
                TextField("搜索课程标题或视频地址", text: $search).textFieldStyle(.roundedBorder)
                Toggle("仅已选", isOn: $onlySelected).toggleStyle(.checkbox)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if matches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(model.lessons.isEmpty ? "还没有发现视频" : "没有匹配的课程").font(.headline)
                    Text("配对成功后可导入 Chrome 历史；播放视频后才会有进度。")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(matches) { lesson in
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
        }
    }
}
