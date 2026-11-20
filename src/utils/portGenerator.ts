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
  const picFlags =
    config.targetInstaller === 'livecontainer' || config.targetInstaller === 'both'
      ? '-fPIC'
      : '';
  const pieLinkerFlags =
    config.targetInstaller === 'livecontainer' || config.targetInstaller === 'both'
      ? '-Wl,-pie'
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
        description: 'URL temporaneo opzionale al tuo default.xbe (4.8MB) se non hai impostato il Secret DEFAULT_XBE_URL'
        required: false
        default: ''
        type: string
      publish_release:
        description: 'Pubblica anche ShadowRecomp-iOS.ipa come GitHub Release (stile MarathonRecompilediOS)'
        required: false
        default: false
        type: boolean
  push:
    branches: [ main, master ]

env:
  APP_NAME: "${config.appName}"
  BUNDLE_ID: "${config.bundleId}"
  APP_VERSION: "${config.appVersion}"
  IOS_DEPLOYMENT_TARGET: "${config.deploymentTarget}"
  UPSTREAM_REPO: "${config.upstreamRepoUrl}"
  MOLTENVK_VERSION: "v1.4.2"
  FREETYPE_VERSION: "2.13.3"

jobs:
  build-shadowrecomp-ios-ipa:
    name: Build Unsigned IPA on GitHub macOS-15 (iPhone 16 Pro / arm64)
    runs-on: macos-15
    timeout-minutes: 90
    permissions:
      contents: write
    steps:
      - name: 1. Checkout Repository Porting iOS
        uses: actions/checkout@v4
        with:
          path: ios-port

      - name: 2. Clone FoxWorkshop/ShadowRecomp (branch master + submodules reali)
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
          # Usa 'git submodule status' così inizializza SOLO i submodule realmente presenti nell'indice Git
          # (evita errori pathspec su voci obsolete di .gitmodules come thirdparty/ogg e salta thirdparty/vcpkg)
          git submodule sync
          REAL_SUBMODULES="\$(git submodule status | awk '{print \$2}' | grep -v '^thirdparty/vcpkg\$' || true)"
          for sub in \${REAL_SUBMODULES}; do
            echo "==> Init submodule: \${sub}"
            git submodule update --init --recursive --depth 1 "\${sub}" || git submodule update --init --recursive "\${sub}"
          done

      - name: 3. Recupera default.xbe in Modo Effimero (Mai Salvato su Git)
        env:
          SECRET_XBE_URL: \${{ secrets.DEFAULT_XBE_URL }}
          INPUT_XBE_URL: \${{ inputs.default_xbe_url }}
        run: |
          TARGET_XBE="\${GITHUB_WORKSPACE}/ShadowRecomp-Upstream/ShadowRecompLib/private/default.xbe"
          mkdir -p "\$(dirname "\${TARGET_XBE}")"

          if [ -n "\${SECRET_XBE_URL}" ]; then
            echo "==> Download effimero default.xbe da GitHub Secret DEFAULT_XBE_URL (non salvato nel repo)..."
            curl -fSL "\${SECRET_XBE_URL}" -o "\${TARGET_XBE}"
          elif [ -n "\${INPUT_XBE_URL}" ]; then
            echo "==> Download effimero default.xbe da input workflow..."
            curl -fSL "\${INPUT_XBE_URL}" -o "\${TARGET_XBE}"
          elif [ -f "ios-port/private/default.xbe" ]; then
            echo "==> Trovato default.xbe locale in repo privato"
            cp "ios-port/private/default.xbe" "\${TARGET_XBE}"
          else
            echo "::error::Imposta il GitHub Secret DEFAULT_XBE_URL per compilare senza mai caricare default.xbe nel repo!"
            echo "================================================================================"
            echo "COME FUNZIONA IN SICUREZZA SU REPO PUBBLICO (stile MarathonRecompilediOS):"
            echo "1. NON committare MAI default.xbe nel repository Git (.gitignore lo blocca)."
            echo "2. Vai su GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret."
            echo "3. Crea il Secret 'DEFAULT_XBE_URL' con un link diretto privato al tuo default.xbe (~4.8MB)."
            echo "4. Rilancia la Action: GitHub scarica default.xbe SOLO nella VM temporanea di build,"
            echo "   genera l'IPA (~35MB) e distrugge subito la VM. Nessun file SEGA finisce nel repo!"
            echo "================================================================================"
            exit 1
          fi
          ls -lh "\${TARGET_XBE}"

      - name: 4. Configura Xcode, MoltenVK (iOS arm64), DXC Host Wrapper & FreeType
        run: |
          if [ -d "/Applications/Xcode_16.2.app/Contents/Developer" ]; then
            sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer
          fi
          xcodebuild -version
          brew install cmake ninja ldid pkg-config zstd

          # 4a. Scarica MoltenVK ufficiale iOS arm64 (traduce Vulkan/SPIR-V di Plume in Apple Metal 3)
          mkdir -p "\${GITHUB_WORKSPACE}/ios-deps/moltenvk"
          curl -fSL "https://github.com/KhronosGroup/MoltenVK/releases/download/\${MOLTENVK_VERSION}/MoltenVK-ios.tar" -o /tmp/MoltenVK-ios.tar
          tar -xf /tmp/MoltenVK-ios.tar -C "\${GITHUB_WORKSPACE}/ios-deps/moltenvk"
          find "\${GITHUB_WORKSPACE}/ios-deps/moltenvk" -name "libMoltenVK.a"

          # 4b. Prepara wrapper DXC macOS arm64 dal submodule dxc-bin (imposta DYLD_LIBRARY_PATH)
          mkdir -p "\${GITHUB_WORKSPACE}/build-host"
          DXC_DIR="\${GITHUB_WORKSPACE}/ShadowRecomp-Upstream/tools/XShaderRecomp/thirdparty/dxc-bin"
          if [ ! -f "\${DXC_DIR}/bin/arm64/dxc-macos" ]; then
            echo "::error::dxc-macos non trovato in \${DXC_DIR}/bin/arm64/dxc-macos"
            ls -la "\${DXC_DIR}" || true
            exit 1
          fi
          chmod +x "\${DXC_DIR}/bin/arm64/dxc-macos"
          cat << EOF_DXC > "\${GITHUB_WORKSPACE}/build-host/dxc-wrapper.sh"
          #!/usr/bin/env bash
          export DYLD_LIBRARY_PATH="\${DXC_DIR}/lib/arm64:\\\${DYLD_LIBRARY_PATH:-}"
          exec "\${DXC_DIR}/bin/arm64/dxc-macos" "\\$@"
          EOF_DXC
          chmod +x "\${GITHUB_WORKSPACE}/build-host/dxc-wrapper.sh"
          grep -Fq '"$@"' "\${GITHUB_WORKSPACE}/build-host/dxc-wrapper.sh"
          "\${GITHUB_WORKSPACE}/build-host/dxc-wrapper.sh" --version
          echo "DIRECTX_DXC_TOOL=\${GITHUB_WORKSPACE}/build-host/dxc-wrapper.sh" >> "\${GITHUB_ENV}"

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

          # 5a. Compila XboxRecomp2 (Rust) esattamente come ShadowRecompLib/cmake/recompile/select/build_from_source.cmake
          echo "==> Compilazione XboxRecomp2 (Rust) su macOS arm64..."
          cargo build --release --locked \\
            --manifest-path tools/XboxRecomp2/Cargo.toml \\
            --target-dir "\${GITHUB_WORKSPACE}/build-host/xr2-target" \\
            -p xbox-recomp2-cli
          XBOXRECOMP2_BIN="\${GITHUB_WORKSPACE}/build-host/xr2-target/release/xboxrecomp2"
          if [ ! -x "\${XBOXRECOMP2_BIN}" ]; then
            echo "::error::Binario xboxrecomp2 non trovato in \${XBOXRECOMP2_BIN}"
            ls -la "\${GITHUB_WORKSPACE}/build-host/xr2-target/release" || true
            exit 1
          fi
          cp "\${XBOXRECOMP2_BIN}" "\${GITHUB_WORKSPACE}/build-host/xboxrecomp2"
          chmod +x "\${GITHUB_WORKSPACE}/build-host/xboxrecomp2"
          echo "XBOXRECOMP2_HOST_BIN=\${GITHUB_WORKSPACE}/build-host/xboxrecomp2" >> "\${GITHUB_ENV}"

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

          cmake -B build-ios -G Ninja \\
            -DCMAKE_SYSTEM_NAME=iOS \\
            -DCMAKE_OSX_SYSROOT="\${IOS_SDK}" \\
            -DCMAKE_OSX_ARCHITECTURES=arm64 \\
            -DCMAKE_OSX_DEPLOYMENT_TARGET="\${IOS_DEPLOYMENT_TARGET}" \\
            -DCMAKE_BUILD_TYPE="\${CONFIG}" \\
            -DCMAKE_PREFIX_PATH="\${GITHUB_WORKSPACE}/ios-deps/freetype-install" \\
            -DFREETYPE_INCLUDE_DIRS="\${GITHUB_WORKSPACE}/ios-deps/freetype-install/include/freetype2" \\
            -DFREETYPE_LIBRARY="\${GITHUB_WORKSPACE}/ios-deps/freetype-install/lib/libfreetype.a" \\
            -DCMAKE_C_FLAGS="${picFlags}" \\
            -DCMAKE_CXX_FLAGS="${picFlags}" \\
            -DCMAKE_EXE_LINKER_FLAGS="${pieLinkerFlags}" \\
            -DSHADOW_IOS_PORT=ON \\
            -DPLUME_SDL3_VULKAN_ENABLED=ON \\
            -DSHADOW_RECOMP_XBOXRECOMP2_EXECUTABLE="\${XBOXRECOMP2_HOST_BIN}" \\
            -DSHADOW_HOST_FILE_TO_C="\${FILE_TO_C_HOST_BIN}" \\
            -DDIRECTX_DXC_TOOL="\${DIRECTX_DXC_TOOL}" \\
            -DMOLTENVK_STATIC_LIB="\${MOLTENVK_LIB}" \\
            -DSDL_STATIC=ON \\
            -DSDL_SHARED=OFF \\
            -DSDL_TESTS=OFF

          # Patch x86_context.h generato da XboxRecomp2 per AppleClang 16 (LLVM 17 non ha __builtin_elementwise_sqrt / __builtin_issignaling)
          python3 - "build-ios/ShadowRecompLib/x86/x86_context.h" << 'PY_X86_CTX'
          import sys, pathlib
          p = pathlib.Path(sys.argv[1])
          if p.exists():
              src = p.read_text(encoding="utf-8")
              if "SHADOW_IOS_CLANG_BUILTINS_H" not in src:
                  polyfill = '''#ifndef SHADOW_IOS_CLANG_BUILTINS_H
          #define SHADOW_IOS_CLANG_BUILTINS_H
          #if defined(__APPLE__) && defined(__cplusplus)
          #include <bit>
          #include <cmath>
          #include <cstdint>
          #if !__has_builtin(__builtin_elementwise_sqrt)
          static inline float shadow_ios_builtin_sqrt(float x) { return std::sqrt(x); }
          static inline double shadow_ios_builtin_sqrt(double x) { return std::sqrt(x); }
          static inline long double shadow_ios_builtin_sqrt(long double x) { return std::sqrt(x); }
          #define __builtin_elementwise_sqrt(x) shadow_ios_builtin_sqrt(x)
          #endif
          #if !__has_builtin(__builtin_issignaling)
          static inline bool shadow_ios_builtin_issignaling(float x) {
              uint32_t bits = std::bit_cast<uint32_t>(x);
              return ((bits & 0x7F800000u) == 0x7F800000u) && ((bits & 0x00400000u) == 0u) && ((bits & 0x003FFFFFu) != 0u);
          }
          static inline bool shadow_ios_builtin_issignaling(double x) {
              uint64_t bits = std::bit_cast<uint64_t>(x);
              return ((bits & 0x7FF0000000000000ull) == 0x7FF0000000000000ull) && ((bits & 0x0008000000000000ull) == 0ull) && ((bits & 0x0007FFFFFFFFFFFFull) != 0ull);
          }
          static inline bool shadow_ios_builtin_issignaling(long double x) {
              return shadow_ios_builtin_issignaling(static_cast<double>(x));
          }
          #define __builtin_issignaling(x) shadow_ios_builtin_issignaling(x)
          #endif
          #endif
          #endif
          '''
                  p.write_text(polyfill + src, encoding="utf-8")
                  print("Patched build-ios/ShadowRecompLib/x86/x86_context.h for AppleClang 16 builtins")
          PY_X86_CTX

      - name: 8. Compila ShadowRecomp.app (arm64 Unsigned via Ninja)
        working-directory: ShadowRecomp-Upstream
        run: |
          cmake --build build-ios --target ShadowRecomp --parallel "\$(sysctl -n hw.ncpu)" -- -k 10

      - name: 9. Firma Ad-Hoc (ldid) & Impacchetta IPA Unsigned per Feather / LiveContainer
        run: |
          APP_BUNDLE="\$(find ShadowRecomp-Upstream/build-ios -type d -name "\${APP_NAME}.app" | head -n 1)"
          if [ -z "\${APP_BUNDLE}" ]; then
            echo "::error::Bundle \${APP_NAME}.app non trovato in build-ios!"
            find ShadowRecomp-Upstream/build-ios -maxdepth 4
            exit 1
          fi
          echo "==> Trovato bundle: \${APP_BUNDLE}"

          rm -rf Payload
          mkdir -p "Payload/\${APP_NAME}.app"
          if [ -f "\${APP_BUNDLE}/\${APP_NAME}" ]; then
            cp -R "\${APP_BUNDLE}/." "Payload/\${APP_NAME}.app/"
          elif [ -f "\${APP_BUNDLE}/Contents/MacOS/\${APP_NAME}" ]; then
            cp "\${APP_BUNDLE}/Contents/MacOS/\${APP_NAME}" "Payload/\${APP_NAME}.app/\${APP_NAME}"
            if [ -d "\${APP_BUNDLE}/Contents/Resources" ]; then
              cp -R "\${APP_BUNDLE}/Contents/Resources/." "Payload/\${APP_NAME}.app/"
            fi
          else
            echo "::error::Binario \${APP_NAME} non trovato dentro \${APP_BUNDLE}!"
            find "\${APP_BUNDLE}" -maxdepth 4
            exit 1
          fi

          cp ios-port/ios/Info.plist "Payload/\${APP_NAME}.app/Info.plist"
          file "Payload/\${APP_NAME}.app/\${APP_NAME}"

          # Rimuove eventuali firme residue e applica firma ad-hoc con entitlement RAM aumentata
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
          retention-days: 7

      - name: 11. Pubblica GitHub Release Opzionale (stile MarathonRecompilediOS)
        if: \${{ inputs.publish_release == true }}
        env:
          GH_TOKEN: \${{ github.token }}
        run: |
          TAG="ios-v\${APP_VERSION}-\${GITHUB_RUN_NUMBER}"
          cp "\${APP_NAME}-iOS-v\${APP_VERSION}-Unsigned.ipa" "\${APP_NAME}-iOS.ipa"
          shasum -a 256 "\${APP_NAME}-iOS.ipa" > "SHA256SUMS-\${APP_NAME}.txt"
          gh release create "\${TAG}" \\
            "\${APP_NAME}-iOS.ipa" \\
            "SHA256SUMS-\${APP_NAME}.txt" \\
            --title "Shadow the Hedgehog (2005) — iOS Unsigned IPA (build \${APP_VERSION}.\${GITHUB_RUN_NUMBER})" \\
            --notes "Unsigned IPA per Feather / LiveContainer (iPhone 16 Pro arm64). Nessun asset di gioco incluso: importa i file estratti dalla tua copia Xbox al primo avvio dall'App File di iOS."
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
cat << 'EOF_NFD_HPP' > "\${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/nfd.hpp"
#pragma once
#include <nfd.h>
#include <memory>

