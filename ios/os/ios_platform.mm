// ios/os/ios_platform.mm
// Implementazione nativa iOS dei namespace os::logger, os::process, os::media, os::user, os::version
// + Motore EdgyiOS Crashlog & Diagnostica 10s (Documents/ShadowRecomp/crashlog.txt)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>
#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_log.h>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <exception>
#include <execinfo.h>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mutex>
#include <os/proc.h>
#include <signal.h>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <vector>

#include <os/logger.h>
#include <os/media.h>
#include <os/process.h>
#include <os/user.h>
#include <os/version.h>

extern "C" void ShadowIOS_VideoOnWillEnterBackground();
extern "C" void ShadowIOS_VideoOnDidEnterForeground();

typedef void (*ShadowCrashLogStateCallback)(bool capturing, int remainingSec, bool savedOk);

namespace {
std::mutex g_logMutex;
std::once_flag g_iosRuntimeInitOnce;
id g_iosWillResignObserver = nil;
id g_iosDidEnterBgObserver = nil;
id g_iosDidBecomeActiveObserver = nil;
id g_iosMemWarnObserver = nil;

// Ring buffer lock-free in RAM (256 righe x 256 byte = 64 KB): zero allocazioni heap e zero I/O disco a 120fps!
constexpr size_t kCrashRingCapacity = 256;
constexpr size_t kCrashRingLineMax  = 256;
char g_crashRingLines[kCrashRingCapacity][kCrashRingLineMax]{};
std::atomic<uint64_t> g_crashRingSeq{0};

// Buffer statici pre-calcolati all'avvio per scrittura 100% async-signal-safe in caso di SIGSEGV/SIGABRT/SIGBUS
char g_crashLogPath[1024]{};
char g_crashPrevPath[1024]{};
char g_logsDirPath[1024]{};
char g_deviceBanner[512]{};
uint8_t g_altSigStackMem[65536]{};
std::atomic<int> g_inCrashHandler{0};
NSUncaughtExceptionHandler *g_prevNSExceptionHandler = nullptr;
std::terminate_handler g_prevTerminateHandler = nullptr;

// Contesto runtime lock-free (aggiornato da virtual controller e frame tick per FPS reali)
std::atomic<uint64_t> g_frameTickCounter{0};
std::atomic<bool> g_ctxTVMode{false};
std::atomic<bool> g_ctxP2Active{false};
std::atomic<bool> g_ctxP2Connected{false};
std::atomic<bool> g_ctxPhysicalPad{false};

// Stato cattura manuale temporizzata (pulsante LOG nella barra Chaos Emerald)
std::atomic<bool> g_captureActive{false};
std::atomic<int> g_captureRemainingSec{0};
std::atomic<int> g_captureTotalSec{10};
std::mutex g_captureMutex;
std::vector<std::string> g_capturePreContext;
std::vector<std::string> g_captureLiveLines;
std::string g_captureStartTimestamp;
uint64_t g_capturePrevFrames = 0;
double g_capturePrevSampleSec = 0.0;
dispatch_source_t g_captureTimer = nil;
dispatch_queue_t g_captureQueue = nil;
std::mutex g_captureCbMutex;
ShadowCrashLogStateCallback g_captureStateCb = nullptr;

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

static inline void SafeWriteStr(int fd, const char *s) {
    if (fd < 0 || !s) return;
    size_t len = 0;
    while (s[len] != '\0') ++len;
    if (len > 0) {
        ssize_t ignored = ::write(fd, s, len);
        (void)ignored;
    }
}

static inline void SafeWriteHex(int fd, uintptr_t val) {
    char buf[24];
    buf[0] = '0';
    buf[1] = 'x';
    static const char kHex[] = "0123456789abcdef";
    for (int i = 0; i < 16; ++i) {
        buf[2 + i] = kHex[(val >> ((15 - i) * 4)) & 0xF];
    }
    buf[18] = '\0';
    SafeWriteStr(fd, buf);
}

static inline void SafeWriteInt(int fd, int64_t v) {
    char buf[32];
    int pos = 31;
    buf[pos] = '\0';
    bool neg = (v < 0);
    uint64_t u = neg ? static_cast<uint64_t>(-(v + 1)) + 1ULL : static_cast<uint64_t>(v);
    if (u == 0) {
        buf[--pos] = '0';
    } else {
        while (u > 0 && pos > 1) {
            buf[--pos] = static_cast<char>('0' + (u % 10));
            u /= 10;
        }
    }
    if (neg && pos > 0) buf[--pos] = '-';
    SafeWriteStr(fd, &buf[pos]);
}

static void FormatWallTimestamp(char *outBuf, size_t outCap, bool includeDate) {
    struct timeval tv{};
    gettimeofday(&tv, nullptr);
    struct tm tmLocal{};
    localtime_r(&tv.tv_sec, &tmLocal);
    int ms = static_cast<int>(tv.tv_usec / 1000);
    if (includeDate) {
        std::snprintf(outBuf, outCap, "%04d-%02d-%02d %02d:%02d:%02d.%03d",
                      tmLocal.tm_year + 1900, tmLocal.tm_mon + 1, tmLocal.tm_mday,
                      tmLocal.tm_hour, tmLocal.tm_min, tmLocal.tm_sec, ms);
    } else {
        std::snprintf(outBuf, outCap, "%02d:%02d:%02d.%03d",
                      tmLocal.tm_hour, tmLocal.tm_min, tmLocal.tm_sec, ms);
    }
}

static double QueryPhysFootprintMB() {
    task_vm_info_data_t vmInfo{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&vmInfo), &count) == KERN_SUCCESS) {
        return static_cast<double>(vmInfo.phys_footprint) / (1024.0 * 1024.0);
    }
    return -1.0;
}

