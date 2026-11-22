# Legal Notice, Licensing & Disclaimers — EdgyiOS

**Project:** EdgyiOS: Shadow The Hedgehog Recompiled for iOS  
**iOS Port Maintainer:** hiperema  
**Bundle Identifier:** `com.hiperema.edgyios.ios`  
**Version:** v1.0.1  

---

## 1. Zero Copyrighted Assets Policy

This GitHub repository and any `.ipa` package produced by its CI workflow **do not contain any copyrighted game data** from *Shadow the Hedgehog (2005)* or any commercial third party. Specifically, the following materials are **never included and never distributed**:

- Original Xbox executables (`default.xbe`);
- Disc images (`*.iso`, `*.xiso`);
- Game archives, textures, 3D models, level geometry, voice lines, music, or video cutscenes (`*.afs`, `*.one`, `*.txd`, `*.adx`, `*.sfd`, etc.).

The repository `.gitignore` explicitly blocks these file extensions to prevent accidental commits. The compiled application contains only the native recompilation runtime and iOS compatibility modules, and cannot run the game without user-supplied files from an original copy.

---

## 2. Legal Ownership, Interoperability & Anti-Piracy

- Building and running **EdgyiOS** requires owning a **legitimate, legally purchased physical or digital copy** of *Shadow the Hedgehog (2005)* for the original Xbox.
- Extracting files from your own lawfully owned copy for personal backup, preservation, and cross-platform interoperability is intended strictly for personal non-commercial use in accordance with applicable copyright interoperability and backup provisions (such as EU Directive 2009/24/EC and equivalent local laws; users are responsible for complying with the laws of their jurisdiction).
- **Zero tolerance for piracy:** Any issue, discussion, comment, or pull request requesting or linking to copyrighted ROMs, ISOs, XISOs, `.xbe` binaries, or extracted game assets will be deleted immediately.

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

- **EdgyiOS** is an unofficial community iOS port maintained by **hiperema** and built on top of [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp).
- To avoid any confusion or impersonation with the upstream authors, **EdgyiOS** uses its own distinct application name (`EdgyiOS`) and reverse-DNS bundle identifier (`com.hiperema.edgyios.ios`), while preserving full attribution to **FoxWorkshop** across documentation, CI build scripts, and in-app installer credits.
- Please do **not** report iOS-specific bugs from **EdgyiOS** to the upstream FoxWorkshop/ShadowRecomp issue tracker unless reproduced on upstream desktop builds.

---

## 5. AI-Assisted Development Disclosure (Google AI Studio)

The iOS porting layer of **EdgyiOS** — including the CoreGraphics/CoreHaptics virtual controller, local `Network.framework` 2-Player server and web gamepad, Dual-Screen AirPlay/HDMI TV Mode, automatic 6-language localization, iOS Files picker bridge, and GitHub Actions zero-Mac build workflow — was designed, iterated, and verified by **hiperema** with the assistance of **Google AI Studio**.

All architectural decisions, physical iOS device testing (Feather and LiveContainer), debugging, and repository releases are reviewed and maintained by **hiperema**.

---

## 6. Open-Source Licensing & Third-Party Components

The original iOS porting layer in this repository (`ios/`, `cmake/`, `scripts/`, `.github/`, and generator tooling) is provided as open-source software aligned with the GNU General Public License v3.0 (GPL-3.0, official text available at [gnu.org/licenses/gpl-3.0](https://www.gnu.org/licenses/gpl-3.0.html)) in harmony with the upstream **ShadowRecomp** ecosystem.

All external open-source components fetched or linked during compilation remain governed by their own respective licenses and copyrights:

| Component | Source Repository | License |
| :--- | :--- | :--- |
| **ShadowRecomp** (`XboxRecomp2`, `XShaderRecomp`, `Plume`) | [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp) | Upstream Repository License |
| **MarathonRecompilediOS** (architectural reference) | [DevZer0D4Y/MarathonRecompilediOS](https://github.com/DevZer0D4Y/MarathonRecompilediOS) | Upstream Repository License |
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
