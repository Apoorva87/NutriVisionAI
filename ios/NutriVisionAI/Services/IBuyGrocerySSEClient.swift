// IBuyGrocerySSEClient — Minimal SSE consumer for the iBuyGrocery /events/list/{id} stream.
// Delivers `item_resolved` payloads so the UI can update a single list item without refetching.
//
// Format from sse-starlette:
//   event: ready\n
//   data: {"list_id": 1}\n\n
//   event: item_resolved\n
//   data: {"type":"item_resolved","item":{...ListItemOut...}}\n\n
//   event: ping\n
//   data: {}\n\n

import Foundation

@MainActor
final class IBuyGrocerySSEClient: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var isConnected = false
    @Published var lastError: String?

    /// Fired whenever a fresh `item_resolved` payload arrives from the server.
    var onItemResolved: ((IBGListItem) -> Void)?

    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var buffer = Data()
    private var currentEvent = "message"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    func connect(listId: Int) {
        disconnect()
        guard let url = IBuyGroceryClient.shared.eventsURL(listId: listId) else {
            lastError = "Store Prices backend URL is not set."
            return
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var req = URLRequest(url: url)
        // Explicit SSE headers — `Accept: text/event-stream` overrides the
        // JSON Accept we set in `authHeaders()`.
        for (k, v) in IBuyGroceryClient.shared.authHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 3600

        let task = session.dataTask(with: req)
        task.resume()
        self.task = task
    }

    func disconnect() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll()
        currentEvent = "message"
        isConnected = false
    }

    // MARK: - URLSessionDataDelegate

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                                didReceive response: URLResponse,
                                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            Task { @MainActor in self.isConnected = true }
            completionHandler(.allow)
        } else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in
                self.isConnected = false
                switch code {
                case 401, 403:
                    self.lastError = "Backend rejected the API token. Open Settings → Store Prices."
                case 0:
                    self.lastError = "Could not reach Store Prices backend."
                default:
                    self.lastError = "SSE HTTP \(code)"
                }
            }
            completionHandler(.cancel)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                                didReceive data: Data) {
        Task { @MainActor in self.ingest(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            if let error = error as NSError?,
               error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                // intentional disconnect — no-op
                return
            }
            if let error = error {
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - SSE parser

    /// Accepts bytes from the stream and emits complete LF- or CRLF-terminated SSE frames.
    func ingest(_ data: Data) {
        buffer.append(data)
        while let range = frameDelimiter(in: buffer) {
            let chunk = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let text = String(data: chunk, encoding: .utf8) {
                parseEvent(text)
            }
        }
    }

    private func frameDelimiter(in data: Data) -> Range<Data.Index>? {
        let lf = data.range(of: Data([0x0a, 0x0a]))  // \n\n
        let crlf = data.range(of: Data([0x0d, 0x0a, 0x0d, 0x0a]))  // \r\n\r\n

        switch (lf, crlf) {
        case let (.some(lf), .some(crlf)):
            return lf.lowerBound < crlf.lowerBound ? lf : crlf
        case let (.some(lf), .none):
            return lf
        case let (.none, .some(crlf)):
            return crlf
        case (.none, .none):
            return nil
        }
    }

    private func parseEvent(_ text: String) {
        var event = "message"
        var dataLines: [String] = []
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalizedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line)
            if trimmed.hasPrefix("event:") {
                event = String(trimmed.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("data:") {
                dataLines.append(String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        currentEvent = event
        let dataString = dataLines.joined(separator: "\n")
        guard !dataString.isEmpty else { return }

        switch event {
        case "item_resolved":
            handleItemResolved(dataString)
        case "ready", "ping":
            return
        default:
            return
        }
    }

    private struct ItemResolvedPayload: Decodable {
        let type: String
        let item: IBGListItem
    }

    private func handleItemResolved(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        do {
            let payload = try decoder.decode(ItemResolvedPayload.self, from: data)
            onItemResolved?(payload.item)
        } catch {
            // non-fatal — just skip malformed frames
            lastError = "SSE decode: \(error.localizedDescription)"
        }
    }
}
