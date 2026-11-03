import Foundation
import Testing
@testable import VLNetworkKit

/// Runs a real `WKWebView` on fixed HTML: needs an iOS simulator as destination
@MainActor
@Suite("Web loader", .serialized, .timeLimit(.minutes(1)))
struct WebLoaderTests
{
 private let base = URL(string: "https://site.fr/recettes/tarte.html")

 /// Short timeout, so that a page that never becomes ready does not block the tests for 30 s
 private let configuration = VLWebLoader.Configuration(timeout: 10)

 private func makeLoader(body: String,
                         head: String = "",
                         lang: String? = "fr",
                         sanitize: VLWebLoader.HtmlSanitizationOptions = .nothing,
                         configuration: VLWebLoader.Configuration? = nil) -> VLWebLoader
 {
  let langAttribute = if let lang { " lang=\"\(lang)\"" } else { "" }
  let html = "<!doctype html><html\(langAttribute)><head>\(head)</head><body>\(body)</body></html>"

  return VLWebLoader(html: html,
                     baseURL: base,
                     sanitize: sanitize,
                     configuration: configuration ?? self.configuration)
 }

 // MARK: - Text
 @Test("Blocks are separated by line breaks")
 func textContent() async throws
 {
  let loader = makeLoader(body: "<h1>Tarte</h1><p>Ingrédients</p><ul><li>2 oeufs</li><li>100 g de sucre</li></ul>")

  let text = try await loader.getTextContent()

  #expect(text == "Tarte\nIngrédients\n2 oeufs\n100 g de sucre")
 }

 @Test("Inline elements stay on the same line")
 func inlineText() async throws
 {
  let loader = makeLoader(body: "<p>Bonjour <b>tout</b> le <a href=\"#\">monde</a></p>")

  let text = try await loader.getTextContent()

  #expect(text == "Bonjour tout le monde")
 }

 @Test("Scripts, styles and noscript are not part of the text")
 func textWithoutScripts() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p><script>var x = 1;</script><style>p { color: red; }</style><noscript>Activez JavaScript</noscript>")

  let text = try await loader.getTextContent()

