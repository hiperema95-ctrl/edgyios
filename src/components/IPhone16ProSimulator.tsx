import React, { useState, useEffect, useRef } from 'react';
import {
  FolderPlus,
  CheckCircle2,
  AlertTriangle,
  Play,
  Puzzle,
  Cpu,
  ArrowUp,
  ArrowDown,
  Trash2,
  Sliders,
  Gamepad2,
  FolderOpen,
  RotateCcw,
  FileCode2,
  Volume2,
  ShieldCheck,
} from 'lucide-react';
import {
  ShadowModItem,
  BuiltinCodePatch,
  XboxRequiredFile,
  PortBuildConfig,
  resolveVirtualFileSystemPath,
} from '../utils/portGenerator';

interface IPhone16ProSimulatorProps {
  config: PortBuildConfig;
  mods: ShadowModItem[];
  codes: BuiltinCodePatch[];
  xboxFiles: XboxRequiredFile[];
  onToggleMod: (id: string) => void;
  onMoveMod: (index: number, direction: 'up' | 'down') => void;
  onDeleteMod: (id: string) => void;
  onOpenImportModModal: () => void;
  onToggleCode: (id: string) => void;
  onImportAllXboxFiles: () => void;
  onToggleSingleXboxFile: (relativePath: string) => void;
  autoStartGame?: boolean;
}

