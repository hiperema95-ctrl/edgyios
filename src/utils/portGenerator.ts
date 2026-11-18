export interface PortBuildConfig {
  upstreamRepoUrl: string;
  upstreamBranch: string;
  iosRefRepoUrl: string;
  bundleId: string;
  appName: string;
  appVersion: string;
  deploymentTarget: '17.0' | '17.4' | '18.0';
  targetInstaller: 'both' | 'feather' | 'livecontainer';
  enable120HzProMotion: boolean;
  enableIncreasedMemoryLimit: boolean;
  enableVirtualGamepad: boolean;
  enableMetal3ArgumentBuffers: boolean;
  enableFileSharingApp: boolean;
  buildConfiguration: 'Release' | 'RelWithDebInfo';
}

export interface ShadowModItem {
  id: string;
  folderName: string;
  name: string;
  author: string;
  version: string;
  category: 'Graphics' | 'Gameplay' | 'Audio' | 'Skins' | 'UI';
  description: string;
  replacedAssets: string[];
  enabled: boolean;
}

export interface BuiltinCodePatch {
  id: string;
  title: string;
  category: 'Performance' | 'Graphics' | 'Controls' | 'QoL';
  author: string;
  description: string;
  enabled: boolean;
}

export interface XboxRequiredFile {
  relativePath: string;
  description: string;
  expectedMinSizeMB: number;
  verified: boolean;
}

export interface GeneratedRepositoryFile {
  path: string;
  title: string;
  language: 'yaml' | 'swift' | 'objc' | 'xml' | 'cmake' | 'bash' | 'markdown';
  description: string;
  content: string;
}

export const DEFAULT_BUILD_CONFIG: PortBuildConfig = {
  upstreamRepoUrl: 'https://github.com/FoxWorkshop/ShadowRecomp.git',
  upstreamBranch: 'main',
  iosRefRepoUrl: 'https://github.com/DevZer0D4Y/MarathonRecompilediOS',
  bundleId: 'com.foxworkshop.shadowrecomp.ios',
  appName: 'ShadowRecomp',
  appVersion: '1.1.0',
  deploymentTarget: '17.0',
  targetInstaller: 'both',
  enable120HzProMotion: true,
  enableIncreasedMemoryLimit: true,
  enableVirtualGamepad: true,
  enableMetal3ArgumentBuffers: true,
  enableFileSharingApp: true,
  buildConfiguration: 'Release',
};

export const INITIAL_XBOX_FILES: XboxRequiredFile[] = [
  {
    relativePath: 'default.xbe',
    description: 'Eseguibile principale Xbox (NTSC-U / PAL ver. verificata da XboxRecomp2)',
    expectedMinSizeMB: 4.8,
    verified: true,
  },
  {
    relativePath: 'files/ONE/shadow.one',
    description: 'Archivio RenderWare modello, animazioni ed effetti Chaos di Shadow',
    expectedMinSizeMB: 18.4,
    verified: true,
  },
  {
    relativePath: 'files/ONE/stage0100.one',
    description: 'Geometria e collisioni Westopolis (Stage 100)',
    expectedMinSizeMB: 42.1,
    verified: true,
  },
  {
    relativePath: 'files/ADX/s_bgm.afs',
    description: 'Streaming CRI ADX colonna sonora originale e tracce vocali',
    expectedMinSizeMB: 312.0,
    verified: true,
  },
  {
    relativePath: 'files/fnt/font_en.txd',
    description: 'Dizionario texture RenderWare font UI ed elementi HUD',
    expectedMinSizeMB: 2.1,
    verified: true,
  },
];

