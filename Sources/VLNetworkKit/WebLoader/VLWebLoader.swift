import Foundation
import WebKit

@MainActor
public final class VLWebLoader: NSObject
{
 @usableFromInline
 internal let baseURL: URL?
 private var domReadyContinuation: CheckedContinuation<Void, Never>?
 private var domReadyTask: Task<Void, Never>?
 /// Set once the page is stable (or the timeout is reached), even if nobody was waiting yet
 private var isDOMReady = false
 private let configuration: VLWebLoader.Configuration
 private var timeoutTask: Task<Void, Never>?
 private let webView: WKWebView

 // MARK: - Init
 private init(baseURL: URL? = nil,
              configuration: VLWebLoader.Configuration? = nil)
 {
  let webLoaderConfiguration: VLWebLoader.Configuration = configuration ?? .init()

  self.baseURL = baseURL
  self.configuration = webLoaderConfiguration

  let config = WKWebViewConfiguration()
  if webLoaderConfiguration.useEphemeralCookies
  {
   config.websiteDataStore = .nonPersistent()
  }

  let profile = WKWebpagePreferences()
  profile.allowsContentJavaScript = webLoaderConfiguration.allowsContentJavaScript
  profile.preferredContentMode = webLoaderConfiguration.preferredContentMode
  config.defaultWebpagePreferences = profile

  let controller = WKUserContentController()
  let script = WKUserScript(source: Self.domObserverJS,
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
  controller.addUserScript(script)
  config.userContentController = controller

  let wv = WKWebView(frame: .zero, configuration: config)
  if let userAgent = configuration?.userAgent
  {
   wv.customUserAgent = userAgent
  }

  self.webView = wv
  super.init()
  // The controller retains its handlers: the relay keeps the loader weak to avoid a retain cycle
  controller.add(WeakScriptMessageHandler(self), name: "domReady")
  self.webView.navigationDelegate = self
 }

 convenience public init(url: URL,
                         configuration: VLWebLoader.Configuration? = nil)
 {
  self.init(baseURL: url, configuration: configuration)
  Task
  {
   @MainActor in
   await setupWebView()
   webView.load(URLRequest(url: url))
  }
 }

 convenience public init(urlString: String,
                         configuration: VLWebLoader.Configuration? = nil) throws
 {
  guard let url = URL(string: urlString) else { throw VLWebLoaderError.invalidURL(urlString) }
  self.init(url: url, configuration: configuration)
 }

 convenience public init(html: String,
                         baseURL: URL? = nil,
                         sanitize: VLWebLoader.HtmlSanitizationOptions = .nothing,
                         configuration: VLWebLoader.Configuration? = nil)
 {
  self.init(baseURL: baseURL, configuration: configuration)
  Task
  {
   @MainActor in
   await setupWebView()

   var injectedHtml: String = html

   if sanitize.contains(.script)
   {
    injectedHtml = injectedHtml.replacing(/(?i)<script\b[^>]*>[\s\S]*?<\/script>/, with: "")
    injectedHtml = injectedHtml.replacing(/(?i)<script\b[^>]*\/>/, with: "")
   }

   if sanitize.contains(.iframe)
   {
    injectedHtml = injectedHtml.replacing(/(?i)<iframe\b[^>]*>[\s\S]*?<\/iframe>/, with: "")
    injectedHtml = injectedHtml.replacing(/(?i)<iframe\b[^>]*\/>/, with: "")
   }

   if sanitize.contains(.style)
   {
    injectedHtml = injectedHtml.replacing(/(?i)<style\b[^>]*>[\s\S]*?<\/style>/, with: "")
   }

   if sanitize.contains(.link)
   {
    injectedHtml = injectedHtml.replacing(/(?i)<link\b[^>]*\/?>/, with: "")
   }

   webView.loadHTMLString(injectedHtml, baseURL: baseURL)
  }
 }

 convenience public init(html: String,
                         baseURLString: String? = nil,
                         sanitize: VLWebLoader.HtmlSanitizationOptions = .nothing,
                         configuration: VLWebLoader.Configuration? = nil) throws
 {
  var baseURL: URL? = nil
  if let baseURLString
  {
   guard let url = URL(string: baseURLString) else { throw VLWebLoaderError.invalidURL(baseURLString) }
   baseURL = url
  }
  self.init(html: html, baseURL: baseURL, sanitize: sanitize, configuration: configuration)
 }

 // MARK: - Deinit
 @MainActor
 deinit
 {
  timeoutTask?.cancel()
  timeoutTask = nil
  domReadyTask?.cancel()
  domReadyTask = nil
  domReadyContinuation = nil
  webView.configuration.userContentController.removeScriptMessageHandler(forName: "domReady")
  webView.navigationDelegate = nil
  webView.stopLoading()
  webView.configuration.userContentController.removeAllUserScripts()
 }

 // MARK: - Continuation
 private func resumeContinuation()
 {
  isDOMReady = true
  timeoutTask?.cancel()
  timeoutTask = nil
  if let continuation = domReadyContinuation
  {
   domReadyContinuation = nil
   continuation.resume()
  }
 }

 // MARK: - Private helper
 /// Identifier of the compiled rule list kept by WebKit: change its version when the rules change
 private static let blockResourcesIdentifier = "VLNetworkKit.WebLoader.blockResources.v1"

 private func blockResources() async
 {
  guard self.configuration.blockResources == true else { return }

  // TODO: find out which of this rule is targeting iframes
  //  {
  //   "trigger": { "url-filter": ".*", "resource-type": [ "document" ], "if-frame-url": [ ".*" ] },
  //   "action": { "type": "block" }
  //  },

  //  {
  //   "trigger": { "url-filter": ".*", "load-context": [ "child-frame" ] },
  //   "action": { "type": "block" }
  //  },

  let rules = """
 [
  {
   "trigger": { "url-filter": ".*", "resource-type": [ "image", "style-sheet", "media", "font" ] },
   "action": { "type": "block" }
  }
 ]
 """

  guard let store = WKContentRuleListStore.default() else { return }

  // The list compiled by a previous loader is reused, it is compiled only the first time
  let ruleList: WKContentRuleList?
  if let compiled = try? await store.contentRuleList(forIdentifier: Self.blockResourcesIdentifier)
  {
   ruleList = compiled
  }
  else
  {
   ruleList = try? await store.compileContentRuleList(forIdentifier: Self.blockResourcesIdentifier,
                                                      encodedContentRuleList: rules)
  }

  guard let ruleList else { return }

  webView.configuration.userContentController.add(ruleList)
 }

 private func clean(string: String) -> String
 {
  string.replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacing(/\ {2,}/, with: " ")
        .replacingOccurrences(of: "\t", with: "  ")
        .replacing(/\n{3,}/, with: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
 }

 /// Empty strings returned by the page mean "no value"
 private static func nonEmpty(_ value: String?) -> String?
 {
  guard let value, !value.isEmpty else { return nil }

  return value
 }

 @MainActor
 private func setupWebView() async
 {
  if !self.configuration.cookies.isEmpty
  {
   let store = webView.configuration.websiteDataStore.httpCookieStore
   for cookie in self.configuration.cookies
   {
    await store.setCookie(cookie)
   }
  }

  if self.configuration.blockResources
  {
   await blockResources()
  }
 }

 // MARK: - Wait for DOM ready
 private func startWaitForDOMReady() async
 {
  // The page may already be stable: its signal came before the first call
  guard !isDOMReady else { return }

  let timeoutNanoseconds = UInt64(self.configuration.timeout * 1_000_000_000)

  await withCheckedContinuation
  {
   continuation in
   self.domReadyContinuation = continuation

   // Timeout in case the DOM never becomes stable (endlessly reloading ads, broken page, endless JS or XHR calls, etc.)
   timeoutTask?.cancel()
   timeoutTask = Task
   {
    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
    guard timeoutTask?.isCancelled == false else { return }
    resumeContinuation()
   }
  }
 }

 private func waitForDOMReady() async
 {
  if let task = domReadyTask
  {
   await task.value
   return
  }

  let task = Task
  {
   await startWaitForDOMReady()
   // Without waiting: `run` would wait for this very task
   try? await execute(js: Self.stopObserverJS)
  }
  domReadyTask = task

  await task.value
 }

 // MARK: - Javascript
 /// Waits for the page, evaluates `js` and returns its result; a JavaScript `null` is returned as nil (for an optional `T`)
 public func getValue<T>(js: String) async throws -> T where T: Sendable
 {
  await waitForDOMReady()

  return try await evaluate(js: js)
 }

 /// Waits for the page, then runs `js`
 public func run(js: String) async throws
 {
  await waitForDOMReady()
  try await execute(js: js)
 }

 private func evaluate<T>(js: String) async throws -> T where T: Sendable
 {
  try await withCheckedThrowingContinuation
  {
   continuation in
   webView.evaluateJavaScript(js)
   {
    result, error in
    let value: Any? = result is NSNull ? nil : result
    if let error { continuation.resume(throwing: VLWebLoaderError.javascriptEvaluationFailed(error)) }
    else if let value = value as? T { continuation.resume(returning: value) }
    else
    {
     let expected = String(describing: T.self)
     let received = result.map { String(describing: type(of: $0)) } ?? "nil"
     continuation.resume(throwing: VLWebLoaderError.unexpectedResultType(expected: expected, received: received))
    }
   }
  }
 }

 private func execute(js: String) async throws
 {
  try await withCheckedThrowingContinuation
  {
   (continuation: CheckedContinuation<Void, any Error>) in
   webView.evaluateJavaScript(js)
   {
    _, error in
    if let error { continuation.resume(throwing: VLWebLoaderError.javascriptEvaluationFailed(error)) }
    else { continuation.resume() }
   }
  }
 }

 // MARK: - High-level API
 public func getAttribute(_ attribute: String,
                          of selector: String) async throws -> String?
 {
  let js = """
 (function()
 {
  const el = \(Self.documentQuerySelector(selector));
  return el ? el.getAttribute(\(Self.javaScriptString(attribute))) : null;
 })();
 """

  return try await getValue(js: js)
 }

 public func getCanonicalURL() async throws -> URL?
 {
  let string: String = try await getValue(js: "(document.querySelector('link[rel=canonical]')?.href) || ''")

  return URL(string: string)
 }

 public func getImagesURL(baseURL expectedBase: URL? = nil) async throws -> Set<URL>
 {
  let urls: Set<String> = try await getImagesURLString()

  return VLNetworkHelper.toAbsoluteURLs(urls: urls,
                                        baseURL: expectedBase ?? self.baseURL)
 }

 public func getImagesURLAbsoluteString(baseURL expectedBase: URL? = nil) async throws -> Set<String>
 {
  let urls: Set<String> = try await getImagesURLString()

  return VLNetworkHelper.toAbsoluteURLStrings(urls: urls,
                                              baseURL: expectedBase ?? self.baseURL)
 }

 public func getImagesURLString() async throws -> Set<String>
 {
  let urls: [ String ] = try await getValue(js: Self.imagesSourcesJS)

  return Set(urls)
 }

 public func getInnerHTML(of selector: String? = nil) async throws -> String
 {
  let node = if let selector { Self.documentQuerySelector(selector) } else { "document.body" }

  return try await getValue(js: "\(node).innerHTML || \"\"")
 }

 public func getInnerText(of selector: String? = nil) async throws -> String
 {
  let node = if let selector { Self.documentQuerySelector(selector) } else { "document.body" }
  let raw: String = try await getValue(js: "\(node).innerText || ''")

  return clean(string: raw)
 }

 public func getLanguage() async throws -> String?
 {
  let lang: String = try await getValue(js: "document.documentElement.getAttribute('lang') || ''")

  return lang.isEmpty ? nil : lang
 }

 public func getLinksURL(baseURL expectedBase: URL? = nil) async throws -> Set<URL>
 {
  let urls: Set<String> = try await getLinksURLString()

  return VLNetworkHelper.toAbsoluteURLs(urls: urls,
                                        baseURL: expectedBase ?? self.baseURL)
 }

 public func getLinksURLAbsoluteString(baseURL expectedBase: URL? = nil) async throws -> Set<String>
 {
  let urls: Set<String> = try await getLinksURLString()

  return VLNetworkHelper.toAbsoluteURLStrings(urls: urls,
                                              baseURL: expectedBase ?? self.baseURL)
 }

 public func getLinksURLString() async throws -> Set<String>
 {
  let strings: [ String ] = try await getValue(js: "Array.from(document.querySelectorAll('a[href]')).map(a => a.href)")

  return Set(strings)
 }

 public func getMetadata() async throws -> Metadata
 {
  let js = """
 ({
   "title": document.title || "",
   "description": document.querySelector("meta[name=description]")?.content || "",
   "ogTitle": document.querySelector('meta[property="og:title"]')?.content || "",
   "ogImage": document.querySelector('meta[property="og:image"]')?.content || "",
   "canonical": document.querySelector("link[rel=canonical]")?.href || "",
   "lang": document.documentElement.getAttribute("lang") || ""
 })
 """

  let dict: [ String: String ] = try await getValue(js: js)

  return Metadata(title: Self.nonEmpty(dict["title"]),
                  description: Self.nonEmpty(dict["description"]),
                  ogTitle: Self.nonEmpty(dict["ogTitle"]),
                  ogImage: Self.nonEmpty(dict["ogImage"]).flatMap(URL.init(string:)),
                  canonical: Self.nonEmpty(dict["canonical"]).flatMap(URL.init(string:)),
                  lang: Self.nonEmpty(dict["lang"]))
 }

 public func getTextContent(of selector: String? = nil) async throws -> String
 {
  let raw: String = try await getValue(js: Self.recursiveTextContentJS(of: selector))

  return clean(string: raw)
 }

 public func removeNodes(_ selectors: [ String ]) async throws
 {
  let nodes = selectors.joined(separator: ", ")
  try await run(js: "\(Self.documentQuerySelectorAll(nodes)).forEach(el => el.remove())")
 }

 public func removeNodes(_ selectors: String...) async throws
 {
  try await removeNodes(selectors)
 }

 public func removeScripts() async throws
 {
  try await removeNodes("script", "noscript")
 }

 public func removeStyles() async throws
 {
  try await removeNodes("style", "link")
 }
}

// MARK: - WKScriptMessageHandler
extension VLWebLoader: WKScriptMessageHandler
{
 public func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage)
 {
  if message.name == "domReady"
  {
   resumeContinuation()
  }
 }
}

/// Forwards the script messages to the loader without retaining it
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler
{
 private weak var loader: VLWebLoader?

 init(_ loader: VLWebLoader)
 {
  self.loader = loader
 }

 func userContentController(_ userContentController: WKUserContentController,
                            didReceive message: WKScriptMessage)
 {
  loader?.userContentController(userContentController, didReceive: message)
 }
}

// MARK: - WKNavigationDelegate
extension VLWebLoader: WKNavigationDelegate
{
 public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
 {
  // Intentionally empty:
  // - needed for WebKit stability
  // - allows adding behaviors later
  // - avoids some bugs with scripts not being injected
 }
}

// MARK: - Injected JS
extension VLWebLoader
{
 internal static func documentQuerySelector(_ selector: String) -> String
 {
  "document.querySelector(\(Self.javaScriptString(selector)))"
 }

