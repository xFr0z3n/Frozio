// FZProbe: Swift reflection for what Objective-C can't see in NaviMus (docs/REDESIGN_PLAN.md, R0b/R0c).
//
// Every NaviMus page is a NavigationStackHostingController<AnyView>, so the class can't tell an album
// page from an artist page. The SwiftUI view inside the AnyView can: type metadata names (Arpeggi.…)
// survive the symbol stripping, and Mirror walks into AnyView's storage. Debug builds log them with the
// census; the redesign will use the same lookup to know which page NaviMus is pushing.
//
// It reports type and field *names* only, never a field's value.
import AppIntents
import SwiftUI
import UIKit

@objc(FZProbe)
public final class FZProbe: NSObject {
    private static let systemModules = ["SwiftUI.", "SwiftUICore.", "Swift.", "Foundation.", "Combine.", "UIKit.", "__C.", "AttributeGraph.", "CoreGraphics.", "Observation."]

    private static func isAppType(_ name: String) -> Bool {
        name.contains(".") && !name.hasPrefix("(") && !name.hasPrefix("__") && !systemModules.contains { name.hasPrefix($0) }
    }

    /// The first non-system type inside a SwiftUI value, walking AnyView storage and modifiers.
    static func appValue(in value: Any, depth: Int = 0) -> Any? {
        let name = String(reflecting: type(of: value))
        if depth > 0, isAppType(name) { return value }
        guard depth < 24 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = appValue(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    /// The type name of a hosting controller's root app view, e.g. "Arpeggi.AlbumDetailView", or nil.
    @objc public static func rootViewType(_ controller: UIViewController) -> String? {
        guard let host = controller as? UIHostingController<AnyView> else { return nil }
        guard let view = appValue(in: host.rootView) else { return nil }
        return String(reflecting: type(of: view))
    }

    /// "label: Type" for each stored field of that root view (names and types, no values).
    @objc public static func rootViewFields(_ controller: UIViewController) -> String? {
        guard let host = controller as? UIHostingController<AnyView>, let view = appValue(in: host.rootView) else { return nil }
        return Mirror(reflecting: view).children.map { "\($0.label ?? "?"): \(String(reflecting: type(of: $0.value)))" }
            .joined(separator: ", ")
    }

    /// NaviMus's App Intents and entities: which exist and what fields an instance has.
    @objc public static func intentSummary() -> String {
        let names = ["PlayAlbumIntent", "PlayArtistIntent", "PlayPlaylistIntent", "PlaySongIntent", "PlayGenreIntent",
                     "OpenAlbumIntent", "OpenArtistIntent", "OpenPlaylistIntent", "RandomMixIntent", "ResumeMusicIntent",
                     "LikeSongIntent", "AlbumEntity", "ArtistEntity", "PlaylistEntity", "SongEntity", "GenreEntity"]
        var lines: [String] = []
        for name in names {
            var found = false
            for kind in ["V", "C", "O"] {
                guard let type = _typeByName("7Arpeggi\(name.utf8.count)\(name)\(kind)") else { continue }
                found = true
                var line = "\(name) (\(kind)): \(String(reflecting: type))"
                if let intentType = type as? any AppIntent.Type {
                    let fields = Mirror(reflecting: intentType.init()).children
                        .map { "\($0.label ?? "?"): \(String(reflecting: Swift.type(of: $0.value)))" }
                    line += " fields [\(fields.joined(separator: ", "))]"
                } else if let entityType = type as? any AppEntity.Type {
                    line += " query \(String(reflecting: Swift.type(of: entityType.defaultQuery)))"
                }
                lines.append(line)
                break
            }
            if !found { lines.append("\(name): not found") }
        }
        return lines.joined(separator: "\n")
    }
}