export const INITIAL_MODS: ShadowModItem[] = [
  {
    id: 'mod_hd_ui_xbox',
    folderName: 'Shadow_4K_HUD_DynamicIsland',
    name: '4K Xbox UI & Dynamic Island Safe Area',
    author: 'FoxWorkshop & Zer0D4Y',
    version: '2.1.0',
    category: 'UI',
    description: 'Sostituisce le texture HUD con asset vettoriali 4K e sposta i contatori Chaos/Armi fuori dalla Dynamic Island di iPhone 16 Pro.',
    replacedAssets: ['files/fnt/font_en.txd', 'files/ONE/ui_common.one'],
    enabled: true,
  },
  {
    id: 'mod_sa2_shadow_skin',
    folderName: 'SA2_Terios_Legacy_Pack',
    name: 'Sonic Adventure 2 Soap Shoes & Shaders',
    author: 'ChaosX',
    version: '1.4.2',
    category: 'Skins',
    description: 'Importa il modello high-poly di Shadow con Soap Shoes e riflessi speculari RenderWare nativi.',
    replacedAssets: ['files/ONE/shadow.one'],
    enabled: true,
  },
  {
    id: 'mod_reloaded_physics',
    folderName: 'Shadow_Reloaded_Physics',
    name: 'Shadow Reloaded Tweaks & Weapon Balance',
    author: ' LimblessVector',
    version: '3.0.1',
    category: 'Gameplay',
    description: 'Riduce lo scivolamento durante lo skate, migliora l’homing attack e bilancia i punti Hero/Dark delle missioni.',
    replacedAssets: ['files/ONE/player_param.one', 'files/ONE/stage0100.one'],
    enabled: true,
  },
  {
    id: 'mod_crush40_remaster',
    folderName: 'Crush40_Lossless_ADX',
    name: 'I Am... All of Me Lossless Audio Pack',
    author: 'VGM_Archiver',
    version: '1.0.0',
    category: 'Audio',
    description: 'Sostituisce lo stream ADX compresso con tracce ad alto bitrate 48kHz per speaker stereo e AirPods Pro.',
    replacedAssets: ['files/ADX/s_bgm.afs'],
    enabled: false,
  },
];

export const INITIAL_CODES: BuiltinCodePatch[] = [
  {
    id: 'fps_120_promotion',
    title: 'Unlock 120 FPS ProMotion (A18 Pro)',
    category: 'Performance',
    author: 'DevZer0D4Y',
    description: 'Disaccoppia il tick di fisica RenderWare (60Hz fissi) dall’interpolazione della camera Metal 3 fino a 120Hz su iPhone 16 Pro.',
    enabled: true,
  },
  {
    id: 'widescreen_19_5_9',
    title: 'Aspect Ratio 19.5:9 Full Display',
    category: 'Graphics',
    author: 'FoxWorkshop',
    description: 'Estende l’angolo di campo orizzontale Hor+ per riempire i 2622×1206 pixel di iPhone 16 Pro mantenendo l’HUD centrato in 16:9.',
    enabled: true,
  },
  {
    id: 'disable_xbox_trail_blur',
    title: 'Rimuovi Xbox Framebuffer Ghosting',
    category: 'Graphics',
    author: 'FoxWorkshop',
    description: 'Disabilita il post-processing a 640x480 dell’Xbox originale che causava sfocatura ad alte risoluzioni.',
    enabled: true,
  },
  {
    id: 'livecontainer_jitless_heap',
    title: 'Allocatore Statico JIT-less (LiveContainer / Feather)',
    category: 'Performance',
    author: 'DevZer0D4Y',
    description: 'Mappa i 64MB di RAM contigua Xbox usando mmap statico compatibile senza entitlement JIT.',
    enabled: true,
  },
  {
    id: 'skip_startup_fmv',
    title: 'Fast Boot al Title Screen',
    category: 'QoL',
    author: 'Community',
    description: 'Salta i loghi SEGA, Sonic Team e CRIWare all’avvio del motore.',
    enabled: false,
  },
];

export function parseModIniContent(rawIni: string, fallbackFolderName: string): Omit<ShadowModItem, 'id' | 'enabled'> {
  const lines = rawIni.split(/\r?\n/);
  const map: Record<string, string> = {};
  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed || trimmed.startsWith(';') || trimmed.startsWith('#') || trimmed.startsWith('[')) {
      continue;
    }
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx > 0) {
      const key = trimmed.slice(0, eqIdx).trim().toLowerCase();
      const val = trimmed.slice(eqIdx + 1).trim().replace(/^"(.*)"$/, '$1');
      map[key] = val;
    }
  }

  const rawCategory = (map['category'] || 'Gameplay').toLowerCase();
  let category: ShadowModItem['category'] = 'Gameplay';
  if (rawCategory.includes('graph') || rawCategory.includes('shader')) category = 'Graphics';
  else if (rawCategory.includes('aud') || rawCategory.includes('music')) category = 'Audio';
  else if (rawCategory.includes('skin') || rawCategory.includes('char') || rawCategory.includes('model')) category = 'Skins';
  else if (rawCategory.includes('ui') || rawCategory.includes('hud')) category = 'UI';

  const replaced = map['include']
    ? map['include'].split(',').map((s) => s.trim()).filter(Boolean)
    : ['files/ONE/shadow.one'];

  return {
    folderName: fallbackFolderName.replace(/[^a-zA-Z0-9_-]/g, '_'),
    name: map['name'] || fallbackFolderName,
    author: map['author'] || 'Community Modder',
    version: map['version'] || '1.0.0',
    category,
    description: map['description'] || 'Mod compatibile con ShadowRecomp importata tramite App File di iOS.',
    replacedAssets: replaced,
  };
}

