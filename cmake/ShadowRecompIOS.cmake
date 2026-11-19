# cmake/ShadowRecompIOS.cmake
# Integrazione nativa iOS arm64 per FoxWorkshop/ShadowRecomp (iPhone 16 Pro / Feather / LiveContainer)

add_library(nfd::nfd INTERFACE IMPORTED)
target_include_directories(nfd::nfd INTERFACE "${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include")

add_library(CURL::libcurl INTERFACE IMPORTED)
target_include_directories(CURL::libcurl INTERFACE "${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include")

function(shadow_configure_ios_target TARGET_NAME)
    message(STATUS "Configuring ${TARGET_NAME} for iOS arm64 (iPhone 16 Pro / MoltenVK -> Metal 3)")

    set_target_properties(${TARGET_NAME} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/ios/Info.plist"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.foxworkshop.shadowrecomp.ios"
        XCODE_ATTRIBUTE_MARKETING_VERSION "1.0.0"
        XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "1"
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
    )

    target_include_directories(${TARGET_NAME} PRIVATE
        "${CMAKE_SOURCE_DIR}/ShadowRecomp/ios_compat/include"
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
        SHADOW_IOS_PORT=1
        PLUME_SDL_VULKAN_ENABLED=1
        SHADOW_IOS_PROMOTION_120HZ=1
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
    if(MOLTENVK_STATIC_LIB AND EXISTS "${MOLTENVK_STATIC_LIB}")
        target_link_libraries(${TARGET_NAME} PRIVATE "${MOLTENVK_STATIC_LIB}")
        target_link_options(${TARGET_NAME} PRIVATE "-Wl,-u,_vkGetInstanceProcAddr" "-Wl,-export_dynamic")
    else()
        message(WARNING "MOLTENVK_STATIC_LIB non trovato; verificare il download di MoltenVK-ios.tar")
    endif()

    # Framework Apple iOS necessari per Metal 3, SDL3, App File, Controller e Audio
    target_link_libraries(${TARGET_NAME} PRIVATE
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
endfunction()