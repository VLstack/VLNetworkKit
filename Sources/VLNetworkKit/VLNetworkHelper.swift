import Foundation

public enum VLNetworkHelper
{
 /// Resolves relative URLs against `expectedBase`; URLs still without scheme (relative without base) are dropped
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

  return Set(absolutes.map(\.absoluteURL).filter { $0.scheme != nil })
 }

 /// Resolves relative URL strings against `expectedBase`; URLs still without scheme (relative without base) are dropped
 @inlinable
 static public func toAbsoluteURLs(urls: Set<String>,
                                   baseURL expectedBase: URL?) -> Set<URL>
 {
  let absolutes = urls.compactMap
  {
   string -> URL? in
   // An absolute URL is kept as is
   if let url = URL(string: string), url.scheme != nil { return url }
   // Otherwise it is resolved against the given base
   return URL(string: string, relativeTo: expectedBase)
  }

  return Set(absolutes.map(\.absoluteURL).filter { $0.scheme != nil })
 }

 @inlinable
 static public func toAbsoluteURLStrings(urls: Set<String>,
                                         baseURL expectedBase: URL?) -> Set<String>
 {
  let absolutes = VLNetworkHelper.toAbsoluteURLs(urls: urls,
                                                 baseURL: expectedBase)

  return Set(absolutes.map(\.absoluteString))
 }
}
