// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import ReadabilityCore

/// A content generator that creates reader HTML using a template and a readability result.
/// Conforms to the `ReaderContentGeneratable` protocol.
struct ReaderContentGenerator: ReaderContentGeneratable {
    private let encoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private let scriptLoader = ScriptLoader(bundle: .module)

    /// Generates reader HTML content based on the provided `ReadabilityResult` and `ReaderStyle`.
    ///
    /// - Parameters:
    ///   - readabilityResult: The result of the readability parsing.
    ///   - initialStyle: The initial style settings to apply.
    /// - Returns: An optional `String` containing the generated reader HTML, or `nil` if generation fails.
    func generate(
        _ readabilityResult: ReadabilityResult,
        initialStyle: ReaderStyle
    ) async -> String? {
        // Load the HTML template and encode the reader style into JSON.
        guard let template = try? await scriptLoader.load(.readerHTML),
              let styleData = try? encoder.encode(initialStyle),
              let styleString = String(data: styleData, encoding: .utf8)
        else { return nil }

        // Replace placeholders in the template with actual content.
        return template.replacingOccurrences(of: "%READER-STYLE%", with: styleString)
            .replacingOccurrences(of: "%READER-TITLE%", with: readabilityResult.title)
            .replacingOccurrences(of: "%READER-BYLINE%", with: readabilityResult.byline ?? "")
            .replacingOccurrences(of: "%READER-CONTENT%", with: readabilityResult.content)
            .replacingOccurrences(of: "%READER-LANGUAGE%", with: readabilityResult.language ?? "en")
            .replacingOccurrences(of: "%READER-DIRECTION%", with: readabilityResult.direction ?? "auto")
    }
}
