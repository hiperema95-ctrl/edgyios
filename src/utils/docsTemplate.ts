// Template documentazione elegante per GitHub:
// - README.md (EdgyiOS: Shadow The Hedgehog Recompiled for iOS)
// - LEGAL.md (Note legali complete, marchi, proprietà copia, trasparenza Google AI Studio, licenze di terze parti)
// - RELEASE_NOTES.md (Note di release v1.0.0 pronte per GitHub Releases & Workflow)

export interface DocsTemplateConfig {
  appName: string;
  appVersion: string;
  deploymentTarget: string;
  upstreamRepoUrl: string;
  iosRefRepoUrl: string;
}

export function generateEdgyIosReadmeMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `<div align="center">

<img src="ios/AppIcon.jpg" alt="EdgyiOS App Icon" width="128" height="128" />

# EdgyiOS
### *Shadow The Hedgehog Recompiled for iOS*

**Porting nativo iOS / iPadOS (arm64 · Metal 3 · 120Hz ProMotion) sviluppato da hiperema con il supporto di Google AI Studio**

[![Platform](https://img.shields.io/badge/Platform-iOS%20${config.deploymentTarget}%2B%20%7C%20iPadOS%20${config.deploymentTarget}%2B-111111?style=for-the-badge&logo=apple&logoColor=white)](#dispositivi-compatibili)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20Native%20(Zero%20JIT)-dc2626?style=for-the-badge)](#architettura-e-sviluppo)
[![Graphics](https://img.shields.io/badge/Graphics-Vulkan%20%E2%86%92%20MoltenVK%20%E2%86%92%20Metal%203-0ea5e9?style=for-the-badge)](#funzionalita-esclusive-ios)
[![Sideload](https://img.shields.io/badge/Sideload-Feather%20%7C%20LiveContainer-6366f1?style=for-the-badge)](#installazione-su-iphone-e-ipad)
[![Assets](https://img.shields.io/badge/Copyrighted%20Assets-0%25%20Clean%20Repo-16a34a?style=for-the-badge)](#note-legali-e-copyright)

<p>
  <a href="#funzionalita-esclusive-ios">Funzionalità iOS</a> •
  <a href="#dispositivi-compatibili">iPhone &amp; iPad Compatibili</a> •
  <a href="#architettura-e-sviluppo">Come è Stato Sviluppato</a> •
  <a href="#risorse-github-e-crediti">Risorse GitHub</a> •
  <a href="#compilazione-cloud-zero-mac">Build Cloud</a> •
  <a href="#installazione-su-iphone-e-ipad">Installazione</a> •
  <a href="RELEASE_NOTES.md">Release v${config.appVersion}</a> •
  <a href="LEGAL.md">Note Legali</a>
</p>

</div>

---

## Panoramica

**EdgyiOS: Shadow The Hedgehog Recompiled for iOS** è il porting iOS e iPadOS nativo del progetto open-source [ShadowRecomp](${cleanUpstream}), progettato per eseguire *Shadow the Hedgehog (2005)* a piena velocità nativa su Apple Silicon senza emulazione JIT e senza bisogno di un Mac per compilare.

A differenza degli emulatori tradizionali, la ricompilazione statica traduce l'eseguibile Xbox originale direttamente in codice C++ nativo **arm64** e gli shader grafici in **SPIR-V / Metal 3** tramite MoltenVK. Il risultato è un'applicazione leggera, reattiva e capace di spingersi fino a **120 FPS** sui dispositivi ProMotion, arricchita da funzionalità pensate su misura per iPhone e iPad: controller touch vettoriale con CoreHaptics, multiplayer 2 giocatori via Hotspot/Wi-Fi locale, Modalità TV Dual-Screen (AirPlay & HDMI) e localizzazione automatica in 6 lingue.

> **Importante — Zero file protetti da copyright:** né questo repository né il pacchetto \`.ipa\` finale contengono asset, texture, audio, video o codice di gioco di proprietà SEGA/Sonic Team. Per avviare il gioco è obbligatorio importare i file estratti dalla **propria copia originale legalmente posseduta** del gioco per Xbox tramite l'App File di iOS. Consulta [LEGAL.md](LEGAL.md) per tutti i dettagli.

---

## Funzionalità Esclusive iOS

### 1. Prestazioni Native arm64, Metal 3 & 120Hz ProMotion
- **Esecuzione 100% nativa senza JIT**: compatibile con iOS standard senza jailbreak, sia in modalità standalone (**Feather**) che containerizzata (**LiveContainer**, compilato con \`-fPIC -Wl,-pie\`).
- **Risoluzione nativa full-screen**: supporto \`UILaunchScreen\` e \`UIDeviceFamily\` universale (iPhone + iPad), sfruttando l'intero pannello (es. \`2622×1206\` su iPhone 16 Pro) senza barre nere o scaling sfocato.
- **Sblocco ProMotion 120Hz**: \`CADisableMinimumFrameDurationOnPhone\` attivo, compositing overlay ottimizzato (\`allowsGroupOpacity = NO\`) e bridge input lock-free a 0 allocazioni per mantenere 120 FPS fluidi anche nelle zone ad alto carico.
- **Gestione memoria estesa & ciclo vita GPU**: entitlements \`increased-memory-limit\` ed \`extended-virtual-addressing\`, drenaggio sicuro della coda Metal (\`vkQueueWaitIdle\`) su blocco schermo o cambio app con ricostruzione automatica della swapchain al rientro.

### 2. Controller Virtuale Xbox Original a Tema Shadow the Hedgehog
- **Grafica vettoriale CoreGraphics / QuartzCore**: design in vetro ossidiana traslucido con bagliore cremisi, analogico sinistro con emblema Shadow & anello uncinato a inclinazione 3D e sensibilità alla pressione, analogico destro camera, D-Pad scorrevole a 8 direzioni, ABXY Xbox Original, grilletti analogici \`LT/RT\`, pulsanti \`LB (White)\`, \`RB (Black)\`, \`L3\`, \`R3\`, \`Start\` e \`Back\`.
- **Feedback Aptico CoreHaptics (Taptic Engine)**: click meccanico calibrato su pressione e rilascio, detent tattili sugli analogici e inoltro nativo della vibrazione di gioco (\`XboxVibrationPacket\`) al Taptic Engine.
- **Chaos Emerald Quick-HUD**: pulsante centrale a forma di Smeraldo del Caos che cambia aura dinamicamente (**Hero / Neutral / Dark**) e apre la barra rapida con:
  - Regolazione **Opacità** (\`25%–95%\`, salvata in \`NSUserDefaults\`);
  - Toggle **Aptica** (ON/OFF);
  - **Auto-Hide 4s** (dissolvenza automatica dopo 4 secondi di inattività con riapparizione istantanea al primo tocco);
  - Pulsante **Modalità TV** (AirPlay/HDMI);
  - Pulsante **Multiplayer 2P**.
- **Rilevamento Controller Fisici**: collegando qualsiasi gamepad Bluetooth o USB-C (DualSense, Xbox Wireless, Backbone, MFi), i comandi touch scompaiono automaticamente lasciando lo schermo completamente libero.

### 3. Multiplayer 2 Giocatori via Hotspot Personale / Wi-Fi (iOS & Android)
- **Server HTTP + WebSocket integrato sull'iPhone**: basato su Apple \`Network.framework\` (\`nw_listener_t\`, porta \`8765\`, \`TCP_NODELAY\`), rileva automaticamente l'interfaccia Hotspot (\`bridge100\` / \`172.20.10.1\`) o la rete Wi-Fi locale senza richiedere connessione a Internet.
- **Abbinamento istantaneo**: attivando l'icona **2 Giocatori** dal menu Smeraldo compare la pillola **Abbina**; toccandola si apre una scheda con **QR Code nativo** (\`CoreImage\`) e il link viene copiato automaticamente negli appunti (con background keep-alive per incollarlo su WhatsApp/Messaggi senza chiudere il server).
- **Controller Web Cross-Platform**: il secondo giocatore (su qualsiasi **Android** o **iPhone**) apre il link dal browser e ottiene un controller virtuale a schermo intero con bottoni ingranditi giocabili senza distogliere lo sguardo dallo schermo principale, vibrazione aptica e stato di connessione in tempo reale.
- **Pillola intelligente**: appena il Giocatore 2 si collega, la pillola passa a **Connesso** e scompare automaticamente dopo 3,5 secondi per non occupare spazio sullo schermo, riapparendo con notifica solo in caso di disconnessione.
- **Iniezione nativa Giocatore 2**: supporta sia la modalità competitiva **2P** sia il controllo di Sonic e dei compagni negli stage della storia.

### 4. Modalità TV Dedicata Dual-Screen (AirPlay & HDMI)
- **Attivazione automatica su schermo esterno**: il pulsante **TV** accanto al pulsante 2P si illumina automaticamente quando l'iPhone o l'iPad è connesso via **AirPlay** o cavo/adattatore **HDMI**.
- **Schermo pulito sulla TV, gamepad dedicato sull'iPhone**:
  - Sulla **TV** viene spostata **esclusivamente** la superficie Metal del gioco a schermo intero (zero bottoni virtuali sulla TV, compensazione overscan disabilitata, cap intelligente a 1080p per evitare crash Jetsam su TV 4K).
  - Sull'**iPhone** lo schermo passa a uno sfondo scuro dedicato con **comandi virtuali ingranditi** progettati per giocare alla cieca mantenendo pieno feedback aptico e compatibilità simultanea con il Multiplayer 2P.
- **Ripresa senza freeze**: bloccando lo schermo o cambiando app durante la Modalità TV, la finestra esterna viene staccata in sicurezza e ricostruita automaticamente al rientro con recovery continuo della swapchain MoltenVK.

### 5. Localizzazione Automatica in 6 Lingue
- All'avvio l'app rileva automaticamente la lingua di sistema del dispositivo (\`[NSLocale preferredLanguages]\`) e localizza coerentemente ogni etichetta dell'HUD, del Multiplayer 2P, della Modalità TV, del selettore File iOS e i crediti dell'installer (*"Porting iOS sviluppato da hiperema"*).
- Anche il controller web del secondo smartphone si adatta automaticamente alla lingua del proprio browser (\`navigator.language\`).
- **Lingue supportate**: Italiano, Inglese (fallback universale), Spagnolo, Francese, Tedesco e Giapponese.

### 6. App File iOS Nativa, Mod Manager & Icona Dedicata
- **Importazione da App File**: bridge nativo \`UIDocumentPickerViewController\` a schermo intero con copia sicura in sandbox (\`asCopy\`) + rilevamento automatico dei file già copiati in *Su iPhone → ShadowRecomp*.
- **Mod Manager iOS**: interfaccia UIKit integrata compatibile con \`ModLoader::Init()\` (\`mods/.modloader/profiles/Default.json\`).
- **Icona app compilata in \`Assets.car\`**: icone PNG opache generate per iPhone e iPad e compilate tramite \`actool\` per una visualizzazione nitida sia su SpringBoard (Feather) che in LiveContainer.

---

## Dispositivi Compatibili

Requisiti minimi di sistema: **iOS ${config.deploymentTarget}+ / iPadOS ${config.deploymentTarget}+** · Architettura **arm64** (Apple Silicon / A-series).

### iPhone Compatibili

| Fascia | Modelli iPhone | Chip | RAM | Esperienza Attesa |
| :--- | :--- | :--- | :---: | :--- |
| **Ottimale (120Hz ProMotion)** | **iPhone 17 / 17 Air / 17 Pro / 17 Pro Max**<br>**iPhone 16 Pro / 16 Pro Max**<br>**iPhone 15 Pro / 15 Pro Max** | A19 / A19 Pro<br>A18 Pro<br>A17 Pro | 8–12 GB | **120 FPS** nativi, risoluzione piena, Modalità TV e 2P fluidi, zero limiti RAM |
| **Eccellente (60Hz–120Hz)** | **iPhone 16 / 16 Plus / 16e**<br>**iPhone 15 / 15 Plus**<br>**iPhone 14 Pro / 14 Pro Max**<br>**iPhone 13 Pro / 13 Pro Max** | A18<br>A16 Bionic<br>A16 Bionic<br>A15 Bionic | 6–8 GB | **60–120 FPS** (120Hz sui modelli Pro), ottima stabilità con \`increased-memory-limit\` |
| **Buona (60Hz)** | **iPhone 14 / 14 Plus**<br>**iPhone 13 / 13 mini**<br>**iPhone 12 Pro / 12 Pro Max**<br>**iPhone SE (3ª gen)** | A15 Bionic<br>A15 Bionic<br>A14 Bionic<br>A15 Bionic | 4–6 GB | **60 FPS** fluidi (su modelli da 4 GB consigliato chiudere le app in background) |
| **Supporto Base (60Hz)** | **iPhone 12 / 12 mini**<br>**iPhone 11 / 11 Pro / 11 Pro Max**<br>**iPhone XS / XS Max / XR**<br>**iPhone SE (2ª gen)** | A14 Bionic<br>A13 Bionic<br>A12 Bionic<br>A13 Bionic | 3–4 GB | Funzionante su iOS 17+, possibili chiusure Jetsam su dispositivi da 3 GB (XR / SE 2ª gen) nelle aree più pesanti |

### iPad Compatibili

| Fascia | Modelli iPad | Chip | RAM | Esperienza Attesa |
| :--- | :--- | :--- | :---: | :--- |
| **Ottimale (120Hz ProMotion)** | **iPad Pro 11" / 13" (M4)**<br>**iPad Pro 11" / 12.9" (M2 / M1)**<br>**iPad Pro (2018 / 2020)** | M4 / M2 / M1<br>A12X / A12Z | 4–16 GB | **120 FPS** su display ProMotion, USB-C HDMI nativo plug-and-play per Modalità TV |
| **Eccellente (60Hz)** | **iPad Air 11" / 13" (M3 / M2 / M1)**<br>**iPad mini (A17 Pro / 6ª gen)**<br>**iPad Air (4ª gen)** | M3 / M2 / M1<br>A17 Pro / A15<br>A14 | 4–8 GB | **60 FPS** costanti, schermo ampio ideale per gamepad fisico o touch |
| **Supporto Base (60Hz)** | **iPad (11ª gen A16 / 10ª gen A14 / 9ª gen A13)**<br>**iPad Air (3ª gen)** · **iPad mini (5ª gen)** | A16 / A14 / A13 / A12 | 3–6 GB | Compatibile con iPadOS 17+; su modelli con 3 GB di RAM si consiglia di limitare le mod pesanti |

> **Nota RAM e Sideloading:** i dispositivi con **6 GB di RAM o superiori** offrono la migliore esperienza complessiva. Quando si firma l'IPA con un certificato che supporta \`com.apple.developer.kernel.increased-memory-limit\` (o tramite LiveContainer), iOS concede un margine di memoria significativamente più alto per MoltenVK e gli asset di gioco.

---

## Architettura e Sviluppo

**EdgyiOS** è stato sviluppato da **hiperema** avvalendosi di **Google AI Studio** per l'ingegnerizzazione del layer di porting iOS, l'automazione delle patch C++/Objective-C++/CMake, la pipeline di cross-compilazione cloud e la suite di test automatici.

### Flusso Tecnico (Zero-Mac Pipeline)
\`\`\`text
[Host macOS-15 Runner su GitHub Actions]
  ├── XboxRecomp2 (Rust)  ──► Ricompilazione statica x86 Xbox -> C++ nativo arm64
  ├── XShaderRecomp + DXC ──► Compilazione shader Xbox -> SPIR-V
  └── file_to_c           ──► Risorse UI e font di ShadowRecomp
                │
                ▼
[Cross-Compilazione iOS arm64 (CMake + Ninja + Xcode SDK)]
  ├── ShadowRecomp + Plume (Vulkan) ──► MoltenVK (libMoltenVK.a) ──► Apple Metal 3
  ├── SDL3 Static (UIKit AirPlay-safe + CoreAudio + GameController)
  ├── Layer iOS EdgyiOS:
  │     ├── ios_virtual_controller.mm (CoreGraphics + CoreHaptics + TV Mode + 6 Lingue)
  │     ├── ios_p2_server.mm          (Network.framework HTTP/WS + Web Controller 2P)
  │     ├── nfd_ios.mm                (UIDocumentPicker App File full-screen)
  │     ├── ios_mod_manager.mm        (ModLoader profiles.json UIKit)
  │     └── ios_platform.mm           (os::logger/process/media + GPU lifecycle hooks)
  └── Firma ad-hoc ldid + Assets.car ──► ShadowRecomp-iOS.ipa (Unsigned, Zero Asset)
\`\`\`

---

## Risorse GitHub e Crediti

Questo progetto esiste grazie al lavoro straordinario della community open-source. Tutte le risorse esterne utilizzate nella realizzazione di **EdgyiOS**:

| Progetto / Risorsa | Ruolo in EdgyiOS | Licenza / Riferimento |
| :--- | :--- | :--- |
| **[FoxWorkshop/ShadowRecomp](${cleanUpstream})** | Progetto upstream di ricompilazione statica di *Shadow the Hedgehog* (inclusi \`XboxRecomp2\`, \`XShaderRecomp\` e \`Plume\`) | Open-Source (Upstream) |
| **[DevZer0D4Y/MarathonRecompilediOS](${config.iosRefRepoUrl})** | Riferimento architetturale iOS per build cloud Zero-Asset, App File e Mod Manager | Open-Source (Riferimento) |
| **[KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK)** | Layer di traduzione Vulkan / SPIR-V → Apple Metal 3 per iOS arm64 | Apache-2.0 |
| **[libsdl-org/SDL](https://github.com/libsdl-org/SDL)** | SDL3 UIKit (windowing, eventi, audio CoreAudio, GameController) | zlib License |
| **[FreeType](https://freetype.org/)** | Rendering font statico arm64 per \`msdf-atlas-gen\` | FreeType License / GPL |
| **[ocornut/imgui](https://github.com/ocornut/imgui)** | Interfaccia installer wizard e menu overlay di ShadowRecomp | MIT License |
| **[ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid)** | Applicazione degli entitlements iOS (\`increased-memory-limit\`, \`extended-virtual-addressing\`) in CI | BSD / Open-Source |
| **[khcrysalis/Feather](https://github.com/khcrysalis/Feather)** | Sideloader iOS standalone supportato e testato | Open-Source |
| **[LiveContainer/LiveContainer](https://github.com/LiveContainer/LiveContainer)** | Esecuzione containerizzata iOS supportata e testata (\`-fPIC -Wl,-pie\`) | Apache-2.0 |
| **Google AI Studio** | Ambiente di co-sviluppo utilizzato da **hiperema** per progettare, patchare e verificare il porting iOS | Strumento di sviluppo |

---

## Compilazione Cloud (Zero-Mac)

Non serve un Mac: l'intera build gira gratuitamente su **GitHub Actions (\`macos-15\`)** senza mai committare file di gioco nel repository (\`.gitignore\` blocca automaticamente \`*.xbe\`, \`*.iso\`, \`*.xiso\`, \`*.afs\`, \`*.one\`, \`*.txd\` e \`private/\`).

1. Effettua un fork o clona questo repository su GitHub.
2. Vai in **Settings → Secrets and variables → Actions → New repository secret**.
3. Crea il Secret cifrato **\`DEFAULT_XBE_URL\`** inserendo un link diretto temporaneo/privato al \`default.xbe\` estratto dalla **tua copia originale** del gioco (~4,8 MB).
   - Il file viene scaricato esclusivamente dentro la VM effimera \`macos-15\` durante lo step di ricompilazione di \`XboxRecomp2\` e rimosso al termine della build.
4. Apri **Actions → Build ShadowRecomp iOS Unsigned IPA → Run workflow**.
   - Seleziona \`Release\` (consigliato).
   - *(Opzionale)* Spunta **\`publish_release\`** per pubblicare automaticamente una GitHub Release con \`${config.appName}-iOS.ipa\` e il file \`SHA256SUMS\`.
5. Scarica l'artifact \`.ipa\` direttamente sul tuo iPhone o iPad.

---

## Installazione su iPhone e iPad

### Con Feather (Standalone)
1. Importa \`${config.appName}-iOS.ipa\` in **Feather**, firma e installa.
2. Avvia l'app: all'apertura dell'installer si aprirà il selettore nativo dell'**App File di iOS** (in alternativa, copia prima la tua \`.iso\` / \`.xiso\` o la cartella estratta in *Su iPhone → ${config.appName}*).
3. Completa l'installazione: al termine appariranno i crediti (*"Porting iOS sviluppato da hiperema"*) e al riavvio il gioco sarà pronto!

### Con LiveContainer
1. Importa \`${config.appName}-iOS.ipa\` in **LiveContainer** (l'eseguibile è già compilato con \`-fPIC -Wl,-pie\`).
2. Avvia **EdgyiOS**, seleziona i file della tua copia originale dall'App File di iOS e completa la procedura guidata.

---

## Note Legali e Copyright

- **Nessun contenuto protetto da copyright è incluso** in questo repository, nei sorgenti o nell'IPA compilato.
- **EdgyiOS** è un progetto indipendente, amatoriale e senza scopo di lucro, non affiliato né approvato da **SEGA CORPORATION**, **Sonic Team**, **Microsoft Corporation** o **Apple Inc.**
- Tutti i marchi citati (*Shadow the Hedgehog*, *SEGA*, *Xbox*, *iPhone*, *iPad*, *iOS*, *AirPlay*, *Metal*) appartengono ai rispettivi legittimi proprietari.
- L'utilizzo di questo software richiede il possesso legale di una copia originale di *Shadow the Hedgehog (2005)* per Xbox. Non vengono forniti né richiesti link a ROM, ISO o file proprietari.

Per l'informativa legale completa, i dettagli sull'uso di Google AI Studio e le licenze dei componenti open-source, leggi **[LEGAL.md](LEGAL.md)**.

---

<div align="center">
  <sub>Sviluppato con passione da <strong>hiperema</strong> · Co-sviluppato con <strong>Google AI Studio</strong> · Basato su <strong>FoxWorkshop/ShadowRecomp</strong></sub>
</div>
`;
}

