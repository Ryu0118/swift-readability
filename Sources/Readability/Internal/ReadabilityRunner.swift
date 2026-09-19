import Foundation
import ReadabilityCore
import SwiftUI
import WebKit

/// A runner class responsible for processing HTML content and producing a `ReadabilityResult`.
/// This class uses a WKWebView to load HTML and execute JavaScript for parsing.
@MainActor
final class ReadabilityRunner {
    // The script loader for fetching JavaScript resources from the bundle.
    private let scriptLoader = ScriptLoader(bundle: .module)

    private let encoder = JSONEncoder()

    init() {}

    /// Parses `html` using a dedicated `WKWebView` for this call.
    ///
    /// A fresh web view is created per call (rather than reused across calls) so that
    /// concurrent `parseHTML` invocations on the same `ReadabilityRunner` don't race:
    /// a shared web view would have its in-flight navigation cancelled by a second
    /// `loadHTMLString`, and its accumulated user scripts (each carrying that call's
    /// own `__READABILITY_OPTION__` substitution) would leak into later parses.
    func parseHTML(
        _ html: String,
        options: Readability.Options?,
        baseURL: URL? = nil
    ) async throws -> ReadabilityResult {
        let shouldSanitize = options?.shouldSanitize ?? false
        let script = try await scriptLoader
            .load(shouldSanitize ? .readabilitySanitized : .readabilityBasic)
            .replacingOccurrences(
                of: "__READABILITY_OPTION__",
                with: generateJSONOptions(options: options)
            )

        let configuration = WKWebViewConfiguration()
        let messageHandler = ReadabilityMessageHandler(
            mode: .generateReadabilityResult,
            readerContentGenerator: EmptyContentGenerator()
        )
        configuration.userContentController.add(messageHandler, name: "readabilityMessageHandler")

        let endScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(endScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(html, baseURL: baseURL)

        return try await withCheckedThrowingContinuation { continuation in
            // Keep the web view and message handler alive for the duration of the
            // continuation: both are otherwise unowned once this function returns.
            let resolver = ParseResolver(continuation: continuation, keepAlive: (webView, messageHandler)) {
                messageHandler.subscribeEvent(nil)
            }

            // `isProbablyReaderable` is only a hint the page script emits before it
            // attempts to parse; it can under-count pages made of lists/tables/figures.
            // Treat it as advisory and let the actual parse outcome decide, bounded by
            // an overall deadline so a page that never produces a terminal event
            // (e.g. the injected script fails to run) still resolves.
            resolver.armDeadline(withinSeconds: Self.parseDeadline, with: Error.readerIsUnavailable)

            messageHandler.subscribeEvent { event in
                switch event {
                case let .contentParsed(readabilityResult):
                    resolver.resolve(.success(readabilityResult))
                case .contentParseFailed:
                    resolver.resolve(.failure(Error.readerIsUnavailable))
                case .availabilityChanged:
                    break
                default:
                    break
                }
            }
        }
    }
}

extension ReadabilityRunner {
    /// The maximum time to wait for a terminal parse outcome (`contentParsed` or a
    /// failed/undecodable parse) before giving up. This has to outlast the page
    /// script's own work — clone/serialize, sanitize (when enabled), `Readability.parse()`,
    /// `JSON.stringify`, and the native JSON decode — not just IPC latency.
    fileprivate static let parseDeadline: TimeInterval = 10
}

@MainActor
final class ParseResolver {
    private var continuation: CheckedContinuation<ReadabilityResult, Swift.Error>?
    private var deadlineTask: Task<Void, Never>?
    private let onFinish: () -> Void
    // Retained only so the web view and message handler outlive this call; never read.
    private var keepAlive: (WKWebView, AnyObject)?

    init(
        continuation: CheckedContinuation<ReadabilityResult, Swift.Error>,
        keepAlive: (WKWebView, AnyObject),
        onFinish: @escaping () -> Void
    ) {
        self.continuation = continuation
        self.keepAlive = keepAlive
        self.onFinish = onFinish
    }

    func resolve(_ outcome: Result<ReadabilityResult, Swift.Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        onFinish()
        continuation.resume(with: outcome)
    }

    /// Fails with `error` if no other outcome resolves within `seconds`.
    ///
    /// The task holds `self` strongly: nothing outside this class is guaranteed to
    /// keep the resolver alive for the deadline's duration, so a weak capture here
    /// would let the resolver deallocate before it fires and the continuation would
    /// never resume. `resolve(_:)` cancels this task, breaking the retain cycle.
    func armDeadline(withinSeconds seconds: Double, with error: Swift.Error) {
        guard continuation != nil, deadlineTask == nil else { return }
        deadlineTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.resolve(.failure(error))
        }
    }
}

extension ReadabilityRunner {
    private func generateJSONOptions(options: Readability.Options?) throws -> String {
        if let options = options {
            let data = try encoder.encode(options)
            return String(data: data, encoding: .utf8) ?? "{}"
        } else {
            return "{}"
        }
    }
}

extension ReadabilityRunner {
    /// Errors that can occur during HTML parsing.
    enum Error: Swift.Error {
        /// No usable content was produced: the parse failed/returned nothing, or no
        /// terminal outcome arrived before `ReadabilityRunner.parseDeadline` elapsed.
        case readerIsUnavailable
    }
}

/// A placeholder content generator that conforms to `ReaderContentGeneratable` and does not generate any content.
private struct EmptyContentGenerator: ReaderContentGeneratable {
    func generate(_: ReadabilityResult, initialStyle _: ReaderStyle) async -> String? {
        nil
    }
}
