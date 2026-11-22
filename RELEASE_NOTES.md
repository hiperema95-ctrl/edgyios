# EdgyiOS v1.0.0 — Shadow The Hedgehog Recompiled for iOS

Prima release stabile completa del porting iOS / iPadOS nativo di [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp), sviluppata da **hiperema** con **Google AI Studio**.

> **Zero asset di gioco inclusi:** l'`.ipa` contiene solo il motore ricompilato nativo arm64 e i moduli iOS. Al primo avvio importa i file estratti dalla **tua copia originale legalmente posseduta** di *Shadow the Hedgehog (2005)* tramite l'App File di iOS.

---

## Novità Principali di v1.0.0

### Motore Nativo, Risoluzione & 120Hz ProMotion
- **Esecuzione nativa arm64 + Metal 3 (MoltenVK)** senza JIT, con sblocco **120Hz ProMotion** e pieno supporto a **Feather** (standalone) e **LiveContainer** (`-fPIC -Wl,-pie`).
- **Risoluzione nativa full-screen** su iPhone e iPad tramite `UILaunchScreen` (es. `2622×1206` su iPhone 16 Pro, risolto lo scaling 1440×960 su Feather).
- **Sospensione/Ripresa GPU Metal sicura**: drenaggio sincronizzato su blocco schermo o cambio app e recovery automatico della swapchain senza crash o freeze.
- **Icona iOS personalizzata** compilata in `Assets.car` + crediti localizzati nell'installer (*"Porting iOS sviluppato da hiperema"*).

### Controller Virtuale Xbox Original & CoreHaptics
- **Overlay vettoriale a tema Shadow** con analogico sinistro ad emblema 3D-tilt/pressione, D-Pad scorrevole, ABXY, grilletti analogici `LT/RT`, `LB/RB`, `L3/R3`, `Start/Back` e **Chaos Emerald Quick-HUD** (aura Hero/Neutral/Dark).
- **Taptic Engine CoreHaptics**: click meccanici, detent analogici e rumble del gioco in tempo reale.
- **Auto-hide 4s** con risveglio istantaneo al tocco, opacità regolabile salvata e scomparsa automatica con controller fisici (DualSense, Xbox, Backbone, MFi).

### Multiplayer 2 Giocatori (Hotspot / Wi-Fi — iOS & Android)
- **Server HTTP + WebSocket locale integrato** (`Network.framework`, porta `8765`, zero internet richiesto, zero impatto sui 120 FPS).
- **QR Code nativo + link copiato** con pillola **Abbina → Connesso** che scompare automaticamente dopo 3,5 secondi e avvisa solo in caso di disconnessione.
- **Web Controller 2P cross-platform** con bottoni grandi giocabili alla cieca su qualsiasi smartphone Android o iPhone.

### Modalità TV Dedicata (AirPlay & HDMI Dual-Screen)
- **Pulsante TV** nel menu Smeraldo attivo automaticamente al collegamento AirPlay o HDMI.
- **Zero bottoni virtuali sulla TV**: sulla TV appare solo il gioco pulito a schermo intero (no overscan, cap 1080p anti-Jetsam su TV 4K), mentre sull'iPhone restano i comandi virtuali ingranditi su sfondo scuro con aptica completa e supporto 2P.
- **Ripresa fluida senza freeze** dopo blocco schermo o cambio app in Modalità TV, con ritorno automatico su iPhone se AirPlay/HDMI viene scollegato.

### Lingua Automatica di Sistema (6 Lingue)
- Rilevamento automatico all'avvio di **Italiano, Inglese, Spagnolo, Francese, Tedesco e Giapponese** su tutta l'UI iOS, sul selettore File nativo e sul controller web del secondo smartphone.

---

## Dispositivi Compatibili (iOS / iPadOS 17.0+)
- **Consigliati (120Hz ProMotion):** iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro (e Pro Max), iPad Pro M1 / M2 / M4.
- **Ottimi (60Hz):** iPhone 13 / 14 / 15 / 16 / 16e / 17, iPhone 12 Pro, iPhone SE 3ª gen, iPad Air M1/M2/M3, iPad mini 6/7.
- **Supporto base (60Hz):** iPhone XS / XR / 11 / 12 / SE 2ª gen, iPad 9ª/10ª/11ª gen (su dispositivi con 3–4 GB di RAM chiudere le app in background).

---

## Installazione Rapida
1. Scarica **`ShadowRecomp-iOS.ipa`** e verifica facoltativamente l'impronta in `SHA256SUMS-ShadowRecomp.txt`.
2. Installa con **Feather** o importa in **LiveContainer**.
3. Al primo avvio seleziona i file estratti dalla tua copia originale Xbox tramite l'**App File di iOS** e riavvia il gioco al termine dell'importazione.

---

## Note Legali
Nessun asset protetto da copyright è incluso in questa release. Consulta [LEGAL.md](LEGAL.md) e [README.md](README.md) per tutte le informazioni legali, i crediti e le licenze dei progetti open-source utilizzati.
