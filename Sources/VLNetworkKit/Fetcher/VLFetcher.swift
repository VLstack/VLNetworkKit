import Foundation

public actor VLFetcher
{
 private let session: URLSession

 public init(configuration: URLSessionConfiguration = .default)
 {
  self.session = URLSession(configuration: configuration)
 }

 // MARK: - Publics
 public func fetch(url: URL,
                   options: [ VLFetchOption ]? = nil,
                   decodeAsString: Bool = false) async throws -> VLFetchResult
 {
  let config = parseOptions(options)
  let request = buildRequest(url: url, config: config)

  let (data, response): (Data, URLResponse)
  do
  {
   (data, response) = try await session.data(for: request)
  }
  catch let error as URLError where error.code == .timedOut
  {
   throw VLFetchError.timeout
  }

  guard let httpResponse = response as? HTTPURLResponse else { throw VLFetchError.invalidResponse }

  guard (200..<300).contains(httpResponse.statusCode) else { throw VLFetchError.httpError(statusCode: httpResponse.statusCode) }

  let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
  if let expected = config.expectedContentType,
     let contentType
  {
   let expectedMime = expected.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
   let foundMime = contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
   guard expectedMime == foundMime else { throw VLFetchError.contentTypeMismatch }
  }

  let size = data.count

  let content: String
  if decodeAsString
  {
   // The encoding option wins, then the charset announced by the server, then UTF-8
   let encoding = config.encoding ?? Self.announcedEncoding(of: httpResponse) ?? .utf8
   guard let decoded = String(data: data, encoding: encoding) else { throw VLFetchError.decodingError }
   content = decoded
  }
  else
  {
   content = ""
  }

  var headers: [String: String] = [:]
  for (k, v) in httpResponse.allHeaderFields
  {
   if let key = k as? String,
       let value = v as? String
   {
    headers[key] = value
   }
  }

  return VLFetchResult(content: content,
                       contentType: contentType,
                       data: data,
                       headers: headers,
                       size: size,
                       statusCode: httpResponse.statusCode,
                       url: httpResponse.url ?? url)
 }

 public func fetchContent(url: URL,
                          options: [ VLFetchOption ]? = nil) async throws -> String
 {
  try await fetch(url: url,
                  options: options,
                  decodeAsString: true).content
 }

 public func fetchData(url: URL,
                       options: [ VLFetchOption ]? = nil) async throws -> Data
 {
  try await fetch(url: url,
                  options: options,
                  decodeAsString: false).data
 }

 // MARK: - Privates
 private struct RequestConfig
 {
  var additionalHeaders: [String: String]
  /// Encoding forced by the caller, nil to use the charset announced by the server
  var encoding: String.Encoding?
  var expectedContentType: String?
  var timeout: TimeInterval
 }

 /// Encoding of the charset announced in the `Content-Type` header, nil if absent or unknown
 private static func announcedEncoding(of response: HTTPURLResponse) -> String.Encoding?
 {
  guard let name = response.textEncodingName else { return nil }

  let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
  guard cfEncoding != kCFStringEncodingInvalidId else { return nil }

  return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
 }

 private func parseOptions(_ options: [ VLFetchOption ]?) -> RequestConfig
 {
  var config = RequestConfig(additionalHeaders: [:],
                             timeout: 30.0)

  options?.forEach
  {
   option in
   switch option
   {
    case .additionalHeaders(let headers): config.additionalHeaders = headers
    case .encoding(let encoding):         config.encoding = encoding
    case .expectedContentType(let type):  config.expectedContentType = type
    case .timeout(let timeout):           config.timeout = timeout
   }
  }

  return config
 }

 private func buildRequest(url: URL,
                           config: RequestConfig) -> URLRequest
 {
  var request = URLRequest(url: url)
  request.timeoutInterval = config.timeout

  for (key, value) in config.additionalHeaders
  {
   request.setValue(value, forHTTPHeaderField: key)
  }

  return request
 }
}
