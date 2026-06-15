import SwiftUI

struct ContentView: View {
    @State private var route: AppRoute = .home

    var body: some View {
        Group {
            switch route {
            case .home:
                HomeView {
                    route = .initialListen
                }
            case .initialListen:
                InitialListenView {
                    route = .home
                }
            }
        }
        .frame(
            minWidth: 1120,
            idealWidth: 1280,
            minHeight: 740,
            idealHeight: 820
        )
    }
}

private enum AppRoute {
    case home
    case initialListen
}

#Preview {
    ContentView()
}
