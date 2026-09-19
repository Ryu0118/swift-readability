import Foundation
import WebKit

/// A message handler for receiving messages from injected JavaScript in the WKWebView.
@MainActor
package final class ReadabilityMessageHandler<Generator: ReaderContentGeneratable>: NSObject, WKScriptMessageHandler {
    /// Modes that determine how the message handler processes content.
    package enum Mode {
        /// Generates reader HTML using the provided initial style.
        case generateReaderHTML(initialStyle: ReaderStyle)
        /// Returns the raw readability result.
        case generateReadabilityResult
    }

    /// Events emitted by the message handler.
    package enum Event {
        /// The readability content was parsed and reader HTML was generated.
        case contentParsedAndGeneratedHTML(html: String)
        /// The readability content was parsed.
        case contentParsed(readabilityResult: ReadabilityResult)
        /// The availability status of the reader changed.
        case availabilityChanged(availability: ReaderAvailability)
        /// The parse produced no usable content (a `null`/undecodable result from the page script).
        case contentParseFailed
    }

    // The generator used to produce reader HTML from the readability result.
    private let readerContentGenerator: Generator
    private let mode: Mode

    /// A closure that is called when an event is received.
    package var eventHandler: (@MainActor (Event) -> Void)?

    package init(mode: Mode, readerContentGenerator: Generator) {
        self.mode = mode
        self.readerContentGenerator = readerContentGenerator
    }

    package func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let message = message.body as? [String: Any],
              let typeString = message["Type"] as? String,
              let type = ReadabilityMessageType(rawValue: typeString),
              let value = message["Value"]
        else {
            return
        }

        switch type {
        case .stateChange:
            if let availability = ReaderAvailability(rawValue: value as? String ?? "") {
                eventHandler?(.availabilityChanged(availability: availability))
            }
        case .contentParsed:
            Task.detached { [weak self, mode] in
                if let jsonString = value as? String,
                   let jsonData = jsonString.data(using: .utf8),
                   let result = try? JSONDecoder().decode(ReadabilityResult.self, from: jsonData)
                {
                    switch mode {
                    case let .generateReaderHTML(initialStyle):
                        if let html = await self?.readerContentGenerator.generate(result, initialStyle: initialStyle) {
                            await self?.eventHandler?(.contentParsedAndGeneratedHTML(html: html))
                        }
                    case .generateReadabilityResult:
                        await self?.eventHandler?(.contentParsed(readabilityResult: result))
                    }
                } else {
                    await self?.eventHandler?(.contentParseFailed)
                }
            }
        }
    }

    /// Subscribes to events emitted by the message handler.
    ///
    /// - Parameter operation: A closure to be invoked when an event occurs, or `nil` to unsubscribe.
    package func subscribeEvent(_ operation: (@MainActor (Event) -> Void)?) {
        eventHandler = operation
    }
}
