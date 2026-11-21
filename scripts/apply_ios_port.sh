#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_DIR="$1"
PORT_DIR="$2"
DEPS_DIR="$3"

echo "==> [1/7] Creazione stub VCPKG_ROOT per cross-compilazione iOS..."
mkdir -p "${DEPS_DIR}/vcpkg-ios-stub/scripts/buildsystems"
cat << 'EOF_VCPKG' > "${DEPS_DIR}/vcpkg-ios-stub/scripts/buildsystems/vcpkg.cmake"
# Stub vcpkg.cmake per cross-compilazione iOS arm64 su GitHub Actions
message(STATUS "ShadowRecomp iOS: uso toolchain iOS nativa invece di vcpkg desktop.")
EOF_VCPKG

echo "==> [2/7] Copia layer iOS (OS, App File NFD, Mod Manager, CURL stub, Info.plist)..."
mkdir -p "${UPSTREAM_DIR}/ShadowRecomp/os/ios"
mkdir -p "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/curl"
cp "${PORT_DIR}/ios/os/ios_platform.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_platform.mm"
cp "${PORT_DIR}/ios/os/registry_ios.inl" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/registry_ios.inl"
cp "${PORT_DIR}/ios/nfd_ios.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/nfd_ios.mm"
cp "${PORT_DIR}/ios/include/nfd.h" "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/nfd.h"
cp "${PORT_DIR}/ios/ios_mod_manager.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_mod_manager.mm"
cp "${PORT_DIR}/ios/curl_ios_stub.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/curl_ios_stub.mm"
cp "${PORT_DIR}/ios/include/curl/curl.h" "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/curl/curl.h"
cp "${PORT_DIR}/ios/ios_virtual_controller.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_virtual_controller.mm"
cp "${PORT_DIR}/ios/include/ios_virtual_controller.h" "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/ios_virtual_controller.h"
cp "${PORT_DIR}/ios/ios_p2_server.mm" "${UPSTREAM_DIR}/ShadowRecomp/os/ios/ios_p2_server.mm"
cp "${PORT_DIR}/ios/include/ios_p2_server.h" "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/ios_p2_server.h"
cat << 'EOF_NFD_HPP' > "${UPSTREAM_DIR}/ShadowRecomp/ios_compat/include/nfd.hpp"
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
mkdir -p "${UPSTREAM_DIR}/ios" "${UPSTREAM_DIR}/cmake"
cp "${PORT_DIR}/ios/Info.plist" "${UPSTREAM_DIR}/ios/Info.plist"
cp "${PORT_DIR}/ios/Entitlements.plist" "${UPSTREAM_DIR}/ios/Entitlements.plist"
cp "${PORT_DIR}/cmake/ShadowRecompIOS.cmake" "${UPSTREAM_DIR}/cmake/ShadowRecompIOS.cmake"

echo "==> [3/7] Patch ShadowRecomp/user/paths.cpp, paths.h, stdafx.h, guest_thread.cpp, update_checker.cpp e main.cpp per iOS arm64..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/user/paths.cpp" "${UPSTREAM_DIR}/ShadowRecomp/user/paths.h" "${UPSTREAM_DIR}/ShadowRecomp/stdafx.h" "${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.cpp" "${UPSTREAM_DIR}/ShadowRecomp/install/update_checker.cpp" "${UPSTREAM_DIR}/ShadowRecomp/main.cpp" << 'PY_PATHS'
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
        "static std::filesystem::path s_userPath = BuildUserPath();\n    return s_userPath;"
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
        "#elif defined(__linux__) || defined(__APPLE__)\n#include <strings.h>",
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
        "#if defined(__x86_64__) || defined(__i386__)\n#include <x86intrin.h>\n#endif",
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
        '#include "stdafx.h"\n#if defined(SHADOW_IOS_PORT)\n#include <SDL3/SDL_main.h>\n#endif',
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

echo "==> [4/7] Patch ShadowRecomp/os/registry.h, ShadowRecomp/ui/game_window.cpp e ShadowRecomp/ui/installer_wizard.cpp..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/os/registry.h" "${UPSTREAM_DIR}/ShadowRecomp/ui/game_window.cpp" "${UPSTREAM_DIR}/ShadowRecomp/ui/installer_wizard.cpp" << 'PY_REG_WIN'
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
        reg_src = reg_src.replace("#endif", new_apple + "\n#endif", 1)
    reg_p.write_text(reg_src, encoding="utf-8")
    print("Patched registry.h")

win_p = pathlib.Path(sys.argv[2])
win_src = win_p.read_text(encoding="utf-8")
win_changed = False
if "defined(__APPLE__)" not in win_src:
    win_src = win_src.replace(
        "#elif defined(PLUME_SDL_VULKAN_ENABLED)",
        "#elif defined(PLUME_SDL_VULKAN_ENABLED) || defined(__APPLE__)"
    )
    win_changed = True
if "ShadowIOS_VideoOnWillEnterBackground" not in win_src:
    old_focus = """    case SDL_EVENT_WINDOW_FOCUS_LOST:
        GameWindow::s_isFocused = false;
        SDL_ShowCursor();
        break;"""
    new_focus = """#if defined(SHADOW_IOS_PORT)
    case SDL_EVENT_WILL_ENTER_BACKGROUND:
    case SDL_EVENT_DID_ENTER_BACKGROUND:
        ShadowIOS_VideoOnWillEnterBackground();
        break;
    case SDL_EVENT_DID_ENTER_FOREGROUND:
        ShadowIOS_VideoOnDidEnterForeground();
        break;
#endif
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        GameWindow::s_isFocused = false;
        SDL_ShowCursor();
        break;"""
    old_inc = '#include "game_window.h"'
    new_inc = '''#include "game_window.h"
#if defined(SHADOW_IOS_PORT)
extern "C" void ShadowIOS_VideoOnWillEnterBackground();
extern "C" void ShadowIOS_VideoOnDidEnterForeground();
#endif'''
    if old_inc in win_src and old_focus in win_src:
        win_src = win_src.replace(old_inc, new_inc, 1).replace(old_focus, new_focus, 1)
        win_changed = True

if "SHADOW_IOS_TOUCH_COORDS_FIX" not in win_src:
    old_drain = """    for (auto& event : eventsToProcess)
    {
        ImGui_ImplSDL3_ProcessEvent(&event);
    }"""
    new_drain = """    /* SHADOW_IOS_TOUCH_COORDS_FIX */
    for (auto& event : eventsToProcess)
    {
#if defined(SHADOW_IOS_PORT)
        if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN || event.type == SDL_EVENT_MOUSE_BUTTON_UP)
        {
            ImGui::GetIO().AddMousePosEvent(event.button.x, event.button.y);
        }
#endif
        ImGui_ImplSDL3_ProcessEvent(&event);
    }"""
    old_dup = """    if (ImGui::GetIO().BackendPlatformUserData != nullptr)
        ImGui_ImplSDL3_ProcessEvent(event);"""
    new_dup = """#if !defined(SHADOW_IOS_PORT)
    if (ImGui::GetIO().BackendPlatformUserData != nullptr)
        ImGui_ImplSDL3_ProcessEvent(event);
#endif"""
    old_show = "    SDL_ShowWindow(s_pWindow);"
    new_show = """    SDL_ShowWindow(s_pWindow);
#if defined(SHADOW_IOS_PORT)
    SDL_GetWindowSize(s_pWindow, &s_width, &s_height);
#endif"""
    if old_drain not in win_src or old_dup not in win_src or old_show not in win_src:
        raise RuntimeError("Failed to locate DrainImGuiEvents/Window_OnSDLEvent/SDL_ShowWindow in ui/game_window.cpp!")
    win_src = win_src.replace(old_drain, new_drain, 1).replace(old_dup, new_dup, 1).replace(old_show, new_show, 1)
    win_changed = True