  #expect(text == "Texte")
 }

 @Test("Line break and non-breaking space")
 func lineBreakAndSpace() async throws
 {
  let loader = makeLoader(body: "<p>Ligne 1<br>100&nbsp;g de sucre</p>")

  let text = try await loader.getTextContent()

  #expect(text == "Ligne 1\n100 g de sucre")
 }

 @Test("Text of a selector only")
 func textOfSelector() async throws
 {
  let loader = makeLoader(body: "<div id=\"pub\">Promo</div><div id=\"recette\"><p>Etape 1</p></div><div data-role=\"steps\"><p>Etape 2</p></div>")

  let recipe = try await loader.getTextContent(of: "#recette")
  let steps = try await loader.getTextContent(of: "[data-role='steps']")

  #expect(recipe == "Etape 1")
  #expect(steps == "Etape 2")
 }

 /// Expected to fail until fixed (TODO, fragility 8): double spaces are reduced only once
 @Test("Repeated spaces are reduced to one")
 func repeatedSpaces() async throws
 {
  let loader = makeLoader(body: "<p>a    b</p>")

  let text = try await loader.getTextContent()

  #expect(text == "a b")
 }

 @Test("Nodes can be removed before reading the text")
 func removeNodes() async throws
 {
  let loader = makeLoader(body: "<p>Garder</p><div class=\"pub\">Promo</div><aside>Aussi</aside>")

  try await loader.removeNodes(".pub", "aside")
  let text = try await loader.getTextContent()

  #expect(text == "Garder")
 }

 // MARK: - Images and links
 private let imagesBody = """
 <img src="img/a.jpg">
 <img src="https://cdn.fr/b.jpg" srcset="img/b-320.jpg 320w, img/b-640.jpg 640w">
 <picture><source srcset="img/c.webp 1x, img/c@2x.webp 2x"><img src="img/c.jpg"></picture>
 """

 @Test("Images are read from src, srcset and picture sources")
 func imagesStrings() async throws
 {
  let loader = makeLoader(body: imagesBody)

  let images = try await loader.getImagesURLString()

  #expect(images == [ "img/a.jpg", "https://cdn.fr/b.jpg", "img/b-320.jpg", "img/b-640.jpg", "img/c.webp", "img/c@2x.webp", "img/c.jpg" ])
 }

 @Test("Image paths are resolved against the base URL")
 func imagesAbsolute() async throws
 {
  let loader = makeLoader(body: imagesBody)

  let images = try await loader.getImagesURLAbsoluteString()

  #expect(images.contains("https://site.fr/recettes/img/a.jpg"))
  #expect(images.contains("https://site.fr/recettes/img/c@2x.webp"))
  #expect(images.contains("https://cdn.fr/b.jpg"))
  #expect(images.count == 7)
 }

 /// Expected to fail until fixed (new finding): srcset is split on every comma, also inside an URL
 @Test("Srcset URL may contain commas")
 func srcsetWithCommas() async throws
 {
  let small = "https://res.cloudinary.com/demo/image/upload/w_320,h_200/a.jpg"
  let large = "https://res.cloudinary.com/demo/image/upload/w_640,h_400/a.jpg"
  let loader = makeLoader(body: "<img srcset=\"\(small) 320w, \(large) 640w\">")

  let images = try await loader.getImagesURLString()

  #expect(images == [ small, large ])
 }

 @Test("Links are absolute")
 func links() async throws
 {
  let loader = makeLoader(body: "<a href=\"/autre\">Autre</a><a href=\"https://cdn.fr/x\">X</a><a>Sans lien</a>")

  let links = try await loader.getLinksURLString()

  #expect(links == [ "https://site.fr/autre", "https://cdn.fr/x" ])
 }

 // MARK: - Metadata
 @Test("Metadata are read from the head")
 func metadata() async throws
 {
  let head = """
  <title>Tarte aux pommes</title>
  <meta name="description" content="Une tarte simple">
  <meta property="og:title" content="Tarte OG">
  <meta property="og:image" content="https://cdn.fr/tarte.jpg">
  <link rel="canonical" href="https://site.fr/tarte">
  """
  let loader = makeLoader(body: "<p>Texte</p>", head: head)

  let metadata = try await loader.getMetadata()

  #expect(metadata.title == "Tarte aux pommes")
  #expect(metadata.description == "Une tarte simple")
  #expect(metadata.ogTitle == "Tarte OG")
  #expect(metadata.ogImage?.absoluteString == "https://cdn.fr/tarte.jpg")
  #expect(metadata.canonical?.absoluteString == "https://site.fr/tarte")
  #expect(metadata.lang == "fr")
  #expect(try await loader.getCanonicalURL()?.absoluteString == "https://site.fr/tarte")
  #expect(try await loader.getLanguage() == "fr")
  #expect(try await loader.getAttribute("content", of: "meta[name=description]") == "Une tarte simple")
 }

 /// Expected to fail until fixed (new finding): missing values come back as "" instead of nil
 @Test("Missing metadata are nil")
 func missingMetadata() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>", lang: nil)

  let metadata = try await loader.getMetadata()

  #expect(metadata.title == nil)
  #expect(metadata.description == nil)
  #expect(metadata.ogTitle == nil)
  #expect(metadata.ogImage == nil)
  #expect(metadata.canonical == nil)
  #expect(metadata.lang == nil)
 }

 @Test("Missing language and attribute are nil")
 func missingLanguageAndAttribute() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>", lang: nil)

  #expect(try await loader.getLanguage() == nil)
  #expect(try await loader.getAttribute("content", of: "meta[name=description]") == nil)
 }

 // MARK: - Sanitization
 private let sanitizeHead = "<link rel=\"stylesheet\" href=\"s.css\"><style>p { color: red; }</style>"
 private let sanitizeBody = "<p>Texte</p><SCRIPT>var x = 1;</SCRIPT><iframe src=\"about:blank\"></iframe>"

 private func count(tag: String,
                    in loader: VLWebLoader) async throws -> Int
 {
  // Waits for the page before evaluating
  _ = try await loader.getInnerHTML()

  return try await loader.getValue(js: "document.getElementsByTagName('\(tag)').length")
 }

 @Test("Sanitization removes the chosen elements",
       arguments: [ (VLWebLoader.HtmlSanitizationOptions.script, "script"),
                    (VLWebLoader.HtmlSanitizationOptions.iframe, "iframe"),
                    (VLWebLoader.HtmlSanitizationOptions.style, "style"),
                    (VLWebLoader.HtmlSanitizationOptions.link, "link") ])
 func sanitize(_ option: VLWebLoader.HtmlSanitizationOptions,
               tag: String) async throws
 {
  let loader = makeLoader(body: sanitizeBody, head: sanitizeHead, sanitize: option)

  #expect(try await count(tag: tag, in: loader) == 0)
 }

 @Test("Without sanitization every element stays",
       arguments: [ "script", "iframe", "style", "link" ])
 func noSanitize(_ tag: String) async throws
 {
  let loader = makeLoader(body: sanitizeBody, head: sanitizeHead)

  #expect(try await count(tag: tag, in: loader) == 1)
 }

 // MARK: - Errors
 @Test("Unexpected result type is an error")
 func unexpectedResultType() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>")
  _ = try await loader.getTextContent()

  let error = await #expect(throws: VLWebLoaderError.self)
  {
   let _: String = try await loader.getValue(js: "42")
  }

  #expect(error?.label == "unexpectedResultType")
 }

 @Test("JavaScript exception is an error")
 func javascriptException() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>")
  _ = try await loader.getTextContent()

  let error = await #expect(throws: VLWebLoaderError.self)
  {
   try await loader.run(js: "throw new Error('boom')")
  }

  #expect(error?.label == "javascriptEvaluationFailed")
 }

 @Test("Invalid URL string is refused")
 func invalidURLString()
 {
  let urlError = #expect(throws: VLWebLoaderError.self) { try VLWebLoader(urlString: "") }
  let baseError = #expect(throws: VLWebLoaderError.self) { try VLWebLoader(html: "<p>Texte</p>", baseURLString: "") }

  #expect(urlError?.label == "invalidURL")
  #expect(baseError?.label == "invalidURL")
 }

 // MARK: - Waiting and memory
 @Test("Page that never becomes stable ends at the timeout")
 func timeout() async throws
 {
  let script = "<script>setInterval(() => { document.body.dataset.tick = Date.now(); }, 100);</script>"
  let loader = makeLoader(body: "<p>Texte</p>\(script)", configuration: VLWebLoader.Configuration(timeout: 2))
  let clock = ContinuousClock()
  let start = clock.now

  let text = try await loader.getTextContent()

  let elapsed = clock.now - start
  #expect(text == "Texte")
  #expect(elapsed > .seconds(1.5))
  #expect(elapsed < .seconds(5))
 }

 @Test("Second call does not wait again")
 func secondCall() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>")
  _ = try await loader.getTextContent()
  let clock = ContinuousClock()
  let start = clock.now

  _ = try await loader.getTextContent()

  #expect(clock.now - start < .milliseconds(500))
 }

 /// Expected to fail until fixed (TODO, probable error 3): the "ready" signal is lost when nobody waits for it yet
 @Test("Page already stable before the first call does not wait for the timeout")
 func pageReadyBeforeFirstCall() async throws
 {
  let loader = makeLoader(body: "<p>Texte</p>", configuration: VLWebLoader.Configuration(timeout: 5))
  try await Task.sleep(for: .seconds(3))
  let clock = ContinuousClock()
  let start = clock.now

  let text = try await loader.getTextContent()

  #expect(text == "Texte")
  #expect(clock.now - start < .seconds(1))
 }

 /// Expected to fail until fixed (TODO, probable error 1): the script message handler retains the loader
 @Test("Loader is released after use")
 func loaderIsReleased() async throws
 {
  weak var weakLoader: VLWebLoader?
  do
  {
   let loader = makeLoader(body: "<p>Texte</p>")
   weakLoader = loader
   _ = try await loader.getTextContent()
  }

  // Lets the internal tasks end
  try await Task.sleep(for: .milliseconds(500))

  #expect(weakLoader == nil)
 }
}

// MARK: - Comparison helper
private extension VLWebLoaderError
{
 /// Readable name of the case, to compare errors without making `VLWebLoaderError` equatable
 var label: String
 {
  switch self
  {
   case .invalidURL:                 "invalidURL"
   case .javascriptEvaluationFailed: "javascriptEvaluationFailed"
   case .unexpectedResultType:       "unexpectedResultType"
  }
 }
}
