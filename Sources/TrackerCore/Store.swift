import Foundation
import Security
import Darwin

public struct Video: Codable, Equatable {
    public var title: String
    public var selected: Bool
    public var seconds: Double
    public var duration: Double
    public var updated: Double
    public init(title: String = "", selected: Bool = false, seconds: Double = 0, duration: Double = 0, updated: Double = 0) {
        self.title = title; self.selected = selected; self.seconds = seconds; self.duration = duration; self.updated = updated
    }
    public var fraction: Double { duration > 0 ? min(1, max(0, seconds / duration)) : 0 }
}
public struct PartInfo: Codable, Equatable {
    public var page: Int
    public var title: String
    public var duration: Double
    public init(page: Int, title: String = "", duration: Double = 0) { self.page = page; self.title = title; self.duration = duration }
}
public struct Course: Codable, Equatable {
    public var title: String
    public var selected: Bool
    public var currentPart: Int
    public var totalParts: Int?
    public var parts: [PartInfo]
    public var manualProgress: Bool
    public init(title: String = "", selected: Bool = false, currentPart: Int = 1, totalParts: Int? = nil, parts: [PartInfo] = [], manualProgress: Bool = false) {
        self.title = title; self.selected = selected; self.currentPart = currentPart; self.totalParts = totalParts; self.parts = parts; self.manualProgress = manualProgress
    }
    public func positionFraction(video: Video) -> Double? {
        guard let total = totalParts, total > 0 else { return nil }
        return min(1, max(0, (Double(currentPart - 1) + video.fraction) / Double(total)))
    }
}
public struct Database: Codable, Equatable {
    public var videos: [String: Video]
    public var courses: [String: Course]
    public var completion: [String: Bool] = [:]
    public var finished: Set<String> = []
    public var notes: [StudyNote] = []
    public var studyDays: [String: [String: Double]] = [:]
    public init(videos: [String: Video] = [:], courses: [String: Course] = [:]) { self.videos = videos; self.courses = courses }
    enum CodingKeys: String, CodingKey { case videos, courses, completion, finished, notes, studyDays }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videos = try c.decode([String: Video].self, forKey: .videos)
        courses = try c.decodeIfPresent([String: Course].self, forKey: .courses) ?? [:]
        completion = try c.decodeIfPresent([String: Bool].self, forKey: .completion) ?? [:]
        finished = try c.decodeIfPresent(Set<String>.self, forKey: .finished) ?? Set(videos.filter { $0.value.duration > 0 && $0.value.fraction >= 0.95 }.map(\.key))
        notes = try c.decodeIfPresent([StudyNote].self, forKey: .notes) ?? []
        studyDays = try c.decodeIfPresent([String: [String: Double]].self, forKey: .studyDays) ?? [:]
        migrateCourses()
    }
    public mutating func migrateCourses() {
        let groups = Dictionary(grouping: videos.keys, by: { courseID($0) ?? $0 })
        for (base, urls) in groups where courses[base] == nil {
            let recent = urls.max { (videos[$0]?.updated ?? 0) < (videos[$1]?.updated ?? 0) }!
            courses[base] = Course(title: videos[recent]?.title ?? "", selected: urls.contains { videos[$0]?.selected == true }, currentPart: partNumber(recent))
        }
    }
}
public func courseID(_ url: String) -> String? {
    guard let clean = canonicalVideo(url), var c = URLComponents(string: clean) else { return nil }
    c.query = nil; return c.string
}
public func partNumber(_ url: String) -> Int {
    Int(URLComponents(string: url)?.queryItems?.first { $0.name == "p" }?.value ?? "1") ?? 1
}
public func partURL(_ base: String, _ page: Int) -> String { base + (page > 1 ? "?p=\(page)" : "") }
public enum TrackerError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): return text } }
}
public func canonicalVideo(_ raw: String) -> String? {
    guard let c = URLComponents(string: raw), c.scheme == "https", ["www.bilibili.com", "bilibili.com"].contains(c.host),
          c.user == nil, c.password == nil, c.port == nil,
          c.path.range(of: "^/video/BV[0-9A-Za-z]{10}/?$", options: .regularExpression) != nil else { return nil }
    let rawPage = c.queryItems?.first(where: { $0.name == "p" })?.value ?? "1"
    let page = Int(rawPage).map { min(100000, max(1, $0)) } ?? 1
    let id = c.path.split(separator: "/")[1]
    return "https://www.bilibili.com/video/\(id)" + (page > 1 ? "?p=\(page)" : "")
}
public func formattedTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = Int(max(0, min(86400, seconds)))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value/3600, value%3600/60, value%60) : String(format: "%02d:%02d", value/60, value%60)
}

