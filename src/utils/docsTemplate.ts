// Global English GitHub documentation templates for EdgyiOS:
// - README.md (EdgyiOS: Shadow The Hedgehog Recompiled for iOS)
// - LEGAL.md (Legal Notice, Trademarks, Ownership Policy, Google AI Studio Disclosure, Third-Party Licenses)
// - RELEASE_NOTES.md (Versioned Release Notes for GitHub Releases & CI workflow)

export interface DocsTemplateConfig {
  appName: string;
  appVersion: string;
  deploymentTarget: string;
  upstreamRepoUrl: string;
  iosRefRepoUrl: string;
}

export function generateEdgyIosReadmeMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `<div align="center">

<img src="ios/AppIcon.jpg" alt="EdgyiOS App Icon" width="128" height="128" />

# EdgyiOS
### *Shadow The Hedgehog Recompiled for iOS*

**Native iOS & iPadOS port (arm64 · Metal 3 · 120Hz ProMotion) developed by hiperema with Google AI Studio**

[![Platform](https://img.shields.io/badge/Platform-iOS%20${config.deploymentTarget}%2B%20%7C%20iPadOS%20${config.deploymentTarget}%2B-111111?style=for-the-badge&logo=apple&logoColor=white)](#compatible-devices)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20Native%20(Zero%20JIT)-dc2626?style=for-the-badge)](#how-it-was-developed)
[![Graphics](https://img.shields.io/badge/Graphics-Vulkan%20%E2%86%92%20MoltenVK%20%E2%86%92%20Metal%203-0ea5e9?style=for-the-badge)](#ios-exclusive-features)
[![Sideload](https://img.shields.io/badge/Sideload-Feather%20%7C%20LiveContainer-6366f1?style=for-the-badge)](#installation-on-iphone--ipad)
[![Assets](https://img.shields.io/badge/Copyrighted%20Assets-0%25%20Clean%20Repo-16a34a?style=for-the-badge)](#legal--copyright-notice)

<p>
  <a href="#ios-exclusive-features">iOS Features</a> •
  <a href="#compatible-devices">Compatible iPhone &amp; iPad</a> •
  <a href="#how-it-was-developed">How It Was Developed</a> •
  <a href="#github-resources--credits">GitHub Resources &amp; Credits</a> •
  <a href="#cloud-build-no-mac-required">No-Mac Cloud Build</a> •
  <a href="#installation-on-iphone--ipad">Installation</a> •
  <a href="RELEASE_NOTES.md">Release v${config.appVersion}</a> •
  <a href="LEGAL.md">Legal &amp; Licensing</a>
</p>

</div>

---

## Overview

**EdgyiOS: Shadow The Hedgehog Recompiled for iOS** is a native iOS and iPadOS port of the open-source static recompilation project [FoxWorkshop/ShadowRecomp](${cleanUpstream}), engineered to run *Shadow the Hedgehog (2005)* at full native Apple Silicon speed without JIT emulation and without requiring a Mac to build.

Unlike traditional emulators, static recompilation translates the original Xbox executable directly into native **arm64 C++** and compiles its shaders into **SPIR-V / Metal 3** via MoltenVK. The result is a fast, responsive native iOS app capable of up to **120 FPS** on ProMotion displays, featuring custom mobile enhancements: a vector Shadow-themed virtual controller with CoreHaptics, cross-platform 2-Player Hotspot/Wi-Fi multiplayer, Dual-Screen AirPlay & HDMI TV Mode, and automatic 6-language localization.

> **Important — Zero Copyrighted Assets:** Neither this repository nor the generated \`.ipa\` contains any copyrighted game assets, textures, audio, video, or proprietary SEGA/Sonic Team game code. To play, you must supply files extracted from **your own legally purchased copy** of *Shadow the Hedgehog (2005)* for the original Xbox using the iOS Files app. See [LEGAL.md](LEGAL.md) for full details.

---

## iOS Exclusive Features

### 1. Native arm64 Performance, Metal 3 & 120Hz ProMotion
- **100% Native Execution (Zero JIT):** Runs on stock, non-jailbroken iOS via both standalone sideloading (**Feather**) and containerized execution (**LiveContainer**, built with \`-fPIC -Wl,-pie\`).
- **True Native Full-Screen Resolution:** Configured with \`UILaunchScreen\` and universal \`UIDeviceFamily\` (iPhone + iPad) to render edge-to-edge at native display resolution (e.g., \`2622×1206\` on iPhone 16 Pro) with zero letterboxing or stretched scaling.
- **120Hz ProMotion Ready:** Enables \`CADisableMinimumFrameDurationOnPhone\`, zero-overhead overlay compositing (\`allowsGroupOpacity = NO\`), and a lock-free input ring buffer for smooth 120 FPS gameplay.
- **Extended Memory & Safe GPU Lifecycle:** Ships with \`increased-memory-limit\` and \`extended-virtual-addressing\` entitlements, plus synchronous Metal queue draining (\`vkQueueWaitIdle\`) on lock-screen/app-switch and automatic Vulkan swapchain recovery on resume.

### 2. Shadow-Themed Xbox Original Virtual Controller
- **Crisp Vector UI (CoreGraphics / QuartzCore):** Translucent obsidian-glass styling with crimson accents, a 3D-tilt & pressure-sensitive Shadow Emblem left stick, camera right stick, sliding 8-way D-Pad, classic Xbox ABXY cluster, analog \`LT/RT\` triggers, \`LB (White)\`, \`RB (Black)\`, \`L3\`, \`R3\`, \`Start\`, and \`Back\`.
- **CoreHaptics Taptic Engine Feedback:** Calibrated mechanical press/release clicks, analog stick detents, and native forwarding of in-game Xbox rumble (\`XboxVibrationPacket\`) to the iPhone Taptic Engine.
- **Chaos Emerald Quick-HUD:** Center Chaos Emerald button with dynamic **Hero / Neutral / Dark** aura that toggles a compact Quick-HUD bar featuring:
  - **Opacity** adjustment (\`25%–95%\`, persisted via \`NSUserDefaults\`);
  - **Haptics** toggle (ON/OFF);
  - **Auto-Hide 4s** (fades controls out after 4 seconds of inactivity and wakes instantly on touch);
  - **TV Mode** toggle (AirPlay / HDMI);
  - **2-Player Multiplayer** toggle;
  - **LOG** diagnostic recorder (10-second live telemetry & engine capture saved to \`ShadowRecomp/crashlog.txt\`).
- **Automatic Physical Controller Detection:** Connecting any Bluetooth or USB-C controller (DualSense, Xbox Wireless, Backbone, MFi) automatically hides the touch overlay for an unobstructed view.

### 3. Cross-Platform 2-Player Multiplayer (Personal Hotspot & Local Wi-Fi)
- **Built-In Local HTTP + WebSocket Server:** Powered by Apple \`Network.framework\` (\`nw_listener_t\`, port \`8765\`, \`TCP_NODELAY\`), automatically detecting Personal Hotspot (\`bridge100\` / \`172.20.10.1\`) or local Wi-Fi with zero internet required and zero impact on 120 FPS performance.
- **Instant Pairing:** Tap the **2-Player** button in the Chaos Emerald bar to reveal the **Pairing** pill. Tapping it displays a native **QR Code** (\`CoreImage\`) and automatically copies the local link to your clipboard (with background keep-alive so you can paste it in Messages/WhatsApp without dropping the server).
- **Android & iPhone Web Controller:** Smartphone 2 opens the local link in any mobile browser to get a full-screen, oversized, blind-playable virtual controller styled to match the native iOS gamepad, complete with vibration feedback and live connection status.
- **Smart Auto-Hide Status Pill:** Once Player 2 connects, the pill switches to **Connected** and automatically fades away after 3.5 seconds to keep the screen clean, reappearing with an alert only if Player 2 disconnects.
- **Native Player 2 Injection:** Works in both **2P Battle Mode** and story stages where Player 2 controls Sonic and friends.

### 4. Dedicated Dual-Screen TV Mode (AirPlay & HDMI)
- **Automatic External Display Detection:** The **TV** button next to the 2-Player icon activates automatically whenever your iPhone or iPad is connected via **AirPlay** or **HDMI**.
- **Clean Full-Screen Game on TV, Dedicated Gamepad on iPhone:**
  - The **TV** displays **only** the pure full-screen Metal game surface — **zero virtual buttons or HUD overlays appear on the TV** (overscan compensation disabled, smart 1080p cap to prevent Jetsam OOM on 4K TVs).
  - Your **iPhone** transforms into a sleek dark gamepad with **oversized blind-playable controls**, full CoreHaptics feedback, and simultaneous 2-Player Multiplayer support.
- **Freeze-Free Lock Screen & App-Switch Recovery:** Locking your iPhone or switching apps during TV Mode cleanly parks Metal and detaches the external window, then rebuilds a fresh TV window and MoltenVK swapchain automatically upon return (or seamlessly returns the game to your iPhone if AirPlay/HDMI was disconnected).

### 5. Automatic System Language Detection (6 Languages)
- Automatically detects your device's language at launch (\`[NSLocale preferredLanguages]\`) with zero mixed-language labels across the HUD, Quick-Bar, 2P pairing card, TV Mode notifications, native iOS Files picker, and installer credits (*"iOS port developed by hiperema"*).
- Smartphone 2's web controller independently adapts to its own browser language (\`navigator.language\`).
- **Supported Languages:** English (universal fallback), Italian, Spanish, French, German, and Japanese.

### 6. Built-In Crashlog & 10-Second Diagnostic Recorder (\`crashlog.txt\`)
- **Automatic Crash & Memory-Warning Capture:** Intercepts native iOS crashes (\`SIGSEGV\`, \`SIGBUS\`, \`SIGABRT\`, \`SIGILL\`, \`SIGFPE\`, \`SIGTRAP\`, \`NSException\`, \`std::terminate\`) and low-memory warnings with zero impact on 120 FPS gameplay, automatically writing timestamps, ARM64 stack traces, RAM usage, and recent engine/SDL3 logs to **\`On My iPhone → ${config.appName} → ShadowRecomp/crashlog.txt\`**.
- **On-Demand 10s \`LOG\` Button:** Tap **\`LOG\`** (right next to the 2-Player button in the Chaos Emerald bar) whenever you spot a glitch, stutter, or bug to record 10 seconds of live FPS, RAM, thermal state, and engine/SDL3 events directly into \`crashlog.txt\` — ready to attach to a GitHub Issue!

### 7. Native iOS Files Integration, Mod Manager & Custom App Icon
- **Full-Screen iOS Files Picker:** Native \`UIDocumentPickerViewController\` bridge (\`asCopy\`) plus automatic scanning of local files placed in *On My iPhone → ${config.appName}*.
- **Built-In iOS Mod Manager:** Native UIKit interface compatible with ShadowRecomp's \`ModLoader::Init()\` (\`mods/.modloader/profiles/Default.json\`).
- **Compiled App Icon (\`Assets.car\`):** Opaque iPhone and iPad icons compiled via \`actool\` for sharp display on SpringBoard (Feather) and inside LiveContainer.

---

## Compatible Devices

Minimum OS Requirement: **iOS ${config.deploymentTarget}+ / iPadOS ${config.deploymentTarget}+** · **arm64** (Apple Silicon / A-series).

### Compatible iPhones

| Tier | iPhone Models | Chip | RAM | Expected Experience |
| :--- | :--- | :--- | :---: | :--- |
| **Optimal (120Hz ProMotion)** | **iPhone 17 / 17 Air / 17 Pro / 17 Pro Max**<br>**iPhone 16 Pro / 16 Pro Max**<br>**iPhone 15 Pro / 15 Pro Max** | A19 / A19 Pro<br>A18 Pro<br>A17 Pro | 8–12 GB | Native **120 FPS**, full display resolution, smooth TV Mode & 2P Multiplayer, ample RAM headroom |
| **Excellent (60Hz–120Hz)** | **iPhone 16 / 16 Plus / 16e**<br>**iPhone 15 / 15 Plus**<br>**iPhone 14 Pro / 14 Pro Max**<br>**iPhone 13 Pro / 13 Pro Max** | A18<br>A16 Bionic<br>A16 Bionic<br>A15 Bionic | 6–8 GB | **60–120 FPS** (120Hz on Pro models), high stability with \`increased-memory-limit\` |
| **Good (60Hz)** | **iPhone 14 / 14 Plus**<br>**iPhone 13 / 13 mini**<br>**iPhone 12 Pro / 12 Pro Max**<br>**iPhone SE (3rd gen)** | A15 Bionic<br>A15 Bionic<br>A14 Bionic<br>A15 Bionic | 4–6 GB | Smooth **60 FPS** (closing background apps is recommended on 4 GB models) |
| **Basic Support (60Hz)** | **iPhone 12 / 12 mini**<br>**iPhone 11 / 11 Pro / 11 Pro Max**<br>**iPhone XS / XS Max / XR**<br>**iPhone SE (2nd gen)** | A14 Bionic<br>A13 Bionic<br>A12 Bionic<br>A13 Bionic | 3–4 GB | Boots on iOS 17+; 3 GB devices (XR / SE 2nd gen) may hit iOS Jetsam limits in heavy stages |

### Compatible iPads

| Tier | iPad Models | Chip | RAM | Expected Experience |
| :--- | :--- | :--- | :---: | :--- |
| **Optimal (120Hz ProMotion)** | **iPad Pro 11" / 13" (M4)**<br>**iPad Pro 11" / 12.9" (M2 / M1)**<br>**iPad Pro (2018 / 2020)** | M4 / M2 / M1<br>A12X / A12Z | 4–16 GB | **120 FPS** on ProMotion displays, plug-and-play USB-C HDMI TV Mode |
| **Excellent (60Hz)** | **iPad Air 11" / 13" (M3 / M2 / M1)**<br>**iPad mini (A17 Pro / 6th gen)**<br>**iPad Air (4th gen)** | M3 / M2 / M1<br>A17 Pro / A15<br>A14 | 4–8 GB | Rock-solid **60 FPS**, spacious screen ideal for physical controllers or touch |
| **Basic Support (60Hz)** | **iPad (11th gen A16 / 10th gen A14 / 9th gen A13)**<br>**iPad Air (3rd gen)** · **iPad mini (5th gen)** | A16 / A14 / A13 / A12 | 3–6 GB | Supported on iPadOS 17+; avoid heavy texture mods on 3 GB RAM models |

> **RAM & Sideloading Note:** Devices with **6 GB RAM or higher** deliver the best experience. Signing with a certificate that preserves \`com.apple.developer.kernel.increased-memory-limit\` (or running inside LiveContainer) gives MoltenVK and game assets significantly more memory headroom.

---

## How It Was Developed

**EdgyiOS** was developed by **hiperema** using **Google AI Studio** to architect the native iOS compatibility layer, automate upstream C++/Objective-C++/CMake patching, engineer the custom virtual gamepad / 2P server / TV Mode subsystems, and maintain the zero-Mac GitHub Actions CI pipeline and automated test suite.

### Technical Architecture (Zero-Mac Cloud Pipeline)
\`\`\`text
[GitHub Actions macOS-15 Host Runner]
  ├── XboxRecomp2 (Rust)  ──► Static recompilation: Original Xbox x86 -> Native arm64 C++
  ├── XShaderRecomp + DXC ──► Shader translation: Xbox shaders -> SPIR-V
  └── file_to_c           ──► Embedded ShadowRecomp UI & font resources
                │
                ▼
[iOS arm64 Cross-Compilation (CMake + Ninja + Xcode iOS SDK)]
  ├── ShadowRecomp + Plume (Vulkan) ──► MoltenVK (libMoltenVK.a) ──► Apple Metal 3
  ├── SDL3 Static (AirPlay-safe UIKit + CoreAudio + GameController)
  ├── EdgyiOS Native Layer (com.hiperema.edgyios.ios):
  │     ├── ios_virtual_controller.mm (CoreGraphics + CoreHaptics + TV Mode + 6 Languages)
  │     ├── ios_p2_server.mm          (Network.framework HTTP/WS + Cross-Platform 2P Webpad)
  │     ├── nfd_ios.mm                (Full-Screen UIDocumentPicker iOS Files Bridge)
  │     ├── ios_mod_manager.mm        (UIKit ModLoader profiles.json Manager)
  │     └── ios_platform.mm           (os::logger/process/media + Safe Metal GPU Lifecycle)
  └── ldid Entitlements + Assets.car ──► ${config.appName}-iOS.ipa (Unsigned, Zero Game Assets)
\`\`\`

---

## GitHub Resources & Credits

**EdgyiOS** stands on the shoulders of the open-source community. Full credit to every upstream project and resource used:

| Project / Resource | Role in EdgyiOS | License / Reference |
| :--- | :--- | :--- |
| **[FoxWorkshop/ShadowRecomp](${cleanUpstream})** | Upstream static recompilation project for *Shadow the Hedgehog* (including \`XboxRecomp2\`, \`XShaderRecomp\`, and \`Plume\`) | Upstream Open-Source |
| **[DevZer0D4Y/MarathonRecompilediOS](${config.iosRefRepoUrl})** | Architectural inspiration for Zero-Asset iOS cloud builds, iOS Files workflow, and Mod Manager | Upstream Open-Source |
| **[KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK)** | Vulkan / SPIR-V → Apple Metal 3 runtime for iOS arm64 | Apache-2.0 |
| **[libsdl-org/SDL](https://github.com/libsdl-org/SDL)** | SDL3 UIKit backend (windowing, CoreAudio, GameController) | zlib License |
| **[FreeType](https://freetype.org/)** | Static iOS arm64 font rasterizer required by \`msdf-atlas-gen\` | FreeType License / GPL |
| **[ocornut/imgui](https://github.com/ocornut/imgui)** | Installer wizard and in-game overlay UI framework | MIT License |
| **[ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid)** | Ad-hoc entitlement signing (\`increased-memory-limit\`, \`extended-virtual-addressing\`) in CI | BSD-style Open-Source |
| **[khcrysalis/Feather](https://github.com/khcrysalis/Feather)** | Tested & supported standalone iOS sideloader | Open-Source |
| **[LiveContainer/LiveContainer](https://github.com/LiveContainer/LiveContainer)** | Tested & supported containerized iOS runner (\`-fPIC -Wl,-pie\`) | Apache-2.0 |
| **Google AI Studio** | Co-development environment used by **hiperema** to build, iterate, and verify the iOS port | Development Tool |

---

## Cloud Build (No Mac Required)

You do not need a Mac to build **EdgyiOS**. Everything compiles on **GitHub Actions (\`macos-15\`)** without ever committing game files to Git (\`.gitignore\` automatically blocks \`*.xbe\`, \`*.iso\`, \`*.xiso\`, \`*.afs\`, \`*.one\`, \`*.txd\`, and \`private/\`).

1. Fork or clone this repository on GitHub.
2. Open **Settings → Secrets and variables → Actions → New repository secret**.
3. Create an encrypted secret named **\`DEFAULT_XBE_URL\`** pointing to a temporary/private direct download link of the \`default.xbe\` extracted from **your own legal copy** of the game (~4.8 MB).
   - The file is downloaded solely inside the ephemeral \`macos-15\` runner during \`XboxRecomp2\` code generation and destroyed immediately after the build finishes.
4. Go to **Actions → Build EdgyiOS Unsigned IPA → Run workflow**.
   - Select \`Release\` (recommended).
   - *(Optional)* Enable **\`publish_release\`** to automatically create a GitHub Release with \`${config.appName}-iOS.ipa\` and \`SHA256SUMS-${config.appName}.txt\`.
5. Download the generated \`.ipa\` artifact directly onto your iPhone or iPad.

---

## Installation on iPhone & iPad

### Option A — Feather (Standalone)
1. Import \`${config.appName}-iOS.ipa\` into **Feather**, sign with your certificate, and install.
2. Launch **${config.appName}**: the installer wizard opens the native **iOS Files** picker so you can select your extracted game folder or \`.iso\` / \`.xiso\` *(or pre-copy it into On My iPhone → ${config.appName})*.
3. Once installation completes, restart the app and enjoy!

### Option B — LiveContainer
1. Import \`${config.appName}-iOS.ipa\` into **LiveContainer** (the binary is pre-compiled with \`-fPIC -Wl,-pie\` for full compatibility).
2. Launch **${config.appName}**, pick your legally dumped game files via iOS Files, and restart once installation finishes.

---

## Legal & Copyright Notice

- **Zero copyrighted assets** are included in this repository, its source code, or any compiled \`.ipa\`.
- **EdgyiOS** is an independent, non-commercial, fan-made port and is **not affiliated with, endorsed by, or sponsored by** **SEGA CORPORATION**, **Sonic Team**, **Microsoft Corporation**, or **Apple Inc.**
- All trademarks (*Shadow the Hedgehog*, *SEGA*, *Xbox*, *iPhone*, *iPad*, *iOS*, *AirPlay*, *Metal*) are the property of their respective owners.
- Using this project requires owning a legitimate original copy of *Shadow the Hedgehog (2005)* for Xbox. Requests for or links to ROMs, ISOs, or \`.xbe\` files are strictly prohibited.

Please read **[LEGAL.md](LEGAL.md)** for the complete legal notice, AI development disclosure, third-party licenses, and takedown policy.

---

<div align="center">
  <sub>iOS Port developed by <strong>hiperema</strong> · Co-developed with <strong>Google AI Studio</strong> · Built upon <strong>FoxWorkshop/ShadowRecomp</strong></sub>
</div>
`;
}