namespace NFD {
struct Guard {
    Guard() { NFD_Init(); }
    ~Guard() { NFD_Quit(); }
};
struct PathDeleter {
    void operator()(nfdu8char_t* ptr) const { if (ptr) NFD_FreePathU8(ptr); }
};
using UniquePathU8 = std::unique_ptr<nfdu8char_t, PathDeleter>;
using UniquePath = UniquePathU8;

inline nfdresult_t OpenDialog(UniquePathU8& outPath, const nfdu8filteritem_t* filterList = nullptr, nfdfiltersize_t filterCount = 0, const nfdu8char_t* defaultPath = nullptr) {
    nfdu8char_t* raw = nullptr;
    auto res = NFD_OpenDialogU8(&raw, filterList, filterCount, defaultPath);
    if (res == NFD_OKAY) outPath.reset(raw);
    return res;
}
inline nfdresult_t PickFolder(UniquePathU8& outPath, const nfdu8char_t* defaultPath = nullptr) {
    nfdu8char_t* raw = nullptr;
    auto res = NFD_PickFolderU8(&raw, defaultPath);
    if (res == NFD_OKAY) outPath.reset(raw);
    return res;
}
inline const char* GetError() { return NFD_GetError(); }
} // namespace NFD
EOF_NFD_HPP
mkdir -p "\${UPSTREAM_DIR}/ios" "\${UPSTREAM_DIR}/cmake"
cp "\${PORT_DIR}/ios/Info.plist" "\${UPSTREAM_DIR}/ios/Info.plist"
cp "\${PORT_DIR}/ios/Entitlements.plist" "\${UPSTREAM_DIR}/ios/Entitlements.plist"
cp "\${PORT_DIR}/cmake/ShadowRecompIOS.cmake" "\${UPSTREAM_DIR}/cmake/ShadowRecompIOS.cmake"

echo "==> [3/7] Patch ShadowRecomp/user/paths.cpp, paths.h, stdafx.h, guest_thread.cpp, update_checker.cpp e main.cpp per iOS arm64..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/user/paths.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/user/paths.h" "\${UPSTREAM_DIR}/ShadowRecomp/stdafx.h" "\${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/install/update_checker.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/main.cpp" << 'PY_PATHS'
import sys, pathlib

# 3a. user/paths.cpp: aggiungi supporto __APPLE__ (Documents/ShadowRecomp) + static init sicura (evita SIOF con MainGameFolder)
p = pathlib.Path(sys.argv[1])
src = p.read_text(encoding="utf-8")
if "#elif defined(__APPLE__)" not in src:
    apple_block = '''#elif defined(__APPLE__)
    const char* homeDir = getenv("HOME");
    if (homeDir != nullptr)
    {
        userPath = std::filesystem::path(homeDir) / "Documents" / USER_DIRECTORY;
        std::error_code ec;
        std::filesystem::create_directories(userPath, ec);
    }
#else'''
    src = src.replace("#else", apple_block, 1)
    print("Patched user/paths.cpp for iOS Documents/")

if "static std::filesystem::path s_userPath = BuildUserPath();" not in src:
    src = src.replace(
        "return g_userPath;",
        "static std::filesystem::path s_userPath = BuildUserPath();\\n    return s_userPath;"
    )
    print("Patched user/paths.cpp GetUserPath() to prevent C++ SIOF")
p.write_text(src, encoding="utf-8")

# 3b. user/paths.h: su iOS GetGamePath() punta alla sandbox scrivibile Documents/ShadowRecomp (visibile nell'App File)
ph = pathlib.Path(sys.argv[2])
ph_src = ph.read_text(encoding="utf-8")
if "SHADOW_IOS_PORT" not in ph_src:
    old_gp = '''inline std::filesystem::path GetGamePath()
{
    return GAME_INSTALL_DIRECTORY;
}'''
    new_gp = '''const std::filesystem::path& GetUserPath();

inline std::filesystem::path GetGamePath()
{
#if defined(SHADOW_IOS_PORT)
    return GetUserPath();
#else
    return GAME_INSTALL_DIRECTORY;
#endif
}'''
    if old_gp in ph_src:
        ph_src = ph_src.replace(old_gp, new_gp, 1)
        ph.write_text(ph_src, encoding="utf-8")
        print("Patched user/paths.h GetGamePath() for writable iOS Documents/")

# 3c. stdafx.h: abilita i typedef/macro Win32 compat anche su __APPLE__ + polyfill std::atomic_ref<T> per Apple libc++ (Xcode 16.2)
sa = pathlib.Path(sys.argv[3])
sa_src = sa.read_text(encoding="utf-8")
sa_changed = False
if "#elif defined(__linux__) || defined(__APPLE__)" not in sa_src:
    sa_src = sa_src.replace(
        "#elif defined(__linux__)",
        "#elif defined(__linux__) || defined(__APPLE__)\\n#include <strings.h>",
        1
    )
    sa_changed = True
    print("Patched stdafx.h for __APPLE__ POSIX/Win32 compat types")

