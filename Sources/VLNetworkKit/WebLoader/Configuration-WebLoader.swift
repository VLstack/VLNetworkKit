import Foundation
import VLstackNamespace
import WebKit

extension VLstack.WebLoader
{
 public struct Configuration: Sendable
 {
  public let allowsContentJavaScript: Bool
  public let blockResources: Bool
  public let cookies: [ HTTPCookie ]
  public let preferredContentMode: WKWebpagePreferences.ContentMode
  public let sanitizeHtmlSourceScripts: Bool
  public let sanitizeHtmlSourceIframes: Bool
  public let timeout: TimeInterval
  public let userAgent: String?
  public let useEphemeralCookies: Bool

  public init(allowsContentJavaScript: Bool = true,
              blockResources: Bool = true,
              cookies: [ HTTPCookie ] = [],
              preferredContentMode: WKWebpagePreferences.ContentMode = .recommended,
              sanitizeHtmlSourceScripts: Bool = false,
              sanitizeHtmlSourceIframes: Bool = false,
              timeout: TimeInterval = 30,
              userAgent: String? = nil,
              useEphemeralCookies: Bool = true)
  {
   self.allowsContentJavaScript = allowsContentJavaScript
   self.blockResources = blockResources
   self.cookies = cookies
   self.preferredContentMode = preferredContentMode
   self.sanitizeHtmlSourceScripts = sanitizeHtmlSourceScripts
   self.sanitizeHtmlSourceIframes = sanitizeHtmlSourceIframes
   self.timeout = timeout
   self.userAgent = userAgent
   self.useEphemeralCookies = useEphemeralCookies
  }
 }
}

