# EdgyiOS v1.0.0 — Shadow The Hedgehog Recompiled for iOS

Initial global release of **EdgyiOS**, the native iOS & iPadOS port of [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp), developed by **hiperema** with **Google AI Studio**.

> **Zero Game Assets Included:** `EdgyiOS-iOS.ipa` contains only the native arm64 recompiled runtime and iOS subsystems. On first launch, import the files extracted from **your own legally owned Xbox copy** of *Shadow the Hedgehog (2005)* via the iOS Files app.

---

## Highlights in v1.0.0

### Native Engine, Full-Screen Resolution & 120Hz ProMotion
- **Native arm64 + Metal 3 (MoltenVK)** execution with **zero JIT**, **120Hz ProMotion** support, and full compatibility with both **Feather** (standalone) and **LiveContainer** (`-fPIC -Wl,-pie`).
- **True native full-screen resolution** on iPhone & iPad via `UILaunchScreen` (e.g., `2622×1206` on iPhone 16 Pro, eliminating stretched 1440×960 Feather scaling).
- **Safe Metal GPU lifecycle**: synchronous GPU drain on lock-screen/background and automatic Vulkan swapchain recovery on foreground resume.
- **Dedicated identity & custom icon**: App Name **`EdgyiOS`**, Bundle ID **`com.hiperema.edgyios.ios`**, compiled `Assets.car` icon, and localized installer credits (*"iOS port developed by hiperema"*).

### Shadow-Themed Xbox Virtual Controller & CoreHaptics
- **Vector CoreGraphics / QuartzCore overlay** with 3D-tilt & pressure-sensitive Shadow Emblem left stick, sliding 8-way D-Pad, ABXY, analog `LT/RT`, `LB/RB`, `L3/R3`, `Start/Back`, and the **Chaos Emerald Quick-HUD** (dynamic Hero/Neutral/Dark aura).
- **Taptic Engine CoreHaptics**: crisp mechanical button clicks, analog stick detents, and native in-game rumble.
- **4-second auto-hide** with instant touch wake, saved opacity settings, and automatic hiding whenever a physical Bluetooth/USB-C controller is connected.

### Cross-Platform 2-Player Multiplayer (Hotspot / Local Wi-Fi)
- **Built-in local HTTP + WebSocket server** (`Network.framework`, port `8765`, zero internet required, zero impact on 120 FPS).
- **Native QR Code + auto-copied link** with a smart **Pairing → Connected** status pill that auto-hides after 3.5 seconds and alerts only on disconnect.
- **Oversized blind-playable web controller** compatible with any **Android** or **iPhone** browser.

### Dedicated Dual-Screen TV Mode (AirPlay & HDMI)
- **TV Mode button** in the Chaos Emerald bar activates automatically when connected to AirPlay or HDMI.
- **Zero virtual buttons on TV**: displays only the clean full-screen game on your TV (overscan disabled, 1080p cap to prevent 4K Jetsam OOM), while your iPhone becomes an oversized dark blind-playable controller with full haptics and 2P support.
- **Freeze-free background & lock-screen recovery**: cleanly detaches the external window in background and automatically rebuilds the TV window and MoltenVK swapchain upon returning.

### Automatic 6-Language System Localization & Built-In `crashlog.txt` Diagnostics
- Automatically detects your device language at launch across **English, Italian, Spanish, French, German, and Japanese** for all native UI overlays, the iOS Files picker, and Smartphone 2's web controller.
- **Automatic & On-Demand `crashlog.txt`**: automatically logs native crashes and iOS memory warnings, plus includes a **`LOG`** button in the Chaos Emerald bar to capture 10 seconds of live FPS/RAM/thermal/engine diagnostics directly into `ShadowRecomp/crashlog.txt` for easy GitHub bug reports.

---

## Compatible Devices (iOS / iPadOS 17.0+)
- **Optimal (120Hz ProMotion):** iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro (and Pro Max), iPad Pro M1 / M2 / M4.
- **Excellent (60Hz):** iPhone 13 / 14 / 15 / 16 / 16e / 17, iPhone 12 Pro, iPhone SE (3rd gen), iPad Air M1/M2/M3, iPad mini 6/7.
- **Basic Support (60Hz):** iPhone XS / XR / 11 / 12 / SE (2nd gen), iPad 9th/10th/11th gen *(closing background apps recommended on 3–4 GB RAM models)*.

---

## Quick Installation
1. Download **`EdgyiOS-iOS.ipa`** (and optionally verify `SHA256SUMS-EdgyiOS.txt`).
2. Install via **Feather** or import into **LiveContainer**.
3. On first launch, select the files extracted from your own legal Xbox copy via **iOS Files**, complete installation, and relaunch.

---

## Legal
No copyrighted game assets are included in this release. See [LEGAL.md](LEGAL.md) and [README.md](README.md) for full legal notices, upstream credits, and open-source licenses.
