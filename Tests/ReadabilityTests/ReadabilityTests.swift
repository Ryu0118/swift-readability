import Foundation
import Testing
@testable import Readability
@testable import ReadabilityCore

@MainActor
struct ParseResolverTests {
    @Test
    func resolvingWithSuccessCancelsTheDeadlineAndFinishesOnce() async throws {
        var finishCount = 0
        let expected = try ReadabilityResult.stub()

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReadabilityResult, Swift.Error>) in
            let resolver = ParseResolver(continuation: continuation) { finishCount += 1 }
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
                let resolver = ParseResolver(continuation: continuation) { finishCount += 1 }
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
            let resolver = ParseResolver(continuation: continuation) { finishCount += 1 }
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
