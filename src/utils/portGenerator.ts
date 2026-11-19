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
  enableMoltenVKMetal3: boolean;
  enableFileSharingApp: boolean;
  buildConfiguration: 'Release' | 'RelWithDebInfo';
}

export interface ShadowModProfileEntry {
  folderName: string;
  name: string;
  author: string;
  version: string;
  enabled: boolean;
}

export interface GeneratedRepositoryFile {
  path: string;
  title: string;
  language: 'yaml' | 'objc' | 'cpp' | 'xml' | 'cmake' | 'bash' | 'markdown';
  description: string;
  content: string;
}

export const DEFAULT_BUILD_CONFIG: PortBuildConfig = {
  upstreamRepoUrl: 'https://github.com/FoxWorkshop/ShadowRecomp.git',
  upstreamBranch: 'master',
  iosRefRepoUrl: 'https://github.com/DevZer0D4Y/MarathonRecompilediOS',
  bundleId: 'com.foxworkshop.shadowrecomp.ios',
  appName: 'ShadowRecomp',
  appVersion: '1.0.0',
  deploymentTarget: '17.0',
  targetInstaller: 'both',
  enable120HzProMotion: true,
  enableIncreasedMemoryLimit: true,
  enableVirtualGamepad: true,
  enableMoltenVKMetal3: true,
  enableFileSharingApp: true,
  buildConfiguration: 'Release',
};

export function generateShadowRecompModProfileJson(mods: ShadowModProfileEntry[]): {
  profilesJson: string;
  defaultProfileJson: string;
} {
  const profilesObj = {
    ProfileIndex: 0,
    ProfilesList: [
      {
        Name: 'Default',
        Filename: 'Default.json',
      },
    ],
  };

  const defaultObj = {
    EnabledMods: mods.filter((m) => m.enabled).map((m) => m.folderName),
  };

  return {
    profilesJson: JSON.stringify(profilesObj, null, 2),
    defaultProfileJson: JSON.stringify(defaultObj, null, 2),
  };
}

