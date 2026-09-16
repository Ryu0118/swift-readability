import ReadabilityCore
import SwiftUI
import WebKit

/// A runner class responsible for processing HTML content and producing a `ReadabilityResult`.
/// This class uses a WKWebView to load HTML and execute JavaScript for parsing.
@MainActor
final class ReadabilityRunner {
    private let webView: WKWebView

    // The message handler that listens for events from the injected JavaScript.
    private weak var messageHandler: ReadabilityMessageHandler<EmptyContentGenerator>?
    // The script loader for fetching JavaScript resources from the bundle.
    private let scriptLoader = ScriptLoader(bundle: .module)

    private let encoder = JSONEncoder()

    init() {
        let configuration = WKWebViewConfiguration()
        let messageHandler = ReadabilityMessageHandler(
            mode: .generateReadabilityResult,
            readerContentGenerator: EmptyContentGenerator()
        )

        configuration.userContentController.add(messageHandler, name: "readabilityMessageHandler")

        self.messageHandler = messageHandler
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

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

        let endScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        webView.configuration.userContentController.addUserScript(endScript)
        webView.loadHTMLString(html, baseURL: baseURL)

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            let resolver = ParseResolver(continuation: continuation) { [weak self] in
                self?.messageHandler?.subscribeEvent(nil)
            }

            self?.messageHandler?.subscribeEvent { event in
                switch event {
                case let .contentParsed(readabilityResult):
                    resolver.resolve(.success(readabilityResult))
                case let .availabilityChanged(availability):
                    if availability == .unavailable {
                        resolver.failIfNoContentArrives(withinSeconds: 2,
                                                        with: Error.readerIsUnavailable)
                    }
                default:
                    break
                }
            }
        }
    }
}

@MainActor
private final class ParseResolver {
    private var continuation: CheckedContinuation<ReadabilityResult, Swift.Error>?
    private var graceTask: Task<Void, Never>?
    private let onFinish: () -> Void

    init(
        continuation: CheckedContinuation<ReadabilityResult, Swift.Error>,
        onFinish: @escaping () -> Void
    ) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func resolve(_ outcome: Result<ReadabilityResult, Swift.Error>) {
        guard let continuation else { return }
        self.continuation = nil
        graceTask?.cancel()
        graceTask = nil
        onFinish()
        continuation.resume(with: outcome)
    }

    func failIfNoContentArrives(withinSeconds seconds: Double, with error: Swift.Error) {
        guard continuation != nil, graceTask == nil else { return }
        graceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resolve(.failure(error))
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
        /// Indicates that the reader became unavailable during parsing.
        case readerIsUnavailable
    }
}

/// A placeholder content generator that conforms to `ReaderContentGeneratable` and does not generate any content.
private struct EmptyContentGenerator: ReaderContentGeneratable {
    func generate(_: ReadabilityResult, initialStyle _: ReaderStyle) async -> String? {
        nil
    }
}
