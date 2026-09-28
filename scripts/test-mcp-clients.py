#!/usr/bin/env python3
"""Read-only MCP connection regression checks against a running local Paste It."""

import concurrent.futures
import http.client
import json


EXPECTED_TOOLS = {
    "paste_it_health", "paste_it_list_clips", "paste_it_get_clip",
    "paste_it_search", "paste_it_render_screenshot",
}


class Client:
    def __init__(self, name):
        self.name = name
        self.protocol = None

    def send(self, method, params=None, notification=False):
        payload = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        # IDs are scoped to a client, so reuse across independent clients is valid.
        if not notification:
            payload["id"] = 1
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.protocol:
            headers["MCP-Protocol-Version"] = self.protocol
        connection = http.client.HTTPConnection("127.0.0.1", 17321, timeout=15)
        try:
            connection.request("POST", "/mcp", body=json.dumps(payload), headers=headers)
            response = connection.getresponse()
            data = response.read()
            assert response.status == (202 if notification else 200), response.status
            assert response.getheader("MCP-Session-Id") is None, "Expected stateless HTTP"
        finally:
            connection.close()
        if notification:
            assert not data, "Notification should receive an empty response"
            return None
        reply = json.loads(data)
        assert reply.get("id") == 1, "Response ID does not match"
        assert "error" not in reply, reply.get("error")
        return reply["result"]

    def initialize(self):
        result = self.send("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": self.name, "version": "regression-test"},
        })
        assert result["serverInfo"]["name"] == "Paste It"
        self.protocol = result["protocolVersion"]
        self.send("notifications/initialized", notification=True)

    def check_tools(self):
        tools = self.send("tools/list")["tools"]
        assert {tool["name"] for tool in tools} == EXPECTED_TOOLS
        result = self.send("tools/call", {"name": "paste_it_health", "arguments": {}})
        assert not result.get("isError", False), "Health tool returned an error"
        health = json.loads(result["content"][0]["text"])
        assert health["ok"] and health["running"]
        # A distinct synthetic result detects responses delivered to another client.
        name = "synthetic_unknown_tool_" + self.name
        result = self.send("tools/call", {"name": name, "arguments": {}})
        assert result.get("isError") is True
        assert result["content"][0]["text"] == "Unknown tool: " + name


def check_concurrent_client(index):
    client = Client("parallel-" + str(index))
    client.initialize()
    client.check_tools()


def main():
    first, second = Client("client-a"), Client("client-b")
    first.initialize()
    second.initialize()
    first.check_tools()
    second.check_tools()
    reconnected = Client("client-a")
    reconnected.initialize()
    reconnected.check_tools()
    second.check_tools()
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
        list(pool.map(check_concurrent_client, range(24)))
    print(json.dumps({
        "independentClients": "passed", "reconnect": "passed",
        "concurrentClients": 24, "reusedRequestIDs": "passed",
        "toolDiscoveryAndHealth": "passed",
    }, indent=2))


if __name__ == "__main__":
    main()
