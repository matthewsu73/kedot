import Foundation
import TrackerCore

func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(b), got \(a)") }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) { do { _ = try expression() } catch { return }; preconditionFailure("Expected error") }

final class CoreTests {
    var cleanup: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { cleanup.append(block) }
    deinit { cleanup.forEach { $0() } }
    let video = "https://www.bilibili.com/video/BV1234567890?p=2"
    func temporaryStore() throws -> DiskStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:directory) }
        return try DiskStore(directory:directory)
    }
    func request(_ body: Any, path:String = "/history", token:String, headers:[String:String] = [:]) throws -> HTTPRequest {
        var h = ["host":"127.0.0.1:8765","authorization":"Bearer \(token)"]
        h.merge(headers) { _,new in new }
        return HTTPRequest(path:path,headers:h,body:try JSONSerialization.data(withJSONObject:body,options:.fragmentsAllowed))
    }
    func testCanonicalParts() {
        XCTAssertEqual(canonicalVideo("https://bilibili.com/video/BV1234567890/?p=2&foo=1"),video)
        for url in ["https://evil.com/video/BV1234567890","https://www.bilibili.com.evil.com/video/BV1234567890","http://www.bilibili.com/video/BV1234567890","https://user@www.bilibili.com/video/BV1234567890","https://www.bilibili.com:123/video/BV1234567890","https://www.bilibili.com/video/BVshort"] { XCTAssertNil(canonicalVideo(url)) }
        XCTAssertNotEqual(canonicalVideo(video),canonicalVideo(video.replacingOccurrences(of:"p=2",with:"p=3")))
    }
    func testLegacyDataAndTokenMigration() throws {
        var store:DiskStore? = try temporaryStore(); let directory = store!.directory
        let token = store!.token
        try store!.commit(Database(videos:[video:Video(title:"课程",selected:true,seconds:31,duration:100,updated:2)]))
        store = nil
        let restored = try DiskStore(directory:directory)
        XCTAssertEqual(restored.token,token);XCTAssertEqual(restored.database.videos[video]?.seconds,31)
        XCTAssertTrue(restored.database.videos[video]!.selected)
        for name in ["token.txt","data.json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath:directory.appendingPathComponent(name).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue,0o600)
        }
    }
    func testExclusiveLock() throws {
        let store = try temporaryStore()
        XCTAssertThrowsError(try DiskStore(directory:store.directory))
        withExtendedLifetime(store) {}
    }
    func testCorruptDataIsPreserved() throws {
        let store = try temporaryStore()
        let file = store.directory.appendingPathComponent("data.json")
        try Data("broken".utf8).write(to:file)
        XCTAssertThrowsError(try DiskStore(directory:store.directory,exclusive:false))
        XCTAssertEqual(try String(contentsOf:file),"broken")
    }
    func testHistoryProgressSelectionAndOrdering() throws {
        let store = try temporaryStore(), api = TrackerAPI(store:try temporaryStore())
        let active = TrackerAPI(store:store)
        XCTAssertEqual(active.handle(try request(["items":[["url":video,"title":"课程"]]],token:store.token)).status,200)
        XCTAssertEqual(active.handle(try request(["url":video,"seconds":42,"duration":100],path:"/progress",token:store.token)).status,200)
        let updated = store.database.videos[video]!.updated
        try store.select(video,value:true)
        _ = active.handle(try request(["items":[["url":video]]],token:store.token))
        XCTAssertEqual(store.database.videos[video]!.updated,updated)
        XCTAssertTrue(store.database.videos[video]!.selected)
        XCTAssertEqual(store.database.videos[video]!.fraction,0.42)
        XCTAssertEqual(api.store.database.videos.count,0)
    }
    func testAuthorizationAndOrigin() throws {
        let store = try temporaryStore(), path = "/health"
        let api = TrackerAPI(store:store)
        XCTAssertEqual(api.handle(try request([:],path:path,token:"wrong")).status,401)
        XCTAssertEqual(api.handle(try request([:],path:path,token:store.token,headers:["origin":"https://evil.example"])).status,403)
        XCTAssertEqual(api.handle(try request([:],path:path,token:store.token,headers:["host":"evil.example"])).status,403)
        XCTAssertEqual(api.handle(try request([:],path:path,token:store.token,headers:["origin":"chrome-extension://"+String(repeating:"a",count:32)])).status,200)
    }
    func testInvalidPayloadIsAtomic() throws {
        let store = try temporaryStore(), api:TrackerAPI
        api = TrackerAPI(store:store)
        for body:Any in [["items":[NSNull()]], ["items":Array(repeating:["url":video],count:501)], ["items":"bad"], [1,2]] {
            XCTAssertEqual(api.handle(try request(body,token:store.token)).status,400)
        }
        for value:Any in [-1,1000,true,"42"] {
            XCTAssertEqual(api.handle(try request(["url":video,"seconds":value,"duration":100],path:"/progress",token:store.token)).status,400)
        }
        XCTAssertTrue(store.database.videos.isEmpty)
    }
    func testSaveFailureDoesNotMutateMemory() throws {
        let store = try temporaryStore()
        // Force atomic rename to fail without depending on root/user permission differences.
        try FileManager.default.createDirectory(at:store.directory.appendingPathComponent("data.json"),withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.commit(Database(videos:[video:Video(title:"课程")])))
        XCTAssertTrue(store.database.videos.isEmpty)
    }
    func testHTTPFramingAndAbuse() throws {
        let head = "POST /health HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nContent-Length: 2\r\n\r\n"
        XCTAssertNil(try HTTPParser.parse(Data((head+"{").utf8)))
        XCTAssertEqual(try HTTPParser.parse(Data((head+"{}").utf8))?.path,"/health")
        for data in [head+"{}extra", "GET / HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}", "POST / HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}", "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}"] {
            XCTAssertThrowsError(try HTTPParser.parse(Data(data.utf8)))
        }
        XCTAssertThrowsError(try HTTPParser.parse(Data(repeating:65,count:20_000)))
    }
    func testTimeFormat() {
        XCTAssertEqual(formattedTime(3661),"1:01:01")
        XCTAssertEqual(formattedTime(42),"00:42")
        XCTAssertEqual(formattedTime(.nan),"00:00")
    }
    func testCourseMigrationAndMetadata() throws {
        let store = try temporaryStore()
        let base = courseID(video)!
        let legacy = "{\"videos\":{\"\(video)\":{\"title\":\"课程\",\"selected\":true,\"seconds\":42,\"duration\":100,\"updated\":2}}}"
        let db = try JSONDecoder().decode(Database.self,from:Data(legacy.utf8))
        XCTAssertEqual(db.courses.count,1); XCTAssertEqual(db.courses[base]!.currentPart,2)
        XCTAssertNil(db.courses[base]!.totalParts); XCTAssertTrue(db.courses[base]!.selected)
        try store.commit(db)
        let api = TrackerAPI(store:store)
        let body: [String:Any] = ["url":video,"courseTitle":"完整课程","totalParts":60,"parts":[["page":1,"title":"第一集","duration":100],["page":2,"title":"第二集","duration":100]]]
        XCTAssertEqual(api.handle(try request(body,path:"/metadata",token:store.token)).status,200)
        let course = store.database.courses[base]!
        XCTAssertEqual(course.totalParts,60); XCTAssertEqual(course.parts.count,2)
        XCTAssertEqual(course.title,"完整课程")
        XCTAssertTrue(abs(course.positionFraction(video:store.database.videos[video]!)! - 1.42/60)<0.0001)
    }
    func testManualOverrideAndResume() throws {
        let store = try temporaryStore(), api:TrackerAPI
        api = TrackerAPI(store:store)
        _ = api.handle(try request(["url":video,"seconds":20,"duration":100],path:"/progress",token:store.token))
        let base = courseID(video)!
        try store.setManualProgress(base:base,page:12,total:60,seconds:50,duration:100)
        let manualURL = partURL(base,12)
        XCTAssertEqual(store.database.courses[base]!.currentPart,12)
        _ = api.handle(try request(["url":manualURL,"seconds":1,"duration":100],path:"/progress",token:store.token))
        _ = api.handle(try request(["url":video,"seconds":2,"duration":100],path:"/progress",token:store.token))
        XCTAssertEqual(store.database.videos[manualURL]!.seconds,50)
        XCTAssertEqual(store.database.courses[base]!.currentPart,12)
        XCTAssertThrowsError(try store.setManualProgress(base:base,page:12,total:10,seconds:0,duration:100))
        XCTAssertThrowsError(try store.setManualProgress(base:base,page:12,total:60,seconds:101,duration:100))
        try store.resumeAutomatic(base:base)
        _ = api.handle(try request(["url":video,"seconds":30,"duration":100],path:"/progress",token:store.token))
        XCTAssertEqual(store.database.courses[base]!.currentPart,2)
        XCTAssertEqual(store.database.videos[video]!.seconds,30)
        XCTAssertTrue(!store.database.courses[base]!.manualProgress)
    }
    func testCoalescedWritesAndUrgentFlush() throws {
        let store = try temporaryStore(), api:TrackerAPI
        api = TrackerAPI(store:store)
        for second in 1...20 {
            let result = api.handle(try request(["url":video,"seconds":second,"duration":100,"deferSave":true],path:"/progress",token:store.token))
            XCTAssertEqual(result.status,200)
        }
        XCTAssertEqual(store.database.videos[video]!.seconds,20)
        XCTAssertEqual(store.writeCount,0); XCTAssertTrue(store.hasPendingChanges)
        try store.flush(); XCTAssertEqual(store.writeCount,1); XCTAssertTrue(!store.hasPendingChanges)
        try store.flush(); XCTAssertEqual(store.writeCount,1)
        _ = api.handle(try request(["url":video,"seconds":21,"duration":100,"deferSave":true],path:"/progress",token:store.token))
        XCTAssertEqual(store.writeCount,1)
        _ = api.handle(try request(["url":video,"seconds":21,"duration":100,"reason":"pause","deferSave":false],path:"/progress",token:store.token))
        XCTAssertEqual(store.writeCount,2); XCTAssertTrue(!store.hasPendingChanges)
    }
    func testMetadataValidationAndSelectionGrouping() throws {
        let store = try temporaryStore(), api:TrackerAPI
        api = TrackerAPI(store:store)
        let third = video.replacingOccurrences(of:"p=2",with:"p=3")
        _ = api.handle(try request(["items":[["url":video],["url":third]]],token:store.token))
        XCTAssertEqual(store.database.courses.count,1)
        try store.select(third,value:true)
        XCTAssertTrue(store.database.videos[video]!.selected && store.database.videos[third]!.selected)
        let before = store.database
        for count:Any in [0,true,-1,100001,2.5] {
            let result = api.handle(try request(["url":video,"totalParts":count,"parts":[]],path:"/metadata",token:store.token))
            XCTAssertEqual(result.status,400); XCTAssertEqual(store.database,before)
        }
    }

    func testCompletionAndTimestampNotes() throws {
        let store = try temporaryStore(), api = TrackerAPI(store:store)
        let base = courseID(video)!
        _ = api.handle(try request(["items":[["url":video,"title":"Math"]]],token:store.token))
        func progress(_ seconds:Double) throws {
            XCTAssertEqual(api.handle(try request(["url":video,"seconds":seconds,"duration":100],path:"/progress",token:store.token)).status,200)
        }
        try progress(96)
        XCTAssertEqual(store.database.status(base:base,page:2),.completed)
        try progress(20)
        XCTAssertEqual(store.database.status(base:base,page:2),.completed)
        try store.setCompletion(base:base,page:2,completed:false)
        try progress(99)
        XCTAssertEqual(store.database.status(base:base,page:2),.unwatched)
        try store.setCompletion(base:base,page:2,completed:nil)
        XCTAssertEqual(store.database.status(base:base,page:2),.completed)
        XCTAssertEqual(store.database.completedPages(base:base),1)
        var note=StudyNote(course:base,page:2,seconds:12.8,text:"  chain rule  ")
        try store.saveNote(note)
        XCTAssertTrue(note.url!.absoluteString.contains("p=2&t=12"))
        XCTAssertEqual(store.database.notes.first!.text,"chain rule")
        note.text="updated"; try store.saveNote(note)
        XCTAssertEqual(store.database.notes.count,1)
        let restored=try DiskStore(directory:store.directory,exclusive:false)
        XCTAssertEqual(restored.database.notes.first!.text,"updated")
        XCTAssertEqual(restored.database.status(base:base,page:2),.completed)
        XCTAssertEqual(restored.database.studyDays,[:])
        note.seconds = .nan; XCTAssertThrowsError(try store.saveNote(note))
        note.seconds=1; note.text="   "; XCTAssertThrowsError(try store.saveNote(note))
        try store.deleteNote(id:note.id); XCTAssertEqual(store.database.notes.count,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.directory.appendingPathComponent("pre-2.3-backup.json").path))
    }
    func testStudyTimeBoundaries() throws {
        let store=try temporaryStore(), api=TrackerAPI(store:store)
        var now=Date(timeIntervalSince1970:1700000000)
        api.clock = { now }
        func progress(_ seconds:Double, reason:String="timeupdate") throws {
            XCTAssertEqual(api.handle(try request(["url":video,"seconds":seconds,"duration":1000,"reason":reason],path:"/progress",token:store.token)).status,200)
        }
        try progress(0,reason:"playing")
        now=now.addingTimeInterval(2); try progress(2)
        XCTAssertEqual(store.database.totalStudySeconds,2)
        try progress(2); XCTAssertEqual(store.database.totalStudySeconds,2)
        now=now.addingTimeInterval(2); try progress(800,reason:"seeked")
        XCTAssertEqual(store.database.totalStudySeconds,2)
        now=now.addingTimeInterval(2); try progress(802)
        XCTAssertEqual(store.database.totalStudySeconds,4)
        now=now.addingTimeInterval(90); try progress(900)
        XCTAssertEqual(store.database.totalStudySeconds,4)
        try store.setManualProgress(base:courseID(video)!,page:2,total:60,seconds:950,duration:1000)
        XCTAssertEqual(store.database.totalStudySeconds,4)
        var db=Database(), tracker=StudyRecorder()
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let midnight=calendar.date(from:DateComponents(year:2026,month:10,day:29))!
        tracker.record(database:&db,url:video,seconds:10,reason:"playing",now:midnight.addingTimeInterval(-2),calendar:calendar)
        tracker.record(database:&db,url:video,seconds:14,reason:"timeupdate",now:midnight.addingTimeInterval(2),calendar:calendar)
        XCTAssertEqual(db.studyDays["2026-10-28"]!.values.reduce(0,+),2)
        XCTAssertEqual(db.studyDays["2026-10-29"]!.values.reduce(0,+),2)
        let other="https://www.bilibili.com/video/BV1234567891"
        tracker.record(database:&db,url:other,seconds:0,reason:"playing",now:midnight,calendar:calendar)
        tracker.record(database:&db,url:other,seconds:2,reason:"timeupdate",now:midnight.addingTimeInterval(2),calendar:calendar)
        XCTAssertEqual(db.totalStudySeconds,4) // Parallel tabs cannot double-count.
        var slowDB=Database(), slowTracker=StudyRecorder()
        slowTracker.record(database:&slowDB,url:video,seconds:0,reason:"playing",now:midnight,rate:0.5)
        slowTracker.record(database:&slowDB,url:video,seconds:1,reason:"timeupdate",now:midnight.addingTimeInterval(2),rate:0.5)
        XCTAssertEqual(slowDB.totalStudySeconds,2)

    }
    func testLearningSchemaMigrationAndRejection() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:directory) }
        let legacy:[String:Any] = ["videos":[video:["title":"Legacy","selected":true,"seconds":96,"duration":100,"updated":1]]]
        let url=directory.appendingPathComponent("data.json")
        try JSONSerialization.data(withJSONObject:legacy).write(to:url)
        do {
            let store=try DiskStore(directory:directory)
            XCTAssertEqual(store.database.notes,[]); XCTAssertEqual(store.database.studyDays,[:])
            XCTAssertEqual(store.database.status(base:courseID(video)!,page:2),.completed)
            try store.setCompletion(base:courseID(video)!,page:2,completed:false)
        }
        let backup=try Data(contentsOf:directory.appendingPathComponent("pre-2.3-backup.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with:backup) as! NSDictionary, legacy as NSDictionary)
        var malformed=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        malformed["completion"]=["https://evil.example/":true]
        let bad=try JSONSerialization.data(withJSONObject:malformed); try bad.write(to:url)
        XCTAssertThrowsError(try DiskStore(directory:directory)); XCTAssertEqual(try Data(contentsOf:url),bad)
    }

}