if "SHADOW_IOS_ATOMIC_REF_POLYFILL" not in sa_src:
    atomic_ref_polyfill = '''
#if defined(__APPLE__) && defined(__cplusplus) && !defined(__cpp_lib_atomic_ref) && !defined(SHADOW_IOS_ATOMIC_REF_POLYFILL)
#define SHADOW_IOS_ATOMIC_REF_POLYFILL 1
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <type_traits>

namespace std {
namespace shadow_ios_atomic_detail {
struct WaitBucket {
    std::mutex mtx;
    std::condition_variable cv;
};

inline WaitBucket& get_wait_bucket(const volatile void* addr) noexcept {
    static WaitBucket buckets[64];
    uintptr_t h = reinterpret_cast<uintptr_t>(addr);
    h ^= (h >> 16);
    h *= 0x45d9f3bu;
    h ^= (h >> 16);
    return buckets[h & 63u];
}

constexpr int to_builtin_order(memory_order order) noexcept {
    switch (order) {
        case memory_order_relaxed: return __ATOMIC_RELAXED;
        case memory_order_consume: return __ATOMIC_CONSUME;
        case memory_order_acquire: return __ATOMIC_ACQUIRE;
        case memory_order_release: return __ATOMIC_RELEASE;
        case memory_order_acq_rel: return __ATOMIC_ACQ_REL;
        case memory_order_seq_cst:
        default:                   return __ATOMIC_SEQ_CST;
    }
}

constexpr int to_failure_order(memory_order success) noexcept {
    switch (success) {
        case memory_order_acq_rel: return __ATOMIC_ACQUIRE;
        case memory_order_release: return __ATOMIC_RELAXED;
        default:                   return to_builtin_order(success);
    }
}
} // namespace shadow_ios_atomic_detail

template <class T>
class atomic_ref {
    static_assert(std::is_trivially_copyable_v<T>, "std::atomic_ref requires a trivially copyable type");
    T* ptr_;

public:
    using value_type = T;
    static constexpr size_t required_alignment = alignof(T);
    static constexpr bool is_always_lock_free = __atomic_always_lock_free(sizeof(T), nullptr);

    explicit atomic_ref(T& obj) noexcept : ptr_(&obj) {}
    atomic_ref(const atomic_ref&) noexcept = default;
    atomic_ref& operator=(const atomic_ref&) = delete;

    bool is_lock_free() const noexcept {
        return __atomic_is_lock_free(sizeof(T), ptr_);
    }

    void store(T desired, memory_order order = memory_order_seq_cst) const noexcept {
        __atomic_store(ptr_, &desired, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    T operator=(T desired) const noexcept {
        store(desired);
        return desired;
    }

    T load(memory_order order = memory_order_seq_cst) const noexcept {
        T result;
        __atomic_load(ptr_, &result, shadow_ios_atomic_detail::to_builtin_order(order));
        return result;
    }

    operator T() const noexcept {
        return load();
    }

    T exchange(T desired, memory_order order = memory_order_seq_cst) const noexcept {
        T result;
        __atomic_exchange(ptr_, &desired, &result, shadow_ios_atomic_detail::to_builtin_order(order));
        return result;
    }

    bool compare_exchange_weak(T& expected, T desired, memory_order success, memory_order failure) const noexcept {
        return __atomic_compare_exchange(
            ptr_, &expected, &desired, true,
            shadow_ios_atomic_detail::to_builtin_order(success),
            shadow_ios_atomic_detail::to_builtin_order(failure));
    }

    bool compare_exchange_weak(T& expected, T desired, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_compare_exchange(
            ptr_, &expected, &desired, true,
            shadow_ios_atomic_detail::to_builtin_order(order),
            shadow_ios_atomic_detail::to_failure_order(order));
    }

    bool compare_exchange_strong(T& expected, T desired, memory_order success, memory_order failure) const noexcept {
        return __atomic_compare_exchange(
            ptr_, &expected, &desired, false,
            shadow_ios_atomic_detail::to_builtin_order(success),
            shadow_ios_atomic_detail::to_builtin_order(failure));
    }

    bool compare_exchange_strong(T& expected, T desired, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_compare_exchange(
            ptr_, &expected, &desired, false,
            shadow_ios_atomic_detail::to_builtin_order(order),
            shadow_ios_atomic_detail::to_failure_order(order));
    }

    template <class U = T, std::enable_if_t<std::is_integral_v<U> && !std::is_same_v<U, bool>, int> = 0>
    T fetch_add(T arg, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_fetch_add(ptr_, arg, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    template <class U = T, std::enable_if_t<std::is_integral_v<U> && !std::is_same_v<U, bool>, int> = 0>
    T fetch_sub(T arg, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_fetch_sub(ptr_, arg, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    template <class U = T, std::enable_if_t<std::is_integral_v<U> && !std::is_same_v<U, bool>, int> = 0>
    T fetch_and(T arg, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_fetch_and(ptr_, arg, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    template <class U = T, std::enable_if_t<std::is_integral_v<U> && !std::is_same_v<U, bool>, int> = 0>
    T fetch_or(T arg, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_fetch_or(ptr_, arg, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    template <class U = T, std::enable_if_t<std::is_integral_v<U> && !std::is_same_v<U, bool>, int> = 0>
    T fetch_xor(T arg, memory_order order = memory_order_seq_cst) const noexcept {
        return __atomic_fetch_xor(ptr_, arg, shadow_ios_atomic_detail::to_builtin_order(order));
    }

    void wait(T old, memory_order order = memory_order_seq_cst) const noexcept {
        T cur = load(order);
        if (std::memcmp(&cur, &old, sizeof(T)) != 0)
            return;
        auto& bucket = shadow_ios_atomic_detail::get_wait_bucket(ptr_);
        std::unique_lock<std::mutex> lock(bucket.mtx);
        while (true) {
            cur = load(order);
            if (std::memcmp(&cur, &old, sizeof(T)) != 0)
                break;
            bucket.cv.wait_for(lock, std::chrono::milliseconds(5));
        }
    }

    void notify_one() const noexcept {
        auto& bucket = shadow_ios_atomic_detail::get_wait_bucket(ptr_);
        {
            std::lock_guard<std::mutex> lock(bucket.mtx);
        }
        bucket.cv.notify_all();
    }

    void notify_all() const noexcept {
        auto& bucket = shadow_ios_atomic_detail::get_wait_bucket(ptr_);
        {
            std::lock_guard<std::mutex> lock(bucket.mtx);
        }
        bucket.cv.notify_all();
    }
};

template <class T>
atomic_ref(T&) -> atomic_ref<T>;
} // namespace std
#endif
'''
    sa_src = sa_src + atomic_ref_polyfill
    sa_changed = True
    print("Patched stdafx.h with C++20 std::atomic_ref<T> polyfill for Apple libc++")

if sa_changed:
    sa.write_text(sa_src, encoding="utf-8")

# 3d. cpu/guest_thread.cpp: proteggi #include <x86intrin.h> (non esiste su iOS arm64)
gt = pathlib.Path(sys.argv[4])
gt_src = gt.read_text(encoding="utf-8")
if "#include <x86intrin.h>" in gt_src and "defined(__x86_64__)" not in gt_src:
    gt_src = gt_src.replace(
        "#include <x86intrin.h>",
        "#if defined(__x86_64__) || defined(__i386__)\\n#include <x86intrin.h>\\n#endif",
        1
    )
    gt.write_text(gt_src, encoding="utf-8")
    print("Patched cpu/guest_thread.cpp to guard x86intrin.h on arm64")

# 3e. install/update_checker.cpp: sostituisci std::system() vietato su iOS SDK con SDL_OpenURL()
uc = pathlib.Path(sys.argv[5])
uc_src = uc.read_text(encoding="utf-8")
if "SHADOW_IOS_PORT" not in uc_src:
    old_uc = '''#elif defined(__APPLE__)
    std::string command = "open " + std::string(VISIT_URL) + " &";
    std::system(command.c_str());'''
    new_uc = '''#elif defined(__APPLE__)
#if defined(SHADOW_IOS_PORT)
    SDL_OpenURL(VISIT_URL);
#else
    std::string command = "open " + std::string(VISIT_URL) + " &";
    std::system(command.c_str());
#endif'''
    if old_uc in uc_src:
        uc_src = uc_src.replace(old_uc, new_uc, 1)
        uc.write_text(uc_src, encoding="utf-8")
        print("Patched install/update_checker.cpp to use SDL_OpenURL on iOS")

# 3f. main.cpp: includi <SDL3/SDL_main.h> per entry-point UIApplicationMain e usa GetWorkingDirectory() scrivibile su iOS
mp = pathlib.Path(sys.argv[6])
mp_src = mp.read_text(encoding="utf-8")
if "SDL3/SDL_main.h" not in mp_src:
    mp_src = mp_src.replace(
        '#include "stdafx.h"',
        '#include "stdafx.h"\\n#if defined(SHADOW_IOS_PORT)\\n#include <SDL3/SDL_main.h>\\n#endif',
        1
    )
    print("Patched main.cpp with SDL3/SDL_main.h for iOS UIKit bootstrap")
old_cwd = "std::filesystem::current_path(os::process::GetExecutableRoot(), ec);"
new_cwd = '''#if defined(SHADOW_IOS_PORT)
        auto iosWorkDir = os::process::GetWorkingDirectory();
        std::filesystem::create_directories(iosWorkDir, ec);
        std::filesystem::current_path(iosWorkDir, ec);
#else
        std::filesystem::current_path(os::process::GetExecutableRoot(), ec);
#endif'''
if old_cwd in mp_src and "iosWorkDir" not in mp_src:
    mp_src = mp_src.replace(old_cwd, new_cwd, 1)
    print("Patched main.cpp working directory to writable iOS Documents/ShadowRecomp")
old_upd = """    if (Config::CheckForUpdates && difftime(timeNow, Config::LastChecked) > TimeBetweenUpdateChecksInSeconds)
    {
        UpdateChecker::initialize();
        UpdateChecker::start();
        Config::LastChecked = timeNow;
        Config::Save();
    }"""
new_upd = """#if !defined(SHADOW_IOS_PORT)
    if (Config::CheckForUpdates && difftime(timeNow, Config::LastChecked) > TimeBetweenUpdateChecksInSeconds)
    {
        UpdateChecker::initialize();
        UpdateChecker::start();
        Config::LastChecked = timeNow;
        Config::Save();
    }
#endif"""
if old_upd in mp_src and "#if !defined(SHADOW_IOS_PORT)" not in mp_src:
    mp_src = mp_src.replace(old_upd, new_upd, 1)
    print("Patched main.cpp to skip background UpdateChecker on iOS")
mp.write_text(mp_src, encoding="utf-8")
PY_PATHS

echo "==> [4/7] Patch ShadowRecomp/os/registry.h e ShadowRecomp/ui/game_window.cpp..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/os/registry.h" "\${UPSTREAM_DIR}/ShadowRecomp/ui/game_window.cpp" << 'PY_REG_WIN'
import sys, pathlib

reg_p = pathlib.Path(sys.argv[1])
reg_src = reg_p.read_text(encoding="utf-8")
if "registry_ios.inl" not in reg_src:
    old_apple = '''/*#elif defined(__APPLE__)
#include <os/macos/registry_macos.inl>*/'''
    new_apple = '''#elif defined(__APPLE__)
#include <os/ios/registry_ios.inl>'''
    if old_apple in reg_src:
        reg_src = reg_src.replace(old_apple, new_apple, 1)
    else:
        reg_src = reg_src.replace("#endif", new_apple + "\\n#endif", 1)
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

echo "==> [5/7] Patch Plume, discord-rpc, thirdparty e XShaderRecomp per iOS arm64 (MoltenVK + no Cocoa/system())..."
python3 - "\${UPSTREAM_DIR}/thirdparty/CMakeLists.txt" "\${UPSTREAM_DIR}/thirdparty/plume/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/XShaderRecomp/thirdparty/CMakeLists.txt" "\${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/lib/dxc_compiler.cpp" "\${UPSTREAM_DIR}/thirdparty/discord-rpc/src/discord_register_linux.cpp" "\${UPSTREAM_DIR}/thirdparty/plume" << 'PY_TP'
import sys, pathlib, re

# 5a. thirdparty/CMakeLists.txt: abilita PLUME_SDL3_VULKAN_ENABLED su iOS (MoltenVK)
tp_p = pathlib.Path(sys.argv[1])
tp_src = tp_p.read_text(encoding="utf-8")
if 'CMAKE_SYSTEM_NAME STREQUAL "iOS"' not in tp_src:
    tp_src = tp_src.replace(
        'if (CMAKE_SYSTEM_NAME MATCHES "Linux")',
        'if (CMAKE_SYSTEM_NAME MATCHES "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")'
    )
    tp_p.write_text(tp_src, encoding="utf-8")
    print("Patched thirdparty/CMakeLists.txt")

# 5b. thirdparty/plume: consenti PLUME_SDL3_VULKAN_ENABLED su iOS e rimuovi dipendenze macOS-only (Cocoa / plume_metal.mm AppKit)
plume_p = pathlib.Path(sys.argv[2])
if plume_p.exists():
    plume_src = plume_p.read_text(encoding="utf-8")
    plume_src = plume_src.replace(
        'cmake_dependent_option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF IS_LINUX OFF)',
        'option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF)'
    )
    plume_src = plume_src.replace("PUBLIC PUBLIC SDL3::Headers", "PUBLIC SDL3::Headers")
    plume_src = re.sub(r'"-framework\\s+Cocoa"', '""', plume_src)
    plume_src = re.sub(r'"-framework\\s+AppKit"', '""', plume_src)
    plume_src = re.sub(r'find_library\\([^)]*\\b(?:Cocoa|AppKit)\\b[^)]*\\)', '', plume_src)
    plume_src = plume_src.replace("-framework Cocoa", "")
    plume_src = plume_src.replace("-framework AppKit", "")
    plume_p.write_text(plume_src, encoding="utf-8")
    print("Patched plume/CMakeLists.txt")