export function generateModsConfigToml(mods: ShadowModItem[], codes: BuiltinCodePatch[], config: PortBuildConfig): string {
  const activeMods = mods.filter((m) => m.enabled);
  const modLines = activeMods.map((m) => `  "${m.folderName}",`).join('\n');
  const codeLines = codes.map((c) => `${c.id} = ${c.enabled ? 'true' : 'false'}`).join('\n');

  return `# Generato da ShadowRecompiOS Launcher (ispirato a MarathonRecompilediOS)
# Percorso su iPhone: /var/mobile/Containers/Data/Application/<UUID>/Documents/ModsConfig.toml

[System]
TargetDevice = "iPhone17,1 (iPhone 16 Pro - A18 Pro)"
BundleIdentifier = "${config.bundleId}"
GraphicsBackend = "${config.enableMetal3ArgumentBuffers ? 'PlumeMetal3' : 'PlumeMoltenVK'}"
MaxRefreshRate = ${config.enable120HzProMotion ? 120 : 60}
VirtualControllerOverlay = ${config.enableVirtualGamepad ? 'true' : 'false'}
GameDataPath = "Documents/GameData"
ModsDirectory = "Documents/Mods"

[Mods]
# Ordine di priorità (dall'alto verso il basso)
ActiveMods = [
${modLines}
]

[Codes]
${codeLines}
`;
}

export function resolveVirtualFileSystemPath(
  xboxPath: string,
  mods: ShadowModItem[]
): { resolvedPath: string; sourceModName: string | null } {
  const cleanRel = xboxPath
    .replace(/^[dD]:[\\/]+/, '')
    .replace(/\\/g, '/')
    .replace(/^\/+/, '');

  for (const mod of mods) {
    if (!mod.enabled) continue;
    const matches = mod.replacedAssets.some(
      (asset) => asset.toLowerCase() === cleanRel.toLowerCase()
    );
    if (matches) {
      return {
        resolvedPath: `Documents/Mods/${mod.folderName}/${cleanRel}`,
        sourceModName: mod.name,
      };
    }
  }

  return {
    resolvedPath: `Documents/GameData/${cleanRel}`,
    sourceModName: null,
  };
}