export function generateGitHubWorkflowYaml(config: PortBuildConfig): string {
  const pieFlags =
    config.targetInstaller === 'livecontainer' || config.targetInstaller === 'both'
      ? '-Wl,-pie -fPIC'
      : '';

  return `name: Build ShadowRecomp iOS Unsigned IPA (No-Mac Cloud Builder)

on:
  workflow_dispatch:
    inputs:
      build_configuration:
        description: 'Configurazione CMake/Xcode'
        required: true
        default: '${config.buildConfiguration}'
        type: choice
        options:
          - Release
          - RelWithDebInfo
      upstream_branch:
        description: 'Branch di FoxWorkshop/ShadowRecomp (default: master)'
        required: true
        default: '${config.upstreamBranch}'
        type: string
      default_xbe_url:
        description: 'URL diretto opzionale al tuo default.xbe (4.8MB) se non presente in private/default.xbe'
        required: false
        default: ''
        type: string
  push:
    branches: [ main, master ]

env:
  APP_NAME: "${config.appName}"
  BUNDLE_ID: "${config.bundleId}"
  APP_VERSION: "${config.appVersion}"
  IOS_DEPLOYMENT_TARGET: "${config.deploymentTarget}"
  UPSTREAM_REPO: "${config.upstreamRepoUrl}"
  MOLTENVK_VERSION: "v1.2.11"
  FREETYPE_VERSION: "2.13.3"

jobs:
  build-shadowrecomp-ios-ipa:
    name: Build Unsigned IPA on GitHub macOS-15 (iPhone 16 Pro / arm64)
    runs-on: macos-15
    timeout-minutes: 90
    permissions:
      contents: read
    steps:
      - name: 1. Checkout Repository Porting iOS
        uses: actions/checkout@v4
        with:
          path: ios-port

      - name: 2. Clone FoxWorkshop/ShadowRecomp (branch master + submodules)
        run: |
          BRANCH="\${{ inputs.upstream_branch || '${config.upstreamBranch}' }}"
          echo "==> Cloning \${UPSTREAM_REPO} (branch: \${BRANCH})..."
          if git ls-remote --exit-code --heads "\${UPSTREAM_REPO}" "\${BRANCH}" >/dev/null 2>&1; then
            git clone --depth 1 --branch "\${BRANCH}" "\${UPSTREAM_REPO}" ShadowRecomp-Upstream
          else
            echo "WARN: Branch '\${BRANCH}' non trovato, uso il branch predefinito del repository upstream."
            git clone --depth 1 "\${UPSTREAM_REPO}" ShadowRecomp-Upstream
          fi

          cd ShadowRecomp-Upstream
          # Inizializza tutti i submodule reali di ShadowRecomp tranne vcpkg completo (usiamo toolchain iOS dedicata)
          git submodule sync --recursive
          for sub in thirdparty/SDL thirdparty/SDL_mixer thirdparty/plume thirdparty/imgui thirdparty/implot \\
                     thirdparty/msdf-atlas-gen thirdparty/o1heap thirdparty/stb thirdparty/ddspp \\
                     thirdparty/unordered_dense thirdparty/concurrentqueue thirdparty/ogg thirdparty/vorbis \\
                     thirdparty/discord-rpc ShadowRecompResources tools/bc_diff tools/XboxRecomp \\
                     tools/XboxRecomp2 tools/XShaderRecomp tools/file_to_c; do
            if git config -f .gitmodules --get "submodule.\${sub}.path" >/dev/null 2>&1; then
              echo "==> Init submodule: \${sub}"
              git submodule update --init --recursive --depth 1 "\${sub}" || git submodule update --init --recursive "\${sub}"
            fi
          done

      - name: 3. Verifica default.xbe per Ricompilazione Statica XboxRecomp2
        env:
          SECRET_XBE_URL: \${{ secrets.DEFAULT_XBE_URL }}
          INPUT_XBE_URL: \${{ inputs.default_xbe_url }}
        run: |
          TARGET_XBE="\${GITHUB_WORKSPACE}/ShadowRecomp-Upstream/ShadowRecompLib/private/default.xbe"
          mkdir -p "\$(dirname "\${TARGET_XBE}")"

          if [ -f "ios-port/private/default.xbe" ]; then
            echo "==> Trovato ios-port/private/default.xbe"
            cp "ios-port/private/default.xbe" "\${TARGET_XBE}"
          elif [ -f "ios-port/default.xbe" ]; then
            echo "==> Trovato ios-port/default.xbe"
            cp "ios-port/default.xbe" "\${TARGET_XBE}"
          elif [ -n "\${INPUT_XBE_URL}" ]; then
            echo "==> Download default.xbe da input workflow..."
            curl -fSL "\${INPUT_XBE_URL}" -o "\${TARGET_XBE}"
          elif [ -n "\${SECRET_XBE_URL}" ]; then
            echo "==> Download default.xbe da GitHub Secret DEFAULT_XBE_URL..."
            curl -fSL "\${SECRET_XBE_URL}" -o "\${TARGET_XBE}"
          else
            echo "::error::MANCA default.xbe (~4.8MB) per la ricompilazione statica!"
            echo "================================================================================"
            echo "NOTA TECNICA (come MarathonRecompilediOS / Sonic '06):"
            echo "L'IPA finale pesa solo ~34MB e NON contiene i 4GB del gioco (.iso/texture/audio):"
            echo "quelli li importerai al primo avvio dall'App File sul tuo iPhone 16 Pro."
            echo ""
            echo "MA per ricompilare staticamente il codice macchina Xbox in codice nativo arm64"
            echo "senza JIT (tramite XboxRecomp2), GitHub Actions ha bisogno SOLO del file"
            echo "default.xbe (~4.8MB) estratto dal tuo disco originale di Shadow the Hedgehog."
            echo ""
            echo "SOLUZIONE RAPIDA (dal browser, senza Mac):"
            echo "1. Carica il tuo file default.xbe in questo repo PRIVATO nel percorso:"
            echo "      private/default.xbe"
            echo "   OPPURE imposta il Secret GitHub DEFAULT_XBE_URL / parametro default_xbe_url."
            echo "2. Rilancia questa GitHub Action."
            echo "================================================================================"
            exit 1
          fi
          ls -lh "\${TARGET_XBE}"

      - name: 4. Configura Xcode, Rust, MoltenVK (iOS arm64), DXC & FreeType
        run: |
          if [ -d "/Applications/Xcode_16.2.app/Contents/Developer" ]; then
            sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer
          fi
          xcodebuild -version
          brew install cmake ninja ldid pkg-config zstd

          # 4a. Scarica MoltenVK ufficiale per iOS arm64 (traduce Vulkan/SPIR-V di Plume in Apple Metal 3)
          mkdir -p "\${GITHUB_WORKSPACE}/ios-deps/moltenvk"
          curl -fSL "https://github.com/KhronosGroup/MoltenVK/releases/download/\${MOLTENVK_VERSION}/MoltenVK-all.tar" -o /tmp/MoltenVK-all.tar
          tar -xf /tmp/MoltenVK-all.tar -C "\${GITHUB_WORKSPACE}/ios-deps/moltenvk"
          find "\${GITHUB_WORKSPACE}/ios-deps/moltenvk" -name "libMoltenVK.a"

          # 4b. Prepara DXC macOS host per compilare gli shader HLSL -> .spirv.h durante la build
          mkdir -p "\${GITHUB_WORKSPACE}/ios-deps/dxc"
          DXC_FOUND="\$(find "\${GITHUB_WORKSPACE}/ShadowRecomp-Upstream/tools/XShaderRecomp" -type f -name "dxc*" -perm +111 2>/dev/null | grep -i mac | head -n 1 || true)"
          if [ -z "\${DXC_FOUND}" ]; then
            brew install directx-shader-compiler || true
            DXC_FOUND="\$(which dxc || true)"
          fi
          if [ -z "\${DXC_FOUND}" ]; then
            echo "::error::Impossibile trovare eseguibile macOS dxc per generare gli shader SPIR-V."
            exit 1
          fi
          echo "DIRECTX_DXC_TOOL=\${DXC_FOUND}" >> "\${GITHUB_ENV}"
          echo "==> DXC Host Tool: \${DXC_FOUND}"

          # 4c. Compila FreeType statico per iOS arm64 (richiesto da msdf-atlas-gen)
          IOS_SDK="\$(xcrun --sdk iphoneos --show-sdk-path)"
          mkdir -p "\${GITHUB_WORKSPACE}/ios-deps/freetype-src" "\${GITHUB_WORKSPACE}/ios-deps/freetype-install"
          curl -fSL "https://download.savannah.gnu.org/releases/freetype/freetype-\${FREETYPE_VERSION}.tar.gz" -o /tmp/freetype.tar.gz
          tar -xzf /tmp/freetype.tar.gz -C "\${GITHUB_WORKSPACE}/ios-deps/freetype-src" --strip-components=1
          cmake -S "\${GITHUB_WORKSPACE}/ios-deps/freetype-src" -B "\${GITHUB_WORKSPACE}/ios-deps/freetype-build" -G Ninja \\
            -DCMAKE_SYSTEM_NAME=iOS \\
            -DCMAKE_OSX_SYSROOT="\${IOS_SDK}" \\
            -DCMAKE_OSX_ARCHITECTURES=arm64 \\
            -DCMAKE_OSX_DEPLOYMENT_TARGET="\${IOS_DEPLOYMENT_TARGET}" \\
            -DCMAKE_BUILD_TYPE=Release \\
            -DBUILD_SHARED_LIBS=OFF \\
            -DFT_DISABLE_HARFBUZZ=ON \\
            -DFT_DISABLE_PNG=ON \\
            -DFT_DISABLE_BZIP2=ON \\
            -DFT_DISABLE_BROTLI=ON \\
            -DFT_DISABLE_ZLIB=OFF \\
            -DCMAKE_INSTALL_PREFIX="\${GITHUB_WORKSPACE}/ios-deps/freetype-install"
          cmake --build "\${GITHUB_WORKSPACE}/ios-deps/freetype-build" --parallel
          cmake --install "\${GITHUB_WORKSPACE}/ios-deps/freetype-build"

      - name: 5. Compila Tool Nativi Host macOS (XboxRecomp2 Rust + file_to_c)
        working-directory: ShadowRecomp-Upstream
        run: |
          mkdir -p "\${GITHUB_WORKSPACE}/build-host"

          # 5a. Compila XboxRecomp2 (Rust) per ricompilazione statica di default.xbe
          echo "==> Compilazione XboxRecomp2 (Rust) su macOS arm64..."
          cargo build --release --manifest-path tools/XboxRecomp2/Cargo.toml
          XBOXRECOMP2_BIN="\$(find tools/XboxRecomp2/target/release -maxdepth 1 -type f -perm +111 \\( -name 'xbox-recomp2*' -o -name 'XboxRecomp2*' \\) | head -n 1)"
          if [ -z "\${XBOXRECOMP2_BIN}" ]; then
            echo "::error::Binario XboxRecomp2 non trovato dopo cargo build!"
            exit 1
          fi
          cp "\${XBOXRECOMP2_BIN}" "\${GITHUB_WORKSPACE}/build-host/xbox-recomp2"
          chmod +x "\${GITHUB_WORKSPACE}/build-host/xbox-recomp2"
          echo "XBOXRECOMP2_HOST_BIN=\${GITHUB_WORKSPACE}/build-host/xbox-recomp2" >> "\${GITHUB_ENV}"

          # 5b. Compila file_to_c nativo macOS (usato da BIN2C durante cross-compilazione iOS)
          echo "==> Compilazione file_to_c host macOS..."
          ZSTD_PREFIX="\$(brew --prefix zstd)"
          clang++ -std=c++17 -O2 tools/file_to_c/file_to_c.cpp \\
            -I"\${ZSTD_PREFIX}/include" -L"\${ZSTD_PREFIX}/lib" -lzstd \\
            -o "\${GITHUB_WORKSPACE}/build-host/file_to_c"
          chmod +x "\${GITHUB_WORKSPACE}/build-host/file_to_c"
          echo "FILE_TO_C_HOST_BIN=\${GITHUB_WORKSPACE}/build-host/file_to_c" >> "\${GITHUB_ENV}"

      - name: 6. Applica Patch Porting iOS Reale (OS iOS, App File NFD, Mod Manager, MoltenVK)
        run: |
          chmod +x ios-port/scripts/apply_ios_port.sh
          ./ios-port/scripts/apply_ios_port.sh \\
            "\${GITHUB_WORKSPACE}/ShadowRecomp-Upstream" \\
            "\${GITHUB_WORKSPACE}/ios-port" \\
            "\${GITHUB_WORKSPACE}/ios-deps"

      - name: 7. Configura CMake Cross-Compile per iOS arm64 (iPhone 16 Pro)
        working-directory: ShadowRecomp-Upstream
        env:
          # Toolchain stub compatibile con il check VCPKG_ROOT del CMakeLists.txt di ShadowRecomp
          VCPKG_ROOT: \${{ github.workspace }}/ios-deps/vcpkg-ios-stub
        run: |
          CONFIG="\${{ inputs.build_configuration || '${config.buildConfiguration}' }}"
          IOS_SDK="\$(xcrun --sdk iphoneos --show-sdk-path)"
          MOLTENVK_LIB="\$(find "\${GITHUB_WORKSPACE}/ios-deps/moltenvk" -path "*ios-arm64*" -name "libMoltenVK.a" | head -n 1)"
          if [ -z "\${MOLTENVK_LIB}" ]; then
            MOLTENVK_LIB="\$(find "\${GITHUB_WORKSPACE}/ios-deps/moltenvk" -path "*iOS*" -name "libMoltenVK.a" | head -n 1)"
          fi
          echo "==> MoltenVK Static Library: \${MOLTENVK_LIB}"

          cmake -B build-ios -G Xcode \\
            -DCMAKE_SYSTEM_NAME=iOS \\
            -DCMAKE_OSX_SYSROOT="\${IOS_SDK}" \\
            -DCMAKE_OSX_ARCHITECTURES=arm64 \\
            -DCMAKE_OSX_DEPLOYMENT_TARGET="\${IOS_DEPLOYMENT_TARGET}" \\
            -DCMAKE_BUILD_TYPE="\${CONFIG}" \\
            -DCMAKE_PREFIX_PATH="\${GITHUB_WORKSPACE}/ios-deps/freetype-install" \\
            -DFREETYPE_INCLUDE_DIRS="\${GITHUB_WORKSPACE}/ios-deps/freetype-install/include/freetype2" \\
            -DFREETYPE_LIBRARY="\${GITHUB_WORKSPACE}/ios-deps/freetype-install/lib/libfreetype.a" \\
            -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE=NO \\
            -DCMAKE_XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER="\${BUNDLE_ID}" \\
            -DCMAKE_XCODE_ATTRIBUTE_MARKETING_VERSION="\${APP_VERSION}" \\
            -DCMAKE_C_FLAGS="${pieFlags}" \\
            -DCMAKE_CXX_FLAGS="${pieFlags}" \\
            -DSHADOW_IOS_PORT=ON \\
            -DPLUME_SDL3_VULKAN_ENABLED=ON \\
            -DSHADOW_RECOMP_XBOXRECOMP2_EXECUTABLE="\${XBOXRECOMP2_HOST_BIN}" \\
            -DSHADOW_HOST_FILE_TO_C="\${FILE_TO_C_HOST_BIN}" \\
            -DDIRECTX_DXC_TOOL="\${DIRECTX_DXC_TOOL}" \\
            -DMOLTENVK_STATIC_LIB="\${MOLTENVK_LIB}" \\
            -DSDL_STATIC=ON \\
            -DSDL_SHARED=OFF \\
            -DSDL_TESTS=OFF

      - name: 8. Compila ShadowRecomp.app (arm64 Unsigned)
        working-directory: ShadowRecomp-Upstream
        run: |
          CONFIG="\${{ inputs.build_configuration || '${config.buildConfiguration}' }}"
          cmake --build build-ios --config "\${CONFIG}" --target ShadowRecomp -- \\
            -sdk iphoneos \\
            -arch arm64 \\
            CODE_SIGN_IDENTITY="" \\
            CODE_SIGNING_REQUIRED=NO \\
            CODE_SIGNING_ALLOWED=NO \\
            AD_HOC_CODE_SIGNING_ALLOWED=YES

      - name: 9. Firma Ad-Hoc (ldid) & Impacchetta IPA Unsigned per Feather / LiveContainer
        run: |
          CONFIG="\${{ inputs.build_configuration || '${config.buildConfiguration}' }}"
          APP_BUNDLE="\$(find ShadowRecomp-Upstream/build-ios -type d -name "\${APP_NAME}.app" | head -n 1)"
          if [ -z "\${APP_BUNDLE}" ]; then
            echo "::error::Bundle \${APP_NAME}.app non trovato in build-ios!"
            find ShadowRecomp-Upstream/build-ios -maxdepth 4
            exit 1
          fi
          echo "==> Trovato bundle: \${APP_BUNDLE}"

          rm -rf Payload
          mkdir -p Payload
          cp -R "\${APP_BUNDLE}" "Payload/\${APP_NAME}.app"
          cp ios-port/ios/Info.plist "Payload/\${APP_NAME}.app/Info.plist"

          # Rimuove eventuali firme residui e applica firma ad-hoc con entitlement RAM aumentata
          rm -rf "Payload/\${APP_NAME}.app/_CodeSignature"
          ldid -Sios-port/ios/Entitlements.plist "Payload/\${APP_NAME}.app/\${APP_NAME}"
          chmod +x "Payload/\${APP_NAME}.app/\${APP_NAME}"

          IPA_NAME="\${APP_NAME}-iOS-v\${APP_VERSION}-Unsigned.ipa"
          zip -qry "\${IPA_NAME}" Payload
          ls -lh "\${IPA_NAME}"
          shasum -a 256 "\${IPA_NAME}" > "\${IPA_NAME}.sha256"

      - name: 10. Carica Artifact IPA Pronto per Feather / LiveContainer
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

  const applyScript = `#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_DIR="$1"
PORT_DIR="$2"
DEPS_DIR="$3"

echo "==> [1/7] Creazione stub VCPKG_ROOT per cross-compilazione iOS..."
mkdir -p "\${DEPS_DIR}/vcpkg-ios-stub/scripts/buildsystems"
cat << 'EOF_VCPKG' > "\${DEPS_DIR}/vcpkg-ios-stub/scripts/buildsystems/vcpkg.cmake"
# Stub vcpkg.cmake per cross-compilazione iOS arm64 su GitHub Actions
message(STATUS "ShadowRecomp iOS: uso toolchain iOS nativa invece di vcpkg desktop.")
EOF_VCPKG

echo "==> [2/7] Copia layer iOS (OS, App File NFD, Mod Manager, CURL stub, Info.plist)..."
mkdir -p "\${UPSTREAM_DIR}/ShadowRecomp/os/ios"
mkdir -p "\${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/curl"
cp "\${PORT_DIR}/ios/os/ios_platform.mm" "\${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_platform.mm"
cp "\${PORT_DIR}/ios/os/registry_ios.inl" "\${UPSTREAM_DIR}/ShadowRecomp/os/ios/registry_ios.inl"
cp "\${PORT_DIR}/ios/nfd_ios.mm" "\${UPSTREAM_DIR}/ShadowRecomp/os/ios/nfd_ios.mm"
cp "\${PORT_DIR}/ios/include/nfd.h" "\${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/nfd.h"
cp "\${PORT_DIR}/ios/ios_mod_manager.mm" "\${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_mod_manager.mm"
cp "\${PORT_DIR}/ios/curl_ios_stub.mm" "\${UPSTREAM_DIR}/ShadowRecomp/os/ios/curl_ios_stub.mm"
cp "\${PORT_DIR}/ios/include/curl/curl.h" "\${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/curl/curl.h"
mkdir -p "\${UPSTREAM_DIR}/ios"
cp "\${PORT_DIR}/ios/Info.plist" "\${UPSTREAM_DIR}/ios/Info.plist"
cp "\${PORT_DIR}/ios/Entitlements.plist" "\${UPSTREAM_DIR}/ios/Entitlements.plist"
cp "\${PORT_DIR}/cmake/ShadowRecompIOS.cmake" "\${UPSTREAM_DIR}/cmake/ShadowRecompIOS.cmake" 2>/dev/null || (mkdir -p "\${UPSTREAM_DIR}/cmake" && cp "\${PORT_DIR}/cmake/ShadowRecompIOS.cmake" "\${UPSTREAM_DIR}/cmake/ShadowRecompIOS.cmake")

echo "==> [3/7] Patch ShadowRecomp/user/paths.cpp (rimuove static_assert per __APPLE__ / iOS)..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/user/paths.cpp" << 'PY_PATHS'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text(encoding="utf-8")
if "#elif defined(__APPLE__)" not in src:
    apple_block = """#elif defined(__APPLE__)
    const char* homeDir = getenv("HOME");
    if (homeDir != nullptr)
    {
        userPath = std::filesystem::path(homeDir) / "Documents" / USER_DIRECTORY;
        std::error_code ec;
        std::filesystem::create_directories(userPath, ec);
    }
#else"""
    src = src.replace("#else", apple_block, 1)
    p.write_text(src, encoding="utf-8")
    print("Patched paths.cpp for iOS Documents/")
PY_PATHS

echo "==> [4/7] Patch ShadowRecomp/os/registry.h e ShadowRecomp/ui/game_window.cpp..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/os/registry.h" "\${UPSTREAM_DIR}/ShadowRecomp/ui/game_window.cpp" << 'PY_REG_WIN'
import sys, pathlib

reg_p = pathlib.Path(sys.argv[1])
reg_src = reg_p.read_text(encoding="utf-8")
if "registry_ios.inl" not in reg_src:
    reg_src = reg_src.replace(
        "/*#elif defined(__APPLE__)\n#include <os/macos/registry_macos.inl>*/",
        "#elif defined(__APPLE__)\n#include <os/ios/registry_ios.inl>"
    )
    if "registry_ios.inl" not in reg_src:
        reg_src = reg_src.replace("#endif", "#elif defined(__APPLE__)\n#include <os/ios/registry_ios.inl>\n#endif", 1)
    reg_p.write_text(reg_src, encoding="utf-8")
    print("Patched registry.h")

win_p = pathlib.Path(sys.argv[2])
win_src = win_p.read_text(encoding="utf-8")
if "defined(__APPLE__)" not in win_src:
    win_src = win_src.replace(
        "#elif defined(PLUME_SDL_VULKAN_ENABLED)",
        "#elif defined(PLUME_SDL_VULKAN_ENABLED) || defined(__APPLE__)"
    )
    win_p.write_text(win_src, encoding="utf-8")
    print("Patched game_window.cpp")
PY_REG_WIN

echo "==> [5/7] Patch Plume, thirdparty e XShaderRecomp per iOS arm64 (MoltenVK + no desktop DXC dylib)..."
python3 - "\${UPSTREAM_DIR}/thirdparty/CMakeLists.txt" "\${UPSTREAM_DIR}/thirdparty/plume/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/XShaderRecomp/thirdparty/CMakeLists.txt" << 'PY_TP'
import sys, pathlib

# 5a. thirdparty/CMakeLists.txt: abilita PLUME_SDL3_VULKAN_ENABLED su iOS (MoltenVK) e disabilita discord-rpc su iOS
tp_p = pathlib.Path(sys.argv[1])
tp_src = tp_p.read_text(encoding="utf-8")
if "CMAKE_SYSTEM_NAME STREQUAL \"iOS\"" not in tp_src:
    tp_src = tp_src.replace(
        'if (CMAKE_SYSTEM_NAME MATCHES "Linux")',
        'if (CMAKE_SYSTEM_NAME MATCHES "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")'
    )
    tp_p.write_text(tp_src, encoding="utf-8")
    print("Patched thirdparty/CMakeLists.txt")

# 5b. thirdparty/plume/CMakeLists.txt: consenti PLUME_SDL3_VULKAN_ENABLED anche su APPLE/iOS
plume_p = pathlib.Path(sys.argv[2])
if plume_p.exists():
    plume_src = plume_p.read_text(encoding="utf-8")
    plume_src = plume_src.replace(
        'cmake_dependent_option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF IS_LINUX OFF)',
        'option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF)'
    )
    # Rimuovi doppio PUBLIC typo se presente in plume upstream
    plume_src = plume_src.replace("PUBLIC PUBLIC SDL3::Headers", "PUBLIC SDL3::Headers")
    plume_p.write_text(plume_src, encoding="utf-8")
    print("Patched plume/CMakeLists.txt")

# 5c. XShaderRecomp: su iOS non compilare XShaderRecompTool (eseguibile host) e non linkare libdxcompiler.dylib macOS nel binario iOS
xsr_p = pathlib.Path(sys.argv[3])
if xsr_p.exists():
    xsr_src = xsr_p.read_text(encoding="utf-8")
    if "SHADOW_IOS_PORT" not in xsr_src:
        xsr_src = xsr_src.replace(
            "Microsoft::DirectXShaderCompiler",
            "$<$<NOT:$<BOOL:\${SHADOW_IOS_PORT}>>:Microsoft::DirectXShaderCompiler>"
        )
        xsr_src = xsr_src.replace(
            "add_executable(XShaderRecompTool",
            "if(NOT SHADOW_IOS_PORT)\nadd_executable(XShaderRecompTool"
        )
        xsr_src += "\nif(NOT SHADOW_IOS_PORT)\nendif()\n"
        # Fix nesting cleanly if target_precompile_headers(XShaderRecompTool ...) was wrapped
        xsr_src = xsr_src.replace(
            "target_precompile_headers(XShaderRecompTool REUSE_FROM XShaderRecompLib)\nif(NOT SHADOW_IOS_PORT)\nendif()",
            "target_precompile_headers(XShaderRecompTool REUSE_FROM XShaderRecompLib)\nendif()"
        )
        xsr_p.write_text(xsr_src, encoding="utf-8")
        print("Patched XShaderRecomp/CMakeLists.txt")

xsr_tp = pathlib.Path(sys.argv[4])
if xsr_tp.exists():
    xsr_tp_src = xsr_tp.read_text(encoding="utf-8")
    if "SHADOW_IOS_PORT" not in xsr_tp_src:
        xsr_tp_src = xsr_tp_src.replace(
            'if (NOT TARGET Microsoft::DirectXShaderCompiler)',
            'if (NOT SHADOW_IOS_PORT AND NOT TARGET Microsoft::DirectXShaderCompiler)'
        )
        xsr_tp.write_text(xsr_tp_src, encoding="utf-8")
        print("Patched XShaderRecomp/thirdparty/CMakeLists.txt")
PY_TP

echo "==> [6/7] Patch ShadowRecomp/CMakeLists.txt e ShadowRecompLib/CMakeLists.txt per iOS arm64..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/CMakeLists.txt" "\${UPSTREAM_DIR}/ShadowRecompLib/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/CMakeLists.txt" << 'PY_SR'
import sys, pathlib

sr_p = pathlib.Path(sys.argv[1])
sr_src = sr_p.read_text(encoding="utf-8")

# Usa SHADOW_HOST_FILE_TO_C in BIN2C durante cross-compile iOS
sr_src = sr_src.replace(
    "COMMAND $<TARGET_FILE:file_to_c>",
    "COMMAND $<IF:$<BOOL:\${SHADOW_HOST_FILE_TO_C}>,\${SHADOW_HOST_FILE_TO_C},$<TARGET_FILE:file_to_c>>"
)

# Su iOS, SDL3 gestisce UIApplicationMain tramite SDL_main: rimuovi SDL_MAIN_HANDLED su iOS
sr_src = sr_src.replace(
    "add_compile_definitions(\n    SDL_MAIN_HANDLED",
    "if(NOT SHADOW_IOS_PORT)\n    add_compile_definitions(SDL_MAIN_HANDLED)\nendif()\nadd_compile_definitions("
)

# Aggiungi sorgenti OS iOS
ios_os_block = """elseif (CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJC OBJCXX)
    set(SHADOW_RECOMP_OS_CXX_SOURCES
        "os/ios/ios_platform.mm"
        "os/ios/nfd_ios.mm"
        "os/ios/ios_mod_manager.mm"
        "os/ios/curl_ios_stub.mm"
    )
endif()"""
if "os/ios/ios_platform.mm" not in sr_src:
    sr_src = sr_src.replace(
        '        "os/linux/user_linux.cpp"\n    )\nendif()',
        '        "os/linux/user_linux.cpp"\n    )\n' + ios_os_block
    )

# Sostituisci find_package(CURL/nfd) con target iOS nativi quando SHADOW_IOS_PORT=ON
sr_src = sr_src.replace(
    "find_package(CURL REQUIRED)\nfind_package(nfd REQUIRED)",
    """if(NOT SHADOW_IOS_PORT)
    find_package(CURL REQUIRED)
    find_package(nfd REQUIRED)
else()
    include("\${CMAKE_SOURCE_DIR}/cmake/ShadowRecompIOS.cmake")
endif()"""
)

# Crea ShadowRecomp come MACOSX_BUNDLE su iOS
sr_src = sr_src.replace(
    "else()\n    add_executable(ShadowRecomp \${SHADOW_RECOMP_CXX_SOURCES})\nendif()",
    """elseif(SHADOW_IOS_PORT)
    add_executable(ShadowRecomp MACOSX_BUNDLE \${SHADOW_RECOMP_CXX_SOURCES})
else()
    add_executable(ShadowRecomp \${SHADOW_RECOMP_CXX_SOURCES})
endif()"""
)

# Aggiungi hook finale ShadowRecompIOS_ConfigureTarget
if "shadow_configure_ios_target" not in sr_src:
    sr_src += "\nif(SHADOW_IOS_PORT)\n    shadow_configure_ios_target(ShadowRecomp)\nendif()\n"

sr_p.write_text(sr_src, encoding="utf-8")
print("Patched ShadowRecomp/CMakeLists.txt")

# Patch ShadowRecompLib/CMakeLists.txt: AppleClang (Xcode) non accetta alcuni flag -mllvm interni di LLVM upstream
lib_p = pathlib.Path(sys.argv[2])
lib_src = lib_p.read_text(encoding="utf-8")
lib_src = lib_src.replace(
    'if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")',
    'if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")'
)
lib_p.write_text(lib_src, encoding="utf-8")
print("Patched ShadowRecompLib/CMakeLists.txt")

# Patch tools/CMakeLists.txt: salta la build iOS di file_to_c (usiamo il binario host macOS)
tools_p = pathlib.Path(sys.argv[3])
tools_src = tools_p.read_text(encoding="utf-8")
tools_src = tools_src.replace(
    "add_subdirectory(\${SHADOW_RECOMP_TOOLS_ROOT}/file_to_c)",
    "if(NOT SHADOW_IOS_PORT)\n    add_subdirectory(\${SHADOW_RECOMP_TOOLS_ROOT}/file_to_c)\nendif()"
)
tools_p.write_text(tools_src, encoding="utf-8")
print("Patched tools/CMakeLists.txt")
PY_SR

echo "==> [7/7] Patch iOS completata con successo!"`;

  const cmakeIos = `# cmake/ShadowRecompIOS.cmake
# Integrazione nativa iOS arm64 per FoxWorkshop/ShadowRecomp (iPhone 16 Pro / Feather / LiveContainer)

add_library(nfd::nfd INTERFACE IMPORTED)
target_include_directories(nfd::nfd INTERFACE "\${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include")

add_library(CURL::libcurl INTERFACE IMPORTED)
target_include_directories(CURL::libcurl INTERFACE "\${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include")

function(shadow_configure_ios_target TARGET_NAME)
    message(STATUS "Configuring \${TARGET_NAME} for iOS arm64 (iPhone 16 Pro / MoltenVK -> Metal 3)")

    set_target_properties(\${TARGET_NAME} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "\${CMAKE_SOURCE_DIR}/ios/Info.plist"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${config.bundleId}"
        XCODE_ATTRIBUTE_MARKETING_VERSION "${config.appVersion}"
        XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "1"
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
    )

    target_include_directories(\${TARGET_NAME} PRIVATE
        "\${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include"
    )

    target_compile_definitions(\${TARGET_NAME} PRIVATE
        SHADOW_IOS_PORT=1
        PLUME_SDL_VULKAN_ENABLED=1
        ${config.enable120HzProMotion ? 'SHADOW_IOS_PROMOTION_120HZ=1' : 'SHADOW_IOS_PROMOTION_120HZ=0'}
    )

    # Disabilita PCH sui file Objective-C++ (.mm)
    set_source_files_properties(
        "os/ios/ios_platform.mm"
        "os/ios/nfd_ios.mm"
        "os/ios/ios_mod_manager.mm"
        "os/ios/curl_ios_stub.mm"
        PROPERTIES SKIP_PRECOMPILE_HEADERS ON
    )

    # Link statico MoltenVK (Vulkan -> Apple Metal 3)
    if(MOLTENVK_STATIC_LIB AND EXISTS "\${MOLTENVK_STATIC_LIB}")
        target_link_libraries(\${TARGET_NAME} PRIVATE "\${MOLTENVK_STATIC_LIB}")
    else()
        message(WARNING "MOLTENVK_STATIC_LIB non trovato; verificare il download di MoltenVK-all.tar")
    endif()

    # Framework Apple iOS necessari per Metal 3, SDL3, App File, Controller e Audio
    target_link_libraries(\${TARGET_NAME} PRIVATE
        "-framework Foundation"
        "-framework UIKit"
        "-framework Metal"
        "-framework MetalKit"
        "-framework IOSurface"
        "-framework QuartzCore"
        "-framework CoreGraphics"
        "-framework CoreFoundation"
        "-framework GameController"
        "-framework CoreHaptics"
        "-framework CoreMotion"
        "-framework AVFoundation"
        "-framework AudioToolbox"
        "-framework UniformTypeIdentifiers"
        "-lc++"
    )
endfunction()`;

  const iosPlatformMm = `// ios/os/ios_platform.mm
// Implementazione nativa iOS dei namespace os::logger, os::process, os::media, os::user, os::version
// per FoxWorkshop/ShadowRecomp (modello DevZer0D4Y/MarathonRecompilediOS)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>
#include <unistd.h>
#include <mach-o/dyld.h>

#include <os/logger.h>
#include <os/media.h>
#include <os/process.h>
#include <os/user.h>
#include <os/version.h>

namespace {
std::mutex g_logMutex;
std::filesystem::path GetIOSDocumentsDir() {
    @autoreleasepool {
        NSArray<NSURL *> *urls = [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        if (urls.count > 0) {
            return std::filesystem::path(urls.firstObject.fileSystemRepresentation);
        }
        const char* home = getenv("HOME");
        return home ? (std::filesystem::path(home) / "Documents") : std::filesystem::path("/tmp");
    }
}
}

namespace os::logger {

void Init() {
    std::error_code ec;
    std::filesystem::create_directories(GetIOSDocumentsDir() / "ShadowRecomp" / "logs", ec);
}

void Log(const std::string_view str, ELogType type, const char* func) {
    std::lock_guard<std::mutex> lock(g_logMutex);
    const char* prefix = "[INFO]";
    if (type == ELogType::Warning) prefix = "[WARN]";
    else if (type == ELogType::Error) prefix = "[ERR ]";
    else if (type == ELogType::Utility) prefix = "[UTIL]";

    @autoreleasepool {
        NSLog(@"ShadowRecomp %s [%s] %.*s", prefix, func ? func : "*", (int)str.size(), str.data());
    }
}

void LogFile(const std::string_view str, std::filesystem::path fileName) {
    std::lock_guard<std::mutex> lock(g_logMutex);
    auto outPath = GetIOSDocumentsDir() / "ShadowRecomp" / "logs" / fileName.filename();
    std::error_code ec;
    std::filesystem::create_directories(outPath.parent_path(), ec);
    std::ofstream ofs(outPath, std::ios::app);
    if (ofs.is_open()) {
        ofs.write(str.data(), static_cast<std::streamsize>(str.size()));
        ofs << "\\n";
    }
}

} // namespace os::logger

namespace os::media {

bool IsExternalMediaPlaying() {
    @autoreleasepool {
        return [[AVAudioSession sharedInstance] isOtherAudioPlaying] == YES;
    }
}

bool IsSupported() {
    return true;
}

} // namespace os::media

namespace os::process {

std::filesystem::path GetExecutablePath() {
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::string buf(size, '\\0');
    if (_NSGetExecutablePath(buf.data(), &size) == 0) {
        return std::filesystem::path(buf.c_str());
    }
    @autoreleasepool {
        NSString* exec = [[NSBundle mainBundle] executablePath];
        return exec ? std::filesystem::path(exec.fileSystemRepresentation) : std::filesystem::path();
    }
}

std::filesystem::path GetExecutableRoot() {
    return GetExecutablePath().parent_path();
}

std::filesystem::path GetWorkingDirectory() {
    return GetIOSDocumentsDir() / "ShadowRecomp";
}

bool SetWorkingDirectory(const std::filesystem::path& path) {
    return chdir(path.c_str()) == 0;
}

bool StartProcess(const std::filesystem::path&, const std::vector<std::string>&, std::filesystem::path) {
    // Su iOS non è permesso eseguire fork/exec di processi esterni
    return false;
}

void CheckConsole() {}
void ShowConsole() {}

} // namespace os::process

namespace os::user {

bool IsDarkTheme() {
    @autoreleasepool {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
}

} // namespace os::user

namespace os::version {

OSVersion GetOSVersion() {
    @autoreleasepool {
        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        return OSVersion{
            static_cast<uint32_t>(v.majorVersion),
            static_cast<uint32_t>(v.minorVersion),
            static_cast<uint32_t>(v.patchVersion)
        };
    }
}

} // namespace os::version`;

  const registryIosInl = `// ios/os/registry_ios.inl
#pragma once
#include <os/registry.h>

inline bool os::registry::Init() {
    return false;
}

template<typename T>
bool os::registry::ReadValue(const std::string_view&, T&) {
    return false;
}

template<typename T>
bool os::registry::WriteValue(const std::string_view&, const T&) {
    return false;
}`;

  const nfdHeader = `// ios/include/nfd.h
// Drop-in header compatibile con nativefiledialog-extended per ShadowRecomp/ui/installer_wizard.cpp
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef char nfdchar_t;
typedef char nfdu8char_t;
typedef size_t nfdfiltersize_t;

typedef struct {
    const nfdu8char_t* name;
    const nfdu8char_t* spec;
} nfdu8filteritem_t;

typedef nfdu8filteritem_t nfdfilteritem_t;

typedef enum {
    NFD_ERROR,
    NFD_OKAY,
    NFD_CANCEL
} nfdresult_t;

nfdresult_t NFD_Init(void);
void NFD_Quit(void);
nfdresult_t NFD_OpenDialogU8(nfdu8char_t** outPath, const nfdu8filteritem_t* filterList, nfdfiltersize_t filterCount, const nfdu8char_t* defaultPath);
nfdresult_t NFD_PickFolderU8(nfdu8char_t** outPath, const nfdu8char_t* defaultPath);
void NFD_FreePathU8(nfdu8char_t* filePath);
const char* NFD_GetError(void);

#ifdef __cplusplus
}
#endif`;

  const nfdIosMm = `// ios/nfd_ios.mm
// Collega l'Installer Wizard originale di FoxWorkshop/ShadowRecomp (NFD_OpenDialogU8 / NFD_PickFolderU8)
// direttamente all'App File nativa di iOS (UIDocumentPickerViewController).
// Al primo avvio su iPhone 16 Pro, l'utente può selezionare la propria ISO Xbox o cartella estratta in 1 tap.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <nfd.h>
#include <cstdlib>
#include <cstring>
#include <string>

static std::string g_lastNfdError;

@interface ShadowDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, copy) NSString *selectedPath;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL pickFolder;
@end

@implementation ShadowDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        self.cancelled = YES;
        dispatch_semaphore_signal(self.semaphore);
        return;
    }

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *docs = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *importDir = [docs URLByAppendingPathComponent:@"ShadowRecomp/imports" isDirectory:YES];
    [fm createDirectoryAtURL:importDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *destURL = [importDir URLByAppendingPathComponent:url.lastPathComponent];
    [fm removeItemAtURL:destURL error:nil];

    NSError *copyErr = nil;
    // Copia (o linka se già nella sandbox App File) così ShadowRecomp C++ può leggerlo senza scadenza permessi
    if ([url.path hasPrefix:docs.path]) {
        self.selectedPath = url.path;
    } else if ([fm copyItemAtURL:url toURL:destURL error:&copyErr]) {
        self.selectedPath = destURL.path;
    } else {
        // Fallback: prova accesso diretto al path security-scoped
        self.selectedPath = url.path;
    }

    if (accessed) {
        [url stopAccessingSecurityScopedResource];
    }
    self.cancelled = NO;
    dispatch_semaphore_signal(self.semaphore);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.cancelled = YES;
    dispatch_semaphore_signal(self.semaphore);
}

@end

static UIViewController* GetTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (!keyWindow) keyWindow = ws.windows.firstObject;
        }
    }
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

static nfdresult_t PresentIOSFilesPicker(nfdu8char_t** outPath, BOOL folderMode) {
    if (!outPath) {
        g_lastNfdError = "outPath is null";
        return NFD_ERROR;
    }
    *outPath = nullptr;

    ShadowDocumentPickerDelegate *delegate = [[ShadowDocumentPickerDelegate alloc] init];
    delegate.semaphore = dispatch_semaphore_create(0);
    delegate.pickFolder = folderMode;
    delegate.cancelled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = GetTopViewController();
        if (!presenter) {
            g_lastNfdError = "No active UIViewController to present Files app";
            dispatch_semaphore_signal(delegate.semaphore);
            return;
        }

        NSArray<UTType *> *types = folderMode
            ? @[UTTypeFolder]
            : @[UTTypeItem, UTTypeData, UTTypeDiskImage, UTTypeArchive];

        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
        picker.delegate = delegate;
        picker.allowsMultipleSelection = NO;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [presenter presentViewController:picker animated:YES completion:nil];
    });

    dispatch_semaphore_wait(delegate.semaphore, DISPATCH_TIME_FOREVER);

    if (delegate.cancelled || delegate.selectedPath.length == 0) {
        return NFD_CANCEL;
    }

    const char* utf8 = delegate.selectedPath.UTF8String;
    *outPath = static_cast<nfdu8char_t*>(std::malloc(std::strlen(utf8) + 1));
    std::strcpy(*outPath, utf8);
    return NFD_OKAY;
}

extern "C" {

nfdresult_t NFD_Init(void) { return NFD_OKAY; }
void NFD_Quit(void) {}

nfdresult_t NFD_OpenDialogU8(nfdu8char_t** outPath, const nfdu8filteritem_t*, nfdfiltersize_t, const nfdu8char_t*) {
    return PresentIOSFilesPicker(outPath, NO);
}

nfdresult_t NFD_PickFolderU8(nfdu8char_t** outPath, const nfdu8char_t*) {
    return PresentIOSFilesPicker(outPath, YES);
}

void NFD_FreePathU8(nfdu8char_t* filePath) {
    std::free(filePath);
}

const char* NFD_GetError(void) {
    return g_lastNfdError.c_str();
}

}`;

  const iosModManagerMm = `// ios/ios_mod_manager.mm
// Menu Mod Manager nativo iOS ispirato a DevZer0D4Y/MarathonRecompilediOS (ui/ios_mod_manager.mm)
// Scrive nel formato REALE letto da FoxWorkshop/ShadowRecomp/mod/mod_loader.cpp:
//   <GamePath>/mods/.modloader/profiles/profiles.json
//   <GamePath>/mods/.modloader/profiles/Default.json  -> { "EnabledMods": [ ... ] }
// Permette di importare cartelle mod (con mod.ini) direttamente dall'App File di iOS.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>
#include <user/paths.h>

namespace ShadowIOS {

struct ModEntry {
    std::string folderName;
    std::string title;
    std::string author;
    bool enabled = false;
};

static std::filesystem::path GetModsRoot() {
    auto modsDir = GetGamePath() / "mods";
    std::error_code ec;
    std::filesystem::create_directories(modsDir / ".modloader" / "profiles", ec);
    return modsDir;
}

static std::vector<std::string> ReadEnabledMods() {
    std::vector<std::string> enabled;
    auto defaultProfile = GetModsRoot() / ".modloader" / "profiles" / "Default.json";
    if (!std::filesystem::exists(defaultProfile)) return enabled;
    try {
        std::ifstream ifs(defaultProfile);
        auto j = nlohmann::json::parse(ifs);
        if (j.contains("EnabledMods") && j["EnabledMods"].is_array()) {
            for (const auto& item : j["EnabledMods"]) {
                enabled.push_back(item.get<std::string>());
            }
        }
    } catch (...) {}
    return enabled;
}

static void SaveShadowRecompProfiles(const std::vector<ModEntry>& mods) {
    auto profilesDir = GetModsRoot() / ".modloader" / "profiles";
    std::error_code ec;
    std::filesystem::create_directories(profilesDir, ec);

    nlohmann::json profilesList = {
        {"ProfileIndex", 0},
        {"ProfilesList", {{{"Name", "Default"}, {"Filename", "Default.json"}}}}
    };
    {
        std::ofstream ofs(profilesDir / "profiles.json");
        ofs << profilesList.dump(2);
    }

    nlohmann::json enabledArr = nlohmann::json::array();
    for (const auto& m : mods) {
        if (m.enabled) enabledArr.push_back(m.folderName);
    }
    nlohmann::json defaultProfile = { {"EnabledMods", enabledArr} };
    {
        std::ofstream ofs(profilesDir / "Default.json");
        ofs << defaultProfile.dump(2);
    }
}

static std::vector<ModEntry> ScanInstalledMods() {
    std::vector<ModEntry> result;
    auto enabledList = ReadEnabledMods();
    auto modsRoot = GetModsRoot();
    if (!std::filesystem::exists(modsRoot)) return result;

    for (const auto& entry : std::filesystem::directory_iterator(modsRoot)) {
        if (!entry.is_directory()) continue;
        std::string folder = entry.path().filename().string();
        if (folder == ".modloader") continue;

        ModEntry m;
        m.folderName = folder;
        m.title = folder;
        m.author = "Community";
        m.enabled = std::find(enabledList.begin(), enabledList.end(), folder) != enabledList.end();

        auto iniPath = entry.path() / "mod.ini";
        if (std::filesystem::exists(iniPath)) {
            std::ifstream ifs(iniPath);
            std::string line;
            while (std::getline(ifs, line)) {
                auto eq = line.find('=');
                if (eq == std::string::npos) continue;
                std::string key = line.substr(0, eq);
                std::string val = line.substr(eq + 1);
                if (key.find("Title") != std::string::npos || key.find("Name") != std::string::npos) m.title = val;
                if (key.find("Author") != std::string::npos) m.author = val;
            }
        }
        result.push_back(m);
    }
    return result;
}

} // namespace ShadowIOS

@interface ShadowModManagerViewController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, assign) std::vector<ShadowIOS::ModEntry> *modsPtr;
@end

@implementation ShadowModManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ShadowRecomp Mod Manager";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.modsPtr = new std::vector<ShadowIOS::ModEntry>(ShadowIOS::ScanInstalledMods());

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(closeManager)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Importa Mod"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(importModFolder)];
}

- (void)dealloc {
    delete self.modsPtr;
}

- (void)closeManager {
    ShadowIOS::SaveShadowRecompProfiles(*self.modsPtr);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)importModFolder {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *src = urls.firstObject;
    if (!src) return;
    BOOL scoped = [src startAccessingSecurityScopedResource];
    NSString *destRoot = [NSString stringWithUTF8String:ShadowIOS::GetModsRoot().c_str()];
    NSURL *dst = [[NSURL fileURLWithPath:destRoot isDirectory:YES] URLByAppendingPathComponent:src.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:src toURL:dst error:nil];
    if (scoped) [src stopAccessingSecurityScopedResource];

    *self.modsPtr = ShadowIOS::ScanInstalledMods();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.modsPtr->size();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ModCell"];
    const auto& mod = (*self.modsPtr)[(size_t)indexPath.row];
    cell.textLabel.text = [NSString stringWithUTF8String:mod.title.c_str()];
    cell.detailTextLabel.text = [NSString stringWithUTF8String:mod.author.c_str()];
    cell.accessoryType = mod.enabled ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    auto& mod = (*self.modsPtr)[(size_t)indexPath.row];
    mod.enabled = !mod.enabled;
    ShadowIOS::SaveShadowRecompProfiles(*self.modsPtr);
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end

extern "C" void ShadowIOS_PresentModManager(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWin = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                keyWin = ((UIWindowScene *)s).windows.firstObject;
                if (keyWin) break;
            }
        }
        UIViewController *root = keyWin.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if (!root) return;
        ShadowModManagerViewController *vc = [[ShadowModManagerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [root presentViewController:nav animated:YES completion:nil];
    });
}`;

  const curlHeader = `// ios/include/curl/curl.h
// Stub leggero compatibile con ShadowRecomp/install/update_checker.cpp su iOS (evita dipendenza OpenSSL/libcurl)
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void CURL;
typedef int CURLcode;
typedef int CURLoption;

#define CURLE_OK 0
#define CURLE_UNSUPPORTED_PROTOCOL 1
#define CURLOPT_URL 10002
#define CURLOPT_USERAGENT 10018
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_FOLLOWLOCATION 52
#define CURLOPT_TIMEOUT 13

CURL* curl_easy_init(void);
CURLcode curl_easy_setopt(CURL* curl, CURLoption option, ...);
CURLcode curl_easy_perform(CURL* curl);
void curl_easy_cleanup(CURL* curl);
const char* curl_easy_strerror(CURLcode code);

#ifdef __cplusplus
}
#endif`;

  const curlStubMm = `// ios/curl_ios_stub.mm
#include <curl/curl.h>

extern "C" {
CURL* curl_easy_init(void) { return reinterpret_cast<CURL*>(1); }
CURLcode curl_easy_setopt(CURL*, CURLoption, ...) { return CURLE_OK; }
CURLcode curl_easy_perform(CURL*) { return CURLE_UNSUPPORTED_PROTOCOL; }
void curl_easy_cleanup(CURL*) {}
const char* curl_easy_strerror(CURLcode) { return "Update checker disabled on iOS sideload"; }
}`;

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

    <!-- Accesso completo dall'App File di iOS ("Su iPhone -> ${config.appName}") -->
    <key>UIFileSharingEnabled</key>
    <${config.enableFileSharingApp ? 'true' : 'false'}/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <${config.enableFileSharingApp ? 'true' : 'false'}/>
    <key>UISupportsDocumentBrowser</key>
    <false/>

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

  const readmeMd = `# ShadowRecomp iOS Port (GitHub Actions Unsigned IPA)

Porting iOS per **iPhone 16 Pro (arm64)** di [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp), ispirato all'architettura iOS di [DevZer0D4Y/MarathonRecompilediOS](https://github.com/DevZer0D4Y/MarathonRecompilediOS).
Tutta la compilazione avviene nel cloud su **GitHub Actions (\`macos-15\`)**, senza bisogno di un Mac.

## Perché serve SOLO \`default.xbe\` (4.8MB) nella build, e NON la ISO da 4GB?
Esattamente come **MarathonRecompilediOS (Sonic '06, ~34MB)**:
- **La ISO / asset di gioco (texture, livelli, audio, video)** NON vengono mai inseriti nell'IPA: li selezionerai comodamente dall'**App File di iOS** al primo avvio dell'app su iPhone (tramite \`ios/nfd_ios.mm\` collegato a \`UIDocumentPickerViewController\`).
- **Il solo file \`default.xbe\` (~4.8MB)** serve invece a **\`XboxRecomp2\`** durante la GitHub Action per tradurre staticamente il codice macchina x86 di Shadow the Hedgehog in C++ nativo \`arm64\`. Questo è il motivo per cui l'IPA pesa ~34MB e **non richiede JIT** su Feather o LiveContainer.

## Come compilare l'IPA da GitHub (Zero Mac)
1. Carica tutti i file di questo pacchetto nel tuo repository **privato** GitHub (es. \`hiperema95-ctrl/edgyios\`).
2. Carica il tuo file \`default.xbe\` (~4.8MB) estratto dal gioco originale nel percorso:
   \`private/default.xbe\`
   *(In alternativa puoi impostare il Secret GitHub \`DEFAULT_XBE_URL\` o incollare l'URL nel campo \`default_xbe_url\` quando avvii la Action).*
3. Vai su **Actions → Build ShadowRecomp iOS Unsigned IPA (No-Mac Cloud Builder) → Run workflow**.
4. Al termine della build, scarica l'artifact **\`${config.appName}-iOS-Unsigned-IPA\`** direttamente sul tuo iPhone 16 Pro.
5. Installalo con **Feather** (o **LiveContainer**), avvia **${config.appName}** e seleziona la tua ISO / file di gioco dall'App File di iOS!

## Mod Manager su iOS
Il modulo \`ios/ios_mod_manager.mm\` gestisce le mod esattamente nel formato nativo letto da \`FoxWorkshop/ShadowRecomp/mod/mod_loader.cpp\`:
- Cartella mod: \`Su iPhone → ${config.appName} → ShadowRecomp → mods/<NomeMod>/mod.ini\`
- Profili attivi: \`mods/.modloader/profiles/profiles.json\` e \`Default.json\` (\`EnabledMods\`).`;

  return [
    {
      path: '.github/workflows/build-ios-ipa.yml',
      title: 'GitHub Action Cloud Builder (.yml)',
      language: 'yaml',
      description: 'Clona branch master, compila XboxRecomp2 (Rust) + file_to_c + FreeType + MoltenVK, applica patch iOS e crea l’IPA unsigned.',
      content: workflowYml,
    },
    {
      path: 'scripts/apply_ios_port.sh',
      title: 'Script Patch CMake & C++ Upstream',
      language: 'bash',
      description: 'Patcha i file reali di FoxWorkshop/ShadowRecomp (paths.cpp, registry.h, game_window.cpp, plume, XShaderRecomp, CMakeLists.txt).',
      content: applyScript,
    },
    {
      path: 'cmake/ShadowRecompIOS.cmake',
      title: 'CMake iOS Target & MoltenVK Linking',
      language: 'cmake',
      description: 'Configura il bundle MACOSX_BUNDLE iOS arm64, linka libMoltenVK.a e i framework Metal/UIKit/GameController.',
      content: cmakeIos,
    },
    {
      path: 'ios/nfd_ios.mm',
      title: 'Bridge App File iOS (UIDocumentPicker)',
      language: 'objc',
      description: 'Sostituisce nativefiledialog-extended così l’Installer Wizard originale di ShadowRecomp apre l’App File di iOS per la ISO.',
      content: nfdIosMm,
    },
    {
      path: 'ios/include/nfd.h',
      title: 'Header NFD Compatibile (nfd.h)',
      language: 'cpp',
      description: 'Header drop-in compatibile con ShadowRecomp/ui/installer_wizard.cpp (NFD_OpenDialogU8 / NFD_PickFolderU8).',
      content: nfdHeader,
    },
    {
      path: 'ios/ios_mod_manager.mm',
      title: 'Mod Manager Nativo iOS (profiles.json)',
      language: 'objc',
      description: 'Menu UIKit stile MarathonRecompilediOS che scrive mods/.modloader/profiles/Default.json per ModLoader::Init().',
      content: iosModManagerMm,
    },
    {
      path: 'ios/os/ios_platform.mm',
      title: 'Implementazione OS iOS (os::logger/process/media)',
      language: 'objc',
      description: 'Implementa tutti i simboli di ShadowRecomp/os/*.h richiesti dal linker su iOS arm64.',
      content: iosPlatformMm,
    },
    {
      path: 'ios/os/registry_ios.inl',
      title: 'Header Registry iOS (registry_ios.inl)',
      language: 'cpp',
      description: 'Implementazione inline os::registry per Apple/iOS inclusa da ShadowRecomp/os/registry.h.',
      content: registryIosInl,
    },
    {
      path: 'ios/curl_ios_stub.mm',
      title: 'Stub libcurl iOS (update_checker)',
      language: 'objc',
      description: 'Evita dipendenze OpenSSL/libcurl desktop compilando update_checker.cpp nativamente su iOS.',
      content: curlStubMm,
    },
    {
      path: 'ios/include/curl/curl.h',
      title: 'Header curl.h per iOS',
      language: 'cpp',
      description: 'Dichiarazioni minime CURL usate da ShadowRecomp/install/update_checker.cpp.',
      content: curlHeader,
    },
    {
      path: 'ios/Info.plist',
      title: 'Info.plist (App File + 120Hz ProMotion)',
      language: 'xml',
      description: 'UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace, CADisableMinimumFrameDurationOnPhone.',
      content: infoPlist,
    },
    {
      path: 'ios/Entitlements.plist',
      title: 'Entitlements.plist (ldid Extended RAM)',
      language: 'xml',
      description: 'increased-memory-limit ed extended-virtual-addressing per Feather e LiveContainer su iPhone 16 Pro.',
      content: entitlementsPlist,
    },
    {
      path: 'README.md',
      title: 'Guida Tecnica Zero-Mac (Feather / LiveContainer)',
      language: 'markdown',
      description: 'Istruzioni esatte su default.xbe, GitHub Action e primo avvio con App File.',
      content: readmeMd,
    },
  ];
}
