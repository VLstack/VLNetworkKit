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

  let (data, response) = try await session.data(for: request)

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
  if let maxSize = config.maxSize
  {
   guard size <= maxSize else { throw VLFetchError.exceedMaxSize }
  }

  let content: String
  if decodeAsString
  {
   guard let decoded = String(data: data, encoding: config.encoding) else { throw VLFetchError.decodingError }
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
  var encoding: String.Encoding
  var expectedContentType: String?
  var maxSize: Int?
  var timeout: TimeInterval
 }

 private func parseOptions(_ options: [ VLFetchOption ]?) -> RequestConfig
 {
  var config = RequestConfig(additionalHeaders: [:],
                             encoding: .utf8,
                             timeout: 30.0)

  options?.forEach
  {
   option in
   switch option
   {
    case .additionalHeaders(let headers): config.additionalHeaders = headers
    case .encoding(let encoding):         config.encoding = encoding
    case .expectedContentType(let type):  config.expectedContentType = type
    case .maxSize(let size):              config.maxSize = size
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
