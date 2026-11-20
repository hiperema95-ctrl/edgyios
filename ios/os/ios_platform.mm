// ios/os/ios_platform.mm
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
        SDL_SetHint(SDL_HINT_IDLE_TIMER_DISABLED, "1");
        SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
        SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

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

    std::fprintf(stderr, "ShadowRecomp %s [%s] %.*s\n", prefix, func ? func : "*", static_cast<int>(str.size()), str.data());
}

void LogFile(const std::string_view str, std::filesystem::path fileName) {
    std::lock_guard<std::mutex> lock(g_logMutex);
    auto outPath = GetIOSDocumentsDir() / "ShadowRecomp" / "logs" / fileName.filename();
    std::error_code ec;
    std::filesystem::create_directories(outPath.parent_path(), ec);
    std::ofstream ofs(outPath, std::ios::app);
    if (ofs.is_open()) {
        ofs.write(str.data(), static_cast<std::streamsize>(str.size()));
        ofs << "\n";
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
    std::string buf(size, '\0');
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

} // namespace os::version