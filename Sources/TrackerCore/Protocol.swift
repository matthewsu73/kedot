import Foundation
public struct HTTPRequest {
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public init(path: String, headers: [String: String], body: Data) { self.path = path; self.headers = headers; self.body = body }
}
public struct HTTPFailure: Error {
    public let status: Int
    public let message: String
    public init(_ status: Int, _ message: String) { self.status = status; self.message = message }
}
public enum HTTPParser {
    public static func parse(_ data: Data) throws -> HTTPRequest? {
        guard data.count <= 1_020_000 else { throw HTTPFailure(413, "请求过大") }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 16_384 { throw HTTPFailure(431, "请求头过大") }
            return nil
        }
        guard boundary.lowerBound <= 16_384,
              let headerText = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { throw HTTPFailure(400, "请求头无效") }
        let lines = headerText.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ")
        guard request.count == 3, request[2] == "HTTP/1.1" else { throw HTTPFailure(400, "HTTP 格式无效") }
        guard request[0] == "POST" else { throw HTTPFailure(405, "仅允许 POST") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw HTTPFailure(400, "请求头无效") }
            let key = String(line[..<colon]).lowercased()
            guard !key.isEmpty, headers[key] == nil else { throw HTTPFailure(400, "重复请求头") }
            headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let countText = headers["content-length"], !countText.isEmpty,
              countText.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let count = Int(countText), count > 0 else { throw HTTPFailure(400, "Content-Length 无效") }
        guard count <= 1_000_000 else { throw HTTPFailure(413, "请求体过大") }
        guard data.count >= boundary.upperBound + count else { return nil }
        guard data.count == boundary.upperBound + count else { throw HTTPFailure(400, "不支持流水线请求") }
        return HTTPRequest(path: String(request[1]), headers: headers, body: data.subdata(in: boundary.upperBound..<data.count))
    }
}
public struct APIResult {
    public let status: Int
    public let body: [String: Any]
    public var wire: Data {
        let content = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason = [200:"OK",400:"Bad Request",401:"Unauthorized",403:"Forbidden",404:"Not Found",405:"Method Not Allowed",413:"Payload Too Large",431:"Request Header Fields Too Large",500:"Internal Server Error"][status] ?? "Error"
        var result = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(content.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        result.append(content); return result
    }
    public init(_ status: Int, _ body: [String: Any]) { self.status = status; self.body = body }
}
public final class TrackerAPI {
    public let store: DiskStore
    public let port: UInt16
    public var didSync: (() -> Void)?
    private var recorder = StudyRecorder()
    public var clock: () -> Date = Date.init
    public init(store: DiskStore, port: UInt16 = 8765) { self.store = store; self.port = port }
    private func sameSecret(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x,y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    public func handle(_ request: HTTPRequest) -> APIResult {
        do {
            guard request.headers["host"] == "127.0.0.1:\(port)" else { throw HTTPFailure(403, "Host 无效") }
            if let origin = request.headers["origin"], origin.range(of: "^chrome-extension://[a-p]{32}$", options: .regularExpression) == nil { throw HTTPFailure(403, "Origin 无效") }
            guard sameSecret(request.headers["authorization"] ?? "", "Bearer " + store.token) else { throw HTTPFailure(401, "配对码错误，请重新配对") }
            guard ["/history", "/progress", "/metadata", "/health"].contains(request.path) else { throw HTTPFailure(404, "接口不存在") }
            guard let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else { throw HTTPFailure(400, "需要 JSON 对象") }
            if request.path == "/health" { return APIResult(200, ["ok":true,"version":"2.3.0","channel":"stable"]) }
            let entries: [[String:Any]]
            if request.path == "/history" {
                guard let items = body["items"] as? [[String:Any]], items.count <= 500 else { throw HTTPFailure(400, "历史格式无效，最多 500 条") }
                entries = items
            } else { entries = [body] }
            var copy = store.database
            copy.migrateCourses()
            var accepted = 0
            var nextRecorder = recorder
            for entry in entries {
                guard let raw = entry["url"] as? String, let url = canonicalVideo(raw) else { continue }
                let base = courseID(url)!
                var course = copy.courses[base] ?? Course()
                var item = copy.videos[url] ?? Video(selected: course.selected)
                if let title = entry["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    item.title = String(title.replacingOccurrences(of: "_哔哩哔哩_bilibili", with: "").prefix(200))
                    if course.title.isEmpty { course.title = item.title }
                }
                if request.path == "/progress" {
                    guard let s = entry["seconds"] as? NSNumber, let d = entry["duration"] as? NSNumber,
                          CFGetTypeID(s) != CFBooleanGetTypeID(), CFGetTypeID(d) != CFBooleanGetTypeID() else { throw HTTPFailure(400, "进度必须为数字") }
                    let seconds = s.doubleValue, duration = d.doubleValue
                    guard seconds.isFinite, duration.isFinite, duration > 0, duration < 86400, seconds >= 0, seconds <= duration + 5 else { throw HTTPFailure(400, "进度超出范围") }
                    if seconds / duration >= 0.95 { copy.finished.insert(url) }
                    nextRecorder.record(database:&copy,url:url,seconds:seconds,reason:entry["reason"] as? String ?? "timeupdate",now:clock(),rate:(entry["playbackRate"] as? Double) ?? 1)
                    if !course.manualProgress {
                        if let total = course.totalParts, partNumber(url)>total { throw HTTPFailure(400,"当前分 P 超出已知总集数，请刷新页面分集信息") }
                        item.seconds = min(seconds, duration); item.duration = duration
                        item.updated = Date().timeIntervalSince1970; course.currentPart = partNumber(url)
                    }
                } else if item.updated == 0 { item.updated = Date().timeIntervalSince1970 }
                if request.path == "/metadata" {
                    guard let count = entry["totalParts"] as? NSNumber,
                          CFGetTypeID(count) != CFBooleanGetTypeID(), count.doubleValue == Double(count.intValue),
                          (1...100000).contains(count.intValue),
                          let parts = entry["parts"] as? [[String: Any]], parts.count <= 10000 else { throw HTTPFailure(400, "总集数或分集列表无效") }
                    var parsed: [PartInfo] = []; var pages = Set<Int>()
                    for part in parts {
                        guard let p = part["page"] as? NSNumber, CFGetTypeID(p) != CFBooleanGetTypeID(),
                              p.doubleValue == Double(p.intValue), (1...count.intValue).contains(p.intValue),
                              let d = part["duration"] as? NSNumber, CFGetTypeID(d) != CFBooleanGetTypeID(),
                              d.doubleValue.isFinite, (0..<86400).contains(d.doubleValue), pages.insert(p.intValue).inserted else { throw HTTPFailure(400, "分集信息无效") }
                        parsed.append(PartInfo(page: p.intValue, title: String((part["title"] as? String ?? "").prefix(200)), duration: d.doubleValue))
                    }
                    if !course.manualProgress {
                        guard count.intValue >= course.currentPart else { throw HTTPFailure(400, "总集数小于当前分 P") }
                        course.totalParts = count.intValue; course.parts = parsed
                        if let title = entry["courseTitle"] as? String, !title.isEmpty { course.title = String(title.prefix(200)) }
                    }
                }
                copy.videos[url] = item; copy.courses[base] = course; accepted += 1
            }
            // Older extensions save immediately; only active timeupdate messages opt into batching.
            if request.path == "/progress", body["deferSave"] as? Bool == true { store.stage(copy) }
            else { try store.commit(copy) }
            recorder = nextRecorder
            didSync?()
            return APIResult(200, ["ok":true,"accepted":accepted,"lowPower":ProcessInfo.processInfo.isLowPowerModeEnabled])
        } catch let error as HTTPFailure { return APIResult(error.status, ["error":error.message]) }
        catch is DecodingError { return APIResult(400, ["error":"JSON 格式无效"]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 3840 { return APIResult(400, ["error":"JSON 格式无效"]) }
        catch { return APIResult(500, ["error":"保存失败：\(error.localizedDescription)"]) }
    }
}
import CoreFoundation
