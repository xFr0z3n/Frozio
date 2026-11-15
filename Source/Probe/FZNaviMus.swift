// FZNaviMus: Frozio's way into NaviMus's own actions, from Objective-C (docs/REDESIGN_PLAN.md).
//
// - Page data: a field of the SwiftUI view a NaviMus page shows (e.g. AlbumViewWrapper.albumID), read with
//   Mirror. Verified on the device (probe build 33).
// - Actions: NaviMus's own App Intents, the same ones Shortcuts and Siri run: PlayAlbumIntent(_album),
//   PlayArtistIntent(_artist), PlayPlaylistIntent(_entity), PlaySongIntent(_entity), Open…Intent(_target).
//   The entity is looked up by ID through its own query (AlbumEntityQuery, …), the intent's parameter set,
//   and perform() run. Types are found by mangled name; on any mismatch nothing runs and the reason is
//   handed back.
import AppIntents
import SwiftUI
import UIKit

@objc(FZNaviMus)
public final class FZNaviMus: NSObject {
    /// The root view type of a NaviMus page, e.g. "Arpeggi.AlbumViewWrapper".
    @objc public static func pageType(_ controller: UIViewController) -> String? {
        FZProbe.rootViewType(controller)
    }

    /// A string field of a NaviMus page's root view, along a dotted path ("albumID", "album.id").
    @objc public static func pageString(_ controller: UIViewController, path: String) -> String? {
        guard let host = controller as? UIHostingController<AnyView>, var value = FZProbe.appValue(in: host.rootView) else { return nil }
        for label in path.split(separator: ".") {
            guard let child = Mirror(reflecting: value).children.first(where: { $0.label == String(label) || $0.label == "_" + label }) else {
                return nil
            }
            value = child.value
        }
        if let text = value as? String, !text.isEmpty { return text }
        return nil
    }

    /// NaviMus's module, then the host app's own (the harness's stand-in intents).
    private static let modules = ["Arpeggi", ProcessInfo.processInfo.processName]

    private static func type(_ name: String) -> Any.Type? {
        for module in modules {
            for kind in ["V", "C"] {
                if let type = _typeByName("\(module.utf8.count)\(module)\(name.utf8.count)\(name)\(kind)") { return type }
            }
        }
        return nil
    }

    /// Plays an album, artist, playlist or song in NaviMus. kind: "Album", "Artist", "Playlist", "Song".
    @objc public static func play(_ kind: String, id: String, completion: @escaping (Bool, String?) -> Void) {
        let label = ["Album": "_album", "Artist": "_artist"][kind] ?? "_entity"
        run(intent: "Play\(kind)Intent", entity: "\(kind)Entity", label: label, id: id, completion: completion)
    }

    /// Opens NaviMus's own page for an album, artist or playlist (its navigation stays in step).
    @objc public static func open(_ kind: String, id: String, completion: @escaping (Bool, String?) -> Void) {
        run(intent: "Open\(kind)Intent", entity: "\(kind)Entity", label: "_target", id: id, completion: completion)
    }

    /// NaviMus's play queue, read from its AudioManager (Arpeggi.AudioManager, an NSObject; 1.6.1 fields
    /// _currentQueueItem, _primaryQueue, _secondaryQueue, _continuousQueue, _queueHistory, each a Deque of QueueItem
    /// { id, song: Song, songFormatInfo, origin }). Keys are those field names; each song is a dictionary of id,
    /// title, artist, album, coverArt, albumId, artistId and duration (seconds).
    @objc public static func queue(_ manager: AnyObject) -> [String: Any] {
        var result: [String: Any] = [:]
        var mirror: Mirror? = Mirror(reflecting: manager)
        while let current = mirror {
            for child in current.children {
                guard let label = child.label else { continue }
                switch label {
                case "_primaryQueue", "_secondaryQueue", "_continuousQueue", "_queueHistory":
                    result[label] = Mirror(reflecting: child.value).children.compactMap { song(of: $0.value) }
                case "_currentQueueItem":
                    if let item = unwrap(child.value), let song = song(of: item) { result[label] = song }
                default:
                    break
                }
            }
            mirror = current.superclassMirror
        }
        return result
    }

    private static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private static func song(of item: Any) -> [String: Any]? {
        guard let song = Mirror(reflecting: item).children.first(where: { $0.label == "song" })?.value else { return nil }
        var out: [String: Any] = [:]
        for child in Mirror(reflecting: song).children {
            guard let label = child.label, let value = unwrap(child.value) else { continue }
            if ["id", "title", "artist", "album", "coverArt", "albumId", "artistId"].contains(label), let text = value as? String {
                out[label] = text
            } else if label == "duration", let seconds = value as? Int {
                out[label] = seconds
            }
        }
        return out["id"] == nil ? nil : out
    }

    /// Runs one of NaviMus's intents that take no parameters (LikeSongIntent: the playing song; probe build 33).
    @objc public static func perform(_ intentName: String, completion: @escaping (Bool, String?) -> Void) {
        let done: (Bool, String?) -> Void = { ok, why in DispatchQueue.main.async { completion(ok, why) } }
        guard let intentType = type(intentName) as? any AppIntent.Type else { return done(false, "\(intentName) not found") }
        Task { @MainActor in
            do {
                _ = try await intentType.init().perform()
                done(true, nil)
            } catch {
                done(false, "\(intentName) failed: \(error.localizedDescription)")
            }
        }
    }

    private static func run(intent intentName: String, entity entityName: String, label: String, id: String,
                            completion: @escaping (Bool, String?) -> Void) {
        let done: (Bool, String?) -> Void = { ok, why in DispatchQueue.main.async { completion(ok, why) } }
        guard let intentType = type(intentName) as? any AppIntent.Type else { return done(false, "\(intentName) not found") }
        guard let entityType = type(entityName) as? any AppEntity.Type else { return done(false, "\(entityName) not found") }
        Task { @MainActor in
            do {
                let why = try await perform(intentType, entityType: entityType, label: label, id: id)
                done(why == nil, why)
            } catch {
                done(false, "\(intentName) failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private static func perform<E: AppEntity>(_ intentType: any AppIntent.Type, entityType: E.Type, label: String,
                                              id: String) async throws -> String? {
        guard let identifier = id as? E.ID else { return "\(E.self) IDs aren't strings" }
        guard let entity = try await E.defaultQuery.entities(for: [identifier]).first else { return "no \(E.self) \(id)" }
        let intent = intentType.init()
        // IntentParameter is a class, so setting it through the mirrored reference sets the intent's own.
        var set = false
        for child in Mirror(reflecting: intent).children where child.label == label {
            if let parameter = child.value as? IntentParameter<E?> {
                parameter.wrappedValue = entity
                set = true
            } else if let parameter = child.value as? IntentParameter<E> {
                parameter.wrappedValue = entity
                set = true
            }
        }
        guard set else { return "\(intentType) has no \(label) for \(E.self)" }
        _ = try await intent.perform()
        return nil
    }
}
