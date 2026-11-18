import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_BUILD_CONFIG,
  INITIAL_MODS,
  INITIAL_CODES,
  parseModIniContent,
  generateModsConfigToml,
  resolveVirtualFileSystemPath,
  generateGitHubWorkflowYaml,
  generateAllRepositoryFiles,
} from './portGenerator';

test('parseModIniContent extracts SA Mod Manager / ShadowRecomp mod.ini properties', () => {
  const sampleIni = `
[Main]
Name=Shadow Generations Boost VFX
Author=ChaosModder
Version=2.4.0
Category=Graphics
Description=Replaces Chaos Control aura with high-res shaders
Include=files/ONE/shadow.one, files/fnt/font_en.txd
`;
  const parsed = parseModIniContent(sampleIni, 'Shadow_Gen_VFX');
  assert.equal(parsed.name, 'Shadow Generations Boost VFX');
  assert.equal(parsed.author, 'ChaosModder');
  assert.equal(parsed.version, '2.4.0');
  assert.equal(parsed.category, 'Graphics');
  assert.deepEqual(parsed.replacedAssets, ['files/ONE/shadow.one', 'files/fnt/font_en.txd']);
});

test('resolveVirtualFileSystemPath prioritizes enabled mods in load order and falls back to GameData', () => {
  const res1 = resolveVirtualFileSystemPath('D:\\files\\ONE\\shadow.one', INITIAL_MODS);
  assert.equal(res1.sourceModName, 'Sonic Adventure 2 Soap Shoes & Shaders');
  assert.equal(res1.resolvedPath, 'Documents/Mods/SA2_Terios_Legacy_Pack/files/ONE/shadow.one');

  // Disabled mod (Crush40_Lossless_ADX) should fall back to GameData
  const resAudio = resolveVirtualFileSystemPath('D:\\files\\ADX\\s_bgm.afs', INITIAL_MODS);
  assert.equal(resAudio.sourceModName, null);
  assert.equal(resAudio.resolvedPath, 'Documents/GameData/files/ADX/s_bgm.afs');
});

test('generateModsConfigToml serializes active mods and 120Hz ProMotion codes', () => {
  const toml = generateModsConfigToml(INITIAL_MODS, INITIAL_CODES, DEFAULT_BUILD_CONFIG);
  assert.ok(toml.includes('MaxRefreshRate = 120'));
  assert.ok(toml.includes('"Shadow_4K_HUD_DynamicIsland"'));
  assert.ok(!toml.includes('"Crush40_Lossless_ADX"'));
  assert.ok(toml.includes('fps_120_promotion = true'));
});

test('generateGitHubWorkflowYaml produces complete macOS-15 unsigned IPA pipeline without requiring local Mac', () => {
  const yaml = generateGitHubWorkflowYaml(DEFAULT_BUILD_CONFIG);
  assert.ok(yaml.includes('runs-on: macos-15'));
  assert.ok(yaml.includes('CODE_SIGNING_ALLOWED=NO'));
  assert.ok(yaml.includes('ldid -Sios-port/ios/Entitlements.plist'));
  assert.ok(yaml.includes('-Unsigned.ipa'));
});

test('generateAllRepositoryFiles returns all required iOS port & GitHub Actions files', () => {
  const files = generateAllRepositoryFiles(DEFAULT_BUILD_CONFIG);
  assert.equal(files.length, 8);
  const paths = files.map((f) => f.path);
  assert.ok(paths.includes('.github/workflows/build-ios-ipa.yml'));
  assert.ok(paths.includes('ios/ShadowRecompLauncherView.swift'));
  assert.ok(paths.includes('ios/Info.plist'));
  assert.ok(paths.includes('ios/Entitlements.plist'));
});
