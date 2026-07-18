import Foundation
import MCP
import Network

/// Loopback-only MCP HTTP acceptor. Default off; started from the menu / AppSettings.
/// Parses raw HTTP and forwards `POST /mcp` to `StatelessHTTPServerTransport`.
final class AgentAPIServer: @unchecked Sendable {
    static let shared = AgentAPIServer()
    static let port: UInt16 = 17_321
    /// MCP Streamable HTTP endpoint (Stateless).
    static let defaultBaseURL = "http://127.0.0.1:17321/mcp"
    static let mcpPath = "/mcp"

    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ConnectionSession] = [:]
    private var _isRunning = false
    private var startGeneration = 0

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    private init() {}

    /// Starts the listener. Pass `forceRestart: true` when enabling from the menu so a
    /// dead/half-open listener (after a failed render) is torn down and rebound.
    @MainActor
    func start(forceRestart: Bool = false) {
        if forceRestart {
            stopListener()
        }
        guard !isRunning else { return }

        startGeneration += 1
        let generation = startGeneration

        Task {
            do {
                try await PasteItMCPServer.shared.restart()
            } catch {
                NSLog("PasteIt: MCP stack failed to start: \(error)")
                return
            }

            await MainActor.run {
                guard generation == self.startGeneration else { return }
                self.bindListener()
            }
        }
    }

    @MainActor
    func stop() {
        startGeneration += 1
        stopListener()
        Task {
            await PasteItMCPServer.shared.stop()
        }
        NSLog("PasteIt: MCP stopped")
    }

    @MainActor
    private func bindListener() {
        guard listener == nil else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcp)
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: Self.port)!
            )

            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.setRunning(true)
                    NSLog("PasteIt: MCP listening on \(Self.defaultBaseURL)")
                case .failed(let error):
                    NSLog("PasteIt: MCP listener failed: \(error)")
                    Task { @MainActor in
                        self?.stopListener()
                    }
                case .cancelled:
                    self?.setRunning(false)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
            lock.lock()
            self.listener = listener
            lock.unlock()
        } catch {
            NSLog("PasteIt: MCP listener failed to start: \(error)")
            setRunning(false)
        }
    }

    @MainActor
    private func stopListener() {
        lock.lock()
        let current = listener
        let sessions = connections
        listener = nil
        connections.removeAll()
        _isRunning = false
        lock.unlock()

        current?.cancel()
        for (_, session) in sessions {
            session.connection.cancel()
        }
    }

    private func setRunning(_ value: Bool) {
        lock.lock()
        _isRunning = value
        lock.unlock()
    }

    private func accept(_ connection: NWConnection) {
        let session = ConnectionSession(connection: connection)
        let id = ObjectIdentifier(connection)
        lock.lock()
        connections[id] = session
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.lock.lock()
                self?.connections.removeValue(forKey: id)
                self?.lock.unlock()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        session.readAndServe { raw in
            await Self.handle(rawRequest: raw)
        }
    }

    private static func handle(rawRequest data: Data) async -> Data {
        guard let message = RawHTTPMessage.parse(data) else {
            return RawHTTPResponse.json(status: 400, body: ["error": "Malformed HTTP request"])
        }

        let path = message.path.split(separator: "?").first.map(String.init) ?? message.path
        guard path == mcpPath else {
            return RawHTTPResponse.json(status: 404, body: ["error": "Not found"])
        }
        guard message.method == "POST" else {
            return RawHTTPResponse.raw(
                status: 405,
                contentType: "application/json; charset=utf-8",
                body: Data(#"{"error":"Method Not Allowed"}"#.utf8),
                extraHeaders: ["Allow": "POST"]
            )
        }

        let mcpRequest = MCP.HTTPRequest(
            method: message.method,
            headers: message.headers,
            body: message.body,
            path: path
        )
        let mcpResponse = await PasteItMCPServer.shared.handle(mcpRequest)
        return RawHTTPResponse.from(mcpResponse)
    }
}

// MARK: - Connection read (headers + Content-Length body)

