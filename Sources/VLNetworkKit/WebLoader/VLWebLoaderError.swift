import Foundation
import VLBundleKit

public enum VLWebLoaderError: Error, LocalizedError
{
 case invalidURL(String)
 case javascriptEvaluationFailed(any Error)
 case unexpectedResultType(expected: String, received: String)

 public var errorDescription: String?
 {
  // The catalog keys hold the formats, the values are inserted after the lookup
  switch self
  {
   case .invalidURL(let url):
    let format = Bundle.main.localizedString("I18N-VLNetworkKit.InvalidURL(%@)", fallbackModule: .module)
    return String(format: format, url)

   case .javascriptEvaluationFailed(let error):
    let format = Bundle.main.localizedString("I18N-VLNetworkKit.javascriptEvaluationFailed(%@)", fallbackModule: .module)
    return String(format: format, error.localizedDescription)

   case .unexpectedResultType(let expected, let received):
    let format = Bundle.main.localizedString("I18N-VLNetworkKit.unexpectedResultType(%@, %@)", fallbackModule: .module)
    return String(format: format, expected, received)
  }
 }
}
