import Foundation

public enum PartStatus: String { case unwatched, watching, completed }
public struct StudyNote: Codable, Equatable, Identifiable {
    public var id: UUID
    public var course: String
    public var page: Int
    public var seconds: Double
    public var text: String
    public var created: Double
    public init(id: UUID = UUID(), course: String, page: Int, seconds: Double, text: String, created: Double = Date().timeIntervalSince1970) {
        self.id = id; self.course = course; self.page = page; self.seconds = seconds; self.text = text; self.created = created
    }
    public var url: URL? {
        guard courseID(course) == course, !course.contains("?"), (1...100000).contains(page), seconds.isFinite, (0..<86400).contains(seconds),
              var parts = URLComponents(string:partURL(course,page)) else { return nil }
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name:"t",value:String(Int(seconds)))]
        return parts.url
    }
}
public extension Database {
    func status(base: String, page: Int) -> PartStatus {
        let url = partURL(base,page)
        if let manual = completion[url] { return manual ? .completed : .unwatched }
        if finished.contains(url) { return .completed }
        guard let v = videos[url] else { return .unwatched }
        if v.duration > 0 && v.fraction >= 0.95 { return .completed }
        return v.seconds > 0 ? .watching : .unwatched
    }
    func completedPages(base: String) -> Int {
        let keys = Set(videos.keys.filter { courseID($0) == base }).union(completion.keys.filter { courseID($0) == base })
        return keys.union(finished.filter { courseID($0) == base }).filter { url in
            (courses[base]?.totalParts.map { partNumber(url) <= $0 } ?? true) && status(base:base,page:partNumber(url)) == .completed
        }.count
    }
    var totalStudySeconds: Double { studyDays.values.reduce(0) { $0 + $1.values.reduce(0,+) } }
    func validateLearningData() throws {
        guard finished.allSatisfy({ canonicalVideo($0) == $0 && courses[courseID($0) ?? ""] != nil }),
              completion.keys.allSatisfy({ canonicalVideo($0) == $0 && courses[courseID($0) ?? ""] != nil }),
              Set(notes.map(\.id)).count == notes.count,
              notes.allSatisfy({ $0.url != nil && courses[$0.course] != nil && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.text.count <= 10000 && $0.created.isFinite }),
              studyDays.allSatisfy({ day, courses in
                  day.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options:.regularExpression) != nil &&
                  courses.allSatisfy({ base, seconds in courseID(base) == base && !base.contains("?") && seconds.isFinite && (0...90000).contains(seconds) }) && courses.values.reduce(0,+) <= 90000
              }) else { throw TrackerError.message("笔记、逐集状态或统计数据无效，请保留原文件。") }
    }
}
public extension DiskStore {
    func setCompletion(base: String, page: Int, completed: Bool?) throws {
        guard let course = database.courses[base], (1...100000).contains(page), course.totalParts.map({page <= $0}) ?? true else {
            throw TrackerError.message("分集不存在或超出总集数。")
        }
        var copy = database
        copy.completion[partURL(base,page)] = completed
        try commit(copy)
    }
    func saveNote(_ note: StudyNote) throws {
        guard database.courses[note.course] != nil, note.url != nil else { throw TrackerError.message("请检查课程、分 P 和笔记时间。") }
        var copy = database
        var value = note; value.text = value.text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.text.isEmpty, value.text.count <= 10000 else { throw TrackerError.message("请输入笔记内容，最多10,000字。") }
        if let index = copy.notes.firstIndex(where:{$0.id == note.id}) {
            value.created = copy.notes[index].created
            copy.notes[index] = value
        } else { copy.notes.append(value) }
        try commit(copy)
    }
    func deleteNote(id: UUID) throws {
        var copy = database; copy.notes.removeAll { $0.id == id }; try commit(copy)
    }
}

/// Estimates wall-clock playback, not attention or unique content watched.
/// Samples never persist: startup, seeks and offline replay cannot reconstruct time.
public struct PlaybackSample { let seconds: Double; let date: Date }
public struct StudyRecorder {
    private var samples: [String: PlaybackSample] = [:]
    private var lastCredit: Date?
    public init() {}
    public mutating func record(database: inout Database, url: String, seconds: Double, reason: String, now: Date, calendar: Calendar = .current, rate: Double = 1) {
        let previous = samples[url]
        samples[url] = PlaybackSample(seconds:seconds,date:now)
        if samples.count > 100 { samples = Dictionary(uniqueKeysWithValues:samples.sorted { $0.value.date > $1.value.date }.prefix(100).map { ($0.key,$0.value) }) }
        guard !["seeked","loaded","initial","playing","ratechange","durationchange"].contains(reason), let previous else { return }
        let elapsed = now.timeIntervalSince(previous.date), advance = seconds-previous.seconds
        guard rate.isFinite, rate > 0, rate <= 16, elapsed >= 0.25, elapsed <= 30, advance > 0, advance <= elapsed*rate*1.5+2 else { return }
        let globalAvailable = lastCredit.map { max(0,now.timeIntervalSince($0)) } ?? elapsed
        let credit = min(elapsed,advance/rate,globalAvailable)
        guard credit > 0 else { return }
        lastCredit = now
        let base = courseID(url)!
        // Split credit at local midnight, including DST boundaries.
        var cursor = now.addingTimeInterval(-credit)
        while cursor < now {
            let start = calendar.startOfDay(for:cursor)
            guard let next = calendar.date(byAdding:.day,value:1,to:start) else { break }
            let end = min(next,now)
            let key = Self.dayKey(cursor,calendar:calendar)
            let current = database.studyDays[key,default:[:]].values.reduce(0,+)
            database.studyDays[key,default:[:]][base,default:0] += max(0,min(end.timeIntervalSince(cursor),90000-current))
            cursor = end
        }
    }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
}
