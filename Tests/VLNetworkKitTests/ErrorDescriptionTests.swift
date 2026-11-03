import Foundation
import Testing
@testable import VLNetworkKit

/// Messages must come from the catalog, never as raw keys
///
/// Expected to fail until fixed (TODO, probable error 2) for the cases with a value: the key is built with the value inside
@Suite("Error descriptions")
struct ErrorDescriptionTests
{
 private struct SampleError: LocalizedError
 {
  var errorDescription: String? { "sample failure" }
 }

 private func isTranslated(_ description: String?) -> Bool
 {
  guard let description else { return false }

  return !description.isEmpty && !description.hasPrefix("I18N-")
 }

 @Test("Fetch errors without value are translated",
       arguments: [ VLFetchError.invalidResponse, .contentTypeMismatch, .exceedMaxSize, .decodingError, .timeout ])
 func fetchErrors(_ error: VLFetchError)
 {
  #expect(isTranslated(error.errorDescription))
 }

 @Test("HTTP error is translated with its status code")
 func httpError()
 {
  let description = VLFetchError.httpError(statusCode: 404).errorDescription

  #expect(isTranslated(description))
  #expect(description?.contains("404") == true)
 }

 @Test("Invalid URL is translated with the URL")
 func invalidURL()
 {
  let description = VLWebLoaderError.invalidURL("not an url").errorDescription

  #expect(isTranslated(description))
  #expect(description?.contains("not an url") == true)
 }

 @Test("JavaScript failure is translated with the underlying message")
 func javascriptEvaluationFailed()
 {
  let description = VLWebLoaderError.javascriptEvaluationFailed(SampleError()).errorDescription

  #expect(isTranslated(description))
  #expect(description?.contains("sample failure") == true)
 }

 @Test("Unexpected result type is translated with both types")
 func unexpectedResultType()
 {
  let description = VLWebLoaderError.unexpectedResultType(expected: "String", received: "NSNumber").errorDescription

  #expect(isTranslated(description))
  #expect(description?.contains("String") == true)
  #expect(description?.contains("NSNumber") == true)
 }
}
