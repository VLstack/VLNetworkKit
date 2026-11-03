import Foundation
import Testing
@testable import VLNetworkKit

@Suite("Fetcher")
struct FetcherTests
{
 private let fetcher = VLFetcher(configuration: MockURLProtocol.makeConfiguration())

 private func register(statusCode: Int = 200,
                       headers: [String: String] = [ "Content-Type": "text/html; charset=utf-8" ],
                       body: Data = Data("Bonjour".utf8),
                       path: String = "page.html") throws -> URL
 {
  let url = try MockURLProtocol.makeURL(path)
  MockURLProtocol.register(.http(statusCode: statusCode, headers: headers, body: body), for: url)
  return url
 }

 // MARK: - Success
 @Test("Content is decoded as UTF-8 by default")
 func fetchContent() async throws
 {
  let url = try register(body: Data("Crème brûlée".utf8))

  let content = try await fetcher.fetchContent(url: url)

  #expect(content == "Crème brûlée")
 }

 @Test("Data is returned as received")
 func fetchData() async throws
 {
  let body = Data([ 0x89, 0x50, 0x4E, 0x47, 0xFF ])
  let url = try register(headers: [ "Content-Type": "image/png" ], body: body, path: "image.png")

  let data = try await fetcher.fetchData(url: url)

  #expect(data == body)
 }

 @Test("Result describes the response")
 func resultFields() async throws
 {
  let url = try register(headers: [ "Content-Type": "text/html; charset=utf-8", "X-Server": "mock" ])

  let result = try await fetcher.fetch(url: url, decodeAsString: true)

  #expect(result.content == "Bonjour")
  #expect(result.data == Data("Bonjour".utf8))
  #expect(result.size == 7)
  #expect(result.statusCode == 200)
  #expect(result.isSuccess)
  #expect(result.contentType == "text/html; charset=utf-8")
  #expect(result.headers["X-Server"] == "mock")
  #expect(result.url == url)
 }

 @Test("Content stays empty when not decoded")
 func contentNotDecoded() async throws
 {
  let url = try register()

  let result = try await fetcher.fetch(url: url)

  #expect(result.content.isEmpty)
  #expect(result.size == 7)
 }

 // MARK: - Options
 @Test("Additional headers are sent")
 func additionalHeaders() async throws
 {
  let url = try register()

  _ = try await fetcher.fetchContent(url: url,
                                     options: [ .additionalHeaders([ "X-Test": "1", "Accept-Language": "fr" ]) ])

  let request = try #require(MockURLProtocol.receivedRequest(for: url))
  #expect(request.value(forHTTPHeaderField: "X-Test") == "1")
  #expect(request.value(forHTTPHeaderField: "Accept-Language") == "fr")
 }

 @Test("Timeout is 30 s by default and can be changed")
 func timeoutOption() async throws
 {
  let defaultURL = try register()
  let customURL = try register()

  _ = try await fetcher.fetchContent(url: defaultURL)
  _ = try await fetcher.fetchContent(url: customURL, options: [ .timeout(5) ])

  #expect(MockURLProtocol.receivedRequest(for: defaultURL)?.timeoutInterval == 30)
  #expect(MockURLProtocol.receivedRequest(for: customURL)?.timeoutInterval == 5)
 }

 @Test("Expected content type ignores parameters and case",
       arguments: [ "text/html", "Text/HTML", "text/html; charset=iso-8859-1" ])
 func expectedContentTypeMatches(_ expected: String) async throws
 {
  let url = try register(headers: [ "Content-Type": "text/html; charset=UTF-8" ])

  let content = try await fetcher.fetchContent(url: url, options: [ .expectedContentType(expected) ])

  #expect(content == "Bonjour")
 }

 @Test("Other content type is refused")
 func expectedContentTypeMismatch() async throws
 {
  let url = try register()

  let error = await #expect(throws: VLFetchError.self)
  {
   try await fetcher.fetchContent(url: url, options: [ .expectedContentType("application/json") ])
  }

  #expect(error?.label == "contentTypeMismatch")
 }