/// Caller serializes access. UI and request mutations are all dispatched to the main thread.
public final class DiskStore {
    public let directory: URL
    public let token: String
    public private(set) var database: Database
    private var lockFD: Int32 = -1
    private var persisted = Database()
    private var pendingSave: DispatchWorkItem?
    public private(set) var writeCount = 0
    public var onPersistenceError: ((Error) -> Void)?
    public var hasPendingChanges: Bool { database != persisted }
    public init(directory: URL, exclusive: Bool = true) throws {
        self.directory = directory
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var descriptor: Int32 = -1
        if exclusive {
            descriptor = Darwin.open(directory.appendingPathComponent("native.lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { throw TrackerError.message("无法创建数据锁，请检查目录权限。") }
            if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                Darwin.close(descriptor)
                throw TrackerError.message("程序已经运行，请从菜单栏打开已有窗口。")
            }
        }
        do {
            let tokenURL = directory.appendingPathComponent("token.txt")
            if fm.fileExists(atPath: tokenURL.path) {
                let value = try String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.count >= 32, value.utf8.allSatisfy({ $0 >= 33 && $0 < 127 }) else { throw TrackerError.message("配对码文件损坏，请备份 token.txt 后重新生成。") }
                token = value
            } else {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw TrackerError.message("无法生成配对码。") }
                token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                try Data(token.utf8).write(to: tokenURL, options: [.atomic])
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            let dataURL = directory.appendingPathComponent("data.json")
            if fm.fileExists(atPath: dataURL.path) {
                database = try JSONDecoder().decode(Database.self, from: Data(contentsOf: dataURL))
                for (url, item) in database.videos {
                    guard canonicalVideo(url) == url, item.seconds.isFinite, item.duration.isFinite, item.updated.isFinite,
                          item.seconds >= 0, item.duration >= item.seconds, item.duration < 86400 else {
                        throw TrackerError.message("数据文件包含无效记录。请先备份 data.json，不要覆盖原数据。")
                    }
                }
            } else { database = Database() }
            for (base, course) in database.courses {
                guard courseID(base) == base, (1...100000).contains(course.currentPart),
                      course.totalParts.map({ (course.currentPart...100000).contains($0) }) ?? true,
                      course.parts.count <= 10000,
                      course.parts.allSatisfy({ (1...100000).contains($0.page) && $0.duration.isFinite && $0.duration >= 0 && $0.duration < 86400 }) else {
                    throw TrackerError.message("课程分集数据无效，请先备份 data.json。")
                }
            }
            try database.validateLearningData()
            persisted = database
            lockFD = descriptor
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw error
        }
    }
    deinit { pendingSave?.cancel(); if lockFD >= 0 { Darwin.close(lockFD) } }
    public func commit(_ value: Database) throws {
        if value == persisted { database = value; pendingSave?.cancel(); pendingSave = nil; return }
        let url = directory.appendingPathComponent("data.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try value.validateLearningData()
        let bytes = try encoder.encode(value)
        if FileManager.default.fileExists(atPath:url.path), !FileManager.default.fileExists(atPath:directory.appendingPathComponent("pre-2.3-backup.json").path) {
            try FileManager.default.copyItem(at:url,to:directory.appendingPathComponent("pre-2.3-backup.json"))
        }
        // Create temporary content with 0600 before atomically replacing the database.
        let temporary = directory.appendingPathComponent(".save-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else {
            throw TrackerError.message("无法保存课程，请检查磁盘和目录权限。")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw TrackerError.message("无法替换数据文件。原记录已保留。") }
        database = value; persisted = value; writeCount += 1
        pendingSave?.cancel(); pendingSave = nil
    }
    /// Event-driven coalescing: memory/UI update now, at most one disk flush per ten seconds.
    public func stage(_ value: Database) {
        guard value != database else { return }
        database = value
        guard pendingSave == nil, hasPendingChanges else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            do { try self.flush() } catch { self.onPersistenceError?(error) }
        }
        pendingSave = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: task)
    }
    public func flush() throws { try commit(database) }
    public func select(_ url: String, value: Bool) throws {
        guard let base = courseID(url) else { return }
        var copy = database; copy.migrateCourses()
        guard copy.courses[base] != nil else { return }
        copy.courses[base]?.selected = value
        for key in copy.videos.keys where courseID(key) == base { copy.videos[key]?.selected = value }
        try commit(copy)
    }
    public func setManualProgress(base: String, page: Int, total: Int?, seconds: Double, duration: Double) throws {
        guard courseID(base) == base, (1...100000).contains(page),
              total.map({ (page...100000).contains($0) }) ?? true,
              seconds.isFinite, duration.isFinite, duration >= 0, duration < 86400, seconds >= 0, seconds <= duration else {
            throw TrackerError.message("请检查分 P、总集数和本集时间；已看时间不能超过时长。")
        }
        var copy = database; copy.migrateCourses()
        guard var course = copy.courses[base] else { throw TrackerError.message("课程不存在。") }
        course.currentPart = page; course.totalParts = total; course.manualProgress = true
        copy.courses[base] = course
        let url = partURL(base, page)
        var video = copy.videos[url] ?? Video(title: course.title, selected: course.selected)
        video.seconds = seconds; video.duration = duration; video.updated = Date().timeIntervalSince1970
        copy.videos[url] = video
        try commit(copy)
    }
    public func resumeAutomatic(base: String) throws {
        var copy = database
        guard copy.courses[base] != nil else { return }
        copy.courses[base]?.manualProgress = false; try commit(copy)
    }
}
