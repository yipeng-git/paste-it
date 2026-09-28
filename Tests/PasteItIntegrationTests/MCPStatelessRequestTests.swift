import Foundation
import MCP
import Testing
@testable import PasteIt

@Suite("MCP stateless HTTP requests", .timeLimit(.minutes(1)))
struct MCPStatelessRequestTests {
    @Test func independentClientsAndReconnectCanInitialize() async throws {
        try await Self.withServer { host in
            for client in ["client-a", "client-b", "client-a"] {
                let initialized = try Self.result(await host.handle(Self.initialize(client: client)))
                #expect(initialized["protocolVersion"]?.stringValue == "2025-11-25")
                #expect(initialized["serverInfo"]?.objectValue?["name"]?.stringValue == "Paste It")
                let notification = await host.handle(try Self.request("notifications/initialized", id: nil))
                #expect(notification.statusCode == 202)
                let tools = try Self.result(await host.handle(Self.request("tools/list")))
                let names = tools["tools"]?.arrayValue?.compactMap {
                    $0.objectValue?["name"]?.stringValue
                }
                #expect(names == PasteItMCPTools.definitions.map(\.name))
            }
        }
    }

    @Test func concurrentClientsCanReuseRequestIDsWithoutCrossingResponses() async throws {
        try await Self.withServer { host in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<24 {
                    group.addTask {
                        _ = try Self.result(await host.handle(Self.initialize(client: "client-\(index)")))
                        // Each response is distinguishable without opening real history.
                        let name = "synthetic_unknown_tool_\(index)"
                        let reply = try Self.result(await host.handle(Self.request("tools/call", params: [
                            "name": .string(name), "arguments": .object([:]),
                        ])))
                        #expect(reply["isError"]?.boolValue == true)
                        #expect(reply["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
                            == "Unknown tool: \(name)")
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    @Test func validationAndLifecycleRemainIntact() async throws {
        try await Self.withServer { host in
            let malformed = await host.handle(HTTPRequest(method: "POST", body: Data("invalid".utf8)))
            #expect(malformed.statusCode == 400)
            let badVersion = await host.handle(try Self.request("tools/list", headers: [
                "MCP-Protocol-Version": "unsupported",
            ]))
            #expect(badVersion.statusCode == 400)
            let badOrigin = await host.handle(try Self.request("tools/list", headers: [
                "Origin": "https://example.com",
            ]))
            #expect(badOrigin.statusCode == 403)
            _ = try Self.result(await host.handle(Self.request("tools/list")))

            await host.stop()
            let stopped = await host.handle(try Self.initialize(client: "after-stop"))
            #expect(stopped.statusCode == 503)
            await host.restart()
            _ = try Self.result(await host.handle(Self.initialize(client: "after-restart")))
        }
    }

    private static func withServer(
        _ body: @Sendable (PasteItMCPServer) async throws -> Void
    ) async throws {
        let host = PasteItMCPServer()
        await host.restart()
        // Close transports if a regression leaves response waiters outstanding.
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            await host.stop()
        }
        defer { watchdog.cancel() }
        do {
            try await body(host)
            await host.stop()
        } catch {
            await host.stop()
            throw error
        }
    }

    private static func initialize(client: String) throws -> HTTPRequest {
        try request("initialize", params: [
            "protocolVersion": "2025-11-25",
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string(client), "version": "test"]),
        ])
    }

    private static func request(
        _ method: String, id: Int? = 1, params: [String: Value] = [:],
        headers: [String: String] = [:]
    ) throws -> HTTPRequest {
        var payload: [String: Value] = [
            "jsonrpc": "2.0", "method": .string(method), "params": .object(params),
        ]
        if let id { payload["id"] = .int(id) }
        var requestHeaders = ["Content-Type": "application/json", "Accept": "application/json"]
        requestHeaders.merge(headers) { _, new in new }
        return HTTPRequest(method: "POST", headers: requestHeaders,
                           body: try JSONEncoder().encode(payload), path: "/mcp")
    }

    private static func result(_ response: HTTPResponse) throws -> [String: Value] {
        #expect(response.statusCode == 200)
        #expect(!response.headers.keys.contains { $0.lowercased() == "mcp-session-id" })
        let data = try #require(response.bodyData)
        let payload = try JSONDecoder().decode([String: Value].self, from: data)
        #expect(payload["id"]?.intValue == 1)
        #expect(payload["error"] == nil)
        return try #require(payload["result"]?.objectValue)
    }
}