export function generateEdgyIosLegalMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `# Note Legali, Licenze e Disclaimer — EdgyiOS

**Progetto:** EdgyiOS: Shadow The Hedgehog Recompiled for iOS  
**Autore del porting iOS:** hiperema  
**Versione:** v${config.appVersion}  

---

## 1. Politica "Zero Copyrighted Assets"

Questo repository GitHub e qualsiasi pacchetto \`.ipa\` generato tramite il workflow CI incluso **non contengono alcun file protetto da copyright** appartenente a *Shadow the Hedgehog (2005)* o a terze parti commerciali. In particolare, **non sono inclusi e non saranno mai distribuiti**:

- Eseguibili originali Xbox (\`default.xbe\`);
- Immagini disco (\`*.iso\`, \`*.xiso\`);
- Archivi di gioco, texture, modelli 3D, livelli, audio, musiche o filmati (\`*.afs\`, \`*.one\`, \`*.txd\`, \`*.adx\`, \`*.sfd\`, ecc.).

Il file \`.gitignore\` del repository è configurato esplicitamente per impedire il commit accidentale di tali formati. L'applicazione compilata funge esclusivamente da **motore nativo di ricompilazione/esecuzione** e rimane inutilizzabile senza i file estratti dalla copia originale dell'utente.

---

## 2. Proprietà Legale, Interoperabilità e Anti-Pirateria

- Per compilare e utilizzare **EdgyiOS** è obbligatorio possedere una **copia fisica o digitale originale e legalmente acquistata** di *Shadow the Hedgehog* per Xbox Original.
- L'estrazione dei file dalla propria copia legittimamente detenuta a scopo di backup personale, preservazione digitale e interoperabilità su hardware moderno rientra nei principi riconosciuti dal diritto d'autore in materia di copia privata e interoperabilità (es. Direttiva UE 2009/24/CE e corrispondenti normative nazionali applicabili; ogni utente è tenuto a verificare e rispettare le leggi vigenti nella propria giurisdizione).
- Il progetto **condanna fermamente la pirateria**: qualsiasi richiesta o condivisione di ROM, ISO, XISO, file \`.xbe\` o asset protetti da copyright su Issues, Discussions o Pull Request verrà immediatamente rimossa.

---

## 3. Marchi Registrati e Non Affiliazione

**EdgyiOS** è un progetto comunitario indipendente, gratuito e senza scopo di lucro. Non è in alcun modo affiliato, sponsorizzato, autorizzato o approvato da alcuno dei titolari di marchi sottoelencati:

- *Shadow the Hedgehog*, *Sonic the Hedgehog*, *SEGA* e *Sonic Team* sono marchi registrati di **SEGA CORPORATION**.
- *Xbox* e *DirectX* sono marchi registrati di **Microsoft Corporation**.
- *Apple*, *iPhone*, *iPad*, *iOS*, *iPadOS*, *AirPlay*, *Metal* e *ProMotion* sono marchi registrati di **Apple Inc.**
- *Vulkan* è un marchio registrato di **The Khronos Group Inc.**

Tutti i nomi e marchi sono citati esclusivamente a scopo descrittivo e di compatibilità tecnica.

---

## 4. Trasparenza sullo Sviluppo con Google AI Studio

Il layer di porting iOS di **EdgyiOS** (inclusi il controller virtuale CoreGraphics/CoreHaptics, il server locale 2P su \`Network.framework\`, la Modalità TV Dual-Screen AirPlay/HDMI, la localizzazione multi-lingua, il bridge App File iOS e la pipeline GitHub Actions Zero-Mac) è stato progettato, iterato e verificato da **hiperema** con il supporto assistito di **Google AI Studio**.

Tutte le scelte architetturali, i test reali su hardware iOS (Feather e LiveContainer), il debugging su dispositivo fisico e la pubblicazione del codice sono sotto la responsabilità del manutentore del repository.

---

## 5. Licenza del Codice di Porting e Componenti di Terze Parti

Il codice sorgente originale del layer iOS contenuto in questo repository (file in \`ios/\`, \`cmake/\`, \`scripts/\`, \`.github/\` e tool di generazione) è rilasciato come software open-source in armonia con la licenza del progetto upstream **ShadowRecomp** (GNU General Public License v3.0 — testo ufficiale consultabile su [gnu.org/licenses/gpl-3.0](https://www.gnu.org/licenses/gpl-3.0.html)).

I progetti esterni scaricati o integrati durante la build mantengono le rispettive licenze e copyright originali:

| Componente | Repository / Fonte | Licenza |
| :--- | :--- | :--- |
| **ShadowRecomp** (\`XboxRecomp2\`, \`XShaderRecomp\`, \`Plume\`) | [FoxWorkshop/ShadowRecomp](${cleanUpstream}) | Licenza del repository upstream |
| **MarathonRecompilediOS** (riferimento architetturale) | [DevZer0D4Y/MarathonRecompilediOS](${config.iosRefRepoUrl}) | Licenza del repository upstream |
| **MoltenVK** | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache License 2.0 |
| **SDL3** | [libsdl-org/SDL](https://github.com/libsdl-org/SDL) | zlib License |
| **FreeType** | [freetype.org](https://freetype.org/) | FreeType License (FTL) / GPL |
| **Dear ImGui** | [ocornut/imgui](https://github.com/ocornut/imgui) | MIT License |
| **ldid** | [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid) | BSD-style Open-Source License |

---

## 6. Esclusione di Garanzia e Limitazione di Responsabilità

Questo software è fornito **"COSÌ COM'È" ("AS IS")**, senza alcuna garanzia esplicita o implicita di commerciabilità, idoneità a uno scopo particolare, continuità di funzionamento o assenza di difetti. In nessun caso l'autore o i contributori potranno essere ritenuti responsabili per danni diretti, indiretti, incidentali o consequenziali (inclusi perdita di dati, surriscaldamento o problemi legati a procedure di sideloading) derivanti dall'uso o dall'impossibilità di usare questo software.

---

## 7. Segnalazioni e Rimozioni (Notice & Takedown)

Qualora un titolare di diritti ritenga che un contenuto presente in questo repository violi involontariamente i propri diritti di proprietà intellettuale, è invitato ad aprire una segnalazione dettagliata tramite il repository GitHub: il materiale segnalato verrà esaminato e, se necessario, rimosso tempestivamente.
`;
}

