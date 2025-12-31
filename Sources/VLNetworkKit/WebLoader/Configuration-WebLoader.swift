import Foundation
import VLstackNamespace
import WebKit

extension VLstack.WebLoader
{
 public struct Configuration: Sendable
 {
  public enum PreprocessingTiming: Sendable
  {
   case beforeStopObserver
   case afterStopObserver
  }

  public let allowsContentJavaScript: Bool
  public let blockResources: Bool
  public let cookies: [ HTTPCookie ]
  public let preferredContentMode: WKWebpagePreferences.ContentMode
  public let preProcessingJavaScript: String?
  public let preProcessingTiming: VLstack.WebLoader.Configuration.PreprocessingTiming
  public let timeout: TimeInterval
  public let userAgent: String?
  public let useEphemeralCookies: Bool

  public init(allowsContentJavaScript: Bool = true,
              blockResources: Bool = true,
              cookies: [ HTTPCookie ] = [],
              preferredContentMode: WKWebpagePreferences.ContentMode = .recommended,
              preProcessingJavaScript: String? = nil,
              preProcessingTiming: VLstack.WebLoader.Configuration.PreprocessingTiming = .beforeStopObserver,
              timeout: TimeInterval = 30,
              userAgent: String? = nil,
              useEphemeralCookies: Bool = true)
  {
   self.allowsContentJavaScript = allowsContentJavaScript
   self.blockResources = blockResources
   self.cookies = cookies
   self.preferredContentMode = preferredContentMode
   self.preProcessingJavaScript = preProcessingJavaScript
   self.preProcessingTiming = preProcessingTiming
   self.timeout = timeout
   self.userAgent = userAgent
   self.useEphemeralCookies = useEphemeralCookies
  }
 }
}

