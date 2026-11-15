// A SwiftUI stand-in for NaviMus's shape, so Frozio's redesign can be seen on what SwiftUI really builds:
// a TabView (SwiftUI.UIKitTabBarController) of NavigationStacks (SwiftUI.UIKitNavigationController,
// NavigationStackHostingController<AnyView>), lists and a form, a Settings tab titled "Settings" (what
// FZSettingsEntry looks for), the mini player as a tab accessory on iOS 26 (NaviMus's TabViewiOS26),
// and NaviMus's own tint (its AccentColor asset, sRGB 0.996/1/1, docs/FEATURES.md).
//
// Launch arguments: -FZHarnessLight YES asks for light mode the way NaviMus's appearance setting does
// (preferredColorScheme), to check the redesign keeps it dark.
import AppIntents
import AVFoundation
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

// -FZHarnessLegacyMini YES: NaviMus's iOS 17 shape on iOS 26 too, its mini player a band over each tab's
// content (device probe, build 33: `_UIInheritedView` from 692 to the bottom) that grows into its player.
private let legacyMini: Bool = {
    if #available(iOS 26.0, *) { return UserDefaults.standard.bool(forKey: "FZHarnessLegacyMini") }
    return true
}()

private struct StandInRoot: View {
    private let light = UserDefaults.standard.bool(forKey: "FZHarnessLight")