 internal static func documentQuerySelectorAll(_ selector: String) -> String
 {
  "document.querySelectorAll(\(Self.javaScriptString(selector)))"
 }

 /// JavaScript string literal of `string`, escaped by JSON encoding: quotes, backslashes and line breaks can never end the string
 internal static func javaScriptString(_ string: String) -> String
 {
  guard let data = try? JSONEncoder().encode(string),
        let literal = String(data: data, encoding: .utf8)
  else { return "\"\"" }

  return literal
 }

 private static let domObserverJS = """
 (function()
 {
  let timeout;
  window.__webLoaderObserver = new MutationObserver(() =>
  {
   clearTimeout(timeout);
   timeout = setTimeout(() => { window.webkit.messageHandlers.domReady.postMessage("ready"); }, 300);
  });
  window.__webLoaderObserver.observe(document, { "childList": true, "subtree": true, "attributes": true });
  timeout = setTimeout(() => { window.webkit.messageHandlers.domReady.postMessage("ready"); }, 1000);
 })();
 """

 private static let stopObserverJS = """
 (function()
 {
  if ( window.__webLoaderObserver )
  {
   window.__webLoaderObserver.disconnect()
   window.__webLoaderObserver = null;
  }
 })();
 """

 private static func recursiveTextContentJS(of selector: String? = nil) -> String
 {
  let node = if let selector { Self.documentQuerySelector(selector) } else { "document.body" }

  return """
  (function extractText(node)
  {
   if (!node) { return ""; }
   const blockTags = new Set([ "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "tr", "td", "th", "blockquote", "pre", "address", "details", "summary", "figure", "figcaption", "dl", "dt", "dd", "fieldset", "legend", "dialog", "hr" ]);
   let text = "";
   for ( const child of node.childNodes )
   {
    if ( child.nodeType === Node.TEXT_NODE )
    {
     const t = child.textContent.replace(/\\n/g, " ").trim();
     if ( t.length > 0 ) { text += t + " "; }
    }
    else if ( child.nodeType === Node.ELEMENT_NODE )
    {
     const tag = child.tagName.toLowerCase();
     if ( tag === "script" || tag === "style" || tag === "noscript" || tag == "img" || tag == "link" || tag == "iframe" ) { continue; }
     if ( tag == "br" || tag == "hr" ) { text = text.trimEnd() + "\\n"; }
     else
     {
      text += extractText(child);
      if ( blockTags.has(tag) ) { text = text.trimEnd() + "\\n"; }
     }
    }
   }

   return text;
  })(\(node));
  """
 }

