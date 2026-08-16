import XCTest
@testable import NutriVisionAI

final class IBuyGroceryClientTests: XCTestCase {
    private var originalBaseURL = ""
    private var originalAPIToken: String?

    override func setUp() {
        super.setUp()
        let client = IBuyGroceryClient.shared
        originalBaseURL = client.baseURL
        originalAPIToken = client.apiToken
    }

    override func tearDown() {
        let client = IBuyGroceryClient.shared
        client.baseURL = originalBaseURL
        client.setAPIToken(originalAPIToken)
        super.tearDown()
    }

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

    @MainActor
    func testSSEIngestDeliversItemResolvedFromCRLFAndLFFrames() {
        let client = IBuyGrocerySSEClient()
        var received: [IBGListItem] = []
        client.onItemResolved = { received.append($0) }

        client.ingest(Data("event: item_resolved\\r\\ndata: {\\\"type\\\":\\\"item_resolved\\\",\\\"item\\\":{\\\"id\\\":7,\\\"raw_text\\\":\\\"milk\\\",\\\"state\\\":\\\"recommended\\\",\\\"position\\\":0,\\\"recommended\\\":null,\\\"selected_candidate_id\\\":null,\\\"search_progress\\\":null}}\\r\\n\\r\\n".utf8))
        client.ingest(Data("event: item_resolved\\ndata: {\\\"type\\\":\\\"item_resolved\\\",\\\"item\\\":{\\\"id\\\":8,\\\"raw_text\\\":\\\"bread\\\",\\\"state\\\":\\\"recommended\\\",\\\"position\\\":1,\\\"recommended\\\":null,\\\"selected_candidate_id\\\":null,\\\"search_progress\\\":null}}\\n\\n".utf8))

        XCTAssertEqual(received.map(\.id), [7, 8])
        XCTAssertEqual(received.map(\.rawText), ["milk", "bread"])
    }

    func testLocalCartSeedingSkipsExistingRemoteLinesAndDuplicateSeeds() {
        let existing = [
            IBGListItem(
                id: 1, rawText: "Milk", state: .recommended, position: 0,
                recommended: nil, selectedCandidateId: nil, searchProgress: nil
            )
        ]

        let missing = GroceryStorePricesView.linesToSeed(
            [" milk ", "bananas", "BANANAS", ""],
            absentFrom: existing
        )

        XCTAssertEqual(missing, ["bananas"])
    }
}