plume_dir = pathlib.Path(sys.argv[7])
if plume_dir.exists():
    plume_apple_ios_stub = '''#else
#include "plume_apple.h"

namespace plume {
    RenderDeviceVendor getRenderDeviceVendor(uint64_t) {
        return RenderDeviceVendor::APPLE;
    }

    CocoaWindow::CocoaWindow(void* window)
        : windowHandle(window), cachedAttributes{0, 0, 0, 0}, cachedRefreshRate(60) {}

    CocoaWindow::~CocoaWindow() = default;

    void CocoaWindow::updateWindowAttributesInternal(bool) {}

    void CocoaWindow::updateRefreshRateInternal(bool) {}

    void CocoaWindow::getWindowAttributes(CocoaWindowAttributes* attributes) const {
        if (attributes != nullptr) {
            std::lock_guard<std::mutex> lock(attributesMutex);
            *attributes = cachedAttributes;
        }
    }

    int CocoaWindow::getRefreshRate() const {
        return cachedRefreshRate.load();
    }

    void CocoaWindow::toggleFullscreen() {}
}
#endif
'''
    for src_file in sorted(set(list(plume_dir.rglob("*.mm")) + list(plume_dir.rglob("plume_metal.cpp")))):
        mm_src = src_file.read_text(encoding="utf-8")
        if "SHADOW_IOS_PLUME_GUARDED" in mm_src:
            continue
        is_macos_backend = src_file.name in ("plume_metal.cpp", "plume_apple.mm")
        has_macos_ui = any(k in mm_src for k in ("Cocoa/Cocoa.h", "AppKit/AppKit.h", "CocoaWindow", "NSWindow", "NSView"))
        if is_macos_backend or has_macos_ui:
            footer = "\\n" + plume_apple_ios_stub if src_file.name == "plume_apple.mm" else "\\n#endif\\n"
            guarded = "/* SHADOW_IOS_PLUME_GUARDED */\\n#include <TargetConditionals.h>\\n#if !TARGET_OS_IPHONE\\n" + mm_src + footer
            src_file.write_text(guarded, encoding="utf-8")
            print(f"Guarded macOS-only Plume file for iOS: {src_file.name}")

    plume_metal_cpp = plume_dir / "plume_metal.cpp"
    if plume_metal_cpp.exists() and "SHADOW_IOS_PLUME_GUARDED" not in plume_metal_cpp.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to guard thirdparty/plume/plume_metal.cpp for iOS!")
    plume_apple_mm = plume_dir / "plume_apple.mm"
    if plume_apple_mm.exists() and "CocoaWindow::~CocoaWindow()" not in plume_apple_mm.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to inject iOS CocoaWindow stub into thirdparty/plume/plume_apple.mm!")

    # Isola tutti i puntatori globali PFN_vk* di Volk nel namespace C++ plume_volk su iOS
    # cosi i simboli mangled non collidono MAI con i 414 simboli C _vk* esportati da libMoltenVK.a,
    # e collega volkInitialize() direttamente a _vkGetInstanceProcAddr di libMoltenVK.a
    volk_h = plume_dir / "contrib" / "volk" / "volk.h"
    if volk_h.exists():
        vh_src = volk_h.read_text(encoding="utf-8")
        if "SHADOW_IOS_VOLK_NAMESPACE" not in vh_src:
            if "TargetConditionals.h" not in vh_src:
                vh_src = "#if defined(__APPLE__)\\n#include <TargetConditionals.h>\\n#endif\\n" + vh_src
            marker_h = "/* VOLK_GENERATE_PROTOTYPES_H */"
            parts_h = vh_src.split(marker_h)
            if len(parts_h) != 3:
                raise RuntimeError(f"Expected 2 {marker_h} markers in volk.h, got {len(parts_h) - 1}")
            open_ns_h = (
                '/* SHADOW_IOS_VOLK_NAMESPACE */\\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\\n'
                '} /* close extern "C" */\\n'
                'namespace plume_volk {\\n'
                '#endif\\n'
                + marker_h
            )
            close_ns_h = (
                marker_h + '\\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\\n'
                '} /* close namespace plume_volk */\\n'
                'using namespace plume_volk;\\n'
                'extern "C" {\\n'
                '#endif'
            )
            vh_src = parts_h[0] + open_ns_h + parts_h[1] + close_ns_h + parts_h[2]
            volk_h.write_text(vh_src, encoding="utf-8")
            print("Patched volk.h: isolated PFN_vk* prototypes into namespace plume_volk for iOS")

    volk_c = plume_dir / "contrib" / "volk" / "volk.c"
    if volk_c.exists():
        v_src = volk_c.read_text(encoding="utf-8")
        if "TargetConditionals.h" not in v_src:
            v_src = "#if defined(__APPLE__)\\n#include <TargetConditionals.h>\\n#include <dlfcn.h>\\n#endif\\n" + v_src
        if "SHADOW_IOS_STATIC_MOLTENVK" not in v_src and "volkInitialize(" in v_src:
            v_src = re.sub(
                r'(VkResult\\s+volkInitialize\\s*\\(\\s*void\\s*\\)\\s*\\{)',
                r'''#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL shadow_ios_moltenvk_vkGetInstanceProcAddr(VkInstance instance, const char* pName) __asm__("_vkGetInstanceProcAddr");
#endif

\\1
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    /* SHADOW_IOS_STATIC_MOLTENVK: link diretto a _vkGetInstanceProcAddr in libMoltenVK.a */
    volkInitializeCustom(&shadow_ios_moltenvk_vkGetInstanceProcAddr);
    return VK_SUCCESS;
#endif''',
                v_src,
                count=1
            )
        if "SHADOW_IOS_VOLK_NAMESPACE" not in v_src:
            marker_c = "/* VOLK_GENERATE_PROTOTYPES_C */"
            parts_c = v_src.split(marker_c)
            if len(parts_c) != 3:
                raise RuntimeError(f"Expected 2 {marker_c} markers in volk.c, got {len(parts_c) - 1}")
            open_ns_c = (
                '/* SHADOW_IOS_VOLK_NAMESPACE */\\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\\n'
                '} /* close extern "C" so Volk globals never collide with libMoltenVK.a */\\n'
                'namespace plume_volk {\\n'
                '#endif\\n'
                + marker_c
            )
            close_ns_c = (
                marker_c + '\\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\\n'
                '} /* close namespace plume_volk */\\n'
                'extern "C" {\\n'
                '#endif'
            )
            v_src = parts_c[0] + open_ns_c + parts_c[1] + close_ns_c + parts_c[2]
        volk_c.write_text(v_src, encoding="utf-8")
        print("Patched volk.c: static MoltenVK binding + namespace plume_volk isolation for iOS")

    if volk_h.exists() and "SHADOW_IOS_VOLK_NAMESPACE" not in volk_h.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to namespace thirdparty/plume/contrib/volk/volk.h for iOS!")
    if volk_c.exists() and "SHADOW_IOS_VOLK_NAMESPACE" not in volk_c.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to namespace thirdparty/plume/contrib/volk/volk.c for iOS!")

# 5e. discord-rpc/src/discord_register_linux.cpp: rimuovi system() (vietato su iOS SDK)
discord_reg = pathlib.Path(sys.argv[6])
if discord_reg.exists():
    discord_stub = '''#include "discord_register.h"

extern "C" void Discord_Register(const char*, const char*)
{
}

extern "C" void Discord_RegisterSteamGame(const char*, const char*)
{
}
'''
    discord_reg.write_text(discord_stub, encoding="utf-8")
    print("Patched discord_register_linux.cpp (iOS no-op stub without system())")

# 5c. XShaderRecomp/CMakeLists.txt: su iOS non compilare XShaderRecompTool e proteggi OGNI target_*(XShaderRecompTool ...)

def guard_cmake_calls(text, func_regex, condition):
    out = []
    pos = 0
    for m in re.finditer(func_regex, text):
        start = m.start()
        if start < pos:
            continue
        i = text.find('(', start)
        if i == -1:
            continue
        depth = 0
        while i < len(text):
            ch = text[i]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
        out.append(text[pos:start])
        out.append(f"if({condition})\\n{text[start:i]}\\nendif()")
        pos = i
    out.append(text[pos:])
    return "".join(out)

xsr_p = pathlib.Path(sys.argv[3])
if xsr_p.exists():
    xsr_src = xsr_p.read_text(encoding="utf-8")
    if "SHADOW_IOS_PORT" not in xsr_src:
        xsr_src = xsr_src.replace(
            "Microsoft::DirectXShaderCompiler",
            "$<$<NOT:$<BOOL:\${SHADOW_IOS_PORT}>>:Microsoft::DirectXShaderCompiler>"
        )
        xsr_src = guard_cmake_calls(
            xsr_src,
            r'add_executable\\s*\\(\\s*XShaderRecompTool\\b',
            "NOT SHADOW_IOS_PORT"
        )
        xsr_src = guard_cmake_calls(
            xsr_src,
            r'(?:target_\\w+|set_target_properties)\\s*\\(\\s*XShaderRecompTool\\b',
            "TARGET XShaderRecompTool"
        )
        xsr_src += '''
if(SHADOW_IOS_PORT)
    target_compile_definitions(XShaderRecompLib PRIVATE SHADOW_IOS_PORT=1)
    target_include_directories(XShaderRecompLib PRIVATE
        "\${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/dxc-bin/inc"
        "\${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/dxc-bin/inc/dxc"
    )
endif()
'''
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

# 5d. dxc_compiler.cpp: su iOS gli shader sono precompilati al build time (fornisce stub DxcCreateInstance se referenziato)
dxc_cpp = pathlib.Path(sys.argv[5])
if dxc_cpp.exists():
    dxc_src = dxc_cpp.read_text(encoding="utf-8")
    if "SHADOW_IOS_PORT" not in dxc_src and "DxcCreateInstance" in dxc_src and "dlopen" not in dxc_src:
        ios_dxc_stub = '''
#if defined(SHADOW_IOS_PORT)
extern "C" HRESULT DxcCreateInstance(REFCLSID, REFIID, LPVOID* ppv)
{
    if (ppv) *ppv = nullptr;
    return E_NOTIMPL;
}
#endif
'''
        dxc_cpp.write_text(dxc_src + ios_dxc_stub, encoding="utf-8")
        print("Patched dxc_compiler.cpp with iOS DxcCreateInstance stub")
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
old_sdl_main = '''add_compile_definitions(
    SDL_MAIN_HANDLED'''
new_sdl_main = '''if(NOT SHADOW_IOS_PORT)
    add_compile_definitions(SDL_MAIN_HANDLED)
endif()
add_compile_definitions('''
sr_src = sr_src.replace(old_sdl_main, new_sdl_main)

# Aggiungi sorgenti OS iOS
old_linux_os = '''        "os/linux/user_linux.cpp"
    )
endif()'''
new_ios_os = '''        "os/linux/user_linux.cpp"
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJC OBJCXX)
    set(SHADOW_RECOMP_OS_CXX_SOURCES
        "os/ios/ios_platform.mm"
        "os/ios/nfd_ios.mm"
        "os/ios/ios_mod_manager.mm"
        "os/ios/curl_ios_stub.mm"
    )
endif()'''
if "os/ios/ios_platform.mm" not in sr_src:
    sr_src = sr_src.replace(old_linux_os, new_ios_os)

