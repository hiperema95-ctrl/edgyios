import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import {
  DEFAULT_BUILD_CONFIG,
  generateGitHubWorkflowYaml,
  generateAllRepositoryFiles,
  generateShadowRecompModProfileJson,
} from './portGenerator';
import { buildZipArchiveBytes } from './zipBuilder';

test('default upstream branch is master (matches FoxWorkshop/ShadowRecomp)', () => {
  assert.equal(DEFAULT_BUILD_CONFIG.upstreamBranch, 'master');
  const yml = generateGitHubWorkflowYaml(DEFAULT_BUILD_CONFIG);
  assert.match(yml, /default:\s*'master'/);
  assert.match(yml, /git ls-remote --exit-code --heads/);
});

test('GitHub Actions workflow builds host XboxRecomp2, file_to_c, MoltenVK, and unsigned IPA', () => {
  const yml = generateGitHubWorkflowYaml(DEFAULT_BUILD_CONFIG);
  assert.match(yml, /runs-on:\s*macos-15/);
  assert.match(yml, /git submodule status/);
  assert.match(yml, /-p xbox-recomp2-cli/);
  assert.match(yml, /dxc-wrapper\.sh/);
  assert.match(yml, /tools\/file_to_c\/file_to_c\.cpp/);
  assert.match(yml, /MoltenVK-ios\.tar/);
  assert.match(yml, /DSHADOW_RECOMP_XBOXRECOMP2_EXECUTABLE=/);
  assert.match(yml, /DPLUME_SDL3_VULKAN_ENABLED=ON/);
  assert.match(yml, /cmake -B build-ios -G Ninja/);
  assert.match(yml, /ldid -Sios-port\/ios\/Entitlements\.plist/);
  assert.match(yml, /ShadowRecompLib\/private\/default\.xbe/);
});

test('generated repository contains real ShadowRecomp iOS patches and NFD Files picker', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';
  assert.match(applyScript, /ShadowRecomp\/user\/paths\.cpp/);
  assert.match(applyScript, /ShadowRecomp\/os\/registry\.h/);
  assert.match(applyScript, /ShadowRecomp\/ui\/game_window\.cpp/);
  assert.match(applyScript, /thirdparty\/plume\/CMakeLists\.txt/);
  assert.match(applyScript, /ShadowRecompLib\/CMakeLists\.txt/);

  const nfdMm = byPath.get('ios/nfd_ios.mm') ?? '';
  assert.match(nfdMm, /UIDocumentPickerViewController/);
  assert.match(nfdMm, /NFD_OpenDialogU8/);
  assert.match(nfdMm, /NFD_PickFolderU8/);

  const modMgr = byPath.get('ios/ios_mod_manager.mm') ?? '';
  assert.match(modMgr, /profiles\.json/);
  assert.match(modMgr, /Default\.json/);
  assert.match(modMgr, /EnabledMods/);

  const plist = byPath.get('ios/Info.plist') ?? '';
  assert.match(plist, /UIFileSharingEnabled/);
  assert.match(plist, /LSSupportsOpeningDocumentsInPlace/);
  assert.match(plist, /CADisableMinimumFrameDurationOnPhone/);
});

test('generateShadowRecompModProfileJson matches ModLoader::Init() schema', () => {
  const { profilesJson, defaultProfileJson } = generateShadowRecompModProfileJson([
    { folderName: 'Shadow_Reloaded', name: 'Reloaded', author: 'LV', version: '1.0', enabled: true },
    { folderName: 'Disabled_Mod', name: 'Off', author: 'Test', version: '1.0', enabled: false },
  ]);
  const profiles = JSON.parse(profilesJson);
  const def = JSON.parse(defaultProfileJson);
  assert.equal(profiles.ProfileIndex, 0);
  assert.equal(profiles.ProfilesList[0].Filename, 'Default.json');
  assert.deepEqual(def.EnabledMods, ['Shadow_Reloaded']);
});

