import Foundation

/// 探测结果：拿到状态码，或者一句人话的失败原因。
enum ConnectionTestOutcome {
    case success(Int)
    case failure(String)
}

/// 轻量的连通性探测：只发一个 GET，看能不能拿到 HTTP 状态码。
final class ConnectionTester: NSObject, URLSessionDataDelegate {
    private static var running: [ConnectionTester] = []

    private var completion: ((ConnectionTestOutcome) -> Void)?
    private var session: URLSession?
    private var trustSelfSigned = false

    static func check(url: URL, trustSelfSigned: Bool, completion: @escaping (ConnectionTestOutcome) -> Void) {
        let tester = ConnectionTester()
        tester.trustSelfSigned = trustSelfSigned
        tester.completion = completion
        running.append(tester)
        tester.start(url: url)
    }

    private func start(url: URL) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        session.dataTask(with: request) { [weak self] _, response, error in
            self?.finish(response: response, error: error)
        }.resume()
    }

    private func finish(response: URLResponse?, error: Error?) {
        let handler = completion
        completion = nil
        guard handler != nil else { return }

        let outcome: ConnectionTestOutcome
        if let error = error {
            outcome = .failure(error.localizedDescription)
        } else if let http = response as? HTTPURLResponse {
            outcome = .success(http.statusCode)
        } else {
            outcome = .success(0)
        }

        DispatchQueue.main.async {
            handler?(outcome)
            self.session?.invalidateAndCancel()
            self.session = nil
            ConnectionTester.running.removeAll { $0 === self }
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           trustSelfSigned,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
