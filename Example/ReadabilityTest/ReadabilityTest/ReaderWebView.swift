import Observation
import ReadabilityUI
import SwiftUI
import WebKit
import WebUI

@Observable
@MainActor
final class ReaderWebModel {
    var configuration: WKWebViewConfiguration?
    var configurationError: (any Error)?
    var urlString = ""
    var readerHTMLCaches: [URL: String] = [:]
    var isReaderAvailable = false
    var isReaderPresenting = false

    let webCoordinator = ReadabilityWebCoordinator(initialStyle: .init(theme: .dark, fontSize: .size5))
}

struct ReaderWebView: View {
    @State private var model = ReaderWebModel()
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        Group {
            if let configuration = model.configuration {
                core(configuration: configuration)
            } else if let error = model.configurationError {
                ContentUnavailableView(
                    "Reader Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                model.configuration = try await model.webCoordinator.createReadableWebViewConfiguration()
            } catch {
                model.configurationError = error
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func core(configuration: WKWebViewConfiguration) -> some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                addressBar(proxy: proxy)
                ProgressView(value: proxy.estimatedProgress, total: 1)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .opacity(proxy.estimatedProgress < 1 ? 1 : 0)
                    .animation(.easeOut, value: proxy.estimatedProgress)
                    .frame(height: 2)
                WebView(configuration: configuration)
                    .uiDelegate(ReadabilityUIDelegate())
                    .navigationDelegate(
                        NavigationDelegate(didFinish: {
                            Task { @MainActor in
                                model.isReaderPresenting = (try? await proxy.isReaderMode()) ?? false
                            }
                        })
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .onChange(of: proxy.url) { _, newURL in
                        if let newURL, !addressFieldFocused {
                            model.urlString = newURL.absoluteString
                        }
                    }
                    .task {
                        for await html in model.webCoordinator.contentParsed {
                            if let url = proxy.url {
                                model.readerHTMLCaches[url] = html
                            }
                        }
                    }
                    .task {
                        for await availability in model.webCoordinator.availabilityChanged {
                            model.isReaderAvailable = availability == .available
                            if availability == .unavailable {
                                model.isReaderPresenting = false
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        toolbar(proxy: proxy)
                    }
            }
        }
    }

    private func addressBar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 10) {
            Image(systemName: proxy.url?.scheme == "https" ? "lock.fill" : "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search or enter website name", text: $model.urlString)
                .focused($addressFieldFocused)
                .textFieldStyle(.plain)
                .font(.callout)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    load(model.urlString, proxy: proxy)
                }

            if model.isReaderAvailable {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .transition(.scale.combined(with: .opacity))
            }

            if !model.urlString.isEmpty {
                Button {
                    model.urlString = ""
                    addressFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isReaderAvailable)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private func load(_ text: String, proxy: WebViewProxy) {
        guard !text.isEmpty else { return }
        let url = URL(string: text)
        let resolvedURL = (url?.scheme != nil ? url : URL(string: "https://\(text)")) ?? url
        if let resolvedURL {
            proxy.load(request: URLRequest(url: resolvedURL))
        }
        addressFieldFocused = false
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        let readerHTML = proxy.url.flatMap { model.readerHTMLCaches[$0] }

        return HStack {
            toolbarButton("Back", systemImage: "chevron.backward", isEnabled: proxy.canGoBack) {
                proxy.goBack()
            }

            Spacer()

            toolbarButton("Forward", systemImage: "chevron.forward", isEnabled: proxy.canGoForward) {
                proxy.goForward()
            }

            Spacer()

            toolbarButton(
                model.isReaderPresenting ? "Hide Reader" : "Show Reader",
                systemImage: model.isReaderPresenting ? "text.page.fill" : "text.page",
                isEnabled: model.isReaderAvailable && readerHTML != nil
            ) {
                guard let readerHTML else { return }
                Task {
                    if model.isReaderPresenting {
                        try? await proxy.hideReaderContent()
                    } else {
                        try? await proxy.showReaderContent(with: readerHTML)
                    }
                    model.isReaderPresenting.toggle()
                }
            }

            Spacer()

            Menu {
                Menu("Theme", systemImage: "circle.lefthalf.filled") {
                    ForEach(ReaderStyle.Theme.allCases, id: \.self) { theme in
                        Button(theme.rawValue.capitalized) {
                            Task { try? await proxy.set(theme: theme) }
                        }
                    }
                }
                Menu("Font Size", systemImage: "textformat.size") {
                    ForEach(ReaderStyle.FontSize.allCases, id: \.self) { fontSize in
                        Button(fontSize.rawValue.description) {
                            Task { try? await proxy.set(fontSize: fontSize) }
                        }
                    }
                }
            } label: {
                Label("Reader Appearance", systemImage: "paintpalette")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18))
            }
            .disabled(!model.isReaderPresenting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func toolbarButton(_ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 18))
            .disabled(!isEnabled)
    }
}

final class ReadabilityUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

final class NavigationDelegate: NSObject, WKNavigationDelegate {
    let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        didFinish()
    }
}

extension WebViewProxy: @retroactive ReaderControllable {}