test('buildZipArchiveBytes generates valid PKZIP binary containing all 18 files including .gitignore', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  assert.equal(files.length, 18);
  const gitignore = files.find((f) => f.path === '.gitignore')?.content ?? '';
  assert.match(gitignore, /\*\.xbe/);
  assert.match(gitignore, /\*\.xiso/);
  assert.match(gitignore, /private\//);
  const yml = files.find((f) => f.path === '.github/workflows/build-ios-ipa.yml')?.content ?? '';
  assert.match(yml, /publish_release/);

  const zip = buildZipArchiveBytes(files.map((f) => ({ path: f.path, content: f.content })));
  // Local file header signature: PK\x03\x04
  assert.equal(zip[0], 0x50);
  assert.equal(zip[1], 0x4b);
  assert.equal(zip[2], 0x03);
  assert.equal(zip[3], 0x04);
  // End of central directory signature: PK\x05\x06 at last 22 bytes
  const eocdOffset = zip.length - 22;
  assert.equal(zip[eocdOffset], 0x50);
  assert.equal(zip[eocdOffset + 1], 0x4b);
  assert.equal(zip[eocdOffset + 2], 0x05);
  assert.equal(zip[eocdOffset + 3], 0x06);
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  assert.equal(view.getUint16(eocdOffset + 8, true), files.length);
});

