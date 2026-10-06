import Foundation

/// Source assets are available before a project's first build or installation.
public enum ProjectIconSource {
    public static func candidates(projectPath: String) -> [URL] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let catalogs = [
            "ios/Runner/Assets.xcassets/AppIcon.appiconset",
            "macos/Runner/Assets.xcassets/AppIcon.appiconset"
        ]
        var result = catalogs.flatMap { catalogIcons(at: root.appendingPathComponent($0)) }
        result += ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi"].map {
            root.appendingPathComponent("android/app/src/main/res/mipmap-\($0)/ic_launcher.png")
        }
        result += ["web/icons/Icon-512.png", "web/icons/Icon-192.png", "web/favicon.png"].map {
            root.appendingPathComponent($0)
        }
        return result.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func catalogIcons(at directory: URL) -> [URL] {
        struct Catalog: Decodable {
            struct Icon: Decodable {
                let filename: String?
                let size: String?
                let scale: String?
                let appearances: [[String: String]]?
                var pixelSize: Double {
                    let points = Double(size?.split(separator: "x").first.map(String.init) ?? "") ?? 0
                    let multiplier = Double(scale?.replacingOccurrences(of: "x", with: "") ?? "1") ?? 1
                    return points * multiplier
                }
            }
            let images: [Icon]
        }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.images.filter { $0.appearances?.isEmpty != false }
            .sorted { $0.pixelSize > $1.pixelSize }
            .compactMap { icon in
                guard let filename = icon.filename, !filename.isEmpty,
                      filename == (filename as NSString).lastPathComponent,
                      filename != ".", filename != ".." else { return nil }
                return directory.appendingPathComponent(filename)
            }
    }
}
