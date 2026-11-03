import Foundation
import VLBundleKit

public enum VLFetchError: Error, LocalizedError
{
 case invalidResponse
 case contentTypeMismatch
 case exceedMaxSize
 case httpError(statusCode: Int)
 case decodingError
 case timeout

 public var errorDescription: String?
 {
  switch self
  {
   case .invalidResponse:
    return Bundle.main.localizedString("I18N-VLNetworkKit.ServerAnswerIsInvalid", fallbackModule: .module)

   case .contentTypeMismatch:
    return Bundle.main.localizedString("I18N-VLNetworkKit.ContentTypeMismatch", fallbackModule: .module)

   case .exceedMaxSize:
    return Bundle.main.localizedString("I18N-VLNetworkKit.ExceedMaxSize", fallbackModule: .module)

   case .httpError(let statusCode):
    // The catalog key holds the format, the value is inserted after the lookup
    let format = Bundle.main.localizedString("I18N-VLNetworkKit.HTTPError %lld", fallbackModule: .module)
    return String(format: format, statusCode)

   case .decodingError:
    return Bundle.main.localizedString("I18N-VLNetworkKit.DecodingError", fallbackModule: .module)

   case .timeout:
    return Bundle.main.localizedString("I18N-VLNetworkKit.Timeout", fallbackModule: .module)
  }
 }
}
