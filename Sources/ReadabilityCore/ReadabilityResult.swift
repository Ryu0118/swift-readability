import Foundation

/// A structure representing the result of parsing a web page using Readability.
/// It contains metadata and content extracted from the web page.
public struct ReadabilityResult: Decodable, Sendable {
    /// The title of the article.
    public let title: String
    /// The byline of the article, if available.
    public let byline: String?
    /// The main HTML content of the article.
    public let content: String
    /// The plain text content of the article.
    public let textContent: String
    /// The length of the article content.
    public let length: Int
    /// An excerpt from the article.
    public let excerpt: String
    /// The name of the site where the article originated.
    public let siteName: String?
    /// The language of the article.
    public let language: String?
    /// The text direction (e.g., "ltr", "rtl") of the article, if available.
    public let direction: String?
    /// The published time of the article, if available.
    public let publishedTime: String?

    public enum CodingKeys: String, CodingKey, Sendable {
        case title
        case byline
        case content
        case textContent
        case length
        case excerpt
        case siteName
        case language = "lang"
        case direction = "dir"
        case publishedTime
    }
}
