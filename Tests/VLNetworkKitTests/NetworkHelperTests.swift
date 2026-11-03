import Foundation
import Testing
@testable import VLNetworkKit

@Suite("Network helper")
struct NetworkHelperTests
{
 private let base = URL(string: "https://site.fr/recettes/tarte.html")

 // MARK: - Strings
 @Test("Strings are resolved against the base",
       arguments: [ ("https://cdn.fr/a.jpg", "https://cdn.fr/a.jpg"),
                    ("img/a.jpg", "https://site.fr/recettes/img/a.jpg"),
                    ("/img/a.jpg", "https://site.fr/img/a.jpg"),
                    ("//cdn.site.fr/a.jpg", "https://cdn.site.fr/a.jpg"),
                    ("../a.jpg", "https://site.fr/a.jpg"),
                    ("mon image.jpg", "https://site.fr/recettes/mon%20image.jpg"),
                    ("data:image/png;base64,AAAA", "data:image/png;base64,AAAA") ])
 func resolveString(_ string: String,
                    expected: String)
 {
  let result = VLNetworkHelper.toAbsoluteURLStrings(urls: [ string ], baseURL: base)

  #expect(result == [ expected ])
 }

 @Test("Relative and absolute forms of the same URL are merged")
 func duplicatesAreMerged()
 {
  let result = VLNetworkHelper.toAbsoluteURLs(urls: [ "img/a.jpg", "https://site.fr/recettes/img/a.jpg" ],
                                              baseURL: base)

  #expect(result.count == 1)
  #expect(result.first?.absoluteString == "https://site.fr/recettes/img/a.jpg")
 }

 @Test("Empty string is ignored")
 func emptyStringIsIgnored()
 {
  let result = VLNetworkHelper.toAbsoluteURLs(urls: [ "" ], baseURL: base)

  #expect(result.isEmpty)
 }

 /// Expected to fail until fixed: today the relative URL comes back without scheme, and Yumeo would try to download it
 @Test("Relative string without base is ignored")
 func relativeStringWithoutBaseIsIgnored()
 {
  let result = VLNetworkHelper.toAbsoluteURLs(urls: [ "img/a.jpg", "https://cdn.fr/b.jpg" ], baseURL: nil)

  #expect(result.map(\.absoluteString) == [ "https://cdn.fr/b.jpg" ])
 }

 // MARK: - URLs
 @Test("URLs are resolved against the base")
 func resolveURLs() throws
 {
  let relative = try #require(URL(string: "img/a.jpg"))
  let absolute = try #require(URL(string: "https://cdn.fr/b.jpg"))

  let result = VLNetworkHelper.toAbsoluteURLs(urls: [ relative, absolute ], baseURL: base)

  #expect(Set(result.map(\.absoluteString)) == [ "https://site.fr/recettes/img/a.jpg", "https://cdn.fr/b.jpg" ])
 }

 /// Expected to fail until fixed (same reason as the string variant)
 @Test("Relative URL without base is ignored")
 func relativeURLWithoutBaseIsIgnored() throws
 {
  let relative = try #require(URL(string: "img/a.jpg"))

  let result = VLNetworkHelper.toAbsoluteURLs(urls: [ relative ], baseURL: nil)

  #expect(result.isEmpty)
 }
}
