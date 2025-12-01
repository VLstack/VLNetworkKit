import Foundation
import VLstackNamespace

extension VLstack
{
 public enum FetchOption: Sendable
 {
  case additionalHeaders([String: String])
  case encoding(String.Encoding)
  case expectedContentType(String)
  case maxSize(Int)
  case timeout(TimeInterval)
 }
}