if win_changed:
    win_p.write_text(win_src, encoding="utf-8")
    print("Patched game_window.cpp (iOS Vulkan surface + background/foreground lifecycle + ImGui touch coords)")

wiz_p = pathlib.Path(sys.argv[3])
if wiz_p.exists():
    wiz_src = wiz_p.read_text(encoding="utf-8")
    if "SHADOW_IOS_HIPEREMA_CREDITS" not in wiz_src:
        old_credits = "DrawScrollingCredits(ImVec2(panelMin.x + creditsPadding, creditsY), ImVec2(panelMax.x - creditsPadding, creditsY + fileFontSize * 1.5f), scale);"
        new_credits = """DrawScrollingCredits(ImVec2(panelMin.x + creditsPadding, creditsY), ImVec2(panelMax.x - creditsPadding, creditsY + fileFontSize * 1.5f), scale);

#if defined(SHADOW_IOS_PORT)
		/* SHADOW_IOS_HIPEREMA_CREDITS */
		{
			const char* portCredit = nullptr;
			switch (Config::Language.Value)
			{
				case ELanguage::Italian:
					portCredit = reinterpret_cast<const char*>(u8"Porting iOS sviluppato da hiperema");
					break;
				case ELanguage::French:
					portCredit = reinterpret_cast<const char*>(u8"Portage iOS développé par hiperema");
					break;
				case ELanguage::German:
					portCredit = reinterpret_cast<const char*>(u8"iOS-Port entwickelt von hiperema");
					break;
				case ELanguage::Spanish:
					portCredit = reinterpret_cast<const char*>(u8"Port de iOS desarrollado por hiperema");
					break;
				case ELanguage::Japanese:
					portCredit = reinterpret_cast<const char*>(u8"iOS移植開発: hiperema");
					break;
				case ELanguage::English:
				default:
					portCredit = reinterpret_cast<const char*>(u8"iOS port developed by hiperema");
					break;
			}
			ImVec2 portCreditSize = font->CalcTextSizeA(fileFontSize, FLT_MAX, 0, portCredit);
			float portCreditX = centerX - (portCreditSize.x * 0.5f);
			float portCreditY = creditsY + (fileFontSize * 1.5f) + (12.0f * scale);
			DrawTextWithShadow(font, fileFontSize, ImVec2(portCreditX, portCreditY), IM_COL32(255, 224, 224, 255), portCredit, 1.5, 1, IM_COL32(0, 0, 0, 127));
		}
#endif"""
        if old_credits not in wiz_src:
            raise RuntimeError("Failed to locate DrawScrollingCredits in ui/installer_wizard.cpp!")
        wiz_src = wiz_src.replace(old_credits, new_credits, 1)
        wiz_p.write_text(wiz_src, encoding="utf-8")
        print("Patched installer_wizard.cpp (localized iOS port credits: hiperema)")
PY_REG_WIN

