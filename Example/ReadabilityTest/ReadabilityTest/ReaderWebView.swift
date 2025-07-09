import Observation
import ReadabilityUI
import SwiftUI
import WebKit
import WebUI

@Observable
@MainActor
final class ReaderWebModel {
    var configuration: WKWebViewConfiguration?
    var isLoading = false
    var urlString = ""
    var isPresented = true
    var readerHTMLCaches: [URL: String] = [:]
    var isReaderAvailable = false
    var isReaderPresenting = false

    let webCoordinator = ReadabilityWebCoordinator(initialStyle: .init(theme: .dark, fontSize: .size5))
}

struct ReaderWebView: View {
    @Bindable var model = ReaderWebModel()

    var body: some View {
        Group {
            if let configuration = model.configuration {
                core(configuration: configuration)
            } else {
                ProgressView()
            }
        }
        .task {
            model.configuration = try? await model.webCoordinator.createReadableWebViewConfiguration()
        }
        .overlay {
            if model.isLoading {
                ProgressView()
            }
        }
    }

    private func core(configuration: WKWebViewConfiguration) -> some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                ProgressView(value: proxy.estimatedProgress, total: 1)
                    .progressViewStyle(.linear)
                WebView(configuration: configuration)
                    .uiDelegate(ReadabilityUIDelegate())
                    .navigationDelegate(
                        NavigationDelegate(didFinish: {
                            Task { @MainActor in
                                model.isReaderPresenting = try await proxy.isReaderMode()
                            }
                        })
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .searchable(text: $model.urlString, isPresented: $model.isPresented)
                    .onSubmit(of: .search) {
                        if let url = URL(string: model.urlString) {
                            proxy.load(request: URLRequest(url: url))
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
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        bottomBar(proxy: proxy)
                    }
            }
        }
    }

    private func withLoading(_ operation: @escaping () async throws -> Void) {
        model.isLoading = true
        Task {
            do {
                try await operation()
            } catch {
                print(error)
            }
            model.isLoading = false
        }
    }

    private func bottomBar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
            Group {
                Button {
                    proxy.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .resizable()
                        .scaledToFit()
                }
                .disabled(!proxy.canGoBack)
                Button {
                    proxy.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                        .resizable()
                        .scaledToFit()
                }
                .disabled(!proxy.canGoForward)

                if let url = proxy.url,
                   let html = model.readerHTMLCaches[url]
                {
                    Button {
                        Task {
                            if model.isReaderPresenting {
                                try await proxy.hideReaderContent()
                            } else {
                                try await proxy.showReaderContent(with: html)
                            }
                            model.isReaderPresenting.toggle()
                        }
                    } label: {
                        Image(systemName: "text.page")
                            .resizable()
                            .scaledToFit()
                    }
                    .symbolVariant(model.isReaderPresenting ? .fill : .none)

                    Menu {
                        Menu("Theme") {
                            ForEach(ReaderStyle.Theme.allCases, id: \.self) { theme in
                                Button(theme.rawValue) {
                                    Task {
                                        try await proxy.set(theme: theme)
                                    }
                                }
                            }
                        }
                        Menu("FontSize") {
                            ForEach(ReaderStyle.FontSize.allCases, id: \.self) { fontSize in
                                Button(fontSize.rawValue.description) {
                                    Task {
                                        try await proxy.set(fontSize: fontSize)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                    }
                    .disabled(!model.isReaderPresenting)
                }
            }
            .frame(width: 15)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.capsule)
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
