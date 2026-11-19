import test from 'node:test';
import assert from 'node:assert/strict';
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
  assert.match(yml, /CODE_SIGNING_ALLOWED=NO/);
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

test('buildZipArchiveBytes generates valid PKZIP binary containing all 14 files including .gitignore', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  assert.equal(files.length, 14);
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
