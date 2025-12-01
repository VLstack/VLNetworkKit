#  TODO

// MARK: - Exemple d’utilisation
/*
let fetcher = URLFetcher()

// Fetch simple
Task {
do {
let result = try await fetcher.fetch(url: URL(string: “https://api.github.com”)!)
print(“Status: (result.statusCode)”)
print(“Content-Type: (result.contentType ?? “unknown”)”)
print(“Size: (result.size) bytes”)
} catch {
print(“Erreur: (error.localizedDescription)”)
}
}

// Fetch avec options
Task {
do {
let content = try await fetcher.fetchContent(
url: URL(string: “https://api.github.com”)!,
options: [
.expectedContentType(“application/json”),
.maxSize(1_000_000),
.timeout(10),
.additionalHeaders([“User-Agent”: “MyApp/1.0”])
]
)
print(“Contenu: (content)”)
} catch {
print(“Erreur: (error.localizedDescription)”)
}
}
*/
