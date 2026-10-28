import Foundation
import Network

public final class LocalServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "BiliWidget.local-http")
    private var sessions: [UUID: HTTPSession] = [:]
    public var onState: ((Result<Void, Error>) -> Void)?
    public var onRequest: ((HTTPRequest, @escaping (APIResult) -> Void) -> Void)?
    public init() {}
    public func start(port: UInt16 = 8765) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: DispatchQueue.main.async { self?.onState?(.success(())) }
            case .failed(let error): DispatchQueue.main.async { self?.onState?(.failure(error)) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.sessions.count < 32 else { connection.cancel(); return }
            let id = UUID()
            let session = HTTPSession(connection: connection, queue: self.queue)
            session.finished = { [weak self] in self?.sessions.removeValue(forKey: id) }
            session.request = { [weak self] request, respond in
                DispatchQueue.main.async {
                    guard let handler = self?.onRequest else { respond(APIResult(500, ["error":"服务未就绪"])); return }
                    handler(request, respond)
                }
            }
            self.sessions[id] = session; session.start()
        }
        listener.start(queue: queue)
    }
    public func stop() {
        listener?.cancel()
        queue.async { [weak self] in
            guard let self else { return }
            let current = Array(self.sessions.values)
            current.forEach { $0.finish() }
        }
    }
}
private final class HTTPSession {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var data = Data()
    private var timer: DispatchSourceTimer?
    private var ended = false
    var finished: (() -> Void)?
    var request: ((HTTPRequest, @escaping (APIResult) -> Void) -> Void)?
    init(connection: NWConnection, queue: DispatchQueue) { self.connection = connection; self.queue = queue }
    func start() {
        connection.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 8)
        timer.setEventHandler { [weak self] in self?.finish() }
        self.timer = timer; timer.resume(); receive()
    }
    func finish() {
        guard !ended else { return }
        ended = true; timer?.cancel(); timer = nil; connection.cancel(); finished?()
    }
    private func send(_ response: APIResult) {
        queue.async { [weak self] in
            guard let self, !self.ended else { return }
            self.connection.send(content: response.wire, completion: .contentProcessed { [weak self] _ in self?.finish() })
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, done, error in
            guard let self, !self.ended else { return }
            if let chunk { self.data.append(chunk) }
            do {
                if let request = try HTTPParser.parse(self.data) {
                    self.request?(request, { [weak self] in self?.send($0) }); return
                }
            } catch let failure as HTTPFailure { self.send(APIResult(failure.status, ["error":failure.message])); return }
            catch { self.send(APIResult(400, ["error":"请求无效"])); return }
            if error != nil || done { self.finish() } else { self.receive() }
        }
    }
}
