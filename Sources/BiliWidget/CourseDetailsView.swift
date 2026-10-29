import SwiftUI
import TrackerCore

struct CourseDetailsView: View {
    let model: WidgetModel
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss
    @State private var batch = 0
    @State private var section: Int
    init(model: WidgetModel, lesson: Lesson, initialSection: Int = 0) {
        self.model=model; self.lesson=lesson
        _section=State(initialValue:initialSection)
    }
    @State private var noteDraft: StudyNote?
    @State private var deleting: StudyNote?
    private var course: Course { model.library.courses[lesson.id] ?? lesson.course }
    private var notes: [StudyNote] { model.library.notes.filter { $0.course == lesson.id }.sorted { $0.created > $1.created } }
    private var knownPages: [Int] {
        let recorded = model.library.videos.keys.filter { courseID($0) == lesson.id }.map(partNumber)
        return Set(course.parts.map(\.page) + recorded + [course.currentPart]).sorted()
    }
    private func newNote() {
        let url = partURL(lesson.id,course.currentPart)
        let position = model.library.videos[url]?.seconds ?? lesson.video.seconds
        noteDraft = StudyNote(course:lesson.id,page:course.currentPart,seconds:position,text:"")
    }
    var body: some View {
        let pages = course.totalParts == nil ? knownPages : []
        let count = course.totalParts ?? pages.count
        let lastBatch = max(0,(count-1)/100)
        let first = min(batch,lastBatch)*100
        let visible = course.totalParts != nil ? Array((first+1)...min(count,first+100)) : Array(pages.dropFirst(first).prefix(100))
        VStack(alignment:.leading,spacing:14) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(course.title.isEmpty ? lesson.title : course.title).font(.title2.bold()).lineLimit(2)
                    Text("已完成 \(model.library.completedPages(base:lesson.id)) / \(course.totalParts.map(String.init) ?? "未知") 集 · 2.3")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("课程内容",selection:$section) {
                Text("逐集状态").tag(0)
                Text("时间戳笔记").tag(1)
            }.pickerStyle(.segmented)
            Group {
                if section == 0 {
                VStack(alignment:.leading,spacing:10) {
                    Text("自动完成：播放位置达到95%；不证明整集均已观看。手动标记独立保存，选择“跟随播放”可恢复自动判断。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        Text("每页最多100集")
                        Spacer()
                        Stepper("第 \(min(batch,lastBatch)+1) / \(lastBatch+1) 页",value:$batch,in:0...lastBatch)
                    }.font(.caption)
                    List(visible,id:\.self) { page in
                        let state = model.library.status(base:lesson.id,page:page)
                        let title = course.parts.first { $0.page == page }?.title ?? ""
                        HStack(spacing:12) {
                            Image(systemName:state == .completed ? "checkmark.circle.fill" : state == .watching ? "play.circle" : "circle")
                                .foregroundStyle(state == .completed ? model.palette.accent : .secondary)
                            VStack(alignment:.leading,spacing:3) {
                                Text("P\(page)" + (title.isEmpty ? "" : " · " + title)).lineLimit(2)
                                Text(state == .completed ? "已完成" : state == .watching ? "观看中" : "未完成")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.library.completion[partURL(lesson.id,page)] != nil { Text("手动").font(.caption).foregroundStyle(.secondary) }
                            Button(state == .completed ? "标未完成" : "标完成") { model.completion(lesson,page:page,value:state != .completed) }
                            Button("跟随播放") { model.completion(lesson,page:page,value:nil) }
                                .disabled(model.library.completion[partURL(lesson.id,page)] == nil)

                        }.padding(.vertical,3)
                    }.buttonStyle(.borderless)
                }.padding(.top,12)
                } else {
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        Text("以桌面最近同步的分P和时间为准，保存前可调整。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("记笔记",systemImage:"square.and.pencil",action:newNote)
                    }
                    if notes.isEmpty {
                        ContentUnavailableView("还没有笔记",systemImage:"note.text",description:Text("边看边记下重点；点击时间即可回到对应视频位置。"))
                    } else {
                        ScrollView {
                            LazyVStack(alignment:.leading,spacing:12) {
                            ForEach(notes) { note in
                            VStack(alignment:.leading,spacing:8) {
                                HStack {
                                    Button("P\(note.page) · \(formattedTime(note.seconds))") { model.openNote(note) }
                                        .help("在浏览器打开视频并请求跳转到此时间；是否跳转取决于B站播放器")
                                    Spacer()
                                    Button("编辑") { noteDraft = note }
                                    Button("删除",role:.destructive) { deleting = note }
                                }
                                Text(note.text).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            }.padding(14).background(model.palette.card,in:RoundedRectangle(cornerRadius:12))
                                .accessibilityElement(children:.contain)
                            }
                            }.padding(4)
                        }.buttonStyle(.bordered)
                    }
                }.padding(.top,12)
                }
            }
            if let note = deleting {
                HStack {
                    Text("确认删除这条笔记？").font(.callout)
                    Spacer()
                    Button("取消删除") { deleting=nil }
                    Button("确认删除",role:.destructive) { model.deleteNote(note); deleting=nil }
                }.padding(10).background(.red.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
            }
            if let message = model.errorMessage { Text(message).font(.caption).foregroundStyle(.red) }
        }.padding(22).frame(width:680,height:560)
        .background(model.palette.background).foregroundStyle(model.palette.foreground)
        .tint(model.palette.accent).preferredColorScheme(model.palette.colorScheme)
        .sheet(item:$noteDraft) { note in NoteEditor(model:model,note:note) }

    }
}

struct NoteEditor: View {
    let model: WidgetModel
    let note: StudyNote
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String
    @State private var page: Int
    @State private var seconds: Double
    @State private var error: String?
    init(model: WidgetModel, note: StudyNote) {
        self.model=model; self.note=note
        // A one-time draft seed deliberately ignores incoming playback changes.
        _text=State(initialValue:note.text); _page=State(initialValue:note.page); _seconds=State(initialValue:note.seconds)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("时间戳笔记").font(.title2.bold())
            HStack {
                Stepper("P\(page)",value:$page,in:1...100000)
                Text("时间（秒）").font(.callout)
                TextField("视频时间（秒）",value:$seconds,format:.number).frame(width:130)
            }
            TextEditor(text:$text).font(.body).focused($focused).frame(height:180)
                .overlay { RoundedRectangle(cornerRadius:6).stroke(.secondary.opacity(0.2)) }
                .accessibilityLabel("笔记内容")
            Text("纯文本，最多10,000字；不会上传云端。时间是播放器位置，不是学习时长。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var value=note; value.text=text; value.page=page; value.seconds=seconds
                    do { try model.saveNote(value); dismiss() } catch { self.error=error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width:500).background(model.palette.background).foregroundStyle(model.palette.foreground)
        .tint(model.palette.accent).preferredColorScheme(model.palette.colorScheme).onAppear { focused=true }
    }
}