static double QueryAvailableMemoryMB() {
#if defined(__APPLE__) && TARGET_OS_IOS
    size_t avail = os_proc_available_memory();
    return static_cast<double>(avail) / (1024.0 * 1024.0);
#else
    return -1.0;
#endif
}

static const char *QueryThermalStateString() {
    if (@available(iOS 11.0, *)) {
        switch ([NSProcessInfo processInfo].thermalState) {
            case NSProcessInfoThermalStateNominal:  return "Nominal";
            case NSProcessInfoThermalStateFair:     return "Fair";
            case NSProcessInfoThermalStateSerious:  return "Serious";
            case NSProcessInfoThermalStateCritical: return "Critical";
            default:                                return "Unknown";
        }
    }
    return "N/A";
}

static std::string QueryAudioRouteSummary() {
    @autoreleasepool {
        @try {
            AVAudioSessionRouteDescription *route = [AVAudioSession sharedInstance].currentRoute;
            if (route.outputs.count > 0) {
                AVAudioSessionPortDescription *outPort = route.outputs.firstObject;
                if (outPort.portType) {
                    return std::string(outPort.portType.UTF8String);
                }
            }
        } @catch (NSException *ex) {
            (void)ex;
        }
    }
    return "Unknown";
}

static void PushRingLogLine(const char *levelTag, const char *source, const char *msg, size_t msgLen) {
    char ts[24];
    FormatWallTimestamp(ts, sizeof(ts), false);

    uint64_t seq = g_crashRingSeq.fetch_add(1, std::memory_order_relaxed);
    char *slot = g_crashRingLines[seq & (kCrashRingCapacity - 1)];

    int written = std::snprintf(slot, kCrashRingLineMax, "[%s] %s [%s] %.*s",
                                ts,
                                levelTag ? levelTag : "[INFO]",
                                source ? source : "*",
                                static_cast<int>(msgLen > 180 ? 180 : msgLen),
                                msg ? msg : "");
    if (written < 0) {
        slot[0] = '\0';
    } else {
        size_t len = static_cast<size_t>(written);
        if (len >= kCrashRingLineMax) len = kCrashRingLineMax - 1;
        // Rimuovi eventuali newline interni per mantenere una riga pulita
        for (size_t i = 0; i < len; ++i) {
            if (slot[i] == '\n' || slot[i] == '\r') slot[i] = ' ';
        }
        slot[len] = '\0';
    }

    // Se la cattura manuale LOG (10s) e attiva, accoda subito la riga anche nel buffer di cattura
    if (g_captureActive.load(std::memory_order_relaxed)) {
        std::lock_guard<std::mutex> lock(g_captureMutex);
        if (g_captureLiveLines.size() < 4096) {
            g_captureLiveLines.emplace_back(slot);
        }
    }
}

static void RotateCrashLogIfOversized() {
    if (g_crashLogPath[0] == '\0') return;
    struct stat st{};
    if (::stat(g_crashLogPath, &st) == 0 && st.st_size > (2 * 1024 * 1024)) {
        std::error_code ec;
        std::filesystem::create_directories(std::filesystem::path(g_crashPrevPath).parent_path(), ec);
        std::filesystem::rename(g_crashLogPath, g_crashPrevPath, ec);
    }
}

static void NotifyCaptureCallback(bool capturing, int remainingSec, bool savedOk) {
    ShadowCrashLogStateCallback cb = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_captureCbMutex);
        cb = g_captureStateCb;
    }
    if (!cb) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        cb(capturing, remainingSec, savedOk);
    });
}

