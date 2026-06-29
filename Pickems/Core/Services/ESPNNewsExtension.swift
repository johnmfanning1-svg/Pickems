import Foundation

extension ESPNService {
    func fetchNews(limit: Int = 8) async throws -> [ESPNNewsItem] {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/college-football/news?limit=\(limit)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ESPNError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let articles = json["articles"] as? [[String: Any]] else {
            return []
        }

        return articles.prefix(limit).compactMap { article in
            guard let id = article["id"] as? String ?? (article["id"] as? Int).map(String.init),
                  let headline = article["headline"] as? String else { return nil }

            let description = article["description"] as? String
            let images = article["images"] as? [[String: Any]]
            let imageURL = images?.first?["url"] as? String
            let published = article["published"] as? String
            let date = ISO8601DateFormatter().date(from: published ?? "") ?? Date()
            let links = article["links"] as? [String: Any]
            let web = links?["web"] as? [String: Any]
            let href = web?["href"] as? String

            return ESPNNewsItem(
                id: id,
                headline: headline,
                description: description,
                imageURL: imageURL,
                publishedAt: date,
                link: href.flatMap { URL(string: $0) }
            )
        }
    }
}
