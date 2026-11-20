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

test('buildZipArchiveBytes generates valid PKZIP binary containing all 16 files including .gitignore', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  assert.equal(files.length, 16);
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