export const IPhone16ProSimulator: React.FC<IPhone16ProSimulatorProps> = ({
  config,
  mods,
  codes,
  xboxFiles,
  onToggleMod,
  onMoveMod,
  onDeleteMod,
  onOpenImportModModal,
  onToggleCode,
  onImportAllXboxFiles,
  onToggleSingleXboxFile,
  autoStartGame = false,
}) => {
  const [launcherTab, setLauncherTab] = useState<'files' | 'mods' | 'codes' | 'vfs'>('files');
  const [isFilesAppSheetOpen, setIsFilesAppSheetOpen] = useState(false);
  const [isPlayingEngine, setIsPlayingEngine] = useState(autoStartGame);
  const [chaosGauge, setChaosGauge] = useState(78);
  const [heroGauge, setHeroGauge] = useState(64);
  const [ringsCount, setRingsCount] = useState(42);
  const [activeActionLabel, setActiveActionLabel] = useState('Standby - Westopolis (Stage 100)');
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const playerStateRef = useRef({
    x: 0,
    z: 0,
    speed: 1.4,
    chaosControlActive: false,
    frame: 0,
  });

  const missingFiles = xboxFiles.filter((f) => !f.verified);
  const isGameReady = missingFiles.length === 0;
  const activeModsCount = mods.filter((m) => m.enabled).length;

  useEffect(() => {
    document.body.setAttribute('data-state', isPlayingEngine ? 'playing-ios-engine' : 'ios-launcher');
  }, [isPlayingEngine]);

  // Canvas 3D-style RenderWare / Metal 3 Westopolis preview loop
  useEffect(() => {
    if (!isPlayingEngine) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId = 0;
    const hasSoapShoesMod = mods.some((m) => m.id === 'mod_sa2_shadow_skin' && m.enabled);

    const renderFrame = () => {
      playerStateRef.current.frame += 1;
      const f = playerStateRef.current.frame;
      const w = canvas.width;
      const h = canvas.height;

      // Sky & Westopolis Crimson Sunset Gradient
      const skyGrad = ctx.createLinearGradient(0, 0, 0, h * 0.55);
      if (playerStateRef.current.chaosControlActive) {
        skyGrad.addColorStop(0, '#021b2b');
        skyGrad.addColorStop(1, '#0e4f6e');
      } else {
        skyGrad.addColorStop(0, '#160404');
        skyGrad.addColorStop(0.6, '#450a0a');
        skyGrad.addColorStop(1, '#7f1d1d');
      }
      ctx.fillStyle = skyGrad;
      ctx.fillRect(0, 0, w, h * 0.55);

      // Perspective Highway Grid (RenderWare stage0100.one)
      ctx.fillStyle = '#090d16';
      ctx.fillRect(0, h * 0.55, w, h * 0.45);

      const horizonY = h * 0.55;
      const centerX = w * 0.5 + playerStateRef.current.x * 45;

      ctx.strokeStyle = playerStateRef.current.chaosControlActive
        ? 'rgba(56, 189, 248, 0.45)'
        : 'rgba(239, 68, 68, 0.4)';
      ctx.lineWidth = 1.5;

      // Radial perspective lines
      for (let i = -8; i <= 8; i++) {
        ctx.beginPath();
        ctx.moveTo(centerX + i * 18, horizonY);
        ctx.lineTo(centerX + i * 110, h);
        ctx.stroke();
      }

      // Moving road ties
      const speedMult = playerStateRef.current.chaosControlActive ? 4.5 : 1.8;
      for (let d = 1; d <= 10; d++) {
        const offset = ((f * speedMult + d * 12) % 120) / 120;
        const y = horizonY + Math.pow(offset, 2.1) * (h - horizonY);
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
      }

      // Shadow Character Silhouette & Jet Skate Boost Trails
      const charX = w * 0.5 - playerStateRef.current.x * 28;
      const charY = h * 0.77 + Math.sin(f * 0.25) * 3;

      // Air Shoes Jet Flame
      const flameColor = playerStateRef.current.chaosControlActive
        ? '#38bdf8'
        : hasSoapShoesMod
        ? '#f59e0b'
        : '#ef4444';
      ctx.fillStyle = flameColor;
      ctx.beginPath();
      ctx.arc(charX - 12, charY + 24, 6 + (f % 4), 0, Math.PI * 2);
      ctx.arc(charX + 12, charY + 24, 6 + ((f + 2) % 4), 0, Math.PI * 2);
      ctx.fill();

      // Shadow Spikes & Body
      ctx.fillStyle = '#0f172a';
      ctx.beginPath();
      ctx.moveTo(charX, charY - 26);
      ctx.lineTo(charX - 24, charY - 12);
      ctx.lineTo(charX - 14, charY + 18);
      ctx.lineTo(charX + 14, charY + 18);
      ctx.lineTo(charX + 24, charY - 12);
      ctx.closePath();
      ctx.fill();

      // Crimson Quill Highlights
      ctx.strokeStyle = '#dc2626';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(charX - 22, charY - 12);
      ctx.lineTo(charX, charY - 22);
      ctx.lineTo(charX + 22, charY - 12);
      ctx.stroke();

      animId = requestAnimationFrame(renderFrame);
    };

    animId = requestAnimationFrame(renderFrame);
    return () => cancelAnimationFrame(animId);
  }, [isPlayingEngine, mods]);

  const triggerGameAction = (action: 'homing' | 'chaos' | 'spear' | 'left' | 'right') => {
    if (action === 'left') {
      playerStateRef.current.x = Math.max(-2.5, playerStateRef.current.x - 0.6);
      setActiveActionLabel('Air Skate Strafe Left');
    } else if (action === 'right') {
      playerStateRef.current.x = Math.min(2.5, playerStateRef.current.x + 0.6);
      setActiveActionLabel('Air Skate Strafe Right');
    } else if (action === 'homing') {
      setRingsCount((r) => r + 5);
      setHeroGauge((g) => Math.min(100, g + 8));
      setActiveActionLabel('Homing Attack Combo (+5 Rings)');
    } else if (action === 'spear') {
      setChaosGauge((c) => Math.min(100, c + 10));
      setActiveActionLabel('Chaos Spear Triggered');
    } else if (action === 'chaos') {
      playerStateRef.current.chaosControlActive = !playerStateRef.current.chaosControlActive;
      setActiveActionLabel(
        playerStateRef.current.chaosControlActive
          ? 'CHAOS CONTROL ATTIVO (120Hz Time Warp)'
          : 'Chaos Control Terminato'
      );
    }
  };

  return (
    <div className="w-full">
      {/* iPhone 16 Pro Titanium Bezel Container (Landscape 19.5:9) */}
      <div
        data-testid="iphone-16-pro-frame"
        className="relative mx-auto w-full max-w-4xl rounded-[44px] border-[6px] border-neutral-700 bg-neutral-950 p-3 shadow-2xl"
      >
        {/* Dynamic Island Pill (Left side in Landscape orientation) */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute left-6 top-1/2 z-30 h-24 w-7 -translate-y-1/2 rounded-full bg-black border border-neutral-800 flex flex-col items-center justify-between py-3"
        >
          <div className="h-2.5 w-2.5 rounded-full bg-neutral-900 border border-neutral-800" />
          <div className="h-2 w-2 rounded-full bg-emerald-500/70" />
        </div>

        {/* Screen Viewport */}
        <div className="relative min-h-[470px] w-full overflow-hidden rounded-[34px] bg-slate-950 pl-12 pr-4 py-3 flex flex-col justify-between border border-slate-800">
          {!isPlayingEngine ? (
            /* ================= NATIVE SWIFTUI LAUNCHER & MOD MANAGER ================= */
            <div className="flex h-full flex-col justify-between gap-3">
              {/* Top iOS Navigation Bar */}
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800 pb-2.5">
                <div>
                  <div className="flex items-center gap-2 text-xs text-slate-400">
                    <span>iPhone 16 Pro · iOS {config.deploymentTarget}</span>
                    <span>·</span>
                    <span>{config.enable120HzProMotion ? '120Hz ProMotion' : '60Hz'}</span>
                    <span>·</span>
                    <span>{config.targetInstaller === 'livecontainer' ? 'LiveContainer' : 'Feather / LiveContainer'}</span>
                  </div>
                  <h3 className="text-base font-bold text-white tracking-tight">
                    {config.appName} — iOS Launcher & Mod Manager
                  </h3>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setIsPlayingEngine(true)}
                    disabled={!isGameReady}
                    className={`flex items-center gap-1.5 rounded-xl px-4 py-2 text-xs font-semibold transition-all whitespace-nowrap shrink-0 ${
                      isGameReady
                        ? 'bg-red-600 text-white hover:bg-red-500 shadow-sm'
                        : 'bg-slate-800 text-slate-500 cursor-not-allowed'
                    }`}
                  >
                    <Play className="h-3.5 w-3.5 fill-current" />
                    Avvia Gioco ({activeModsCount} Mod)
                  </button>
                </div>
              </div>

              {/* Segmented iOS Tabs */}
              <div className="flex items-center gap-1 rounded-xl bg-slate-900 p-1 border border-slate-800">
                <button
                  type="button"
                  onClick={() => setLauncherTab('files')}
                  className={`flex-1 flex items-center justify-center gap-1.5 rounded-lg py-1.5 px-2 text-xs font-medium transition-colors whitespace-nowrap ${
                    launcherTab === 'files'
                      ? 'bg-slate-800 text-white'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <FolderOpen className="h-3.5 w-3.5" />
                  1. Primo Avvio & File Xbox ({xboxFiles.length - missingFiles.length}/{xboxFiles.length})
                </button>
                <button
                  type="button"
                  onClick={() => setLauncherTab('mods')}
                  className={`flex-1 flex items-center justify-center gap-1.5 rounded-lg py-1.5 px-2 text-xs font-medium transition-colors whitespace-nowrap ${
                    launcherTab === 'mods'
                      ? 'bg-slate-800 text-white'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <Puzzle className="h-3.5 w-3.5" />
                  2. Mod Manager ({activeModsCount}/{mods.length})
                </button>
                <button
                  type="button"
                  onClick={() => setLauncherTab('codes')}
                  className={`flex-1 flex items-center justify-center gap-1.5 rounded-lg py-1.5 px-2 text-xs font-medium transition-colors whitespace-nowrap ${
                    launcherTab === 'codes'
                      ? 'bg-slate-800 text-white'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <Cpu className="h-3.5 w-3.5" />
                  3. Codes & 120Hz ({codes.filter((c) => c.enabled).length})
                </button>
                <button
                  type="button"
                  onClick={() => setLauncherTab('vfs')}
                  className={`flex-1 flex items-center justify-center gap-1.5 rounded-lg py-1.5 px-2 text-xs font-medium transition-colors whitespace-nowrap ${
                    launcherTab === 'vfs'
                      ? 'bg-slate-800 text-white'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <FileCode2 className="h-3.5 w-3.5" />
                  4. VFS Override Test
                </button>
              </div>

              {/* Tab Body */}
              <div className="flex-1 overflow-y-auto pr-1">
                {launcherTab === 'files' && (
                  <div className="space-y-3">
                    <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-800 bg-slate-900/70 p-3">
                      <div className="space-y-0.5">
                        <div className="flex items-center gap-2">
                          {isGameReady ? (
                            <CheckCircle2 className="h-4 w-4 text-emerald-400 shrink-0" />
                          ) : (
                            <AlertTriangle className="h-4 w-4 text-amber-400 shrink-0" />
                          )}
                          <span className="text-xs font-semibold text-white">
                            {isGameReady
                              ? 'Dump Xbox Verificato in Documents/GameData/'
                              : `Primo Avvio: Mancano ${missingFiles.length} file Xbox per avviare ShadowRecomp`}
                          </span>
                        </div>
                        <p className="text-xs text-slate-400">
                          L&apos;utente seleziona la cartella del gioco direttamente dall&apos;app{' '}
                          <strong className="text-slate-200">File di iOS</strong> grazie a{' '}
                          <code className="text-red-400">UIDocumentPickerViewController</code>.
                        </p>
                      </div>

                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => setIsFilesAppSheetOpen(true)}
                          className="flex items-center gap-1.5 rounded-lg bg-red-600 px-3 py-2 text-xs font-semibold text-white hover:bg-red-500 transition-colors whitespace-nowrap"
                        >
                          <FolderPlus className="h-3.5 w-3.5" />
                          Apri App File iOS
                        </button>
                      </div>
                    </div>

                    <div className="divide-y divide-slate-800/80 rounded-xl border border-slate-800 bg-slate-900/40">
                      {xboxFiles.map((file) => (
                        <div
                          key={file.relativePath}
                          className="flex items-center justify-between gap-3 px-3 py-2 text-xs"
                        >
                          <div className="min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="font-mono font-medium text-slate-200">
                                Documents/GameData/{file.relativePath}
                              </span>
                              <span className="text-slate-500">·</span>
                              <span className="font-mono text-slate-400 tabular-nums">
                                {file.expectedMinSizeMB.toFixed(1)} MB
                              </span>
                            </div>
                            <p className="text-slate-400 truncate">{file.description}</p>
                          </div>

                          <button
                            type="button"
                            onClick={() => onToggleSingleXboxFile(file.relativePath)}
                            aria-label={`Cambia stato verifica per ${file.relativePath}`}
                            className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                              file.verified
                                ? 'bg-emerald-950/80 text-emerald-300 border border-emerald-800/60'
                                : 'bg-amber-950/80 text-amber-300 border border-amber-800/60'
                            }`}
                          >
                            {file.verified ? 'Verificato' : 'Simula Mancante'}
                          </button>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {launcherTab === 'mods' && (
                  <div className="space-y-2.5">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-xs text-slate-400">
                        Ispirato a <strong className="text-slate-200">MarathonRecompilediOS</strong>: importa cartelle con{' '}
                        <code className="text-red-400">mod.ini</code> dall&apos;App File e ordina la priorità di caricamento.
                      </p>
                      <button
                        type="button"
                        onClick={onOpenImportModModal}
                        className="flex items-center gap-1.5 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-500 transition-colors whitespace-nowrap shrink-0"
                      >
                        <FolderPlus className="h-3.5 w-3.5" />
                        Importa Mod (mod.ini)
                      </button>
                    </div>

                    <div className="divide-y divide-slate-800 rounded-xl border border-slate-800 bg-slate-900/50">
                      {mods.map((mod, idx) => (
                        <div
                          key={mod.id}
                          className="flex items-center justify-between gap-3 px-3 py-2.5 text-xs"
                        >
                          <div className="flex items-start gap-2.5 min-w-0">
                            <input
                              type="checkbox"
                              id={`toggle-${mod.id}`}
                              checked={mod.enabled}
                              onChange={() => onToggleMod(mod.id)}
                              className="mt-1 h-4 w-4 rounded border-slate-700 bg-slate-800 text-red-600 focus:ring-red-500"
                            />
                            <div className="min-w-0">
                              <label
                                htmlFor={`toggle-${mod.id}`}
                                className="font-semibold text-white cursor-pointer hover:text-red-300"
                              >
                                #{idx + 1} · {mod.name}
                              </label>
                              <div className="flex flex-wrap items-center gap-1.5 text-[11px] text-slate-400">
                                <span>Autore: {mod.author}</span>
                                <span>·</span>
                                <span className="font-mono">v{mod.version}</span>
                                <span>·</span>
                                <span>Categoria: {mod.category}</span>
                                <span>·</span>
                                <span className="font-mono text-slate-500">
                                  Override: {mod.replacedAssets.join(', ')}
                                </span>
                              </div>
                            </div>
                          </div>

                          <div className="flex items-center gap-1 shrink-0">
                            <button
                              type="button"
                              onClick={() => onMoveMod(idx, 'up')}
                              disabled={idx === 0}
                              aria-label={`Sposta in alto ${mod.name}`}
                              className="p-1.5 rounded-lg text-slate-400 hover:bg-slate-800 hover:text-white disabled:opacity-30"
                            >
                              <ArrowUp className="h-3.5 w-3.5" />
                            </button>
                            <button
                              type="button"
                              onClick={() => onMoveMod(idx, 'down')}
                              disabled={idx === mods.length - 1}
                              aria-label={`Sposta in basso ${mod.name}`}
                              className="p-1.5 rounded-lg text-slate-400 hover:bg-slate-800 hover:text-white disabled:opacity-30"
                            >
                              <ArrowDown className="h-3.5 w-3.5" />
                            </button>
                            <button
                              type="button"
                              onClick={() => onDeleteMod(mod.id)}
                              aria-label={`Rimuovi mod ${mod.name}`}
                              className="p-1.5 rounded-lg text-slate-400 hover:bg-red-950/60 hover:text-red-400"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {launcherTab === 'codes' && (
                  <div className="divide-y divide-slate-800 rounded-xl border border-slate-800 bg-slate-900/50">
                    {codes.map((code) => (
                      <div
                        key={code.id}
                        className="flex items-center justify-between gap-3 px-3 py-2.5 text-xs"
                      >
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-semibold text-white">{code.title}</span>
                            <span className="text-slate-500">·</span>
                            <span className="text-slate-400">{code.category}</span>
                            <span className="text-slate-500">·</span>
                            <span className="font-mono text-slate-400">{code.author}</span>
                          </div>
                          <p className="text-slate-400">{code.description}</p>
                        </div>
                        <button
                          type="button"
                          onClick={() => onToggleCode(code.id)}
                          aria-label={`Attiva o disattiva patch ${code.title}`}
                          className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap shrink-0 ${
                            code.enabled
                              ? 'bg-red-600 text-white'
                              : 'bg-slate-800 text-slate-400 hover:text-white'
                          }`}
                        >
                          {code.enabled ? 'Attivo' : 'Disattivato'}
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                {launcherTab === 'vfs' && (
                  <div className="space-y-2.5 text-xs">
                    <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-3">
                      <h4 className="font-semibold text-white mb-1">
                        Simulatore Risoluzione Percorsi Xbox D:\ &rarr; Sandbox iOS (IOSVFSBridge.mm)
                      </h4>
                      <p className="text-slate-400 mb-2.5">
                        Verifica in tempo reale quale file viene caricato dal motore ricompilato in base all&apos;ordine delle mod abilitate:
                      </p>
                      <div className="space-y-2 font-mono">
                        {[
                          'D:\\files\\ONE\\shadow.one',
                          'D:\\files\\ONE\\stage0100.one',
                          'D:\\files\\fnt\\font_en.txd',
                          'D:\\files\\ADX\\s_bgm.afs',
                        ].map((xboxPath) => {
                          const resolved = resolveVirtualFileSystemPath(xboxPath, mods);
                          return (
                            <div
                              key={xboxPath}
                              className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-slate-950/90 px-3 py-2 border border-slate-800/80"
                            >
                              <span className="text-slate-300">{xboxPath}</span>
                              <div className="flex items-center gap-2">
                                <span className="text-emerald-400">{resolved.resolvedPath}</span>
                                <span className="text-slate-500">·</span>
                                <span className="text-slate-400">
                                  {resolved.sourceModName ? `Mod: ${resolved.sourceModName}` : 'Dump Xbox Base'}
                                </span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* iOS DocumentPicker Bottom Sheet Modal Simulation */}
              {isFilesAppSheetOpen && (
                <div className="absolute inset-0 z-40 flex items-end bg-black/75 backdrop-blur-sm p-4">
                  <div className="w-full rounded-2xl border border-slate-700 bg-slate-900 p-4 shadow-2xl space-y-3">
                    <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                      <div>
                        <span className="text-xs font-semibold text-red-400">
                          iOS UIDocumentPickerViewController
                        </span>
                        <h4 className="text-sm font-bold text-white">
                          Sfoglia: Su iPhone &rarr; Download &rarr; Shadow_Xbox_Dump
                        </h4>
                      </div>
                      <button
                        type="button"
                        onClick={() => setIsFilesAppSheetOpen(false)}
                        className="text-xs text-slate-400 hover:text-white px-2 py-1"
                      >
                        Annulla
                      </button>
                    </div>

                    <p className="text-xs text-slate-300">
                      Seleziona l&apos;intera cartella estratta del gioco Xbox (`default.xbe` + `files/`). L&apos;app copierà automaticamente i file nella sandbox <code className="text-emerald-400">Documents/GameData/</code>.
                    </p>

                    <div className="flex items-center justify-end gap-2 pt-1">
                      <button
                        type="button"
                        onClick={() => {
                          onImportAllXboxFiles();
                          setIsFilesAppSheetOpen(false);
                        }}
                        className="flex items-center gap-1.5 rounded-xl bg-emerald-600 px-4 py-2 text-xs font-semibold text-white hover:bg-emerald-500"
                      >
                        <ShieldCheck className="h-4 w-4" />
                        Seleziona Cartella &ldquo;Shadow_Xbox_Dump&rdquo; (Importa Tutto)
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ) : (
            /* ================= IN-GAME 120HZ METAL 3 ENGINE & TOUCH GAMEPAD ================= */
            <div className="relative flex min-h-[446px] flex-1 w-full flex-col justify-between overflow-hidden rounded-[26px]">
              <canvas
                ref={canvasRef}
                width={800}
                height={446}
                data-testid="shadow-metal-canvas"
                className="absolute inset-0 h-full w-full object-cover"
              />

              {/* Top In-Game HUD (Safe-Area aware for Dynamic Island) */}
              <div className="relative z-10 flex items-center justify-between gap-4 bg-gradient-to-b from-black/80 via-black/40 to-transparent px-4 py-2.5 text-xs">
                <div className="flex items-center gap-4">
                  <div>
                    <span className="text-[10px] text-slate-400 block">DARK / CHAOS GAUGE</span>
                    <div className="w-28 h-2 bg-slate-800 rounded-full overflow-hidden mt-0.5">
                      <div
                        className="h-full bg-red-500 transition-all"
                        style={{ width: `${chaosGauge}%` }}
                      />
                    </div>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block">HERO GAUGE</span>
                    <div className="w-28 h-2 bg-slate-800 rounded-full overflow-hidden mt-0.5">
                      <div
                        className="h-full bg-sky-400 transition-all"
                        style={{ width: `${heroGauge}%` }}
                      />
                    </div>
                  </div>
                  <div className="font-mono font-bold text-amber-400 tabular-nums">
                    RINGS: {ringsCount}
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <span className="font-mono text-[11px] text-emerald-400 tabular-nums">
                    {config.enable120HzProMotion ? '120.0 FPS · Metal 3' : '60.0 FPS · Metal'}
                  </span>
                  <button
                    type="button"
                    onClick={() => setIsPlayingEngine(false)}
                    className="flex items-center gap-1 rounded-lg bg-slate-900/90 border border-slate-700 px-3 py-1.5 text-xs font-semibold text-white hover:bg-slate-800"
                  >
                    <Sliders className="h-3.5 w-3.5" />
                    Menu Mod
                  </button>
                </div>
              </div>

              {/* Center Status Toast */}
              <div className="relative z-10 my-auto flex flex-col items-center pointer-events-none">
                <div className="rounded-lg bg-black/65 px-3 py-1 text-xs font-mono text-slate-200 border border-white/10">
                  {activeActionLabel}
                </div>
              </div>

              {/* On-Screen Touch Virtual Controller (Unleashed/MarathonRecompilediOS style) */}
              {config.enableVirtualGamepad && (
                <div className="relative z-10 flex items-end justify-between px-4 pb-3 pt-2 bg-gradient-to-t from-black/80 via-black/30 to-transparent">
                  {/* Left Analog / D-Pad */}
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => triggerGameAction('left')}
                      className="h-11 w-14 rounded-xl bg-white/15 backdrop-blur-md border border-white/25 text-xs font-bold text-white active:scale-95"
                    >
                      &larr; Strafe
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerGameAction('right')}
                      className="h-11 w-14 rounded-xl bg-white/15 backdrop-blur-md border border-white/25 text-xs font-bold text-white active:scale-95"
                    >
                      Strafe &rarr;
                    </button>
                  </div>

                  {/* Right Action Buttons (Xbox layout A/B/X/Y + RT Chaos Control) */}
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => triggerGameAction('spear')}
                      className="h-11 px-3.5 rounded-xl bg-amber-500/25 border border-amber-400/50 text-xs font-bold text-amber-200 active:scale-95"
                    >
                      X · Chaos Spear
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerGameAction('homing')}
                      className="h-11 px-3.5 rounded-xl bg-emerald-500/25 border border-emerald-400/50 text-xs font-bold text-emerald-200 active:scale-95"
                    >
                      A · Homing Attack
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerGameAction('chaos')}
                      className="h-11 px-4 rounded-xl bg-sky-500/30 border border-sky-400/60 text-xs font-bold text-sky-200 active:scale-95"
                    >
                      RT · Chaos Control
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