static std::string ReadLatestUpstreamLogTail(size_t maxLines) {
    if (g_logsDirPath[0] == '\0') return {};
    std::error_code ec;
    std::filesystem::path logsDir(g_logsDirPath);
    if (!std::filesystem::exists(logsDir, ec)) return {};

    std::filesystem::path newestFile;
    std::filesystem::file_time_type newestTime{};
    bool found = false;
    for (const auto &entry : std::filesystem::directory_iterator(logsDir, ec)) {
        if (!entry.is_regular_file(ec)) continue;
        std::string name = entry.path().filename().string();
        if (name == "crashlog_prev.txt") continue;
        auto ft = entry.last_write_time(ec);
        if (!ec && (!found || ft > newestTime)) {
            newestTime = ft;
            newestFile = entry.path();
            found = true;
        }
    }
    if (!found) return {};

    std::ifstream ifs(newestFile, std::ios::in);
    if (!ifs.is_open()) return {};
    std::vector<std::string> ring(maxLines);
    size_t count = 0;
    std::string line;
    while (std::getline(ifs, line)) {
        ring[count % maxLines] = line;
        ++count;
    }
    if (count == 0) return {};

    std::string out = "Source file: logs/" + newestFile.filename().string() + "\n";
    size_t start = count > maxLines ? (count - maxLines) : 0;
    for (size_t i = start; i < count; ++i) {
        out += ring[i % maxLines];
        out += "\n";
    }
    return out;
}

static void WriteRingBufferAsyncSafe(int fd) {
    SafeWriteStr(fd, "\n--- Recent Engine / SDL3 / Runtime Events (Ring Buffer) ---\n");
    uint64_t total = g_crashRingSeq.load(std::memory_order_relaxed);
    uint64_t count = total < kCrashRingCapacity ? total : kCrashRingCapacity;
    uint64_t start = total - count;
    for (uint64_t i = start; i < total; ++i) {
        const char *line = g_crashRingLines[i & (kCrashRingCapacity - 1)];
        if (line[0] != '\0') {
            SafeWriteStr(fd, line);
            SafeWriteStr(fd, "\n");
        }
    }
}

static const char *SignalNameFromNumber(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV (Invalid Memory Access)";
        case SIGBUS:  return "SIGBUS (Bus / Alignment Fault)";
        case SIGABRT: return "SIGABRT (Abort / Assertion Failure)";
        case SIGILL:  return "SIGILL (Illegal ARM64 Instruction)";
        case SIGFPE:  return "SIGFPE (Floating-Point / Arithmetic Fault)";
        case SIGTRAP: return "SIGTRAP (Breakpoint / Trap)";
        default:      return "UNKNOWN_SIGNAL";
    }
}