    var body: some View {
        let tabs = TabView {
            HomeTab().legacyBand().tabItem { Label("Home", systemImage: "house") }
            LibraryTab().legacyBand().tabItem { Label("Library", systemImage: "square.stack") }
            SearchTab().legacyBand().tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsTab().legacyBand().tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(naviMusTint)
        Group {
            if #available(iOS 26.0, *), !legacyMini {
                tabs.tabViewBottomAccessory { MiniPlayer() }
            } else {
                // NaviMus's visible card is drawn over the tabs from the root view (device, build 40).
                tabs.overlay(alignment: .bottom) { RootCard() }
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
struct LikeSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Love Song"
    func perform() async throws -> some IntentResult {
        NSLog("[harness] LikeSongIntent performed")
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

private let standInSongs = ["Purpose General", "Face The Flame", "Lose Control", "Onë Thing I Fear (Interlude) With A Long Title", "Fifth Song",
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
                HStack(spacing: 24) {
                    Button {
                        NSLog("[harness] NaviMus header shuffle (labelled Repeat) tapped")
                        StandInPlayer.shared.play("so-3")
                    } label: { Image(systemName: "shuffle") }
                        .accessibilityLabel("Repeat")
                    Button { StandInPlayer.shared.play("so-1") } label: { Image(systemName: "play.fill") }
                        .accessibilityLabel("Play")
                    Button { } label: { Image(systemName: "heart") }
                        .accessibilityLabel("Love")
                }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            // NaviMus's rows: the title, its download ring ("circle.dotted"), then a ⋯ labelled "More".
            ForEach(Array(standInSongs.enumerated()), id: \.offset) { n, title in
                HStack {
                    // As NaviMus's row: a tap plays the album from that song, the rest queued.
                    Text(title)
                        .onTapGesture {
                            NSLog("[harness] NaviMus album row tapped: %@", title)
                            StandInPlayer.shared.play("so-\(n + 1)")
                        }
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
        // As on NaviMus's album page (device logs, builds 35–37): the bar carries only ⋯, a SwiftUI menu that
        // accessibility doesn't list on iOS 17; the album's download is one of its items.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // NaviMus's album download is an item of its ⋯ menu (device log, build 37).
                Menu {
                    Button("Download") { NSLog("[harness] NaviMus menu: Download album") }
                    Button("Add to Playlist") {}
                    Button("Go to Artist") {}
                } label: { Image(systemName: "ellipsis") }
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
                    if name == "Songs" {
                        NavigationLink(name) {
                            StandInHostedGrid().ignoresSafeArea(edges: .bottom).navigationTitle("Songs")
                                .toolbar { Button("Sort") { NotificationCenter.default.post(name: .init("standin.resort"), object: nil) } }
                        }
                    } else if name == "Albums" {
                        NavigationLink(name) { StandInAlbumGrid().ignoresSafeArea(edges: .bottom).navigationTitle("Albums") }
                    } else {
                        NavigationLink(name) { LibraryCategory(name: name) }
                    }
                }
                Section("Recently Added") {
                    ForEach(albums.prefix(5)) { AlbumRow(album: $0) }
                }
            }
            .navigationTitle("Library")
        }
    }
}

// A Library category as NaviMus draws it (the user's screenshot, build 40): a sort menu and ⋯ in the bar, tinted.
private struct LibraryCategory: View {
    let name: String
    @AppStorage("libraryAlbumsOrder") private var albumType = "alphabeticalByName"
    var body: some View {
        // Sections headed by a round chip, as NaviMus's library lists are (the user's screenshot, build 43: "2017").
        List {
            ForEach([("2017", albums.prefix(5)), ("2018", albums.dropFirst(5).prefix(5)), ("2019", albums.dropFirst(10))], id: \.0) { year, group in
                Section {
                    ForEach(Array(group)) { AlbumRow(album: $0) }
                } header: {
                    Text(year).font(.title2.bold()).foregroundStyle(.green)
                        .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 4)
                        .background(Circle().fill(Color(white: 0.2)))
                }
            }
        }
            .listStyle(.plain)
            .navigationTitle(name)
            // As NaviMus does: the stored sort becomes getAlbumList2's type.
            .task(id: albumType) {
                var request = URLRequest(url: URL(string: "http://localhost:4533/rest/getAlbumList2.view?type=\(albumType)&size=50&u=demo&f=json")!)
                request.httpMethod = "GET"
                NSLog("[harness] album list request %@", request.url?.absoluteString ?? "")
                _ = try? await URLSession.shared.data(for: request)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $albumType) {
                            Text("Name").tag("alphabeticalByName")
                            Text("Artist").tag("alphabeticalByArtist")
                            Text("Recently Added").tag("newest")
                            Text("Frequently Played").tag("frequent")
                            Text("Recently Played").tag("recent")
                            Text("Random").tag("random")
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                        .accessibilityLabel("Sort")
                    Menu {
                        Button("Shuffle All") {}
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More")
                }
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
                // NaviMus's account button at the top right of Search (the user's report, build 43).
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { NSLog("[harness] account tapped") } label: { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("Account")
                    }
                }
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
                Section("Glass reference (Apple's own)") {
                    ZStack {
                        LinearGradient(colors: [.orange, .purple, .blue], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 90)
                        HStack(spacing: 20) {
                            if #available(iOS 26.0, *) {
                                Button { } label: { Image(systemName: "shuffle").frame(width: 30, height: 30) }
                                    .buttonStyle(.glass)
                                Image(systemName: "arrow.down").frame(width: 48, height: 48)
                                    .glassEffect(.regular, in: .circle)
                            }
                        }
                    }
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

private extension View {
    @ViewBuilder func legacyBand() -> some View {
        if legacyMini { overlay(alignment: .bottom) { LegacyBand() } } else { self }
    }
}

// NaviMus's iOS 17 mini player and player in one overlay: tapping the mini player grows it into the player, whose
// ⋯ menu has the song's Download (names guessed until the device log shows NaviMus's).
private struct LegacyBand: View {
    @ObservedObject private var model = StandInPlayer.shared.model
    var body: some View {
        if model.song != nil {
            Group {
                if model.expanded {
                    VStack(spacing: 24) {
                        HStack {
                            Button { model.expanded = false } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                                .accessibilityLabel("Close")
                            Spacer()
                            Menu {
                                Button("Download") { NSLog("[harness] NaviMus player menu: Download song") }
                                Button("Add to Playlist") { NSLog("[harness] NaviMus player menu: Add to Playlist") }
                                Button("Add to Queue") {
                                    NSLog("[harness] NaviMus player menu: Add to Queue")
                                    let manager = StandInAudioManager.shared
                                    if let current = manager._currentQueueItem { manager._primaryQueue.append(current) }
                                    manager.handleItemChanged()
                                }
                                Button("Go to Album") {}
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel("More")
                        }
                        Cover(hue: 0.55, size: 280)
                        Text(model.song ?? "").font(.title2.bold())
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                } else {
                    VStack(spacing: 0) {
                        MiniPlayer()
                            .frame(height: 64)
                            .background(.regularMaterial)
                            .contentShape(Rectangle())
                            .onTapGesture { model.expanded = true }
                        Color.clear.frame(height: 88)   // under the tab bar, as NaviMus's band
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .compositingGroup()
            .geometryGroup()
            .animation(.spring, value: model.expanded)
        }
    }
}

private struct RootCard: View {
    @ObservedObject private var model = StandInPlayer.shared.model
    var body: some View {
        if model.song != nil && !model.expanded {
            MiniPlayer()
                .frame(height: 56)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 8)
                .padding(.bottom, 57)
                .onTapGesture { NSLog("[harness] NaviMus root card tapped"); model.expanded = true }
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

// NaviMus's player as the system sees it: Now Playing info with the song ID, duration, elapsed time and artwork,
// and its command handlers (play/pause, next, previous, position, shuffle, repeat).
final class StandInModel: ObservableObject {
    @Published var song: String?
    @Published var expanded = false   // NaviMus's player open (it grows out of the band)
}

// NaviMus's AudioManager as Frozio reads it: an NSObject of that name with its queue fields (1.6.1 names).
struct StandInSong { let id: String; let title: String; let artist: String?; let album: String?; let coverArt: String?; let duration: Int? }
struct StandInQueueItem { let id = UUID(); var song: StandInSong }

@objc(_TtC7Arpeggi12AudioManager)
final class StandInAudioManager: NSObject {
    static let shared = StandInAudioManager()
    override init() {
        super.init()
        // As NaviMus's does (its interruption and offline-mode observers): Frozio finds it here.
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    @objc func handleInterruption(_ note: Notification) {}
    var _currentQueueItem: StandInQueueItem?
    var _primaryQueue: [StandInQueueItem] = []
    var _secondaryQueue: [StandInQueueItem] = []
    var _continuousQueue: [StandInQueueItem] = []
    var _queueHistory: [StandInQueueItem] = []
    @objc func handleItemChanged() {}
    @objc dynamic func updateCurrentRoute() {}
    @objc dynamic func playerDidFinishPlaying(_ note: Any?) {}

    func load(current index: Int) {
        func item(_ i: Int) -> StandInQueueItem {
            StandInQueueItem(song: StandInSong(id: "so-\(i + 1)", title: standInSongs[i], artist: "Harness Artist", album: "Harness Album 1",
                                               coverArt: "al-1", duration: 200))
        }
        _currentQueueItem = item(index)
        _queueHistory = (0..<index).map(item)
        _secondaryQueue = ((index + 1)..<standInSongs.count).map(item)
        _continuousQueue = [StandInQueueItem(song: StandInSong(id: "so-ap", title: "Autoplay Song", artist: "Guest Singer", album: "Harness Album 2",
                                                               coverArt: "al-2", duration: 180))]
        handleItemChanged()
    }
}

@MainActor
final class StandInPlayer {
    static let shared = StandInPlayer()
    let model = StandInModel()
    private var song: String?
    private var playing = false
    private var elapsed = 0.0
    private var started = Date()
    private let duration = 200.0

    private init() {
        let center = MPRemoteCommandCenter.shared()
        center.changeShuffleModeCommand.addTarget { event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = event.shuffleType
            NSLog("[harness] NaviMus shuffle handler → type %ld", event.shuffleType.rawValue)
            return .success
        }
        center.changeRepeatModeCommand.addTarget { event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            NSLog("[harness] NaviMus repeat handler → type %ld", event.repeatType.rawValue)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let song = self.song else { return .noActionableNowPlayingItem }
            self.setPlaying(!self.playing)
            self.publish(song)
            NSLog("[harness] toggle play/pause → %@", self.playing ? "playing" : "paused")
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, let song = self.song else { return .noActionableNowPlayingItem }
            self.setPlaying(false)
            self.publish(song)
            NSLog("[harness] pause")
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let song = self.song else { return .noActionableNowPlayingItem }
            let n = (Int(song.dropFirst(3)) ?? 1) % standInSongs.count + 1
            NSLog("[harness] next track")
            self.play("so-\(n)")
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let song = self.song else { return .noActionableNowPlayingItem }
            let n = max(1, (Int(song.dropFirst(3)) ?? 1) - 1)
            NSLog("[harness] previous track")
            self.play("so-\(n)")
            return .success
        }
        center.changePlaybackRateCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            NSLog("[harness] NaviMus rate handler → %.2f", event.playbackRate)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let song = self.song, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.elapsed = event.positionTime
            self.started = Date()
            self.publish(song)
            NSLog("[harness] seek → %.1f", event.positionTime)
            return .success
        }
    }

    private func now() -> Double { playing ? min(duration, elapsed + Date().timeIntervalSince(started)) : elapsed }

    private func setPlaying(_ on: Bool) {
        elapsed = now()
        started = Date()
        playing = on
    }

    func play(_ id: String) {
        song = id
        model.song = id
        StandInAudioManager.shared.load(current: max(0, min(standInSongs.count - 1, (Int(id.dropFirst(3)) ?? 1) - 1)))
        elapsed = 0
        started = Date()
        playing = true
        publish(id)
    }

    private func artwork(_ id: String) -> MPMediaItemArtwork {
        let hue = CGFloat((Int(id.dropFirst(3)) ?? 1) % 7) / 7
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            let colors = [UIColor(hue: hue, saturation: 0.7, brightness: 0.85, alpha: 1).cgColor,
                          UIColor(hue: hue + 0.12, saturation: 0.8, brightness: 0.35, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func publish(_ id: String) {
        let index = (Int(id.dropFirst(3)) ?? 1) - 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: standInSongs[max(0, min(standInSongs.count - 1, index))],
            MPMediaItemPropertyArtist: "Harness Artist", MPMediaItemPropertyAlbumTitle: "Harness Album 1",
            MPNowPlayingInfoPropertyExternalContentIdentifier: id,
            MPMediaItemPropertyPlaybackDuration: duration, MPMediaItemPropertyArtwork: artwork(id),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: now(), MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
    }
}

// NaviMus's album grid as its 1.6.1 types show it (AlbumsDiffableCollectionView, HostingCollectionViewCell<V> with a
// `hostingController: UIHostingController<V>?` reused for every album), and its CoverArtView, which loads the cover
// once when it appears (@State image): a reused cell keeps the previous album's cover, the user's bug (build 43).
final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    var hostingController: UIHostingController<Content>?
    func host(_ view: Content) {
        if let hostingController {
            hostingController.rootView = view
        } else {
            let controller = UIHostingController(rootView: view)
            controller.view.backgroundColor = .clear
            controller.view.frame = contentView.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(controller.view)
            hostingController = controller
        }
    }
}

private struct StandInCoverArtView: View {
    let index: Int
    @State private var shown: Int?
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hue: Double(shown ?? 0) / 40, saturation: 0.7, brightness: shown == nil ? 0.2 : 0.8))
            .overlay(Text(shown.map { "#\($0)" } ?? "…").font(.headline).foregroundStyle(.white))
            .overlay(alignment: .bottom) { Text("album \(index)").font(.caption).foregroundStyle(.white) }
            .onAppear { shown = index }   // as NaviMus: loaded once, when it first appears
    }
}

private struct StandInAlbumGrid: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 170, height: 170)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .black
        view.register(HostingCollectionViewCell<StandInCoverArtView>.self, forCellWithReuseIdentifier: "album")
        view.dataSource = context.coordinator
        view.accessibilityIdentifier = "standin.albumGrid"
        return view
    }
    func updateUIView(_ view: UICollectionView, context: Context) {}
    final class Coordinator: NSObject, UICollectionViewDataSource {
        func collectionView(_ view: UICollectionView, numberOfItemsInSection section: Int) -> Int { 40 }
        func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
            let cell = view.dequeueReusableCell(withReuseIdentifier: "album", for: path) as! HostingCollectionViewCell<StandInCoverArtView>
            cell.host(StandInCoverArtView(index: path.item))
            return cell
        }
    }
}

// NaviMus's other lists: plain UICollectionViewCells with UIHostingConfiguration (device log, build 45:
// "UICollectionViewCell / UIKit._UICustomContentConfiguration"), the cover in @State loaded on appear.
private struct StandInHostedGrid: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 170, height: 170)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .black
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "song")
        view.dataSource = context.coordinator
        context.coordinator.view = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.resort), name: .init("standin.resort"), object: nil)
        return view
    }
    func updateUIView(_ view: UICollectionView, context: Context) {}
    final class Coordinator: NSObject, UICollectionViewDataSource {
        weak var view: UICollectionView?
        var order = Array(0..<40)
        func configure(_ cell: UICollectionViewCell, _ item: Int) {
            cell.contentConfiguration = UIHostingConfiguration { StandInCoverArtView(index: item) }.margins(.all, 0)
        }
        func collectionView(_ view: UICollectionView, numberOfItemsInSection section: Int) -> Int { order.count }
        func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
            let cell = view.dequeueReusableCell(withReuseIdentifier: "song", for: path)
            configure(cell, order[path.item])
            return cell
        }
        // As NaviMus does when its sort changes: the visible cells are filled again in place (a diffable reconfigure).
        @objc func resort() {
            order.reverse()
            guard let view else { return }
            for path in view.indexPathsForVisibleItems { if let cell = view.cellForItem(at: path) { configure(cell, order[path.item]) } }
            NSLog("[harness] hosted grid re-sorted in place")
        }
    }
}
