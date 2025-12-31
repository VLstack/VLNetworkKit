import Foundation
import VLstackNamespace

extension VLstack.WebLoader
{
 public struct Metadata: Sendable
 {
  public let title: String?
  public let description: String?
  public let ogTitle: String?
  public let ogImage: URL?
  public let canonical: URL?
  public let lang: String?
 }
}
