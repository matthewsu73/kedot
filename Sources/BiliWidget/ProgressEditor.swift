import SwiftUI
import TrackerCore

struct ProgressEditor: View {
    let model: WidgetModel
    let lesson: Lesson
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case total, duration, seconds }
    @State private var page: Int
    @State private var total: String
    @State private var seconds: Double
    @State private var duration: Double
    @State private var error: String?
    init(model: WidgetModel, lesson: Lesson) {
        self.model = model; self.lesson = lesson
        // Seed an editing draft once; incoming playback must not overwrite user input.
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
                TextField("总集数（未知可留空）",text:$total).focused($focusedField,equals:.total)
                TextField("本集时长（秒）",value:$duration,format:.number.precision(.fractionLength(0...1))).focused($focusedField,equals:.duration)
                TextField("本集已看到（秒）",value:$seconds,format:.number.precision(.fractionLength(0...1))).focused($focusedField,equals:.seconds)
                Slider(value:Binding(get:{ ProgressInput.sliderSeconds(seconds, duration:duration) },set:{ seconds = $0 }),in:0...ProgressInput.sliderUpperBound(duration)).disabled(!duration.isFinite || duration<=0).accessibilityLabel("本集观看进度")
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
            .onAppear { focusedField = .seconds }
            .onChange(of:duration) { _, value in
                if value.isFinite, value >= 0, seconds.isFinite, seconds > value { seconds = value }
            }
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
