import React, { useState, useMemo, useEffect } from 'react';
import {
  Download,
  Copy,
  Check,
  Terminal,
  Smartphone,
  GitBranch,
  FileCode,
  Shield,
  Sliders,
  Plus,
  X,
  CheckCircle2,
  FolderGit2,
  Sparkles,
  ExternalLink,
} from 'lucide-react';
import {
  DEFAULT_BUILD_CONFIG,
  INITIAL_MODS,
  INITIAL_CODES,
  INITIAL_XBOX_FILES,
  PortBuildConfig,
  ShadowModItem,
  BuiltinCodePatch,
  XboxRequiredFile,
  parseModIniContent,
  generateModsConfigToml,
  generateAllRepositoryFiles,
} from './utils/portGenerator';
import { IPhone16ProSimulator } from './components/IPhone16ProSimulator';

export default function App() {
  const [config, setConfig] = useState<PortBuildConfig>(DEFAULT_BUILD_CONFIG);
  const [mods, setMods] = useState<ShadowModItem[]>(INITIAL_MODS);
  const [codes, setCodes] = useState<BuiltinCodePatch[]>(INITIAL_CODES);
  const [xboxFiles, setXboxFiles] = useState<XboxRequiredFile[]>(INITIAL_XBOX_FILES);
  const [selectedFileIndex, setSelectedFileIndex] = useState<number>(0);
  const [copiedPath, setCopiedPath] = useState<string | null>(null);
  const [isAddModModalOpen, setIsAddModModalOpen] = useState<boolean>(false);
  const [customModFolder, setCustomModFolder] = useState<string>('Shadow_Custom_Chaos_Mod');
  const [customModIni, setCustomModIni] = useState<string>(
    `[Main]\nName=Pure Dark Chaos Shaders 120Hz\nAuthor=ShadowFan95\nVersion=1.2.0\nCategory=Graphics\nDescription=Aggiunge particelle Metal 3 ad alta densità durante il Chaos Blast su iPhone 16 Pro.\nInclude=files/ONE/shadow.one, files/fnt/font_en.txd`
  );
  const [ciPipelineStep, setCiPipelineStep] = useState<number>(9);
  const [isSimulatingCi, setIsSimulatingCi] = useState<boolean>(false);

  const autoStartGame = useMemo(() => {
    if (typeof window === 'undefined') return false;
    const params = new URLSearchParams(window.location.search);
    return params.get('autostart') === '1';
  }, []);

  const generatedFiles = useMemo(() => generateAllRepositoryFiles(config), [config]);
  const modsConfigToml = useMemo(
    () => generateModsConfigToml(mods, codes, config),
    [mods, codes, config]
  );

  const activeFile = generatedFiles[selectedFileIndex] || generatedFiles[0];

  useEffect(() => {
    if (!isSimulatingCi) return;
    if (ciPipelineStep >= 9) {
      setIsSimulatingCi(false);
      return;
    }
    const timer = setTimeout(() => {
      setCiPipelineStep((s) => Math.min(9, s + 1));
    }, 450);
    return () => clearTimeout(timer);
  }, [isSimulatingCi, ciPipelineStep]);

  const handleCopyContent = (content: string, label: string) => {
    navigator.clipboard?.writeText(content);
    setCopiedPath(label);
    setTimeout(() => setCopiedPath(null), 2000);
  };

  const handleDownloadSingleFile = (filename: string, content: string) => {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename.split('/').pop() || filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleDownloadZeroMacSetupBundle = () => {
    // Genera uno script auto-estraente POSIX/sh + archivio testuale di tutti i file per creare il repo in 1 click o caricarli via web su GitHub
    const parts: string[] = [
      `#!/usr/bin/env bash`,
      `# ==============================================================================`,
      `# ShadowRecomp iOS Cloud Builder - Auto-Extractor (No-Mac GitHub Actions Setup)`,
      `# Target: iPhone 16 Pro (A18 Pro / 120Hz ProMotion / Feather & LiveContainer)`,
      `# ==============================================================================`,
      `set -euo pipefail`,
      `mkdir -p .github/workflows ios cmake scripts`,
      ``,
    ];

    for (const file of generatedFiles) {
      parts.push(`cat << 'EOF_SHADOW_FILE' > "${file.path}"`);
      parts.push(file.content);
      parts.push(`EOF_SHADOW_FILE`);
      parts.push(``);
    }

    parts.push(`cat << 'EOF_SHADOW_TOML' > "ios/DefaultModsConfig.toml"`);
    parts.push(modsConfigToml);
    parts.push(`EOF_SHADOW_TOML`);
    parts.push(`chmod +x scripts/apply_ios_port.sh`);
    parts.push(`echo "Repository iOS pronto! Fai git push su GitHub per compilare ShadowRecomp-iOS-Unsigned.ipa con GitHub Actions."`);

    handleDownloadSingleFile('setup-shadowrecomp-ios-github.sh', parts.join('\n'));
  };

  const handleToggleMod = (id: string) => {
    setMods((prev) => prev.map((m) => (m.id === id ? { ...m, enabled: !m.enabled } : m)));
  };

  const handleMoveMod = (index: number, direction: 'up' | 'down') => {
    setMods((prev) => {
      const copy = [...prev];
      const targetIndex = direction === 'up' ? index - 1 : index + 1;
      if (targetIndex < 0 || targetIndex >= copy.length) return prev;
      const [item] = copy.splice(index, 1);
      copy.splice(targetIndex, 0, item);
      return copy;
    });
  };

  const handleDeleteMod = (id: string) => {
    setMods((prev) => prev.filter((m) => m.id !== id));
  };

  const handleCreateCustomMod = (e: React.FormEvent) => {
    e.preventDefault();
    if (!customModFolder.trim() || !customModIni.trim()) return;
    const parsed = parseModIniContent(customModIni, customModFolder.trim());
    const newMod: ShadowModItem = {
      ...parsed,
      id: `mod_custom_${Date.now()}`,
      enabled: true,
    };
    setMods((prev) => [newMod, ...prev]);
    setIsAddModModalOpen(false);
  };

  const handleToggleCode = (id: string) => {
    setCodes((prev) => prev.map((c) => (c.id === id ? { ...c, enabled: !c.enabled } : c)));
  };

  const handleImportAllXboxFiles = () => {
    setXboxFiles((prev) => prev.map((f) => ({ ...f, verified: true })));
  };

  const handleToggleSingleXboxFile = (relativePath: string) => {
    setXboxFiles((prev) =>
      prev.map((f) => (f.relativePath === relativePath ? { ...f, verified: !f.verified } : f))
    );
  };

  const startCiSimulation = () => {
    setCiPipelineStep(1);
    setIsSimulatingCi(true);
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      {/* Top Bar Contract: 3 Zones separated by gap-8 */}
      <header className="sticky top-0 z-30 flex items-center justify-between gap-8 border-b border-slate-800 bg-slate-950/90 backdrop-blur-md px-6 py-3.5">
        <a
          href="#top"
          className="font-display text-lg font-bold tracking-tight text-white whitespace-nowrap shrink-0"
        >
          ShadowRecomp iOS Studio
        </a>

        <nav className="hidden md:flex items-center gap-6 text-sm font-medium text-slate-300">
          <a
            href="#zero-mac-workflow"
            className="hover:text-white transition-colors whitespace-nowrap shrink-0"
          >
            1. GitHub Cloud Action (Senza Mac)
          </a>
          <a
            href="#iphone16-simulator"
            className="hover:text-white transition-colors whitespace-nowrap shrink-0"
          >
            2. Simulatore iPhone 16 Pro & Mod
          </a>
          <a
            href="#source-files"
            className="hover:text-white transition-colors whitespace-nowrap shrink-0"
          >
            3. File Porting & YAML
          </a>
          <a
            href="#install-guide"
            className="hover:text-white transition-colors whitespace-nowrap shrink-0"
          >
            4. Guida Feather / LiveContainer
          </a>
        </nav>

        <div className="flex items-center gap-3 shrink-0">
          <button
            type="button"
            onClick={() =>
              handleDownloadSingleFile(
                'build-ios-ipa.yml',
                generatedFiles[0].content
              )
            }
            className="flex items-center gap-2 rounded-xl bg-red-600 px-4 py-2 text-xs font-semibold text-white hover:bg-red-500 transition-colors whitespace-nowrap shrink-0"
          >
            <Download className="h-3.5 w-3.5" />
            Scarica build-ios-ipa.yml
          </button>
        </div>
      </header>

      <main id="top" className="mx-auto w-full max-w-7xl flex-1 px-6 py-8 space-y-12">
        {/* Hero & Zero-Mac Explanation Section */}
        <section
          id="zero-mac-workflow"
          className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-stretch"
        >
          <div className="lg:col-span-7 flex flex-col justify-between rounded-2xl border border-slate-800 bg-slate-900/50 p-6 space-y-6">
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400">
                <span>FoxWorkshop/ShadowRecomp</span>
                <span>·</span>
                <span>DevZer0D4Y/MarathonRecompilediOS Pattern</span>
                <span>·</span>
                <span>iPhone 16 Pro (A18 Pro · 120Hz)</span>
              </div>

              <h1
                className="font-display text-3xl sm:text-4xl font-bold tracking-tight text-white"
                style={{ textWrap: 'balance' }}
              >
                Compilazione Completa nel Cloud di GitHub: Ottieni il tuo file .ipa senza avere un Mac
              </h1>

              <p className="text-sm sm:text-base text-slate-300 leading-relaxed">
                Poiché non disponi di un Mac per eseguire <code className="text-red-400">XboxRecomp2</code>,{' '}
                <code className="text-red-400">XShaderRecomp</code> e <code className="text-red-400">xcodebuild</code>,
                questa suite genera il pacchetto completo di porting iOS in cui{' '}
                <strong className="text-white">
                  tutto il lavoro di ricompilazione statica C++ e creazione dell&apos;IPA unsigned viene eseguito dai server gratuiti macOS-15 di GitHub Actions
                </strong>
                . Tu devi solo scaricare l&apos;artifact <code className="text-emerald-400">ShadowRecomp-iOS-Unsigned.ipa</code> sul tuo iPhone 16 Pro e installarlo da <strong className="text-white">Feather</strong> o <strong className="text-white">LiveContainer</strong>.
              </p>
            </div>

            {/* Key Technical Capabilities Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2 border-t border-slate-800/80 text-xs">
              <div className="rounded-xl bg-slate-950/70 p-3.5 border border-slate-800/80">
                <div className="font-semibold text-white mb-1">1. Zero-Mac GitHub Runner</div>
                <p className="text-slate-400 break-words leading-relaxed">
                  La Action clona <code className="text-slate-200">FoxWorkshop/ShadowRecomp</code>, compila gli shader Xbox NV2A in Metal 3 e firma con <code className="text-slate-200">ldid</code> nel cloud.
                </p>
              </div>
              <div className="rounded-xl bg-slate-950/70 p-3.5 border border-slate-800/80">
                <div className="font-semibold text-white mb-1">2. App File iOS al 1° Avvio</div>
                <p className="text-slate-400 break-words leading-relaxed">
                  Usa <code className="text-slate-200">UIDocumentPicker</code> e <code className="text-slate-200">UIFileSharingEnabled</code> per selezionare la cartella Xbox dall&apos;App File.
                </p>
              </div>
              <div className="rounded-xl bg-slate-950/70 p-3.5 border border-slate-800/80">
                <div className="font-semibold text-white mb-1">3. Mod Manager Integrato</div>
                <p className="text-slate-400 break-words leading-relaxed">
                  Menu identico a <code className="text-slate-200">MarathonRecompilediOS</code> per importare cartelle mod (<code className="text-slate-200">mod.ini</code>), riordinarle e attivare i 120Hz.
                </p>
              </div>
            </div>

            {/* Primary CTA Actions */}
            <div className="flex flex-wrap items-center gap-3 pt-1">
              <button
                type="button"
                onClick={() =>
                  handleDownloadSingleFile('build-ios-ipa.yml', generatedFiles[0].content)
                }
                className="flex items-center gap-2 rounded-xl bg-red-600 px-5 py-3 text-xs font-semibold text-white hover:bg-red-500 transition-colors"
              >
                <Download className="h-4 w-4" />
                Scarica .github/workflows/build-ios-ipa.yml
              </button>

              <button
                type="button"
                onClick={handleDownloadZeroMacSetupBundle}
                className="flex items-center gap-2 rounded-xl border border-slate-700 bg-slate-800/90 px-4 py-3 text-xs font-semibold text-slate-100 hover:bg-slate-800 transition-colors"
              >
                <FolderGit2 className="h-4 w-4 text-red-400" />
                Scarica Tutti gli 8 File del Porting (.sh Bundle)
              </button>

              <button
                type="button"
                onClick={() => handleCopyContent(generatedFiles[0].content, 'hero-yml')}
                className="flex items-center gap-1.5 rounded-xl border border-slate-800 bg-slate-950 px-4 py-3 text-xs font-medium text-slate-300 hover:text-white transition-colors"
              >
                {copiedPath === 'hero-yml' ? (
                  <>
                    <Check className="h-4 w-4 text-emerald-400" />
                    YAML Copiato!
                  </>
                ) : (
                  <>
                    <Copy className="h-4 w-4" />
                    Copia YAML negli Appunti
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Right Column: Live GitHub Actions Cloud Builder Configurator & Pipeline Simulator */}
          <div className="lg:col-span-5 flex flex-col justify-between rounded-2xl border border-slate-800 bg-slate-900/50 p-6 space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <div>
                <h2 className="font-display text-base font-bold text-white">
                  Parametri Build GitHub Actions (iPhone 16 Pro)
                </h2>
                <p className="text-xs text-slate-400">
                  Ogni modifica aggiorna istantaneamente il file <code className="text-red-400">build-ios-ipa.yml</code> e <code className="text-red-400">Info.plist</code>
                </p>
              </div>
              <Sliders className="h-4 w-4 text-slate-400 shrink-0" />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div>
                <label
                  htmlFor="bundle-id-input"
                  className="block text-slate-400 mb-1 font-medium"
                >
                  Bundle Identifier (Feather / LiveContainer)
                </label>
                <input
                  id="bundle-id-input"
                  type="text"
                  value={config.bundleId}
                  onChange={(e) => setConfig({ ...config, bundleId: e.target.value })}
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-white focus:border-red-500 focus:outline-none"
                />
              </div>

              <div>
                <label
                  htmlFor="installer-select"
                  className="block text-slate-400 mb-1 font-medium"
                >
                  Target Sideload Installer
                </label>
                <select
                  id="installer-select"
                  value={config.targetInstaller}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      targetInstaller: e.target.value as PortBuildConfig['targetInstaller'],
                    })
                  }
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-xs text-white focus:border-red-500 focus:outline-none"
                >
                  <option value="both">Feather + LiveContainer (Universal PIE)</option>
                  <option value="feather">Solo Feather (ldid Entitlements)</option>
                  <option value="livecontainer">Solo LiveContainer (JIT-less MH_PIE)</option>
                </select>
              </div>

              <div>
                <label
                  htmlFor="ios-target-select"
                  className="block text-slate-400 mb-1 font-medium"
                >
                  Versione Minima iOS
                </label>
                <select
                  id="ios-target-select"
                  value={config.deploymentTarget}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      deploymentTarget: e.target.value as PortBuildConfig['deploymentTarget'],
                    })
                  }
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-xs text-white focus:border-red-500 focus:outline-none"
                >
                  <option value="17.0">iOS 17.0+ (Consigliato)</option>
                  <option value="17.4">iOS 17.4+</option>
                  <option value="18.0">iOS 18.0+ (iPhone 16 Pro Nativo)</option>
                </select>
              </div>

              <div>
                <label
                  htmlFor="build-config-select"
                  className="block text-slate-400 mb-1 font-medium"
                >
                  Ottimizzazione C++ / CMake
                </label>
                <select
                  id="build-config-select"
                  value={config.buildConfiguration}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      buildConfiguration: e.target.value as PortBuildConfig['buildConfiguration'],
                    })
                  }
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-xs text-white focus:border-red-500 focus:outline-none"
                >
                  <option value="Release">Release (-O3 -flto armv8.6-a)</option>
                  <option value="RelWithDebInfo">RelWithDebInfo (Con simboli debug)</option>
                </select>
              </div>
            </div>

            {/* Hardware Switches */}
            <div className="space-y-2 pt-1 text-xs">
              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2 cursor-pointer">
                <span>Abilita 120Hz ProMotion (CADisableMinimumFrameDurationOnPhone)</span>
                <input
                  type="checkbox"
                  checked={config.enable120HzProMotion}
                  onChange={(e) =>
                    setConfig({ ...config, enable120HzProMotion: e.target.checked })
                  }
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>

              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2 cursor-pointer">
                <span>Entitlement increased-memory-limit (Evita crash RAM su iOS)</span>
                <input
                  type="checkbox"
                  checked={config.enableIncreasedMemoryLimit}
                  onChange={(e) =>
                    setConfig({ ...config, enableIncreasedMemoryLimit: e.target.checked })
                  }
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>

              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2 cursor-pointer">
                <span>Cartella visibile nell&apos;App File di iOS (UIFileSharingEnabled)</span>
                <input
                  type="checkbox"
                  checked={config.enableFileSharingApp}
                  onChange={(e) =>
                    setConfig({ ...config, enableFileSharingApp: e.target.checked })
                  }
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>
            </div>

            {/* GitHub Runner Pipeline Status Verification */}
            <div className="rounded-xl border border-slate-800 bg-slate-950 p-3 space-y-2 text-xs">
              <div className="flex items-center justify-between">
                <span className="font-mono font-semibold text-slate-300">
                  Runner: GitHub Actions macos-15 (Xcode 16.2)
                </span>
                <button
                  type="button"
                  onClick={startCiSimulation}
                  className="text-red-400 hover:text-red-300 font-semibold underline"
                >
                  Simula Run Workflow ({ciPipelineStep}/9)
                </button>
              </div>
              <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
                <div
                  className="h-full bg-emerald-500 transition-all duration-300"
                  style={{ width: `${(ciPipelineStep / 9) * 100}%` }}
                />
              </div>
              <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono">
                <span>
                  {ciPipelineStep < 9
                    ? `Step ${ciPipelineStep}/9: Compilazione C++ & Metal Shaders nel cloud...`
                    : 'Artifact pronto: ShadowRecomp-iOS-v1.1.0-Unsigned.ipa'}
                </span>
                <span className="text-emerald-400">0 Mac Richiesti</span>
              </div>
            </div>
          </div>
        </section>

        {/* Section 2: Interactive iPhone 16 Pro Preview (First Launch Files App + Mod Manager + Gameplay) */}
        <section id="iphone16-simulator" className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-4 border-b border-slate-800 pb-4">
            <div>
              <h2 className="font-display text-2xl font-bold text-white">
                Anteprima Interattiva su iPhone 16 Pro (Primo Avvio, App File & Mod Manager)
              </h2>
              <p className="text-sm text-slate-400">
                Prova esattamente l&apos;esperienza utente che avrai su iPhone 16 Pro appena installato l&apos;IPA da Feather o LiveContainer: seleziona i file Xbox dall&apos;App File, gestisci le mod in stile{' '}
                <code className="text-red-400">MarathonRecompilediOS</code> e premi <strong className="text-white">Avvia Gioco</strong>.
              </p>
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setIsAddModModalOpen(true)}
                className="flex items-center gap-1.5 rounded-xl bg-slate-800 border border-slate-700 px-3.5 py-2 text-xs font-semibold text-white hover:bg-slate-700 transition-colors"
              >
                <Plus className="h-3.5 w-3.5 text-red-400" />
                Aggiungi Nuova Mod (mod.ini)
              </button>
            </div>
          </div>

          <IPhone16ProSimulator
            config={config}
            mods={mods}
            codes={codes}
            xboxFiles={xboxFiles}
            onToggleMod={handleToggleMod}
            onMoveMod={handleMoveMod}
            onDeleteMod={handleDeleteMod}
            onOpenImportModModal={() => setIsAddModModalOpen(true)}
            onToggleCode={handleToggleCode}
            onImportAllXboxFiles={handleImportAllXboxFiles}
            onToggleSingleXboxFile={handleToggleSingleXboxFile}
            autoStartGame={autoStartGame}
          />
        </section>

        {/* Section 3: Complete Source Code & GitHub Action YAML Inspector */}
        <section id="source-files" className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-4 border-b border-slate-800 pb-4">
            <div>
              <h2 className="font-display text-2xl font-bold text-white">
                Codice Completo del Porting iOS & Configurazione GitHub Actions (.yml)
              </h2>
              <p className="text-sm text-slate-400">
                Esplora, copia o scarica singolarmente i file che compongono il porting iOS automatico su GitHub.
              </p>
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() =>
                  handleDownloadSingleFile(activeFile.path, activeFile.content)
                }
                className="flex items-center gap-1.5 rounded-xl bg-red-600 px-4 py-2 text-xs font-semibold text-white hover:bg-red-500 transition-colors"
              >
                <Download className="h-3.5 w-3.5" />
                Scarica {activeFile.path.split('/').pop()}
              </button>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            {/* Left File Tree List */}
            <div className="lg:col-span-4 space-y-2">
              <div className="rounded-2xl border border-slate-800 bg-slate-900/50 p-2 divide-y divide-slate-800/60">
                {generatedFiles.map((file, idx) => {
                  const isSelected = idx === selectedFileIndex;
                  return (
                    <button
                      key={file.path}
                      type="button"
                      onClick={() => setSelectedFileIndex(idx)}
                      className={`w-full text-left rounded-xl p-3 transition-colors flex flex-col gap-1 ${
                        isSelected
                          ? 'bg-slate-800 text-white'
                          : 'text-slate-300 hover:bg-slate-900'
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="font-mono text-xs font-semibold text-red-400 truncate">
                          {file.path}
                        </span>
                        <span className="text-[11px] font-mono text-slate-400 uppercase">
                          {file.language}
                        </span>
                      </div>
                      <span className="text-xs font-semibold text-white">
                        {file.title}
                      </span>
                      <span className="text-[11px] text-slate-400 line-clamp-2">
                        {file.description}
                      </span>
                    </button>
                  );
                })}
              </div>

              {/* Live Generated ModsConfig.toml Preview Box */}
              <div className="rounded-2xl border border-slate-800 bg-slate-900/50 p-4 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-mono text-xs font-semibold text-emerald-400">
                    Documents/ModsConfig.toml (Live)
                  </span>
                  <button
                    type="button"
                    onClick={() => handleCopyContent(modsConfigToml, 'toml-copy')}
                    className="text-xs text-slate-300 hover:text-white flex items-center gap-1"
                  >
                    {copiedPath === 'toml-copy' ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-400" />
                        Copiato
                      </>
                    ) : (
                      <>
                        <Copy className="h-3.5 w-3.5" />
                        Copia TOML
                      </>
                    )}
                  </button>
                </div>
                <pre className="max-h-56 overflow-auto rounded-xl bg-slate-950 p-3 text-[11px] font-mono text-slate-300 border border-slate-800">
                  {modsConfigToml}
                </pre>
              </div>
            </div>

            {/* Right Code Editor Viewer */}
            <div className="lg:col-span-8 rounded-2xl border border-slate-800 bg-slate-900/60 overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-800 bg-slate-900 px-4 py-3">
                <div>
                  <div className="font-mono text-xs font-semibold text-red-400">
                    {activeFile.path}
                  </div>
                  <div className="text-xs text-slate-400">{activeFile.description}</div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => handleCopyContent(activeFile.content, activeFile.path)}
                    className="flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-white hover:bg-slate-700"
                  >
                    {copiedPath === activeFile.path ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-400" />
                        Copiato!
                      </>
                    ) : (
                      <>
                        <Copy className="h-3.5 w-3.5" />
                        Copia File
                      </>
                    )}
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      handleDownloadSingleFile(activeFile.path, activeFile.content)
                    }
                    className="flex items-center gap-1.5 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500"
                  >
                    <Download className="h-3.5 w-3.5" />
                    Scarica
                  </button>
                </div>
              </div>

              <pre className="max-h-[600px] overflow-auto p-4 text-xs font-mono leading-relaxed text-slate-200 bg-slate-950">
                <code>{activeFile.content}</code>
              </pre>
            </div>
          </div>
        </section>

        {/* Section 4: Step-by-Step Guide to compile on GitHub without a Mac and install on iPhone 16 Pro */}
        <section
          id="install-guide"
          className="rounded-2xl border border-slate-800 bg-slate-900/40 p-6 space-y-6"
        >
          <div className="border-b border-slate-800 pb-4">
            <h2 className="font-display text-2xl font-bold text-white">
              Come Ottenere l&apos;IPA da GitHub (Senza Mac) e Giocare su iPhone 16 Pro
            </h2>
            <p className="text-sm text-slate-400">
              Segui questi 4 passaggi direttamente dal browser o dal tuo iPhone 16 Pro per compilare e avviare Shadow the Hedgehog con le mod.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 text-xs">
            <div className="rounded-xl border border-slate-800 bg-slate-950/80 p-4 space-y-2">
              <div className="font-display text-sm font-bold text-white">
                01. Crea Repo & Carica i File su GitHub
              </div>
              <p className="text-slate-300 leading-relaxed">
                Crea un nuovo repository su GitHub (anche privato). Carica i file presenti nella sezione 3 qui sopra, assicurandoti che il file YAML si trovi in{' '}
                <code className="text-red-400">.github/workflows/build-ios-ipa.yml</code>.
              </p>
            </div>

            <div className="rounded-xl border border-slate-800 bg-slate-950/80 p-4 space-y-2">
              <div className="font-display text-sm font-bold text-white">
                02. Avvia la GitHub Action nel Cloud
              </div>
              <p className="text-slate-300 leading-relaxed">
                Apri la scheda <strong className="text-white">Actions</strong> del tuo repository GitHub e premi <strong className="text-white">Run workflow</strong>. Il server macOS-15 di GitHub clonerà{' '}
                <code className="text-slate-200">FoxWorkshop/ShadowRecomp</code>, eseguirà la ricompilazione statica C++ e applicherà il tuo Mod Manager iOS.
              </p>
            </div>

            <div className="rounded-xl border border-slate-800 bg-slate-950/80 p-4 space-y-2">
              <div className="font-display text-sm font-bold text-white">
                03. Installa l&apos;IPA in Feather o LiveContainer
              </div>
              <p className="text-slate-300 leading-relaxed">
                Scarica l&apos;artifact <code className="text-emerald-400">ShadowRecomp-iOS-Unsigned-IPA</code> su iPhone 16 Pro. Importalo in <strong className="text-white">Feather</strong> (firma con il tuo certificato mantenendo gli entitlements RAM) oppure aprilo direttamente in <strong className="text-white">LiveContainer</strong> (nessun JIT richiesto).
              </p>
            </div>

            <div className="rounded-xl border border-slate-800 bg-slate-950/80 p-4 space-y-2">
              <div className="font-display text-sm font-bold text-white">
                04. Seleziona File Xbox e Mod dall&apos;App File
              </div>
              <p className="text-slate-300 leading-relaxed">
                Al primo avvio tocca <strong className="text-white">&ldquo;Seleziona Cartella Gioco dall&apos;App File&rdquo;</strong> e punta alla cartella del tuo gioco Xbox (<code className="text-slate-200">default.xbe</code> + <code className="text-slate-200">files/</code>). Poi apri la scheda <strong className="text-white">Mod Manager</strong> per importare le tue mod!
              </p>
            </div>
          </div>
        </section>
      </main>

      {/* Modal for testing custom mod.ini import */}
      {isAddModModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="modal-mod-title"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4"
        >
          <div className="w-full max-w-lg rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <h3 id="modal-mod-title" className="font-display text-lg font-bold text-white">
                Importa Nuova Mod per ShadowRecomp (Formato mod.ini)
              </h3>
              <button
                type="button"
                onClick={() => setIsAddModModalOpen(false)}
                aria-label="Chiudi finestra"
                className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-white"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleCreateCustomMod} className="space-y-4 text-xs">
              <div>
                <label
                  htmlFor="mod-folder-name"
                  className="block font-medium text-slate-300 mb-1"
                >
                  Nome Cartella Mod (in Documents/Mods/)
                </label>
                <input
                  id="mod-folder-name"
                  type="text"
                  required
                  value={customModFolder}
                  onChange={(e) => setCustomModFolder(e.target.value)}
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-white focus:border-red-500 focus:outline-none"
                />
              </div>

              <div>
                <label
                  htmlFor="mod-ini-content"
                  className="block font-medium text-slate-300 mb-1"
                >
                  Contenuto file mod.ini (Standard SA Mod Manager / ShadowRecomp)
                </label>
                <textarea
                  id="mod-ini-content"
                  rows={6}
                  required
                  value={customModIni}
                  onChange={(e) => setCustomModIni(e.target.value)}
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 p-3 font-mono text-white focus:border-red-500 focus:outline-none"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setIsAddModModalOpen(false)}
                  className="rounded-xl border border-slate-700 px-4 py-2 font-medium text-slate-300 hover:bg-slate-800"
                >
                  Annulla
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-red-600 px-4 py-2 font-semibold text-white hover:bg-red-500"
                >
                  Importa nel Mod Manager iOS
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <footer className="border-t border-slate-900 bg-slate-950 px-6 py-5 text-xs text-slate-500">
        <div className="mx-auto max-w-7xl flex flex-wrap items-center justify-between gap-4">
          <span>
            ShadowRecomp iOS Cloud Porting Suite · Basato su FoxWorkshop/ShadowRecomp & DevZer0D4Y/MarathonRecompilediOS
          </span>
          <span>
            Compatibile con iPhone 16 Pro (A18 Pro · Metal 3 · Feather & LiveContainer Unsigned IPA)
          </span>
        </div>
      </footer>
    </div>
  );
}
