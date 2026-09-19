import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("ReaderTextView", value: ExampleDestination.readerTextView)
                NavigationLink("ReaderWebView", value: ExampleDestination.readerWebView)
            }
            .navigationDestination(for: ExampleDestination.self) { destination in
                switch destination {
                case .readerTextView:
                    ReaderTextView()
                case .readerWebView:
                    ReaderWebView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