export function generateEdgyIosReleaseNotesMd(config: DocsTemplateConfig): string {
  const cleanUpstream = config.upstreamRepoUrl.replace(/\.git$/, '');
  return `# EdgyiOS v${config.appVersion} — Shadow The Hedgehog Recompiled for iOS

Prima release stabile completa del porting iOS / iPadOS nativo di [FoxWorkshop/ShadowRecomp](${cleanUpstream}), sviluppata da **hiperema** con **Google AI Studio**.

> **Zero asset di gioco inclusi:** l'\`.ipa\` contiene solo il motore ricompilato nativo arm64 e i moduli iOS. Al primo avvio importa i file estratti dalla **tua copia originale legalmente posseduta** di *Shadow the Hedgehog (2005)* tramite l'App File di iOS.

---

## Novità Principali di v${config.appVersion}

### Motore Nativo, Risoluzione & 120Hz ProMotion
- **Esecuzione nativa arm64 + Metal 3 (MoltenVK)** senza JIT, con sblocco **120Hz ProMotion** e pieno supporto a **Feather** (standalone) e **LiveContainer** (\`-fPIC -Wl,-pie\`).
- **Risoluzione nativa full-screen** su iPhone e iPad tramite \`UILaunchScreen\` (es. \`2622×1206\` su iPhone 16 Pro, risolto lo scaling 1440×960 su Feather).
- **Sospensione/Ripresa GPU Metal sicura**: drenaggio sincronizzato su blocco schermo o cambio app e recovery automatico della swapchain senza crash o freeze.
- **Icona iOS personalizzata** compilata in \`Assets.car\` + crediti localizzati nell'installer (*"Porting iOS sviluppato da hiperema"*).

### Controller Virtuale Xbox Original & CoreHaptics
- **Overlay vettoriale a tema Shadow** con analogico sinistro ad emblema 3D-tilt/pressione, D-Pad scorrevole, ABXY, grilletti analogici \`LT/RT\`, \`LB/RB\`, \`L3/R3\`, \`Start/Back\` e **Chaos Emerald Quick-HUD** (aura Hero/Neutral/Dark).
- **Taptic Engine CoreHaptics**: click meccanici, detent analogici e rumble del gioco in tempo reale.
- **Auto-hide 4s** con risveglio istantaneo al tocco, opacità regolabile salvata e scomparsa automatica con controller fisici (DualSense, Xbox, Backbone, MFi).

### Multiplayer 2 Giocatori (Hotspot / Wi-Fi — iOS & Android)
- **Server HTTP + WebSocket locale integrato** (\`Network.framework\`, porta \`8765\`, zero internet richiesto, zero impatto sui 120 FPS).
- **QR Code nativo + link copiato** con pillola **Abbina → Connesso** che scompare automaticamente dopo 3,5 secondi e avvisa solo in caso di disconnessione.
- **Web Controller 2P cross-platform** con bottoni grandi giocabili alla cieca su qualsiasi smartphone Android o iPhone.

### Modalità TV Dedicata (AirPlay & HDMI Dual-Screen)
- **Pulsante TV** nel menu Smeraldo attivo automaticamente al collegamento AirPlay o HDMI.
- **Zero bottoni virtuali sulla TV**: sulla TV appare solo il gioco pulito a schermo intero (no overscan, cap 1080p anti-Jetsam su TV 4K), mentre sull'iPhone restano i comandi virtuali ingranditi su sfondo scuro con aptica completa e supporto 2P.
- **Ripresa fluida senza freeze** dopo blocco schermo o cambio app in Modalità TV, con ritorno automatico su iPhone se AirPlay/HDMI viene scollegato.

### Lingua Automatica di Sistema (6 Lingue)
- Rilevamento automatico all'avvio di **Italiano, Inglese, Spagnolo, Francese, Tedesco e Giapponese** su tutta l'UI iOS, sul selettore File nativo e sul controller web del secondo smartphone.

---

## Dispositivi Compatibili (iOS / iPadOS ${config.deploymentTarget}+)
- **Consigliati (120Hz ProMotion):** iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro (e Pro Max), iPad Pro M1 / M2 / M4.
- **Ottimi (60Hz):** iPhone 13 / 14 / 15 / 16 / 16e / 17, iPhone 12 Pro, iPhone SE 3ª gen, iPad Air M1/M2/M3, iPad mini 6/7.
- **Supporto base (60Hz):** iPhone XS / XR / 11 / 12 / SE 2ª gen, iPad 9ª/10ª/11ª gen (su dispositivi con 3–4 GB di RAM chiudere le app in background).

---

## Installazione Rapida
1. Scarica **\`${config.appName}-iOS.ipa\`** e verifica facoltativamente l'impronta in \`SHA256SUMS-${config.appName}.txt\`.
2. Installa con **Feather** o importa in **LiveContainer**.
3. Al primo avvio seleziona i file estratti dalla tua copia originale Xbox tramite l'**App File di iOS** e riavvia il gioco al termine dell'importazione.

---

## Note Legali
Nessun asset protetto da copyright è incluso in questa release. Consulta [LEGAL.md](LEGAL.md) e [README.md](README.md) per tutte le informazioni legali, i crediti e le licenze dei progetti open-source utilizzati.
`;
}