# Sostituisci find_package(CURL/nfd) con target iOS nativi quando SHADOW_IOS_PORT=ON
old_find_pkgs = '''find_package(CURL REQUIRED)
find_package(nfd REQUIRED)'''
new_find_pkgs = '''if(NOT SHADOW_IOS_PORT)
    find_package(CURL REQUIRED)
    find_package(nfd REQUIRED)
else()
    include("\${CMAKE_SOURCE_DIR}/cmake/ShadowRecompIOS.cmake")
endif()'''
sr_src = sr_src.replace(old_find_pkgs, new_find_pkgs)

# Crea ShadowRecomp come MACOSX_BUNDLE su iOS
old_add_exec = '''else()
    add_executable(ShadowRecomp \${SHADOW_RECOMP_CXX_SOURCES})
endif()'''
new_add_exec = '''elseif(SHADOW_IOS_PORT)
    add_executable(ShadowRecomp MACOSX_BUNDLE \${SHADOW_RECOMP_CXX_SOURCES})
else()
    add_executable(ShadowRecomp \${SHADOW_RECOMP_CXX_SOURCES})
endif()'''
sr_src = sr_src.replace(old_add_exec, new_add_exec)

# Aggiungi hook finale ShadowRecompIOS_ConfigureTarget
if "shadow_configure_ios_target" not in sr_src:
    sr_src += '''
if(SHADOW_IOS_PORT)
    shadow_configure_ios_target(ShadowRecomp)
endif()
'''

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
    '''if(NOT SHADOW_IOS_PORT)
    add_subdirectory(\${SHADOW_RECOMP_TOOLS_ROOT}/file_to_c)
endif()'''
)
tools_p.write_text(tools_src, encoding="utf-8")
print("Patched tools/CMakeLists.txt")
PY_SR

echo "==> [7/8] Patch runtime iOS arm64 (ARM64 CAS deadlock, stack 8MB, autoreleasepool, precompile idempotente, audio ring buffer, o1heap Jetsam)..."
python3 - "\${UPSTREAM_DIR}/ShadowRecomp/kernel/imports.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.h" "\${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/gpu/video.cpp" "\${UPSTREAM_DIR}/ShadowRecomp/audio/driver/sdl3_driver.cpp" "\${UPSTREAM_DIR}/thirdparty/o1heap/o1heap.h" "\${UPSTREAM_DIR}/thirdparty/o1heap/o1heap.c" "\${UPSTREAM_DIR}/ShadowRecomp/kernel/heap.cpp" << 'PY_IOS_RUNTIME'
import sys, pathlib

# 7a. kernel/imports.cpp: FIX ARM64 compare_exchange_weak spurious-failure deadlock in Event::Wait e RtlEnterCriticalSection + IsCurrentThread()
imp_p = pathlib.Path(sys.argv[1])
imp_src = imp_p.read_text(encoding="utf-8")
if "SHADOW_IOS_ARM64_CAS_FIX" not in imp_src:
    old_ev = """\t\t\t\twhile (true)
\t\t\t\t{
\t\t\t\t\tbool expected = true;
\t\t\t\t\tif (signaled.compare_exchange_weak(expected, false))
\t\t\t\t\t\tbreak;

\t\t\t\t\tsignaled.wait(expected);
\t\t\t\t}"""
    new_ev = """\t\t\t\t/* SHADOW_IOS_ARM64_CAS_FIX */
\t\t\t\twhile (true)
\t\t\t\t{
\t\t\t\t\tbool expected = true;
\t\t\t\t\tif (signaled.compare_exchange_strong(expected, false))
\t\t\t\t\t\tbreak;
\t\t\t\t\tif (expected)
\t\t\t\t\t\tcontinue;

\t\t\t\t\tsignaled.wait(expected);
\t\t\t\t}"""
    if old_ev not in imp_src:
        raise RuntimeError("Failed to locate Event::Wait compare_exchange_weak in kernel/imports.cpp!")
    imp_src = imp_src.replace(old_ev, new_ev, 1)

    old_cs = """\twhile (true)
\t{
\t\tuint32_t previousOwner = 0;

\t\tif (owningThread.compare_exchange_weak(previousOwner, thisThread) || previousOwner == thisThread)
\t\t{
\t\t\tCritSec->RecursionCount++;
\t\t\treturn;
\t\t}

\t\towningThread.wait(previousOwner);
\t}"""
    new_cs = """\twhile (true)
\t{
\t\tuint32_t previousOwner = 0;

\t\tif (owningThread.compare_exchange_strong(previousOwner, thisThread) || previousOwner == thisThread)
\t\t{
\t\t\tCritSec->RecursionCount++;
\t\t\treturn;
\t\t}

\t\tif (previousOwner == 0)
\t\t\tcontinue;

\t\towningThread.wait(previousOwner);
\t}"""
    if old_cs not in imp_src:
        raise RuntimeError("Failed to locate RtlEnterCriticalSection compare_exchange_weak in kernel/imports.cpp!")
    imp_src = imp_src.replace(old_cs, new_cs, 1)

    old_susp = "ThreadHandle->thread.get_id() == std::this_thread::get_id()"
    if old_susp in imp_src:
        imp_src = imp_src.replace(old_susp, "ThreadHandle->IsCurrentThread()", 1)

    imp_p.write_text(imp_src, encoding="utf-8")
    print("Patched kernel/imports.cpp: fixed ARM64 CAS deadlocks + IsCurrentThread()")

# 7b. cpu/guest_thread.h & guest_thread.cpp: 8 MB pthread stack su iOS (evita stack overflow 512 KB su GameLoop/CRI Sofdec FMV)
gth_p = pathlib.Path(sys.argv[2])
gth_src = gth_p.read_text(encoding="utf-8")
if "SHADOW_IOS_PTHREAD_STACK" not in gth_src:
    gth_src = gth_src.replace(
        "#include <condition_variable>",
        "#include <condition_variable>\\n#if defined(SHADOW_IOS_PORT)\\n#include <pthread.h>\\n#endif",
        1
    )
    old_member = "    std::thread thread;"
    new_member = """    /* SHADOW_IOS_PTHREAD_STACK */
#if defined(SHADOW_IOS_PORT)
    pthread_t thread{};
    std::atomic<bool> threadValid{false};
    std::atomic<uint32_t> hostThreadId{0};
    bool IsCurrentThread() const { return threadValid.load(std::memory_order_acquire) && pthread_equal(thread, pthread_self()) != 0; }
#else
    std::thread thread;
    bool IsCurrentThread() const { return thread.get_id() == std::this_thread::get_id(); }
#endif"""
    if old_member not in gth_src:
        raise RuntimeError("Failed to locate std::thread thread in cpu/guest_thread.h!")
    gth_src = gth_src.replace(old_member, new_member, 1)
    gth_p.write_text(gth_src, encoding="utf-8")
    print("Patched cpu/guest_thread.h for 8 MB iOS pthread stack")

gtc_p = pathlib.Path(sys.argv[3])
gtc_src = gtc_p.read_text(encoding="utf-8")
if "SHADOW_IOS_PTHREAD_STACK" not in gtc_src:
    old_gt_block = r"""static void GuestThreadFunc(GuestThreadHandle* hThread)
{
\t//printf("GuestThreadFunc(GuestThreadHandle* hThread): Function %08X\\n", hThread->params.function);
\thThread->suspended.wait(true);
\tGuestThread::Start(hThread->params);
}


GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
\t: params(params), suspended((params.flags & 0x1) != 0), thread(GuestThreadFunc, this)
{

}

static uint32_t GetThreadId(const std::thread::id& id)
{
\treturn *reinterpret_cast<const uint32_t*>(&id);
}

GuestThreadHandle::~GuestThreadHandle()
{
\tauto id = GetThreadId(this->thread.get_id());
\tstd::string s = GetThreadName(params.function);
\tLOGFN("Destroy thread {:08X} with ID {} ({})", params.function, id, s);

\tif (suspended.load())
\t{
\t\tLOGFN_WARNING("GuestThread: Destroying suspended thread {:08X} ({}), forcing resume", params.function, s);
\t\tsuspended.store(false, std::memory_order_release);
\t\tsuspended.notify_all();
\t}

\t{
\t\tstd::lock_guard lock(suspendMutex);
\t\tresumeRequested = true;
\t}
\tsuspendCV.notify_all();

\tif (thread.joinable())
\t\tthread.join();
}

uint32_t GuestThreadHandle::Wait(uint32_t timeout)
{
\tLOGFN("Wait: Thread {:08X}", params.function);
\tassert(timeout == INFINITE);

\tif (thread.joinable())
\t\tthread.join();

\treturn STATUS_WAIT_0;
}



GuestThreadHandle* GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId)
{
\t//printf("GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId), function: %08X\\n", params.function);
\tauto hThread = CreateKernelObject<GuestThreadHandle>(params);

\tif (threadId != nullptr)
\t{
\t\t*threadId = GetThreadId(hThread->thread.get_id());"""
    new_gt_block = r"""/* SHADOW_IOS_PTHREAD_STACK */
#if defined(SHADOW_IOS_PORT)
extern "C" void* objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void*);

static uint32_t GetIOSPthreadId(pthread_t t)
{
\tuint64_t tid = 0;
\tif (pthread_threadid_np(t, &tid) == 0 && tid != 0)
\t\treturn static_cast<uint32_t>(tid);
\treturn static_cast<uint32_t>(reinterpret_cast<uintptr_t>(t));
}
#endif

static void GuestThreadFunc(GuestThreadHandle* hThread)
{
#if defined(SHADOW_IOS_PORT)
\tvoid* arp = objc_autoreleasePoolPush();
#endif
\thThread->suspended.wait(true);
\tGuestThread::Start(hThread->params);
#if defined(SHADOW_IOS_PORT)
\tobjc_autoreleasePoolPop(arp);
#endif
}

#if defined(SHADOW_IOS_PORT)
static void* GuestThreadFuncPthread(void* arg)
{
\tGuestThreadFunc(static_cast<GuestThreadHandle*>(arg));
\treturn nullptr;
}

GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
\t: params(params), suspended((params.flags & 0x1) != 0)
{
\tpthread_attr_t attr;
\tpthread_attr_init(&attr);
\tpthread_attr_setstacksize(&attr, 8 * 1024 * 1024); // 8 MB stack per evitare crash 512 KB su iOS
\tif (pthread_create(&thread, &attr, &GuestThreadFuncPthread, this) == 0)
\t{
\t\thostThreadId.store(GetIOSPthreadId(thread), std::memory_order_release);
\t\tthreadValid.store(true, std::memory_order_release);
\t}
\tpthread_attr_destroy(&attr);
}
#else
GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
\t: params(params), suspended((params.flags & 0x1) != 0), thread(GuestThreadFunc, this)
{

}
#endif

static uint32_t GetThreadId(const std::thread::id& id)
{
\treturn *reinterpret_cast<const uint32_t*>(&id);
}

GuestThreadHandle::~GuestThreadHandle()
{
#if defined(SHADOW_IOS_PORT)
\tauto id = hostThreadId.load(std::memory_order_acquire);
#else
\tauto id = GetThreadId(this->thread.get_id());
#endif
\tstd::string s = GetThreadName(params.function);
\tLOGFN("Destroy thread {:08X} with ID {} ({})", params.function, id, s);

\tif (suspended.load())
\t{
\t\tLOGFN_WARNING("GuestThread: Destroying suspended thread {:08X} ({}), forcing resume", params.function, s);
\t\tsuspended.store(false, std::memory_order_release);
\t\tsuspended.notify_all();
\t}

\t{
\t\tstd::lock_guard lock(suspendMutex);
\t\tresumeRequested = true;
\t}
\tsuspendCV.notify_all();

#if defined(SHADOW_IOS_PORT)
\tif (threadValid.exchange(false, std::memory_order_acq_rel))
\t\tpthread_join(thread, nullptr);
#else
\tif (thread.joinable())
\t\tthread.join();
#endif
}

uint32_t GuestThreadHandle::Wait(uint32_t timeout)
{
\tLOGFN("Wait: Thread {:08X}", params.function);
\tassert(timeout == INFINITE);

#if defined(SHADOW_IOS_PORT)
\tif (threadValid.exchange(false, std::memory_order_acq_rel))
\t\tpthread_join(thread, nullptr);
#else
\tif (thread.joinable())
\t\tthread.join();
#endif

\treturn STATUS_WAIT_0;
}



GuestThreadHandle* GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId)
{
\tauto hThread = CreateKernelObject<GuestThreadHandle>(params);

\tif (threadId != nullptr)
\t{
#if defined(SHADOW_IOS_PORT)
\t\t*threadId = hThread->hostThreadId.load(std::memory_order_acquire);
#else
\t\t*threadId = GetThreadId(hThread->thread.get_id());
#endif"""
    if old_gt_block not in gtc_src:
        raise RuntimeError("Failed to locate GuestThreadHandle implementation block in cpu/guest_thread.cpp!")
    gtc_src = gtc_src.replace(old_gt_block, new_gt_block, 1)

    old_cur_tid = """uint32_t GuestThread::GetCurrentThreadId()
{
\treturn GetThreadId(std::this_thread::get_id());
}"""
    new_cur_tid = """uint32_t GuestThread::GetCurrentThreadId()
{
#if defined(SHADOW_IOS_PORT)
\treturn GetIOSPthreadId(pthread_self());
#else
\treturn GetThreadId(std::this_thread::get_id());
#endif
}"""
    if old_cur_tid not in gtc_src:
        raise RuntimeError("Failed to locate GuestThread::GetCurrentThreadId in cpu/guest_thread.cpp!")
    gtc_src = gtc_src.replace(old_cur_tid, new_cur_tid, 1)
    gtc_p.write_text(gtc_src, encoding="utf-8")
    print("Patched cpu/guest_thread.cpp for 8 MB iOS pthread stack + pthread_threadid_np")