export function generateGitHubWorkflowYaml(config: PortBuildConfig): string {
  const liveContainerFlags =
    config.targetInstaller === 'livecontainer' || config.targetInstaller === 'both'
      ? `-Wl,-pie -fPIC`
      : ``;

  return `name: Build ShadowRecomp iOS Unsigned IPA (No-Mac Cloud Builder)

on:
  workflow_dispatch:
    inputs:
      build_configuration:
        description: 'Configurazione di compilazione CMake/Xcode'
        required: true
        default: '${config.buildConfiguration}'
        type: choice
        options:
          - Release
          - RelWithDebInfo
      upstream_branch:
        description: 'Branch o Tag di FoxWorkshop/ShadowRecomp'
        required: true
        default: '${config.upstreamBranch}'
        type: string
  push:
    branches: [ main ]

env:
  APP_NAME: "${config.appName}"
  BUNDLE_ID: "${config.bundleId}"
  APP_VERSION: "${config.appVersion}"
  IOS_DEPLOYMENT_TARGET: "${config.deploymentTarget}"
  UPSTREAM_REPO: "${config.upstreamRepoUrl}"

jobs:
  build-shadowrecomp-ios-ipa:
    name: Build Unsigned IPA on GitHub macOS-15 (iPhone 16 Pro / arm64)
    runs-on: macos-15
    permissions:
      contents: write
    steps:
      - name: 1. Checkout iOS Port Repository (Questo Repo)
        uses: actions/checkout@v4
        with:
          path: ios-port

      - name: 2. Clone FoxWorkshop/ShadowRecomp con Submodules
        run: |
          git clone --recursive --branch "\${{ inputs.upstream_branch || '${config.upstreamBranch}' }}" "\${UPSTREAM_REPO}" ShadowRecomp-Upstream

      - name: 3. Seleziona Xcode 16.2 & Installa Dipendenze nel Cloud
        run: |
          sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer
          xcodebuild -version
          brew update
          brew install cmake ninja ldid pkg-config python3 llvm

      - name: 4. Compila i Tool di Ricompilazione Statica (XboxRecomp2 & XShaderRecomp)
        working-directory: ShadowRecomp-Upstream
        run: |
          # Compila sul runner macOS gli strumenti che convertono gli shader Xbox NV2A in Metal/SPIR-V
          # e preparano il codice statico C++ senza bisogno di un Mac locale
          cmake -B build-host -G Ninja \\
            -DCMAKE_BUILD_TYPE=Release \\
            -DSHADOW_BUILD_HOST_TOOLS=ON
          cmake --build build-host --parallel

      - name: 5. Applica Patch iOS (UIKit Launcher, Mod Manager & Metal Backend)
        run: |
          chmod +x ios-port/scripts/apply_ios_port.sh
          ./ios-port/scripts/apply_ios_port.sh "${'$'}{GITHUB_WORKSPACE}/ShadowRecomp-Upstream" "${'$'}{GITHUB_WORKSPACE}/ios-port"

      - name: 6. Configura CMake per iOS arm64 (iPhone 16 Pro - A18 Pro)
        working-directory: ShadowRecomp-Upstream
        run: |
          cmake -B build-ios -G Xcode \\
            -DCMAKE_SYSTEM_NAME=iOS \\
            -DCMAKE_OSX_ARCHITECTURES=arm64 \\
            -DCMAKE_OSX_DEPLOYMENT_TARGET="\${IOS_DEPLOYMENT_TARGET}" \\
            -DCMAKE_OSX_SYSROOT=iphoneos \\
            -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER="\${BUNDLE_ID}" \\
            -DCMAKE_XCODE_ATTRIBUTE_MARKETING_VERSION="\${APP_VERSION}" \\
            -DCMAKE_C_FLAGS="-march=armv8.6-a+simd+crypto ${liveContainerFlags}" \\
            -DCMAKE_CXX_FLAGS="-march=armv8.6-a+simd+crypto ${liveContainerFlags}" \\
            -DSHADOW_HOST_TOOLS_DIR="${'$'}{GITHUB_WORKSPACE}/ShadowRecomp-Upstream/build-host" \\
            -DSHADOW_IOS_PORT=ON \\
            -DPLUME_METAL_BACKEND=${config.enableMetal3ArgumentBuffers ? 'ON' : 'OFF'} \\
            -DSHADOW_PROMOTION_120HZ=${config.enable120HzProMotion ? 'ON' : 'OFF'} \\
            -DSDL_STATIC=ON \\
            -DSDL_SHARED=OFF

      - name: 7. Compila ShadowRecomp.app (Unsigned arm64)
        working-directory: ShadowRecomp-Upstream
        run: |
          CONFIG="\${{ inputs.build_configuration || '${config.buildConfiguration}' }}"
          xcodebuild build \\
            -project build-ios/ShadowRecomp.xcodeproj \\
            -scheme "\${APP_NAME}" \\
            -configuration "\${CONFIG}" \\
            -sdk iphoneos \\
            -arch arm64 \\
            CODE_SIGN_IDENTITY="" \\
            CODE_SIGNING_REQUIRED=NO \\
            CODE_SIGNING_ALLOWED=NO \\
            AD_HOC_CODE_SIGNING_ALLOWED=YES

      - name: 8. Firma Ad-Hoc con ldid & Impacchetta IPA per Feather e LiveContainer
        run: |
          CONFIG="\${{ inputs.build_configuration || '${config.buildConfiguration}' }}"
          APP_BUNDLE="ShadowRecomp-Upstream/build-ios/\${CONFIG}-iphoneos/\${APP_NAME}.app"

          rm -rf Payload
          mkdir -p Payload
          cp -R "\${APP_BUNDLE}" "Payload/\${APP_NAME}.app"

          # Copia Info.plist aggiornato con supporto App File e 120Hz ProMotion
          cp ios-port/ios/Info.plist "Payload/\${APP_NAME}.app/Info.plist"

          # Applica gli entitlements (increased-memory-limit per evitare crash RAM su iOS)
          ldid -Sios-port/ios/Entitlements.plist "Payload/\${APP_NAME}.app/\${APP_NAME}"
          chmod +x "Payload/\${APP_NAME}.app/\${APP_NAME}"

          # Genera il pacchetto .ipa finale
          zip -qry "\${APP_NAME}-iOS-v\${APP_VERSION}-Unsigned.ipa" Payload
          shasum -a 256 "\${APP_NAME}-iOS-v\${APP_VERSION}-Unsigned.ipa" > "\${APP_NAME}-iOS-v\${APP_VERSION}-Unsigned.ipa.sha256"

      - name: 9. Carica File IPA pronto da scaricare su iPhone
        uses: actions/upload-artifact@v4
        with:
          name: \${{ env.APP_NAME }}-iOS-Unsigned-IPA
          path: |
            \${{ env.APP_NAME }}-iOS-v\${{ env.APP_VERSION }}-Unsigned.ipa
            \${{ env.APP_NAME }}-iOS-v\${{ env.APP_VERSION }}-Unsigned.ipa.sha256
          retention-days: 90
`;
}