echo "==> [5/7] Patch Plume, SDL3 UIKit (AirPlay), discord-rpc, thirdparty e XShaderRecomp per iOS arm64..."
python3 - "${UPSTREAM_DIR}/thirdparty/CMakeLists.txt" "${UPSTREAM_DIR}/thirdparty/plume/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/thirdparty/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/lib/dxc_compiler.cpp" "${UPSTREAM_DIR}/thirdparty/discord-rpc/src/discord_register_linux.cpp" "${UPSTREAM_DIR}/thirdparty/plume" "${UPSTREAM_DIR}/thirdparty/SDL/src/video/uikit" << 'PY_TP'
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
    plume_src = re.sub(r'"-framework\s+Cocoa"', '""', plume_src)
    plume_src = re.sub(r'"-framework\s+AppKit"', '""', plume_src)
    plume_src = re.sub(r'find_library\([^)]*\b(?:Cocoa|AppKit)\b[^)]*\)', '', plume_src)
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
            footer = "\n" + plume_apple_ios_stub if src_file.name == "plume_apple.mm" else "\n#endif\n"
            guarded = "/* SHADOW_IOS_PLUME_GUARDED */\n#include <TargetConditionals.h>\n#if !TARGET_OS_IPHONE\n" + mm_src + footer
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
                vh_src = "#if defined(__APPLE__)\n#include <TargetConditionals.h>\n#endif\n" + vh_src
            marker_h = "/* VOLK_GENERATE_PROTOTYPES_H */"
            parts_h = vh_src.split(marker_h)
            if len(parts_h) != 3:
                raise RuntimeError(f"Expected 2 {marker_h} markers in volk.h, got {len(parts_h) - 1}")
            open_ns_h = (
                '/* SHADOW_IOS_VOLK_NAMESPACE */\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n'
                '} /* close extern "C" */\n'
                'namespace plume_volk {\n'
                '#endif\n'
                + marker_h
            )
            close_ns_h = (
                marker_h + '\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n'
                '} /* close namespace plume_volk */\n'
                'using namespace plume_volk;\n'
                'extern "C" {\n'
                '#endif'
            )
            vh_src = parts_h[0] + open_ns_h + parts_h[1] + close_ns_h + parts_h[2]
            volk_h.write_text(vh_src, encoding="utf-8")
            print("Patched volk.h: isolated PFN_vk* prototypes into namespace plume_volk for iOS")

    volk_c = plume_dir / "contrib" / "volk" / "volk.c"
    if volk_c.exists():
        v_src = volk_c.read_text(encoding="utf-8")
        if "TargetConditionals.h" not in v_src:
            v_src = "#if defined(__APPLE__)\n#include <TargetConditionals.h>\n#include <dlfcn.h>\n#endif\n" + v_src
        if "SHADOW_IOS_STATIC_MOLTENVK" not in v_src and "volkInitialize(" in v_src:
            v_src = re.sub(
                r'(VkResult\s+volkInitialize\s*\(\s*void\s*\)\s*\{)',
                r'''#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL shadow_ios_moltenvk_vkGetInstanceProcAddr(VkInstance instance, const char* pName) __asm__("_vkGetInstanceProcAddr");
#endif

\1
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
                '/* SHADOW_IOS_VOLK_NAMESPACE */\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n'
                '} /* close extern "C" so Volk globals never collide with libMoltenVK.a */\n'
                'namespace plume_volk {\n'
                '#endif\n'
                + marker_c
            )
            close_ns_c = (
                marker_c + '\n'
                '#if defined(__cplusplus) && defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE\n'
                '} /* close namespace plume_volk */\n'
                'extern "C" {\n'
                '#endif'
            )
            v_src = parts_c[0] + open_ns_c + parts_c[1] + close_ns_c + parts_c[2]
        volk_c.write_text(v_src, encoding="utf-8")
        print("Patched volk.c: static MoltenVK binding + namespace plume_volk isolation for iOS")

    if volk_h.exists() and "SHADOW_IOS_VOLK_NAMESPACE" not in volk_h.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to namespace thirdparty/plume/contrib/volk/volk.h for iOS!")
    if volk_c.exists() and "SHADOW_IOS_VOLK_NAMESPACE" not in volk_c.read_text(encoding="utf-8"):
        raise RuntimeError("Failed to namespace thirdparty/plume/contrib/volk/volk.c for iOS!")

    # Limita i timeout di vkAcquireNextImageKHR (100ms) e vkWaitForFences (2s) su iOS
    # cosi MoltenVK non puo MAI bloccarsi all'infinito su lock-screen / swipe Home
    plume_vk = plume_dir / "plume_vulkan.cpp"
    if plume_vk.exists():
        pvk_src = plume_vk.read_text(encoding="utf-8")
        if "SHADOW_IOS_VK_TIMEOUT_FIX" not in pvk_src:
            if "TargetConditionals.h" not in pvk_src:
                pvk_src = "#if defined(__APPLE__)\n#include <TargetConditionals.h>\n#endif\n" + pvk_src
            old_acq = "        VkResult res = vkAcquireNextImageKHR(commandQueue->device->vk, vk, UINT64_MAX, interfaceSemaphore->vk, VK_NULL_HANDLE, textureIndex);"
            new_acq = """        /* SHADOW_IOS_VK_TIMEOUT_FIX */
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        VkResult res = vkAcquireNextImageKHR(commandQueue->device->vk, vk, 100000000ULL, interfaceSemaphore->vk, VK_NULL_HANDLE, textureIndex);
#else
        VkResult res = vkAcquireNextImageKHR(commandQueue->device->vk, vk, UINT64_MAX, interfaceSemaphore->vk, VK_NULL_HANDLE, textureIndex);
#endif"""
            old_fence = "        VkResult res = vkWaitForFences(device->vk, 1, &interfaceFence->vk, VK_TRUE, UINT64_MAX);"
            new_fence = """#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        VkResult res = vkWaitForFences(device->vk, 1, &interfaceFence->vk, VK_TRUE, 2000000000ULL);
#else
        VkResult res = vkWaitForFences(device->vk, 1, &interfaceFence->vk, VK_TRUE, UINT64_MAX);
#endif"""
            if old_acq not in pvk_src or old_fence not in pvk_src:
                raise RuntimeError("Failed to locate vkAcquireNextImageKHR / vkWaitForFences in thirdparty/plume/plume_vulkan.cpp!")
            pvk_src = pvk_src.replace(old_acq, new_acq, 1).replace(old_fence, new_fence, 1)
            plume_vk.write_text(pvk_src, encoding="utf-8")
            print("Patched thirdparty/plume/plume_vulkan.cpp: bounded iOS acquire/fence timeouts")

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

# 5f. SDL3 UIKit AirPlay / External Display crash fix (Feather standalone):
#     Impedisce a SDLUIKitSceneDelegate di agganciare scene AirPlay esterne (evitando doppio avvio di main()
#     e mantenendo il mirroring nativo iOS su TV come LiveContainer) e filtra UIKit_GetActiveWindowScene / UIKit_AddDisplay.
sdl_uikit_dir = pathlib.Path(sys.argv[8])
if sdl_uikit_dir.exists():
    app_del = sdl_uikit_dir / "SDL_uikitappdelegate.m"
    if app_del.exists():
        ad_src = app_del.read_text(encoding="utf-8")
        if "SHADOW_IOS_AIRPLAY_SCENE_FIX" not in ad_src:
            old_cfg = """    // This doesn't appear to be called, but it needs to be implemented to signal that we support the UIScene life cycle
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"SDLSceneConfiguration" sessionRole:connectingSceneSession.role];"""
            new_cfg = """    /* SHADOW_IOS_AIRPLAY_SCENE_FIX: rifiuta scene ExternalDisplay/AirPlay cosi iOS usa mirroring nativo */
    if (![connectingSceneSession.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
        return nil;
    }
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"SDLSceneConfiguration" sessionRole:connectingSceneSession.role];"""

            old_conn = """    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }"""
            new_conn = """    if (![scene isKindOfClass:[UIWindowScene class]] ||
        ![session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
        return;
    }"""

            old_post = """- (void)postFinishLaunch
{
    [self performSelector:@selector(hideLaunchScreen) withObject:nil afterDelay:0.0];"""
            new_post = """- (void)postFinishLaunch
{
    static BOOL s_shadowSdlMainStarted = NO;
    if (s_shadowSdlMainStarted) {
        return;
    }
    s_shadowSdlMainStarted = YES;
    [self performSelector:@selector(hideLaunchScreen) withObject:nil afterDelay:0.0];"""

            old_fg = """- (void)sceneDidBecomeActive:(UIScene *)scene
{
    SDL_OnApplicationDidEnterForeground();
}

- (void)sceneWillResignActive:(UIScene *)scene
{
    SDL_OnApplicationWillEnterBackground();
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
    SDL_OnApplicationWillEnterForeground();
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    SDL_OnApplicationDidEnterBackground();
}"""
            new_fg = """- (void)sceneDidBecomeActive:(UIScene *)scene
{
    if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) return;
    SDL_OnApplicationDidEnterForeground();
}

- (void)sceneWillResignActive:(UIScene *)scene
{
    if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) return;
    SDL_OnApplicationWillEnterBackground();
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
    if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) return;
    SDL_OnApplicationWillEnterForeground();
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) return;
    SDL_OnApplicationDidEnterBackground();
}"""
            if old_cfg not in ad_src or old_conn not in ad_src or old_post not in ad_src or old_fg not in ad_src:
                raise RuntimeError("Failed to locate SDLUIKitSceneDelegate anchors in SDL_uikitappdelegate.m!")
            ad_src = (ad_src
                      .replace(old_cfg, new_cfg, 1)
                      .replace(old_conn, new_conn, 1)
                      .replace(old_post, new_post, 1)
                      .replace(old_fg, new_fg, 1))
            app_del.write_text(ad_src, encoding="utf-8")
            print("Patched SDL_uikitappdelegate.m (AirPlay external scene rejection + single main() guard)")

    uikit_vid = sdl_uikit_dir / "SDL_uikitvideo.m"
    if uikit_vid.exists():
        uv_src = uikit_vid.read_text(encoding="utf-8")
        if "SHADOW_IOS_AIRPLAY_SCENE_FIX" not in uv_src:
            old_get_scene = """        // First, try to find an active foreground scene
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    return windowScene;
                }
            }
        }

        // If no active scene, return any foreground scene
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundInactive) {
                    return windowScene;
                }
            }
        }

        // Last resort: return first window scene
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                return (UIWindowScene *)scene;
            }
        }"""
            new_get_scene = """        /* SHADOW_IOS_AIRPLAY_SCENE_FIX: seleziona solo UIWindowSceneSessionRoleApplication */
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (![windowScene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    return windowScene;
                }
            }
        }

        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (![windowScene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
                if (windowScene.activationState == UISceneActivationStateForegroundInactive) {
                    return windowScene;
                }
            }
        }

        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (![windowScene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
                return windowScene;
            }
        }"""
            if old_get_scene not in uv_src:
                raise RuntimeError("Failed to locate UIKit_GetActiveWindowScene in SDL_uikitvideo.m!")
            uv_src = uv_src.replace(old_get_scene, new_get_scene, 1)
            uikit_vid.write_text(uv_src, encoding="utf-8")
            print("Patched SDL_uikitvideo.m (UIKit_GetActiveWindowScene filters out AirPlay external scenes)")

    uikit_modes = sdl_uikit_dir / "SDL_uikitmodes.m"
    if uikit_modes.exists():
        um_src = uikit_modes.read_text(encoding="utf-8")
        if "SHADOW_IOS_AIRPLAY_SCENE_FIX" not in um_src:
            old_add_disp = """bool UIKit_AddDisplay(UIScreen *uiscreen, bool send_event)
{
    UIScreenMode *uiscreenmode = uiscreen.currentMode;"""
            new_add_disp = """bool UIKit_AddDisplay(UIScreen *uiscreen, bool send_event)
{
#ifndef SDL_PLATFORM_TVOS
    /* SHADOW_IOS_AIRPLAY_SCENE_FIX: ignora schermi esterni AirPlay (evita crash currentMode=nil/0x0 e multi-monitor) */
    if (uiscreen != [UIScreen mainScreen]) {
        return true;
    }
#endif
    UIScreenMode *uiscreenmode = uiscreen.currentMode;"""
            if old_add_disp not in um_src:
                raise RuntimeError("Failed to locate UIKit_AddDisplay in SDL_uikitmodes.m!")
            um_src = um_src.replace(old_add_disp, new_add_disp, 1)
            uikit_modes.write_text(um_src, encoding="utf-8")
            print("Patched SDL_uikitmodes.m (UIKit_AddDisplay skips secondary AirPlay UIScreen)")

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
        out.append(f"if({condition})\n{text[start:i]}\nendif()")
        pos = i
    out.append(text[pos:])
    return "".join(out)

xsr_p = pathlib.Path(sys.argv[3])
if xsr_p.exists():
    xsr_src = xsr_p.read_text(encoding="utf-8")
    if "SHADOW_IOS_PORT" not in xsr_src:
        xsr_src = xsr_src.replace(
            "Microsoft::DirectXShaderCompiler",
            "$<$<NOT:$<BOOL:${SHADOW_IOS_PORT}>>:Microsoft::DirectXShaderCompiler>"
        )
        xsr_src = guard_cmake_calls(
            xsr_src,
            r'add_executable\s*\(\s*XShaderRecompTool\b',
            "NOT SHADOW_IOS_PORT"
        )
        xsr_src = guard_cmake_calls(
            xsr_src,
            r'(?:target_\w+|set_target_properties)\s*\(\s*XShaderRecompTool\b',
            "TARGET XShaderRecompTool"
        )
        xsr_src += '''
if(SHADOW_IOS_PORT)
    target_compile_definitions(XShaderRecompLib PRIVATE SHADOW_IOS_PORT=1)
    target_include_directories(XShaderRecompLib PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/dxc-bin/inc"
        "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/dxc-bin/inc/dxc"
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
python3 - "${UPSTREAM_DIR}/ShadowRecomp/CMakeLists.txt" "${UPSTREAM_DIR}/ShadowRecompLib/CMakeLists.txt" "${UPSTREAM_DIR}/tools/CMakeLists.txt" << 'PY_SR'
import sys, pathlib

sr_p = pathlib.Path(sys.argv[1])
sr_src = sr_p.read_text(encoding="utf-8")

# Usa SHADOW_HOST_FILE_TO_C in BIN2C durante cross-compile iOS
sr_src = sr_src.replace(
    "COMMAND $<TARGET_FILE:file_to_c>",
    "COMMAND $<IF:$<BOOL:${SHADOW_HOST_FILE_TO_C}>,${SHADOW_HOST_FILE_TO_C},$<TARGET_FILE:file_to_c>>"
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
        "os/ios/ios_virtual_controller.mm"
        "os/ios/ios_p2_server.mm"
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
    include("${CMAKE_SOURCE_DIR}/cmake/ShadowRecompIOS.cmake")
endif()'''
sr_src = sr_src.replace(old_find_pkgs, new_find_pkgs)

# Crea ShadowRecomp come MACOSX_BUNDLE su iOS
old_add_exec = '''else()
    add_executable(ShadowRecomp ${SHADOW_RECOMP_CXX_SOURCES})
endif()'''
new_add_exec = '''elseif(SHADOW_IOS_PORT)
    add_executable(ShadowRecomp MACOSX_BUNDLE ${SHADOW_RECOMP_CXX_SOURCES})
else()
    add_executable(ShadowRecomp ${SHADOW_RECOMP_CXX_SOURCES})
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
    "add_subdirectory(${SHADOW_RECOMP_TOOLS_ROOT}/file_to_c)",
    '''if(NOT SHADOW_IOS_PORT)
    add_subdirectory(${SHADOW_RECOMP_TOOLS_ROOT}/file_to_c)
endif()'''
)
tools_p.write_text(tools_src, encoding="utf-8")
print("Patched tools/CMakeLists.txt")
PY_SR

echo "==> [7/8] Patch runtime iOS arm64 (ARM64 CAS deadlock, stack 8MB, autoreleasepool, precompile idempotente, audio ring buffer, o1heap Jetsam)..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/kernel/imports.cpp" "${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.h" "${UPSTREAM_DIR}/ShadowRecomp/cpu/guest_thread.cpp" "${UPSTREAM_DIR}/ShadowRecomp/gpu/video.cpp" "${UPSTREAM_DIR}/ShadowRecomp/audio/driver/sdl3_driver.cpp" "${UPSTREAM_DIR}/thirdparty/o1heap/o1heap.h" "${UPSTREAM_DIR}/thirdparty/o1heap/o1heap.c" "${UPSTREAM_DIR}/ShadowRecomp/kernel/heap.cpp" << 'PY_IOS_RUNTIME'
import sys, pathlib

# 7a. kernel/imports.cpp: FIX ARM64 compare_exchange_weak spurious-failure deadlock in Event::Wait e RtlEnterCriticalSection + IsCurrentThread()
imp_p = pathlib.Path(sys.argv[1])
imp_src = imp_p.read_text(encoding="utf-8")
if "SHADOW_IOS_ARM64_CAS_FIX" not in imp_src:
    old_ev = """				while (true)
				{
					bool expected = true;
					if (signaled.compare_exchange_weak(expected, false))
						break;

					signaled.wait(expected);
				}"""
    new_ev = """				/* SHADOW_IOS_ARM64_CAS_FIX */
				while (true)
				{
					bool expected = true;
					if (signaled.compare_exchange_strong(expected, false))
						break;
					if (expected)
						continue;

					signaled.wait(expected);
				}"""
    if old_ev not in imp_src:
        raise RuntimeError("Failed to locate Event::Wait compare_exchange_weak in kernel/imports.cpp!")
    imp_src = imp_src.replace(old_ev, new_ev, 1)

    old_cs = """	while (true)
	{
		uint32_t previousOwner = 0;

		if (owningThread.compare_exchange_weak(previousOwner, thisThread) || previousOwner == thisThread)
		{
			CritSec->RecursionCount++;
			return;
		}

		owningThread.wait(previousOwner);
	}"""
    new_cs = """	while (true)
	{
		uint32_t previousOwner = 0;

		if (owningThread.compare_exchange_strong(previousOwner, thisThread) || previousOwner == thisThread)
		{
			CritSec->RecursionCount++;
			return;
		}

		if (previousOwner == 0)
			continue;

		owningThread.wait(previousOwner);
	}"""
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
        "#include <condition_variable>\n#if defined(SHADOW_IOS_PORT)\n#include <pthread.h>\n#endif",
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
	//printf("GuestThreadFunc(GuestThreadHandle* hThread): Function %08X\n", hThread->params.function);
	hThread->suspended.wait(true);
	GuestThread::Start(hThread->params);
}


GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
	: params(params), suspended((params.flags & 0x1) != 0), thread(GuestThreadFunc, this)
{

}

static uint32_t GetThreadId(const std::thread::id& id)
{
	return *reinterpret_cast<const uint32_t*>(&id);
}

GuestThreadHandle::~GuestThreadHandle()
{
	auto id = GetThreadId(this->thread.get_id());
	std::string s = GetThreadName(params.function);
	LOGFN("Destroy thread {:08X} with ID {} ({})", params.function, id, s);

	if (suspended.load())
	{
		LOGFN_WARNING("GuestThread: Destroying suspended thread {:08X} ({}), forcing resume", params.function, s);
		suspended.store(false, std::memory_order_release);
		suspended.notify_all();
	}

	{
		std::lock_guard lock(suspendMutex);
		resumeRequested = true;
	}
	suspendCV.notify_all();

	if (thread.joinable())
		thread.join();
}

uint32_t GuestThreadHandle::Wait(uint32_t timeout)
{
	LOGFN("Wait: Thread {:08X}", params.function);
	assert(timeout == INFINITE);

	if (thread.joinable())
		thread.join();

	return STATUS_WAIT_0;
}



GuestThreadHandle* GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId)
{
	//printf("GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId), function: %08X\n", params.function);
	auto hThread = CreateKernelObject<GuestThreadHandle>(params);

	if (threadId != nullptr)
	{
		*threadId = GetThreadId(hThread->thread.get_id());"""
    new_gt_block = r"""/* SHADOW_IOS_PTHREAD_STACK */
#if defined(SHADOW_IOS_PORT)
extern "C" void* objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void*);

static uint32_t GetIOSPthreadId(pthread_t t)
{
	uint64_t tid = 0;
	if (pthread_threadid_np(t, &tid) == 0 && tid != 0)
		return static_cast<uint32_t>(tid);
	return static_cast<uint32_t>(reinterpret_cast<uintptr_t>(t));
}
#endif

static void GuestThreadFunc(GuestThreadHandle* hThread)
{
#if defined(SHADOW_IOS_PORT)
	void* arp = objc_autoreleasePoolPush();
#endif
	hThread->suspended.wait(true);
	GuestThread::Start(hThread->params);
#if defined(SHADOW_IOS_PORT)
	objc_autoreleasePoolPop(arp);
#endif
}

#if defined(SHADOW_IOS_PORT)
static void* GuestThreadFuncPthread(void* arg)
{
	GuestThreadFunc(static_cast<GuestThreadHandle*>(arg));
	return nullptr;
}

GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
	: params(params), suspended((params.flags & 0x1) != 0)
{
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setstacksize(&attr, 8 * 1024 * 1024); // 8 MB stack per evitare crash 512 KB su iOS
	if (pthread_create(&thread, &attr, &GuestThreadFuncPthread, this) == 0)
	{
		hostThreadId.store(GetIOSPthreadId(thread), std::memory_order_release);
		threadValid.store(true, std::memory_order_release);
	}
	pthread_attr_destroy(&attr);
}
#else
GuestThreadHandle::GuestThreadHandle(const GuestThreadParams& params)
	: params(params), suspended((params.flags & 0x1) != 0), thread(GuestThreadFunc, this)
{

}
#endif

static uint32_t GetThreadId(const std::thread::id& id)
{
	return *reinterpret_cast<const uint32_t*>(&id);
}

GuestThreadHandle::~GuestThreadHandle()
{
#if defined(SHADOW_IOS_PORT)
	auto id = hostThreadId.load(std::memory_order_acquire);
#else
	auto id = GetThreadId(this->thread.get_id());
#endif
	std::string s = GetThreadName(params.function);
	LOGFN("Destroy thread {:08X} with ID {} ({})", params.function, id, s);

	if (suspended.load())
	{
		LOGFN_WARNING("GuestThread: Destroying suspended thread {:08X} ({}), forcing resume", params.function, s);
		suspended.store(false, std::memory_order_release);
		suspended.notify_all();
	}

	{
		std::lock_guard lock(suspendMutex);
		resumeRequested = true;
	}
	suspendCV.notify_all();

#if defined(SHADOW_IOS_PORT)
	if (threadValid.exchange(false, std::memory_order_acq_rel))
		pthread_join(thread, nullptr);
#else
	if (thread.joinable())
		thread.join();
#endif
}

uint32_t GuestThreadHandle::Wait(uint32_t timeout)
{
	LOGFN("Wait: Thread {:08X}", params.function);
	assert(timeout == INFINITE);

#if defined(SHADOW_IOS_PORT)
	if (threadValid.exchange(false, std::memory_order_acq_rel))
		pthread_join(thread, nullptr);
#else
	if (thread.joinable())
		thread.join();
#endif

	return STATUS_WAIT_0;
}



GuestThreadHandle* GuestThread::Start(const GuestThreadParams& params, uint32_t* threadId)
{
	auto hThread = CreateKernelObject<GuestThreadHandle>(params);

	if (threadId != nullptr)
	{
#if defined(SHADOW_IOS_PORT)
		*threadId = hThread->hostThreadId.load(std::memory_order_acquire);
#else
		*threadId = GetThreadId(hThread->thread.get_id());
#endif"""
    if old_gt_block not in gtc_src:
        raise RuntimeError("Failed to locate GuestThreadHandle implementation block in cpu/guest_thread.cpp!")
    gtc_src = gtc_src.replace(old_gt_block, new_gt_block, 1)

    old_cur_tid = """uint32_t GuestThread::GetCurrentThreadId()
{
	return GetThreadId(std::this_thread::get_id());
}"""
    new_cur_tid = """uint32_t GuestThread::GetCurrentThreadId()
{
#if defined(SHADOW_IOS_PORT)
	return GetIOSPthreadId(pthread_self());
#else
	return GetThreadId(std::this_thread::get_id());
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
    import re as _re_vid
    old_ps = """static void PrecompileShaders(const std::function<void(float)>& progress = {})
{
	auto totalStart = std::chrono::steady_clock::now();"""
    new_ps = """static void PrecompileShaders(const std::function<void(float)>& progress = {})
{
	/* SHADOW_IOS_VIDEO_FIX: evita doppia compilazione e leak GPU dopo InstallerWizard */
	static bool s_shadersPrecompiled = false;
	if (s_shadersPrecompiled)
	{
		if (progress) progress(1.0f);
		return;
	}
	auto totalStart = std::chrono::steady_clock::now();"""
    if old_ps not in vid_src:
        raise RuntimeError("Failed to locate PrecompileShaders in gpu/video.cpp!")
    vid_src = vid_src.replace(old_ps, new_ps, 1)

    vid_src, n_ps = _re_vid.subn(
        r'(\tLOGFN\("PrecompileShaders: [^\n]*\);)',
        r'\ts_shadersPrecompiled = true;\n\1',
        vid_src,
        count=1
    )
    if n_ps == 0:
        raise RuntimeError("Failed to locate PrecompileShaders end log in gpu/video.cpp!")

    old_psp = """static void PrecompileStaticPipelines(const std::function<void(float)>& progress = {})
{
	if constexpr (g_staticPipelineCacheCount == 0)
		return;"""
    new_psp = """static void PrecompileStaticPipelines(const std::function<void(float)>& progress = {})
{
	if constexpr (g_staticPipelineCacheCount == 0)
		return;
	static bool s_staticPipelinesPrecompiled = false;
	if (s_staticPipelinesPrecompiled)
	{
		if (progress) progress(1.0f);
		return;
	}"""
    if old_psp not in vid_src:
        raise RuntimeError("Failed to locate PrecompileStaticPipelines in gpu/video.cpp!")
    vid_src = vid_src.replace(old_psp, new_psp, 1)

    vid_src, n_psp = _re_vid.subn(
        r'(\tLOGFN\("PipelineCache: Static precompiled [^\n]*\);)',
        r'\ts_staticPipelinesPrecompiled = true;\n\1',
        vid_src,
        count=1
    )
    if n_psp == 0:
        raise RuntimeError("Failed to locate PrecompileStaticPipelines end log in gpu/video.cpp!")

    old_rt_head = """static std::thread g_renderThread([]
	{"""
    new_rt_head = """#if defined(SHADOW_IOS_PORT)
#include <pthread.h>
extern "C" void* objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void*);
static void ShadowIOSRenderThreadMain()
#else
static std::thread g_renderThread([]
#endif
	{"""
    if old_rt_head not in vid_src:
        raise RuntimeError("Failed to locate g_renderThread in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_head, new_rt_head, 1)

    old_rt_loop = """					if (g_renderDirectorProfiler.active)
						g_rtQueueWaitInFrameAccum.Add(waitMs);
				}
			}
			for (size_t i = 0; i < count; i++)"""
    new_rt_loop = """					if (g_renderDirectorProfiler.active)
						g_rtQueueWaitInFrameAccum.Add(waitMs);
				}
			}
#if defined(SHADOW_IOS_PORT)
			void* iosArp = objc_autoreleasePoolPush();
#endif
			for (size_t i = 0; i < count; i++)"""
    if old_rt_loop not in vid_src:
        raise RuntimeError("Failed to locate render loop batch in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_loop, new_rt_loop, 1)

    old_rt_end = """				default:
					ProcessRenderCommand(cmd);
					break;
				}
			}
		}
	});"""
    new_rt_end = """				default:
					ProcessRenderCommand(cmd);
					break;
				}
			}