static void PosixCrashSignalHandler(int sig, siginfo_t *info, void *ucontext) {
    (void)ucontext;
    if (g_inCrashHandler.exchange(1, std::memory_order_acq_rel) == 0 && g_crashLogPath[0] != '\0') {
        int fd = ::open(g_crashLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            struct timeval tv{};
            gettimeofday(&tv, nullptr);
            struct tm tmLocal{};
            localtime_r(&tv.tv_sec, &tmLocal);

            SafeWriteStr(fd, "\n====================================================================\n");
            SafeWriteStr(fd, "EDGYIOS CRASH REPORT [AUTO-CRASH / POSIX SIGNAL]\n");
            SafeWriteStr(fd, "====================================================================\n");
            SafeWriteStr(fd, "Timestamp: ");
            SafeWriteInt(fd, tmLocal.tm_year + 1900); SafeWriteStr(fd, "-");
            if (tmLocal.tm_mon + 1 < 10) SafeWriteStr(fd, "0");
            SafeWriteInt(fd, tmLocal.tm_mon + 1); SafeWriteStr(fd, "-");
            if (tmLocal.tm_mday < 10) SafeWriteStr(fd, "0");
            SafeWriteInt(fd, tmLocal.tm_mday); SafeWriteStr(fd, " ");
            if (tmLocal.tm_hour < 10) SafeWriteStr(fd, "0");
            SafeWriteInt(fd, tmLocal.tm_hour); SafeWriteStr(fd, ":");
            if (tmLocal.tm_min < 10) SafeWriteStr(fd, "0");
            SafeWriteInt(fd, tmLocal.tm_min); SafeWriteStr(fd, ":");
            if (tmLocal.tm_sec < 10) SafeWriteStr(fd, "0");
            SafeWriteInt(fd, tmLocal.tm_sec); SafeWriteStr(fd, "\n");

            if (g_deviceBanner[0] != '\0') {
                SafeWriteStr(fd, g_deviceBanner);
                SafeWriteStr(fd, "\n");
            }
            SafeWriteStr(fd, "Anomaly: ");
            SafeWriteStr(fd, SignalNameFromNumber(sig));
            SafeWriteStr(fd, " (sig=");
            SafeWriteInt(fd, sig);
            if (info) {
                SafeWriteStr(fd, ", si_code=");
                SafeWriteInt(fd, info->si_code);
                SafeWriteStr(fd, ", fault_addr=");
                SafeWriteHex(fd, reinterpret_cast<uintptr_t>(info->si_addr));
            }
            SafeWriteStr(fd, ")\nImage ASLR Slide: ");
            SafeWriteHex(fd, static_cast<uintptr_t>(_dyld_get_image_vmaddr_slide(0)));
            SafeWriteStr(fd, "\nRuntime: TVMode=");
            SafeWriteStr(fd, g_ctxTVMode.load(std::memory_order_relaxed) ? "ON" : "OFF");
            SafeWriteStr(fd, " | 2P=");
            SafeWriteStr(fd, g_ctxP2Active.load(std::memory_order_relaxed) ? "ON" : "OFF");
            SafeWriteStr(fd, " (Connected=");
            SafeWriteStr(fd, g_ctxP2Connected.load(std::memory_order_relaxed) ? "YES" : "NO");
            SafeWriteStr(fd, ") | PhysicalPad=");
            SafeWriteStr(fd, g_ctxPhysicalPad.load(std::memory_order_relaxed) ? "YES" : "NO");
            SafeWriteStr(fd, " | FrameTicks=");
            SafeWriteInt(fd, static_cast<int64_t>(g_frameTickCounter.load(std::memory_order_relaxed)));
            SafeWriteStr(fd, "\n\n--- Native ARM64 Stack Trace ---\n");

            void *frames[64];
            int frameCount = ::backtrace(frames, 64);
            if (frameCount > 0) {
                ::backtrace_symbols_fd(frames, frameCount, fd);
            }

            WriteRingBufferAsyncSafe(fd);
            SafeWriteStr(fd, "====================================================================\n");
            ::fsync(fd);
            ::close(fd);
        }
    }

    // Ripristina handler di default e rilancia il segnale per chiusura pulita iOS
    signal(sig, SIG_DFL);
    raise(sig);
}

static void WriteManagedAnomalyReport(const char *reportType, const std::string &anomalySummary, const std::string &extraStack) {
    if (g_crashLogPath[0] == '\0') return;
    std::lock_guard<std::mutex> lock(g_logMutex);
    RotateCrashLogIfOversized();

    char ts[40];
    FormatWallTimestamp(ts, sizeof(ts), true);
    double memMB = QueryPhysFootprintMB();
    double availMB = QueryAvailableMemoryMB();

    std::ofstream ofs(g_crashLogPath, std::ios::app);
    if (!ofs.is_open()) return;

    ofs << "\n====================================================================\n";
    ofs << "EDGYIOS CRASH REPORT [" << (reportType ? reportType : "ANOMALY") << "]\n";
    ofs << "====================================================================\n";
    ofs << "Timestamp: " << ts << "\n";
    if (g_deviceBanner[0] != '\0') ofs << g_deviceBanner << "\n";
    ofs << "Runtime: TVMode=" << (g_ctxTVMode.load(std::memory_order_relaxed) ? "ON" : "OFF")
        << " | 2P=" << (g_ctxP2Active.load(std::memory_order_relaxed) ? "ON" : "OFF")
        << " (Connected=" << (g_ctxP2Connected.load(std::memory_order_relaxed) ? "YES" : "NO") << ")"
        << " | PhysicalPad=" << (g_ctxPhysicalPad.load(std::memory_order_relaxed) ? "YES" : "NO")
        << " | Audio=" << QueryAudioRouteSummary() << "\n";
    char memLine[160];
    std::snprintf(memLine, sizeof(memLine), "Memory: Footprint=%.1f MB | Available=%.1f MB | Thermal=%s",
                  memMB, availMB, QueryThermalStateString());
    ofs << memLine << "\n";
    ofs << "Anomaly: " << anomalySummary << "\n";
    if (!extraStack.empty()) {
        ofs << "\n--- Stack Trace ---\n" << extraStack << "\n";
    }
    ofs << "\n--- Recent Engine / SDL3 / Runtime Events (Ring Buffer) ---\n";
    uint64_t total = g_crashRingSeq.load(std::memory_order_relaxed);
    uint64_t count = total < kCrashRingCapacity ? total : kCrashRingCapacity;
    uint64_t start = total - count;
    for (uint64_t i = start; i < total; ++i) {
        const char *line = g_crashRingLines[i & (kCrashRingCapacity - 1)];
        if (line[0] != '\0') ofs << line << "\n";
    }
    ofs << "====================================================================\n";
    ofs.flush();
}

