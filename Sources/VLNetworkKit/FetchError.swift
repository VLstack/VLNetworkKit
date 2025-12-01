import SwiftUI
import VLBundleKit
import VLstackNamespace

extension VLstack
{
 public enum FetchError: Error, LocalizedError
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
     return Bundle.main.localizedString("I18N-VLNetworkKit.HTTPError \(statusCode)", fallbackModule: .module)

    case .decodingError:
     return Bundle.main.localizedString("I18N-VLNetworkKit.DecodingError", fallbackModule: .module)

    case .timeout:
     return Bundle.main.localizedString("I18N-VLNetworkKit.Timeout", fallbackModule: .module)
   }
  }
 }
}