let tests = CoreTests()
let checks: [(String, () throws -> Void)] = [
    ("canonical URLs and parts", tests.testCanonicalParts),
    ("legacy migration, token and permissions", tests.testLegacyDataAndTokenMigration),
    ("exclusive lock", tests.testExclusiveLock),
    ("corrupt data preservation", tests.testCorruptDataIsPreserved),
    ("history, progress and selection", tests.testHistoryProgressSelectionAndOrdering),
    ("authentication, host and origin", tests.testAuthorizationAndOrigin),
    ("invalid payload atomicity", tests.testInvalidPayloadIsAtomic),
    ("disk failure rollback", tests.testSaveFailureDoesNotMutateMemory),
    ("HTTP framing and malformed requests", tests.testHTTPFramingAndAbuse),
    ("time formatting", tests.testTimeFormat),
    ("course migration, metadata and total position", tests.testCourseMigrationAndMetadata),
    ("manual progress lock and automatic resume", tests.testManualOverrideAndResume),
    ("coalesced disk writes and immediate pause flush", tests.testCoalescedWritesAndUrgentFlush),
    ("metadata validation and course grouping", tests.testMetadataValidationAndSelectionGrouping),
    ("completion persistence, override and timestamp note CRUD", tests.testCompletionAndTimestampNotes),
    ("study time, seeks, gaps, midnight and parallel tabs", tests.testStudyTimeBoundaries),
    ("learning data migration, backup and malformed file preservation", tests.testLearningSchemaMigrationAndRejection)
]
for (name, run) in checks { try run(); print("PASS: \(name)") }
print("All \(checks.count) native core checks passed")
