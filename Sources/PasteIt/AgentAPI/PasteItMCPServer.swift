import Foundation
import MCP
import PasteItCore

/// Official MCP host: `StatelessHTTPServerTransport` + tool handlers.
/// Does not bind a port — pair with `AgentAPIServer` NWListener.
actor PasteItMCPServer {
    static let shared = PasteItMCPServer()

    private var server: Server?
    private var transport: StatelessHTTPServerTransport?
    private var isReady = false

    /// Tears down any existing stack and starts a fresh MCP server + transport.
    func restart() async throws {
        await stop()

        let transport = StatelessHTTPServerTransport()
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let server = Server(
            name: "Paste It",
            version: version,
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: PasteItMCPTools.definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await PasteItMCPTools.call(params)
        }

        try await server.start(transport: transport)

        self.server = server
        self.transport = transport
        self.isReady = true
    }

    func stop() async {
        let server = self.server
        let transport = self.transport
        self.server = nil
        self.transport = nil
        self.isReady = false

        await server?.stop()
        await transport?.disconnect()
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        guard isReady, let transport else {
            return .error(
                statusCode: 503,
                .internalError("MCP transport is not ready")
            )
        }
        return await transport.handleRequest(request)
    }
}

// MARK: - Tools

enum PasteItMCPTools {
    static let definitions: [Tool] = [
        Tool(
            name: "paste_it_health",
            description: "Health check: clip count and whether the local MCP endpoint is running.",
            inputSchema: .object(["type": "object", "properties": [:]]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "paste_it_list_clips",
            description: "List clipboard history clips (newest first). Does not mutate history.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max clips (1–500, default 50)"],
                    "offset": ["type": "integer", "description": "Skip N clips (default 0)"],
                    "type": [
                        "type": "string",
                        "description": "Filter by primary type (text|image|url|file|…)",
                    ],
                    "sourceApp": ["type": "string", "description": "Filter by source app name"],
                ],
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "paste_it_get_clip",
            description: "Get one clip by UUID. Optionally include image blobs as base64.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Clip UUID"],
                    "includeBlobs": [
                        "type": "boolean",
                        "description": "Include image/thumbnail base64 (default false)",
                    ],
                ],
                "required": ["id"],
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "paste_it_search",
            description: "Search clipboard history with the same query language as the app UI.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "q": ["type": "string", "description": "Search query (supports type:, app:)"],
                    "limit": ["type": "integer", "description": "Max results (1–500, default 50)"],
                    "type": ["type": "string", "description": "Filter by primary type"],
                    "sourceApp": ["type": "string", "description": "Filter by source app name"],
                ],
                "required": ["q"],
            ]),
            annotations: .init(readOnlyHint: true)
        ),
        Tool(
            name: "paste_it_render_screenshot",
            description:
                "Render a throwaway ephemeral timeline and capture a screen-region PNG. Does not write to main history.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "cards": [
                        "type": "array",
                        "description": "Cards to seed into the ephemeral timeline",
                    ],
                    "ui": [
                        "type": "object",
                        "description": "Optional UI state: query, selectedType, selectedIndex",
                    ],
                    "outputPath": [
                        "type": "string",
                        "description": "Absolute output PNG path (optional; default AgentScreenshots dir)",
                    ],
                ],
                "required": ["cards"],
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false)
        ),
    ]

    static func call(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            switch params.name {
            case "paste_it_health":
                return try await jsonResult(health())
            case "paste_it_list_clips":
                return try await jsonResult(listClips(arguments: params.arguments))
            case "paste_it_get_clip":
                return try await getClip(arguments: params.arguments)
            case "paste_it_search":
                return try await jsonResult(search(arguments: params.arguments))
            case "paste_it_render_screenshot":
                return try await renderScreenshot(arguments: params.arguments)
            default:
                return errorResult("Unknown tool: \(params.name)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: Handlers

    @MainActor
    private static func health() throws -> some Encodable {
        struct Body: Encodable {
            let ok: Bool
            let clipCount: Int
            let running: Bool
            let version: String
        }
        let runtime = AppRuntime.shared
        return Body(
            ok: true,
            clipCount: runtime.historyStore.clips.count,
            running: AgentAPIServer.shared.isRunning,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        )
    }

    @MainActor
    private static func listClips(arguments: [String: Value]?) throws -> some Encodable {
        let limit = min(max(intArg(arguments, "limit", default: 50), 1), 500)
        let offset = max(intArg(arguments, "offset", default: 0), 0)
        let typeFilter = stringArg(arguments, "type").flatMap { FilterCategory.from(typeToken: $0) } ?? .all
        let sourceApp = stringArg(arguments, "sourceApp")

        let runtime = AppRuntime.shared
        var clips = runtime.historyStore.clips
        if typeFilter != .all {
            clips = clips.filter {
                typeFilter.matches(primaryTypeRaw: $0.primaryType.rawValue, plainText: $0.plainText)
            }
        }
        if let sourceApp, !sourceApp.isEmpty {
            clips = clips.filter { $0.sourceAppName == sourceApp }
        }

        let page = Array(clips.dropFirst(offset).prefix(limit))
        let encoded = page.map {
            HistoryReadDTO.encode($0, blobStore: nil, includeBlobs: false)
        }

        struct Body: Encodable {
            let total: Int
            let offset: Int
            let limit: Int
            let clips: [HistoryReadDTO.Clip]
        }
        return Body(total: clips.count, offset: offset, limit: limit, clips: encoded)
    }

    @MainActor
    private static func getClip(arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let idString = stringArg(arguments, "id"), let id = UUID(uuidString: idString) else {
            return errorResult("Invalid or missing clip id")
        }
        let runtime = AppRuntime.shared
        guard let item = runtime.historyStore.clips.first(where: { $0.id == id }) else {
            return errorResult("Clip not found")
        }
        let includeBlobs = boolArg(arguments, "includeBlobs", default: false)
        let encoded = HistoryReadDTO.encode(
            item,
            blobStore: runtime.historyStore.blobStore,
            includeBlobs: includeBlobs
        )
        return try jsonResult(encoded)
    }

    @MainActor
    private static func search(arguments: [String: Value]?) throws -> some Encodable {
        let q = stringArg(arguments, "q") ?? stringArg(arguments, "query") ?? ""
        let typeFilter = stringArg(arguments, "type").flatMap { FilterCategory.from(typeToken: $0) } ?? .all
        let sourceApp = stringArg(arguments, "sourceApp")
        let limit = min(max(intArg(arguments, "limit", default: 50), 1), 500)

        let runtime = AppRuntime.shared
        let results = runtime.searchService.search(
            clips: runtime.historyStore.clips,
            query: q,
            selectedFilter: typeFilter,
            sourceApp: sourceApp,
            pinboardID: nil,
            foldedHaystack: { item in
                runtime.historyStore.foldedSearchText(for: item)
            }
        )
        let page = Array(results.prefix(limit))
        let encoded = page.map {
            HistoryReadDTO.encode($0, blobStore: nil, includeBlobs: false)
        }

        struct Body: Encodable {
            let query: String
            let total: Int
            let clips: [HistoryReadDTO.Clip]
        }
        return Body(query: q, total: results.count, clips: encoded)
    }

    @MainActor
    private static func renderScreenshot(arguments: [String: Value]?) async throws -> CallTool.Result {
        let payload: RenderScreenshotHandler.Request
        do {
            let object = Value.object(arguments ?? [:])
            let data = try JSONEncoder().encode(object)
            payload = try JSONDecoder().decode(RenderScreenshotHandler.Request.self, from: data)
        } catch {
            return errorResult("Invalid arguments: \(error.localizedDescription)")
        }

        do {
            let result = try await RenderScreenshotHandler.handle(
                payload,
                settings: AppRuntime.shared.settings
            )
            return try jsonResult(result)
        } catch let error as RenderScreenshotHandler.HandlerError {
            return errorResult(error.localizedDescription)
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: Helpers

    private static func jsonResult(_ value: some Encodable) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            isError: false
        )
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }

    private static func intArg(_ args: [String: Value]?, _ key: String, default defaultValue: Int)
        -> Int
    {
        guard let value = args?[key] else { return defaultValue }
        if let int = value.intValue { return int }
        if let double = value.doubleValue { return Int(double) }
        if let string = value.stringValue, let int = Int(string) { return int }
        return defaultValue
    }

    private static func stringArg(_ args: [String: Value]?, _ key: String) -> String? {
        args?[key]?.stringValue
    }

    private static func boolArg(
        _ args: [String: Value]?,
        _ key: String,
        default defaultValue: Bool
    ) -> Bool {
        guard let value = args?[key] else { return defaultValue }
        if let bool = value.boolValue { return bool }
        if let string = value.stringValue {
            let lower = string.lowercased()
            return lower == "true" || lower == "1" || lower == "base64"
        }
        if let int = value.intValue { return int != 0 }
        return defaultValue
    }
}