#if defined(SHADOW_IOS_PORT)
			objc_autoreleasePoolPop(iosArp);
#endif
		}
#if defined(SHADOW_IOS_PORT)
	}
struct ShadowIOSRenderThreadStarter
{
	static void* Entry(void*)
	{
		ShadowIOSRenderThreadMain();
		return nullptr;
	}
	ShadowIOSRenderThreadStarter()
	{
		pthread_t tid{};
		pthread_attr_t attr;
		pthread_attr_init(&attr);
		pthread_attr_setstacksize(&attr, 8 * 1024 * 1024); // 8 MB stack per MoltenVK + SPIRV-Cross
		if (pthread_create(&tid, &attr, &Entry, nullptr) == 0)
			pthread_detach(tid);
		pthread_attr_destroy(&attr);
	}
};
static ShadowIOSRenderThreadStarter g_renderThread;
#else
	});
#endif"""
    if old_rt_end not in vid_src:
        raise RuntimeError("Failed to locate g_renderThread closing block in gpu/video.cpp!")
    vid_src = vid_src.replace(old_rt_end, new_rt_end, 1)

    # 7c-bis. iOS background/lock-screen suspend & foreground swapchain recovery (SHADOW_IOS_LIFECYCLE_FIX)
    old_proc_ef = """static void ProcEndFrame(const RenderCommand& cmd)
{"""
    new_proc_ef = """/* SHADOW_IOS_LIFECYCLE_FIX */
#if defined(SHADOW_IOS_PORT)
static std::mutex g_iosLifecycleMutex;
static std::condition_variable g_iosLifecycleCv;
static std::atomic<bool> g_iosAppBackgrounded{ false };
static std::atomic<bool> g_iosRenderParked{ false };
static std::atomic<bool> g_iosSwapChainForceRebuild{ false };
static std::atomic<bool> g_iosRenderThreadStarted{ false };

static void ShadowIOSDrainInFlightGpuOnly()
{
	if (g_queue)
	{
		for (size_t i = 0; i < NUM_FRAMES; i++)
		{
			if (g_commandListStates[i])
			{
				g_queue->waitForCommandFence(g_commandFences[i].get());
				g_commandListStates[i] = false;
			}
		}
	}
	if (g_vulkan && g_swapChain)
	{
		auto* curSwapChain = GetVulkanSwapChain();
		if (curSwapChain && curSwapChain->commandQueue && curSwapChain->commandQueue->queue &&
		    curSwapChain->commandQueue->queue->vk != VK_NULL_HANDLE)
		{
			std::scoped_lock lock(*curSwapChain->commandQueue->queue->mutex);
			vkQueueWaitIdle(curSwapChain->commandQueue->queue->vk);
		}
	}
}

static void ShadowIOSParkIfBackgrounded()
{
	if (!g_iosAppBackgrounded.load(std::memory_order_acquire))
		return;

	// Drena tutti i command buffer Metal gia in volo PRIMA che iOS revochi la GPU (zero nuovi commit!)
	ShadowIOSDrainInFlightGpuOnly();

	std::unique_lock<std::mutex> lock(g_iosLifecycleMutex);
	g_iosRenderParked.store(true, std::memory_order_release);
	g_iosLifecycleCv.notify_all();

	g_iosLifecycleCv.wait(lock, [] {
		return !g_iosAppBackgrounded.load(std::memory_order_acquire);
	});
	g_iosRenderParked.store(false, std::memory_order_release);
}

extern "C" void ShadowIOS_VideoOnWillEnterBackground()
{
	if (g_iosAppBackgrounded.exchange(true, std::memory_order_acq_rel))
		return;
	if (!g_iosRenderThreadStarted.load(std::memory_order_acquire))
		return;

	std::unique_lock<std::mutex> lock(g_iosLifecycleMutex);
	// Attesa limitata (450ms max) per drenare la GPU in modo sincrono senza mai rischiare deadlock con UIKit
	g_iosLifecycleCv.wait_for(lock, std::chrono::milliseconds(450), [] {
		return g_iosRenderParked.load(std::memory_order_acquire) || !g_iosAppBackgrounded.load(std::memory_order_acquire);
	});
}

extern "C" void ShadowIOS_VideoOnDidEnterForeground()
{
	g_iosSwapChainForceRebuild.store(true, std::memory_order_release);
	{
		std::lock_guard<std::mutex> lock(g_iosLifecycleMutex);
		g_iosAppBackgrounded.store(false, std::memory_order_release);
	}
	g_iosLifecycleCv.notify_all();
}
#endif

static void ProcEndFrame(const RenderCommand& cmd)
{"""
    if old_proc_ef not in vid_src:
        raise RuntimeError("Failed to locate ProcEndFrame in gpu/video.cpp!")
    vid_src = vid_src.replace(old_proc_ef, new_proc_ef, 1)

    old_chk_sc = """	CheckSwapChain(cmd.endFrame.gameThreadWaits);
	ProcBeginCommandList(cmd);"""
    new_chk_sc = """#if defined(SHADOW_IOS_PORT)
	ShadowIOSParkIfBackgrounded();
	const bool iosForceRebuild = g_iosSwapChainForceRebuild.exchange(false, std::memory_order_acq_rel);
	const bool canRebuildSwapChain = cmd.endFrame.gameThreadWaits || iosForceRebuild;
	if (iosForceRebuild)
	{
		g_swapChainValid = false;
	}
	CheckSwapChain(canRebuildSwapChain);
	if (iosForceRebuild && !g_swapChainValid && !g_iosAppBackgrounded.load(std::memory_order_acquire))
	{
		for (int retry = 0; retry < 30 && !g_swapChainValid && !g_iosAppBackgrounded.load(std::memory_order_acquire); ++retry)
		{
			std::this_thread::sleep_for(std::chrono::milliseconds(16));
			CheckSwapChain(true);
		}
	}
#else
	CheckSwapChain(cmd.endFrame.gameThreadWaits);
#endif
	ProcBeginCommandList(cmd);"""
    if old_chk_sc not in vid_src:
        raise RuntimeError("Failed to locate CheckSwapChain call in ProcEndFrame of gpu/video.cpp!")
    vid_src = vid_src.replace(old_chk_sc, new_chk_sc, 1)

    old_wait_deq = "				count = g_renderQueue.wait_dequeue_bulk(commands, std::size(commands));"
    new_wait_deq = """#if defined(SHADOW_IOS_PORT)
				g_iosRenderThreadStarted.store(true, std::memory_order_release);
				ShadowIOSParkIfBackgrounded();
				count = g_renderQueue.wait_dequeue_bulk_timed(commands, std::size(commands), std::chrono::milliseconds(10));
				if (count == 0)
					continue;
#else
				count = g_renderQueue.wait_dequeue_bulk(commands, std::size(commands));
#endif"""
    if old_wait_deq not in vid_src:
        raise RuntimeError("Failed to locate wait_dequeue_bulk in gpu/video.cpp!")
    vid_src = vid_src.replace(old_wait_deq, new_wait_deq, 1)

    # 7c-ter. ImGui touch coordinate scaling fix on fresh iOS install (usa sempre SDL_GetWindowSize live invece di s_width/s_height stale 640x480)
    old_imgui_scale = """	uint32_t width = g_swapChain->getWidth();
	uint32_t height = g_swapChain->getHeight();
	float mousePosScaleX = float(width) / float(GameWindow::s_width);
	float mousePosScaleY = float(height) / float(GameWindow::s_height);"""
    new_imgui_scale = """	uint32_t width = g_swapChain->getWidth();
	uint32_t height = g_swapChain->getHeight();
#if defined(SHADOW_IOS_PORT)
	/* SHADOW_IOS_IMGUI_TOUCH_SCALE_FIX: usa la dimensione logica live SDL (es. 874x402), mai 640x480 stale */
	int liveWinW = GameWindow::s_width;
	int liveWinH = GameWindow::s_height;
	if (GameWindow::s_pWindow != nullptr)
	{
		SDL_GetWindowSize(GameWindow::s_pWindow, &liveWinW, &liveWinH);
		if (liveWinW > 0 && liveWinH > 0)
		{
			GameWindow::s_width = liveWinW;
			GameWindow::s_height = liveWinH;
		}
	}
	float mousePosScaleX = (liveWinW > 0) ? (float(width) / float(liveWinW)) : 1.0f;
	float mousePosScaleY = (liveWinH > 0) ? (float(height) / float(liveWinH)) : 1.0f;
#else
	float mousePosScaleX = float(width) / float(GameWindow::s_width);
	float mousePosScaleY = float(height) / float(GameWindow::s_height);
#endif"""
    if old_imgui_scale not in vid_src:
        raise RuntimeError("Failed to locate DrawImGui mousePosScale block in gpu/video.cpp!")
    vid_src = vid_src.replace(old_imgui_scale, new_imgui_scale, 1)

    vid_p.write_text(vid_src, encoding="utf-8")
    print("Patched gpu/video.cpp: idempotent precompile + 8 MB iOS render thread + autoreleasepool + background/foreground GPU pause + ImGui touch scale fix")