export function generateAllRepositoryFiles(config: PortBuildConfig): GeneratedRepositoryFile[] {
  const workflowYml = generateGitHubWorkflowYaml(config);

  const infoPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>it</string>
    <key>CFBundleDisplayName</key>
    <string>${config.appName}</string>
    <key>CFBundleExecutable</key>
    <string>${config.appName}</string>
    <key>CFBundleIdentifier</key>
    <string>${config.bundleId}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${config.appName}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${config.appVersion}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>${config.deploymentTarget}</string>

    <!-- ProMotion 120Hz su iPhone 16 Pro -->
    <key>CADisableMinimumFrameDurationOnPhone</key>
    <${config.enable120HzProMotion ? 'true' : 'false'}/>

    <!-- Visibilità completa nell'App File di iOS ("Su iPhone -> ${config.appName}") -->
    <key>UIFileSharingEnabled</key>
    <${config.enableFileSharingApp ? 'true' : 'false'}/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <${config.enableFileSharingApp ? 'true' : 'false'}/>
    <key>UISupportsDocumentBrowser</key>
    <false/>

    <!-- Landscape Fullscreen -->
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIRequiresFullScreen</key>
    <true/>
    <key>UIStatusBarHidden</key>
    <true/>
    <key>UIViewControllerBasedStatusBarAppearance</key>
    <false/>

    <!-- Supporto Controller Bluetooth (DualSense, Xbox, Backbone One USB-C) -->
    <key>GCSupportedGameControllers</key>
    <array>
        <dict>
            <key>ProfileName</key>
            <string>ExtendedGamepad</string>
        </dict>
    </array>
</dict>
</plist>`;

  const entitlementsPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.kernel.increased-memory-limit</key>
    <${config.enableIncreasedMemoryLimit ? 'true' : 'false'}/>
    <key>com.apple.developer.kernel.extended-virtual-addressing</key>
    <true/>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>`;

  const swiftLauncher = `// ios/ShadowRecompLauncherView.swift
// Ispirato a DevZer0D4Y/MarathonRecompilediOS - Adattato per FoxWorkshop/ShadowRecomp
// Gestisce:
// 1. Primo avvio con selezione file Xbox (default.xbe + cartella files/) dall'app File di iOS
// 2. Mod Manager completo (importazione cartelle mod con mod.ini, toggle e ordine di priorità)
// 3. Patch & Codes 120Hz ProMotion per iPhone 16 Pro

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
    @Published var enable120Hz: Bool = ${config.enable120HzProMotion}
    @Published var enableWidescreen19_5_9: Bool = true
    @Published var enableTouchOverlay: Bool = ${config.enableVirtualGamepad}

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
        let active = mods.filter(\\.isEnabled).map { "  \\"\\($0.folderName)\\"" }.joined(separator: ",\\n")
        let toml = """
        [System]
        MaxRefreshRate = \\(enable120Hz ? 120 : 60)
        Widescreen19_5_9 = \\(enableWidescreen19_5_9)
        TouchGamepad = \\(enableTouchOverlay)

        [Mods]
        ActiveMods = [
        \\(active)
        ]
        """
        try? toml.write(to: documentsURL.appendingPathComponent("ModsConfig.toml"), atomically: true, encoding: .utf8)
    }
}`;

  const objcBridge = `// ios/IOSVFSBridge.mm
// Reindirizza il Virtual File System Xbox (D:\\) di FoxWorkshop/ShadowRecomp
// verso la sandbox iOS (Documents/GameData e Documents/Mods) e configura SDL/Metal.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <filesystem>
#include <string>
#include <vector>

namespace ShadowRecomp::iOS {

std::filesystem::path GetDocumentsRoot() {
    NSArray<NSURL *> *paths = [[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    return std::filesystem::path([[paths firstObject] fileSystemRepresentation]);
}

std::filesystem::path ResolveXboxFile(const std::string& rawXboxPath, const std::vector<std::string>& activeModFolders) {
    std::string rel = rawXboxPath;
    if (rel.rfind("D:\\\\", 0) == 0 || rel.rfind("d:\\\\", 0) == 0) {
        rel = rel.substr(3);
    }
    std::replace(rel.begin(), rel.end(), '\\\\', '/');

    auto docs = GetDocumentsRoot();
    // 1. Priorità alle Mod abilitate nel Mod Manager iOS
    for (const auto& modFolder : activeModFolders) {
        auto candidate = docs / "Mods" / modFolder / rel;
        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
    }

    // 2. Fallback ai file del gioco base importati dall'App File
    return docs / "GameData" / rel;
}

} // namespace ShadowRecomp::iOS`;

  const applyScript = `#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_DIR="$1"
PORT_DIR="$2"

echo "==> Applicazione patch iOS a FoxWorkshop/ShadowRecomp..."
mkdir -p "\${UPSTREAM_DIR}/ios"
cp -R "\${PORT_DIR}/ios/"* "\${UPSTREAM_DIR}/ios/"

# Aggiunge la configurazione iOS/Metal al CMakeLists.txt principale se non presente
if ! grep -q "SHADOW_IOS_PORT" "\${UPSTREAM_DIR}/CMakeLists.txt"; then
  cat "\${PORT_DIR}/cmake/iOSPortTarget.cmake" >> "\${UPSTREAM_DIR}/CMakeLists.txt"
fi

echo "==> Patch iOS applicata con successo."`;

  const cmakePatch = `# cmake/iOSPortTarget.cmake
# Configurazione automatica del bundle iOS per ShadowRecomp su GitHub Actions
if(SHADOW_IOS_PORT)
    message(STATUS "Configuring ShadowRecomp for iOS arm64 (iPhone 16 Pro / Metal 3)")
    enable_language(OBJC OBJCXX Swift)

    target_sources(ShadowRecomp PRIVATE
        "\${CMAKE_CURRENT_SOURCE_DIR}/ios/ShadowRecompLauncherView.swift"
        "\${CMAKE_CURRENT_SOURCE_DIR}/ios/IOSVFSBridge.mm"
    )

    set_target_properties(ShadowRecomp PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "\${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_COMBINE_HIDPI_IMAGES "YES"
        XCODE_ATTRIBUTE_SWIFT_VERSION "5.10"
    )

    target_link_libraries(ShadowRecomp PRIVATE
        "-framework UIKit"
        "-framework SwiftUI"
        "-framework Metal"
        "-framework MetalKit"
        "-framework QuartzCore"
        "-framework GameController"
        "-framework CoreHaptics"
        "-framework AVFoundation"
        "-framework UniformTypeIdentifiers"
    )
endif()`;

  const readmeMd = `# ShadowRecomp iOS Cloud Builder (Zero-Mac Setup)

Questo repository compila automaticamente **ShadowRecomp** (\`FoxWorkshop/ShadowRecomp\`) in un file **\`.ipa\` unsigned** per **iPhone 16 Pro** (e dispositivi iOS \`arm64\`) direttamente sui server gratuiti \`macos-15\` di **GitHub Actions**, senza bisogno di possedere un Mac.

Include il **Launcher & Mod Manager nativo iOS** ispirato a \`DevZer0D4Y/MarathonRecompilediOS\`.

## Come ottenere il file \`.ipa\` in 3 minuti (Senza Mac)
1. Crea un nuovo repository su GitHub dal browser o dall'app GitHub.
2. Carica tutti i file generati da questo pacchetto (inclusa la cartella \`.github/workflows/\`).
3. Vai nella scheda **Actions** del tuo repository GitHub.
4. Seleziona **Build ShadowRecomp iOS Unsigned IPA (No-Mac Cloud Builder)** e premi **Run workflow**.
5. Al termine della compilazione (~6-8 minuti), scorri in basso fino a **Artifacts** e scarica **\`${config.appName}-iOS-Unsigned-IPA\`** direttamente sul tuo iPhone 16 Pro.

## Installazione su iPhone 16 Pro
- **Tramite Feather**: Importa il file \`.ipa\` in Feather, firma con il tuo certificato e installa.
- **Tramite LiveContainer**: Importa il file \`.ipa\` dentro LiveContainer e avvialo direttamente (non serve JIT perché il binario Xbox \`default.xbe\` viene ricompilato staticamente in codice nativo \`arm64\`).

## Primo Avvio & Caricamento File di Gioco dall'App File
1. Apri **${config.appName}** su iPhone 16 Pro.
2. Comparirà la schermata **Primo Avvio & File Gioco**.
3. Tocca **"Seleziona Cartella Gioco dall'App File"** e seleziona la cartella del tuo dump Xbox (contenente \`default.xbe\` e la sottocartella \`files/\`), oppure copia i file manualmente dall'app **File → Su iPhone → ${config.appName} → GameData**.
4. Nella scheda **Mod Manager** tocca **"Importa Mod da File"** per aggiungere mod compatibili (\`mod.ini\`), riordinarle o attivare i **120 FPS ProMotion**.`;

  return [
    {
      path: '.github/workflows/build-ios-ipa.yml',
      title: 'GitHub Action Cloud Builder (.yml)',
      language: 'yaml',
      description: 'Compila XboxRecomp2, gli shader Metal e genera l’IPA unsigned nel cloud di GitHub senza Mac.',
      content: workflowYml,
    },
    {
      path: 'ios/ShadowRecompLauncherView.swift',
      title: 'Launcher & Mod Manager SwiftUI',
      language: 'swift',
      description: 'Interfaccia nativa stile MarathonRecompilediOS per importare i file di gioco e le mod dall’app File di iOS.',
      content: swiftLauncher,
    },
    {
      path: 'ios/IOSVFSBridge.mm',
      title: 'Bridge VFS Xbox -> iOS Sandbox',
      language: 'objc',
      description: 'Mappa il disco Xbox D:\\ su Documents/GameData e applica l’override delle mod attive in Documents/Mods.',
      content: objcBridge,
    },
    {
      path: 'ios/Info.plist',
      title: 'Info.plist (App File + 120Hz ProMotion)',
      language: 'xml',
      description: 'Abilita UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace e CADisableMinimumFrameDurationOnPhone.',
      content: infoPlist,
    },
    {
      path: 'ios/Entitlements.plist',
      title: 'Entitlements.plist (ldid Extended RAM)',
      language: 'xml',
      description: 'Entitlement increased-memory-limit applicato via ldid per evitare limiti di memoria su iPhone 16 Pro.',
      content: entitlementsPlist,
    },
    {
      path: 'cmake/iOSPortTarget.cmake',
      title: 'CMake iOS Target & Frameworks',
      language: 'cmake',
      description: 'Configura Metal, MetalKit, GameController, CoreHaptics e SwiftUI nel progetto CMake.',
      content: cmakePatch,
    },
    {
      path: 'scripts/apply_ios_port.sh',
      title: 'Script Automatico di Patch CI',
      language: 'bash',
      description: 'Eseguito dalla GitHub Action per iniettare il codice iOS nel clone fresco di FoxWorkshop/ShadowRecomp.',
      content: applyScript,
    },
    {
      path: 'README.md',
      title: 'Guida Passo-Passo Zero-Mac',
      language: 'markdown',
      description: 'Istruzioni complete per eseguire la GitHub Action dal browser e installare l’IPA su Feather o LiveContainer.',
      content: readmeMd,
    },
  ];
}
