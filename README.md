# VLNetworkKit

Fetching and reading web pages on iOS 17+, written for Swift 6 strict concurrency.

- `VLFetcher` (actor, `URLSession`): downloads a page or a file, with options and translated errors (`VLFetchError`).
- `VLWebLoader` (`@MainActor`, invisible `WKWebView`): loads a URL or an HTML string, waits until the page is stable, then reads its text, images, links, metadata or runs JavaScript.
- `VLNetworkHelper`: resolves relative URLs against a base URL.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/VLstack/VLNetworkKit", from: "3.0.1")
```

## VLFetcher

```swift
let fetcher = VLFetcher()

// Text of a page, decoded with the charset announced by the server (UTF-8 otherwise)
let html = try await fetcher.fetchContent(url: url)

// Raw data, with options
let data = try await fetcher.fetchData(url: imageURL,
                                       options: [ .expectedContentType("image/jpeg"),
                                                  .timeout(10),
                                                  .additionalHeaders([ "Accept-Language": "fr" ]) ])

// Full result: status code, headers, content type, size, final URL
let result = try await fetcher.fetch(url: url, decodeAsString: true)
```

`.encoding(...)` forces the text encoding. Errors are `VLFetchError` (HTTP status, content type, decoding, timeout) or the `URLError` of the session.

## VLWebLoader

```swift
let loader = VLWebLoader(url: url)
// or, from downloaded HTML without scripts, iframes, styles and links
let loader = VLWebLoader(html: html, baseURL: url, sanitize: .all)

try await loader.removeNodes("nav", "footer", ".ads")
let text = try await loader.getTextContent()
let images = try await loader.getImagesURL()   // src, srcset and <picture> sources, absolute
let metadata = try await loader.getMetadata()  // title, description, og:title, og:image, canonical, lang
```

Every call waits until the page is stable (no DOM change for 300 ms, or the timeout of `VLWebLoader.Configuration`, 30 s by default). Images, fonts, styles and media are blocked by default (`blockResources`).

Selectors and attribute names are passed to JavaScript as escaped strings. `getValue(js:)` and `run(js:)` run the given JavaScript as is: never build it from page or user content.

## VLNetworkHelper

```swift
let urls = VLNetworkHelper.toAbsoluteURLs(urls: [ "img/a.jpg", "//cdn.example.com/b.jpg" ],
                                          baseURL: pageURL)
```

Relative URLs that cannot be resolved (no base) are dropped.