# 7d. audio/driver/sdl3_driver.cpp: 1024 sample frames su iOS CoreAudio + protezione bounds ring-buffer in Pull()
aud_p = pathlib.Path(sys.argv[5])
aud_src = aud_p.read_text(encoding="utf-8")
if "SHADOW_IOS_AUDIO_FIX" not in aud_src:
    old_hint = '	SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "512"); // necessary for weapon SFX timing (SDL default is 1024)'
    new_hint = '''#if defined(SHADOW_IOS_PORT)
	/* SHADOW_IOS_AUDIO_FIX: 1024 frame (~21ms @ 48kHz) riduce interruzioni CoreAudio realtime su iOS */
	SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "1024");
#else
	SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "512"); // necessary for weapon SFX timing (SDL default is 1024)
#endif'''
    if old_hint not in aud_src:
        raise RuntimeError("Failed to locate SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES in sdl3_driver.cpp!")
    aud_src = aud_src.replace(old_hint, new_hint, 1)

    old_pull = """	int srcBytesPerSample = SDL_AUDIO_BITSIZE(mFormat) / 8 * mChannelCount;
	int dstBytesPerSample = SDL_AUDIO_BITSIZE(mParent->mFormat) / 8 * mParent->mChannelCount;
	float ratio = (float)mParent->mFrequency / (float)mFrequency
		* (float)dstBytesPerSample / (float)srcBytesPerSample;
	int read_size = (int)(size / ratio);
	read_size -= read_size % srcBytesPerSample; // align to sample boundary

	read_size = mLooping
		? read_size
		: std::min(read_size, mWrittenSize);

	if (read_size <= 0)
	{
		StopSfxEarly();
		return result;
	}"""
    new_pull = """	if (mBufferSize <= 0 || mFrequency <= 0 || mParent->mFrequency <= 0 || size <= 0)
	{
		StopSfxEarly();
		return result;
	}

	int srcBytesPerSample = SDL_AUDIO_BITSIZE(mFormat) / 8 * mChannelCount;
	int dstBytesPerSample = SDL_AUDIO_BITSIZE(mParent->mFormat) / 8 * mParent->mChannelCount;
	if (srcBytesPerSample <= 0 || dstBytesPerSample <= 0)
	{
		return result;
	}

	float ratio = (float)mParent->mFrequency / (float)mFrequency
		* (float)dstBytesPerSample / (float)srcBytesPerSample;
	int read_size = (int)(size / ratio);
	read_size -= read_size % srcBytesPerSample; // align to sample boundary

	read_size = mLooping
		? read_size
		: std::min(read_size, mWrittenSize);

	if (read_size > mBufferSize)
	{
		read_size = mBufferSize - (mBufferSize % srcBytesPerSample);
	}

	if (mBufferReadLoc < 0 || mBufferReadLoc >= mBufferSize)
	{
		mBufferReadLoc = ((mBufferReadLoc % mBufferSize) + mBufferSize) % mBufferSize;
	}

	if (read_size <= 0)
	{
		StopSfxEarly();
		return result;
	}"""
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

	// Check if pointer is in physical heap region
	if (ptr >= physicalHeap)
	{
		//printf("[FREE PHYSICAL] ptr: %p\n", ptr);
		std::lock_guard lock(physicalMutex);
		o1heapFree(physicalHeap, *((void**)ptr - 1));
	}
	else
	{
		//printf("[FREE REGULAR] ptr: %p\n", ptr);
		std::lock_guard lock(mutex);
		o1heapFree(heap, ptr);
	}

}"""
    new_heap_free = """#if defined(SHADOW_IOS_PORT)