static void EdgyIOSUncaughtNSExceptionHandler(NSException *exception) {
    @autoreleasepool {
        std::string summary = "NSException: ";
        summary += exception.name ? exception.name.UTF8String : "Unknown";
        summary += " | Reason: ";
        summary += exception.reason ? exception.reason.UTF8String : "(none)";

        std::string stack;
        for (NSString *sym in exception.callStackSymbols) {
            stack += sym.UTF8String;
            stack += "\n";
        }
        WriteManagedAnomalyReport("AUTO-CRASH / NSException", summary, stack);
    }
    if (g_prevNSExceptionHandler) {
        g_prevNSExceptionHandler(exception);
    }
}

static void EdgyIOSTerminateHandler() {
    std::string summary = "std::terminate invoked";
    try {
        auto ep = std::current_exception();
        if (ep) {
            std::rethrow_exception(ep);
        }
    } catch (const std::exception &ex) {
        summary += " | std::exception: ";
        summary += ex.what();
    } catch (...) {
        summary += " | unknown C++ exception";
    }

    void *frames[48];
    int count = ::backtrace(frames, 48);
    std::string stack;
    char **syms = ::backtrace_symbols(frames, count);
    if (syms) {
        for (int i = 0; i < count; ++i) {
            stack += syms[i];
            stack += "\n";
        }
        std::free(syms);
    }
    WriteManagedAnomalyReport("AUTO-CRASH / C++ Terminate", summary, stack);
    if (g_prevTerminateHandler) {
        g_prevTerminateHandler();
    }
    std::abort();
}

static void SDLCALL EdgyIOSSdlLogCallback(void *userdata, int category, SDL_LogPriority priority, const char *message) {
    (void)userdata;
    if (!message) return;
    const char *tag = "[SDL3]";
    if (priority >= SDL_LOG_PRIORITY_ERROR) tag = "[SDL3-ERR]";
    else if (priority == SDL_LOG_PRIORITY_WARN) tag = "[SDL3-WARN]";

    char catBuf[24];
    std::snprintf(catBuf, sizeof(catBuf), "SDL:%d", category);
    PushRingLogLine(tag, catBuf, message, std::strlen(message));

    if (priority >= SDL_LOG_PRIORITY_WARN) {
        std::fprintf(stderr, "EdgyiOS %s [%s] %s\n", tag, catBuf, message);
    }
}

static void FlushManualDiagnosticCaptureLocked(const char *reason) {
    if (g_captureTimer) {
        dispatch_source_cancel(g_captureTimer);
        g_captureTimer = nil;
    }
    g_captureActive.store(false, std::memory_order_release);
    g_captureRemainingSec.store(0, std::memory_order_release);

    std::vector<std::string> preCtx;
    std::vector<std::string> liveLines;
    std::string startTs;
    int totalSec = g_captureTotalSec.load(std::memory_order_relaxed);
    preCtx.swap(g_capturePreContext);
    liveLines.swap(g_captureLiveLines);
    startTs.swap(g_captureStartTimestamp);

    bool savedOk = false;
    if (g_crashLogPath[0] != '\0') {
        std::lock_guard<std::mutex> fileLock(g_logMutex);
        RotateCrashLogIfOversized();

        char endTs[40];
        FormatWallTimestamp(endTs, sizeof(endTs), true);
        double memMB = QueryPhysFootprintMB();
        double availMB = QueryAvailableMemoryMB();

        std::ofstream ofs(g_crashLogPath, std::ios::app);
        if (ofs.is_open()) {
            ofs << "\n====================================================================\n";
            ofs << "EDGYIOS DIAGNOSTIC LOG [MANUAL CAPTURE - " << totalSec << "s]\n";
            ofs << "====================================================================\n";
            ofs << "Start Time: " << startTs << "\n";
            ofs << "End Time:   " << endTs << "\n";
            ofs << "Reason:     " << (reason ? reason : "Manual LOG capture completed") << "\n";
            if (g_deviceBanner[0] != '\0') ofs << g_deviceBanner << "\n";
            ofs << "Runtime:    TVMode=" << (g_ctxTVMode.load(std::memory_order_relaxed) ? "ON" : "OFF")
                << " | 2P=" << (g_ctxP2Active.load(std::memory_order_relaxed) ? "ON" : "OFF")
                << " (Connected=" << (g_ctxP2Connected.load(std::memory_order_relaxed) ? "YES" : "NO") << ")"
                << " | PhysicalPad=" << (g_ctxPhysicalPad.load(std::memory_order_relaxed) ? "YES" : "NO")
                << " | Audio=" << QueryAudioRouteSummary() << "\n";
            char resLine[160];
            std::snprintf(resLine, sizeof(resLine), "Resources:  Footprint=%.1f MB | Available=%.1f MB | Thermal=%s",
                          memMB, availMB, QueryThermalStateString());
            ofs << resLine << "\n";

            ofs << "\n--- Pre-Trigger Context (events right before LOG button was tapped) ---\n";
            if (preCtx.empty()) {
                ofs << "(no pre-trigger engine events recorded yet)\n";
            } else {
                for (const auto &line : preCtx) ofs << line << "\n";
            }

            ofs << "\n--- Live Capture Window (1Hz Telemetry + Engine / SDL3 / Metal / Audio Events) ---\n";
            for (const auto &line : liveLines) ofs << line << "\n";

            std::string upstreamTail = ReadLatestUpstreamLogTail(30);
            if (!upstreamTail.empty()) {
                ofs << "\n--- Latest Upstream Log Tail (ShadowRecomp/logs/) ---\n" << upstreamTail;
            }
            ofs << "====================================================================\n";
            ofs.flush();
            savedOk = ofs.good();
        }
    }

    NotifyCaptureCallback(false, 0, savedOk);
}