 // MARK: - Encoding
 @Test("Invalid bytes give a decoding error")
 func decodingError() async throws
 {
  let url = try register(body: Data([ 0xFF, 0xFE, 0xFD ]))

  let error = await #expect(throws: VLFetchError.self)
  {
   try await fetcher.fetchContent(url: url)
  }

  #expect(error?.label == "decodingError")
 }

 @Test("Encoding option is used")
 func encodingOption() async throws
 {
  let body = try #require("Crème brûlée".data(using: .isoLatin1))
  let url = try register(body: body)

  let content = try await fetcher.fetchContent(url: url, options: [ .encoding(.isoLatin1) ])

  #expect(content == "Crème brûlée")
 }

 /// Expected to fail until fixed (TODO, probable error 4): the charset announced by the server is ignored
 @Test("Charset announced by the server is used")
 func serverCharset() async throws
 {
  let body = try #require("Crème brûlée".data(using: .isoLatin1))
  let url = try register(headers: [ "Content-Type": "text/html; charset=ISO-8859-1" ], body: body)

  let content = try await fetcher.fetchContent(url: url)

  #expect(content == "Crème brûlée")
 }

 @Test("Encoding option wins over the charset announced by the server")
 func encodingOptionWins() async throws
 {
  let body = try #require("Crème brûlée".data(using: .isoLatin1))
  let url = try register(headers: [ "Content-Type": "text/html; charset=utf-8" ], body: body)

  let content = try await fetcher.fetchContent(url: url, options: [ .encoding(.isoLatin1) ])

  #expect(content == "Crème brûlée")
 }

 // MARK: - Errors
 @Test("HTTP status outside 2xx is an error",
       arguments: [ 404, 500 ])
 func httpError(_ statusCode: Int) async throws
 {
  let url = try register(statusCode: statusCode)

  let error = await #expect(throws: VLFetchError.self)
  {
   try await fetcher.fetchContent(url: url)
  }

  #expect(error?.label == "httpError(\(statusCode))")
 }

 @Test("Response that is not HTTP is invalid")
 func invalidResponse() async throws
 {
  let url = try MockURLProtocol.makeURL()
  MockURLProtocol.register(.notHTTP(body: Data("Bonjour".utf8)), for: url)

  let error = await #expect(throws: VLFetchError.self)
  {
   try await fetcher.fetchContent(url: url)
  }

  #expect(error?.label == "invalidResponse")
 }

 @Test("Network error is passed through")
 func networkError() async throws
 {
  let url = try MockURLProtocol.makeURL()
  MockURLProtocol.register(.failure(URLError(.notConnectedToInternet)), for: url)

  let error = await #expect(throws: URLError.self)
  {
   try await fetcher.fetchContent(url: url)
  }

  #expect(error?.code == .notConnectedToInternet)
 }

 /// Expected to fail until fixed (TODO, fragility 5): `VLFetchError.timeout` is never thrown
 @Test("Timed out request gives the timeout error")
 func timeoutError() async throws
 {
  let url = try MockURLProtocol.makeURL()
  MockURLProtocol.register(.failure(URLError(.timedOut)), for: url)

  let error = await #expect(throws: VLFetchError.self)
  {
   try await fetcher.fetchContent(url: url)
  }

  #expect(error?.label == "timeout")
 }
}

// MARK: - Comparison helper
private extension VLFetchError
{
 /// Readable name of the case, to compare errors without making `VLFetchError` equatable
 var label: String
 {
  switch self
  {
   case .invalidResponse:           "invalidResponse"
   case .contentTypeMismatch:       "contentTypeMismatch"
   case .httpError(let statusCode): "httpError(\(statusCode))"
   case .decodingError:             "decodingError"
   case .timeout:                   "timeout"
  }
 }
}
