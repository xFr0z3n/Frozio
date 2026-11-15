// A SwiftUI stand-in for NaviMus's shape, so Frozio's redesign can be seen on what SwiftUI really builds:
// a TabView (SwiftUI.UIKitTabBarController) of NavigationStacks (SwiftUI.UIKitNavigationController,
// NavigationStackHostingController<AnyView>), lists and a form, a Settings tab titled "Settings" (what
// FZSettingsEntry looks for), the mini player as a tab accessory on iOS 26 (NaviMus's TabViewiOS26),
// and NaviMus's own tint (its AccentColor asset, sRGB 0.996/1/1, docs/FEATURES.md).
//
// Launch arguments: -FZHarnessLight YES asks for light mode the way NaviMus's appearance setting does
// (preferredColorScheme), to check the redesign keeps it dark.
import AppIntents
import MediaPlayer
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
    var serverID: String { "al-\(index)" }
    let index: Int
    let title: String
    let artist: String
    let hue: Double
}

private let albums: [Album] = (0..<14).map { i in
    Album(index: i + 1, title: "Harness Album \(i + 1)", artist: ["Harness Artist", "Guest Singer", "Blocked Band"][i % 3],
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
        .task { await login() }
    }

    private func login() async {
        var url = URLComponents(string: "http://localhost:4533/rest/ping.view")!
        url.queryItems = [.init(name: "u", value: "demo"), .init(name: "t", value: "26719a1196d2a940705a59634eb18eab"),
                          .init(name: "s", value: "c19b2d"), .init(name: "v", value: "1.16.1"),
                          .init(name: "c", value: "Arpeggi"), .init(name: "f", value: "json")]
        let result = try? await URLSession.shared.data(for: URLRequest(url: url.url!))
        NSLog("[harness] login ping %@", result == nil ? "failed (is Harness/mockserver.py running?)" : "ok")
    }
}

// NaviMus's App Intents, same names and parameter shapes (probe build 33), so Frozio's intent bridge runs
// the same way it does in NaviMus.
struct AlbumEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static let defaultQuery = AlbumEntityQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}
struct AlbumEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] { identifiers.map(AlbumEntity.init) }
}
struct SongEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Song"
    static let defaultQuery = SongEntityQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}
struct SongEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SongEntity] { identifiers.map(SongEntity.init) }
}
struct ArtistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Artist"
    static let defaultQuery = ArtistEntityQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}
struct ArtistEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ArtistEntity] { identifiers.map(ArtistEntity.init) }
}
struct PlayAlbumIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Album"
    @Parameter(title: "Album") var album: AlbumEntity?
    @Parameter(title: "Search") var albumSearchTerm: String?
    func perform() async throws -> some IntentResult {
        NSLog("[harness] PlayAlbumIntent performed: %@", album?.id ?? "nil")
        await StandInPlayer.shared.play("so-1")
        return .result()
    }
}
struct PlaySongIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Song"
    @Parameter(title: "Song") var entity: SongEntity?
    @Parameter(title: "Name") var name: String?
    func perform() async throws -> some IntentResult {
        NSLog("[harness] PlaySongIntent performed: %@", entity?.id ?? "nil")
        if let id = entity?.id { await StandInPlayer.shared.play(id) }
        return .result()
    }
}
struct OpenArtistIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Artist"
    @Parameter(title: "Artist") var target: ArtistEntity
    func perform() async throws -> some IntentResult {
        NSLog("[harness] OpenArtistIntent performed: %@", target.id)
        return .result()
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
                        NavigationLink { AlbumViewWrapper(album: album, albumID: album.serverID) } label: { AlbumRow(album: album) }
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

private let standInSongs = ["Purpose General", "Face The Flame", "Lose Control", "Fourth Song", "Fifth Song",
                            "Sixth Song", "Seventh Song", "Eighth Song"]

// Named and shaped like NaviMus's album page root (Arpeggi.AlbumViewWrapper: album, albumID), so the
// redesign's page interception finds it the same way.
private struct AlbumViewWrapper: View {
    let album: Album
    let albumID: String?
    var body: some View {
        List {
            VStack(spacing: 8) {
                Cover(hue: album.hue, size: 220)
                Text(album.title).font(.title2.bold())
                Text(album.artist).foregroundStyle(naviMusTint)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            // NaviMus's rows: the title, its download ring ("circle.dotted"), then a ⋯ labelled "More".
            ForEach(Array(standInSongs.enumerated()), id: \.offset) { n, title in
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "circle.dotted")
                    Menu {
                        Button("Play Next") { NSLog("[harness] NaviMus row menu: Play Next for %@", title) }
                        Button("Add to Playlist") {}
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("More")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        // As on NaviMus's album page (device log, build 35): Shuffle, Play, Download and More are items of the
        // navigation bar, not of the page.
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    NSLog("[harness] NaviMus shuffle tapped")
                    MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = .items
                    StandInPlayer.shared.play("so-3")
                } label: { Image(systemName: "shuffle") }
                    .accessibilityLabel("Shuffle")
                Button { NSLog("[harness] NaviMus download tapped") } label: { Image(systemName: "arrow.down.circle") }
                    .accessibilityLabel("Download")
                Menu { Button("Add to Playlist") {}; Button("Go to Artist") {} } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
            }
        }
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

// NaviMus's player as the system sees it: Now Playing info with the song ID, and a play/pause handler.
@MainActor
final class StandInPlayer {
    static let shared = StandInPlayer()
    private var song: String?
    private var playing = false

    private init() {
        MPRemoteCommandCenter.shared().changeShuffleModeCommand.addTarget { event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = event.shuffleType
            NSLog("[harness] NaviMus shuffle handler → type %ld", event.shuffleType.rawValue)
            return .success
        }
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let song = self.song else { return .noActionableNowPlayingItem }
            self.playing.toggle()
            self.publish(song)
            NSLog("[harness] toggle play/pause → %@", self.playing ? "playing" : "paused")
            return .success
        }
    }

    func play(_ id: String) {
        song = id
        playing = true
        publish(id)
    }

    private func publish(_ id: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: id, MPMediaItemPropertyArtist: "Harness Artist",
            MPNowPlayingInfoPropertyExternalContentIdentifier: id,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
    }
}