export function generateEdgyIosLegalMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `# Legal Notice, Licensing & Disclaimers — EdgyiOS

**Project:** EdgyiOS: Shadow The Hedgehog Recompiled for iOS  
**iOS Port Maintainer:** hiperema  
**Bundle Identifier:** \`com.hiperema.edgyios.ios\`  
**Version:** v${config.appVersion}  

---

## 1. Zero Copyrighted Assets Policy

This GitHub repository and any \`.ipa\` package produced by its CI workflow **do not contain any copyrighted game data** from *Shadow the Hedgehog (2005)* or any commercial third party. Specifically, the following materials are **never included and never distributed**:

- Original Xbox executables (\`default.xbe\`);
- Disc images (\`*.iso\`, \`*.xiso\`);
- Game archives, textures, 3D models, level geometry, voice lines, music, or video cutscenes (\`*.afs\`, \`*.one\`, \`*.txd\`, \`*.adx\`, \`*.sfd\`, etc.).

The repository \`.gitignore\` explicitly blocks these file extensions to prevent accidental commits. The compiled application contains only the native recompilation runtime and iOS compatibility modules, and cannot run the game without user-supplied files from an original copy.

---

## 2. Legal Ownership, Interoperability & Anti-Piracy

- Building and running **EdgyiOS** requires owning a **legitimate, legally purchased physical or digital copy** of *Shadow the Hedgehog (2005)* for the original Xbox.
- Extracting files from your own lawfully owned copy for personal backup, preservation, and cross-platform interoperability is intended strictly for personal non-commercial use in accordance with applicable copyright interoperability and backup provisions (such as EU Directive 2009/24/EC and equivalent local laws; users are responsible for complying with the laws of their jurisdiction).
- **Zero tolerance for piracy:** Any issue, discussion, comment, or pull request requesting or linking to copyrighted ROMs, ISOs, XISOs, \`.xbe\` binaries, or extracted game assets will be deleted immediately.

---

## 3. Trademarks & Non-Affiliation Disclaimer

**EdgyiOS** is an independent, free, non-commercial open-source porting project. It is **not affiliated with, endorsed by, authorized by, or associated with** any of the following trademark holders:

- *Shadow the Hedgehog*, *Sonic the Hedgehog*, *SEGA*, and *Sonic Team* are registered trademarks of **SEGA CORPORATION**.
- *Xbox* and *DirectX* are registered trademarks of **Microsoft Corporation**.
- *Apple*, *iPhone*, *iPad*, *iOS*, *iPadOS*, *AirPlay*, *Metal*, and *ProMotion* are registered trademarks of **Apple Inc.**
- *Vulkan* is a registered trademark of **The Khronos Group Inc.**

All product names, logos, and trademarks are referenced strictly for identification and technical compatibility.

---

## 4. Upstream Attribution & Bundle Identifier Separation

- **EdgyiOS** is an unofficial community iOS port maintained by **hiperema** and built on top of [FoxWorkshop/ShadowRecomp](${cleanUpstream}).
- To avoid any confusion or impersonation with the upstream authors, **EdgyiOS** uses its own distinct application name (\`${config.appName}\`) and reverse-DNS bundle identifier (\`com.hiperema.edgyios.ios\`), while preserving full attribution to **FoxWorkshop** across documentation, CI build scripts, and in-app installer credits.
- Please do **not** report iOS-specific bugs from **EdgyiOS** to the upstream FoxWorkshop/ShadowRecomp issue tracker unless reproduced on upstream desktop builds.

---

## 5. AI-Assisted Development Disclosure (Google AI Studio)

The iOS porting layer of **EdgyiOS** — including the CoreGraphics/CoreHaptics virtual controller, local \`Network.framework\` 2-Player server and web gamepad, Dual-Screen AirPlay/HDMI TV Mode, automatic 6-language localization, iOS Files picker bridge, and GitHub Actions zero-Mac build workflow — was designed, iterated, and verified by **hiperema** with the assistance of **Google AI Studio**.

All architectural decisions, physical iOS device testing (Feather and LiveContainer), debugging, and repository releases are reviewed and maintained by **hiperema**.

---

## 6. Open-Source Licensing & Third-Party Components

The original iOS porting layer in this repository (\`ios/\`, \`cmake/\`, \`scripts/\`, \`.github/\`, and generator tooling) is provided as open-source software aligned with the GNU General Public License v3.0 (GPL-3.0, official text available at [gnu.org/licenses/gpl-3.0](https://www.gnu.org/licenses/gpl-3.0.html)) in harmony with the upstream **ShadowRecomp** ecosystem.

All external open-source components fetched or linked during compilation remain governed by their own respective licenses and copyrights:

| Component | Source Repository | License |
| :--- | :--- | :--- |
| **ShadowRecomp** (\`XboxRecomp2\`, \`XShaderRecomp\`, \`Plume\`) | [FoxWorkshop/ShadowRecomp](${cleanUpstream}) | Upstream Repository License |
| **MarathonRecompilediOS** (architectural reference) | [DevZer0D4Y/MarathonRecompilediOS](${config.iosRefRepoUrl}) | Upstream Repository License |
| **MoltenVK** | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache License 2.0 |
| **SDL3** | [libsdl-org/SDL](https://github.com/libsdl-org/SDL) | zlib License |
| **FreeType** | [freetype.org](https://freetype.org/) | FreeType License (FTL) / GPL |
| **Dear ImGui** | [ocornut/imgui](https://github.com/ocornut/imgui) | MIT License |
| **ldid** | [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid) | BSD-style Open-Source License |

---

## 7. Disclaimer of Warranty & Limitation of Liability

This software is provided **"AS IS"**, without warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, or non-infringement. Under no circumstances shall the maintainer or contributors be liable for any direct, indirect, incidental, special, or consequential damages arising from the use of this software or third-party sideloading tools.

---

## 8. Copyright & Takedown Requests (Notice & Takedown)

If you are a rights holder and believe any material in this repository inadvertently infringes your intellectual property rights, please open a detailed notice on this GitHub repository. Any verified concern will be reviewed and addressed promptly.
`;
}

export function generateEdgyIosReleaseNotesMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `# EdgyiOS v${config.appVersion} — Shadow The Hedgehog Recompiled for iOS

Global release **v${config.appVersion}** of **EdgyiOS**, the native iOS & iPadOS port of [FoxWorkshop/ShadowRecomp](${cleanUpstream}), developed by **hiperema** with **Google AI Studio**.

> **Zero Game Assets Included:** \`${config.appName}-iOS.ipa\` contains only the native arm64 recompiled runtime and iOS subsystems. On first launch, import the files extracted from **your own legally owned Xbox copy** of *Shadow the Hedgehog (2005)* via the iOS Files app.

---

## What's New in v${config.appVersion}
- **Built-In \`crashlog.txt\` Automatic Crash & Memory-Warning Capture:** Automatically intercepts native ARM64 fatal signals (\`SIGSEGV\`, \`SIGBUS\`, \`SIGABRT\`, \`SIGILL\`, \`SIGFPE\`, \`SIGTRAP\`), uncaught \`NSException\` / \`std::terminate\` crashes, and iOS low-memory warnings (Jetsam risk) with zero impact on 120 FPS gameplay, writing timestamps, stack traces, RAM usage, and recent engine/SDL3 logs to **\`On My iPhone → ${config.appName} → ShadowRecomp/crashlog.txt\`**.
- **On-Demand 10-Second \`LOG\` Diagnostic Button:** Added a dedicated **\`LOG\`** button right after the 2-Player button in the Chaos Emerald Quick-HUD bar. Tap it whenever you encounter a bug or slowdown to capture 10 seconds of live FPS, RAM, thermal state, and engine/SDL3 telemetry directly into \`ShadowRecomp/crashlog.txt\` (localized across all 6 languages) — ready to attach to a GitHub Issue.
- **Cleaner TV Mode Quick-HUD Bar:** Removed the redundant **Opacity (\`TV 100%\`)** and **Auto-Hide (\`4s\`)** buttons when Dual-Screen TV Mode is active, keeping a compact centered bar (**Haptics · TV · 2P · LOG**) with zero overlap on the enlarged gamepad controls.

---

## Full Feature Highlights in v${config.appVersion}

### Native Engine, Full-Screen Resolution & 120Hz ProMotion
- **Native arm64 + Metal 3 (MoltenVK)** execution with **zero JIT**, **120Hz ProMotion** support, and full compatibility with both **Feather** (standalone) and **LiveContainer** (\`-fPIC -Wl,-pie\`).
- **True native full-screen resolution** on iPhone & iPad via \`UILaunchScreen\` (e.g., \`2622×1206\` on iPhone 16 Pro, eliminating stretched 1440×960 Feather scaling).
- **Safe Metal GPU lifecycle**: synchronous GPU drain on lock-screen/background and automatic Vulkan swapchain recovery on foreground resume.
- **Dedicated identity & custom icon**: App Name **\`${config.appName}\`**, Bundle ID **\`com.hiperema.edgyios.ios\`**, compiled \`Assets.car\` icon, and localized installer credits (*"iOS port developed by hiperema"*).

### Shadow-Themed Xbox Virtual Controller & CoreHaptics
- **Vector CoreGraphics / QuartzCore overlay** with 3D-tilt & pressure-sensitive Shadow Emblem left stick, sliding 8-way D-Pad, ABXY, analog \`LT/RT\`, \`LB/RB\`, \`L3/R3\`, \`Start/Back\`, and the **Chaos Emerald Quick-HUD** (dynamic Hero/Neutral/Dark aura).
- **Taptic Engine CoreHaptics**: crisp mechanical button clicks, analog stick detents, and native in-game rumble.
- **4-second auto-hide** with instant touch wake, saved opacity settings, and automatic hiding whenever a physical Bluetooth/USB-C controller is connected.

### Cross-Platform 2-Player Multiplayer (Hotspot / Local Wi-Fi)
- **Built-in local HTTP + WebSocket server** (\`Network.framework\`, port \`8765\`, zero internet required, zero impact on 120 FPS).
- **Native QR Code + auto-copied link** with a smart **Pairing → Connected** status pill that auto-hides after 3.5 seconds and alerts only on disconnect.
- **Oversized blind-playable web controller** compatible with any **Android** or **iPhone** browser.

### Dedicated Dual-Screen TV Mode (AirPlay & HDMI)
- **TV Mode button** in the Chaos Emerald bar activates automatically when connected to AirPlay or HDMI.
- **Zero virtual buttons on TV**: displays only the clean full-screen game on your TV (overscan disabled, 1080p cap to prevent 4K Jetsam OOM), while your iPhone becomes an oversized dark blind-playable controller with full haptics and 2P support.
- **Freeze-free background & lock-screen recovery**: cleanly detaches the external window in background and automatically rebuilds the TV window and MoltenVK swapchain upon returning.

### Automatic 6-Language System Localization & Built-In \`crashlog.txt\` Diagnostics
- Automatically detects your device language at launch across **English, Italian, Spanish, French, German, and Japanese** for all native UI overlays, the iOS Files picker, and Smartphone 2's web controller.
- **Automatic & On-Demand \`crashlog.txt\`**: automatically logs native crashes and iOS memory warnings, plus includes a **\`LOG\`** button in the Chaos Emerald bar to capture 10 seconds of live FPS/RAM/thermal/engine diagnostics directly into \`ShadowRecomp/crashlog.txt\` for easy GitHub bug reports.

---

## Compatible Devices (iOS / iPadOS ${config.deploymentTarget}+)
- **Optimal (120Hz ProMotion):** iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro (and Pro Max), iPad Pro M1 / M2 / M4.
- **Excellent (60Hz):** iPhone 13 / 14 / 15 / 16 / 16e / 17, iPhone 12 Pro, iPhone SE (3rd gen), iPad Air M1/M2/M3, iPad mini 6/7.
- **Basic Support (60Hz):** iPhone XS / XR / 11 / 12 / SE (2nd gen), iPad 9th/10th/11th gen *(closing background apps recommended on 3–4 GB RAM models)*.

---

## Quick Installation
1. Download **\`${config.appName}-iOS.ipa\`** (and optionally verify \`SHA256SUMS-${config.appName}.txt\`).
2. Install via **Feather** or import into **LiveContainer**.
3. On first launch, select the files extracted from your own legal Xbox copy via **iOS Files**, complete installation, and relaunch.

---

## Legal
No copyrighted game assets are included in this release. See [LEGAL.md](LEGAL.md) and [README.md](README.md) for full legal notices, upstream credits, and open-source licenses.
`;
}
