import Foundation
import os
import Testing

/// Fake `URLProtocol` that serves registered answers without network, and records the requests it receives
///
/// Each test registers its answers on its own URL (see `makeURL`), so tests can run in parallel
final class MockURLProtocol: URLProtocol
{
 /// Answer served for a registered URL
 enum Answer: Sendable
 {
  case http(statusCode: Int, headers: [String: String], body: Data)
  case notHTTP(body: Data)
  case failure(URLError)
 }

 private struct State: Sendable
 {
  var answers: [URL: Answer] = [:]
  var requests: [URL: URLRequest] = [:]
 }

 private static let state = OSAllocatedUnfairLock(initialState: State())

 // MARK: - Test helpers
 /// Session configuration that routes every request to this protocol
 static func makeConfiguration() -> URLSessionConfiguration
 {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ MockURLProtocol.self ]
  return configuration
 }

 /// Unique URL for a test, so that answers of parallel tests never collide
 static func makeURL(_ path: String = "page.html") throws -> URL
 {
  try #require(URL(string: "https://mock.test/\(UUID().uuidString)/\(path)"))
 }

 static func register(_ answer: Answer,
                      for url: URL)
 {
  state.withLock { $0.answers[url] = answer }
 }

 /// Last request received for `url`, as seen by the protocol (after `URLSession` added its own values)
 static func receivedRequest(for url: URL) -> URLRequest?
 {
  state.withLock { $0.requests[url] }
 }

 // MARK: - URLProtocol
 override class func canInit(with request: URLRequest) -> Bool { true }

 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

 override func startLoading()
 {
  guard let url = request.url
  else
  {
   client?.urlProtocol(self, didFailWithError: URLError(.badURL))
   return
  }

  let request = self.request
  let answer = Self.state.withLock
  {
   state in
   state.requests[url] = request
   return state.answers[url]
  }

  switch answer
  {
   case .http(let statusCode, let headers, let body):
    guard let response = HTTPURLResponse(url: url,
                                         statusCode: statusCode,
                                         httpVersion: "HTTP/1.1",
                                         headerFields: headers)
    else
    {
     client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
     return
    }
    send(response: response, body: body)

   case .notHTTP(let body):
    let response = URLResponse(url: url,
                               mimeType: "text/plain",
                               expectedContentLength: body.count,
                               textEncodingName: nil)
    send(response: response, body: body)

   case .failure(let error):
    client?.urlProtocol(self, didFailWithError: error)

   case nil:
    client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
  }
 }

 override func stopLoading() {}

 private func send(response: URLResponse,
                   body: Data)
 {
  client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
  client?.urlProtocol(self, didLoad: body)
  client?.urlProtocolDidFinishLoading(self)
 }
}
