# Note Legali, Licenze e Disclaimer — EdgyiOS

**Progetto:** EdgyiOS: Shadow The Hedgehog Recompiled for iOS  
**Autore del porting iOS:** hiperema  
**Versione:** v1.0.0  

---

## 1. Politica "Zero Copyrighted Assets"

Questo repository GitHub e qualsiasi pacchetto `.ipa` generato tramite il workflow CI incluso **non contengono alcun file protetto da copyright** appartenente a *Shadow the Hedgehog (2005)* o a terze parti commerciali. In particolare, **non sono inclusi e non saranno mai distribuiti**:

- Eseguibili originali Xbox (`default.xbe`);
- Immagini disco (`*.iso`, `*.xiso`);
- Archivi di gioco, texture, modelli 3D, livelli, audio, musiche o filmati (`*.afs`, `*.one`, `*.txd`, `*.adx`, `*.sfd`, ecc.).

Il file `.gitignore` del repository è configurato esplicitamente per impedire il commit accidentale di tali formati. L'applicazione compilata funge esclusivamente da **motore nativo di ricompilazione/esecuzione** e rimane inutilizzabile senza i file estratti dalla copia originale dell'utente.

---

## 2. Proprietà Legale, Interoperabilità e Anti-Pirateria

- Per compilare e utilizzare **EdgyiOS** è obbligatorio possedere una **copia fisica o digitale originale e legalmente acquistata** di *Shadow the Hedgehog* per Xbox Original.
- L'estrazione dei file dalla propria copia legittimamente detenuta a scopo di backup personale, preservazione digitale e interoperabilità su hardware moderno rientra nei principi riconosciuti dal diritto d'autore in materia di copia privata e interoperabilità (es. Direttiva UE 2009/24/CE e corrispondenti normative nazionali applicabili; ogni utente è tenuto a verificare e rispettare le leggi vigenti nella propria giurisdizione).
- Il progetto **condanna fermamente la pirateria**: qualsiasi richiesta o condivisione di ROM, ISO, XISO, file `.xbe` o asset protetti da copyright su Issues, Discussions o Pull Request verrà immediatamente rimossa.

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

Il layer di porting iOS di **EdgyiOS** (inclusi il controller virtuale CoreGraphics/CoreHaptics, il server locale 2P su `Network.framework`, la Modalità TV Dual-Screen AirPlay/HDMI, la localizzazione multi-lingua, il bridge App File iOS e la pipeline GitHub Actions Zero-Mac) è stato progettato, iterato e verificato da **hiperema** con il supporto assistito di **Google AI Studio**.

Tutte le scelte architetturali, i test reali su hardware iOS (Feather e LiveContainer), il debugging su dispositivo fisico e la pubblicazione del codice sono sotto la responsabilità del manutentore del repository.

---

## 5. Licenza del Codice di Porting e Componenti di Terze Parti

Il codice sorgente originale del layer iOS contenuto in questo repository (file in `ios/`, `cmake/`, `scripts/`, `.github/` e tool di generazione) è rilasciato come software open-source in armonia con la licenza del progetto upstream **ShadowRecomp** (GNU General Public License v3.0 — testo ufficiale consultabile su [gnu.org/licenses/gpl-3.0](https://www.gnu.org/licenses/gpl-3.0.html)).

I progetti esterni scaricati o integrati durante la build mantengono le rispettive licenze e copyright originali:

| Componente | Repository / Fonte | Licenza |
| :--- | :--- | :--- |
| **ShadowRecomp** (`XboxRecomp2`, `XShaderRecomp`, `Plume`) | [FoxWorkshop/ShadowRecomp](https://github.com/FoxWorkshop/ShadowRecomp) | Licenza del repository upstream |
| **MarathonRecompilediOS** (riferimento architetturale) | [DevZer0D4Y/MarathonRecompilediOS](https://github.com/DevZer0D4Y/MarathonRecompilediOS) | Licenza del repository upstream |
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
