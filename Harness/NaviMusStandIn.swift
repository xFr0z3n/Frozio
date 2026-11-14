// A SwiftUI stand-in for NaviMus's shape, so Frozio's redesign can be seen on what SwiftUI really builds:
// a TabView (SwiftUI.UIKitTabBarController) of NavigationStacks (SwiftUI.UIKitNavigationController,
// NavigationStackHostingController<AnyView>), lists and a form, a Settings tab titled "Settings" (what
// FZSettingsEntry looks for), the mini player as a tab accessory on iOS 26 (NaviMus's TabViewiOS26),
// and NaviMus's own tint (its AccentColor asset, sRGB 0.996/1/1, docs/FEATURES.md).
//
// Launch arguments: -FZHarnessLight YES asks for light mode the way NaviMus's appearance setting does
// (preferredColorScheme), to check the redesign keeps it dark.
import SwiftUI
import UIKit

@objc(FZHarnessStandIn)
final class FZHarnessStandIn: NSObject {
    @objc static func makeRoot() -> UIViewController {
        UIHostingController(rootView: StandInRoot())
    }
}

private let naviMusTint = Color(red: 0.996, green: 1, blue: 1)

private struct Album: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let hue: Double
}

private let albums: [Album] = (0..<14).map { i in
    Album(title: "Harness Album \(i + 1)", artist: ["Harness Artist", "Guest Singer", "Blocked Band"][i % 3],
          hue: Double(i) / 14)
}

private struct StandInRoot: View {
    private let light = UserDefaults.standard.bool(forKey: "FZHarnessLight")

    var body: some View {
        let tabs = TabView {
            HomeTab().tabItem { Label("Home", systemImage: "house") }
            LibraryTab().tabItem { Label("Library", systemImage: "square.stack") }
            SearchTab().tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(naviMusTint)
        Group {
            if #available(iOS 26.0, *) {
                tabs.tabViewBottomAccessory { MiniPlayer() }
            } else {
                tabs
            }
        }
        .preferredColorScheme(light ? .light : nil)
    }
}

private struct Cover: View {
    let hue: Double
    var size: CGFloat = 52
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.9),
                                          Color(hue: hue + 0.1, saturation: 0.8, brightness: 0.5)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

private struct AlbumRow: View {
    let album: Album
    var body: some View {
        HStack(spacing: 12) {
            Cover(hue: album.hue)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.body)
                Text(album.artist).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HomeTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Recently Played") {
                    ForEach(albums.prefix(6)) { album in
                        NavigationLink { AlbumDetail(album: album) } label: { AlbumRow(album: album) }
                    }
                }
                Section("Frequently Played") {
                    ForEach(albums.suffix(8)) { album in AlbumRow(album: album) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Home")
        }
    }
}

private struct AlbumDetail: View {
    let album: Album
    var body: some View {
        List {
            VStack(spacing: 8) {
                Cover(hue: album.hue, size: 220)
                Text(album.title).font(.title2.bold())
                Text(album.artist).foregroundStyle(naviMusTint)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            ForEach(1..<11) { n in
                HStack { Text("\(n)").foregroundStyle(.secondary); Text("Track \(n)"); Spacer(); Text("3:2\(n % 10)").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LibraryTab: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(["Playlists", "Artists", "Albums", "Songs", "Genres", "Downloaded"], id: \.self) { name in
                    NavigationLink(name) { List(albums) { AlbumRow(album: $0) }.navigationTitle(name) }
                }
                Section("Recently Added") {
                    ForEach(albums.prefix(5)) { AlbumRow(album: $0) }
                }
            }
            .navigationTitle("Library")
        }
    }
}

private struct SearchTab: View {
    @State private var text = ""
    var body: some View {
        NavigationStack {
            List(albums.filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }) { AlbumRow(album: $0) }
                .listStyle(.plain)
                .navigationTitle("Search")
                .searchable(text: $text, prompt: "Artists, Albums, Songs")
        }
    }
}

private struct SettingsTab: View {
    @State private var precache = true
    @State private var scrobble = true
    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Navidrome", value: "harness.local")
                    LabeledContent("User", value: "demo")
                }
                Section("Playback") {
                    Toggle("Pre-cache", isOn: $precache)
                    Toggle("Scrobble", isOn: $scrobble)
                    NavigationLink("Transcoding") { Text("Transcoding") }
                }
                Section("Appearance") {
                    NavigationLink("Player Style") { Text("Player Style") }
                    NavigationLink("Tint Colour") { Text("Tint Colour") }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct MiniPlayer: View {
    var body: some View {
        HStack(spacing: 10) {
            Cover(hue: 0.55, size: 32)
            Text("Harness Song").font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "play.fill")
            Image(systemName: "forward.fill")
        }
        .padding(.horizontal, 14)
    }
}
