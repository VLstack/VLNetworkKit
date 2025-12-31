import SwiftUI
import VLBundleKit
import VLstackNamespace

extension VLstack
{
 public enum WebLoaderError: Error, LocalizedError
 {
  case invalidURL(String)
  case javascriptEvaluationFailed(Error)
  case unexpectedResultType(expected: String, received: String)

  public var errorDescription: String?
  {
   switch self
   {
    case .invalidURL(let url):
     return Bundle.main.localizedString("I18N-VLNetworkKit.InvalidURL(\(url))", fallbackModule: .module)

    case .javascriptEvaluationFailed(let error):
     return Bundle.main.localizedString("I18N-VLNetworkKit.javascriptEvaluationFailed(\(error.localizedDescription))", fallbackModule: .module)

    case .unexpectedResultType(let expected, let received):
     return Bundle.main.localizedString("I18N-VLNetworkKit.unexpectedResultType(\(expected), \(received))", fallbackModule: .module)
   }
  }
 }
}
