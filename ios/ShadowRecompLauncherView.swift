import SwiftUI
import UniformTypeIdentifiers

struct ShadowModEntry: Identifiable, Codable, Equatable {
    var id: String { folderName }
    var folderName: String
    var name: String
    var author: String
    var version: String
    var isEnabled: Bool
}

@MainActor
final class ShadowLauncherViewModel: ObservableObject {
    @Published var isGameReady: Bool = false
    @Published var missingFiles: [String] = []
    @Published var mods: [ShadowModEntry] = []
    @Published var enable120Hz: Bool = true
    @Published var enableWidescreen19_5_9: Bool = true
    @Published var enableTouchOverlay: Bool = true

    let requiredXboxFiles = [
        "default.xbe",
        "files/ONE/shadow.one",
        "files/ONE/stage0100.one",
        "files/ADX/s_bgm.afs"
    ]

    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    var gameDataURL: URL { documentsURL.appendingPathComponent("GameData", isDirectory: true) }
    var modsURL: URL { documentsURL.appendingPathComponent("Mods", isDirectory: true) }

    init() {
        try? FileManager.default.createDirectory(at: gameDataURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
        verifyGameFiles()
        scanMods()
    }

    func verifyGameFiles() {
        missingFiles = requiredXboxFiles.filter { rel in
            !FileManager.default.fileExists(atPath: gameDataURL.appendingPathComponent(rel).path)
        }
        isGameReady = missingFiles.isEmpty
    }

    func importFromFilesApp(urls: [URL], isMod: Bool) {
        let fm = FileManager.default
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let targetRoot = isMod ? modsURL.appendingPathComponent(url.lastPathComponent) : gameDataURL
            if isMod {
                try? fm.removeItem(at: targetRoot)
                try? fm.copyItem(at: url, to: targetRoot)
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            let rel = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                            let dst = targetRoot.appendingPathComponent(rel)
                            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try? fm.copyItem(at: fileURL, to: dst)
                        }
                    }
                } else {
                    let dst = targetRoot.appendingPathComponent(url.lastPathComponent)
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: url, to: dst)
                }
            }
        }
        verifyGameFiles()
        scanMods()
        writeModsConfigToml()
    }

    func scanMods() {
        guard let items = try? FileManager.default.contentsOfDirectory(at: modsURL, includingPropertiesForKeys: nil) else { return }
        mods = items.compactMap { folder in
            let iniURL = folder.appendingPathComponent("mod.ini")
            guard let ini = try? String(contentsOf: iniURL, encoding: .utf8) else { return nil }
            var name = folder.lastPathComponent
            var author = "Community"
            var version = "1.0"
            for line in ini.components(separatedBy: .newlines) {
                let p = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count == 2 {
                    if p[0].lowercased() == "name" { name = p[1] }
                    if p[0].lowercased() == "author" { author = p[1] }
                    if p[0].lowercased() == "version" { version = p[1] }
                }
            }
            return ShadowModEntry(folderName: folder.lastPathComponent, name: name, author: author, version: version, isEnabled: true)
        }
    }

    func writeModsConfigToml() {
        let active = mods.filter(\.isEnabled).map { "  \"\($0.folderName)\"" }.joined(separator: ",\n")
        let toml = """
        [System]
        MaxRefreshRate = \(enable120Hz ? 120 : 60)
        Widescreen19_5_9 = \(enableWidescreen19_5_9)
        TouchGamepad = \(enableTouchOverlay)

        [Mods]
        ActiveMods = [
        \(active)
        ]
        """
        try? toml.write(to: documentsURL.appendingPathComponent("ModsConfig.toml"), atomically: true, encoding: .utf8)
    }
}