static void InstallCrashLogInfrastructure() {
    auto rootDir = GetIOSDocumentsDir() / "ShadowRecomp";
    auto logsDir = rootDir / "logs";
    std::error_code ec;
    std::filesystem::create_directories(logsDir, ec);

    std::string crashPath = (rootDir / "crashlog.txt").string();
    std::string prevPath  = (logsDir / "crashlog_prev.txt").string();
    std::string logsPath  = logsDir.string();
    std::snprintf(g_crashLogPath, sizeof(g_crashLogPath), "%s", crashPath.c_str());
    std::snprintf(g_crashPrevPath, sizeof(g_crashPrevPath), "%s", prevPath.c_str());
    std::snprintf(g_logsDirPath, sizeof(g_logsDirPath), "%s", logsPath.c_str());

    struct utsname uts{};
    uname(&uts);
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *appName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"EdgyiOS";
        NSString *bundleId = bundle.bundleIdentifier ?: @"com.hiperema.edgyios.ios";
        NSString *shortVer = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
        NSString *buildVer = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
        NSString *sysVer = [NSProcessInfo processInfo].operatingSystemVersionString ?: @"iOS 17+";
        unsigned long long totalRamMB = [NSProcessInfo processInfo].physicalMemory / (1024ULL * 1024ULL);
        NSUInteger cpuCount = [NSProcessInfo processInfo].processorCount;

        std::snprintf(g_deviceBanner, sizeof(g_deviceBanner),
                      "App: %s %s (build %s, %s) | Device: %s | OS: %s | CPUs: %lu | TotalRAM: %llu MB",
                      appName.UTF8String, shortVer.UTF8String, buildVer.UTF8String, bundleId.UTF8String,
                      uts.machine, sysVer.UTF8String, static_cast<unsigned long>(cpuCount), totalRamMB);
    }

    // Stack alternativo per gestire anche stack overflow SIGSEGV
    stack_t ss{};
    ss.ss_sp = g_altSigStackMem;
    ss.ss_size = sizeof(g_altSigStackMem);
    ss.ss_flags = 0;
    sigaltstack(&ss, nullptr);

    struct sigaction sa{};
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = &PosixCrashSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
    const int kFatalSigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP };
    for (int sig : kFatalSigs) {
        sigaction(sig, &sa, nullptr);
    }

    g_prevNSExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&EdgyIOSUncaughtNSExceptionHandler);
    g_prevTerminateHandler = std::set_terminate(&EdgyIOSTerminateHandler);

    SDL_SetLogOutputFunction(&EdgyIOSSdlLogCallback, nullptr);
    PushRingLogLine("[BOOT]", "EdgyiOS", g_deviceBanner, std::strlen(g_deviceBanner));
}