private final class ConnectionSession: @unchecked Sendable {
    let connection: NWConnection
    private var buffer = Data()
    private let lock = NSLock()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func readAndServe(_ handler: @escaping @Sendable (Data) async -> Data) {
        receiveMore(handler)
    }

    private func receiveMore(_ handler: @escaping @Sendable (Data) async -> Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("PasteIt: MCP receive error: \(error)")
                self.connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                self.lock.lock()
                self.buffer.append(data)
                let snapshot = self.buffer
                self.lock.unlock()

                if let complete = Self.completeHTTPMessage(in: snapshot) {
                    self.lock.lock()
                    self.buffer.removeAll(keepingCapacity: false)
                    self.lock.unlock()
                    Task {
                        let response = await handler(complete)
                        self.connection.send(content: response, completion: .contentProcessed { _ in
                            self.connection.cancel()
                        })
                    }
                    return
                }
            }
            if isComplete {
                self.connection.cancel()
                return
            }
            self.receiveMore(handler)
        }
    }

    private static func completeHTTPMessage(in data: Data) -> Data? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var contentLength = 0
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("Content-Length:".count)
                    .trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }
        let bodyStart = headerEnd + 4
        let totalNeeded = bodyStart + contentLength
        guard data.count >= totalNeeded else { return nil }
        return data.subdata(in: 0..<totalNeeded)
    }

    private static func findHeaderEnd(in data: Data) -> Int? {
        let pattern: [UInt8] = [13, 10, 13, 10]
        if data.count < 4 { return nil }
        for i in 0...(data.count - 4) {
            if data[i] == pattern[0], data[i + 1] == pattern[1],
                data[i + 2] == pattern[2], data[i + 3] == pattern[3]
            {
                return i
            }
        }
        return nil
    }
}

// MARK: - Raw HTTP parse / write (avoid clashing with MCP.HTTPRequest)

struct RawHTTPMessage: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> RawHTTPMessage? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0].uppercased()
        let rawTarget = parts[1]
        let pathPart: String
        if let qIndex = rawTarget.firstIndex(of: "?") {
            pathPart = String(rawTarget[..<qIndex])
        } else {
            pathPart = rawTarget
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerEnd + 4
        let body: Data
        if bodyStart < data.count {
            body = data.subdata(in: bodyStart..<data.count)
        } else {
            body = Data()
        }

        return RawHTTPMessage(method: method, path: pathPart, headers: headers, body: body)
    }

    private static func findHeaderEnd(in data: Data) -> Int? {
        let pattern: [UInt8] = [13, 10, 13, 10]
        if data.count < 4 { return nil }
        for i in 0...(data.count - 4) {
            if data[i] == pattern[0], data[i + 1] == pattern[1],
                data[i + 2] == pattern[2], data[i + 3] == pattern[3]
            {
                return i
            }
        }
        return nil
    }
}

enum RawHTTPResponse {
    static func from(_ response: MCP.HTTPResponse) -> Data {
        let body = response.bodyData ?? Data()
        var headers = response.headers
        if headers[HTTPHeaderName.contentType] == nil, !body.isEmpty {
            headers[HTTPHeaderName.contentType] = ContentTypeJSON
        }
        return raw(
            status: response.statusCode,
            contentType: headers[HTTPHeaderName.contentType] ?? ContentTypeJSON,
            body: body,
            extraHeaders: headers.filter { $0.key.lowercased() != "content-type" }
        )
    }

    static func json(status: Int, body: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(body)) ?? Data(#"{"error":"encode failed"}"#.utf8)
        return raw(status: status, contentType: ContentTypeJSON, body: payload)
    }

    static func raw(
        status: Int,
        contentType: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 406: reason = "Not Acceptable"
        case 415: reason = "Unsupported Media Type"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        for (name, value) in extraHeaders {
            let lower = name.lowercased()
            if lower == "content-type" || lower == "content-length" || lower == "connection" {
                continue
            }
            header += "\(name): \(value)\r\n"
        }
        header += "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static let ContentTypeJSON = "application/json; charset=utf-8"
}
