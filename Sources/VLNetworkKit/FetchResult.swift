import Foundation
import VLstackNamespace

extension VLstack
{
 public struct FetchResult: Sendable
 {
  public let content: String
  public let contentType: String?
  public let data: Data
  public let headers: [String: String]
  public let size: Int
  public let statusCode: Int
  public let url: URL

  public var isSuccess: Bool { (200..<300).contains(statusCode) }  
 }
}