void InitializeIOSRuntimeOnce() {
    std::call_once(g_iosRuntimeInitOnce, []() {
        InstallCrashLogInfrastructure();

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
            @try {
                AVAudioSession *session = [AVAudioSession sharedInstance];
                NSError *err = nil;
                [session setCategory:AVAudioSessionCategoryAmbient error:&err];
                [session setPreferredSampleRate:48000.0 error:nil];
                [session setPreferredIOBufferDuration:0.021333 error:nil];
                [session setActive:YES error:&err];
            } @catch (NSException *ex) {
                (void)ex;
            }

            // Osservatori UIKit sincroni (queue:nil) per bloccare/riprendere Metal PRIMA che iOS
            // revochi la GPU su blocco schermo o swipe Home — funziona anche dentro LiveContainer!
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            g_iosWillResignObserver = [nc addObserverForName:UIApplicationWillResignActiveNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
                (void)note;
                PushRingLogLine("[LIFE]", "UIKit", "UIApplicationWillResignActive -> parking Metal", 45);
                ShadowIOS_VideoOnWillEnterBackground();
            }];
            g_iosDidEnterBgObserver = [nc addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
                (void)note;
                PushRingLogLine("[LIFE]", "UIKit", "UIApplicationDidEnterBackground", 31);
                ShadowIOS_VideoOnWillEnterBackground();
            }];
            g_iosDidBecomeActiveObserver = [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                                                           object:nil
                                                            queue:nil
                                                       usingBlock:^(NSNotification * _Nonnull note) {
                (void)note;
                PushRingLogLine("[LIFE]", "UIKit", "UIApplicationDidBecomeActive -> resuming Metal", 46);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIApplication sharedApplication].idleTimerDisabled = YES;
                });
                @try {
                    [[AVAudioSession sharedInstance] setActive:YES error:nil];
                } @catch (NSException *ex) {
                    (void)ex;
                }
                ShadowIOS_VideoOnDidEnterForeground();
            }];
            g_iosMemWarnObserver = [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil
                                                    queue:nil
                                               usingBlock:^(NSNotification * _Nonnull note) {
                (void)note;
                double memMB = QueryPhysFootprintMB();
                double availMB = QueryAvailableMemoryMB();
                char buf[160];
                std::snprintf(buf, sizeof(buf), "iOS Memory Warning! phys_footprint=%.1f MB, avail=%.1f MB (possible Jetsam risk)", memMB, availMB);
                PushRingLogLine("[MEMWARN]", "iOS", buf, std::strlen(buf));
                WriteManagedAnomalyReport("AUTO-MEMORY-WARNING / JETSAM RISK", buf, "");
            }];
        }
    });
}
} // namespace

