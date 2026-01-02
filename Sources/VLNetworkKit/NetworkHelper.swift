import Foundation
import VLstackNamespace

extension VLstack
{
 public enum NetworkHelper
 {
  @inlinable
  static public func toAbsoluteURLs(urls: Set<URL>,
                                    baseURL expectedBase: URL?) -> Set<URL>
  {
   let absolutes = urls.compactMap
   {
    url -> URL? in
    guard url.scheme == nil else { return url }

    return URL(string: url.relativeString, relativeTo: expectedBase)
   }

   return Set(absolutes.compactMap(\.absoluteURL))
  }

  @inlinable
  static public func toAbsoluteURLs(urls: Set<String>,
                                    baseURL expectedBase: URL?) -> Set<URL>
  {
   let absolutes = urls.compactMap
   {
    string -> URL? in
    // On essaie d'abord de créer une URL absolue
    if let url = URL(string: string), url.scheme != nil { return url }
    // Sinon, on la résout par rapport à la base URL en paramètre ou founie au constructeur
    return URL(string: string, relativeTo: expectedBase)
   }

   return Set(absolutes.compactMap(\.absoluteURL))
  }

  @inlinable
  static public func toAbsoluteURLStrings(urls: Set<String>,
                                          baseURL expectedBase: URL?) -> Set<String>
  {
   let absolutes = VLstack.NetworkHelper.toAbsoluteURLs(urls: urls,
                                                        baseURL: expectedBase)

   return Set(absolutes.compactMap(\.absoluteString))
  }
 }
}
