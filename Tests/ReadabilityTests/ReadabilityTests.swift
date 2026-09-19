import Foundation
import Testing
import WebKit
@testable import Readability
@testable import ReadabilityCore

@MainActor
struct ParseResolverTests {
    // ParseResolver only retains this to keep a real WKWebView/message handler alive
    // for the duration of a real parse; it's inert for these unit tests.
    private static func dummyKeepAlive() -> (WKWebView, AnyObject) {
        (WKWebView(), NSObject())
    }

    @Test
    func resolvingWithSuccessCancelsTheDeadlineAndFinishesOnce() async throws {
        var finishCount = 0
        let expected = try ReadabilityResult.stub()

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReadabilityResult, Swift.Error>) in
            let resolver = ParseResolver(continuation: continuation, keepAlive: Self.dummyKeepAlive()) { finishCount += 1 }
            resolver.armDeadline(withinSeconds: 0.05, with: TestError.timedOut)
            resolver.resolve(.success(expected))
        }

        #expect(result.title == expected.title)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(finishCount == 1)
    }

    @Test
    func deadlineFiresWhenNoOutcomeArrives() async {
        var finishCount = 0

        await #expect(throws: TestError.timedOut) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReadabilityResult, Swift.Error>) in
                let resolver = ParseResolver(continuation: continuation, keepAlive: Self.dummyKeepAlive()) { finishCount += 1 }
                resolver.armDeadline(withinSeconds: 0.05, with: TestError.timedOut)
            }
        }

        #expect(finishCount == 1)
    }

    @Test
    func resolvingTwiceIsANoOp() async throws {
        var finishCount = 0
        let expected = try ReadabilityResult.stub()

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReadabilityResult, Swift.Error>) in
            let resolver = ParseResolver(continuation: continuation, keepAlive: Self.dummyKeepAlive()) { finishCount += 1 }
            resolver.armDeadline(withinSeconds: 0.05, with: TestError.timedOut)
            resolver.resolve(.success(expected))
            resolver.resolve(.failure(TestError.timedOut))
        }

        #expect(result.title == expected.title)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(finishCount == 1)
    }
}

private enum TestError: Swift.Error, Equatable {
    case timedOut
}

// Serialized rather than parallel: each test spins up its own WKWebView, and all
// four running concurrently on a resource-constrained CI runner (e.g. GitHub
// Actions' xcode-27 preview image) can starve WebContent/GPU/Networking process
// launches badly enough to blow through parseDeadline on an otherwise-passing test.
@Suite(.serialized)
@MainActor
struct ReadabilityRunnerIntegrationTests {
    // Reproduces the PR #7 repro: a short intro paragraph, a list of links, and one
    // paragraph just long enough to score under isProbablyReaderable's threshold —
    // isProbablyReaderable says "unavailable" but Readability.parse() succeeds.
    @Test
    func parsesContentThatIsProbablyReaderableWouldRejectButReadabilityCanParse() async throws {
        let html = """
        <html><body>
        <article>
        <p>A short intro line that is not long enough to score on its own.</p>
        <ul>
        <li><a href="https://example.com/1">Link one</a></li>
        <li><a href="https://example.com/2">Link two</a></li>
        <li><a href="https://example.com/3">Link three</a></li>
        </ul>
        <p>\(String(repeating: "Disclosure text that pads this paragraph out. ", count: 10))</p>
        </article>
        </body></html>
        """

        let result = try await Readability().parse(html: html, options: nil, baseURL: nil)
        #expect(!result.textContent.isEmpty)
    }

    @Test
    func emptyDocumentThrows() async throws {
        // That an undecodable parse resolves promptly (rather than waiting out the
        // 10s deadline) is covered at the unit level by ParseResolverTests, where
        // process launch time can't confound the timing. This only checks that the
        // runner routes an empty document to a thrown error at all.
        await #expect(throws: (any Swift.Error).self) {
            _ = try await Readability().parse(html: "<html><body></body></html>", options: nil, baseURL: nil)
        }
    }

    @Test
    func sanitizedOptionParsesANormalArticle() async throws {
        let html = """
        <html><body>
        <article>
        <h1>Title</h1>
        <p>\(String(repeating: "This is a normal article with enough content to parse. ", count: 20))</p>
        </article>
        </body></html>
        """

        let result = try await Readability().parse(
            html: html,
            options: .init(shouldSanitize: true),
            baseURL: nil
        )
        #expect(!result.textContent.isEmpty)
    }

    // Pins the fix for concurrent parse() calls on one Readability instance racing
    // over a shared WKWebView (stale navigation cancellation / leaked user scripts).
    @Test
    func concurrentParsesOnTheSameInstanceBothResolveCorrectly() async throws {
        let readability = Readability()

        func makeHTML(title: String) -> String {
            """
            <html><head><title>\(title)</title></head><body><article>
            <h1>\(title)</h1>
            <p>\(String(repeating: "Enough content to be parsed by Readability. ", count: 20))</p>
            </article></body></html>
            """
        }

        async let first = readability.parse(html: makeHTML(title: "First"), options: nil, baseURL: nil)
        async let second = readability.parse(html: makeHTML(title: "Second"), options: nil, baseURL: nil)

        let (firstResult, secondResult) = try await (first, second)
        #expect(firstResult.title == "First")
        #expect(secondResult.title == "Second")
    }
}

extension ReadabilityResult {
    fileprivate static func stub() throws -> ReadabilityResult {
        let json = """
        {
            "title": "Title",
            "byline": null,
            "content": "<p>Body</p>",
            "textContent": "Body",
            "length": 4,
            "excerpt": "Body",
            "siteName": null,
            "lang": null,
            "dir": null,
            "publishedTime": null
        }
        """
        return try JSONDecoder().decode(ReadabilityResult.self, from: Data(json.utf8))
    }
}
