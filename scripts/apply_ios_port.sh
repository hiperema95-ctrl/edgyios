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

echo "==> [3/7] Patch ShadowRecomp/user/paths.cpp (rimuove static_assert per __APPLE__ / iOS)..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/user/paths.cpp" << 'PY_PATHS'
import sys, pathlib
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
    p.write_text(src, encoding="utf-8")
    print("Patched paths.cpp for iOS Documents/")
PY_PATHS

echo "==> [4/7] Patch ShadowRecomp/os/registry.h e ShadowRecomp/ui/game_window.cpp..."
python3 - "${UPSTREAM_DIR}/ShadowRecomp/os/registry.h" "${UPSTREAM_DIR}/ShadowRecomp/ui/game_window.cpp" << 'PY_REG_WIN'
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
if "defined(__APPLE__)" not in win_src:
    win_src = win_src.replace(
        "#elif defined(PLUME_SDL_VULKAN_ENABLED)",
        "#elif defined(PLUME_SDL_VULKAN_ENABLED) || defined(__APPLE__)"
    )
    win_p.write_text(win_src, encoding="utf-8")
    print("Patched game_window.cpp")
PY_REG_WIN

echo "==> [5/7] Patch Plume, thirdparty e XShaderRecomp per iOS arm64 (MoltenVK + no desktop DXC dylib)..."
python3 - "${UPSTREAM_DIR}/thirdparty/CMakeLists.txt" "${UPSTREAM_DIR}/thirdparty/plume/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/thirdparty/CMakeLists.txt" "${UPSTREAM_DIR}/tools/XShaderRecomp/XShaderRecomp/lib/dxc_compiler.cpp" << 'PY_TP'
import sys, pathlib

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

# 5b. thirdparty/plume/CMakeLists.txt: consenti PLUME_SDL3_VULKAN_ENABLED anche su APPLE/iOS
plume_p = pathlib.Path(sys.argv[2])
if plume_p.exists():
    plume_src = plume_p.read_text(encoding="utf-8")
    plume_src = plume_src.replace(
        'cmake_dependent_option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF IS_LINUX OFF)',
        'option(PLUME_SDL3_VULKAN_ENABLED "Enable SDL3 Vulkan integration" OFF)'
    )
    plume_src = plume_src.replace("PUBLIC PUBLIC SDL3::Headers", "PUBLIC SDL3::Headers")
    plume_p.write_text(plume_src, encoding="utf-8")
    print("Patched plume/CMakeLists.txt")

# 5c. XShaderRecomp/CMakeLists.txt: su iOS non compilare XShaderRecompTool e proteggi OGNI target_*(XShaderRecompTool ...)
import re

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

echo "==> [7/7] Patch iOS completata con successo!"