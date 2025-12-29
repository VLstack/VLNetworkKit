import Foundation
import VLstackNamespace
import VLStringKit
import WebKit

extension VLstack
{
 @MainActor
 public final class WebLoader: NSObject
 {
  public struct Metadata
  {
   let title: String?
   let description: String?
   let ogTitle: String?
   let ogImage: URL?
   let canonical: URL?
   let lang: String?
  }

  @usableFromInline
  internal let baseURL: URL?
  private var domReadyContinuation: CheckedContinuation<Void, Never>?
  private var domReadyTask: Task<Void, Never>?
  private let preProcessing: String?
  private let timeout: TimeInterval
  private var timeoutTask: Task<Void, Never>?
  private var webView: WKWebView?

  // MARK: - Init
  private init(baseURL: URL? = nil,
               timeout: TimeInterval? = nil,
               preProcessing: String? = nil)
  {
   self.baseURL = baseURL
   self.timeout = timeout ?? 30
   self.preProcessing = preProcessing

   let config = WKWebViewConfiguration()

   let profile = WKWebpagePreferences()
   profile.allowsContentJavaScript = true
   // Force explicitement la version Mobile
   profile.preferredContentMode = .mobile
   config.defaultWebpagePreferences = profile

   let controller = WKUserContentController()
   let script = WKUserScript(source: Self.domObserverJS,
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: true)
   controller.addUserScript(script)
   config.userContentController = controller

   self.webView = WKWebView(frame: .zero, configuration: config)
   super.init()
   controller.add(self, name: "domReady")
   self.webView?.navigationDelegate = self
  }

  convenience public init(url: URL,
                          timeout: TimeInterval? = nil,
                          preProcessing: String? = nil)
  {
   self.init(baseURL: url, timeout: timeout, preProcessing: preProcessing)
   Task
   {
    @MainActor in
    await blockResources()
    webView?.load(URLRequest(url: url))
   }
  }

  convenience public init(urlString: String,
                          timeout: TimeInterval? = nil,
                          preProcessing: String? = nil) throws
  {
   guard let url = URL(string: urlString) else { throw WebLoaderError.invalidURL(urlString) }
   self.init(url: url, timeout: timeout, preProcessing: preProcessing)
  }

  convenience public init(html: String,
                          baseURL: URL? = nil,
                          timeout: TimeInterval? = nil,
                          preProcessing: String? = nil)
  {
   self.init(baseURL: baseURL, timeout: timeout, preProcessing: preProcessing)
   Task
   {
    @MainActor in
    await blockResources()
    webView?.loadHTMLString(html, baseURL: baseURL)
   }
  }

  convenience public init(html: String,
                          baseURLString: String? = nil,
                          timeout: TimeInterval? = nil,
                          preProcessing: String? = nil) throws
  {
   var baseURL: URL? = nil
   if let baseURLString
   {
    guard let url = URL(string: baseURLString) else { throw WebLoaderError.invalidURL(baseURLString) }
    baseURL = url
   }
   self.init(html: html, baseURL: baseURL, timeout: timeout, preProcessing: preProcessing)
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
   webView?.configuration.userContentController.removeScriptMessageHandler(forName: "domReady")
   webView?.navigationDelegate = nil
   webView?.stopLoading()
   webView?.configuration.userContentController.removeAllUserScripts()
   webView = nil
  }

  // MARK: - Continuation
  private func resumeContinuation()
  {
   timeoutTask?.cancel()
   timeoutTask = nil
   if let continuation = domReadyContinuation
   {
    domReadyContinuation = nil
    continuation.resume()
   }
  }

  // MARK: - Private helper
  private func blockResources() async
  {
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

   guard let store = WKContentRuleListStore.default(),
         let ruleList = try? await store.compileContentRuleList(forIdentifier: "VLNetwork_WebLoader_blockResources",
                                                                encodedContentRuleList: rules)
   else { return }

   webView?.configuration.userContentController.add(ruleList)
  }