#include <sys/mman.h>
#include <unistd.h>
static void ShadowIOSDiscardPages(void* begin, size_t size)
{
	/* SHADOW_IOS_JETSAM_DISCARD: restituisce pagine liberate >= 64 KB a Darwin Jetsam */
	if (!begin || size < 65536) return;
	static const size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
	const uintptr_t rawStart = reinterpret_cast<uintptr_t>(begin);
	const uintptr_t rawEnd = rawStart + size;
	const uintptr_t alignedStart = (rawStart + pageSize - 1) & ~(pageSize - 1);
	const uintptr_t alignedEnd = rawEnd & ~(pageSize - 1);
	if (alignedEnd > alignedStart && (alignedEnd - alignedStart) >= 65536)
	{
		madvise(reinterpret_cast<void*>(alignedStart), alignedEnd - alignedStart, MADV_FREE);
	}
}
#endif

void Heap::Free(void* ptr)
{
	if (!ptr) return;

	// Check if pointer is in physical heap region
	if (ptr >= physicalHeap)
	{
		std::lock_guard lock(physicalMutex);
#if defined(SHADOW_IOS_PORT)
		void* unusedBegin = nullptr;
		size_t unusedSize = 0;
		o1heapFreeAndGetUnusedRange(physicalHeap, *((void**)ptr - 1), &unusedBegin, &unusedSize);
		ShadowIOSDiscardPages(unusedBegin, unusedSize);
#else
		o1heapFree(physicalHeap, *((void**)ptr - 1));
#endif
	}
	else
	{
		std::lock_guard lock(mutex);
#if defined(SHADOW_IOS_PORT)
		void* unusedBegin = nullptr;
		size_t unusedSize = 0;
		o1heapFreeAndGetUnusedRange(heap, ptr, &unusedBegin, &unusedSize);
		ShadowIOSDiscardPages(unusedBegin, unusedSize);
#else
		o1heapFree(heap, ptr);
#endif
	}
}"""
    if old_heap_free not in heap_src:
        raise RuntimeError("Failed to locate Heap::Free in kernel/heap.cpp!")
    heap_src = heap_src.replace(old_heap_free, new_heap_free, 1)
    heap_p.write_text(heap_src, encoding="utf-8")
    print("Patched kernel/heap.cpp with iOS Jetsam MADV_FREE page discard")
PY_IOS_RUNTIME

echo "==> [8/8] Patch ShadowRecomp/input/input.cpp per Controller Virtuale 1P + Server Hotspot 2P + Haptics..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/input/input.cpp" << 'PY_IOS_INPUT'
import sys, pathlib

inp_p = pathlib.Path(sys.argv[1])
inp_src = inp_p.read_text(encoding="utf-8")

if "IOSVirtualController_GetState" not in inp_src:
    # 1. Include header bridge iOS 1P + Server 2P Hotspot + InstallerWizard
    old_inc = '#include <os/logger.h>'
    new_inc = '''#include <os/logger.h>
#if defined(SHADOW_IOS_PORT)
#include <ui/installer_wizard.h>
#include <ios_virtual_controller.h>
#include <ios_p2_server.h>
#endif'''
    if old_inc not in inp_src:
        raise RuntimeError("Failed to locate #include <os/logger.h> in input/input.cpp!")
    inp_src = inp_src.replace(old_inc, new_inc, 1)

    # 2. Su iOS / LiveContainer non bloccare mai l'input se SDL_EVENT_WINDOW_FOCUS_GAINED non viene emesso subito
    old_allowed = '''bool IsInputAllowed()
{
	return GameWindow::s_isFocused || Config::AllowBackgroundInput;
}'''
    new_allowed = '''bool IsInputAllowed()
{
#if defined(SHADOW_IOS_PORT)
	return true;
#else
	return GameWindow::s_isFocused || Config::AllowBackgroundInput;
#endif
}'''
    if old_allowed not in inp_src:
        raise RuntimeError("Failed to locate IsInputAllowed() in input/input.cpp!")
    inp_src = inp_src.replace(old_allowed, new_allowed, 1)

    # 3. Sincronizza l'overlay virtuale da input::Update() (main thread) con stato controller fisici, installer e Chaos Aura
    old_upd = '''void input::Update()
{
	MainThreadDispatcher::Get().Flush();
	AssignControllers();
	ApplyControllerLEDs();
	PublishPadFrame();
}'''
    new_upd = '''void input::Update()
{
	MainThreadDispatcher::Get().Flush();
	AssignControllers();
	ApplyControllerLEDs();
	PublishPadFrame();
#if defined(SHADOW_IOS_PORT)
	bool hasPhysicalController = (s_activeControllerId.load(std::memory_order_relaxed) != 0) || !s_unassignedControllers.empty();
	if (!hasPhysicalController)
	{
		for (auto& c : g_controllers)
		{
			if (c.CanPoll())
			{
				hasPhysicalController = true;
				break;
			}
		}
	}
	IOSVirtualController_SyncState(hasPhysicalController, InstallerWizard::s_isVisible, static_cast<int>(App::s_chaosMode.load(std::memory_order_relaxed)));
#endif
}'''
    if old_upd not in inp_src:
        raise RuntimeError("Failed to locate input::Update() in input/input.cpp!")
    inp_src = inp_src.replace(old_upd, new_upd, 1)

    # 4. Mostra icone Xbox Original nei prompt di gioco per 1P virtuale e 2P web remoto su iOS
    old_dev = '''input::EInputDevice input::GetPadDevice(uint32_t playerIndex)
{
	const auto frame = GetPadFrame();
	return playerIndex < frame.pads.size() ? frame.pads[playerIndex].device : EInputDevice::Unknown;
}'''
    new_dev = '''input::EInputDevice input::GetPadDevice(uint32_t playerIndex)
{
	const auto frame = GetPadFrame();
	if (playerIndex < frame.pads.size() && frame.pads[playerIndex].connected)
		return frame.pads[playerIndex].device;
#if defined(SHADOW_IOS_PORT)
	if (playerIndex == 0)
		return EInputDevice::Xbox;
	if (playerIndex == 1 && IOSRemoteP2_IsConnected())
		return EInputDevice::Xbox;
#endif
	return EInputDevice::Unknown;
}'''
    if old_dev not in inp_src:
        raise RuntimeError("Failed to locate input::GetPadDevice() in input/input.cpp!")
    inp_src = inp_src.replace(old_dev, new_dev, 1)

    # 5. Inietta lo stato Xbox Original 1P (touch overlay) e 2P (Smartphone 2 via Hotspot WebSocket) in input::GetState
    old_kb_branch = '''		if (dwUserIndex == g_keyboardPort)'''
    new_kb_branch = '''#if defined(SHADOW_IOS_PORT)
		if (dwUserIndex == 1 && !hasController)
		{
			IOSVirtualPadSnapshot vpad{};
			if (IOSVirtualController_GetState(&vpad))
			{
				auto& pad = pState->Gamepad;
				pad.wButtons |= vpad.wButtons;
				for (int i = 0; i < 8; i++)
				{
					if (vpad.bAnalogButtons[i] > pad.bAnalogButtons[i])
						pad.bAnalogButtons[i] = vpad.bAnalogButtons[i];
				}
				if (vpad.sThumbLX != 0) pad.sThumbLX = vpad.sThumbLX;
				if (vpad.sThumbLY != 0) pad.sThumbLY = vpad.sThumbLY;
				if (vpad.sThumbRX != 0)
				{
					int16_t rx = vpad.sThumbRX;
					if (Config::HorizontalCamera1P == ECameraRotationMode::Reverse)
						rx = static_cast<int16_t>(std::clamp(-static_cast<int32_t>(rx), -32768, 32767));
					pad.sThumbRX = rx;
				}
				if (vpad.sThumbRY != 0) pad.sThumbRY = vpad.sThumbRY;
				if (vpad.anyActive)
				{
					input::g_inputDevice = input::EInputDevice::Xbox;
					input::g_inputDeviceController = input::EInputDevice::Xbox;
				}
			}
		}
		else if (dwUserIndex == 2 && !hasController)
		{
			IOSVirtualPadSnapshot vpad2{};
			if (IOSRemoteP2_GetState(&vpad2))
			{
				auto& pad = pState->Gamepad;
				pad.wButtons |= vpad2.wButtons;
				for (int i = 0; i < 8; i++)
				{
					if (vpad2.bAnalogButtons[i] > pad.bAnalogButtons[i])
						pad.bAnalogButtons[i] = vpad2.bAnalogButtons[i];
				}
				pad.sThumbLX = vpad2.sThumbLX;
				pad.sThumbLY = vpad2.sThumbLY;
				int16_t rx2 = vpad2.sThumbRX;
				if (Config::HorizontalCamera2P == ECameraRotationMode::Reverse)
					rx2 = static_cast<int16_t>(std::clamp(-static_cast<int32_t>(rx2), -32768, 32767));
				pad.sThumbRX = rx2;
				pad.sThumbRY = vpad2.sThumbRY;
				return ERROR_SUCCESS;
			}
		}
#endif

		if (dwUserIndex == g_keyboardPort)'''
    if old_kb_branch not in inp_src:
        raise RuntimeError("Failed to locate g_keyboardPort branch in input::GetState!")
    inp_src = inp_src.replace(old_kb_branch, new_kb_branch, 1)

    # 6. Inoltra la vibrazione Xbox Original al Taptic Engine (1P) e a Smartphone 2 via WebSocket (2P)
    old_set_state = '''	if (!frame.hasActiveController)
	{
		return ERROR_DEVICE_NOT_CONNECTED;
	}'''
    new_set_state = '''#if defined(SHADOW_IOS_PORT)
	if (dwUserIndex == 2 && (!frame.hasActiveController || (frame.pads.size() > 1 && !frame.pads[1].connected)) && IOSRemoteP2_IsConnected())
	{
		IOSRemoteP2_SetRumble(outPacket->wLeftMotorSpeed, outPacket->wRightMotorSpeed);
		return ERROR_SUCCESS;
	}
#endif
	if (!frame.hasActiveController)
	{
#if defined(SHADOW_IOS_PORT)
		if (dwUserIndex == 1)
		{
			IOSVirtualController_SetRumble(outPacket->wLeftMotorSpeed, outPacket->wRightMotorSpeed);
			return ERROR_SUCCESS;
		}
#endif
		return ERROR_DEVICE_NOT_CONNECTED;
	}'''
    if old_set_state not in inp_src:
        raise RuntimeError("Failed to locate !frame.hasActiveController in input::SetState!")
    inp_src = inp_src.replace(old_set_state, new_set_state, 1)

    inp_p.write_text(inp_src, encoding="utf-8")
    print("Patched ShadowRecomp/input/input.cpp with iOS 1P virtual controller + 2P Hotspot Web controller + rumble")
PY_IOS_INPUT

echo "==> [9/9] Patch iOS completata con successo!"