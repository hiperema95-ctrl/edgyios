import React, { useState, useMemo } from 'react';
import {
  Download,
  Copy,
  Check,
  AlertTriangle,
  Sliders,
  FolderArchive,
  CheckCircle2,
  Wrench,
  FileCode2,
  HardDrive,
} from 'lucide-react';
import {
  DEFAULT_BUILD_CONFIG,
  PortBuildConfig,
  generateAllRepositoryFiles,
} from './utils/portGenerator';
import { buildZipArchiveBytes } from './utils/zipBuilder';

export default function App() {
  const [config, setConfig] = useState<PortBuildConfig>(DEFAULT_BUILD_CONFIG);
  const [selectedFileIndex, setSelectedFileIndex] = useState<number>(0);
  const [copiedPath, setCopiedPath] = useState<string | null>(null);

  const generatedFiles = useMemo(() => generateAllRepositoryFiles(config), [config]);
  const activeFile = generatedFiles[selectedFileIndex] || generatedFiles[0];

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

  const handleDownloadZipArchive = () => {
    const zipBytes = buildZipArchiveBytes(
      generatedFiles.map((f) => ({ path: f.path, content: f.content }))
    );
    const blob = new Blob([zipBytes], { type: 'application/zip' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${config.appName}-iOS-GitHub-Port.zip`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      {/* Header */}
      <header className="sticky top-0 z-30 flex items-center justify-between gap-8 border-b border-slate-800 bg-slate-950/95 backdrop-blur-md px-6 py-3.5">
        <a
          href="#top"
          className="font-display text-lg font-bold tracking-tight text-white whitespace-nowrap shrink-0"
        >
          ShadowRecomp iOS Port Builder
        </a>

        <nav className="hidden md:flex items-center gap-6 text-sm font-medium text-slate-300">
          <a href="#fix-report" className="hover:text-white transition-colors whitespace-nowrap shrink-0">
            Fix Errore GitHub Action
          </a>
          <a href="#architecture" className="hover:text-white transition-colors whitespace-nowrap shrink-0">
            Architettura Porting Reale
          </a>
          <a href="#source-files" className="hover:text-white transition-colors whitespace-nowrap shrink-0">
            File Repository ({generatedFiles.length})
          </a>
        </nav>

        <div className="flex items-center gap-3 shrink-0">
          <button
            type="button"
            onClick={handleDownloadZipArchive}
            className="flex items-center gap-2 rounded-xl bg-red-600 px-4 py-2 text-xs font-semibold text-white hover:bg-red-500 transition-colors whitespace-nowrap shrink-0"
          >
            <FolderArchive className="h-3.5 w-3.5" />
            Scarica Pacchetto .ZIP Completo
          </button>
        </div>
      </header>

      <main id="top" className="mx-auto w-full max-w-7xl flex-1 px-6 py-8 space-y-10">
        {/* Section 1: Exact Fix for GitHub Action Failure + Build Config */}
        <section id="fix-report" className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-stretch">
          <div className="lg:col-span-7 flex flex-col justify-between rounded-2xl border border-slate-800 bg-slate-900/60 p-6 space-y-5">
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-2 text-xs font-mono text-slate-400">
                <span>Upstream: FoxWorkshop/ShadowRecomp (branch: master)</span>
                <span>·</span>
                <span>Target: iPhone 16 Pro (arm64 / Feather &amp; LiveContainer)</span>
              </div>

              <h1
                className="font-display text-3xl font-bold tracking-tight text-white"
                style={{ textWrap: 'balance' }}
              >
                Porting iOS Reale di ShadowRecomp con Build Unsigned IPA su GitHub Actions
              </h1>

              <p className="text-sm text-slate-300 leading-relaxed">
                Rimosso il simulatore superfluo: questo pannello contiene esclusivamente i{' '}
                <strong className="text-white">{generatedFiles.length} file reali</strong> (Workflow YAML, script di patch CMake/C++, bridge App File <code className="text-red-400">nfd_ios.mm</code>, Mod Manager nativo <code className="text-red-400">ios_mod_manager.mm</code> e layer OS iOS) verificati direttamente contro i sorgenti di{' '}
                <code className="text-slate-200">FoxWorkshop/ShadowRecomp</code> e il modello iOS di{' '}
                <code className="text-slate-200">DevZer0D4Y/MarathonRecompilediOS</code>.
              </p>
            </div>

            {/* Diagnostic Box for the exact screenshot error */}
            <div className="rounded-xl border border-amber-500/30 bg-amber-950/20 p-4 space-y-2.5 text-xs">
              <div className="flex items-center gap-2 font-semibold text-amber-300">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>Cosa era rotto nella Action precedente e cosa è stato corretto ora:</span>
              </div>
              <ul className="space-y-1.5 text-slate-300 list-disc pl-5 leading-relaxed">
                <li>
                  <strong className="text-white">Errore Exit Code 128 (<code className="text-red-300">Remote branch main not found</code>):</strong>{' '}
                  <code className="text-slate-200">FoxWorkshop/ShadowRecomp</code> usa il branch{' '}
                  <code className="text-emerald-400">master</code> (non <code className="text-red-300">main</code>). Il workflow ora verifica e clona <code className="text-emerald-400">master</code> con fallback automatico.
                </li>
                <li>
                  <strong className="text-white">Tool Host macOS mancanti per Cross-Compile iOS:</strong>{' '}
                  <code className="text-slate-200">ShadowRecomp</code> richiede <code className="text-slate-200">XboxRecomp2</code> (Rust), <code className="text-slate-200">file_to_c</code> e <code className="text-slate-200">dxc</code> compilati per il runner <code className="text-slate-200">macos-15</code>, oltre a <code className="text-slate-200">MoltenVK</code> (<code className="text-slate-200">libMoltenVK.a</code>) per tradurre <code className="text-slate-200">plume_vulkan</code> in Apple Metal 3.
                </li>
                <li>
                  <strong className="text-white">File C++ upstream non compatibili con iOS:</strong>{' '}
                  <code className="text-slate-200">scripts/apply_ios_port.sh</code> ora patcha <code className="text-slate-200">user/paths.cpp</code>, <code className="text-slate-200">os/registry.h</code>, <code className="text-slate-200">ui/game_window.cpp</code>, <code className="text-slate-200">plume</code>, <code className="text-slate-200">XShaderRecomp</code> e sostituisce <code className="text-slate-200">nfd</code> con <code className="text-emerald-400">UIDocumentPickerViewController</code> (App File iOS).
                </li>
              </ul>
            </div>

            {/* Primary Download Actions */}
            <div className="flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={handleDownloadZipArchive}
                className="flex items-center gap-2 rounded-xl bg-red-600 px-5 py-3 text-xs font-semibold text-white hover:bg-red-500 transition-colors"
              >
                <FolderArchive className="h-4 w-4" />
                Scarica Tutti i {generatedFiles.length} File (.ZIP per GitHub)
              </button>

              <button
                type="button"
                onClick={() =>
                  handleDownloadSingleFile('build-ios-ipa.yml', generatedFiles[0].content)
                }
                className="flex items-center gap-2 rounded-xl border border-slate-700 bg-slate-800 px-4 py-3 text-xs font-semibold text-white hover:bg-slate-700 transition-colors"
              >
                <Download className="h-4 w-4 text-red-400" />
                Scarica Solo build-ios-ipa.yml
              </button>

              <button
                type="button"
                onClick={() => handleCopyContent(generatedFiles[0].content, 'hero-yml')}
                className="flex items-center gap-1.5 rounded-xl border border-slate-800 bg-slate-950 px-4 py-3 text-xs font-medium text-slate-300 hover:text-white transition-colors"
              >
                {copiedPath === 'hero-yml' ? (
                  <>
                    <Check className="h-4 w-4 text-emerald-400" />
                    YAML Copiato
                  </>
                ) : (
                  <>
                    <Copy className="h-4 w-4" />
                    Copia YAML
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Right Column: Build Parameters */}
          <div className="lg:col-span-5 flex flex-col justify-between rounded-2xl border border-slate-800 bg-slate-900/60 p-6 space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <div>
                <h2 className="font-display text-base font-bold text-white">
                  Configurazione Build IPA (iPhone 16 Pro)
                </h2>
                <p className="text-xs text-slate-400">
                  Aggiorna in tempo reale YAML, CMake, Info.plist ed Entitlements.plist
                </p>
              </div>
              <Sliders className="h-4 w-4 text-slate-400 shrink-0" />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div>
                <label htmlFor="bundle-id-input" className="block text-slate-400 mb-1 font-medium">
                  Bundle Identifier
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
                <label htmlFor="branch-input" className="block text-slate-400 mb-1 font-medium">
                  Branch FoxWorkshop/ShadowRecomp
                </label>
                <input
                  id="branch-input"
                  type="text"
                  value={config.upstreamBranch}
                  onChange={(e) => setConfig({ ...config, upstreamBranch: e.target.value })}
                  className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-emerald-400 focus:border-red-500 focus:outline-none"
                />
              </div>

              <div>
                <label htmlFor="installer-select" className="block text-slate-400 mb-1 font-medium">
                  Target Sideload
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
                  <option value="both">Feather + LiveContainer (-Wl,-pie)</option>
                  <option value="feather">Solo Feather</option>
                  <option value="livecontainer">Solo LiveContainer</option>
                </select>
              </div>

              <div>
                <label htmlFor="ios-target-select" className="block text-slate-400 mb-1 font-medium">
                  iOS Deployment Target
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
                  <option value="17.0">iOS 17.0+</option>
                  <option value="17.4">iOS 17.4+</option>
                  <option value="18.0">iOS 18.0+ (iPhone 16 Pro)</option>
                </select>
              </div>
            </div>

            <div className="space-y-2 text-xs">
              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/70 px-3 py-2 cursor-pointer">
                <span>ProMotion 120Hz (CADisableMinimumFrameDurationOnPhone)</span>
                <input
                  type="checkbox"
                  checked={config.enable120HzProMotion}
                  onChange={(e) => setConfig({ ...config, enable120HzProMotion: e.target.checked })}
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>

              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/70 px-3 py-2 cursor-pointer">
                <span>Entitlement increased-memory-limit (ldid)</span>
                <input
                  type="checkbox"
                  checked={config.enableIncreasedMemoryLimit}
                  onChange={(e) =>
                    setConfig({ ...config, enableIncreasedMemoryLimit: e.target.checked })
                  }
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>

              <label className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/70 px-3 py-2 cursor-pointer">
                <span>Cartella App File iOS (UIFileSharingEnabled)</span>
                <input
                  type="checkbox"
                  checked={config.enableFileSharingApp}
                  onChange={(e) => setConfig({ ...config, enableFileSharingApp: e.target.checked })}
                  className="h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600"
                />
              </label>
            </div>
          </div>
        </section>

        {/* Section 2: Critical Technical Architecture (34MB IPA, default.xbe vs ISO, ModLoader, Files App) */}
        <section id="architecture" className="grid grid-cols-1 md:grid-cols-3 gap-5 text-xs">
          <div className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5 space-y-2.5">
            <div className="flex items-center gap-2 font-display text-sm font-bold text-white">
              <HardDrive className="h-4 w-4 text-red-400 shrink-0" />
              <span>Perché l&apos;IPA pesa ~34MB (come Sonic &apos;06)</span>
            </div>
            <p className="text-slate-300 leading-relaxed">
              <strong className="text-white">La ISO da 4GB NON va su GitHub</strong>: texture, livelli e audio vengono importati al primo avvio sull&apos;iPhone dall&apos;App File.
              Tuttavia, esattamente come <code className="text-slate-200">MarathonRecompilediOS</code> richiede <code className="text-slate-200">default.xex</code> in fase di build,{' '}
              <code className="text-slate-200">ShadowRecompLib/cmake/recompile.cmake</code> richiede <strong className="text-white">solo <code className="text-emerald-400">default.xbe</code> (~4.8MB)</strong> in{' '}
              <code className="text-emerald-400">private/default.xbe</code> (o nel secret <code className="text-slate-200">DEFAULT_XBE_URL</code>) affinché <code className="text-slate-200">XboxRecomp2</code> ricompili staticamente le funzioni x86 in codice nativo <code className="text-slate-200">arm64</code> JIT-less.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5 space-y-2.5">
            <div className="flex items-center gap-2 font-display text-sm font-bold text-white">
              <Wrench className="h-4 w-4 text-red-400 shrink-0" />
              <span>Primo Avvio App File &amp; MoltenVK Metal 3</span>
            </div>
            <p className="text-slate-300 leading-relaxed">
              Invece di riscrivere l&apos;installer originale di <code className="text-slate-200">ShadowRecomp</code>, il file{' '}
              <code className="text-emerald-400">ios/nfd_ios.mm</code> implementa <code className="text-slate-200">NFD_OpenDialogU8</code> e{' '}
              <code className="text-slate-200">NFD_PickFolderU8</code> tramite <code className="text-slate-200">UIDocumentPickerViewController</code>: quando apri l&apos;IPA installato da Feather, l&apos;Installer Wizard apre direttamente l&apos;App File di iOS per selezionare la tua ISO/cartella. La grafica Vulkan (<code className="text-slate-200">plume</code>) viene tradotta su Metal 3 tramite <code className="text-slate-200">libMoltenVK.a</code>.
            </p>
          </div>

          <div className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5 space-y-2.5">
            <div className="flex items-center gap-2 font-display text-sm font-bold text-white">
              <CheckCircle2 className="h-4 w-4 text-emerald-400 shrink-0" />
              <span>Mod Manager Reale (profiles.json)</span>
            </div>
            <p className="text-slate-300 leading-relaxed">
              Ispezionando <code className="text-slate-200">ShadowRecomp/mod/mod_loader.cpp</code>, il gioco carica le mod attive da{' '}
              <code className="text-emerald-400">mods/.modloader/profiles/profiles.json</code> e <code className="text-emerald-400">Default.json</code> (<code className="text-slate-200">EnabledMods</code>). Il nostro{' '}
              <code className="text-emerald-400">ios/ios_mod_manager.mm</code> (modellato su <code className="text-slate-200">MarathonRecompilediOS</code>) importa le cartelle mod dall&apos;App File e genera esattamente quei file JSON.
            </p>
          </div>
        </section>

        {/* Section 3: Complete Source Files Inspector */}
        <section id="source-files" className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-4 border-b border-slate-800 pb-4">
            <div>
              <h2 className="font-display text-2xl font-bold text-white">
                Tutti i {generatedFiles.length} File da Caricare nel Repository GitHub (hiperema95-ctrl/edgyios)
              </h2>
              <p className="text-sm text-slate-400">
                Scarica il pacchetto .ZIP qui in alto per mantenere automaticamente i percorsi esatti, oppure copia/scarica i singoli file.
              </p>
            </div>

            <button
              type="button"
              onClick={() => handleDownloadSingleFile(activeFile.path, activeFile.content)}
              className="flex items-center gap-1.5 rounded-xl bg-red-600 px-4 py-2 text-xs font-semibold text-white hover:bg-red-500 transition-colors"
            >
              <Download className="h-3.5 w-3.5" />
              Scarica {activeFile.path.split('/').pop()}
            </button>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            <div className="lg:col-span-4 rounded-2xl border border-slate-800 bg-slate-900/50 p-2 divide-y divide-slate-800/60 max-h-[640px] overflow-y-auto">
              {generatedFiles.map((file, idx) => {
                const isSelected = idx === selectedFileIndex;
                return (
                  <button
                    key={file.path}
                    type="button"
                    onClick={() => setSelectedFileIndex(idx)}
                    className={`w-full text-left rounded-xl p-3 transition-colors flex flex-col gap-1 ${
                      isSelected ? 'bg-slate-800 text-white' : 'text-slate-300 hover:bg-slate-900'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-mono text-xs font-semibold text-red-400 truncate">
                        {file.path}
                      </span>
                      <span className="text-[11px] font-mono text-slate-400 uppercase shrink-0">
                        {file.language}
                      </span>
                    </div>
                    <span className="text-xs font-semibold text-white">{file.title}</span>
                    <span className="text-[11px] text-slate-400 line-clamp-2">
                      {file.description}
                    </span>
                  </button>
                );
              })}
            </div>

            <div className="lg:col-span-8 rounded-2xl border border-slate-800 bg-slate-900/60 overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-800 bg-slate-900 px-4 py-3">
                <div className="flex items-center gap-2 min-w-0">
                  <FileCode2 className="h-4 w-4 text-red-400 shrink-0" />
                  <div className="min-w-0">
                    <div className="font-mono text-xs font-semibold text-red-400 truncate">
                      {activeFile.path}
                    </div>
                    <div className="text-xs text-slate-400 truncate">{activeFile.description}</div>
                  </div>
                </div>

                <div className="flex items-center gap-2 shrink-0">
                  <button
                    type="button"
                    onClick={() => handleCopyContent(activeFile.content, activeFile.path)}
                    className="flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-white hover:bg-slate-700"
                  >
                    {copiedPath === activeFile.path ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-400" />
                        Copiato
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
                    onClick={() => handleDownloadSingleFile(activeFile.path, activeFile.content)}
                    className="flex items-center gap-1.5 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500"
                  >
                    <Download className="h-3.5 w-3.5" />
                    Scarica
                  </button>
                </div>
              </div>

              <pre className="max-h-[580px] overflow-auto p-4 text-xs font-mono leading-relaxed text-slate-200 bg-slate-950">
                <code>{activeFile.content}</code>
              </pre>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-slate-900 bg-slate-950 px-6 py-4 text-xs text-slate-500">
        <div className="mx-auto max-w-7xl flex flex-wrap items-center justify-between gap-4">
          <span>ShadowRecomp iOS Port Builder · FoxWorkshop/ShadowRecomp (master) → iOS arm64</span>
          <span>Unsigned IPA per Feather / LiveContainer su iPhone 16 Pro</span>
        </div>
      </footer>
    </div>
  );
}
