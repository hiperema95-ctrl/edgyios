# ShadowRecomp iOS Port (Stile MarathonRecompilediOS — Zero File Protetti su Git)

Porting iOS per **iPhone 16 Pro (arm64)** di [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp), basato sullo stesso flusso di [DevZer0D4Y/MarathonRecompilediOS](https://github.com/DevZer0D4Y/MarathonRecompilediOS).
Tutta la compilazione avviene nel cloud su **GitHub Actions (`macos-15`)**, senza bisogno di un Mac.

## 100% Pulito sul Repository GitHub
- Questo repository contiene **ZERO file protetti da copyright** (`.gitignore` blocca `*.xbe`, `*.iso`, `*.xiso` e `private/`).
- Esattamente come `MarathonRecompilediOS` (`Sonic06-iOS.ipa`, ~35 MB): l'`.ipa` finale **non contiene nessun asset di gioco** (texture, livelli, audio, filmati).
- Al primo avvio dell'`.ipa` su **iPhone 16 Pro** (installato da **Feather** o **LiveContainer**), l'app apre l'**App File di iOS** per farti selezionare la cartella con i file estratti dalla tua `.xiso`, completa l'importazione, e al riavvio il gioco parte!

## Come compilare l'`.ipa` su GitHub Actions senza MAI caricare `default.xbe` nel repo
1. Carica tutti i file di questo pacchetto nel tuo repository GitHub.
2. Vai su **Settings → Secrets and variables → Actions → New repository secret**.
3. Crea il Secret cifrato **`DEFAULT_XBE_URL`** con un link diretto temporaneo/privato al tuo `default.xbe` (~4.8 MB).
   - Il Secret è cifrato e invisibile a tutti; `default.xbe` viene scaricato **solo** nella VM temporanea `macos-15` durante la compilazione di `XboxRecomp2` e distrutto subito a fine build.
4. Vai su **Actions → Build ShadowRecomp iOS Unsigned IPA → Run workflow** *(opzionale: spunta `publish_release` se vuoi creare una Release con `ShadowRecomp-iOS.ipa` come `MarathonRecompilediOS`)* e scarica il file `.ipa` su iPhone!