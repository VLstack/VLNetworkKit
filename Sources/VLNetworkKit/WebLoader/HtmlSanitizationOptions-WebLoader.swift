import VLstackNamespace

extension VLstack.WebLoader
{
 public struct HtmlSanitizationOptions: OptionSet, Sendable
 {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let script = HtmlSanitizationOptions(rawValue: 1 << 0)
  public static let iframe = HtmlSanitizationOptions(rawValue: 1 << 1)
  public static let style  = HtmlSanitizationOptions(rawValue: 1 << 2)
  public static let link   = HtmlSanitizationOptions(rawValue: 1 << 3)

  public static let all: HtmlSanitizationOptions = [ .script, .iframe, .style, .link ]
  public static let nothing: HtmlSanitizationOptions = []
 }
}