test('scripts/apply_ios_port.sh has valid bash syntax and valid Python AST in all PY_* heredocs', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const applyScript = files.find((f) => f.path === 'scripts/apply_ios_port.sh')?.content ?? '';
  assert.ok(applyScript.length > 0);

  // Validate bash syntax via `bash -n`
  execFileSync('bash', ['-n'], { input: applyScript, encoding: 'utf-8' });

  // Extract and validate every Python heredoc (`<< 'PY_...'` ... `PY_...`)
  const heredocRegex = /<<\s*'(PY_[A-Z0-9_]+)'\n([\s\S]*?)\n\1(?:\n|$)/g;
  const blocks: Array<{ tag: string; code: string }> = [];
  let match: RegExpExecArray | null;
  while ((match = heredocRegex.exec(applyScript)) !== null) {
    blocks.push({ tag: match[1], code: match[2] });
  }
  assert.equal(blocks.length, 6, `Expected 6 Python heredoc blocks, found ${blocks.length}`);

  for (const { tag, code } of blocks) {
    assert.doesNotThrow(
      () => {
        execFileSync('python3', ['-c', 'import ast, sys; ast.parse(sys.stdin.read())'], {
          input: code,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      },
      `Python AST syntax error in heredoc ${tag}`
    );
  }
});

test('Step 4 dxc-wrapper.sh preserves literal "$@" and DYLD_LIBRARY_PATH when executed by bash', () => {
  const yml = generateGitHubWorkflowYaml(DEFAULT_BUILD_CONFIG);
  assert.match(yml, /exec "\$\{DXC_DIR\}\/bin\/arm64\/dxc-macos" "\\\$@"/);
  assert.match(yml, /grep -Fq '"\$@"' "\$\{GITHUB_WORKSPACE\}\/build-host\/dxc-wrapper\.sh"/);

  const match = yml.match(/cat << EOF_DXC > ".*?"\n([\s\S]*?)\n\s*EOF_DXC/);
  assert.ok(match, 'Expected EOF_DXC heredoc in workflow YAML');
  const script = match[0].replace(/^ {10}/gm, '');
  const generated = execFileSync(
    'bash',
    [
      '-euo',
      'pipefail',
      '-c',
      `TMP_WS="$(mktemp -d)"
mkdir -p "\${TMP_WS}/build-host"
GITHUB_WORKSPACE="\${TMP_WS}"
DXC_DIR="/opt/dxc-bin"
${script}
cat "\${TMP_WS}/build-host/dxc-wrapper.sh"
rm -rf "\${TMP_WS}"`,
    ],
    { encoding: 'utf-8' }
  );
  assert.match(generated, /exec "\/opt\/dxc-bin\/bin\/arm64\/dxc-macos" "\$@"/);
  assert.match(generated, /export DYLD_LIBRARY_PATH="\/opt\/dxc-bin\/lib\/arm64:\$\{DYLD_LIBRARY_PATH:-\}"/);
});

test('all audited Step 8 iOS arm64 patches and FreeType/zlib linking are present', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';
  assert.match(applyScript, /#elif defined\(__linux__\) \|\| defined\(__APPLE__\)/);
  assert.match(applyScript, /defined\(__x86_64__\) \|\| defined\(__i386__\)/);
  assert.match(applyScript, /SDL_OpenURL\(VISIT_URL\)/);
  assert.match(applyScript, /#include <SDL3\/SDL_main\.h>/);
  assert.match(applyScript, /os::process::GetWorkingDirectory\(\)/);
  assert.match(applyScript, /static std::filesystem::path s_userPath = BuildUserPath\(\);/);
  assert.match(applyScript, /SHADOW_IOS_ATOMIC_REF_POLYFILL/);
  assert.match(applyScript, /!defined\(__cpp_lib_atomic_ref\)/);
  assert.match(applyScript, /class atomic_ref/);
  assert.match(applyScript, /compare_exchange_weak/);
  assert.match(applyScript, /void wait\(T old/);
  assert.match(applyScript, /void notify_one\(\)/);
  assert.match(applyScript, /atomic_ref\(T&\) -> atomic_ref<T>;/);
  assert.match(applyScript, /CocoaWindow::~CocoaWindow\(\) = default;/);
  assert.match(applyScript, /RenderDeviceVendor getRenderDeviceVendor\(uint64_t\)/);
  assert.match(applyScript, /CocoaWindow::CocoaWindow\(void\* window\)/);
  assert.match(applyScript, /SHADOW_IOS_VOLK_NAMESPACE/);
  assert.match(applyScript, /namespace plume_volk \{/);
  assert.match(applyScript, /using namespace plume_volk;/);
  assert.match(applyScript, /shadow_ios_moltenvk_vkGetInstanceProcAddr/);
  assert.match(applyScript, /__asm__\("_vkGetInstanceProcAddr"\)/);

  const cmakeIos = byPath.get('cmake/ShadowRecompIOS.cmake') ?? '';
  assert.match(cmakeIos, /find_package\(Freetype REQUIRED\)/);
  assert.match(cmakeIos, /Freetype::Freetype/);
  assert.match(cmakeIos, /"-lz"/);
  assert.doesNotMatch(cmakeIos, /PLUME_SDL_VULKAN_ENABLED=1/);

  const iosPlatform = byPath.get('ios/os/ios_platform.mm') ?? '';
  assert.match(iosPlatform, /#include <cstdint>/);
  assert.match(iosPlatform, /AVAudioSessionCategoryAmbient/);
  assert.match(iosPlatform, /SDL_HINT_VIDEO_ALLOW_SCREENSAVER/);
  assert.match(iosPlatform, /idleTimerDisabled = YES/);
  assert.match(iosPlatform, /bool IsSupported\(\)\s*\{\s*return false;/);
  assert.match(iosPlatform, /bool IsExternalMediaPlaying\(\)\s*\{\s*return false;/);
  assert.doesNotMatch(iosPlatform, /NSLog\(@/);

  const iosModMgr = byPath.get('ios/ios_mod_manager.mm') ?? '';
  assert.match(iosModMgr, /#include <string_view>/);
});

test('iOS ARM64 runtime stability fixes are included in scripts/apply_ios_port.sh', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const applyScript = files.find((f) => f.path === 'scripts/apply_ios_port.sh')?.content ?? '';

  // 1. ARM64 compare_exchange_weak spurious-failure deadlock fix
  assert.match(applyScript, /SHADOW_IOS_ARM64_CAS_FIX/);
  assert.match(applyScript, /signaled\.compare_exchange_strong\(expected, false\)/);
  assert.match(applyScript, /owningThread\.compare_exchange_strong\(previousOwner, thisThread\)/);
  assert.match(applyScript, /wait_for\(lock, std::chrono::milliseconds\(5\)\)/);

  // 2. 8 MB pthread stack for GuestThread and RenderThread + autoreleasepool drain
  assert.match(applyScript, /SHADOW_IOS_PTHREAD_STACK/);
  assert.match(applyScript, /pthread_attr_setstacksize\(&attr, 8 \* 1024 \* 1024\)/);
  assert.match(applyScript, /pthread_threadid_np/);
  assert.match(applyScript, /objc_autoreleasePoolPush\(\)/);
  assert.match(applyScript, /objc_autoreleasePoolPop\(iosArp\)/);

  // 3. Post-install double shader/pipeline precompile crash fix
  assert.match(applyScript, /SHADOW_IOS_VIDEO_FIX/);
  assert.match(applyScript, /static bool s_shadersPrecompiled = false;/);
  assert.match(applyScript, /static bool s_staticPipelinesPrecompiled = false;/);

  // 4. CoreAudio 1024 sample frames + ring-buffer Pull() bounds protection
  assert.match(applyScript, /SHADOW_IOS_AUDIO_FIX/);
  assert.match(applyScript, /SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "1024"/);
  assert.match(applyScript, /if \(read_size > mBufferSize\)/);

  // 5. o1heap Jetsam page reclamation via madvise(MADV_FREE)
  assert.match(applyScript, /o1heapFreeAndGetUnusedRange/);
  assert.match(applyScript, /SHADOW_IOS_JETSAM_DISCARD/);
  assert.match(applyScript, /MADV_FREE/);
});

test('Shadow the Hedgehog iOS virtual Xbox Original controller is wired with CoreHaptics, pressure sticks, 4s auto-hide, and physical controller detection', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const vcH = byPath.get('ios/include/ios_virtual_controller.h') ?? '';
  const vcMm = byPath.get('ios/ios_virtual_controller.mm') ?? '';
  const cmakeIos = byPath.get('cmake/ShadowRecompIOS.cmake') ?? '';
  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';

  // Header C bridge
  assert.match(vcH, /IOSVirtualPadSnapshot/);
  assert.match(vcH, /IOSVirtualController_SyncState/);
  assert.match(vcH, /IOSVirtualController_GetState/);
  assert.match(vcH, /IOSVirtualController_SetRumble/);

  // Visual theme + Xbox Original mapping + pressure + CoreHaptics + 4s auto-hide + physical hide
  assert.match(vcMm, /DrawShadowSpikyRing/);
  assert.match(vcMm, /DrawShadowEmblem/);
  assert.match(vcMm, /DrawChaosEmeraldIcon/);
  assert.match(vcMm, /ComputeTouchPressure01/);
  assert.match(vcMm, /CATransform3DRotate/);
  assert.match(vcMm, /playsHapticsOnly = YES/);
  assert.match(vcMm, /playButtonDownIsTrigger:/);
  assert.match(vcMm, /playButtonUp/);
  assert.match(vcMm, /playStickRimBump:/);
  assert.match(vcMm, /playGameRumbleLeft:/);
  assert.match(vcMm, /kAutoHideIdleSeconds = 4\.0/);
  assert.match(vcMm, /scheduleIdleFadeTimer/);
  assert.match(vcMm, /wakeControlsAnimated:/);
  assert.match(vcMm, /GCControllerDidConnectNotification/);
  assert.match(vcMm, /hiddenForPhysicalController/);
  assert.match(vcMm, /kBtnWhite/);
  assert.match(vcMm, /kBtnBlack/);

  // CMake + input.cpp patch wiring
  assert.match(cmakeIos, /"os\/ios\/ios_virtual_controller\.mm"/);
  assert.match(applyScript, /"os\/ios\/ios_virtual_controller\.mm"/);
  assert.match(applyScript, /PY_IOS_INPUT/);
  assert.match(applyScript, /IOSVirtualController_GetState\(&vpad\)/);
  assert.match(applyScript, /IOSVirtualController_SetRumble/);
  assert.match(applyScript, /IOSVirtualController_SyncState/);
});

test('centered L-Analog/ABXY layout and iOS background/lock-screen GPU suspend & swapchain resume fix are wired', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const vcMm = byPath.get('ios/ios_virtual_controller.mm') ?? '';
  const iosPlatform = byPath.get('ios/os/ios_platform.mm') ?? '';
  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';

  // Centered L-Analog & ABXY vertical alignment + foreground overlay wake
  assert.match(vcMm, /CGFloat midY = H \* 0\.50;/);
  assert.match(vcMm, /CGFloat lStickY = MAX\(minLeftY, midY - lStickSize \* 0\.5\);/);
  assert.match(vcMm, /CGFloat abxyCenterY = MAX\(minAbxyCenterY, midY\);/);
  assert.match(vcMm, /\[self\.superview bringSubviewToFront:self\];/);
  assert.doesNotMatch(vcMm, /initialVelocity:/);

  // Synchronous UIKit lifecycle notifications (LiveContainer-safe)
  assert.match(iosPlatform, /UIApplicationWillResignActiveNotification/);
  assert.match(iosPlatform, /UIApplicationDidEnterBackgroundNotification/);
  assert.match(iosPlatform, /UIApplicationDidBecomeActiveNotification/);
  assert.match(iosPlatform, /ShadowIOS_VideoOnWillEnterBackground\(\)/);
  assert.match(iosPlatform, /ShadowIOS_VideoOnDidEnterForeground\(\)/);

  // SDL3 lifecycle hooks + bounded MoltenVK timeouts + RenderThread park & swapchain recovery
  assert.match(applyScript, /SDL_EVENT_WILL_ENTER_BACKGROUND/);
  assert.match(applyScript, /SDL_EVENT_DID_ENTER_FOREGROUND/);
  assert.match(applyScript, /SHADOW_IOS_VK_TIMEOUT_FIX/);
  assert.match(applyScript, /100000000ULL/);
  assert.match(applyScript, /2000000000ULL/);
  assert.match(applyScript, /SHADOW_IOS_LIFECYCLE_FIX/);
  assert.match(applyScript, /ShadowIOSDrainInFlightGpuOnly/);
  assert.match(applyScript, /ShadowIOSParkIfBackgrounded/);
  assert.match(applyScript, /wait_dequeue_bulk_timed/);
  assert.match(applyScript, /g_iosSwapChainForceRebuild/);

  // Fresh-install iOS ImGui touch coordinate scaling & single-pass event delivery + overlay suppression
  assert.match(applyScript, /SHADOW_IOS_TOUCH_COORDS_FIX/);
  assert.match(applyScript, /SDL_GetWindowSize\(s_pWindow, &s_width, &s_height\)/);
  assert.match(applyScript, /SHADOW_IOS_IMGUI_TOUCH_SCALE_FIX/);
  assert.match(applyScript, /SDL_GetWindowSize\(GameWindow::s_pWindow, &liveWinW, &liveWinH\)/);
  assert.match(vcMm, /_hiddenForInstaller = YES;/);
  assert.match(vcMm, /self\.userInteractionEnabled = !shouldHideCompletely;/);
});

test('localized hiperema installer credits and custom iOS AppIcon (PNG + Assets.car + Info.plist) are wired', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');

  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';
  assert.match(applyScript, /SHADOW_IOS_HIPEREMA_CREDITS/);
  assert.match(applyScript, /Porting iOS sviluppato da hiperema/);
  assert.match(applyScript, /iOS port developed by hiperema/);
  assert.match(applyScript, /Portage iOS développé par hiperema/);
  assert.match(applyScript, /iOS-Port entwickelt von hiperema/);
  assert.match(applyScript, /Port de iOS desarrollado por hiperema/);
  assert.match(applyScript, /iOS移植開発: hiperema/);

  const infoPlist = byPath.get('ios/Info.plist') ?? '';
  assert.match(infoPlist, /<key>CFBundleIconName<\/key>\s*<string>AppIcon<\/string>/);
  assert.match(infoPlist, /<key>CFBundleIcons<\/key>/);
  assert.match(infoPlist, /<key>CFBundleIcons~ipad<\/key>/);
  assert.match(infoPlist, /<string>AppIcon60x60<\/string>/);
  assert.match(infoPlist, /<string>AppIcon76x76<\/string>/);

  const workflowYml = byPath.get('.github/workflows/build-ios-ipa.yml') ?? '';
  assert.match(workflowYml, /ios-port\/ios\/AppIcon\.jpg/);
  assert.match(workflowYml, /AppIcon60x60@2x\.png/);
  assert.match(workflowYml, /AppIcon60x60@3x\.png/);
  assert.match(workflowYml, /AppIcon76x76@2x~ipad\.png/);
  assert.match(workflowYml, /AppIcon83\.5x83\.5@2x~ipad\.png/);
  assert.match(workflowYml, /AppIcon1024x1024\.png/);
  assert.match(workflowYml, /xcrun actool --compile "Payload\/\$\{APP_NAME\}\.app"/);

  // Validate Step 9 bash syntax after stripping 10-space YAML block indent
  const step9Match = workflowYml.match(/- name: 9\.[\s\S]*?run: \|\n([\s\S]*?)\n\s*- name: 10\./);
  assert.ok(step9Match, 'Expected Step 9 run block in workflow YAML');
  const step9Bash = step9Match[1].replace(/^ {10}/gm, '');
  execFileSync('bash', ['-n'], { input: step9Bash, encoding: 'utf-8' });

  // Verify ios/AppIcon.jpg exists on disk, is valid JPEG, and stays lightweight (< 350 KB)
  const iconPath = path.resolve(process.cwd(), 'ios/AppIcon.jpg');
  assert.ok(fs.existsSync(iconPath), 'Expected ios/AppIcon.jpg to exist in repository');
  const iconBuf = fs.readFileSync(iconPath);
  assert.equal(iconBuf[0], 0xff);
  assert.equal(iconBuf[1], 0xd8);
  assert.ok(iconBuf.length < 350 * 1024, `Expected ios/AppIcon.jpg < 350 KB, got ${iconBuf.length} bytes`);
});

test('Feather standalone native resolution (UILaunchScreen) and full-screen asCopy iOS Files picker are configured', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const infoPlist = byPath.get('ios/Info.plist') ?? '';
  assert.match(infoPlist, /<key>UILaunchScreen<\/key>\s*<dict\/>/);
  assert.match(infoPlist, /<key>UIDeviceFamily<\/key>/);
  assert.match(infoPlist, /<key>UISupportedInterfaceOrientations~ipad<\/key>/);

  const nfdMm = byPath.get('ios/nfd_ios.mm') ?? '';
  assert.match(nfdMm, /UIAdaptivePresentationControllerDelegate/);
  assert.match(nfdMm, /presentationControllerDidDismiss:/);
  assert.match(nfdMm, /initForOpeningContentTypes:types asCopy:\(!folderMode\)/);
  assert.match(nfdMm, /picker\.modalPresentationStyle = UIModalPresentationFullScreen;/);
  assert.match(nfdMm, /picker\.shouldShowFileExtensions = YES;/);
  assert.match(nfdMm, /moveItemAtURL:url toURL:destURL/);
  assert.match(nfdMm, /ScanLocalDocumentsCandidates/);
});

test('AirPlay TV external display scene rejection and single-main guard are patched across SDL3 UIKit and iOS overlays', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';
  assert.match(applyScript, /SHADOW_IOS_AIRPLAY_SCENE_FIX/);
  assert.match(applyScript, /thirdparty\/SDL\/src\/video\/uikit/);
  assert.match(applyScript, /SDL_uikitappdelegate\.m/);
  assert.match(applyScript, /SDL_uikitvideo\.m/);
  assert.match(applyScript, /SDL_uikitmodes\.m/);
  assert.match(applyScript, /UIWindowSceneSessionRoleApplication/);
  assert.match(applyScript, /static BOOL s_shadowSdlMainStarted = NO;/);

  const vcMm = byPath.get('ios/ios_virtual_controller.mm') ?? '';
  const nfdMm = byPath.get('ios/nfd_ios.mm') ?? '';
  const modMm = byPath.get('ios/ios_mod_manager.mm') ?? '';
  assert.match(vcMm, /UIWindowSceneSessionRoleApplication/);
  assert.match(nfdMm, /UIWindowSceneSessionRoleApplication/);
  assert.match(modMm, /UIWindowSceneSessionRoleApplication/);
});

test('2-Player Hotspot local HTTP/WebSocket server, "2 omini" HUD button, Pairing->Connected pill, and Player 2 input injection are wired', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  const byPath = new Map(files.map((f) => [f.path, f.content]));

  const p2H = byPath.get('ios/include/ios_p2_server.h') ?? '';
  const p2Mm = byPath.get('ios/ios_p2_server.mm') ?? '';
  const vcMm = byPath.get('ios/ios_virtual_controller.mm') ?? '';
  const cmakeIos = byPath.get('cmake/ShadowRecompIOS.cmake') ?? '';
  const applyScript = byPath.get('scripts/apply_ios_port.sh') ?? '';
  const infoPlist = byPath.get('ios/Info.plist') ?? '';

  // 1. Header & Server implementation (Apple Network.framework nw_listener_t + Hotspot bridge100 + RFC 6455 WebSocket + Background Keep-Alive)
  assert.match(p2H, /IOSRemoteP2_StartServer/);
  assert.match(p2H, /IOSRemoteP2_StopServer/);
  assert.match(p2H, /IOSRemoteP2_IsConnected/);
  assert.match(p2H, /IOSRemoteP2_GetURL/);
  assert.match(p2H, /IOSRemoteP2_GetState/);
  assert.match(p2H, /IOSRemoteP2_SetRumble/);
  assert.match(p2H, /IOSRemoteP2_SetStateCallback/);
  assert.match(p2H, /IOSRemoteP2_EnsureAlive/);
  assert.match(p2H, /IOSRemoteP2_SetAppInBackground/);

  assert.match(p2Mm, /#import <Network\/Network\.h>/);
  assert.match(p2Mm, /nw_listener_create_with_port/);
  assert.match(p2Mm, /nw_tcp_options_set_no_delay/);
  assert.match(p2Mm, /nw_parameters_set_include_peer_to_peer/);
  assert.match(p2Mm, /beginBackgroundTaskWithName/);
  assert.match(p2Mm, /bridge100/);
  assert.match(p2Mm, /172\.20\.10\.1/);
  assert.match(p2Mm, /258EAFA5-E914-47DA-95CA-C5AB0DC85B11/);
  assert.match(p2Mm, /Sec-WebSocket-Accept/);
  assert.match(p2Mm, /CC_SHA1/);
  assert.match(p2Mm, /ShadowRecomp — Controller 2P/);
  assert.match(p2Mm, /navigator\.vibrate/);
  assert.match(p2Mm, /requestFullscreen/);

  // 2. Quick-HUD Bar "2 omini" icon + Pairing -> Connected pill + CoreImage QR Pairing Card + UIPasteboard copy
  assert.match(vcMm, /#import <CoreImage\/CoreImage\.h>/);
  assert.match(vcMm, /#include <ios_p2_server\.h>/);
  assert.match(vcMm, /CIQRCodeGenerator/);
  assert.match(vcMm, /ShadowTwoPlayersIconView/);
  assert.match(vcMm, /TouchTargetKind::P2StatusPill/);
  assert.match(vcMm, /TouchTargetKind::P2CardCopy/);
  assert.match(vcMm, /@"Pairing"/);
  assert.match(vcMm, /@"Connected"/);
  assert.match(vcMm, /UIPasteboard generalPasteboard/);
  assert.match(vcMm, /IOSRemoteP2_StartServer\(8765\)/);
  assert.match(vcMm, /IOSRemoteP2_StopServer\(\)/);
  assert.match(vcMm, /IOSRemoteP2_EnsureAlive\(\)/);
  assert.match(vcMm, /IOSRemoteP2_SetAppInBackground\(true\)/);
  assert.match(vcMm, /IOSRemoteP2_SetStateCallback/);
  assert.match(vcMm, /OnIOSRemoteP2StateChanged\(bool serverRunning, bool clientConnected, const char \*url\)/);

  // 3. CMake + apply_ios_port.sh Player 2 (dwUserIndex == 2) wiring + Network/CoreImage frameworks + Info.plist local networking
  assert.match(cmakeIos, /"os\/ios\/ios_p2_server\.mm"/);
  assert.match(cmakeIos, /"-framework Network"/);
  assert.match(cmakeIos, /"-framework CoreImage"/);
  assert.match(applyScript, /"os\/ios\/ios_p2_server\.mm"/);
  assert.match(applyScript, /ios_p2_server\.h/);
  assert.match(applyScript, /dwUserIndex == 2 && !hasController/);
  assert.match(applyScript, /IOSRemoteP2_GetState\(&vpad2\)/);
  assert.match(applyScript, /Config::HorizontalCamera2P == ECameraRotationMode::Reverse/);
  assert.match(applyScript, /IOSRemoteP2_IsConnected\(\)/);
  assert.match(applyScript, /IOSRemoteP2_SetRumble/);
  assert.match(infoPlist, /NSLocalNetworkUsageDescription/);
  assert.match(infoPlist, /NSBonjourServices/);
  assert.match(infoPlist, /NSAllowsLocalNetworking/);
});







