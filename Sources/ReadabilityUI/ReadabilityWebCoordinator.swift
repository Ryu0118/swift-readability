import SwiftUI
import WebKit
import ReadabilityCore

/// A coordinator that manages a WKWebView configured for reader mode.
/// It sets up the necessary scripts and message handlers to parse content and manage reader mode availability.
@MainActor
public final class ReadabilityWebCoordinator: ObservableObject {
    // A weak reference to the message handler that processes JavaScript messages.
    private weak var messageHandler: ReadabilityMessageHandler<ReaderContentGenerator>?
    // A weak reference to the WKWebView configuration.
    private weak var configuration: WKWebViewConfiguration?

    private let scriptLoader = ScriptLoader(bundle: .module)
    private let messageHandlerName = "readabilityMessageHandler"

    private var (_contentParsed, contentParsedContinuation) = AsyncStream.makeStream(of: String.self)
    private var (_availabilityChanged, availabilityChangedContinuation) = AsyncStream.makeStream(of: ReaderAvailability.self)

    /// An asynchronous stream that emits the generated reader HTML when the content is parsed.
    public var contentParsed: AsyncStream<String> {
        _contentParsed
    }

    /// An asynchronous stream that emits updates to the reader mode availability status.
    public var availabilityChanged: AsyncStream<ReaderAvailability> {
        _availabilityChanged
    }

    /// The initial style to apply to the reader content.
    public let initialStyle: ReaderStyle

    /// Initializes a new `ReadabilityWebCoordinator` with the specified initial style.
    ///
    /// - Parameter initialStyle: The initial `ReaderStyle` to use.
    public init(initialStyle: ReaderStyle) {
        self.initialStyle = initialStyle
    }

    /// Creates and configures a `WKWebViewConfiguration` for reader mode.
    ///
    /// - Returns: A configured `WKWebViewConfiguration` with injected scripts and message handlers.
    /// - Throws: An error if script loading fails.
    public func createReadableWebViewConfiguration() async throws -> WKWebViewConfiguration {
        // Load scripts for document start and document end asynchronously.
        async let documentStartStringTask = scriptLoader.load(.atDocumentStart)
        async let documentEndStringTask = scriptLoader.load(.atDocumentEnd)

        let (documentStartString, documentEndString) = try await (documentStartStringTask, documentEndStringTask)

        // Create user scripts for injection.
        let documentStartScript = WKUserScript(
            source: documentStartString,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )

        let documentEndScript = WKUserScript(
            source: documentEndString,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        let configuration = WKWebViewConfiguration()
        let messageHandler = ReadabilityMessageHandler(
            mode: .generateReaderHTML(initialStyle: initialStyle),
            readerContentGenerator: ReaderContentGenerator()
        )

        self.configuration = configuration
        self.messageHandler = messageHandler

        configuration.userContentController.addUserScript(documentStartScript)
        configuration.userContentController.addUserScript(documentEndScript)
        configuration.userContentController.add(messageHandler, name: messageHandlerName)

        messageHandler.eventHandler = { [weak self] event in
            switch event {
            case .availabilityChanged(let availability):
                self?.availabilityChangedContinuation.yield(availability)
            case .contentParsedAndGeneratedHTML(html: let html):
                self?.contentParsedContinuation.yield(html)
            case .contentParsed:
                break
            }
        }

        return configuration
    }

    /// Invalidates the current configuration by removing all script message handlers and finishing the asynchronous streams.
    public func invalidate() {
        configuration?.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        configuration?.userContentController.removeAllUserScripts()
        contentParsedContinuation.finish()
        availabilityChangedContinuation.finish()
    }

    deinit {
        MainActor.assumeIsolated {
            invalidate()
        }
    }
}
