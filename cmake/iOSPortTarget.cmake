if(SHADOW_IOS_PORT)
    message(STATUS "Configuring ShadowRecomp for iOS arm64 (iPhone 16 Pro / Metal 3)")
    enable_language(OBJC OBJCXX Swift)

    target_sources(ShadowRecomp PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/ios/ShadowRecompLauncherView.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/ios/IOSVFSBridge.mm"
    )

    set_target_properties(ShadowRecomp PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist"
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
endif()