# 7c. gpu/video.cpp: precompile shader/pipeline idempotente (fix crash post-install) + render thread 8 MB stack + autoreleasepool drain
vid_p = pathlib.Path(sys.argv[4])
vid_src = vid_p.read_text(encoding="utf-8")
if "SHADOW_IOS_VIDEO_FIX" not in vid_src:
    old_ps = """static void PrecompileShaders(const std::function<void(float)>& progress = {})
{
\tauto totalStart = std::chrono::steady_clock::now();"""
    new_ps = """static void PrecompileShaders(const std::function<void(float)>& progress = {})
{
\t/* SHADOW_IOS_VIDEO_FIX: evita doppia compilazione e leak GPU dopo InstallerWizard */
\tstatic bool s_shadersPrecompiled = false;
\tif (s_shadersPrecompiled)
\t{
\t\tif (progress) progress(PIPELINE_PRECOMPILE_SHADER_STAGE_END);
\t\treturn;
\t}
\tauto totalStart = std::chrono::steady_clock::now();"""
    if old_ps not in vid_src:
        raise RuntimeError("Failed to locate PrecompileShaders in gpu/video.cpp!")
    vid_src = vid_src.replace(old_ps, new_ps, 1)

    old_ps_end = '\tLOGFN("PrecompileShaders: {} shaders in {:.2f} ms", g_shaderCacheEntryCount, totalElapsed);'
    new_ps_end = '\ts_shadersPrecompiled = true;\\n\tLOGFN("PrecompileShaders: {} shaders in {:.2f} ms", g_shaderCacheEntryCount, totalElapsed);'
    if old_ps_end not in vid_src:
        raise RuntimeError("Failed to locate PrecompileShaders end log in gpu/video.cpp!")
    vid_src = vid_src.replace(old_ps_end, new_ps_end, 1)

    old_psp = """static void PrecompileStaticPipelines(const std::function<void(float)>& progress = {})
{
\tif constexpr (g_staticPipelineCacheCount == 0)
\t\treturn;"""
    new_psp = """static void PrecompileStaticPipelines(const std::function<void(float)>& progress = {})
{
\tif constexpr (g_staticPipelineCacheCount == 0)
\t\treturn;
\tstatic bool s_staticPipelinesPrecompiled = false;
\tif (s_staticPipelinesPrecompiled)
\t{
\t\tif (progress) progress(1.0f);
\t\treturn;
\t}"""
    if old_psp not in vid_src:
        raise RuntimeError("Failed to locate PrecompileStaticPipelines in gpu/video.cpp!")
    vid_src = vid_src.replace(old_psp, new_psp, 1)

    old_psp_end = '\tLOGFN("PipelineCache: Static precompiled {} pipelines ({} deferred) in {:.2f} ms", compiled, deferred, totalElapsed);'
    new_psp_end = '\ts_staticPipelinesPrecompiled = true;\\n\tLOGFN("PipelineCache: Static precompiled {} pipelines ({} deferred) in {:.2f} ms", compiled, deferred, totalElapsed);'
    if old_psp_end not in vid_src:
        raise RuntimeError("Failed to locate PrecompileStaticPipelines end log in gpu/video.cpp!")
    vid_src = vid_src.replace(old_psp_end, new_psp_end, 1)

    old_rt_head = """static std::thread g_renderThread([]
\t{"""
    new_rt_head = """#if defined(SHADOW_IOS_PORT)
#include <pthread.h>
extern "C" void* objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void*);
static void ShadowIOSRenderThreadMain()
#else
static std::thread g_renderThread([]
#endif
\t{"""
    if old_rt_head not in vid_src:
        raise RuntimeError("Failed to locate g_renderThread in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_head, new_rt_head, 1)

    old_rt_loop = """\t\t\t\t\tif (g_renderDirectorProfiler.active)
\t\t\t\t\t\tg_rtQueueWaitInFrameAccum.Add(waitMs);
\t\t\t\t}
\t\t\t}
\t\t\tfor (size_t i = 0; i < count; i++)"""
    new_rt_loop = """\t\t\t\t\tif (g_renderDirectorProfiler.active)
\t\t\t\t\t\tg_rtQueueWaitInFrameAccum.Add(waitMs);
\t\t\t\t}
\t\t\t}
#if defined(SHADOW_IOS_PORT)
\t\t\tvoid* iosArp = objc_autoreleasePoolPush();
#endif
\t\t\tfor (size_t i = 0; i < count; i++)"""
    if old_rt_loop not in vid_src:
        raise RuntimeError("Failed to locate render loop batch in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_loop, new_rt_loop, 1)

    old_rt_end = """\t\t\t\tdefault:
\t\t\t\t\tProcessRenderCommand(cmd);
\t\t\t\t\tbreak;
\t\t\t\t}
\t\t\t}
\t\t}
\t});"""
    new_rt_end = """\t\t\t\tdefault:
\t\t\t\t\tProcessRenderCommand(cmd);
\t\t\t\t\tbreak;
\t\t\t\t}
\t\t\t}
#if defined(SHADOW_IOS_PORT)
\t\t\tobjc_autoreleasePoolPop(iosArp);
#endif
\t\t}
#if defined(SHADOW_IOS_PORT)
\t}
struct ShadowIOSRenderThreadStarter
{
\tstatic void* Entry(void*)
\t{
\t\tShadowIOSRenderThreadMain();
\t\treturn nullptr;
\t}
\tShadowIOSRenderThreadStarter()
\t{
\t\tpthread_t tid{};
\t\tpthread_attr_t attr;
\t\tpthread_attr_init(&attr);
\t\tpthread_attr_setstacksize(&attr, 8 * 1024 * 1024); // 8 MB stack per MoltenVK + SPIRV-Cross
\t\tif (pthread_create(&tid, &attr, &Entry, nullptr) == 0)
\t\t\tpthread_detach(tid);
\t\tpthread_attr_destroy(&attr);
\t}
};
static ShadowIOSRenderThreadStarter g_renderThread;
#else
\t});
#endif"""
    if old_rt_end not in vid_src:
        raise RuntimeError("Failed to locate g_renderThread closing block in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_end, new_rt_end, 1)

    vid_p.write_text(vid_src, encoding="utf-8")
    print("Patched gpu/video.cpp: idempotent precompile + 8 MB iOS render thread + autoreleasepool")

# 7d. audio/driver/sdl3_driver.cpp: 1024 sample frames su iOS CoreAudio + protezione bounds ring-buffer in Pull()
aud_p = pathlib.Path(sys.argv[5])
aud_src = aud_p.read_text(encoding="utf-8")
if "SHADOW_IOS_AUDIO_FIX" not in aud_src:
    old_hint = '\tSDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "512"); // necessary for weapon SFX timing (SDL default is 1024)'
    new_hint = '''#if defined(SHADOW_IOS_PORT)
\t/* SHADOW_IOS_AUDIO_FIX: 1024 frame (~21ms @ 48kHz) riduce interruzioni CoreAudio realtime su iOS */
\tSDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "1024");
#else
\tSDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "512"); // necessary for weapon SFX timing (SDL default is 1024)
#endif'''
    if old_hint not in aud_src:
        raise RuntimeError("Failed to locate SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES in sdl3_driver.cpp!")
    aud_src = aud_src.replace(old_hint, new_hint, 1)

    old_pull = """\tint srcBytesPerSample = SDL_AUDIO_BITSIZE(mFormat) / 8 * mChannelCount;
\tint dstBytesPerSample = SDL_AUDIO_BITSIZE(mParent->mFormat) / 8 * mParent->mChannelCount;
\tfloat ratio = (float)mParent->mFrequency / (float)mFrequency
\t\t* (float)dstBytesPerSample / (float)srcBytesPerSample;
\tint read_size = (int)(size / ratio);
\tread_size -= read_size % srcBytesPerSample; // align to sample boundary

\tread_size = mLooping
\t\t? read_size
\t\t: std::min(read_size, mWrittenSize);

\tif (read_size <= 0)
\t{
\t\tStopSfxEarly();
\t\treturn result;
\t}"""
    new_pull = """\tif (mBufferSize <= 0 || mFrequency <= 0 || mParent->mFrequency <= 0 || size <= 0)
\t{
\t\tStopSfxEarly();
\t\treturn result;
\t}

\tint srcBytesPerSample = SDL_AUDIO_BITSIZE(mFormat) / 8 * mChannelCount;
\tint dstBytesPerSample = SDL_AUDIO_BITSIZE(mParent->mFormat) / 8 * mParent->mChannelCount;
\tif (srcBytesPerSample <= 0 || dstBytesPerSample <= 0)
\t{
\t\treturn result;
\t}

\tfloat ratio = (float)mParent->mFrequency / (float)mFrequency
\t\t* (float)dstBytesPerSample / (float)srcBytesPerSample;
\tint read_size = (int)(size / ratio);
\tread_size -= read_size % srcBytesPerSample; // align to sample boundary

\tread_size = mLooping
\t\t? read_size
\t\t: std::min(read_size, mWrittenSize);

\tif (read_size > mBufferSize)
\t{
\t\tread_size = mBufferSize - (mBufferSize % srcBytesPerSample);
\t}

\tif (mBufferReadLoc < 0 || mBufferReadLoc >= mBufferSize)
\t{
\t\tmBufferReadLoc = ((mBufferReadLoc % mBufferSize) + mBufferSize) % mBufferSize;
\t}

\tif (read_size <= 0)
\t{
\t\tStopSfxEarly();
\t\treturn result;
\t}"""
    if old_pull not in aud_src:
        raise RuntimeError("Failed to locate Pull() bounds block in sdl3_driver.cpp!")
    aud_src = aud_src.replace(old_pull, new_pull, 1)
    aud_p.write_text(aud_src, encoding="utf-8")
    print("Patched audio/driver/sdl3_driver.cpp: 1024 frames + ring-buffer bounds protection")

# 7e. thirdparty/o1heap/o1heap.{h,c} + kernel/heap.cpp: rilascia pagine liberate >= 64 KB a iOS Jetsam (madvise MADV_FREE)
o1h_p = pathlib.Path(sys.argv[6])
o1h_src = o1h_p.read_text(encoding="utf-8")
if "o1heapFreeAndGetUnusedRange" not in o1h_src:
    old_o1h = "    void o1heapFree(O1HeapInstance* const handle, void* const pointer);"
    new_o1h = """    void o1heapFree(O1HeapInstance* const handle, void* const pointer);
    void o1heapFreeAndGetUnusedRange(O1HeapInstance* const handle, void* const pointer, void** out_begin, size_t* out_size);"""
    if old_o1h not in o1h_src:
        raise RuntimeError("Failed to locate o1heapFree declaration in thirdparty/o1heap/o1heap.h!")
    o1h_src = o1h_src.replace(old_o1h, new_o1h, 1)
    o1h_p.write_text(o1h_src, encoding="utf-8")
    print("Patched thirdparty/o1heap/o1heap.h with o1heapFreeAndGetUnusedRange")

o1c_p = pathlib.Path(sys.argv[7])
o1c_src = o1c_p.read_text(encoding="utf-8")
if "o1heapFreeAndGetUnusedRange" not in o1c_src:
    old_o1c = """void o1heapFree(O1HeapInstance* const handle, void* const pointer)
{
    O1HEAP_ASSERT(handle != NULL);
    O1HEAP_ASSERT(handle->diagnostics.capacity <= FRAGMENT_SIZE_MAX);
    if (O1HEAP_LIKELY(pointer != NULL))  // NULL pointer is a no-op.
    {
        Fragment* const frag = (Fragment*)(void*)(((char*)pointer) - O1HEAP_ALIGNMENT);

        // Check for heap corruption in debug builds.
        O1HEAP_ASSERT(((size_t)frag) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(((size_t)frag) >= (((size_t)handle) + INSTANCE_SIZE_PADDED));
        O1HEAP_ASSERT(((size_t)frag) <=
            (((size_t)handle) + INSTANCE_SIZE_PADDED + handle->diagnostics.capacity - FRAGMENT_SIZE_MIN));
        O1HEAP_ASSERT(frag->header.used);  // Catch double-free
        O1HEAP_ASSERT(((size_t)frag->header.next) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(((size_t)frag->header.prev) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(frag->header.size >= FRAGMENT_SIZE_MIN);
        O1HEAP_ASSERT(frag->header.size <= handle->diagnostics.capacity);
        O1HEAP_ASSERT((frag->header.size % FRAGMENT_SIZE_MIN) == 0U);

        // Even if we're going to drop the fragment later, mark it free anyway to prevent double-free.
        frag->header.used = false;

        // Update the diagnostics. It must be done before merging because it invalidates the fragment size information.
        O1HEAP_ASSERT(handle->diagnostics.allocated >= frag->header.size);  // Heap corruption check.
        handle->diagnostics.allocated -= frag->header.size;

        // Merge with siblings and insert the returned fragment into the appropriate bin and update metadata.
        Fragment* const prev = frag->header.prev;
        Fragment* const next = frag->header.next;
        const bool      join_left = (prev != NULL) && (!prev->header.used);
        const bool      join_right = (next != NULL) && (!next->header.used);
        if (join_left && join_right)  // [ prev ][ this ][ next ] => [ ------- prev ------- ]
        {
            unbin(handle, prev);
            unbin(handle, next);
            prev->header.size += frag->header.size + next->header.size;
            frag->header.size = 0;  // Invalidate the dropped fragment headers to prevent double-free.
            next->header.size = 0;
            O1HEAP_ASSERT((prev->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(prev, next->header.next);
            rebin(handle, prev);
        }
        else if (join_left)  // [ prev ][ this ][ next ] => [ --- prev --- ][ next ]
        {
            unbin(handle, prev);
            prev->header.size += frag->header.size;
            frag->header.size = 0;
            O1HEAP_ASSERT((prev->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(prev, next);
            rebin(handle, prev);
        }
        else if (join_right)  // [ prev ][ this ][ next ] => [ prev ][ --- this --- ]
        {
            unbin(handle, next);
            frag->header.size += next->header.size;
            next->header.size = 0;
            O1HEAP_ASSERT((frag->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(frag, next->header.next);
            rebin(handle, frag);
        }
        else
        {
            rebin(handle, frag);
        }
    }
}"""
    new_o1c = """void o1heapFreeAndGetUnusedRange(O1HeapInstance* const handle, void* const pointer, void** out_begin, size_t* out_size)
{
    if (out_begin != NULL) *out_begin = NULL;
    if (out_size != NULL) *out_size = 0U;
    O1HEAP_ASSERT(handle != NULL);
    O1HEAP_ASSERT(handle->diagnostics.capacity <= FRAGMENT_SIZE_MAX);
    if (O1HEAP_LIKELY(pointer != NULL))  // NULL pointer is a no-op.
    {
        Fragment* const frag = (Fragment*)(void*)(((char*)pointer) - O1HEAP_ALIGNMENT);

        O1HEAP_ASSERT(((size_t)frag) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(((size_t)frag) >= (((size_t)handle) + INSTANCE_SIZE_PADDED));
        O1HEAP_ASSERT(((size_t)frag) <=
            (((size_t)handle) + INSTANCE_SIZE_PADDED + handle->diagnostics.capacity - FRAGMENT_SIZE_MIN));
        O1HEAP_ASSERT(frag->header.used);  // Catch double-free
        O1HEAP_ASSERT(((size_t)frag->header.next) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(((size_t)frag->header.prev) % sizeof(Fragment*) == 0U);
        O1HEAP_ASSERT(frag->header.size >= FRAGMENT_SIZE_MIN);
        O1HEAP_ASSERT(frag->header.size <= handle->diagnostics.capacity);
        O1HEAP_ASSERT((frag->header.size % FRAGMENT_SIZE_MIN) == 0U);

        frag->header.used = false;
        O1HEAP_ASSERT(handle->diagnostics.allocated >= frag->header.size);
        handle->diagnostics.allocated -= frag->header.size;

        Fragment* const prev = frag->header.prev;
        Fragment* const next = frag->header.next;
        const bool      join_left = (prev != NULL) && (!prev->header.used);
        const bool      join_right = (next != NULL) && (!next->header.used);
        Fragment*       merged = frag;
        if (join_left && join_right)
        {
            unbin(handle, prev);
            unbin(handle, next);
            prev->header.size += frag->header.size + next->header.size;
            frag->header.size = 0;
            next->header.size = 0;
            O1HEAP_ASSERT((prev->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(prev, next->header.next);
            rebin(handle, prev);
            merged = prev;
        }
        else if (join_left)
        {
            unbin(handle, prev);
            prev->header.size += frag->header.size;
            frag->header.size = 0;
            O1HEAP_ASSERT((prev->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(prev, next);
            rebin(handle, prev);
            merged = prev;
        }
        else if (join_right)
        {
            unbin(handle, next);
            frag->header.size += next->header.size;
            next->header.size = 0;
            O1HEAP_ASSERT((frag->header.size % FRAGMENT_SIZE_MIN) == 0U);
            interlink(frag, next->header.next);
            rebin(handle, frag);
            merged = frag;
        }
        else
        {
            rebin(handle, frag);
        }

        if (out_begin != NULL && out_size != NULL && merged->header.size > sizeof(Fragment))
        {
            *out_begin = ((char*)merged) + sizeof(Fragment);
            *out_size = merged->header.size - sizeof(Fragment);
        }
    }
}

void o1heapFree(O1HeapInstance* const handle, void* const pointer)
{
    o1heapFreeAndGetUnusedRange(handle, pointer, NULL, NULL);
}"""
    if old_o1c not in o1c_src:
        raise RuntimeError("Failed to locate o1heapFree body in thirdparty/o1heap/o1heap.c!")
    o1c_src = o1c_src.replace(old_o1c, new_o1c, 1)
    o1c_p.write_text(o1c_src, encoding="utf-8")
    print("Patched thirdparty/o1heap/o1heap.c with o1heapFreeAndGetUnusedRange")

heap_p = pathlib.Path(sys.argv[8])
heap_src = heap_p.read_text(encoding="utf-8")
if "SHADOW_IOS_JETSAM_DISCARD" not in heap_src:
    old_heap_free = r"""void Heap::Free(void* ptr)
{

\t// Check if pointer is in physical heap region
\tif (ptr >= physicalHeap)
\t{
\t\t//printf("[FREE PHYSICAL] ptr: %p\\n", ptr);
\t\tstd::lock_guard lock(physicalMutex);
\t\to1heapFree(physicalHeap, *((void**)ptr - 1));
\t}
\telse
\t{
\t\t//printf("[FREE REGULAR] ptr: %p\\n", ptr);
\t\tstd::lock_guard lock(mutex);
\t\to1heapFree(heap, ptr);
\t}

}"""
    new_heap_free = """#if defined(SHADOW_IOS_PORT)
#include <sys/mman.h>
#include <unistd.h>
static void ShadowIOSDiscardPages(void* begin, size_t size)
{
\t/* SHADOW_IOS_JETSAM_DISCARD: restituisce pagine liberate >= 64 KB a Darwin Jetsam */
\tif (!begin || size < 65536) return;
\tstatic const size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
\tconst uintptr_t rawStart = reinterpret_cast<uintptr_t>(begin);
\tconst uintptr_t rawEnd = rawStart + size;
\tconst uintptr_t alignedStart = (rawStart + pageSize - 1) & ~(pageSize - 1);
\tconst uintptr_t alignedEnd = rawEnd & ~(pageSize - 1);
\tif (alignedEnd > alignedStart && (alignedEnd - alignedStart) >= 65536)
\t{
\t\tmadvise(reinterpret_cast<void*>(alignedStart), alignedEnd - alignedStart, MADV_FREE);
\t}
}
#endif

void Heap::Free(void* ptr)
{
\tif (!ptr) return;

\t// Check if pointer is in physical heap region
\tif (ptr >= physicalHeap)
\t{
\t\tstd::lock_guard lock(physicalMutex);
#if defined(SHADOW_IOS_PORT)
\t\tvoid* unusedBegin = nullptr;
\t\tsize_t unusedSize = 0;
\t\to1heapFreeAndGetUnusedRange(physicalHeap, *((void**)ptr - 1), &unusedBegin, &unusedSize);
\t\tShadowIOSDiscardPages(unusedBegin, unusedSize);
#else
\t\to1heapFree(physicalHeap, *((void**)ptr - 1));
#endif
\t}
\telse
\t{
\t\tstd::lock_guard lock(mutex);
#if defined(SHADOW_IOS_PORT)
\t\tvoid* unusedBegin = nullptr;
\t\tsize_t unusedSize = 0;
\t\to1heapFreeAndGetUnusedRange(heap, ptr, &unusedBegin, &unusedSize);
\t\tShadowIOSDiscardPages(unusedBegin, unusedSize);
#else
\t\to1heapFree(heap, ptr);
#endif
\t}
}"""
    if old_heap_free not in heap_src:
        raise RuntimeError("Failed to locate Heap::Free in kernel/heap.cpp!")
    heap_src = heap_src.replace(old_heap_free, new_heap_free, 1)
    heap_p.write_text(heap_src, encoding="utf-8")
    print("Patched kernel/heap.cpp with iOS Jetsam MADV_FREE page discard")
PY_IOS_RUNTIME

echo "==> [8/8] Patch iOS completata con successo!"`;

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
        ${config.enable120HzProMotion ? 'SHADOW_IOS_PROMOTION_120HZ=1' : 'SHADOW_IOS_PROMOTION_120HZ=0'}
    )

    # Disabilita PCH e abilita ARC (-fobjc-arc) sui file Objective-C++ (.mm) per Ninja/AppleClang
    set_source_files_properties(
        "os/ios/ios_platform.mm"
        "os/ios/nfd_ios.mm"
        "os/ios/ios_mod_manager.mm"
        "os/ios/curl_ios_stub.mm"
        PROPERTIES
            SKIP_PRECOMPILE_HEADERS ON
            COMPILE_OPTIONS "-fobjc-arc"
    )

    # Link statico MoltenVK (Vulkan -> Apple Metal 3) + forza export simbolo vkGetInstanceProcAddr per SDL3/Volk
    if(MOLTENVK_STATIC_LIB AND EXISTS "\${MOLTENVK_STATIC_LIB}")
        target_link_libraries(\${TARGET_NAME} PRIVATE "\${MOLTENVK_STATIC_LIB}")
        target_link_options(\${TARGET_NAME} PRIVATE "-Wl,-u,_vkGetInstanceProcAddr" "-Wl,-export_dynamic")
    else()
        message(WARNING "MOLTENVK_STATIC_LIB non trovato; verificare il download di MoltenVK-ios.tar")
    endif()

    # FreeType iOS arm64 (usato da imgui_freetype.cpp e msdf-atlas-gen) + zlib di sistema
    find_package(Freetype REQUIRED)
    target_include_directories(\${TARGET_NAME} PRIVATE \${FREETYPE_INCLUDE_DIRS})

    # Framework Apple iOS necessari per Metal 3, SDL3, App File, Controller, FreeType e Audio
    target_link_libraries(\${TARGET_NAME} PRIVATE
        Freetype::Freetype
        "-lz"
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
#include <SDL3/SDL_hints.h>
#include <cstdint>
#include <cstdio>
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
std::once_flag g_iosRuntimeInitOnce;

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

void InitializeIOSRuntimeOnce() {
    std::call_once(g_iosRuntimeInitOnce, []() {
        // Hint SDL3 specifici per iOS (orientamento landscape, schermo attivo, home indicator nascosto)
        SDL_SetHint(SDL_HINT_VIDEO_ALLOW_SCREENSAVER, "0");
        SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
        SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].idleTimerDisabled = YES;
        });

        // Configura AVAudioSession UNA SOLA VOLTA fuori dal thread realtime CoreAudio
        // Ambient rispetta il tasto silenzioso e non va in conflitto con LiveContainer
        @autoreleasepool {
            AVAudioSession *session = [AVAudioSession sharedInstance];
            NSError *err = nil;
            [session setCategory:AVAudioSessionCategoryAmbient error:&err];
            [session setPreferredSampleRate:48000.0 error:nil];
            [session setPreferredIOBufferDuration:0.021333 error:nil];
            [session setActive:YES error:&err];
        }
    });
}
}

namespace os::logger {

void Init() {
    InitializeIOSRuntimeOnce();
    std::error_code ec;
    std::filesystem::create_directories(GetIOSDocumentsDir() / "ShadowRecomp" / "logs", ec);
}

void Log(const std::string_view str, ELogType type, const char* func) {
    // Non chiamare mai NSLog sotto mutex globale: causa contention/deadlock con CoreAudio/RenderThread
    const char* prefix = "[INFO]";
    if (type == ELogType::Warning) prefix = "[WARN]";
    else if (type == ELogType::Error) prefix = "[ERR ]";
    else if (type == ELogType::Utility) prefix = "[UTIL]";

    std::fprintf(stderr, "ShadowRecomp %s [%s] %.*s\\n", prefix, func ? func : "*", static_cast<int>(str.size()), str.data());
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

// CRITICO su iOS: UpdateMusicAttenuation() gira sul thread realtime CoreAudio AURemoteIO!
// Chiamare AVAudioSession/XPC dentro il callback audio causa freeze/crash casuali con audio attivo.
bool IsExternalMediaPlaying() {
    return false;
}

bool IsSupported() {
    return false;
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
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL pickFolder;
@end

@implementation ShadowDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        self.cancelled = YES;
        self.finished = YES;
        if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
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
    self.finished = YES;
    if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.cancelled = YES;
    self.finished = YES;
    if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
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

static ShadowDocumentPickerDelegate *g_activePickerDelegate = nil;

static nfdresult_t PresentIOSFilesPicker(nfdu8char_t** outPath, BOOL folderMode) {
    if (!outPath) {
        g_lastNfdError = "outPath is null";
        return NFD_ERROR;
    }
    *outPath = nullptr;

    ShadowDocumentPickerDelegate *delegate = [[ShadowDocumentPickerDelegate alloc] init];
    delegate.pickFolder = folderMode;
    delegate.cancelled = YES;
    delegate.finished = NO;
    g_activePickerDelegate = delegate;

    void (^presentBlock)(void) = ^{
        UIViewController *presenter = GetTopViewController();
        if (!presenter) {
            g_lastNfdError = "No active UIViewController to present Files app";
            delegate.finished = YES;
            if (delegate.semaphore) dispatch_semaphore_signal(delegate.semaphore);
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
    };

    if ([NSThread isMainThread]) {
        presentBlock();
        while (!delegate.finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    } else {
        delegate.semaphore = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), presentBlock);
        dispatch_semaphore_wait(delegate.semaphore, DISPATCH_TIME_FOREVER);
    }

    NSString *resultPath = delegate.selectedPath;
    BOOL wasCancelled = delegate.cancelled;
    g_activePickerDelegate = nil;

    if (wasCancelled || resultPath.length == 0) {
        return NFD_CANCEL;
    }

    const char* utf8 = resultPath.UTF8String;
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
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
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
typedef int CURLINFO;
struct curl_slist { char* data; struct curl_slist* next; };

#define CURLE_OK 0
#define CURLE_UNSUPPORTED_PROTOCOL 1
#define CURL_GLOBAL_DEFAULT 3L
#define CURLOPT_URL 10002
#define CURLOPT_USERAGENT 10018
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_FOLLOWLOCATION 52
#define CURLOPT_TIMEOUT 13
#define CURLOPT_CONNECTTIMEOUT 78
#define CURLOPT_HTTPHEADER 10023
#define CURLOPT_FAILONERROR 45
#define CURLOPT_SSL_VERIFYPEER 64
#define CURLINFO_RESPONSE_CODE 0x200002

CURLcode curl_global_init(long flags);
void curl_global_cleanup(void);
CURL* curl_easy_init(void);
CURLcode curl_easy_setopt(CURL* curl, CURLoption option, ...);
CURLcode curl_easy_perform(CURL* curl);
CURLcode curl_easy_getinfo(CURL* curl, CURLINFO info, ...);
void curl_easy_cleanup(CURL* curl);
const char* curl_easy_strerror(CURLcode code);
struct curl_slist* curl_slist_append(struct curl_slist* list, const char* string);
void curl_slist_free_all(struct curl_slist* list);

#ifdef __cplusplus
}
#endif`;

  const curlStubMm = `// ios/curl_ios_stub.mm
#include <curl/curl.h>

extern "C" {
CURLcode curl_global_init(long) { return CURLE_OK; }
void curl_global_cleanup(void) {}
CURL* curl_easy_init(void) { return reinterpret_cast<CURL*>(1); }
CURLcode curl_easy_setopt(CURL*, CURLoption, ...) { return CURLE_OK; }
CURLcode curl_easy_perform(CURL*) { return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_easy_getinfo(CURL*, CURLINFO, ...) { return CURLE_OK; }
void curl_easy_cleanup(CURL*) {}
const char* curl_easy_strerror(CURLcode) { return "Update checker disabled on iOS sideload"; }
struct curl_slist* curl_slist_append(struct curl_slist* list, const char*) { return list; }
void curl_slist_free_all(struct curl_slist*) {}
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

  const gitignoreContent = `# Protezione legale: impedisce di committare file protetti da copyright SEGA / Xbox nel repo Git
private/
*.xbe
*.iso
*.xiso
*.afs
*.one
*.txd
build/
build-ios/
build-host/
Payload/
*.ipa
*.mp4
*.mov
public/assets/aistudio/
node_modules/
dist/
.DS_Store`;

  const readmeMd = `# ShadowRecomp iOS Port (Stile MarathonRecompilediOS — Zero File Protetti su Git)

Porting iOS per **iPhone 16 Pro (arm64)** di [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp), basato sullo stesso flusso di [DevZer0D4Y/MarathonRecompilediOS](https://github.com/DevZer0D4Y/MarathonRecompilediOS).
Tutta la compilazione avviene nel cloud su **GitHub Actions (\`macos-15\`)**, senza bisogno di un Mac.

## 100% Pulito sul Repository GitHub
- Questo repository contiene **ZERO file protetti da copyright** (\`.gitignore\` blocca \`*.xbe\`, \`*.iso\`, \`*.xiso\` e \`private/\`).
- Esattamente come \`MarathonRecompilediOS\` (\`Sonic06-iOS.ipa\`, ~35 MB): l'\`.ipa\` finale **non contiene nessun asset di gioco** (texture, livelli, audio, filmati).
- Al primo avvio dell'\`.ipa\` su **iPhone 16 Pro** (installato da **Feather** o **LiveContainer**), l'app apre l'**App File di iOS** per farti selezionare la cartella con i file estratti dalla tua \`.xiso\`, completa l'importazione, e al riavvio il gioco parte!

## Come compilare l'\`.ipa\` su GitHub Actions senza MAI caricare \`default.xbe\` nel repo
1. Carica tutti i file di questo pacchetto nel tuo repository GitHub.
2. Vai su **Settings → Secrets and variables → Actions → New repository secret**.
3. Crea il Secret cifrato **\`DEFAULT_XBE_URL\`** con un link diretto temporaneo/privato al tuo \`default.xbe\` (~4.8 MB).
   - Il Secret è cifrato e invisibile a tutti; \`default.xbe\` viene scaricato **solo** nella VM temporanea \`macos-15\` durante la compilazione di \`XboxRecomp2\` e distrutto subito a fine build.
4. Vai su **Actions → Build ShadowRecomp iOS Unsigned IPA → Run workflow** *(opzionale: spunta \`publish_release\` se vuoi creare una Release con \`${config.appName}-iOS.ipa\` come \`MarathonRecompilediOS\`)* e scarica il file \`.ipa\` su iPhone!`;

  return [
    {
      path: '.github/workflows/build-ios-ipa.yml',
      title: 'GitHub Action Cloud Builder (.yml)',
      language: 'yaml',
      description: 'Clona branch master, recupera default.xbe via Secret effimero, compila XboxRecomp2 + MoltenVK e crea l’IPA unsigned.',
      content: workflowYml,
    },
    {
      path: '.gitignore',
      title: 'Protezione Anti-Copyright (.gitignore)',
      language: 'bash',
      description: 'Blocca automaticamente *.xbe, *.iso, *.xiso e private/ affinché nessun file di gioco finisca mai nel repo Git.',
      content: gitignoreContent,
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
