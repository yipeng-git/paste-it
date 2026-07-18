# Paste It MCP

Local [Model Context Protocol](https://modelcontextprotocol.io) server for agents. **Off by default** — enable from the menu bar **MCP** checkbox after opening Paste It normally.

- MCP URL: `http://127.0.0.1:17321/mcp`
- Transport: **Stateless HTTP** only (`POST /mcp`)
- Bind: loopback only (`127.0.0.1`)
- Mutating the main timeline / capture / settings is **not** exposed

Configure clients with this **HTTP MCP URL** (not a command/args spawn). Paste It must already be running.

## Prerequisites

1. Open Paste It (double-click the app as usual)
2. Right-click the menu bar icon → enable **MCP** (copies the URL automatically)
3. Or use **Copy MCP URL** while MCP is on

## Client config (example)

Point your MCP client at:

```text
http://127.0.0.1:17321/mcp
```

Requests must be JSON-RPC over HTTP with:

- `Content-Type: application/json`
- `Accept: application/json`

## Tools

| Tool | Purpose |
|------|---------|
| `paste_it_health` | `clipCount` + `running` |
| `paste_it_list_clips` | `limit` / `offset` / `type` / `sourceApp` |
| `paste_it_get_clip` | `id` + optional `includeBlobs` |
| `paste_it_search` | `q` / `limit` / … (same query language as the app) |
| `paste_it_render_screenshot` | Ephemeral timeline → screen-region PNG path |

### `paste_it_render_screenshot`

Builds a **throwaway** timeline (does not write main history), shows a temporary glass panel, captures a **screen-region** PNG (so Liquid Glass composites correctly), then destroys the session.

Default output directory:

`~/Library/Application Support/PasteIt/AgentScreenshots/`

Arguments:

```json
{
  "cards": [
    {
      "type": "text",
      "title": "Snippet",
      "plainText": "let x = 1",
      "sourceAppName": "Xcode",
      "sourceBundleIdentifier": "com.apple.dt.Xcode"
    },
    {
      "type": "link",
      "plainText": "https://example.com",
      "linkTitle": "Example",
      "sourceAppName": "Safari",
      "sourceBundleIdentifier": "com.apple.Safari"
    }
  ],
  "ui": { "query": "", "selectedIndex": 0 },
  "outputPath": null
}
```

Result (JSON text content):

```json
{ "path": "/Users/…/AgentScreenshots/render-….png", "width": 1120, "height": 320 }
```

Card fields (all optional except enough content to render):

| Field | Notes |
|-------|--------|
| `type` | `text`, `url` (or `link`), `image`, `file`, … |
| `plainText`, `title`, `htmlText` | Text content |
| `sourceAppName`, `sourceBundleIdentifier` | Source chrome |
| `ocrText`, `linkTitle`, `fileURLString` | Extra metadata |
| `imageBase64` / `imagePath` | Image cards (`imagePath` max 25MB; loaded off the UI thread) |
| `linkImageBase64` | Optional link preview image (skips network fetch when provided) |

For `type: link`/`url` without `linkImageBase64`, render waits for OG image / favicon fetch before capturing. Concurrent renders return a tool error while one is in progress. If the listener ever dies, toggle **MCP** off/on to rebind `:17321`.

## Manual smoke test

```bash
# initialize
curl -s http://127.0.0.1:17321/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'

# tools/list
curl -s http://127.0.0.1:17321/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# tools/call health
curl -s http://127.0.0.1:17321/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"paste_it_health","arguments":{}}}'
```

Old REST paths (`/v1/*`) are not served (404).