  private func clean(string: String) -> String
  {
   string.replacingOccurrences(of: "&nbsp;", with: " ")
         .replacingOccurrences(of: "\u{00A0}", with: " ")
         .replacingOccurrences(of: "  ", with: " ")
         .replacingOccurrences(of: "\t", with: "  ")
         .replacingOccurrences(of: "\n\n\n", with: "\n\n")
         .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @inlinable
  internal func toURLsAbsoluteString(urls: Set<String>,
                                     baseURL expectedBase: URL?) -> Set<String>
  {
   let absolutes = urls.compactMap
   {
    string -> String? in
    // On essaie d'abord de créer une URL absolue
    if let url = URL(string: string), url.scheme != nil { return url.absoluteString }
    // Sinon, on la résout par rapport à la base URL en paramètre ou founie au constructeur
    return URL(string: string, relativeTo: expectedBase ?? self.baseURL)?.absoluteString
   }

   return Set(absolutes)
  }

  // MARK: - Wait for DOM ready
  private func startWaitForDOMReady() async
  {
   await withCheckedContinuation
   {
    continuation in
    self.domReadyContinuation = continuation

    // Déclenche le timeout de vérification au cas ou le DOM ne se stabilise jamais (pub infini qui s'autorecharge, page cassée, js infini, call XHR infini, etc.)
    timeoutTask?.cancel()
    timeoutTask = Task
    {
     try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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
    try? await run(js: Self.stopObserverJS)
    if let preProcessing
    {
     try? await run(js: preProcessing)
    }
   }
   domReadyTask = task

   await task.value
  }

  // MARK: - Javascript
  public func getValue<T>(js: String) async throws -> T where T: Sendable
  {
   try await withCheckedThrowingContinuation
   {
    continuation in
    webView?.evaluateJavaScript(js)
    {
     result, error in
     if let error { continuation.resume(throwing: WebLoaderError.javascriptEvaluationFailed(error)) }
     else if let value = result as? T { continuation.resume(returning: value) }
     else
     {
      let expected = String(describing: T.self)
      let received = result.map { String(describing: type(of: $0)) } ?? "nil"
      continuation.resume(throwing: WebLoaderError.unexpectedResultType(expected: expected, received: received))
     }
    }
   }
  }

  public func run(js: String) async throws
  {
   try await withCheckedThrowingContinuation
   {
    (continuation: CheckedContinuation<Void, Error>) in
    webView?.evaluateJavaScript(js)
    {
     _, error in
     if let error { continuation.resume(throwing: WebLoaderError.javascriptEvaluationFailed(error)) }
     else { continuation.resume() }
    }
   }
  }

  // MARK: - High-level API
  public func getAttribute(_ attribute: String,
                           of selector: String) async throws -> String?
  {
   await waitForDOMReady()
   let js = """
  (function()
  {
   const el = \(Self.documentQuerySelector(selector));
   return el ? el.getAttribute("\(attribute)") : null;
  })();
  """

   return try await getValue(js: js)
  }

  public func getCanonicalURL() async throws -> URL?
  {
   await waitForDOMReady()
   let string: String = try await getValue(js: "(document.querySelector('link[rel=canonical]')?.href) || ''")

   return URL(string: string)
  }

  public func getImagesURL(baseURL: URL? = nil) async throws -> Set<URL>
  {
   let urls = try await getImagesURLAbsoluteString(baseURL: baseURL)

   return Set(urls.compactMap(URL.init))
  }

  public func getImagesURLAbsoluteString(baseURL: URL? = nil) async throws -> Set<String>
  {
   let urls: Set<String> = try await getImagesURLString()

   return toURLsAbsoluteString(urls: urls,
                               baseURL: baseURL)
  }

  public func getImagesURLString() async throws -> Set<String>
  {
   await waitForDOMReady()
   let urls: [ String ] = try await getValue(js: Self.imagesSourcesJS)

   return Set(urls)
  }

  public func getInnerHTML(of selector: String? = nil) async throws -> String
  {
   await waitForDOMReady()
   let node = if let selector { Self.documentQuerySelector(selector) } else { "document.body" }

   return try await getValue(js: "\(node).innerHTML || \"\"")
  }

  public func getInnerText(of selector: String? = nil) async throws -> String
  {
   await waitForDOMReady()
   let node = if let selector { Self.documentQuerySelector(selector) } else { "document.body" }
   let raw: String = try await getValue(js: "\(node).innerText || ''")

   return clean(string: raw)
  }

  public func getLanguage() async throws -> String?
  {
   await waitForDOMReady()
   let lang: String = try await getValue(js: "document.documentElement.getAttribute('lang') || ''")

   return lang.isEmpty ? nil : lang
  }

  public func getLinksURL(baseURL: URL? = nil) async throws -> Set<URL>
  {
   let urls = try await getLinksURLAbsoluteString(baseURL: baseURL)

   return Set(urls.compactMap(URL.init))
  }

  public func getLinksURLAbsoluteString(baseURL: URL? = nil) async throws -> Set<String>
  {
   let urls: Set<String> = try await getLinksURLString()

   return toURLsAbsoluteString(urls: urls, baseURL: baseURL)
  }

  public func getLinksURLString() async throws -> Set<String>
  {
   await waitForDOMReady()
   let strings: [ String ] = try await getValue(js: "Array.from(document.querySelectorAll('a[href]')).map(a => a.href)")

   return Set(strings)
  }

  public func getMetadata() async throws -> Metadata
  {
   await waitForDOMReady()
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

   return Metadata(title: dict["title"],
                   description: dict["description"],
                   ogTitle: dict["ogTitle"],
                   ogImage: (dict["ogImage"]).flatMap(URL.init),
                   canonical: (dict["canonical"]).flatMap(URL.init),
                   lang: dict["lang"])
  }

  public func getTextContent(of selector: String? = nil) async throws -> String
  {
   await waitForDOMReady()
   let raw: String = try await getValue(js: Self.recursiveTextContentJS(of: selector))

   return clean(string: raw)
  }

  public func removeNodes(_ selectors: [ String ]) async throws
  {
   await waitForDOMReady()
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
}

// MARK: - WKScriptMessageHandler
extension VLstack.WebLoader: WKScriptMessageHandler
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

// MARK: - WKNavigationDelegate
extension VLstack.WebLoader: WKNavigationDelegate
{
 public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
 {
  // Intentionnellement vide :
  // - nécessaire pour la stabilité WebKit
  // - permet d'ajouter des comportements plus tard
  // - évite certains bugs de scripts non injectés
 }
}

// MARK: - Injected JS
extension VLstack.WebLoader
{
 @inlinable
 internal static func documentQuerySelector(_ selector: String) -> String
 {
  "document.querySelector('\(Self.selector(selector))')"
 }

 @inlinable
 internal static func documentQuerySelectorAll(_ selector: String) -> String
 {
  "document.querySelectorAll('\(Self.selector(selector))')"
 }

 @inlinable
 internal static func selector(_ string: String) -> String
 {
  string.replacingOccurrences(of: "'", with: "\"")
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

  function parseSrcset(srcset) 
  {
   if ( !srcset ) { return; }
   srcset.split(",").forEach(entry => 
   {
    const parts = entry.trim().split(/\\s+/);
    if ( parts.length > 0 && parts[0] ) { rawStrings.add(parts[0]); }
   });
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
