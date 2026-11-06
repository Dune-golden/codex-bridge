import BridgeMCP
import Foundation
import MCP
import XCTest

final class ModernDiscoveryTests: XCTestCase {
  func testDiscoverAndListToolsWithoutSession() async throws {
    let registry = MCPSessionRegistry(
      boundPort: 8765,
      serverFactory: { _ in await Self.makeServer() },
      statelessServerFactory: { await Self.makeServer() }
    )

    let discovery = await registry.handle(try request("server/discover", id: 1))
    let discoveryResult = try result(from: discovery, id: 1)
    XCTAssertEqual(discoveryResult["resultType"] as? String, "complete")
    XCTAssertTrue((discoveryResult["supportedVersions"] as? [String])?.contains("2026-07-28") == true)

    let listing = await registry.handle(try request("tools/list", id: 2))
    let listingResult = try result(from: listing, id: 2)
    XCTAssertEqual(listingResult["resultType"] as? String, "complete")
    let tools = try XCTUnwrap(listingResult["tools"] as? [[String: Any]])
    XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["fixture"])
    let schema = try XCTUnwrap(tools.first?["inputSchema"] as? [String: Any])
    XCTAssertEqual(schema["type"] as? String, "object")
  }

  private static func makeServer() async -> Server {
    let server = Server(name: "fixture", version: "1", capabilities: .init(tools: .init()))
    await server.withMethodHandler(ListTools.self) { _ in
      ListTools.Result(tools: [.init(name: "fixture", inputSchema: .object(["type": .string("object")]))])
    }
    return server
  }

  private func request(_ method: String, id: Int) throws -> HTTPRequest {
    let version = "2026-07-28"
    let body = try JSONSerialization.data(withJSONObject: [
      "jsonrpc": "2.0",
      "id": id,
      "method": method,
      "params": [
        "_meta": [
          "io.modelcontextprotocol/protocolVersion": version,
          "io.modelcontextprotocol/clientCapabilities": [String: Any](),
        ]
      ],
    ])
    return HTTPRequest(
      method: "POST",
      headers: [
        "Host": "127.0.0.1:8765",
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "Mcp-Method": method,
        "Mcp-Protocol-Version": version,
      ],
      body: body,
      path: "/mcp"
    )
  }

  private func result(from response: HTTPResponse, id: Int) throws -> [String: Any] {
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(response.headers[HTTPHeaderName.contentType], "application/json")
    XCTAssertFalse(response.headers.keys.contains { $0.lowercased() == "mcp-session-id" })
    let data = try XCTUnwrap(response.bodyData)
    let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(envelope["jsonrpc"] as? String, "2.0")
    XCTAssertEqual(envelope["id"] as? Int, id)
    XCTAssertNil(envelope["error"])
    let result = try XCTUnwrap(envelope["result"] as? [String: Any])
    let metadata = try XCTUnwrap(result["_meta"] as? [String: Any])
    XCTAssertNotNil(metadata["io.modelcontextprotocol/serverInfo"] as? [String: Any])
    return result
  }
}