 private static let imagesSourcesJS: String = """
 (function()
 {
  const rawStrings = new Set();

  // A candidate URL runs up to the next whitespace (it may contain commas); trailing commas end the candidate,
  // otherwise its descriptor ("320w", "2x") runs up to the next comma
  function parseSrcset(srcset)
  {
   if ( !srcset ) { return; }
   let position = 0;
   while ( position < srcset.length )
   {
    while ( position < srcset.length && /[\\s,]/.test(srcset[position]) ) { position++; }
    let end = position;
    while ( end < srcset.length && !/\\s/.test(srcset[end]) ) { end++; }
    let url = srcset.slice(position, end);
    position = end;
    if ( url.endsWith(",") ) { url = url.replace(/,+$/, ""); }
    else
    {
     while ( position < srcset.length && srcset[position] !== "," ) { position++; }
    }
    if ( url ) { rawStrings.add(url); }
   }
  }

  document.querySelectorAll("img").forEach(img =>
  {
   const src = img.getAttribute("src");
   if ( src ) { rawStrings.add(src); }
   parseSrcset(img.getAttribute("srcset"));
  });

  document.querySelectorAll("picture source").forEach(source => { parseSrcset(source.getAttribute("srcset")); });

  return Array.from(rawStrings);
 })()
"""
}
