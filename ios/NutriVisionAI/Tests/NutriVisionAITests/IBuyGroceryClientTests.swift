import XCTest
@testable import NutriVisionAI

final class IBuyGroceryClientTests: XCTestCase {
    func testRemoteRequestUsesAPIV1AndAPIKeyHeader() throws {
        let client = IBuyGroceryClient.shared
        client.baseURL = "https://grocery.example.com/"
        client.setAPIToken("sk_search_test")

        XCTAssertEqual(
            try client.requestURL(for: "/healthz").absoluteString,
            "https://grocery.example.com/api/v1/healthz"
        )
        XCTAssertEqual(client.authHeaders()["X-API-Key"], "sk_search_test")
        XCTAssertNil(client.authHeaders()["Authorization"])
    }

    func testHealthAndEventURLsHaveOneAPIV1Prefix() throws {
        let client = IBuyGroceryClient.shared
        client.baseURL = "http://localhost:8766"

        XCTAssertEqual(try client.requestURL(for: "/api/v1/healthz").path, "/api/v1/healthz")
        XCTAssertEqual(client.eventsURL(listId: 42)?.path, "/api/v1/events/list/42")
    }
}