extern "C" {

void ShadowIOS_CrashLogRecordBreadcrumb(const char *tag, const char *message) {
    InitializeIOSRuntimeOnce();
    if (!message) return;
    PushRingLogLine("[EVT ]", tag ? tag : "iOS", message, std::strlen(message));
}

void ShadowIOS_CrashLogSetRuntimeContext(bool tvMode, bool p2Active, bool p2Connected, bool physicalCtrl) {
    g_ctxTVMode.store(tvMode, std::memory_order_relaxed);
    g_ctxP2Active.store(p2Active, std::memory_order_relaxed);
    g_ctxP2Connected.store(p2Connected, std::memory_order_relaxed);
    g_ctxPhysicalPad.store(physicalCtrl, std::memory_order_relaxed);
}

void ShadowIOS_CrashLogNotifyFrame(void) {
    g_frameTickCounter.fetch_add(1, std::memory_order_relaxed);
}

void ShadowIOS_CrashLogSetCallback(ShadowCrashLogStateCallback cb) {
    std::lock_guard<std::mutex> lock(g_captureCbMutex);
    g_captureStateCb = cb;
}

bool ShadowIOS_CrashLogIsCapturing(void) {
    return g_captureActive.load(std::memory_order_acquire);
}

int ShadowIOS_CrashLogRemainingSeconds(void) {
    return g_captureRemainingSec.load(std::memory_order_acquire);
}

bool ShadowIOS_CrashLogStartCapture(int durationSeconds) {
    InitializeIOSRuntimeOnce();
    if (durationSeconds < 3) durationSeconds = 3;
    if (durationSeconds > 30) durationSeconds = 30;

    std::lock_guard<std::mutex> lock(g_captureMutex);
    if (g_captureActive.load(std::memory_order_acquire)) {
        return false;
    }

    // Cattura contesto pre-trigger dal ring buffer (ultime 120 righe prima del tap su LOG)
    g_capturePreContext.clear();
    uint64_t total = g_crashRingSeq.load(std::memory_order_relaxed);
    uint64_t count = total < 120 ? total : 120;
    uint64_t start = total - count;
    for (uint64_t i = start; i < total; ++i) {
        const char *line = g_crashRingLines[i & (kCrashRingCapacity - 1)];
        if (line[0] != '\0') g_capturePreContext.emplace_back(line);
    }

    char startTs[40];
    FormatWallTimestamp(startTs, sizeof(startTs), true);
    g_captureStartTimestamp = startTs;
    g_captureLiveLines.clear();
    g_captureLiveLines.reserve(256);

    g_captureTotalSec.store(durationSeconds, std::memory_order_relaxed);
    g_captureRemainingSec.store(durationSeconds, std::memory_order_release);
    g_capturePrevFrames = g_frameTickCounter.load(std::memory_order_relaxed);
    struct timeval tv{};
    gettimeofday(&tv, nullptr);
    g_capturePrevSampleSec = static_cast<double>(tv.tv_sec) + static_cast<double>(tv.tv_usec) * 1e-6;
    g_captureActive.store(true, std::memory_order_release);

    // Campione immediato T+0s
    {
        char ts[24];
        FormatWallTimestamp(ts, sizeof(ts), false);
        char sampleBuf[256];
        std::snprintf(sampleBuf, sizeof(sampleBuf),
                      "[%s] [SAMPLE T+0s] RAM=%.1f MB (avail=%.1f MB) | Thermal=%s | TV=%s | 2P=%s(%s) | PhysPad=%s",
                      ts, QueryPhysFootprintMB(), QueryAvailableMemoryMB(), QueryThermalStateString(),
                      g_ctxTVMode.load(std::memory_order_relaxed) ? "ON" : "OFF",
                      g_ctxP2Active.load(std::memory_order_relaxed) ? "ON" : "OFF",
                      g_ctxP2Connected.load(std::memory_order_relaxed) ? "Connected" : "Idle",
                      g_ctxPhysicalPad.load(std::memory_order_relaxed) ? "YES" : "NO");
        g_captureLiveLines.emplace_back(sampleBuf);
    }

    if (!g_captureQueue) {
        g_captureQueue = dispatch_queue_create("com.hiperema.edgyios.crashlog", DISPATCH_QUEUE_SERIAL);
    }
    g_captureTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_captureQueue);
    dispatch_source_set_timer(g_captureTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                              (uint64_t)(1 * NSEC_PER_SEC),
                              (uint64_t)(50 * NSEC_PER_MSEC));
    dispatch_source_set_event_handler(g_captureTimer, ^{
        std::lock_guard<std::mutex> tlock(g_captureMutex);
        if (!g_captureActive.load(std::memory_order_acquire)) return;

        struct timeval nowTv{};
        gettimeofday(&nowTv, nullptr);
        double nowSec = static_cast<double>(nowTv.tv_sec) + static_cast<double>(nowTv.tv_usec) * 1e-6;
        double dt = nowSec - g_capturePrevSampleSec;
        if (dt < 0.05) dt = 1.0;
        uint64_t nowFrames = g_frameTickCounter.load(std::memory_order_relaxed);
        double fps = static_cast<double>(nowFrames - g_capturePrevFrames) / dt;
        g_capturePrevFrames = nowFrames;
        g_capturePrevSampleSec = nowSec;

        int rem = g_captureRemainingSec.load(std::memory_order_relaxed) - 1;
        int elapsed = g_captureTotalSec.load(std::memory_order_relaxed) - (rem < 0 ? 0 : rem);
        char ts[24];
        FormatWallTimestamp(ts, sizeof(ts), false);
        char sampleBuf[256];
        std::snprintf(sampleBuf, sizeof(sampleBuf),
                      "[%s] [SAMPLE T+%ds] FPS=%.1f | RAM=%.1f MB (avail=%.1f MB) | Thermal=%s | TV=%s | 2P=%s(%s) | PhysPad=%s",
                      ts, elapsed, fps, QueryPhysFootprintMB(), QueryAvailableMemoryMB(), QueryThermalStateString(),
                      g_ctxTVMode.load(std::memory_order_relaxed) ? "ON" : "OFF",
                      g_ctxP2Active.load(std::memory_order_relaxed) ? "ON" : "OFF",
                      g_ctxP2Connected.load(std::memory_order_relaxed) ? "Connected" : "Idle",
                      g_ctxPhysicalPad.load(std::memory_order_relaxed) ? "YES" : "NO");
        if (g_captureLiveLines.size() < 4096) {
            g_captureLiveLines.emplace_back(sampleBuf);
        }

        if (rem <= 0) {
            FlushManualDiagnosticCaptureLocked("Completed timed diagnostic capture");
        } else {
            g_captureRemainingSec.store(rem, std::memory_order_release);
            NotifyCaptureCallback(true, rem, false);
        }
    });
    dispatch_resume(g_captureTimer);

    NotifyCaptureCallback(true, durationSeconds, false);
    return true;
}

void ShadowIOS_CrashLogStopAndFlush(const char *reason) {
    std::lock_guard<std::mutex> lock(g_captureMutex);
    if (!g_captureActive.load(std::memory_order_acquire)) return;
    FlushManualDiagnosticCaptureLocked(reason ? reason : "User stopped diagnostic capture early");
}

} // extern "C"

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

    PushRingLogLine(prefix, func ? func : "*", str.data(), str.size());
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