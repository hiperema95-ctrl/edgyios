// ios/ios_virtual_controller.mm
// Controller virtuale Xbox Original a tema Shadow the Hedgehog per iPhone 16 Pro (120Hz ProMotion)
// - Grafica vettoriale CoreGraphics/QuartzCore in vetro ossidiana traslucido + bagliore cremisi
// - Analogico sinistro con emblema Shadow & anello uncinato con fisica 3D tilt e sensibilità alla pressione
// - Analogico destro camera + D-Pad 8 direzioni scorrevole + ABXY Xbox Original + LT/LB/L3 & RT/RB/R3
// - Barra navigazione (Pausa / Chaos Emerald Quick-HUD / Indietro) con colore aura dinamico Hero/Neutral/Dark
// - Feedback aptico CoreHaptics (click meccanico pressione/rilascio, detent analogici, rumble di gioco)
// - Auto-scomparsa totale al collegamento di qualsiasi controller fisico (GameController + SDL3)
// - Dissolvenza automatica dopo 4 secondi di inattività + riapparizione istantanea al tocco dello schermo

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>

#include <ios_virtual_controller.h>
#include <ios_p2_server.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <unordered_map>

extern "C" void ShadowIOS_VideoOnWillEnterBackground(void);
extern "C" void ShadowIOS_VideoOnDidEnterForeground(void);
extern "C" void ShadowIOS_VideoRequestSwapChainRebuild(void);

namespace {

// Costanti bitmask Xbox Original identiche a ShadowRecomp/input/input.h
constexpr uint16_t kXboxDPadUp     = 0x0001;
constexpr uint16_t kXboxDPadDown   = 0x0002;
constexpr uint16_t kXboxDPadLeft   = 0x0004;
constexpr uint16_t kXboxDPadRight  = 0x0008;
constexpr uint16_t kXboxStart      = 0x0010;
constexpr uint16_t kXboxBack       = 0x0020;
constexpr uint16_t kXboxLeftThumb  = 0x0040;
constexpr uint16_t kXboxRightThumb = 0x0080;

// Indici bAnalogButtons[8] identici a enum bAnalogBtnE in ShadowRecomp/input/input.h
constexpr int kBtnA     = 0;
constexpr int kBtnB     = 1;
constexpr int kBtnX     = 2;
constexpr int kBtnY     = 3;
constexpr int kBtnBlack = 4; // RB (Pad1P_Black = RightShoulder)
constexpr int kBtnWhite = 5; // LB (Pad1P_White = LeftShoulder)
constexpr int kBtnLT    = 6; // Left Trigger analogico 0..255
constexpr int kBtnRT    = 7; // Right Trigger analogico 0..255

constexpr NSTimeInterval kAutoHideIdleSeconds = 4.0;
constexpr NSTimeInterval kP2ConnectedPillAutoHideSeconds = 3.5;

enum class ShadowUILang : int {
    English = 0,
    Italian = 1,
    Spanish = 2,
    French  = 3,
    German  = 4,
    Japanese = 5
};

struct ShadowLocalizedStrings {
    __unsafe_unretained NSString *opacityFmt;
    __unsafe_unretained NSString *tvFullOpacity;
    __unsafe_unretained NSString *hapticsOn;
    __unsafe_unretained NSString *hapticsOff;
    __unsafe_unretained NSString *autoHideOn;
    __unsafe_unretained NSString *autoHideOff;
    __unsafe_unretained NSString *pairing;
    __unsafe_unretained NSString *connected;
    __unsafe_unretained NSString *cardTitleDefault;
    __unsafe_unretained NSString *cardTitleHotspot;
    __unsafe_unretained NSString *cardTitleWifi;
    __unsafe_unretained NSString *cardSub;
    __unsafe_unretained NSString *cardCopy;
    __unsafe_unretained NSString *cardClose;
    __unsafe_unretained NSString *toastP2Connected;
    __unsafe_unretained NSString *toastP2Disconnected;
    __unsafe_unretained NSString *toastP2ConnectedLinkFmt;
    __unsafe_unretained NSString *toastLinkCopiedFmt;
    __unsafe_unretained NSString *toastServerError;
    __unsafe_unretained NSString *toastTVNeedExt;
    __unsafe_unretained NSString *toastTVReady;
    __unsafe_unretained NSString *toastTVDisconnected;
    __unsafe_unretained NSString *toastTVVideoNotReady;
    __unsafe_unretained NSString *toastTVEnabled;
    __unsafe_unretained NSString *toastTVDisabled;
};

static ShadowUILang DetectSystemUILanguage(void) {
    static ShadowUILang s_lang = []() -> ShadowUILang {
        NSString *preferred = [NSLocale preferredLanguages].firstObject;
        if (preferred.length == 0) {
            preferred = [NSLocale currentLocale].localeIdentifier;
        }
        NSString *lc = [preferred lowercaseString];
        if ([lc hasPrefix:@"it"]) return ShadowUILang::Italian;
        if ([lc hasPrefix:@"es"]) return ShadowUILang::Spanish;
        if ([lc hasPrefix:@"fr"]) return ShadowUILang::French;
        if ([lc hasPrefix:@"de"]) return ShadowUILang::German;
        if ([lc hasPrefix:@"ja"]) return ShadowUILang::Japanese;
        return ShadowUILang::English;
    }();
    return s_lang;
}

static const ShadowLocalizedStrings &L(void) {
    static const ShadowLocalizedStrings kTables[6] = {
        // 0: English (universal fallback)
        {
            @"Opacity %d%%",
            @"TV 100%",
            @"Haptics ON",
            @"Haptics OFF",
            @"Auto-Hide 4s",
            @"Always On",
            @"Pairing",
            @"Connected",
            @"2P CONTROLLER • PAIRING",
            @"2P • HOTSPOT READY",
            @"2P • LOCAL WI-FI",
            @"Scan this QR on Smartphone 2 (Hotspot or same Wi-Fi) or paste the copied link.",
            @"Copy Link",
            @"Close",
            @"2P Controller connected!",
            @"2P Controller disconnected — tap Pairing to reconnect",
            @"2P Connected • Link copied: %@",
            @"Link copied: %@",
            @"2P server error — allow Local Network in Settings",
            @"Connect AirPlay or HDMI to enable TV Mode",
            @"AirPlay/HDMI detected — TV Mode ready",
            @"AirPlay/HDMI disconnected — game returned to iPhone",
            @"Video screen not ready — try again in a moment",
            @"TV Mode active • Game on TV, Gamepad on iPhone",
            @"TV Mode disabled — game returned to iPhone"
        },
        // 1: Italian
        {
            @"Opacità %d%%",
            @"TV 100%",
            @"Aptica SÌ",
            @"Aptica NO",
            @"Sfuma 4s",
            @"Fisso",
            @"Abbina",
            @"Connesso",
            @"CONTROLLER 2P • ABBINA",
            @"2P • HOTSPOT PRONTO",
            @"2P • WI-FI LOCALE",
            @"Inquadra il QR con Smartphone 2 (su Hotspot o stesso Wi-Fi) oppure incolla il link copiato.",
            @"Copia Link",
            @"Chiudi",
            @"Controller 2P connesso!",
            @"Controller 2P disconnesso — tocca Abbina per riconnettere",
            @"2P Connesso • Link copiato: %@",
            @"Link copiato: %@",
            @"Errore avvio server 2P — consenti Rete Locale in Impostazioni",
            @"Collega AirPlay o HDMI per attivare la Modalità TV",
            @"AirPlay/HDMI rilevato — Modalità TV disponibile",
            @"AirPlay/HDMI disconnesso — gioco tornato su iPhone",
            @"Schermo video non pronto — riprova tra un istante",
            @"Modalità TV attiva • Gioco su TV, Controller su iPhone",
            @"Modalità TV disattivata — gioco tornato su iPhone"
        },
        // 2: Spanish
        {
            @"Opacidad %d%%",
            @"TV 100%",
            @"Háptica SÍ",
            @"Háptica NO",
            @"Ocultar 4s",
            @"Fijo",
            @"Vincular",
            @"Conectado",
            @"MANDO 2P • VINCULAR",
            @"2P • HOTSPOT LISTO",
            @"2P • WI-FI LOCAL",
            @"Escanea el QR con el Smartphone 2 (en Hotspot o mismo Wi-Fi) o pega el enlace copiado.",
            @"Copiar enlace",
            @"Cerrar",
            @"¡Mando 2P conectado!",
            @"Mando 2P desconectado — toca Vincular para reconectar",
            @"2P Conectado • Enlace copiado: %@",
            @"Enlace copiado: %@",
            @"Error del servidor 2P — permite Red Local en Ajustes",
            @"Conecta AirPlay o HDMI para activar el Modo TV",
            @"AirPlay/HDMI detectado — Modo TV disponible",
            @"AirPlay/HDMI desconectado — juego devuelto al iPhone",
            @"Pantalla de vídeo no lista — inténtalo en un momento",
            @"Modo TV activo • Juego en TV, Mando en iPhone",
            @"Modo TV desactivado — juego devuelto al iPhone"
        },
        // 3: French
        {
            @"Opacité %d%%",
            @"TV 100%",
            @"Haptique OUI",
            @"Haptique NON",
            @"Masquer 4s",
            @"Fixe",
            @"Jumeler",
            @"Connecté",
            @"MANETTE 2J • JUMELAGE",
            @"2J • PARTAGE PRÊT",
            @"2J • WI-FI LOCAL",
            @"Scannez le QR avec le Smartphone 2 (Partage ou même Wi-Fi) ou collez le lien copié.",
            @"Copier le lien",
            @"Fermer",
            @"Manette 2J connectée !",
            @"Manette 2J déconnectée — touchez Jumeler pour reconnecter",
            @"2J Connecté • Lien copié : %@",
            @"Lien copié : %@",
            @"Erreur serveur 2J — autorisez Réseau local dans Réglages",
            @"Connectez AirPlay ou HDMI pour activer le Mode TV",
            @"AirPlay/HDMI détecté — Mode TV disponible",
            @"AirPlay/HDMI déconnecté — jeu revenu sur iPhone",
            @"Écran vidéo non prêt — réessayez dans un instant",
            @"Mode TV actif • Jeu sur TV, Manette sur iPhone",
            @"Mode TV désactivé — jeu revenu sur iPhone"
        },
        // 4: German
        {
            @"Deckkraft %d%%",
            @"TV 100%",
            @"Haptik EIN",
            @"Haptik AUS",
            @"Ausbl. 4s",
            @"Immer an",
            @"Koppeln",
            @"Verbunden",
            @"2P-CONTROLLER • KOPPELN",
            @"2P • HOTSPOT BEREIT",
            @"2P • LOKALES WLAN",
            @"Scanne den QR auf Smartphone 2 (Hotspot oder gleiches WLAN) oder füge den Link ein.",
            @"Link kopieren",
            @"Schließen",
            @"2P-Controller verbunden!",
            @"2P-Controller getrennt — tippe auf Koppeln",
            @"2P Verbunden • Link kopiert: %@",
            @"Link kopiert: %@",
            @"2P-Serverfehler — erlaube Lokales Netzwerk in Einstellungen",
            @"Verbinde AirPlay oder HDMI für den TV-Modus",
            @"AirPlay/HDMI erkannt — TV-Modus bereit",
            @"AirPlay/HDMI getrennt — Spiel zurück auf iPhone",
            @"Videobild nicht bereit — kurz warten und erneut versuchen",
            @"TV-Modus aktiv • Spiel auf TV, Controller auf iPhone",
            @"TV-Modus beendet — Spiel zurück auf iPhone"
        },
        // 5: Japanese
        {
            @"透明度 %d%%",
            @"TV 100%",
            @"触覚 ON",
            @"触覚 OFF",
            @"自動非表示 4s",
            @"常時表示",
            @"ペアリング",
            @"接続済み",
            @"2Pコントローラー • ペアリング",
            @"2P • テザリング準備完了",
            @"2P • ローカルWi-Fi",
            @"スマホ2（同じWi-Fiまたはテザリング）でQRを読み取るか、コピーしたリンクを開いてください。",
            @"リンクをコピー",
            @"閉じる",
            @"2Pコントローラー接続完了！",
            @"2P切断 — ペアリングをタップして再接続",
            @"2P接続済み • コピー完了: %@",
            @"リンクをコピー: %@",
            @"2Pサーバー起動エラー — 設定でローカルネットワークを許可",
            @"TVモードを使うにはAirPlayまたはHDMIを接続してください",
            @"AirPlay/HDMIを検出 — TVモード利用可能",
            @"AirPlay/HDMI切断 — ゲームがiPhoneに戻りました",
            @"映像画面の準備中 — 少し待ってから再試行してください",
            @"TVモード有効 • TVにゲーム、iPhoneにコントローラー",
            @"TVモード解除 — ゲームがiPhoneに戻りました"
        }
    };
    return kTables[static_cast<int>(DetectSystemUILanguage())];
}

IOSVirtualPadSnapshot g_padSlots[4]{};
std::atomic<uint32_t> g_padActiveSlot{0};
std::atomic<bool> g_overlayAttached{false};
std::atomic<bool> g_lastPhysicalSDL{false};
std::atomic<bool> g_lastInstallerVisible{true};
std::atomic<int>  g_lastChaosAura{0};

static inline float ClampF(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline int16_t FloatToXboxAxis(float v) {
    float c = ClampF(v, -1.0f, 1.0f);
    int32_t raw = static_cast<int32_t>(std::lround(c * 32767.0f));
    if (raw < -32768) raw = -32768;
    if (raw > 32767) raw = 32767;
    return static_cast<int16_t>(raw);
}

// Calcola la pressione normalizzata (0.0..1.0) su iPhone 16 Pro combinando
// force (se disponibile) e majorRadius (area di contatto del polpastrello a 120Hz)
static inline float ComputeTouchPressure01(UITouch *touch) {
    if (!touch) return 0.65f;
    if (touch.maximumPossibleForce > 0.01) {
        return ClampF(static_cast<float>(touch.force / touch.maximumPossibleForce), 0.15f, 1.0f);
    }
    CGFloat radius = touch.majorRadius;
    if (radius > 1.0) {
        // Polpastrello leggero ~15pt -> 0.25, pressione decisa ~32pt -> 1.0
        return ClampF(static_cast<float>((radius - 13.0) / 19.0), 0.20f, 1.0f);
    }
    return 0.65f;
}

static inline UIColor *ShadowCrimsonColor(CGFloat alpha) {
    return [UIColor colorWithRed:0.937 green:0.137 blue:0.235 alpha:alpha]; // #EF233C
}

static inline UIColor *ChaosAuraColor(int mode, CGFloat alpha) {
    if (mode == 1) {
        // Hero Aura: azzurro Chaos Control
        return [UIColor colorWithRed:0.220 green:0.741 blue:0.973 alpha:alpha];
    }
    if (mode == 2) {
        // Dark Aura: rosso-viola Chaos Blast
        return [UIColor colorWithRed:1.000 green:0.090 blue:0.267 alpha:alpha];
    }
    return ShadowCrimsonColor(alpha);
}

// Helper: costruisce il path vettoriale aerodinamico delle alette LT/LB/L3 e RT/RB/R3
enum class WingShapeStyle : int {
    UpperTrigger = 0, // LT / RT
    LowerBumper  = 1, // LB / RB
    InnerBlade   = 2  // L3 / R3
};

static UIBezierPath *BuildWingBladePath(CGRect rect, WingShapeStyle style, BOOL mirroredRight) {
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    UIBezierPath *p = [UIBezierPath bezierPath];

    auto pt = [&](CGFloat nx, CGFloat ny) -> CGPoint {
        CGFloat x = mirroredRight ? (1.0 - nx) * w : nx * w;
        return CGPointMake(rect.origin.x + x, rect.origin.y + ny * h);
    };

    if (style == WingShapeStyle::UpperTrigger) {
        // Ala superiore affilata come nel concept LT/RT
        [p moveToPoint:pt(0.04, 0.84)];
        [p addQuadCurveToPoint:pt(0.42, 0.14) controlPoint:pt(0.14, 0.24)];
        [p addLineToPoint:pt(0.92, 0.08)];
        [p addQuadCurveToPoint:pt(0.97, 0.34) controlPoint:pt(0.99, 0.12)];
        [p addLineToPoint:pt(0.88, 0.78)];
        [p addQuadCurveToPoint:pt(0.76, 0.92) controlPoint:pt(0.85, 0.91)];
        [p addLineToPoint:pt(0.10, 0.94)];
        [p addQuadCurveToPoint:pt(0.04, 0.84) controlPoint:pt(0.02, 0.93)];
        [p closePath];
    } else if (style == WingShapeStyle::LowerBumper) {
        // Ala inferiore affusolata come nel concept LB/RB
        [p moveToPoint:pt(0.05, 0.82)];
        [p addQuadCurveToPoint:pt(0.48, 0.14) controlPoint:pt(0.18, 0.22)];
        [p addLineToPoint:pt(0.90, 0.10)];
        [p addQuadCurveToPoint:pt(0.96, 0.42) controlPoint:pt(0.98, 0.18)];
        [p addLineToPoint:pt(0.90, 0.80)];
        [p addQuadCurveToPoint:pt(0.80, 0.92) controlPoint:pt(0.88, 0.92)];
        [p addLineToPoint:pt(0.12, 0.92)];
        [p addQuadCurveToPoint:pt(0.05, 0.82) controlPoint:pt(0.02, 0.90)];
        [p closePath];
    } else {
        // Ala interna triangolare angolata (L3 / R3) fedele alla terza ala del concept
        [p moveToPoint:pt(0.08, 0.10)];
        [p addLineToPoint:pt(0.90, 0.10)];
        [p addQuadCurveToPoint:pt(0.94, 0.26) controlPoint:pt(0.99, 0.12)];
        [p addQuadCurveToPoint:pt(0.50, 0.62) controlPoint:pt(0.72, 0.38)];
        [p addQuadCurveToPoint:pt(0.24, 0.93) controlPoint:pt(0.36, 0.82)];
        [p addQuadCurveToPoint:pt(0.08, 0.84) controlPoint:pt(0.14, 0.98)];
        [p addLineToPoint:pt(0.04, 0.20)];
        [p addQuadCurveToPoint:pt(0.08, 0.10) controlPoint:pt(0.03, 0.11)];
        [p closePath];
    }
    return p;
}

// Disegna il bagliore a punte cremisi a 8 lame attorno all'analogico sinistro
static void DrawShadowSpikyRing(CGContextRef ctx, CGPoint center, CGFloat innerR, CGFloat outerR, UIColor *accent, CGFloat glowIntensity) {
    CGContextSaveGState(ctx);
    UIBezierPath *star = [UIBezierPath bezierPath];
    const int spikes = 8;
    for (int i = 0; i < spikes; i++) {
        CGFloat angleTip = (CGFloat)i * (M_PI * 2.0 / spikes) - M_PI_2;
        CGFloat angleNextValley = angleTip + (M_PI / spikes);
        CGFloat tipR = (i % 2 == 0) ? outerR : (outerR * 0.92);
        CGFloat valleyR = innerR * 0.96;

        CGPoint tip = CGPointMake(center.x + std::cos(angleTip) * tipR, center.y + std::sin(angleTip) * tipR);
        CGPoint valley = CGPointMake(center.x + std::cos(angleNextValley) * valleyR, center.y + std::sin(angleNextValley) * valleyR);

        if (i == 0) {
            [star moveToPoint:tip];
        } else {
            [star addLineToPoint:tip];
        }
        [star addQuadCurveToPoint:valley
                     controlPoint:CGPointMake(center.x + std::cos(angleTip + 0.18) * (innerR * 1.04),
                                              center.y + std::sin(angleTip + 0.18) * (innerR * 1.04))];
    }
    [star closePath];

    CGContextSetShadowWithColor(ctx, CGSizeZero, 4.0 + 6.0 * glowIntensity,
                                [accent colorWithAlphaComponent:0.55 + 0.35 * glowIntensity].CGColor);
    [[accent colorWithAlphaComponent:0.82 + 0.18 * glowIntensity] setFill];
    [star fill];

    // Anello interno scuro per staccare il medaglione centrale
    UIBezierPath *hole = [UIBezierPath bezierPathWithArcCenter:center radius:innerR * 0.86 startAngle:0 endAngle:M_PI * 2.0 clockwise:YES];
    [[UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.96] setFill];
    [hole fill];

    // Bordo luminoso interno
    [[accent colorWithAlphaComponent:0.65 + 0.30 * glowIntensity] setStroke];
    hole.lineWidth = 1.4;
    [hole stroke];
    CGContextRestoreGState(ctx);
}

// Disegna l'emblema tribale di Shadow the Hedgehog al centro dell'analogico sinistro
static void DrawShadowEmblem(CGContextRef ctx, CGPoint c, CGFloat r, UIColor *accent, CGFloat glowIntensity) {
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 3.0 + 4.0 * glowIntensity,
                                [accent colorWithAlphaComponent:0.75].CGColor);
    [[accent colorWithAlphaComponent:0.92] setFill];

    auto pt = [&](CGFloat nx, CGFloat ny) -> CGPoint {
        return CGPointMake(c.x + nx * r, c.y + ny * r);
    };

    // Silhouette principale stilizzata con le 3 punte swept-back di Shadow
    UIBezierPath *crest = [UIBezierPath bezierPath];
    [crest moveToPoint:pt(-0.56, 0.32)];
    [crest addCurveToPoint:pt(0.28, -0.78)
             controlPoint1:pt(-0.68, -0.35)
             controlPoint2:pt(-0.18, -0.82)];
    [crest addQuadCurveToPoint:pt(0.02, -0.34) controlPoint:pt(0.06, -0.58)];
    // Seconda punta alta
    [crest addQuadCurveToPoint:pt(0.66, -0.30) controlPoint:pt(0.36, -0.44)];
    [crest addQuadCurveToPoint:pt(0.18, -0.02) controlPoint:pt(0.38, -0.14)];
    // Terza punta centrale-bassa
    [crest addQuadCurveToPoint:pt(0.58, 0.24) controlPoint:pt(0.44, 0.04)];
    [crest addQuadCurveToPoint:pt(0.08, 0.30) controlPoint:pt(0.30, 0.32)];
    // Curva inferiore / muso
    [crest addQuadCurveToPoint:pt(0.46, 0.68) controlPoint:pt(0.24, 0.56)];
    [crest addCurveToPoint:pt(-0.56, 0.32)
             controlPoint1:pt(0.02, 0.78)
             controlPoint2:pt(-0.44, 0.64)];
    [crest closePath];
    [crest fill];

    // Taglio occhio affilato scuro
    UIBezierPath *eye = [UIBezierPath bezierPath];
    [eye moveToPoint:pt(-0.22, -0.08)];
    [eye addQuadCurveToPoint:pt(0.16, 0.06) controlPoint:pt(0.02, -0.14)];
    [eye addQuadCurveToPoint:pt(-0.22, -0.08) controlPoint:pt(-0.04, 0.14)];
    [eye closePath];
    [[UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.95] setFill];
    [eye fill];

    CGContextRestoreGState(ctx);
}

// Disegna il Chaos Emerald sfaccettato al centro della barra inferiore
static void DrawChaosEmeraldIcon(CGContextRef ctx, CGPoint c, CGFloat r, UIColor *tint, BOOL pressed) {
    CGContextSaveGState(ctx);
    auto pt = [&](CGFloat nx, CGFloat ny) -> CGPoint {
        return CGPointMake(c.x + nx * r, c.y + ny * r);
    };

    // Sagoma esterna del diamante
    UIBezierPath *gem = [UIBezierPath bezierPath];
    [gem moveToPoint:pt(-0.52, -0.64)];
    [gem addLineToPoint:pt(0.52, -0.64)];
    [gem addLineToPoint:pt(0.92, -0.14)];
    [gem addLineToPoint:pt(0.00, 0.86)];
    [gem addLineToPoint:pt(-0.92, -0.14)];
    [gem closePath];

    CGContextSetShadowWithColor(ctx, CGSizeZero, pressed ? 10.0 : 5.0,
                                [tint colorWithAlphaComponent:pressed ? 0.95 : 0.72].CGColor);
    [[tint colorWithAlphaComponent:pressed ? 0.88 : 0.62] setFill];
    [gem fill];

    // Sfaccettature luminose della corona superiore
    UIBezierPath *crown = [UIBezierPath bezierPath];
    [crown moveToPoint:pt(-0.34, -0.58)];
    [crown addLineToPoint:pt(0.34, -0.58)];
    [crown addLineToPoint:pt(0.46, -0.16)];
    [crown addLineToPoint:pt(-0.46, -0.16)];
    [crown closePath];
    [[UIColor colorWithWhite:1.0 alpha:pressed ? 0.34 : 0.22] setFill];
    [crown fill];

    // Linee interne delle facce
    UIBezierPath *facets = [UIBezierPath bezierPath];
    [facets moveToPoint:pt(-0.90, -0.14)];
    [facets addLineToPoint:pt(0.90, -0.14)];
    [facets moveToPoint:pt(-0.44, -0.14)];
    [facets addLineToPoint:pt(0.00, 0.82)];
    [facets addLineToPoint:pt(0.44, -0.14)];
    [facets moveToPoint:pt(-0.50, -0.62)];
    [facets addLineToPoint:pt(-0.44, -0.14)];
    [facets moveToPoint:pt(0.50, -0.62)];
    [facets addLineToPoint:pt(0.44, -0.14)];

    [[UIColor colorWithWhite:1.0 alpha:0.60] setStroke];
    facets.lineWidth = 1.05;
    [facets stroke];

    [[tint colorWithAlphaComponent:0.95] setStroke];
    gem.lineWidth = 1.3;
    [gem stroke];
    CGContextRestoreGState(ctx);
}

} // namespace

#pragma mark - CoreHaptics + Fallback Tactile Engine

@interface ShadowHapticEngine : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) CHHapticEngine *engine;
@property (nonatomic, assign) BOOL supportsCoreHaptics;
@property (nonatomic, assign) BOOL engineStarted;
@property (nonatomic, strong) UIImpactFeedbackGenerator *lightImpact;
@property (nonatomic, strong) UIImpactFeedbackGenerator *mediumImpact;
@property (nonatomic, strong) UIImpactFeedbackGenerator *rigidImpact;
@property (nonatomic, assign) CFTimeInterval lastRumbleTime;
- (void)ensureStarted;
- (void)playButtonDownIsTrigger:(BOOL)isTrigger pressure:(float)pressure01;
- (void)playButtonUp;
- (void)playDPadTick;
- (void)playStickEngage;
- (void)playStickZoneTick:(float)intensity;
- (void)playStickRimBump:(float)pressure01;
- (void)playStickRelease;
- (void)playGameRumbleLeft:(uint16_t)leftMotor right:(uint16_t)rightMotor;
@end

@implementation ShadowHapticEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _lightImpact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _mediumImpact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        if (@available(iOS 13.0, *)) {
            _rigidImpact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
            _supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware.supportsHaptics;
            if (_supportsCoreHaptics) {
                [self setupCoreHaptics];
            }
        } else {
            _rigidImpact = _mediumImpact;
            _supportsCoreHaptics = NO;
        }
    }
    return self;
}

- (void)setupCoreHaptics {
    if (@available(iOS 13.0, *)) {
        NSError *err = nil;
        CHHapticEngine *eng = [[CHHapticEngine alloc] initAndReturnError:&err];
        if (!eng || err) {
            self.supportsCoreHaptics = NO;
            return;
        }
        // CRITICO: playsHapticsOnly = YES impedisce qualsiasi conflitto con AVAudioSession / CoreAudio del gioco!
        eng.playsHapticsOnly = YES;
        eng.autoShutdownEnabled = YES;

        __weak typeof(self) weakSelf = self;
        eng.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
            (void)reason;
            weakSelf.engineStarted = NO;
        };
        eng.resetHandler = ^{
            weakSelf.engineStarted = NO;
            [weakSelf ensureStarted];
        };
        self.engine = eng;
        [self ensureStarted];
    }
}

- (void)ensureStarted {
    if (!self.enabled || !self.supportsCoreHaptics || !self.engine) return;
    if (self.engineStarted) return;
    if (@available(iOS 13.0, *)) {
        NSError *err = nil;
        if ([self.engine startAndReturnError:&err] && !err) {
            self.engineStarted = YES;
        }
    }
}

- (void)playTransientIntensity:(float)intensity sharpness:(float)sharpness fallbackStyle:(int)fallbackStyle {
    if (!self.enabled) return;
    float clampedI = ClampF(intensity, 0.08f, 1.0f);
    float clampedS = ClampF(sharpness, 0.05f, 1.0f);

    if (self.supportsCoreHaptics && self.engine) {
        [self ensureStarted];
        if (self.engineStarted) {
            if (@available(iOS 13.0, *)) {
                NSError *err = nil;
                CHHapticEventParameter *pInt = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:clampedI];
                CHHapticEventParameter *pSharp = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:clampedS];
                CHHapticEvent *evt = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                                                   parameters:@[pInt, pSharp]
                                                                 relativeTime:0.0];
                CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[evt] parameters:@[] error:&err];
                if (pattern && !err) {
                    id<CHHapticPatternPlayer> player = [self.engine createPlayerWithPattern:pattern error:&err];
                    if (player && !err) {
                        [player startAtTime:CHHapticTimeImmediate error:&err];
                        return;
                    }
                }
            }
        }
    }

    // Fallback UIKit Impact sempre funzionante
    if (fallbackStyle == 0) {
        [self.lightImpact impactOccurredWithIntensity:clampedI];
    } else if (fallbackStyle == 1) {
        [self.mediumImpact impactOccurredWithIntensity:clampedI];
    } else {
        [self.rigidImpact impactOccurredWithIntensity:clampedI];
    }
}

- (void)playButtonDownIsTrigger:(BOOL)isTrigger pressure:(float)pressure01 {
    if (isTrigger) {
        // Click profondo stile grilletto Xbox
        [self playTransientIntensity:0.56f + 0.34f * pressure01 sharpness:0.46f fallbackStyle:1];
    } else {
        // Click netto stile micro-switch meccanico per A/B/X/Y/Pausa/Indietro
        [self playTransientIntensity:0.64f + 0.32f * pressure01 sharpness:0.88f fallbackStyle:2];
    }
}

- (void)playButtonUp {
    // Micro-scatto di ritorno al rilascio del tasto: sensazione tattile fisica!
    [self playTransientIntensity:0.24f sharpness:0.72f fallbackStyle:0];
}

- (void)playDPadTick {
    [self playTransientIntensity:0.50f sharpness:0.92f fallbackStyle:2];
}

- (void)playStickEngage {
    [self playTransientIntensity:0.30f sharpness:0.60f fallbackStyle:0];
}

- (void)playStickZoneTick:(float)intensity {
    [self playTransientIntensity:ClampF(intensity, 0.16f, 0.48f) sharpness:0.52f fallbackStyle:0];
}

- (void)playStickRimBump:(float)pressure01 {
    // Sensazione di battere contro il bordo fisico della ghiera dell'analogico!
    [self playTransientIntensity:0.52f + 0.30f * pressure01 sharpness:0.36f fallbackStyle:1];
}

- (void)playStickRelease {
    [self playTransientIntensity:0.20f sharpness:0.68f fallbackStyle:0];
}

- (void)playGameRumbleLeft:(uint16_t)leftMotor right:(uint16_t)rightMotor {
    if (!self.enabled) return;
    if (leftMotor < 2000 && rightMotor < 2000) return;

    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastRumbleTime < 0.045) return; // Rate limit ~22Hz per fluidità e zero lag
    self.lastRumbleTime = now;

    float leftF = static_cast<float>(leftMotor) / 65535.0f;
    float rightF = static_cast<float>(rightMotor) / 65535.0f;
    float intensity = ClampF(std::max(leftF, rightF) * 0.85f, 0.12f, 0.92f);
    float sharpness = ClampF(0.20f + rightF * 0.65f - leftF * 0.15f, 0.12f, 0.88f);

    if (self.supportsCoreHaptics && self.engine) {
        [self ensureStarted];
        if (self.engineStarted) {
            if (@available(iOS 13.0, *)) {
                NSError *err = nil;
                CHHapticEventParameter *pInt = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity];
                CHHapticEventParameter *pSharp = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharpness];
                CHHapticEvent *evt = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                                                   parameters:@[pInt, pSharp]
                                                                 relativeTime:0.0
                                                                     duration:0.09];
                CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[evt] parameters:@[] error:&err];
                if (pattern && !err) {
                    id<CHHapticPatternPlayer> player = [self.engine createPlayerWithPattern:pattern error:&err];
                    if (player && !err) {
                        [player startAtTime:CHHapticTimeImmediate error:&err];
                        return;
                    }
                }
            }
        }
    }
    [self.mediumImpact impactOccurredWithIntensity:intensity];
}

@end

#pragma mark - Visual Component Views (CoreGraphics 120Hz)

// 1. Wing Trigger / Shoulder Button (LT, LB, L3, R3, RT, RB)
@interface ShadowWingButtonView : UIView
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *subLabel;
@property (nonatomic, assign) WingShapeStyle style;
@property (nonatomic, assign) BOOL mirroredRight;
@property (nonatomic, assign) BOOL pressed;
@property (nonatomic, assign) float analogFill; // 0..1 per LT/RT
@end

@implementation ShadowWingButtonView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    [UIView animateWithDuration:pressed ? 0.06 : 0.14
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = pressed ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    } completion:nil];
    [self setNeedsDisplay];
}

- (void)setAnalogFill:(float)analogFill {
    if (std::fabs(_analogFill - analogFill) < 0.02f) return;
    _analogFill = analogFill;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect inset = CGRectInset(rect, 3.0, 3.0);
    UIBezierPath *blade = BuildWingBladePath(inset, self.style, self.mirroredRight);
    UIColor *crimson = ShadowCrimsonColor(1.0);

    // Ombra/alone cremisi esterno
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, self.pressed ? 9.0 : 4.0,
                                [crimson colorWithAlphaComponent:self.pressed ? 0.90 : 0.50].CGColor);
    [[UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:0.78] setFill];
    [blade fill];
    CGContextRestoreGState(ctx);

    // Riempimento vetro scuro + gradiente cremisi su pressione/analogico
    CGContextSaveGState(ctx);
    [blade addClip];

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat redBoost = self.pressed ? (0.34f + 0.34f * self.analogFill) : 0.08f;
    NSArray *colors = @[
        (__bridge id)[UIColor colorWithRed:0.16 + redBoost green:0.06 blue:0.09 alpha:0.84].CGColor,
        (__bridge id)[UIColor colorWithRed:0.04 + redBoost * 0.45 green:0.05 blue:0.08 alpha:0.90].CGColor
    ];
    CGFloat locs[] = {0.0, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, inset.origin.y), CGPointMake(0, CGRectGetMaxY(inset)), 0);
    CGGradientRelease(grad);

    // Barra di riempimento pressione interna per LT/RT
    if (self.pressed && self.analogFill > 0.05f) {
        CGFloat fillW = inset.size.width * ClampF(self.analogFill, 0.0f, 1.0f);
        CGRect fillRect = self.mirroredRight
            ? CGRectMake(CGRectGetMaxX(inset) - fillW, inset.origin.y, fillW, inset.size.height)
            : CGRectMake(inset.origin.x, inset.origin.y, fillW, inset.size.height);
        [[crimson colorWithAlphaComponent:0.28] setFill];
        CGContextFillRect(ctx, fillRect);
    }

    // Riflesso superiore vetro
    UIBezierPath *sheen = [UIBezierPath bezierPathWithRect:CGRectMake(inset.origin.x, inset.origin.y, inset.size.width, inset.size.height * 0.40)];
    [[UIColor colorWithWhite:1.0 alpha:self.pressed ? 0.16 : 0.09] setFill];
    [sheen fill];
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(ctx);

    // Bordo cremisi affilato
    [[crimson colorWithAlphaComponent:self.pressed ? 1.0 : 0.85] setStroke];
    blade.lineWidth = self.pressed ? 2.1 : 1.45;
    [blade stroke];

    // Etichetta centrata
    if (self.label.length > 0) {
        CGFloat fontSize = (self.style == WingShapeStyle::InnerBlade) ? 12.0 : 13.0;
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:self.pressed ? 1.0 : 0.90 alpha:0.95]
        };
        CGSize sz = [self.label sizeWithAttributes:attrs];
        CGFloat yOffset = (self.style == WingShapeStyle::InnerBlade) ? -rect.size.height * 0.14 : 0.0;
        CGFloat xOffset = 0.0;
        if (self.style == WingShapeStyle::InnerBlade) {
            xOffset = self.mirroredRight ? rect.size.width * 0.08 : -rect.size.width * 0.08;
        }
        CGRect textRect = CGRectMake((rect.size.width - sz.width) * 0.5 + xOffset,
                                     (rect.size.height - sz.height) * 0.5 + yOffset,
                                     sz.width, sz.height);
        [self.label drawInRect:textRect withAttributes:attrs];

        if (self.subLabel.length > 0) {
            NSDictionary *subAttrs = @{
                NSFontAttributeName: [UIFont systemFontOfSize:8.0 weight:UIFontWeightHeavy],
                NSForegroundColorAttributeName: [crimson colorWithAlphaComponent:0.90]
            };
            CGSize subSz = [self.subLabel sizeWithAttributes:subAttrs];
            CGFloat sx = self.mirroredRight ? (CGRectGetMinX(textRect) - subSz.width - 4.0) : (CGRectGetMaxX(textRect) + 4.0);
            [self.subLabel drawAtPoint:CGPointMake(sx, CGRectGetMidY(textRect) - subSz.height * 0.5) withAttributes:subAttrs];
        }
    }
}
@end

// 2. Xbox Original Face Action Button (Y, X, B, A)
@interface ShadowActionButtonView : UIView
@property (nonatomic, copy) NSString *letter;
@property (nonatomic, strong) UIColor *tintAccent;
@property (nonatomic, assign) BOOL pressed;
@property (nonatomic, assign) float pressure;
@end

@implementation ShadowActionButtonView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    CGFloat scale = pressed ? (0.91 - 0.04 * self.pressure) : 1.0;
    [UIView animateWithDuration:pressed ? 0.05 : 0.14
                          delay:0
         usingSpringWithDamping:0.65
          initialSpringVelocity:0.9
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = CGAffineTransformMakeScale(scale, scale);
    } completion:nil];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect circleRect = CGRectInset(rect, 3.5, 3.5);
    CGPoint center = CGPointMake(CGRectGetMidX(circleRect), CGRectGetMidY(circleRect));
    CGFloat radius = MIN(circleRect.size.width, circleRect.size.height) * 0.5;
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:circleRect];
    UIColor *accent = self.tintAccent ?: ShadowCrimsonColor(1.0);
    UIColor *crimson = ShadowCrimsonColor(1.0);

    // Alone esterno luminoso
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, self.pressed ? 11.0 : 4.5,
                                [(self.pressed ? accent : crimson) colorWithAlphaComponent:self.pressed ? 0.92 : 0.45].CGColor);
    [[UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.80] setFill];
    [circle fill];
    CGContextRestoreGState(ctx);

    // Cupola 3D in vetro traslucido colorato
    CGContextSaveGState(ctx);
    [circle addClip];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [accent getRed:&r green:&g blue:&b alpha:&a];
    CGFloat boost = self.pressed ? 0.55 : 0.25;
    NSArray *radColors = @[
        (__bridge id)[UIColor colorWithRed:r * (boost + 0.18) green:g * (boost + 0.18) blue:b * (boost + 0.18) alpha:0.86].CGColor,
        (__bridge id)[UIColor colorWithRed:r * (boost * 0.60) green:g * (boost * 0.60) blue:b * (boost * 0.60) alpha:0.88].CGColor,
        (__bridge id)[UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:0.94].CGColor
    ];
    CGFloat locs[] = {0.0, 0.62, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)radColors, locs);
    CGContextDrawRadialGradient(ctx, grad,
                                CGPointMake(center.x, center.y - radius * 0.22), radius * 0.08,
                                center, radius, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(grad);

    // Riflesso superiore a mezzaluna tipico della cupola Xbox
    CGRect specRect = CGRectMake(center.x - radius * 0.62, center.y - radius * 0.82, radius * 1.24, radius * 0.72);
    UIBezierPath *spec = [UIBezierPath bezierPathWithOvalInRect:specRect];
    [[UIColor colorWithWhite:1.0 alpha:self.pressed ? 0.22 : 0.13] setFill];
    [spec fill];
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(ctx);

    // Bordo esterno stile Shadow (anello cremisi + filo colorato interno)
    [[(self.pressed ? accent : crimson) colorWithAlphaComponent:self.pressed ? 1.0 : 0.82] setStroke];
    circle.lineWidth = self.pressed ? 2.4 : 1.7;
    [circle stroke];

    UIBezierPath *innerRing = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circleRect, 2.5, 2.5)];
    [[accent colorWithAlphaComponent:self.pressed ? 0.85 : 0.45] setStroke];
    innerRing.lineWidth = 1.0;
    [innerRing stroke];

    // Lettera Xbox (Y, X, B, A)
    if (self.letter.length > 0) {
        CGFloat fontSize = radius * 0.98;
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: self.pressed ? [UIColor whiteColor] : [accent colorWithAlphaComponent:0.96]
        };
        CGSize sz = [self.letter sizeWithAttributes:attrs];
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, self.pressed ? 7.0 : 3.0, [accent colorWithAlphaComponent:0.75].CGColor);
        [self.letter drawAtPoint:CGPointMake(center.x - sz.width * 0.5, center.y - sz.height * 0.5) withAttributes:attrs];
        CGContextRestoreGState(ctx);
    }
}
@end

// 3. Analog Stick View (L-Analog Shadow Emblem + R-Analog Smoked Glass Dome)
@interface ShadowAnalogStickView : UIView
@property (nonatomic, assign) BOOL isShadowLeftStick;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) CGPoint normOffset; // -1..1 in coordinate schermo (Y verso il basso)
@property (nonatomic, assign) float pressure;     // 0..1
@property (nonatomic, strong) UIView *thumbCapView;
@property (nonatomic, assign) int chaosAuraMode;
- (void)updateOffset:(CGPoint)normOffset pressure:(float)pressure animated:(BOOL)animated;
@end

@interface ShadowThumbCapView : UIView
@property (nonatomic, assign) BOOL isShadowLeftStick;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) float intensity;
@property (nonatomic, assign) int chaosAuraMode;
@end

@implementation ShadowThumbCapView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat radius = MIN(rect.size.width, rect.size.height) * 0.5 - 2.0;
    UIColor *accent = self.isShadowLeftStick ? ShadowCrimsonColor(1.0) : ChaosAuraColor(self.chaosAuraMode, 1.0);

    if (self.isShadowLeftStick) {
        // Anello uncinato cremisi a 8 punte + emblema centrale Shadow!
        DrawShadowSpikyRing(ctx, center, radius * 0.68, radius * 0.98, accent, self.active ? (0.35 + 0.65 * self.intensity) : 0.15);

        // Disco interno satinato
        CGRect innerRect = CGRectMake(center.x - radius * 0.56, center.y - radius * 0.56, radius * 1.12, radius * 1.12);
        UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:innerRect];
        [[UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.95] setFill];
        [disc fill];
        [[accent colorWithAlphaComponent:0.55 + 0.40 * self.intensity] setStroke];
        disc.lineWidth = 1.25;
        [disc stroke];

        DrawShadowEmblem(ctx, center, radius * 0.44, accent, self.active ? self.intensity : 0.20);
    } else {
        // R-Analog: cupola in vetro fumé scuro con bordo cremisi reattivo come nel concept
        CGRect domeRect = CGRectInset(rect, 4.0, 4.0);
        UIBezierPath *dome = [UIBezierPath bezierPathWithOvalInRect:domeRect];
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, self.active ? 10.0 : 4.0,
                                    [accent colorWithAlphaComponent:self.active ? 0.80 : 0.25].CGColor);
        [[UIColor colorWithRed:0.12 green:0.14 blue:0.19 alpha:0.86] setFill];
        [dome fill];
        CGContextRestoreGState(ctx);

        CGContextSaveGState(ctx);
        [dome addClip];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[
            (__bridge id)[UIColor colorWithRed:0.30 green:0.33 blue:0.40 alpha:0.75].CGColor,
            (__bridge id)[UIColor colorWithRed:0.09 green:0.11 blue:0.15 alpha:0.92].CGColor,
            (__bridge id)[UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.96].CGColor
        ];
        CGFloat locs[] = {0.0, 0.58, 1.0};
        CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
        CGContextDrawRadialGradient(ctx, grad,
                                    CGPointMake(center.x - radius * 0.18, center.y - radius * 0.24), radius * 0.08,
                                    center, radius, kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(grad);
        CGColorSpaceRelease(cs);
        CGContextRestoreGState(ctx);

        [[(self.active ? accent : [UIColor colorWithWhite:0.65 alpha:0.50]) colorWithAlphaComponent:self.active ? 0.95 : 0.55] setStroke];
        dome.lineWidth = self.active ? 2.0 : 1.3;
        [dome stroke];
    }
}
@end

@implementation ShadowAnalogStickView {
    ShadowThumbCapView *_cap;
}

- (instancetype)initWithFrame:(CGRect)frame isShadowLeft:(BOOL)isLeft {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.isShadowLeftStick = isLeft;

        _cap = [[ShadowThumbCapView alloc] initWithFrame:CGRectZero];
        _cap.isShadowLeftStick = isLeft;
        self.thumbCapView = _cap;
        [self addSubview:_cap];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat capSize = self.isShadowLeftStick ? (side * 0.66) : (side * 0.64);
    _cap.bounds = CGRectMake(0, 0, capSize, capSize);
    [self applyThumbTransform];
}

- (void)applyThumbTransform {
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat maxTravel = MIN(self.bounds.size.width, self.bounds.size.height) * 0.28;
    _cap.center = CGPointMake(center.x + self.normOffset.x * maxTravel,
                              center.y + self.normOffset.y * maxTravel);

    // Effetto 3D tilt reale in base a direzione e pressione del pollice!
    CATransform3D t = CATransform3DIdentity;
    t.m34 = -1.0 / 260.0;
    CGFloat tiltMag = 0.28 + 0.14 * self.pressure;
    t = CATransform3DRotate(t, -self.normOffset.y * tiltMag, 1.0, 0.0, 0.0);
    t = CATransform3DRotate(t,  self.normOffset.x * tiltMag, 0.0, 1.0, 0.0);
    CGFloat scale = self.active ? (1.03 - 0.06 * self.pressure) : 1.0;
    t = CATransform3DScale(t, scale, scale, 1.0);
    _cap.layer.transform = t;
}

- (void)updateOffset:(CGPoint)normOffset pressure:(float)pressure animated:(BOOL)animated {
    self.normOffset = normOffset;
    self.pressure = pressure;
    CGFloat mag = std::hypot(normOffset.x, normOffset.y);
    _cap.active = self.active;
    _cap.intensity = ClampF(static_cast<float>(mag * 0.75 + pressure * 0.35), 0.0f, 1.0f);
    _cap.chaosAuraMode = self.chaosAuraMode;

    if (animated) {
        [UIView animateWithDuration:0.24
                              delay:0
             usingSpringWithDamping:0.56
              initialSpringVelocity:1.2
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            [self applyThumbTransform];
        } completion:nil];
    } else {
        [self applyThumbTransform];
    }
    [_cap setNeedsDisplay];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect outer = CGRectInset(rect, 4.0, 4.0);
    CGPoint center = CGPointMake(CGRectGetMidX(outer), CGRectGetMidY(outer));
    CGFloat radius = MIN(outer.size.width, outer.size.height) * 0.5;
    UIColor *accent = self.isShadowLeftStick ? ShadowCrimsonColor(1.0) : ChaosAuraColor(self.chaosAuraMode, 1.0);

    // Base circolare ossidiana spazzolata
    UIBezierPath *base = [UIBezierPath bezierPathWithOvalInRect:outer];
    CGContextSaveGState(ctx);
    [base addClip];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (__bridge id)[UIColor colorWithRed:0.15 green:0.16 blue:0.21 alpha:0.72].CGColor,
        (__bridge id)[UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.86].CGColor
    ];
    CGFloat locs[] = {0.0, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
    CGContextDrawRadialGradient(ctx, grad, center, radius * 0.15, center, radius, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(ctx);

    // Bordo esterno ghiera
    [[UIColor colorWithWhite:0.55 alpha:0.35] setStroke];
    base.lineWidth = 1.6;
    [base stroke];

    // Traccia interna del movimento
    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:center radius:radius * 0.78 startAngle:0 endAngle:M_PI * 2.0 clockwise:YES];
    [[accent colorWithAlphaComponent:self.active ? 0.35 : 0.18] setStroke];
    track.lineWidth = 1.1;
    [track stroke];

    // Arco energetico cremisi direzionale attivo mentre spingi lo stick!
    CGFloat mag = std::hypot(self.normOffset.x, self.normOffset.y);
    if (self.active && mag > 0.08) {
        CGFloat angle = std::atan2(self.normOffset.y, self.normOffset.x);
        CGFloat halfSpan = 0.45 + 0.35 * MIN(mag, 1.0);
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:center
                                                           radius:radius - 1.5
                                                       startAngle:angle - halfSpan
                                                         endAngle:angle + halfSpan
                                                        clockwise:YES];
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0, [accent colorWithAlphaComponent:0.90].CGColor);
        [[accent colorWithAlphaComponent:0.55 + 0.45 * MIN(mag, 1.0)] setStroke];
        arc.lineWidth = 2.8;
        arc.lineCapStyle = kCGLineCapRound;
        [arc stroke];
        CGContextRestoreGState(ctx);
    }
}
@end

// 4. Directional D-Pad View (4 bracci pentagonali con chevron rossi come nel concept)
@interface ShadowDPadView : UIView
@property (nonatomic, assign) uint16_t activeMask; // kXboxDPadUp/Down/Left/Right
@end

@implementation ShadowDPadView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setActiveMask:(uint16_t)activeMask {
    if (_activeMask == activeMask) return;
    _activeMask = activeMask;
    [self setNeedsDisplay];
}

- (void)drawArmInContext:(CGContextRef)ctx center:(CGPoint)c radius:(CGFloat)r angle:(CGFloat)angle pressed:(BOOL)pressed {
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, c.x, c.y);
    CGContextRotateCTM(ctx, angle);

    // Braccio pentagonale puntato verso il centro (disegnato verso l'alto, poi ruotato)
    CGFloat armW = r * 0.29;
    CGFloat topY = -r * 0.90;
    CGFloat midY = -r * 0.36;
    CGFloat tipY = -r * 0.14;

    UIBezierPath *arm = [UIBezierPath bezierPath];
    [arm moveToPoint:CGPointMake(-armW, topY)];
    [arm addLineToPoint:CGPointMake( armW, topY)];
    [arm addLineToPoint:CGPointMake( armW, midY)];
    [arm addLineToPoint:CGPointMake( 0.0,  tipY)];
    [arm addLineToPoint:CGPointMake(-armW, midY)];
    [arm closePath];

    UIColor *crimson = ShadowCrimsonColor(1.0);
    if (pressed) {
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0, [crimson colorWithAlphaComponent:0.95].CGColor);
        [[crimson colorWithAlphaComponent:0.46] setFill];
    } else {
        [[UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:0.78] setFill];
    }
    [arm fill];

    [[crimson colorWithAlphaComponent:pressed ? 1.0 : 0.80] setStroke];
    arm.lineWidth = pressed ? 2.0 : 1.3;
    [arm stroke];

    // Chevron direzionale interno
    UIBezierPath *chev = [UIBezierPath bezierPath];
    CGFloat cy = -r * 0.64;
    CGFloat cw = r * 0.14;
    CGFloat ch = r * 0.10;
    [chev moveToPoint:CGPointMake(-cw, cy + ch)];
    [chev addLineToPoint:CGPointMake(0.0, cy - ch)];
    [chev addLineToPoint:CGPointMake(cw, cy + ch)];
    [[(pressed ? [UIColor whiteColor] : crimson) colorWithAlphaComponent:0.95] setStroke];
    chev.lineWidth = 1.9;
    chev.lineCapStyle = kCGLineCapRound;
    chev.lineJoinStyle = kCGLineJoinRound;
    [chev stroke];

    CGContextRestoreGState(ctx);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect outer = CGRectInset(rect, 3.0, 3.0);
    CGPoint center = CGPointMake(CGRectGetMidX(outer), CGRectGetMidY(outer));
    CGFloat radius = MIN(outer.size.width, outer.size.height) * 0.5;

    // Base circolare traslucida scura
    UIBezierPath *base = [UIBezierPath bezierPathWithOvalInRect:outer];
    [[UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.56] setFill];
    [base fill];
    [[UIColor colorWithWhite:0.50 alpha:0.25] setStroke];
    base.lineWidth = 1.2;
    [base stroke];

    [self drawArmInContext:ctx center:center radius:radius angle:0.0        pressed:(self.activeMask & kXboxDPadUp) != 0];
    [self drawArmInContext:ctx center:center radius:radius angle:M_PI_2     pressed:(self.activeMask & kXboxDPadRight) != 0];
    [self drawArmInContext:ctx center:center radius:radius angle:M_PI       pressed:(self.activeMask & kXboxDPadDown) != 0];
    [self drawArmInContext:ctx center:center radius:radius angle:-M_PI_2    pressed:(self.activeMask & kXboxDPadLeft) != 0];
}
@end

// 5. Bottom Navigation Circular Button (Pausa, Chaos Emerald, Indietro)
enum class NavIconType : int {
    Pause = 0,
    ChaosEmerald = 1,
    Back = 2
};

@interface ShadowNavCircleButtonView : UIView
@property (nonatomic, assign) NavIconType iconType;
@property (nonatomic, assign) BOOL pressed;
@property (nonatomic, assign) int chaosAuraMode;
@end

@implementation ShadowNavCircleButtonView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    [UIView animateWithDuration:pressed ? 0.05 : 0.14 animations:^{
        self.transform = pressed ? CGAffineTransformMakeScale(0.90, 0.90) : CGAffineTransformIdentity;
    }];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect outer = CGRectInset(rect, 3.0, 3.0);
    CGPoint center = CGPointMake(CGRectGetMidX(outer), CGRectGetMidY(outer));
    CGFloat radius = MIN(outer.size.width, outer.size.height) * 0.5;
    UIColor *accent = (self.iconType == NavIconType::ChaosEmerald)
        ? ChaosAuraColor(self.chaosAuraMode, 1.0)
        : ShadowCrimsonColor(1.0);

    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:outer];
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, self.pressed ? 9.0 : 4.0,
                                [accent colorWithAlphaComponent:self.pressed ? 0.90 : 0.45].CGColor);
    [[UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:0.82] setFill];
    [circle fill];
    CGContextRestoreGState(ctx);

    if (self.pressed) {
        [[accent colorWithAlphaComponent:0.28] setFill];
        [circle fill];
    }

    [[accent colorWithAlphaComponent:self.pressed ? 1.0 : 0.85] setStroke];
    circle.lineWidth = self.pressed ? 2.0 : 1.45;
    [circle stroke];

    if (self.iconType == NavIconType::Pause) {
        // Icona || (Start / Pausa)
        CGFloat bw = radius * 0.22;
        CGFloat bh = radius * 0.64;
        CGFloat gap = radius * 0.18;
        UIColor *col = self.pressed ? [UIColor whiteColor] : accent;
        [col setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(center.x - gap - bw, center.y - bh * 0.5, bw, bh) cornerRadius:1.8] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(center.x + gap, center.y - bh * 0.5, bw, bh) cornerRadius:1.8] fill];
    } else if (self.iconType == NavIconType::ChaosEmerald) {
        DrawChaosEmeraldIcon(ctx, center, radius * 0.62, accent, self.pressed);
    } else {
        // Icona freccia curva Indietro (Back)
        UIColor *col = self.pressed ? [UIColor whiteColor] : accent;
        [col setStroke];
        UIBezierPath *arc = [UIBezierPath bezierPath];
        [arc moveToPoint:CGPointMake(center.x - radius * 0.30, center.y - radius * 0.12)];
        [arc addLineToPoint:CGPointMake(center.x + radius * 0.14, center.y - radius * 0.12)];
        [arc addArcWithCenter:CGPointMake(center.x + radius * 0.14, center.y + radius * 0.12)
                       radius:radius * 0.24
                   startAngle:-M_PI_2
                     endAngle:M_PI_2
                    clockwise:YES];
        [arc addLineToPoint:CGPointMake(center.x - radius * 0.22, center.y + radius * 0.36)];
        arc.lineWidth = 2.0;
        arc.lineCapStyle = kCGLineCapRound;
        [arc stroke];

        // Punta freccia sinistra
        UIBezierPath *head = [UIBezierPath bezierPath];
        CGFloat ax = center.x - radius * 0.32;
        CGFloat ay = center.y - radius * 0.12;
        [head moveToPoint:CGPointMake(ax + radius * 0.22, ay - radius * 0.18)];
        [head addLineToPoint:CGPointMake(ax, ay)];
        [head addLineToPoint:CGPointMake(ax + radius * 0.22, ay + radius * 0.18)];
        head.lineWidth = 2.0;
        head.lineCapStyle = kCGLineCapRound;
        head.lineJoinStyle = kCGLineJoinRound;
        [head stroke];
    }
}
@end

#pragma mark - 2-Player ("2 Omini") Vector Icon Button for Quick-HUD Bar

@interface ShadowTwoPlayersIconView : UIView
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL connected;
@end

@implementation ShadowTwoPlayersIconView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)setActive:(BOOL)active {
    if (_active != active) {
        _active = active;
        [self setNeedsDisplay];
    }
}

- (void)setConnected:(BOOL)connected {
    if (_connected != connected) {
        _connected = connected;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect box = CGRectInset(rect, 0.75, 0.75);
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:9.5];
    if (self.connected) {
        [[UIColor colorWithRed:0.08 green:0.42 blue:0.22 alpha:0.65] setFill];
        [bg fill];
        [[UIColor colorWithRed:0.18 green:0.86 blue:0.46 alpha:0.95] setStroke];
        bg.lineWidth = 1.3;
        [bg stroke];
    } else if (self.active) {
        [ShadowCrimsonColor(0.32) setFill];
        [bg fill];
        [ShadowCrimsonColor(0.95) setStroke];
        bg.lineWidth = 1.3;
        [bg stroke];
    } else {
        [[UIColor colorWithWhite:1.0 alpha:0.08] setFill];
        [bg fill];
    }

    // Disegna 2 omini stilizzati affiancati (Giocatore 1 + Giocatore 2)
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    CGFloat cy = h * 0.50;
    CGFloat headR = MIN(w, h) * 0.145;

    auto drawPerson = ^(CGFloat cx, CGFloat yOffset, CGFloat scale, UIColor *color) {
        CGFloat r = headR * scale;
        CGFloat headY = cy - r * 1.15 + yOffset;
        [color setFill];

        // Testa
        UIBezierPath *head = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - r, headY - r, r * 2.0, r * 2.0)];
        [head fill];

        // Spalle / busto a cupola pulita
        CGFloat bodyW = r * 2.95;
        CGFloat bodyH = r * 1.95;
        CGFloat bodyTop = headY + r * 1.20;
        UIBezierPath *body = [UIBezierPath bezierPath];
        [body moveToPoint:CGPointMake(cx - bodyW * 0.5, bodyTop + bodyH)];
        [body addCurveToPoint:CGPointMake(cx + bodyW * 0.5, bodyTop + bodyH)
                controlPoint1:CGPointMake(cx - bodyW * 0.5, bodyTop - bodyH * 0.28)
                controlPoint2:CGPointMake(cx + bodyW * 0.5, bodyTop - bodyH * 0.28)];
        [body closePath];
        [body fill];
    };

    UIColor *backColor = self.connected
        ? [UIColor colorWithRed:0.55 green:0.98 blue:0.72 alpha:0.92]
        : (self.active ? [UIColor colorWithRed:1.0 green:0.58 blue:0.64 alpha:0.95] : [UIColor colorWithWhite:0.82 alpha:0.80]);
    UIColor *frontColor = self.connected
        ? [UIColor colorWithRed:0.86 green:1.0 blue:0.92 alpha:1.0]
        : [UIColor whiteColor];

    // Omino 2 (destra, leggermente arretrato)
    drawPerson(w * 0.62, 0.5, 0.88, backColor);
    // Omino 1 (sinistra, in primo piano)
    drawPerson(w * 0.37, 0.0, 1.0, frontColor);
}
@end

#pragma mark - TV Mode Vector Icon Button (AirPlay / HDMI External Display)

@interface ShadowTVModeIconView : UIView
@property (nonatomic, assign) BOOL available; // YES solo se AirPlay o HDMI e connesso
@property (nonatomic, assign) BOOL active;    // YES quando Modalita TV e attiva
@end

@implementation ShadowTVModeIconView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)setAvailable:(BOOL)available {
    if (_available != available) {
        _available = available;
        [self setNeedsDisplay];
    }
}

- (void)setActive:(BOOL)active {
    if (_active != active) {
        _active = active;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGRect box = CGRectInset(rect, 0.75, 0.75);
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:9.5];
    UIColor *cyanAccent = [UIColor colorWithRed:0.220 green:0.741 blue:0.973 alpha:1.0]; // #38BDF8

    if (self.active) {
        [[cyanAccent colorWithAlphaComponent:0.34] setFill];
        [bg fill];
        [[cyanAccent colorWithAlphaComponent:0.98] setStroke];
        bg.lineWidth = 1.4;
        [bg stroke];
    } else if (self.available) {
        [[cyanAccent colorWithAlphaComponent:0.15] setFill];
        [bg fill];
        [[cyanAccent colorWithAlphaComponent:0.75] setStroke];
        bg.lineWidth = 1.1;
        [bg stroke];
    } else {
        [[UIColor colorWithWhite:1.0 alpha:0.04] setFill];
        [bg fill];
    }

    // Disegna il simbolo vettoriale della TV (cornice 16:10 + schermo + piedistallo)
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    CGFloat tvW = MIN(w * 0.56, h * 0.88);
    CGFloat tvH = tvW * 0.64;
    CGFloat tvX = (w - tvW) * 0.5;
    CGFloat tvY = (h - tvH) * 0.5 - h * 0.08;

    UIColor *strokeCol = self.active
        ? [UIColor colorWithRed:0.86 green:0.98 blue:1.0 alpha:1.0]
        : (self.available
            ? [UIColor colorWithWhite:0.97 alpha:0.96]
            : [UIColor colorWithWhite:0.65 alpha:0.34]);

    CGRect screenRect = CGRectMake(tvX, tvY, tvW, tvH);
    UIBezierPath *tvFrame = [UIBezierPath bezierPathWithRoundedRect:screenRect cornerRadius:2.6];

    if (self.active) {
        [[cyanAccent colorWithAlphaComponent:0.42] setFill];
        [tvFrame fill];
    } else if (self.available) {
        [[cyanAccent colorWithAlphaComponent:0.14] setFill];
        [tvFrame fill];
    }

    [strokeCol setStroke];
    tvFrame.lineWidth = self.active ? 1.75 : 1.5;
    [tvFrame stroke];

    // Riflesso diagonale sottile nello schermo TV quando disponibile o attivo
    if (self.available || self.active) {
        UIBezierPath *glint = [UIBezierPath bezierPath];
        [glint moveToPoint:CGPointMake(tvX + tvW * 0.22, tvY + tvH * 0.25)];
        [glint addLineToPoint:CGPointMake(tvX + tvW * 0.44, tvY + tvH * 0.25)];
        [[UIColor colorWithWhite:1.0 alpha:self.active ? 0.85 : 0.45] setStroke];
        glint.lineWidth = 1.1;
        glint.lineCapStyle = kCGLineCapRound;
        [glint stroke];
    }

    // Collo e base del piedistallo TV
    CGFloat standTopY = tvY + tvH + 1.0;
    CGFloat standBotY = standTopY + MAX(2.5, h * 0.11);
    UIBezierPath *stand = [UIBezierPath bezierPath];
    [stand moveToPoint:CGPointMake(w * 0.5, standTopY)];
    [stand addLineToPoint:CGPointMake(w * 0.5, standBotY)];
    [stand moveToPoint:CGPointMake(w * 0.5 - tvW * 0.28, standBotY)];
    [stand addLineToPoint:CGPointMake(w * 0.5 + tvW * 0.28, standBotY)];
    [strokeCol setStroke];
    stand.lineWidth = 1.5;
    stand.lineCapStyle = kCGLineCapRound;
    [stand stroke];

    // Pallino di stato ciano in alto a destra quando AirPlay/HDMI e connesso
    if (self.available || self.active) {
        CGFloat dotR = 2.3;
        UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(box.origin.x + box.size.width - dotR * 2.0 - 3.5,
                                                                              box.origin.y + 3.5,
                                                                              dotR * 2.0, dotR * 2.0)];
        [(self.active ? [UIColor colorWithRed:0.18 green:0.92 blue:0.55 alpha:1.0] : cyanAccent) setFill];
        [dot fill];
    }
}
@end

#pragma mark - TV Gamepad Mode Obsidian Backdrop (Full-Screen Dedicated Controller Surface)

@interface ShadowTVGamepadBackdropView : UIView
@end

@implementation ShadowTVGamepadBackdropView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = YES;
        self.backgroundColor = [UIColor colorWithRed:0.028 green:0.030 blue:0.045 alpha:1.0];
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat W = rect.size.width;
    CGFloat H = rect.size.height;
    CGPoint center = CGPointMake(W * 0.5, H * 0.5);

    // Base ossidiana opaca (zero blending offscreen)
    [[UIColor colorWithRed:0.028 green:0.030 blue:0.045 alpha:1.0] setFill];
    CGContextFillRect(ctx, rect);

    // Sottile bagliore radiale cremisi al centro stile controller Shadow Pro
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (__bridge id)[UIColor colorWithRed:0.20 green:0.03 blue:0.06 alpha:0.42].CGColor,
        (__bridge id)[UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.18].CGColor,
        (__bridge id)[UIColor colorWithRed:0.025 green:0.028 blue:0.042 alpha:0.0].CGColor
    ];
    CGFloat locs[] = {0.0, 0.48, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
    CGContextDrawRadialGradient(ctx, grad, center, 10.0, center, MAX(W, H) * 0.56, 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);

    // Linee sottili di grip ergonomico laterali per orientamento rapido al tatto
    UIBezierPath *frameLines = [UIBezierPath bezierPath];
    [frameLines moveToPoint:CGPointMake(W * 0.36, 16.0)];
    [frameLines addLineToPoint:CGPointMake(W * 0.64, 16.0)];
    [frameLines moveToPoint:CGPointMake(W * 0.38, H - 14.0)];
    [frameLines addLineToPoint:CGPointMake(W * 0.62, H - 14.0)];
    [ShadowCrimsonColor(0.22) setStroke];
    frameLines.lineWidth = 1.0;
    [frameLines stroke];

    // Filigrana centrale dell'emblema di Shadow (bassissima opacita per estetica console)
    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, 0.08);
    DrawShadowEmblem(ctx, CGPointMake(center.x, center.y - H * 0.04), MIN(W, H) * 0.24, ShadowCrimsonColor(1.0), 0.15);
    CGContextRestoreGState(ctx);
}
@end

#pragma mark - Unified Multi-Touch Overlay Controller

enum class TouchTargetKind : int {
    None = 0,
    LeftStick,
    RightStick,
    DPad,
    ABXYCluster,
    LT,
    LB,
    L3,
    R3,
    RT,
    RB,
    Start,
    Back,
    ChaosEmerald,
    QuickBar,
    P2StatusPill,
    P2CardCopy,
    P2CardClose,
    P2CardBody
};

struct ActiveTouchRecord {
    TouchTargetKind kind;
    int subButton;          // Per ABXYCluster: 0=A, 1=B, 2=X, 3=Y, -1=none
    uint16_t dpadMask;      // Per DPad
    int stickZone;          // 0=center, 1=mid(50%), 2=rim(94%)
    float analogVal;        // 0..1 per LT/RT e ABXY pressure
    CGPoint stickXY;        // -1..1
};

@interface ShadowTouchOverlayView : UIView
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) ShadowHapticEngine *haptics;

// Controlli visuali
@property (nonatomic, strong) ShadowWingButtonView *ltView;
@property (nonatomic, strong) ShadowWingButtonView *lbView;
@property (nonatomic, strong) ShadowWingButtonView *l3View;
@property (nonatomic, strong) ShadowWingButtonView *r3View;
@property (nonatomic, strong) ShadowWingButtonView *rtView;
@property (nonatomic, strong) ShadowWingButtonView *rbView;

@property (nonatomic, strong) ShadowAnalogStickView *leftStickView;
@property (nonatomic, strong) ShadowAnalogStickView *rightStickView;
@property (nonatomic, strong) ShadowDPadView *dpadView;

@property (nonatomic, strong) ShadowActionButtonView *btnYView;
@property (nonatomic, strong) ShadowActionButtonView *btnXView;
@property (nonatomic, strong) ShadowActionButtonView *btnBView;
@property (nonatomic, strong) ShadowActionButtonView *btnAView;

@property (nonatomic, strong) ShadowNavCircleButtonView *pauseView;
@property (nonatomic, strong) ShadowNavCircleButtonView *emeraldView;
@property (nonatomic, strong) ShadowNavCircleButtonView *backView;

// Quick HUD Bar (Opacità / Aptica / Auto-Hide 4s / TV / 2 Giocatori) aperta dal Chaos Emerald
@property (nonatomic, strong) UIView *quickBarView;
@property (nonatomic, strong) UILabel *quickOpacityLabel;
@property (nonatomic, strong) UILabel *quickHapticsLabel;
@property (nonatomic, strong) UILabel *quickAutoHideLabel;
@property (nonatomic, strong) ShadowTVModeIconView *quickTVModeView;
@property (nonatomic, strong) ShadowTwoPlayersIconView *quickTwoPlayersView;
@property (nonatomic, assign) BOOL quickBarOpen;

// Modalita TV (AirPlay / HDMI): gioco su schermo TV esterno + controller ingrandito cieco-giocabile su iPhone
@property (nonatomic, strong) ShadowTVGamepadBackdropView *tvBackdropView;
@property (nonatomic, assign) BOOL externalDisplayAvailable;
@property (nonatomic, assign) BOOL tvGamepadMode;
@property (nonatomic, assign) BOOL tvModeSuspendedForBackground;
@property (nonatomic, assign) NSUInteger tvResumeGeneration;
@property (nonatomic, strong) UIWindow *tvExternalWindow;
@property (nonatomic, weak) UIWindow *tvPhoneWindow;
@property (nonatomic, weak) UIViewController *tvPhoneRootVC;
@property (nonatomic, strong) UIView *tvPhoneHostView;
@property (nonatomic, strong) UIView *tvMovedMetalView;
@property (nonatomic, weak) UIView *tvOriginalMetalSuperview;
@property (nonatomic, assign) BOOL tvMetalWasRootVCView;
@property (nonatomic, assign) BOOL tvOverlayWasInMetalView;
@property (nonatomic, assign) BOOL tvOriginalMetalUserInteraction;
@property (nonatomic, assign) CGRect tvOriginalMetalFrame;
@property (nonatomic, assign) UIViewAutoresizing tvOriginalMetalAutoresizing;
@property (nonatomic, assign) CGFloat tvOriginalMetalScale;

// 2-Player Hotspot Local Server UI (mini-bottoncino Pairing -> Connected + QR Pairing Card + toast)
@property (nonatomic, strong) UIView *p2StatusPillView;
@property (nonatomic, strong) UIView *p2StatusDotView;
@property (nonatomic, strong) UILabel *p2StatusLabel;
@property (nonatomic, strong) UILabel *p2ToastLabel;
@property (nonatomic, strong) UIView *p2PairingCardView;
@property (nonatomic, strong) UIView *p2QrFrameView;
@property (nonatomic, strong) UIImageView *p2QrImageView;
@property (nonatomic, strong) UILabel *p2CardTitleLabel;
@property (nonatomic, strong) UILabel *p2CardSubLabel;
@property (nonatomic, strong) UILabel *p2CardUrlLabel;
@property (nonatomic, strong) UILabel *p2CardCopyBtn;
@property (nonatomic, strong) UILabel *p2CardCloseBtn;
@property (nonatomic, copy) NSString *p2LastUrl;
@property (nonatomic, assign) BOOL p2CardVisible;
@property (nonatomic, assign) BOOL twoPlayerEnabled;
@property (nonatomic, assign) BOOL p2ServerRunning;
@property (nonatomic, assign) BOOL p2ClientConnected;
@property (nonatomic, assign) BOOL p2ConnectedPillDismissed;
@property (nonatomic, strong) NSTimer *p2ConnectedAutoHideTimer;
@property (nonatomic, strong) NSTimer *p2ToastTimer;

// Stato visibilità, trasparenza & 4s auto-hide
@property (nonatomic, assign) CGFloat preferredOpacity;
@property (nonatomic, assign) BOOL autoHideEnabled;
@property (nonatomic, assign) BOOL hiddenForPhysicalController;
@property (nonatomic, assign) BOOL hiddenForInstaller;
@property (nonatomic, assign) BOOL isIdleFaded;
@property (nonatomic, assign) int chaosAuraMode;
@property (nonatomic, strong) NSTimer *idleFadeTimer;

- (void)updateExternalPhysical:(BOOL)sdlPhysical installerVisible:(BOOL)installerVisible chaosAura:(int)aura;
- (void)clearAllInputs;
- (void)handleRemoteP2StateChangedRunning:(BOOL)running connected:(BOOL)connected url:(NSString *)url;
- (void)refreshExternalDisplayAvailabilitySilent:(BOOL)silent;
@end

static __weak ShadowTouchOverlayView *g_p2CallbackOverlay = nil;

static UIImage *CreateCrispQRImage(NSString *text, CGFloat targetPoints) {
    if (text.length == 0) return nil;
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    if (!filter) return nil;
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *ciImg = filter.outputImage;
    if (!ciImg) return nil;

    CIContext *ciCtx = [CIContext contextWithOptions:nil];
    CGImageRef cgImg = [ciCtx createCGImage:ciImg fromRect:ciImg.extent];
    if (!cgImg) return nil;

    CGSize sz = CGSizeMake(targetPoints, targetPoints);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
    UIImage *out = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rCtx) {
        CGContextRef ctx = rCtx.CGContext;
        [[UIColor whiteColor] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, sz.width, sz.height));
        CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
        CGFloat inset = 4.0;
        CGContextDrawImage(ctx, CGRectInset(CGRectMake(0, 0, sz.width, sz.height), inset, inset), cgImg);
    }];
    CGImageRelease(cgImg);
    return out;
}

static void OnIOSRemoteP2StateChanged(bool serverRunning, bool clientConnected, const char *url) {
    ShadowTouchOverlayView *overlay = g_p2CallbackOverlay;
    if (!overlay) return;
    NSString *urlStr = (url && url[0] != '\0') ? [NSString stringWithUTF8String:url] : nil;
    [overlay handleRemoteP2StateChangedRunning:(serverRunning ? YES : NO)
                                     connected:(clientConnected ? YES : NO)
                                           url:urlStr];
}

static UIWindowScene *FindExternalWindowScene(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if ([ws.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
            if (ws.activationState == UISceneActivationStateUnattached) continue;
            return ws;
        }
    }
    return nil;
}

static UIScreen *FindExternalScreen(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIScreen *mainScreen = [UIScreen mainScreen];
    for (UIScreen *scr in [UIScreen screens]) {
        if (scr != mainScreen) {
            return scr;
        }
    }
#pragma clang diagnostic pop
    return nil;
}

static CAMetalLayer *FindCAMetalLayerInView(UIView *view) {
    if (!view) return nil;
    if ([view.layer isKindOfClass:[CAMetalLayer class]]) {
        return (CAMetalLayer *)view.layer;
    }
    for (CALayer *sublayer in view.layer.sublayers) {
        if ([sublayer isKindOfClass:[CAMetalLayer class]]) {
            return (CAMetalLayer *)sublayer;
        }
    }
    return nil;
}

static UIView *FindMetalLayerViewInTree(UIView *root, UIView *excluded) {
    if (!root || root == excluded) return nil;
    if (FindCAMetalLayerInView(root) != nil) {
        return root;
    }
    for (UIView *sub in root.subviews) {
        if (sub == excluded) continue;
        UIView *nested = FindMetalLayerViewInTree(sub, excluded);
        if (nested) return nested;
    }
    return nil;
}

static UIView *FindGameMetalView(UIView *overlaySelf) {
    // 1. In SDL3 UIKit, rootViewController.view E spesso SDL_uikitmetalview stesso (self.superview)!
    UIView *hostView = overlaySelf.superview;
    if (hostView && hostView != overlaySelf) {
        UIView *found = FindMetalLayerViewInTree(hostView, overlaySelf);
        if (found) return found;
    }
    // 2. Scansiona l'intera UIWindow dell'iPhone
    if (overlaySelf.window) {
        UIView *found = FindMetalLayerViewInTree(overlaySelf.window, overlaySelf);
        if (found) return found;
    }
    // 3. Fallback su tutte le UIWindow Application-role (copre anche wrapper multi-window come LiveContainer)
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (![ws.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
        for (UIWindow *w in ws.windows) {
            UIView *found = FindMetalLayerViewInTree(w, overlaySelf);
            if (found) return found;
        }
    }
    return nil;
}

@implementation ShadowTouchOverlayView {
    std::unordered_map<uintptr_t, ActiveTouchRecord> _activeTouches;
    CGRect _abxyClusterRect;
    CGRect _quickOpacityRect;
    CGRect _quickHapticsRect;
    CGRect _quickAutoHideRect;
    CGRect _quickTVModeRect;
    CGRect _quickTwoPlayersRect;
    CGRect _p2CardCopyRect;
    CGRect _p2CardCloseRect;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.multipleTouchEnabled = YES;
        self.exclusiveTouch = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Carica preferenze utente salvate (default: trasparenza 58%, aptica ON, auto-hide 4s ON)
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        CGFloat savedOp = [ud doubleForKey:@"ShadowIOS_OverlayOpacity"];
        _preferredOpacity = (savedOp >= 0.25 && savedOp <= 0.95) ? savedOp : 0.58;
        _autoHideEnabled = ([ud objectForKey:@"ShadowIOS_AutoHide4s"] == nil) ? YES : [ud boolForKey:@"ShadowIOS_AutoHide4s"];
        BOOL savedHaptics = ([ud objectForKey:@"ShadowIOS_HapticsOn"] == nil) ? YES : [ud boolForKey:@"ShadowIOS_HapticsOn"];

        _haptics = [[ShadowHapticEngine alloc] init];
        _haptics.enabled = savedHaptics;

        // Parte nascosto finche input::Update() non conferma che l'InstallerWizard e chiuso
        _hiddenForInstaller = YES;
        self.hidden = YES;
        self.userInteractionEnabled = NO;

        // Sfondo scuro dedicato alla Modalita TV (nascosto finche TV Mode e OFF)
        _tvBackdropView = [[ShadowTVGamepadBackdropView alloc] initWithFrame:self.bounds];
        _tvBackdropView.alpha = 0.0;
        _tvBackdropView.hidden = YES;
        [self addSubview:_tvBackdropView];

        // Container animabile (il root view resta alpha=1.0 così hitTest intercetta sempre il risveglio!)
        _controlsContainer = [[UIView alloc] initWithFrame:self.bounds];
        _controlsContainer.backgroundColor = [UIColor clearColor];
        _controlsContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _controlsContainer.userInteractionEnabled = NO;
        // CRITICO 120Hz: evita il render pass offscreen full-screen (2622x1206) di CoreAnimation quando alpha < 1.0!
        _controlsContainer.layer.allowsGroupOpacity = NO;
        _controlsContainer.alpha = 0.0;
        [self addSubview:_controlsContainer];

        [self buildControls];
        [self buildQuickBar];
        [self registerNotifications];
        [self refreshExternalDisplayAvailabilitySilent:YES];

        // Registra callback in tempo reale dal server locale 2P (Pairing -> Connected)
        g_p2CallbackOverlay = self;
        IOSRemoteP2_SetStateCallback(&OnIOSRemoteP2StateChanged);
        _p2ServerRunning = IOSRemoteP2_IsServerRunning() ? YES : NO;
        _p2ClientConnected = IOSRemoteP2_IsConnected() ? YES : NO;
        if (_p2ServerRunning || _p2ClientConnected) {
            _twoPlayerEnabled = YES;
            [self refreshP2StatusPillAnimated:NO];
            if (_p2ClientConnected) {
                [self scheduleP2ConnectedPillAutoHideAfter:kP2ConnectedPillAutoHideSeconds];
            }
        }

        [self refreshPhysicalControllerState];
        [self scheduleIdleFadeTimer];
    }
    return self;
}

- (void)dealloc {
    if (g_p2CallbackOverlay == self) {
        g_p2CallbackOverlay = nil;
        IOSRemoteP2_SetStateCallback(nullptr);
    }
    [_idleFadeTimer invalidate];
    [_p2ToastTimer invalidate];
    [_p2ConnectedAutoHideTimer invalidate];
    if (_tvExternalWindow) {
        _tvExternalWindow.hidden = YES;
        _tvExternalWindow.rootViewController = nil;
        if (@available(iOS 13.0, *)) {
            _tvExternalWindow.windowScene = nil;
        }
        _tvExternalWindow = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildControls {
    // Top-Left: LT, LB (White), L3
    _ltView = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _ltView.label = @"LT";
    _ltView.style = WingShapeStyle::UpperTrigger;
    _ltView.mirroredRight = NO;

    _lbView = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _lbView.label = @"LB";
    _lbView.subLabel = @"W";
    _lbView.style = WingShapeStyle::LowerBumper;
    _lbView.mirroredRight = NO;

    _l3View = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _l3View.label = @"L3";
    _l3View.style = WingShapeStyle::InnerBlade;
    _l3View.mirroredRight = NO;

    // Top-Right: R3, RT, RB (Black)
    _r3View = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _r3View.label = @"R3";
    _r3View.style = WingShapeStyle::InnerBlade;
    _r3View.mirroredRight = YES;

    _rtView = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _rtView.label = @"RT";
    _rtView.style = WingShapeStyle::UpperTrigger;
    _rtView.mirroredRight = YES;

    _rbView = [[ShadowWingButtonView alloc] initWithFrame:CGRectZero];
    _rbView.label = @"RB";
    _rbView.subLabel = @"B";
    _rbView.style = WingShapeStyle::LowerBumper;
    _rbView.mirroredRight = YES;

    // Analogici L (Shadow Emblem) & R (Camera)
    _leftStickView = [[ShadowAnalogStickView alloc] initWithFrame:CGRectZero isShadowLeft:YES];
    _rightStickView = [[ShadowAnalogStickView alloc] initWithFrame:CGRectZero isShadowLeft:NO];

    // D-Pad 8 direzioni
    _dpadView = [[ShadowDPadView alloc] initWithFrame:CGRectZero];

    // Bottoni Xbox Original Y, X, B, A
    _btnYView = [[ShadowActionButtonView alloc] initWithFrame:CGRectZero];
    _btnYView.letter = @"Y";
    _btnYView.tintAccent = [UIColor colorWithRed:0.980 green:0.800 blue:0.082 alpha:1.0]; // Giallo oro

    _btnXView = [[ShadowActionButtonView alloc] initWithFrame:CGRectZero];
    _btnXView.letter = @"X";
    _btnXView.tintAccent = [UIColor colorWithRed:0.231 green:0.510 blue:0.965 alpha:1.0]; // Blu elettrico

    _btnBView = [[ShadowActionButtonView alloc] initWithFrame:CGRectZero];
    _btnBView.letter = @"B";
    _btnBView.tintAccent = [UIColor colorWithRed:0.937 green:0.267 blue:0.267 alpha:1.0]; // Rosso rubino

    _btnAView = [[ShadowActionButtonView alloc] initWithFrame:CGRectZero];
    _btnAView.letter = @"A";
    _btnAView.tintAccent = [UIColor colorWithRed:0.133 green:0.773 blue:0.369 alpha:1.0]; // Verde smeraldo

    // Barra inferiore: Pausa (Start), Chaos Emerald (Quick-HUD), Indietro (Back)
    _pauseView = [[ShadowNavCircleButtonView alloc] initWithFrame:CGRectZero];
    _pauseView.iconType = NavIconType::Pause;

    _emeraldView = [[ShadowNavCircleButtonView alloc] initWithFrame:CGRectZero];
    _emeraldView.iconType = NavIconType::ChaosEmerald;

    _backView = [[ShadowNavCircleButtonView alloc] initWithFrame:CGRectZero];
    _backView.iconType = NavIconType::Back;

    NSArray<UIView *> *all = @[
        _ltView, _lbView, _l3View, _r3View, _rtView, _rbView,
        _leftStickView, _rightStickView, _dpadView,
        _btnYView, _btnXView, _btnBView, _btnAView,
        _pauseView, _emeraldView, _backView
    ];
    for (UIView *v in all) {
        [_controlsContainer addSubview:v];
    }
}

- (void)buildQuickBar {
    _quickBarView = [[UIView alloc] initWithFrame:CGRectZero];
    _quickBarView.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.11 alpha:0.90];
    _quickBarView.layer.cornerRadius = 15.0;
    _quickBarView.layer.borderWidth = 1.2;
    _quickBarView.layer.borderColor = ShadowCrimsonColor(0.80).CGColor;
    _quickBarView.alpha = 0.0;
    _quickBarView.hidden = YES;
    _quickBarView.userInteractionEnabled = NO;

    UILabel *(^makePill)(void) = ^UILabel *{
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = NSTextAlignmentCenter;
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.72;
        l.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        l.layer.cornerRadius = 10.0;
        l.layer.masksToBounds = YES;
        return l;
    };

    _quickOpacityLabel = makePill();
    _quickHapticsLabel = makePill();
    _quickAutoHideLabel = makePill();
    _quickTVModeView = [[ShadowTVModeIconView alloc] initWithFrame:CGRectZero];
    _quickTwoPlayersView = [[ShadowTwoPlayersIconView alloc] initWithFrame:CGRectZero];

    [_quickBarView addSubview:_quickOpacityLabel];
    [_quickBarView addSubview:_quickHapticsLabel];
    [_quickBarView addSubview:_quickAutoHideLabel];
    [_quickBarView addSubview:_quickTVModeView];
    [_quickBarView addSubview:_quickTwoPlayersView];
    [_controlsContainer addSubview:_quickBarView];

    // Mini-bottoncino Pairing -> Connected per 2 Giocatori via Hotspot/Wi-Fi
    _p2StatusPillView = [[UIView alloc] initWithFrame:CGRectZero];
    _p2StatusPillView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.12 alpha:0.92];
    _p2StatusPillView.layer.cornerRadius = 13.0;
    _p2StatusPillView.layer.borderWidth = 1.3;
    _p2StatusPillView.layer.borderColor = ShadowCrimsonColor(0.92).CGColor;
    _p2StatusPillView.alpha = 0.0;
    _p2StatusPillView.hidden = YES;
    _p2StatusPillView.userInteractionEnabled = NO;

    _p2StatusDotView = [[UIView alloc] initWithFrame:CGRectZero];
    _p2StatusDotView.backgroundColor = ShadowCrimsonColor(1.0);
    _p2StatusDotView.layer.cornerRadius = 3.5;
    [_p2StatusPillView addSubview:_p2StatusDotView];

    _p2StatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2StatusLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightHeavy];
    _p2StatusLabel.textColor = [UIColor whiteColor];
    _p2StatusLabel.textAlignment = NSTextAlignmentLeft;
    _p2StatusLabel.text = L().pairing;
    [_p2StatusPillView addSubview:_p2StatusLabel];

    [_controlsContainer addSubview:_p2StatusPillView];

    // Toast compatto sopra il bottoncino Pairing quando il link locale viene copiato negli appunti
    _p2ToastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2ToastLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightSemibold];
    _p2ToastLabel.textColor = [UIColor colorWithRed:0.95 green:0.96 blue:0.99 alpha:1.0];
    _p2ToastLabel.textAlignment = NSTextAlignmentCenter;
    _p2ToastLabel.adjustsFontSizeToFitWidth = YES;
    _p2ToastLabel.minimumScaleFactor = 0.72;
    _p2ToastLabel.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.10 alpha:0.92];
    _p2ToastLabel.layer.cornerRadius = 10.0;
    _p2ToastLabel.layer.masksToBounds = YES;
    _p2ToastLabel.layer.borderWidth = 1.0;
    _p2ToastLabel.layer.borderColor = ShadowCrimsonColor(0.70).CGColor;
    _p2ToastLabel.alpha = 0.0;
    _p2ToastLabel.hidden = YES;
    _p2ToastLabel.userInteractionEnabled = NO;
    [_controlsContainer addSubview:_p2ToastLabel];

    // Card QR Code 100% opaca (montata su self, zero shadowRadius dinamico per zero offscreen blur GPU)
    _p2PairingCardView = [[UIView alloc] initWithFrame:CGRectZero];
    _p2PairingCardView.backgroundColor = [UIColor colorWithRed:0.055 green:0.060 blue:0.095 alpha:0.96];
    _p2PairingCardView.layer.cornerRadius = 16.0;
    _p2PairingCardView.layer.borderWidth = 1.6;
    _p2PairingCardView.layer.borderColor = ShadowCrimsonColor(0.92).CGColor;
    _p2PairingCardView.alpha = 0.0;
    _p2PairingCardView.hidden = YES;
    _p2PairingCardView.userInteractionEnabled = NO;
    [self addSubview:_p2PairingCardView];

    _p2QrFrameView = [[UIView alloc] initWithFrame:CGRectZero];
    _p2QrFrameView.backgroundColor = [UIColor whiteColor];
    _p2QrFrameView.layer.cornerRadius = 10.0;
    _p2QrFrameView.layer.masksToBounds = YES;
    [_p2PairingCardView addSubview:_p2QrFrameView];

    _p2QrImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _p2QrImageView.contentMode = UIViewContentModeScaleAspectFit;
    [_p2QrFrameView addSubview:_p2QrImageView];

    _p2CardTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2CardTitleLabel.text = L().cardTitleDefault;
    _p2CardTitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    _p2CardTitleLabel.textColor = [UIColor whiteColor];
    _p2CardTitleLabel.adjustsFontSizeToFitWidth = YES;
    _p2CardTitleLabel.minimumScaleFactor = 0.78;
    [_p2PairingCardView addSubview:_p2CardTitleLabel];

    _p2CardSubLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2CardSubLabel.text = L().cardSub;
    _p2CardSubLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
    _p2CardSubLabel.textColor = [UIColor colorWithRed:0.75 green:0.78 blue:0.86 alpha:1.0];
    _p2CardSubLabel.numberOfLines = 3;
    [_p2PairingCardView addSubview:_p2CardSubLabel];

    _p2CardUrlLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2CardUrlLabel.text = @"http://172.20.10.1:8765";
    _p2CardUrlLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightBold];
    _p2CardUrlLabel.textColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.35 alpha:1.0];
    _p2CardUrlLabel.backgroundColor = [UIColor colorWithRed:0.02 green:0.025 blue:0.045 alpha:0.95];
    _p2CardUrlLabel.textAlignment = NSTextAlignmentCenter;
    _p2CardUrlLabel.layer.cornerRadius = 8.0;
    _p2CardUrlLabel.layer.masksToBounds = YES;
    _p2CardUrlLabel.layer.borderWidth = 1.0;
    _p2CardUrlLabel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    _p2CardUrlLabel.adjustsFontSizeToFitWidth = YES;
    _p2CardUrlLabel.minimumScaleFactor = 0.72;
    [_p2PairingCardView addSubview:_p2CardUrlLabel];

    _p2CardCopyBtn = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2CardCopyBtn.text = L().cardCopy;
    _p2CardCopyBtn.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    _p2CardCopyBtn.textColor = [UIColor whiteColor];
    _p2CardCopyBtn.textAlignment = NSTextAlignmentCenter;
    _p2CardCopyBtn.adjustsFontSizeToFitWidth = YES;
    _p2CardCopyBtn.minimumScaleFactor = 0.75;
    _p2CardCopyBtn.backgroundColor = ShadowCrimsonColor(0.92);
    _p2CardCopyBtn.layer.cornerRadius = 8.0;
    _p2CardCopyBtn.layer.masksToBounds = YES;
    [_p2PairingCardView addSubview:_p2CardCopyBtn];

    _p2CardCloseBtn = [[UILabel alloc] initWithFrame:CGRectZero];
    _p2CardCloseBtn.text = L().cardClose;
    _p2CardCloseBtn.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _p2CardCloseBtn.textColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    _p2CardCloseBtn.textAlignment = NSTextAlignmentCenter;
    _p2CardCloseBtn.adjustsFontSizeToFitWidth = YES;
    _p2CardCloseBtn.minimumScaleFactor = 0.75;
    _p2CardCloseBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _p2CardCloseBtn.layer.cornerRadius = 8.0;
    _p2CardCloseBtn.layer.masksToBounds = YES;
    [_p2PairingCardView addSubview:_p2CardCloseBtn];

    [self refreshQuickBarLabels];
}

- (void)refreshQuickBarLabels {
    const ShadowLocalizedStrings &loc = L();
    int pct = static_cast<int>(std::lround(self.preferredOpacity * 100.0));
    self.quickOpacityLabel.text = self.tvGamepadMode ? loc.tvFullOpacity : [NSString stringWithFormat:loc.opacityFmt, pct];
    self.quickHapticsLabel.text = self.haptics.enabled ? loc.hapticsOn : loc.hapticsOff;
    self.quickAutoHideLabel.text = self.autoHideEnabled ? loc.autoHideOn : loc.autoHideOff;
    self.quickTVModeView.available = self.externalDisplayAvailable;
    self.quickTVModeView.active = self.tvGamepadMode;
    self.quickTwoPlayersView.active = self.twoPlayerEnabled;
    self.quickTwoPlayersView.connected = self.p2ClientConnected;
}

- (void)cancelP2ConnectedPillAutoHide {
    [self.p2ConnectedAutoHideTimer invalidate];
    self.p2ConnectedAutoHideTimer = nil;
}

- (void)scheduleP2ConnectedPillAutoHideAfter:(NSTimeInterval)delay {
    [self cancelP2ConnectedPillAutoHide];
    if (!self.twoPlayerEnabled || !self.p2ClientConnected || self.quickBarOpen) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.p2ConnectedAutoHideTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        ShadowTouchOverlayView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.p2ConnectedAutoHideTimer = nil;
        if (strongSelf.twoPlayerEnabled && strongSelf.p2ClientConnected && !strongSelf.quickBarOpen) {
            strongSelf.p2ConnectedPillDismissed = YES;
            [strongSelf refreshP2StatusPillAnimated:YES];
        }
    }];
}

- (void)refreshP2StatusPillAnimated:(BOOL)animated {
    // Quando Player 2 e connesso, "Connected" sparisce dopo pochi secondi per non occupare schermo;
    // riappare subito se si disconnette oppure temporaneamente quando si apre il Chaos Emerald menu.
    BOOL shouldShow = self.twoPlayerEnabled && (!self.p2ClientConnected || !self.p2ConnectedPillDismissed || self.quickBarOpen);
    if (self.p2ClientConnected) {
        self.p2StatusLabel.text = L().connected;
        self.p2StatusLabel.textColor = [UIColor colorWithRed:0.84 green:1.0 blue:0.90 alpha:1.0];
        self.p2StatusDotView.backgroundColor = [UIColor colorWithRed:0.133 green:0.820 blue:0.420 alpha:1.0];
        self.p2StatusPillView.backgroundColor = [UIColor colorWithRed:0.04 green:0.18 blue:0.10 alpha:0.94];
        self.p2StatusPillView.layer.borderColor = [UIColor colorWithRed:0.16 green:0.86 blue:0.46 alpha:0.95].CGColor;
    } else {
        self.p2StatusLabel.text = L().pairing;
        self.p2StatusLabel.textColor = [UIColor whiteColor];
        self.p2StatusDotView.backgroundColor = self.p2ServerRunning
            ? [UIColor colorWithRed:0.98 green:0.72 blue:0.12 alpha:1.0]
            : ShadowCrimsonColor(1.0);
        self.p2StatusPillView.backgroundColor = [UIColor colorWithRed:0.08 green:0.07 blue:0.12 alpha:0.92];
        self.p2StatusPillView.layer.borderColor = (self.p2ServerRunning
            ? [UIColor colorWithRed:0.98 green:0.72 blue:0.12 alpha:0.95]
            : ShadowCrimsonColor(0.92)).CGColor;
    }

    self.quickTwoPlayersView.active = self.twoPlayerEnabled;
    self.quickTwoPlayersView.connected = self.p2ClientConnected;

    if (shouldShow) {
        self.p2StatusPillView.hidden = NO;
        self.p2StatusPillView.transform = CGAffineTransformIdentity;
        [self updateP2FloatingFrames];
        if (animated && self.p2StatusPillView.alpha < 0.1) {
            self.p2StatusPillView.transform = CGAffineTransformMakeScale(0.90, 0.90);
        }
    }

    NSTimeInterval dur = animated ? 0.22 : 0.0;
    [UIView animateWithDuration:dur animations:^{
        self.p2StatusPillView.alpha = shouldShow ? 1.0 : 0.0;
        self.p2StatusPillView.transform = shouldShow ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.90, 0.90);
    } completion:^(BOOL finished) {
        (void)finished;
        BOOL stillShow = self.twoPlayerEnabled && (!self.p2ClientConnected || !self.p2ConnectedPillDismissed || self.quickBarOpen);
        if (!stillShow) {
            self.p2StatusPillView.hidden = YES;
            self.p2StatusPillView.transform = CGAffineTransformIdentity;
        }
    }];
}

- (void)showP2Toast:(NSString *)message duration:(NSTimeInterval)seconds {
    [self.p2ToastTimer invalidate];
    self.p2ToastTimer = nil;

    self.p2ToastLabel.text = [NSString stringWithFormat:@"  %@  ", message];
    self.p2ToastLabel.hidden = NO;
    [self updateP2FloatingFrames];

    [UIView animateWithDuration:0.18 animations:^{
        self.p2ToastLabel.alpha = 1.0;
    }];

    __weak typeof(self) weakSelf = self;
    self.p2ToastTimer = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        ShadowTouchOverlayView *strongSelf = weakSelf;
        if (!strongSelf) return;
        [UIView animateWithDuration:0.25 animations:^{
            strongSelf.p2ToastLabel.alpha = 0.0;
        } completion:^(BOOL finished) {
            (void)finished;
            if (strongSelf.p2ToastLabel.alpha < 0.05) {
                strongSelf.p2ToastLabel.hidden = YES;
            }
        }];
    }];
}

- (void)updateP2PairingCardURL:(NSString *)urlStr {
    if (urlStr.length == 0) {
        char urlBuf[160] = {0};
        IOSRemoteP2_GetURL(urlBuf, sizeof(urlBuf));
        urlStr = [NSString stringWithUTF8String:urlBuf];
    }
    if (urlStr.length == 0) urlStr = @"http://172.20.10.1:8765";

    BOOL changed = (self.p2LastUrl == nil || ![self.p2LastUrl isEqualToString:urlStr]);
    self.p2LastUrl = urlStr;
    self.p2CardUrlLabel.text = urlStr;

    BOOL isHotspot = ([urlStr rangeOfString:@"172.20.10."].location != NSNotFound);
    self.p2CardTitleLabel.text = isHotspot ? L().cardTitleHotspot : L().cardTitleWifi;

    if (changed || self.p2QrImageView.image == nil) {
        self.p2QrImageView.image = CreateCrispQRImage(urlStr, 150.0);
    }
}

- (void)setP2PairingCardVisible:(BOOL)visible animated:(BOOL)animated {
    self.p2CardVisible = visible;
    if (visible) {
        [self updateP2PairingCardURL:nil];
        [self updateP2FloatingFrames];
        self.p2PairingCardView.hidden = NO;
        [self bringSubviewToFront:self.p2PairingCardView];
        if (animated && self.p2PairingCardView.alpha < 0.1) {
            self.p2PairingCardView.transform = CGAffineTransformMakeScale(0.92, 0.92);
        }
    }
    NSTimeInterval dur = animated ? 0.20 : 0.0;
    [UIView animateWithDuration:dur animations:^{
        self.p2PairingCardView.alpha = visible ? 1.0 : 0.0;
        self.p2PairingCardView.transform = visible ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        (void)finished;
        if (!self.p2CardVisible) {
            self.p2PairingCardView.hidden = YES;
            self.p2PairingCardView.transform = CGAffineTransformIdentity;
        }
    }];
}

- (void)handleRemoteP2StateChangedRunning:(BOOL)running connected:(BOOL)connected url:(NSString *)url {
    BOOL wasConnected = self.p2ClientConnected;
    self.p2ServerRunning = running;
    self.p2ClientConnected = connected;
    if (connected) {
        self.twoPlayerEnabled = YES;
        if (!wasConnected) {
            self.p2ConnectedPillDismissed = NO;
        }
    } else if (wasConnected) {
        // Player 2 si e disconnesso: riapri subito il badge Pairing e annulla l'auto-hide!
        [self cancelP2ConnectedPillAutoHide];
        self.p2ConnectedPillDismissed = NO;
    }
    if (url.length > 0) {
        [self updateP2PairingCardURL:url];
    }
    [self refreshP2StatusPillAnimated:YES];

    if (connected && !wasConnected) {
        // Chiude subito la card QR, mostra "Connected" per ~3.5s poi lo nasconde automaticamente!
        if (self.p2CardVisible) {
            [self setP2PairingCardVisible:NO animated:YES];
        }
        [self.haptics ensureStarted];
        [self.haptics playButtonDownIsTrigger:NO pressure:0.95f];
        [self showP2Toast:L().toastP2Connected duration:2.8];
        [self scheduleP2ConnectedPillAutoHideAfter:kP2ConnectedPillAutoHideSeconds];
        [self scheduleIdleFadeTimer];
    } else if (!connected && wasConnected && self.twoPlayerEnabled) {
        // Risveglia subito l'overlay per avvisare l'utente della disconnessione anche se era in fade!
        [self wakeControlsAnimated:YES];
        [self.haptics ensureStarted];
        [self.haptics playButtonDownIsTrigger:NO pressure:0.80f];
        [self showP2Toast:L().toastP2Disconnected duration:4.0];
    }
}

- (void)handlePairingPillTap {
    if (!self.twoPlayerEnabled) return;

    BOOL started = IOSRemoteP2_StartServer(8765) ? YES : NO;
    self.p2ServerRunning = started || (IOSRemoteP2_IsServerRunning() ? YES : NO);
    self.p2ClientConnected = IOSRemoteP2_IsConnected() ? YES : NO;

    char urlBuf[160] = {0};
    IOSRemoteP2_GetURL(urlBuf, sizeof(urlBuf));
    NSString *urlStr = [NSString stringWithUTF8String:urlBuf];
    if (urlStr.length > 0) {
        [UIPasteboard generalPasteboard].string = urlStr;
    }

    [self.haptics ensureStarted];
    [self.haptics playButtonDownIsTrigger:NO pressure:0.85f];
    [self updateP2PairingCardURL:urlStr];
    [self refreshP2StatusPillAnimated:YES];

    if (self.p2ClientConnected) {
        [self showP2Toast:[NSString stringWithFormat:L().toastP2ConnectedLinkFmt, urlStr] duration:3.0];
        [self scheduleP2ConnectedPillAutoHideAfter:kP2ConnectedPillAutoHideSeconds];
    } else if (self.p2ServerRunning) {
        [self setP2PairingCardVisible:!self.p2CardVisible animated:YES];
        [self showP2Toast:[NSString stringWithFormat:L().toastLinkCopiedFmt, urlStr] duration:4.0];
    } else {
        [self showP2Toast:L().toastServerError duration:4.0];
    }
}

#pragma mark - TV Mode (AirPlay / HDMI Dedicated Screen + Oversized Blind-Playable Gamepad)

- (BOOL)isAppForegroundActive {
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (void)teardownTVExternalWindowOnly {
    if (self.tvMovedMetalView && self.tvExternalWindow &&
        [self.tvMovedMetalView isDescendantOfView:self.tvExternalWindow]) {
        [self.tvMovedMetalView removeFromSuperview];
    }
    if (self.tvExternalWindow) {
        self.tvExternalWindow.hidden = YES;
        self.tvExternalWindow.rootViewController = nil;
        if (@available(iOS 13.0, *)) {
            self.tvExternalWindow.windowScene = nil;
        }
        self.tvExternalWindow = nil;
    }
}

- (void)syncTVMetalLayerDrawableForWindow:(UIWindow *)tvWin screen:(UIScreen *)extScreen {
    UIView *metalView = self.tvMovedMetalView;
    if (!metalView || !tvWin) return;

    UIView *tvContainer = tvWin.rootViewController ? tvWin.rootViewController.view : tvWin;
    [tvWin layoutIfNeeded];
    [tvContainer layoutIfNeeded];

    CGRect tvBounds = tvContainer.bounds;
    if ((tvBounds.size.width < 10.0 || tvBounds.size.height < 10.0) && extScreen) {
        tvBounds = extScreen.bounds;
        tvWin.frame = tvBounds;
        tvContainer.frame = tvBounds;
    }
    if (tvBounds.size.width < 10.0 || tvBounds.size.height < 10.0) return;

    // Cap 1080p per zero Jetsam OOM su TV 4K e 60/120fps rock-solid
    CGFloat rawScale = extScreen ? MAX(extScreen.scale, 1.0) : 1.0;
    CGFloat tvScale = rawScale;
    if ((tvBounds.size.width * tvScale) > 1920.0) {
        tvScale = 1920.0 / tvBounds.size.width;
    }
    metalView.frame = tvBounds;
    metalView.contentScaleFactor = tvScale;
    [metalView layoutIfNeeded];

    CAMetalLayer *ml = FindCAMetalLayerInView(metalView);
    if (ml) {
        ml.contentsScale = tvScale;
        ml.frame = metalView.bounds;
        ml.drawableSize = CGSizeMake(std::round(tvBounds.size.width * tvScale),
                                     std::round(tvBounds.size.height * tvScale));
    }
}

- (BOOL)attachMetalViewToExternalDisplay:(UIView *)metalView scene:(UIWindowScene *)extScene screen:(UIScreen *)extScreen {
    if (!metalView || (!extScene && !extScreen)) return NO;

    [self teardownTVExternalWindowOnly];

    if (extScreen) {
        extScreen.overscanCompensation = UIScreenOverscanCompensationNone;
    }
    UIWindow *tvWin = nil;
    if (extScene) {
        tvWin = [[UIWindow alloc] initWithWindowScene:extScene];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        tvWin = [[UIWindow alloc] initWithFrame:extScreen.bounds];
        tvWin.screen = extScreen;
#pragma clang diagnostic pop
    }
    if ((tvWin.bounds.size.width < 10.0 || tvWin.bounds.size.height < 10.0) && extScreen) {
        tvWin.frame = extScreen.bounds;
    }
    tvWin.backgroundColor = [UIColor blackColor];
    tvWin.userInteractionEnabled = NO;

    UIViewController *tvVC = [[UIViewController alloc] init];
    tvVC.view.backgroundColor = [UIColor blackColor];
    tvVC.view.clipsToBounds = YES;
    tvVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tvVC.view.frame = tvWin.bounds;
    tvWin.rootViewController = tvVC;

    // Sposta SOLO la vista CAMetalLayer di ShadowRecomp sulla TV a schermo intero (zero bottoni virtuali!)
    [metalView removeFromSuperview];
    metalView.userInteractionEnabled = NO;
    metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [tvVC.view addSubview:metalView];

    // NON chiamare makeKeyAndVisible: l'iPhone deve restare keyWindow per ricevere multi-touch e aptica!
    tvWin.hidden = NO;
    self.tvExternalWindow = tvWin;
    [self syncTVMetalLayerDrawableForWindow:tvWin screen:extScreen];

    UIWindow *phoneWindow = self.tvPhoneWindow ?: self.window;
    if (phoneWindow && !phoneWindow.isKeyWindow) {
        [phoneWindow makeKeyAndVisible];
    }
    return YES;
}

- (void)scheduleTVSwapChainFollowUpNudgesForGeneration:(NSUInteger)gen {
    static const double kDelays[2] = { 0.35, 0.95 };
    __weak typeof(self) weakSelf = self;
    for (int i = 0; i < 2; ++i) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelays[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShadowTouchOverlayView *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.tvGamepadMode || strongSelf.tvModeSuspendedForBackground) return;
            if (strongSelf.tvResumeGeneration != gen || ![strongSelf isAppForegroundActive]) return;

            UIWindowScene *curScene = FindExternalWindowScene();
            UIScreen *curScreen = curScene ? curScene.screen : FindExternalScreen();
            if (!curScene && !curScreen) return;

            BOOL sceneChanged = (curScene != nil && strongSelf.tvExternalWindow != nil && strongSelf.tvExternalWindow.windowScene != curScene);
            if (strongSelf.tvExternalWindow == nil || sceneChanged || strongSelf.tvMovedMetalView.superview == nil) {
                ShadowIOS_VideoOnWillEnterBackground();
                [strongSelf attachMetalViewToExternalDisplay:strongSelf.tvMovedMetalView scene:curScene screen:curScreen];
                ShadowIOS_VideoOnDidEnterForeground();
            } else {
                strongSelf.tvExternalWindow.hidden = NO;
                [strongSelf syncTVMetalLayerDrawableForWindow:strongSelf.tvExternalWindow screen:curScreen];
                ShadowIOS_VideoRequestSwapChainRebuild();
            }
        });
    }
}

- (void)resumeTVModeAfterForegroundActivationWithAttempt:(NSInteger)attempt generation:(NSUInteger)gen {
    if (gen != self.tvResumeGeneration || !self.tvGamepadMode) return;
    if (![self isAppForegroundActive]) return;

    UIWindowScene *extScene = FindExternalWindowScene();
    UIScreen *extScreen = extScene ? extScene.screen : FindExternalScreen();

    if (extScene || extScreen) {
        self.externalDisplayAvailable = YES;
        self.quickTVModeView.available = YES;
        self.quickTVModeView.active = YES;

        // Ricrea SEMPRE una UIWindow esterna fresca dopo blocco schermo/app-switch cosi
        // AirPlay/WindowServer assegna una nuova superficie composita sana a CAMetalLayer!
        ShadowIOS_VideoOnWillEnterBackground();
        [self attachMetalViewToExternalDisplay:self.tvMovedMetalView scene:extScene screen:extScreen];
        self.tvModeSuspendedForBackground = NO;
        ShadowIOS_VideoOnDidEnterForeground();

        // Nudge di sicurezza post-handshake AirPlay (350ms e 950ms) per azzerare qualsiasi freeze residuo
        [self scheduleTVSwapChainFollowUpNudgesForGeneration:gen];
        return;
    }

    // AirPlay puo impiegare 0.3s-1.5s a rinegoziare la scena esterna allo sblocco: breve finestra di retry
    // (mantiene Metal parcheggiato finche la finestra TV non e pronta o il gioco torna su iPhone)
    if (attempt < 4) {
        ShadowIOS_VideoOnWillEnterBackground();
        double delaySec = (attempt == 0) ? 0.30 : ((attempt == 1) ? 0.40 : 0.50);
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ShadowTouchOverlayView *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf resumeTVModeAfterForegroundActivationWithAttempt:(attempt + 1) generation:gen];
        });
        return;
    }

    // Schermo esterno davvero scollegato durante il blocco/background: riporta pulitamente il gioco su iPhone
    self.tvModeSuspendedForBackground = NO;
    [self disableTVModeWithNotify:NO];
    [self showP2Toast:L().toastTVDisconnected duration:3.5];
}

- (void)refreshExternalDisplayAvailabilitySilent:(BOOL)silent {
    BOOL hasExt = (FindExternalWindowScene() != nil) || (FindExternalScreen() != nil);
    BOOL changed = (hasExt != self.externalDisplayAvailable);
    self.externalDisplayAvailable = hasExt;
    self.quickTVModeView.available = hasExt;
    self.quickTVModeView.active = self.tvGamepadMode;

    // Non toccare MAI la finestra TV o il RenderThread Metal mentre l'app e in background/blocco schermo!
    if (![self isAppForegroundActive] || self.tvModeSuspendedForBackground) {
        return;
    }

    if (!hasExt && (self.tvGamepadMode || self.tvExternalWindow != nil)) {
        // AirPlay/HDMI disconnesso durante Modalita TV: riporta subito il gioco sull'iPhone!
        [self disableTVModeWithNotify:NO];
        if (!silent) {
            [self.haptics ensureStarted];
            [self.haptics playDPadTick];
            [self showP2Toast:L().toastTVDisconnected duration:3.5];
        }
    } else if (changed && hasExt && !silent && !self.hiddenForInstaller && !self.hiddenForPhysicalController) {
        [self showP2Toast:L().toastTVReady duration:2.6];
    }
}

- (void)enableTVMode {
    if (self.tvGamepadMode || self.hiddenForInstaller) return;

    UIWindowScene *extScene = FindExternalWindowScene();
    UIScreen *extScreen = extScene ? extScene.screen : FindExternalScreen();
    if (!extScene && !extScreen) {
        self.externalDisplayAvailable = NO;
        self.quickTVModeView.available = NO;
        [self.haptics playDPadTick];
        [self showP2Toast:L().toastTVNeedExt duration:2.8];
        return;
    }

    UIView *metalView = FindGameMetalView(self);
    if (!metalView || metalView == self) {
        [self showP2Toast:L().toastTVVideoNotReady duration:2.5];
        return;
    }

    UIWindow *phoneWindow = self.window ?: metalView.window;
    UIViewController *phoneVC = phoneWindow ? phoneWindow.rootViewController : nil;
    if (!phoneWindow) {
        [self showP2Toast:L().toastTVVideoNotReady duration:2.5];
        return;
    }

    [self clearAllInputs];
    [self toggleQuickBarOpen:NO];

    // 1. Parcheggia in sicurezza il RenderThread Metal/MoltenVK prima di spostare il CAMetalLayer
    ShadowIOS_VideoOnWillEnterBackground();

    // 2. Salva gerarchia e scala originali sull'iPhone (strong ref su metalView per sicurezza ARC durante lo swap)
    BOOL metalWasRootVCView = (phoneVC != nil && phoneVC.view == metalView);
    BOOL overlayWasInMetal = [self isDescendantOfView:metalView];
    UIView *origMetalSuperview = metalView.superview;

    self.tvPhoneWindow = phoneWindow;
    self.tvPhoneRootVC = phoneVC;
    self.tvMovedMetalView = metalView;
    self.tvOriginalMetalSuperview = origMetalSuperview;
    self.tvMetalWasRootVCView = metalWasRootVCView;
    self.tvOverlayWasInMetalView = overlayWasInMetal;
    self.tvOriginalMetalUserInteraction = metalView.userInteractionEnabled;
    self.tvOriginalMetalFrame = metalView.frame;
    self.tvOriginalMetalAutoresizing = metalView.autoresizingMask;
    self.tvOriginalMetalScale = metalView.contentScaleFactor;
    self.tvModeSuspendedForBackground = NO;

    // 3. Stacca SEMPRE ShadowTouchOverlayView da metalView PRIMA di spostare metalView sulla TV:
    //    cosi sulla TV esce SOLO il gioco pulito a schermo intero con ZERO bottoni virtuali!
    if (metalWasRootVCView && phoneVC) {
        UIView *phoneHost = [[UIView alloc] initWithFrame:phoneWindow.bounds];
        phoneHost.backgroundColor = [UIColor blackColor];
        phoneHost.opaque = YES;
        phoneHost.multipleTouchEnabled = YES;
        phoneHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.tvPhoneHostView = phoneHost;

        [self removeFromSuperview];
        self.frame = phoneHost.bounds;
        [phoneHost addSubview:self];

        // Sostituisce rootViewController.view con phoneHost mantenendo landscape, status bar nascosta e keyWindow su iPhone
        phoneVC.view = phoneHost;
        if (phoneHost.superview == nil) {
            UIView *targetContainer = (origMetalSuperview && origMetalSuperview != metalView) ? origMetalSuperview : phoneWindow;
            phoneHost.frame = targetContainer.bounds;
            [targetContainer addSubview:phoneHost];
        } else {
            phoneHost.frame = phoneHost.superview.bounds;
        }
        self.frame = phoneHost.bounds;
        [phoneHost layoutIfNeeded];
    } else if (overlayWasInMetal) {
        UIView *safePhoneParent = (origMetalSuperview && origMetalSuperview != metalView)
                                  ? origMetalSuperview
                                  : ((phoneVC && phoneVC.view && phoneVC.view != metalView) ? phoneVC.view : phoneWindow);
        [self removeFromSuperview];
        self.frame = safePhoneParent.bounds;
        [safePhoneParent addSubview:self];
        [safePhoneParent bringSubviewToFront:self];
    }

    // 4. Crea la UIWindow dedicata sulla TV e sposta SOLO metalView (zero bottoni virtuali sulla TV!)
    [self attachMetalViewToExternalDisplay:metalView scene:extScene screen:extScreen];

    // 5. Riattiva il RenderThread con rebuild pulito della swapchain MoltenVK sul TV display
    ShadowIOS_VideoOnDidEnterForeground();
    self.tvResumeGeneration += 1;
    [self scheduleTVSwapChainFollowUpNudgesForGeneration:self.tvResumeGeneration];

    // 6. Trasforma lo schermo iPhone in controller virtuale dedicato ingrandito cieco-giocabile
    self.tvGamepadMode = YES;
    self.isIdleFaded = NO;
    [self.idleFadeTimer invalidate];
    self.idleFadeTimer = nil;

    self.tvBackdropView.hidden = NO;
    self.tvBackdropView.alpha = 1.0;

    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self redrawAllVectorControls];
    [self applyVisibilityAnimated:YES];
    [self refreshQuickBarLabels];

    [self.haptics ensureStarted];
    [self.haptics playButtonDownIsTrigger:NO pressure:0.95f];
    [self showP2Toast:L().toastTVEnabled duration:3.2];
}

- (void)redrawAllVectorControls {
    NSArray<UIView *> *views = @[
        self.ltView, self.lbView, self.l3View, self.r3View, self.rtView, self.rbView,
        self.leftStickView, self.rightStickView, self.dpadView,
        self.btnYView, self.btnXView, self.btnBView, self.btnAView,
        self.pauseView, self.emeraldView, self.backView, self.tvBackdropView
    ];
    for (UIView *v in views) {
        [v setNeedsDisplay];
    }
    [self.leftStickView.thumbCapView setNeedsDisplay];
    [self.rightStickView.thumbCapView setNeedsDisplay];
}

- (void)disableTVModeWithNotify:(BOOL)notify {
    if (!self.tvGamepadMode && !self.tvExternalWindow) return;

    self.tvResumeGeneration += 1;
    self.tvModeSuspendedForBackground = NO;

    [self clearAllInputs];
    if (self.quickBarOpen) {
        [self toggleQuickBarOpen:NO];
    }

    // 1. Parcheggia Metal/MoltenVK prima di riportare la vista sull'iPhone
    ShadowIOS_VideoOnWillEnterBackground();

    // 2. Riporta CAMetalLayer nella finestra principale dell'iPhone dietro l'overlay
    UIView *metalView = self.tvMovedMetalView;
    UIWindow *phoneWindow = self.tvPhoneWindow ?: self.window;
    UIViewController *phoneVC = self.tvPhoneRootVC ?: (phoneWindow ? phoneWindow.rootViewController : nil);
    UIView *origParent = self.tvOriginalMetalSuperview;
    UIView *phoneHost = self.tvPhoneHostView;
    BOOL metalWasRootVCView = self.tvMetalWasRootVCView;
    BOOL overlayWasInMetal = self.tvOverlayWasInMetalView;

    if (metalView) {
        UIView *hostSuper = phoneHost ? phoneHost.superview : nil;
        [metalView removeFromSuperview];
        metalView.userInteractionEnabled = self.tvOriginalMetalUserInteraction;
        metalView.autoresizingMask = self.tvOriginalMetalAutoresizing;

        if (metalWasRootVCView && phoneVC) {
            [self removeFromSuperview];
            if (phoneHost) {
                [phoneHost removeFromSuperview];
            }
            CGRect restoreFrame = phoneWindow ? phoneWindow.bounds : self.bounds;
            metalView.frame = restoreFrame;
            phoneVC.view = metalView;
            if (metalView.superview == nil) {
                UIView *targetContainer = (hostSuper && hostSuper != metalView)
                                          ? hostSuper
                                          : ((origParent && origParent != metalView) ? origParent : phoneWindow);
                if (targetContainer) {
                    metalView.frame = targetContainer.bounds;
                    [targetContainer insertSubview:metalView atIndex:0];
                }
            } else {
                metalView.frame = metalView.superview.bounds;
            }
            self.frame = metalView.bounds;
            [metalView addSubview:self];
            [metalView bringSubviewToFront:self];
            [metalView layoutIfNeeded];
        } else {
            UIView *targetParent = (origParent && origParent != metalView)
                                   ? origParent
                                   : ((phoneVC && phoneVC.view && phoneVC.view != metalView) ? phoneVC.view : phoneWindow);
            if (targetParent) {
                metalView.frame = targetParent.bounds;
                [targetParent insertSubview:metalView atIndex:0];
                if (overlayWasInMetal) {
                    [self removeFromSuperview];
                    self.frame = metalView.bounds;
                    [metalView addSubview:self];
                    [metalView bringSubviewToFront:self];
                } else {
                    [targetParent bringSubviewToFront:self];
                }
                [targetParent layoutIfNeeded];
            }
        }

        CGFloat fallbackScale = (phoneWindow && phoneWindow.screen) ? phoneWindow.screen.scale : [UIScreen mainScreen].scale;
        CGFloat phoneScale = (self.tvOriginalMetalScale > 0.5) ? self.tvOriginalMetalScale : fallbackScale;
        metalView.contentScaleFactor = phoneScale;
        [metalView layoutIfNeeded];
        CAMetalLayer *ml = FindCAMetalLayerInView(metalView);
        if (ml) {
            ml.contentsScale = phoneScale;
            ml.frame = metalView.bounds;
            ml.drawableSize = CGSizeMake(std::round(metalView.bounds.size.width * phoneScale),
                                         std::round(metalView.bounds.size.height * phoneScale));
        }
    }

    // 3. Stacca completamente la finestra TV cosi iOS ripristina subito il mirroring / schermo iPhone
    [self teardownTVExternalWindowOnly];
    self.tvPhoneHostView = nil;
    self.tvMovedMetalView = nil;
    self.tvOriginalMetalSuperview = nil;
    self.tvPhoneWindow = nil;
    self.tvPhoneRootVC = nil;
    self.tvMetalWasRootVCView = NO;
    self.tvOverlayWasInMetalView = NO;

    if (phoneWindow && !phoneWindow.isKeyWindow) {
        [phoneWindow makeKeyAndVisible];
    }

    // 4. Riattiva il RenderThread SOLO se l'app e realmente attiva in foreground (mai commit Metal in background!)
    if ([self isAppForegroundActive]) {
        ShadowIOS_VideoOnDidEnterForeground();
    }

    // 5. Ripristina l'interfaccia normale su iPhone
    self.tvGamepadMode = NO;
    self.tvBackdropView.hidden = YES;
    self.tvBackdropView.alpha = 0.0;

    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self redrawAllVectorControls];
    [self applyVisibilityAnimated:YES];
    [self refreshQuickBarLabels];
    [self scheduleIdleFadeTimer];

    if (notify) {
        [self.haptics ensureStarted];
        [self.haptics playDPadTick];
        [self showP2Toast:L().toastTVDisabled duration:2.6];
    }
}

- (void)toggleTVMode {
    if (self.tvGamepadMode) {
        [self disableTVModeWithNotify:YES];
    } else {
        [self refreshExternalDisplayAvailabilitySilent:YES];
        if (!self.externalDisplayAvailable) {
            [self.haptics playDPadTick];
            [self showP2Toast:L().toastTVNeedExt duration:2.8];
            return;
        }
        [self enableTVMode];
    }
}

- (void)registerNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onControllerConnectionChanged:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onControllerConnectionChanged:) name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(onAppWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onAppDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(onAppWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(onAppDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:@"ShadowIOSExternalDisplayChanged" object:nil];
    if (@available(iOS 13.0, *)) {
        [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:UISceneWillConnectNotification object:nil];
        [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:UISceneDidDisconnectNotification object:nil];
        [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:UISceneDidActivateNotification object:nil];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:UIScreenDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onExternalDisplayChanged:) name:UIScreenDidDisconnectNotification object:nil];
#pragma clang diagnostic pop
}

- (void)onExternalDisplayChanged:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isAppForegroundActive]) {
            return;
        }
        if (self.tvGamepadMode) {
            UIWindowScene *extScene = FindExternalWindowScene();
            UIScreen *extScreen = extScene ? extScene.screen : FindExternalScreen();
            BOOL needsRebuild = self.tvModeSuspendedForBackground ||
                                (self.tvExternalWindow == nil) ||
                                (extScene != nil && self.tvExternalWindow.windowScene != extScene);
            if ((extScene || extScreen) && needsRebuild) {
                self.tvResumeGeneration += 1;
                [self resumeTVModeAfterForegroundActivationWithAttempt:0 generation:self.tvResumeGeneration];
                return;
            }
            if ((extScene || extScreen) && self.tvExternalWindow != nil) {
                [self syncTVMetalLayerDrawableForWindow:self.tvExternalWindow screen:extScreen];
                ShadowIOS_VideoRequestSwapChainRebuild();
                return;
            }
        }
        [self refreshExternalDisplayAvailabilitySilent:NO];
    });
}

- (void)onControllerConnectionChanged:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshPhysicalControllerState];
    });
}

- (void)onAppWillResignActive:(NSNotification *)note {
    (void)note;
    [self clearAllInputs];
}

- (void)onAppDidEnterBackground:(NSNotification *)note {
    (void)note;
    if (self.twoPlayerEnabled) {
        // Mantiene vivo NWListener per ~25s mentre l'utente incolla il link su WhatsApp/Messaggi
        IOSRemoteP2_SetAppInBackground(true);
    }
    if (self.tvGamepadMode) {
        // Stacca pulitamente la finestra TV esterna in background cosi AirPlay/WindowServer
        // non lascia una superficie CAMetalLayer orfana allo sblocco o al rientro nell'app!
        self.tvResumeGeneration += 1;
        self.tvModeSuspendedForBackground = YES;
        ShadowIOS_VideoOnWillEnterBackground();
        [self teardownTVExternalWindowOnly];
    }
}

- (void)onAppWillEnterForeground:(NSNotification *)note {
    (void)note;
    IOSRemoteP2_SetAppInBackground(false);
    if (self.twoPlayerEnabled) {
        IOSRemoteP2_EnsureAlive();
    }
}

- (void)onAppDidBecomeActive:(NSNotification *)note {
    (void)note;
    IOSRemoteP2_SetAppInBackground(false);
    if (self.twoPlayerEnabled) {
        IOSRemoteP2_EnsureAlive();
    }
    [self.haptics ensureStarted];
    [self refreshPhysicalControllerState];

    if (self.tvGamepadMode) {
        // Ricostruisce la finestra TV dedicata + swapchain MoltenVK in modo sicuro dopo blocco schermo o app-switch
        self.tvResumeGeneration += 1;
        [self resumeTVModeAfterForegroundActivationWithAttempt:0 generation:self.tvResumeGeneration];
    } else {
        [self refreshExternalDisplayAvailabilitySilent:YES];
    }

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }
    [self wakeControlsAnimated:YES];
}

- (BOOL)hasApplePhysicalController {
    for (GCController *ctrl in [GCController controllers]) {
        if (ctrl.extendedGamepad != nil || ctrl.microGamepad != nil) {
            return YES;
        }
    }
    return NO;
}

- (void)refreshPhysicalControllerState {
    BOOL physical = [self hasApplePhysicalController] || g_lastPhysicalSDL.load(std::memory_order_relaxed);
    BOOL changed = (physical != self.hiddenForPhysicalController);
    self.hiddenForPhysicalController = physical;
    if (physical) {
        [self clearAllInputs];
        self.quickBarOpen = NO;
        self.quickBarView.hidden = YES;
        self.quickBarView.alpha = 0.0;
    }
    if (changed || physical) {
        [self applyVisibilityAnimated:YES];
    }
}

- (void)updateExternalPhysical:(BOOL)sdlPhysical installerVisible:(BOOL)installerVisible chaosAura:(int)aura {
    BOOL physical = sdlPhysical || [self hasApplePhysicalController];
    BOOL visChanged = (physical != self.hiddenForPhysicalController) || (installerVisible != self.hiddenForInstaller);

    self.hiddenForPhysicalController = physical;
    self.hiddenForInstaller = installerVisible;

    if (physical || installerVisible) {
        [self clearAllInputs];
    }

    if (self.chaosAuraMode != aura) {
        self.chaosAuraMode = aura;
        self.emeraldView.chaosAuraMode = aura;
        self.rightStickView.chaosAuraMode = aura;
        [self.emeraldView setNeedsDisplay];
        [self.rightStickView setNeedsDisplay];
    }

    if (visChanged) {
        [self applyVisibilityAnimated:YES];
        if (!physical && !installerVisible) {
            [self wakeControlsAnimated:YES];
        }
    }
}

- (void)applyVisibilityAnimated:(BOOL)animated {
    BOOL shouldHideCompletely = self.hiddenForPhysicalController || self.hiddenForInstaller;
    if (self.hiddenForInstaller && self.tvGamepadMode) {
        [self disableTVModeWithNotify:NO];
    }
    self.userInteractionEnabled = !shouldHideCompletely;
    if (shouldHideCompletely) {
        self.controlsContainer.alpha = 0.0;
        self.hidden = YES;
        return;
    }
    self.hidden = NO;
    CGFloat activeAlpha = self.tvGamepadMode ? 1.0 : self.preferredOpacity;
    CGFloat targetAlpha = (self.isIdleFaded && !self.tvGamepadMode) ? 0.0 : activeAlpha;
    NSTimeInterval dur = animated ? (targetAlpha < 0.01 ? 0.35 : 0.22) : 0.0;

    [UIView animateWithDuration:dur
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.controlsContainer.alpha = targetAlpha;
    } completion:nil];
}

#pragma mark - 4-Second Inactivity Auto-Fade & Instant Screen Wake

- (void)scheduleIdleFadeTimer {
    [self.idleFadeTimer invalidate];
    self.idleFadeTimer = nil;

    if (self.tvGamepadMode || !self.autoHideEnabled || self.hiddenForPhysicalController || self.hiddenForInstaller || self.quickBarOpen || (self.twoPlayerEnabled && !self.p2ClientConnected)) {
        return;
    }
    if (!_activeTouches.empty()) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.idleFadeTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoHideIdleSeconds repeats:NO block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        ShadowTouchOverlayView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.tvGamepadMode || !strongSelf->_activeTouches.empty() || !strongSelf.autoHideEnabled || strongSelf.quickBarOpen || (strongSelf.twoPlayerEnabled && !strongSelf.p2ClientConnected)) return;
        if (strongSelf.hiddenForPhysicalController || strongSelf.hiddenForInstaller) return;

        strongSelf.isIdleFaded = YES;
        [UIView animateWithDuration:0.75
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseInOut
                         animations:^{
            strongSelf.controlsContainer.alpha = 0.0;
        } completion:nil];
    }];
}

- (void)wakeControlsAnimated:(BOOL)animated {
    if (self.hiddenForPhysicalController || self.hiddenForInstaller) return;
    [self.idleFadeTimer invalidate];
    self.idleFadeTimer = nil;

    CGFloat activeAlpha = self.tvGamepadMode ? 1.0 : self.preferredOpacity;
    BOOL wasFaded = self.isIdleFaded || (self.controlsContainer.alpha < activeAlpha - 0.03);
    self.isIdleFaded = NO;

    if (wasFaded) {
        [UIView animateWithDuration:animated ? 0.20 : 0.0
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut
                         animations:^{
            self.controlsContainer.alpha = activeAlpha;
        } completion:nil];
    }
    if (_activeTouches.empty()) {
        [self scheduleIdleFadeTimer];
    }
}

#pragma mark - Responsive Landscape Layout (iPhone 16 Pro Dynamic Island & Safe Area Aware)

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect b = self.bounds;
    if (b.size.width < 100.0 || b.size.height < 100.0) return;

    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat leftPad   = MAX(safe.left, 18.0) + 6.0;
    CGFloat rightPad  = MAX(safe.right, 18.0) + 6.0;
    CGFloat topPad    = MAX(safe.top, 8.0) + 6.0;
    CGFloat bottomPad = MAX(safe.bottom, 12.0) + 4.0;

    CGFloat H = b.size.height;
    CGFloat W = b.size.width;
    // Scala ergonomica proporzionale all'altezza schermo (iPhone 16 Pro landscape ~402pt)
    CGFloat s = ClampF(static_cast<float>(H / 402.0), 0.76f, 1.32f);
    CGFloat midX = W * 0.5;
    self.tvBackdropView.frame = b;

    if (self.tvGamepadMode) {
        // MODALITA TV GAMEPAD: controlli ingranditi cieco-giocabili (zero sovrapposizioni, massima ergonomia guardando la TV)
        CGFloat trigW = 128.0 * s;
        CGFloat trigH = 40.0 * s;
        CGFloat lbH   = 35.0 * s;
        CGFloat wingW = 84.0 * s;
        CGFloat wingH = 62.0 * s;
        CGFloat gapY  = 7.0 * s;

        self.ltView.frame = CGRectMake(leftPad, topPad, trigW, trigH);
        self.lbView.frame = CGRectMake(leftPad, topPad + trigH + gapY, trigW, lbH);
        self.l3View.frame = CGRectMake(leftPad + trigW + 8.0 * s, topPad, wingW, wingH);

        self.rtView.frame = CGRectMake(W - rightPad - trigW, topPad, trigW, trigH);
        self.rbView.frame = CGRectMake(W - rightPad - trigW, topPad + trigH + gapY, trigW, lbH);
        self.r3View.frame = CGRectMake(W - rightPad - trigW - 8.0 * s - wingW, topPad, wingW, wingH);

        CGFloat lStickSize = 152.0 * s;
        CGFloat lStickX = leftPad + 4.0 * s;
        CGFloat minLeftY = CGRectGetMaxY(self.lbView.frame) + 10.0 * s;
        CGFloat lStickY = MAX(minLeftY, H * 0.44 - lStickSize * 0.5);
        self.leftStickView.frame = CGRectMake(lStickX, lStickY, lStickSize, lStickSize);

        CGFloat dpadSize = 114.0 * s;
        CGFloat dpadX = lStickX + lStickSize * 0.88;
        CGFloat dpadY = H - bottomPad - dpadSize;
        self.dpadView.frame = CGRectMake(dpadX, dpadY, dpadSize, dpadSize);

        CGFloat btnSize = 66.0 * s;
        CGFloat diamondSpread = 56.0 * s;
        CGFloat abxyCenterX = W - rightPad - 94.0 * s;
        CGFloat minAbxyCenterY = CGRectGetMaxY(self.rbView.frame) + diamondSpread + btnSize * 0.5 + 8.0 * s;
        CGFloat abxyCenterY = MAX(minAbxyCenterY, H * 0.47);

        self.btnYView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY - diamondSpread - btnSize * 0.5, btnSize, btnSize);
        self.btnAView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY + diamondSpread - btnSize * 0.5, btnSize, btnSize);
        self.btnXView.frame = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
        self.btnBView.frame = CGRectMake(abxyCenterX + diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
        _abxyClusterRect = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.62,
                                      abxyCenterY - diamondSpread - btnSize * 0.62,
                                      (diamondSpread + btnSize * 0.62) * 2.0,
                                      (diamondSpread + btnSize * 0.62) * 2.0);

        CGFloat rStickSize = 104.0 * s;
        CGFloat rStickX = W - (dpadX + dpadSize);
        CGFloat rStickY = H - bottomPad - rStickSize;
        self.rightStickView.frame = CGRectMake(rStickX, rStickY, rStickSize, rStickSize);

        CGFloat navSize = 46.0 * s;
        CGFloat navGap  = 18.0 * s;
        CGFloat navY    = H - bottomPad - navSize - 2.0 * s;
        self.emeraldView.frame = CGRectMake(midX - navSize * 0.5, navY, navSize, navSize);
        self.pauseView.frame   = CGRectMake(midX - navSize * 1.5 - navGap, navY, navSize, navSize);
        self.backView.frame    = CGRectMake(midX + navSize * 0.5 + navGap, navY, navSize, navSize);
    } else {
        // 1. Top-Left Shoulders (LT sopra, LB sotto, L3 ala interna angolata)
        CGFloat trigW = 86.0 * s;
        CGFloat trigH = 30.0 * s;
        CGFloat wingW = 70.0 * s;
        CGFloat wingH = 54.0 * s;
        CGFloat gapY  = 6.0 * s;

        self.ltView.frame = CGRectMake(leftPad, topPad, trigW, trigH);
        self.lbView.frame = CGRectMake(leftPad, topPad + trigH + gapY, trigW, trigH * 0.88);
        self.l3View.frame = CGRectMake(leftPad + trigW + 6.0 * s, topPad, wingW, wingH);

        // 2. Top-Right Shoulders (speculari: R3 ala interna, RT sopra, RB sotto)
        self.rtView.frame = CGRectMake(W - rightPad - trigW, topPad, trigW, trigH);
        self.rbView.frame = CGRectMake(W - rightPad - trigW, topPad + trigH + gapY, trigW, trigH * 0.88);
        self.r3View.frame = CGRectMake(W - rightPad - trigW - 6.0 * s - wingW, topPad, wingW, wingH);

        // 3. Center-Left: L-Analog Stick (Shadow Emblem + anello uncinato) centrato verticalmente (50% altezza)
        CGFloat lStickSize = 114.0 * s;
        CGFloat lStickX = leftPad + 10.0 * s;
        CGFloat midY = H * 0.50;
        CGFloat minLeftY = CGRectGetMaxY(self.lbView.frame) + 12.0 * s;
        CGFloat lStickY = MAX(minLeftY, midY - lStickSize * 0.5);
        self.leftStickView.frame = CGRectMake(lStickX, lStickY, lStickSize, lStickSize);

        // 4. Bottom-Left (stile Xbox Original): D-Pad 8-direzioni in basso leggermente verso l'interno
        CGFloat dpadSize = 96.0 * s;
        CGFloat dpadX = lStickX + lStickSize * 0.72;
        CGFloat dpadY = H - bottomPad - dpadSize;
        self.dpadView.frame = CGRectMake(dpadX, dpadY, dpadSize, dpadSize);

        // 5. Center-Right: Diamante Action Buttons (Y, X, B, A) centrato verticalmente (allineato all'analogico sinistro)
        CGFloat btnSize = 52.0 * s;
        CGFloat diamondSpread = 45.0 * s;
        CGFloat abxyCenterX = W - rightPad - 76.0 * s;
        CGFloat minAbxyCenterY = CGRectGetMaxY(self.rbView.frame) + diamondSpread + btnSize * 0.5 + 12.0 * s;
        CGFloat abxyCenterY = MAX(minAbxyCenterY, midY);

        self.btnYView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY - diamondSpread - btnSize * 0.5, btnSize, btnSize);
        self.btnAView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY + diamondSpread - btnSize * 0.5, btnSize, btnSize);
        self.btnXView.frame = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
        self.btnBView.frame = CGRectMake(abxyCenterX + diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
        _abxyClusterRect = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.56,
                                      abxyCenterY - diamondSpread - btnSize * 0.56,
                                      (diamondSpread + btnSize * 0.56) * 2.0,
                                      (diamondSpread + btnSize * 0.56) * 2.0);

        // 6. Bottom-Right (speculare al D-Pad): R-Analog Camera Stick
        CGFloat rStickSize = 88.0 * s;
        CGFloat rStickX = abxyCenterX - diamondSpread - rStickSize * 0.72;
        CGFloat rStickY = H - bottomPad - rStickSize;
        self.rightStickView.frame = CGRectMake(rStickX, rStickY, rStickSize, rStickSize);

        // 7. Bottom-Center: Navigazione (Pausa, Chaos Emerald, Indietro)
        CGFloat navSize = 40.0 * s;
        CGFloat navGap  = 16.0 * s;
        CGFloat navY    = H - bottomPad - navSize - 2.0 * s;

        self.emeraldView.frame = CGRectMake(midX - navSize * 0.5, navY, navSize, navSize);
        self.pauseView.frame   = CGRectMake(midX - navSize * 1.5 - navGap, navY, navSize, navSize);
        self.backView.frame    = CGRectMake(midX + navSize * 0.5 + navGap, navY, navSize, navSize);
    }

    // 8. Quick-HUD Bar sopra al Chaos Emerald (5 pulsanti: Opacità | Aptica | Sfuma 4s | TV | 2 Omini)
    CGFloat navY = CGRectGetMinY(self.emeraldView.frame);
    CGFloat qbW = 396.0 * s;
    CGFloat qbH = 38.0 * s;
    self.quickBarView.frame = CGRectMake(midX - qbW * 0.5, navY - qbH - 10.0 * s, qbW, qbH);
    CGFloat pad = 5.0 * s;
    CGFloat tvBtnW = 44.0 * s;
    CGFloat twoPBtnW = 46.0 * s;
    CGFloat textAreaW = qbW - pad * 6.0 - tvBtnW - twoPBtnW;
    CGFloat itemW = textAreaW / 3.0;
    CGFloat itemH = qbH - pad * 2.0;
    self.quickOpacityLabel.frame   = CGRectMake(pad, pad, itemW, itemH);
    self.quickHapticsLabel.frame   = CGRectMake(pad * 2.0 + itemW, pad, itemW, itemH);
    self.quickAutoHideLabel.frame  = CGRectMake(pad * 3.0 + itemW * 2.0, pad, itemW, itemH);
    self.quickTVModeView.frame     = CGRectMake(pad * 4.0 + itemW * 3.0, pad, tvBtnW, itemH);
    self.quickTwoPlayersView.frame = CGRectMake(pad * 5.0 + itemW * 3.0 + tvBtnW, pad, twoPBtnW, itemH);

    _quickOpacityRect    = [self convertRect:self.quickOpacityLabel.frame fromView:self.quickBarView];
    _quickHapticsRect    = [self convertRect:self.quickHapticsLabel.frame fromView:self.quickBarView];
    _quickAutoHideRect   = [self convertRect:self.quickAutoHideLabel.frame fromView:self.quickBarView];
    _quickTVModeRect     = [self convertRect:self.quickTVModeView.frame fromView:self.quickBarView];
    _quickTwoPlayersRect = [self convertRect:self.quickTwoPlayersView.frame fromView:self.quickBarView];

    // 9. Mini-bottoncino Abbina/Pairing -> Connesso/Connected + Toast 2P sopra la Quick-HUD Bar
    [self updateP2FloatingFrames];
}

- (void)updateP2FloatingFrames {
    CGRect b = self.bounds;
    if (b.size.width < 100.0 || b.size.height < 100.0) return;

    CGFloat H = b.size.height;
    CGFloat W = b.size.width;
    CGFloat s = ClampF(static_cast<float>(H / 402.0), 0.76f, 1.32f);
    CGFloat midX = W * 0.5;

    CGFloat pillH = 26.0 * s;
    CGSize pillLblSz = [self.p2StatusLabel sizeThatFits:CGSizeMake(180.0 * s, pillH)];
    CGFloat pillW = MAX(92.0 * s, pillLblSz.width + 36.0 * s);
    CGFloat navY = CGRectGetMinY(self.emeraldView.frame);
    CGFloat qbH = 38.0 * s;
    CGFloat anchorY = self.quickBarOpen
        ? (navY - qbH - 10.0 * s - pillH - 8.0 * s)
        : (navY - pillH - 10.0 * s);

    CGAffineTransform prevT = self.p2StatusPillView.transform;
    self.p2StatusPillView.transform = CGAffineTransformIdentity;
    self.p2StatusPillView.frame = CGRectMake(midX - pillW * 0.5, anchorY, pillW, pillH);
    self.p2StatusPillView.layer.cornerRadius = pillH * 0.5;
    self.p2StatusPillView.transform = prevT;

    CGFloat dotSize = 7.0 * s;
    CGFloat dotX = 11.0 * s;
    self.p2StatusDotView.frame = CGRectMake(dotX, (pillH - dotSize) * 0.5, dotSize, dotSize);
    self.p2StatusDotView.layer.cornerRadius = dotSize * 0.5;

    CGFloat lblX = dotX + dotSize + 7.0 * s;
    self.p2StatusLabel.frame = CGRectMake(lblX, 0, pillW - lblX - 8.0 * s, pillH);

    // Toast link copiato centrato subito sopra il bottoncino Pairing
    CGSize toastSize = [self.p2ToastLabel sizeThatFits:CGSizeMake(W * 0.78, 24.0 * s)];
    CGFloat toastW = MIN(W * 0.82, MAX(148.0 * s, toastSize.width + 14.0 * s));
    CGFloat toastH = 22.0 * s;
    self.p2ToastLabel.frame = CGRectMake(midX - toastW * 0.5, anchorY - toastH - 6.0 * s, toastW, toastH);

    // Card QR Code centrata nella parte medio-alta dello schermo (100% opaca e leggibile in landscape)
    CGFloat cardW = MIN(W * 0.72, 368.0 * s);
    CGFloat cardH = MIN(H * 0.44, 152.0 * s);
    CGFloat cardX = midX - cardW * 0.5;
    CGFloat cardY = MAX(18.0 * s, anchorY - cardH - 32.0 * s);

    CGAffineTransform prevCardT = self.p2PairingCardView.transform;
    self.p2PairingCardView.transform = CGAffineTransformIdentity;
    self.p2PairingCardView.frame = CGRectMake(cardX, cardY, cardW, cardH);

    CGFloat pad = 12.0 * s;
    CGFloat qrSize = cardH - pad * 2.0;
    self.p2QrFrameView.frame = CGRectMake(pad, pad, qrSize, qrSize);
    self.p2QrImageView.frame = CGRectInset(self.p2QrFrameView.bounds, 4.0 * s, 4.0 * s);

    CGFloat rightX = pad + qrSize + 12.0 * s;
    CGFloat rightW = cardW - rightX - pad;
    self.p2CardTitleLabel.frame = CGRectMake(rightX, pad, rightW, 18.0 * s);
    self.p2CardSubLabel.frame = CGRectMake(rightX, pad + 19.0 * s, rightW, 38.0 * s);

    CGFloat btnH = 28.0 * s;
    CGFloat btnY = cardH - pad - btnH;
    CGFloat urlH = 26.0 * s;
    CGFloat urlY = btnY - urlH - 8.0 * s;
    self.p2CardUrlLabel.frame = CGRectMake(rightX, urlY, rightW, urlH);

    CGFloat btnGap = 8.0 * s;
    CGFloat closeW = 68.0 * s;
    CGFloat copyW = rightW - closeW - btnGap;
    self.p2CardCopyBtn.frame = CGRectMake(rightX, btnY, copyW, btnH);
    self.p2CardCloseBtn.frame = CGRectMake(rightX + copyW + btnGap, btnY, closeW, btnH);

    _p2CardCopyRect  = [self convertRect:self.p2CardCopyBtn.frame fromView:self.p2PairingCardView];
    _p2CardCloseRect = [self convertRect:self.p2CardCloseBtn.frame fromView:self.p2PairingCardView];
    self.p2PairingCardView.transform = prevCardT;
}

#pragma mark - Hit Testing & Passthrough

- (TouchTargetKind)targetKindAtPoint:(CGPoint)p {
    if (self.p2CardVisible && !self.p2PairingCardView.hidden) {
        if (CGRectContainsPoint(CGRectInset(_p2CardCopyRect, -6, -6), p))  return TouchTargetKind::P2CardCopy;
        if (CGRectContainsPoint(CGRectInset(_p2CardCloseRect, -6, -6), p)) return TouchTargetKind::P2CardClose;
        if (CGRectContainsPoint(self.p2PairingCardView.frame, p))          return TouchTargetKind::P2CardBody;
    }
    if (self.twoPlayerEnabled && !self.p2StatusPillView.hidden && self.p2StatusPillView.alpha > 0.1 &&
        CGRectContainsPoint(CGRectInset(self.p2StatusPillView.frame, -8, -8), p)) {
        return TouchTargetKind::P2StatusPill;
    }
    if (self.quickBarOpen && CGRectContainsPoint(CGRectInset(self.quickBarView.frame, -6, -6), p)) {
        return TouchTargetKind::QuickBar;
    }
    CGFloat xp = self.tvGamepadMode ? 6.0 : 0.0;
    if (CGRectContainsPoint(CGRectInset(self.leftStickView.frame, -(12 + xp), -(12 + xp)), p))  return TouchTargetKind::LeftStick;
    if (CGRectContainsPoint(CGRectInset(self.rightStickView.frame, -(10 + xp), -(10 + xp)), p)) return TouchTargetKind::RightStick;
    if (CGRectContainsPoint(CGRectInset(self.dpadView.frame, -(8 + xp), -(8 + xp)), p))         return TouchTargetKind::DPad;
    if (CGRectContainsPoint(_abxyClusterRect, p))                                               return TouchTargetKind::ABXYCluster;
    if (CGRectContainsPoint(CGRectInset(self.ltView.frame, -(6 + xp), -(6 + xp)), p))           return TouchTargetKind::LT;
    if (CGRectContainsPoint(CGRectInset(self.lbView.frame, -(6 + xp), -(6 + xp)), p))           return TouchTargetKind::LB;
    if (CGRectContainsPoint(CGRectInset(self.l3View.frame, -(5 + xp), -(5 + xp)), p))           return TouchTargetKind::L3;
    if (CGRectContainsPoint(CGRectInset(self.r3View.frame, -(5 + xp), -(5 + xp)), p))           return TouchTargetKind::R3;
    if (CGRectContainsPoint(CGRectInset(self.rtView.frame, -(6 + xp), -(6 + xp)), p))           return TouchTargetKind::RT;
    if (CGRectContainsPoint(CGRectInset(self.rbView.frame, -(6 + xp), -(6 + xp)), p))           return TouchTargetKind::RB;
    if (CGRectContainsPoint(CGRectInset(self.pauseView.frame, -(8 + xp), -(8 + xp)), p))        return TouchTargetKind::Start;
    if (CGRectContainsPoint(CGRectInset(self.emeraldView.frame, -(8 + xp), -(8 + xp)), p))      return TouchTargetKind::ChaosEmerald;
    if (CGRectContainsPoint(CGRectInset(self.backView.frame, -(8 + xp), -(8 + xp)), p))         return TouchTargetKind::Back;
    return TouchTargetKind::None;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hiddenForPhysicalController || self.hiddenForInstaller) {
        return nil;
    }
    // Risveglia sempre i comandi quando l'utente ritocca un punto qualsiasi dello schermo!
    [self wakeControlsAnimated:YES];

    TouchTargetKind kind = [self targetKindAtPoint:point];
    if (kind != TouchTargetKind::None) {
        return self;
    }
    // Tocchi fuori dai comandi: chiudi eventuale Quick-Bar
    if (self.quickBarOpen) {
        [self toggleQuickBarOpen:NO];
    }
    // In Modalita TV l'iPhone e un controller dedicato: assorbe tocchi casuali sullo sfondo scuro
    if (self.tvGamepadMode) {
        return self;
    }
    return nil;
}

#pragma mark - Multi-Touch Logic & Xbox Original Mapping

- (int)closestABXYButtonAtPoint:(CGPoint)p {
    ShadowActionButtonView *views[4] = { self.btnAView, self.btnBView, self.btnXView, self.btnYView };
    int best = -1;
    CGFloat bestDist = 1e9;
    for (int i = 0; i < 4; i++) {
        CGPoint c = views[i].center;
        CGFloat d = std::hypot(p.x - c.x, p.y - c.y);
        CGFloat hitR = views[i].bounds.size.width * 0.72;
        if (d <= hitR && d < bestDist) {
            bestDist = d;
            best = i;
        }
    }
    return best;
}

- (uint16_t)dpadMaskAtPoint:(CGPoint)p {
    CGPoint c = self.dpadView.center;
    CGFloat dx = p.x - c.x;
    CGFloat dy = p.y - c.y;
    CGFloat r = self.dpadView.bounds.size.width * 0.5;
    if (std::hypot(dx, dy) < r * 0.14) return 0;

    // 8 direzioni con soglia diagonale bilanciata (22.5 gradi)
    CGFloat angle = std::atan2(dy, dx); // -PI..PI, 0 = destra, -PI/2 = su
    CGFloat deg = angle * 180.0 / M_PI;
    uint16_t mask = 0;
    if (deg >= -157.5 && deg <= -22.5) mask |= kXboxDPadUp;
    if (deg >=   22.5 && deg <= 157.5) mask |= kXboxDPadDown;
    if (deg >=  -67.5 && deg <=  67.5) mask |= kXboxDPadRight;
    if (deg >=  112.5 || deg <= -112.5) mask |= kXboxDPadLeft;
    return mask;
}

- (void)computeStickForView:(ShadowAnalogStickView *)stickView
                      point:(CGPoint)p
                   pressure:(float)pressure01
                   outNormX:(float *)outNormX
                   outNormY:(float *)outNormY
                    outZone:(int *)outZone {
    CGPoint c = stickView.center;
    CGFloat maxR = MIN(stickView.bounds.size.width, stickView.bounds.size.height) * 0.40;
    if (maxR < 10.0) maxR = 40.0;

    float dx = static_cast<float>((p.x - c.x) / maxR);
    float dy = static_cast<float>((p.y - c.y) / maxR);
    float mag = std::hypot(dx, dy);

    if (mag > 1.0f) {
        dx /= mag;
        dy /= mag;
        mag = 1.0f;
    }

    // Curva progressiva sensibile alla pressione: micro-movimento preciso al centro, sprint pieno al bordo
    float deadzone = 0.08f;
    float curvedMag = 0.0f;
    if (mag > deadzone) {
        float norm = (mag - deadzone) / (1.0f - deadzone);
        // Leggero boost di risposta con pressione decisa sul polpastrello
        float pressureBoost = 1.0f + (pressure01 - 0.5f) * 0.14f;
        curvedMag = ClampF(std::pow(norm, 1.15f) * pressureBoost, 0.0f, 1.0f);
        if (norm > 0.88f) {
            curvedMag = 1.0f; // Garantisce velocità massima di Shadow sul bordo!
        }
    }

    float scale = (mag > 0.001f) ? (curvedMag / mag) : 0.0f;
    *outNormX = dx * scale;
    *outNormY = dy * scale;

    if (curvedMag >= 0.94f) {
        *outZone = 2;
    } else if (curvedMag >= 0.50f) {
        *outZone = 1;
    } else {
        *outZone = 0;
    }
}

- (float)computeTriggerAnalogForView:(ShadowWingButtonView *)view point:(CGPoint)p pressure:(float)pressure01 {
    CGRect f = view.frame;
    float slide = ClampF(static_cast<float>((p.y - CGRectGetMinY(f)) / MAX(f.size.height, 1.0)), 0.0f, 1.0f);
    // Combina pressione del polpastrello e affondo verticale: minimo 0.62 così un tap rapido attiva sempre LT/RT
    return ClampF(0.58f + 0.30f * pressure01 + 0.16f * slide, 0.62f, 1.0f);
}

- (void)toggleQuickBarOpen:(BOOL)open {
    if (self.quickBarOpen == open) return;
    self.quickBarOpen = open;
    if (open) {
        [self refreshExternalDisplayAvailabilitySilent:YES];
        [self refreshQuickBarLabels];
        self.quickBarView.hidden = NO;
        [self.idleFadeTimer invalidate];
        self.idleFadeTimer = nil;
        if (self.twoPlayerEnabled && self.p2ClientConnected) {
            [self cancelP2ConnectedPillAutoHide];
            [self refreshP2StatusPillAnimated:YES];
        }
    } else if (self.twoPlayerEnabled && self.p2ClientConnected) {
        [self scheduleP2ConnectedPillAutoHideAfter:2.0];
    }
    [UIView animateWithDuration:0.18 animations:^{
        self.quickBarView.alpha = open ? 1.0 : 0.0;
        self.quickBarView.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
        [self updateP2FloatingFrames];
    } completion:^(BOOL finished) {
        (void)finished;
        if (!self.quickBarOpen) {
            self.quickBarView.hidden = YES;
            [self scheduleIdleFadeTimer];
        }
    }];
}

- (void)handleQuickBarTapAtPoint:(CGPoint)p {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (CGRectContainsPoint(_quickOpacityRect, p)) {
        if (self.preferredOpacity < 0.45)      self.preferredOpacity = 0.58;
        else if (self.preferredOpacity < 0.72) self.preferredOpacity = 0.80;
        else                                   self.preferredOpacity = 0.35;
        [ud setDouble:self.preferredOpacity forKey:@"ShadowIOS_OverlayOpacity"];
        [self applyVisibilityAnimated:YES];
        [self.haptics playDPadTick];
    } else if (CGRectContainsPoint(_quickHapticsRect, p)) {
        self.haptics.enabled = !self.haptics.enabled;
        [ud setBool:self.haptics.enabled forKey:@"ShadowIOS_HapticsOn"];
        if (self.haptics.enabled) {
            [self.haptics ensureStarted];
            [self.haptics playButtonDownIsTrigger:NO pressure:0.8f];
        }
    } else if (CGRectContainsPoint(_quickAutoHideRect, p)) {
        self.autoHideEnabled = !self.autoHideEnabled;
        [ud setBool:self.autoHideEnabled forKey:@"ShadowIOS_AutoHide4s"];
        [self.haptics playDPadTick];
    } else if (CGRectContainsPoint(_quickTVModeRect, p)) {
        [self toggleTVMode];
    } else if (CGRectContainsPoint(_quickTwoPlayersRect, p)) {
        self.twoPlayerEnabled = !self.twoPlayerEnabled;
        if (self.twoPlayerEnabled) {
            self.p2ConnectedPillDismissed = NO;
            [self.haptics ensureStarted];
            [self.haptics playButtonDownIsTrigger:NO pressure:0.8f];
            [self refreshP2StatusPillAnimated:YES];
            [self.idleFadeTimer invalidate];
            self.idleFadeTimer = nil;
        } else {
            IOSRemoteP2_StopServer();
            self.p2ServerRunning = NO;
            self.p2ClientConnected = NO;
            self.p2ConnectedPillDismissed = NO;
            [self cancelP2ConnectedPillAutoHide];
            [self setP2PairingCardVisible:NO animated:YES];
            [self.p2ToastTimer invalidate];
            self.p2ToastTimer = nil;
            self.p2ToastLabel.alpha = 0.0;
            self.p2ToastLabel.hidden = YES;
            [self.haptics playDPadTick];
            [self refreshP2StatusPillAnimated:YES];
            [self scheduleIdleFadeTimer];
        }
    }
    [self refreshQuickBarLabels];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (self.hiddenForPhysicalController || self.hiddenForInstaller) return;
    [self wakeControlsAnimated:YES];

    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        TouchTargetKind kind = [self targetKindAtPoint:p];
        if (kind == TouchTargetKind::None) continue;

        uintptr_t key = reinterpret_cast<uintptr_t>((__bridge const void *)touch);
        float pressure = ComputeTouchPressure01(touch);

        ActiveTouchRecord rec{};
        rec.kind = kind;
        rec.subButton = -1;
        rec.analogVal = pressure;

        switch (kind) {
            case TouchTargetKind::P2CardCopy: {
                IOSRemoteP2_EnsureAlive();
                char urlBuf[160] = {0};
                IOSRemoteP2_GetURL(urlBuf, sizeof(urlBuf));
                NSString *urlStr = [NSString stringWithUTF8String:urlBuf];
                if (urlStr.length > 0) {
                    [UIPasteboard generalPasteboard].string = urlStr;
                    [self updateP2PairingCardURL:urlStr];
                    [self showP2Toast:[NSString stringWithFormat:L().toastLinkCopiedFmt, urlStr] duration:3.5];
                }
                [self.haptics ensureStarted];
                [self.haptics playButtonDownIsTrigger:NO pressure:0.85f];
                continue;
            }
            case TouchTargetKind::P2CardClose:
                [self.haptics playDPadTick];
                [self setP2PairingCardVisible:NO animated:YES];
                continue;
            case TouchTargetKind::P2CardBody:
                continue;
            case TouchTargetKind::P2StatusPill:
                [self handlePairingPillTap];
                continue;
            case TouchTargetKind::QuickBar:
                [self handleQuickBarTapAtPoint:p];
                continue;
            case TouchTargetKind::ChaosEmerald:
                self.emeraldView.pressed = YES;
                [self.haptics playButtonDownIsTrigger:NO pressure:pressure];
                break;
            case TouchTargetKind::LeftStick: {
                float nx = 0, ny = 0; int zone = 0;
                [self computeStickForView:self.leftStickView point:p pressure:pressure outNormX:&nx outNormY:&ny outZone:&zone];
                rec.stickXY = CGPointMake(nx, ny);
                rec.stickZone = zone;
                self.leftStickView.active = YES;
                [self.leftStickView updateOffset:rec.stickXY pressure:pressure animated:NO];
                [self.haptics playStickEngage];
                break;
            }
            case TouchTargetKind::RightStick: {
                float nx = 0, ny = 0; int zone = 0;
                [self computeStickForView:self.rightStickView point:p pressure:pressure outNormX:&nx outNormY:&ny outZone:&zone];
                rec.stickXY = CGPointMake(nx, ny);
                rec.stickZone = zone;
                self.rightStickView.active = YES;
                [self.rightStickView updateOffset:rec.stickXY pressure:pressure animated:NO];
                [self.haptics playStickEngage];
                break;
            }
            case TouchTargetKind::DPad:
                rec.dpadMask = [self dpadMaskAtPoint:p];
                if (rec.dpadMask != 0) [self.haptics playDPadTick];
                break;
            case TouchTargetKind::ABXYCluster:
                rec.subButton = [self closestABXYButtonAtPoint:p];
                if (rec.subButton >= 0) [self.haptics playButtonDownIsTrigger:NO pressure:pressure];
                break;
            case TouchTargetKind::LT:
                rec.analogVal = [self computeTriggerAnalogForView:self.ltView point:p pressure:pressure];
                [self.haptics playButtonDownIsTrigger:YES pressure:rec.analogVal];
                break;
            case TouchTargetKind::RT:
                rec.analogVal = [self computeTriggerAnalogForView:self.rtView point:p pressure:pressure];
                [self.haptics playButtonDownIsTrigger:YES pressure:rec.analogVal];
                break;
            case TouchTargetKind::LB:
            case TouchTargetKind::RB:
            case TouchTargetKind::L3:
            case TouchTargetKind::R3:
                [self.haptics playButtonDownIsTrigger:YES pressure:pressure];
                break;
            case TouchTargetKind::Start:
            case TouchTargetKind::Back:
                [self.haptics playButtonDownIsTrigger:NO pressure:pressure];
                break;
            default:
                break;
        }
        _activeTouches[key] = rec;
    }
    [self syncVisualsAndPublishSnapshot];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (self.hiddenForPhysicalController || self.hiddenForInstaller) return;

    for (UITouch *touch in touches) {
        uintptr_t key = reinterpret_cast<uintptr_t>((__bridge const void *)touch);
        auto it = _activeTouches.find(key);
        if (it == _activeTouches.end()) continue;

        CGPoint p = [touch locationInView:self];
        float pressure = ComputeTouchPressure01(touch);
        ActiveTouchRecord &rec = it->second;

        switch (rec.kind) {
            case TouchTargetKind::LeftStick: {
                float nx = 0, ny = 0; int zone = 0;
                [self computeStickForView:self.leftStickView point:p pressure:pressure outNormX:&nx outNormY:&ny outZone:&zone];
                if (zone != rec.stickZone) {
                    if (zone == 2) [self.haptics playStickRimBump:pressure];
                    else if (zone == 1 && rec.stickZone == 0) [self.haptics playStickZoneTick:0.28f];
                    rec.stickZone = zone;
                }
                rec.stickXY = CGPointMake(nx, ny);
                rec.analogVal = pressure;
                [self.leftStickView updateOffset:rec.stickXY pressure:pressure animated:NO];
                break;
            }
            case TouchTargetKind::RightStick: {
                float nx = 0, ny = 0; int zone = 0;
                [self computeStickForView:self.rightStickView point:p pressure:pressure outNormX:&nx outNormY:&ny outZone:&zone];
                if (zone != rec.stickZone) {
                    if (zone == 2) [self.haptics playStickRimBump:pressure];
                    else if (zone == 1 && rec.stickZone == 0) [self.haptics playStickZoneTick:0.24f];
                    rec.stickZone = zone;
                }
                rec.stickXY = CGPointMake(nx, ny);
                rec.analogVal = pressure;
                [self.rightStickView updateOffset:rec.stickXY pressure:pressure animated:NO];
                break;
            }
            case TouchTargetKind::DPad: {
                uint16_t newMask = [self dpadMaskAtPoint:p];
                if (newMask != rec.dpadMask) {
                    rec.dpadMask = newMask;
                    if (newMask != 0) [self.haptics playDPadTick];
                }
                break;
            }
            case TouchTargetKind::ABXYCluster: {
                int nextBtn = [self closestABXYButtonAtPoint:p];
                if (nextBtn != rec.subButton) {
                    if (rec.subButton >= 0) [self.haptics playButtonUp];
                    if (nextBtn >= 0)       [self.haptics playButtonDownIsTrigger:NO pressure:pressure];
                    rec.subButton = nextBtn;
                }
                rec.analogVal = pressure;
                break;
            }
            case TouchTargetKind::LT: {
                float prev = rec.analogVal;
                rec.analogVal = [self computeTriggerAnalogForView:self.ltView point:p pressure:pressure];
                if (prev < 0.94f && rec.analogVal >= 0.94f) [self.haptics playStickZoneTick:0.35f];
                break;
            }
            case TouchTargetKind::RT: {
                float prev = rec.analogVal;
                rec.analogVal = [self computeTriggerAnalogForView:self.rtView point:p pressure:pressure];
                if (prev < 0.94f && rec.analogVal >= 0.94f) [self.haptics playStickZoneTick:0.35f];
                break;
            }
            default:
                rec.analogVal = pressure;
                break;
        }
    }
    [self syncVisualsAndPublishSnapshot];
}

- (void)finishTouches:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    for (UITouch *touch in touches) {
        uintptr_t key = reinterpret_cast<uintptr_t>((__bridge const void *)touch);
        auto it = _activeTouches.find(key);
        if (it == _activeTouches.end()) continue;

        TouchTargetKind kind = it->second.kind;
        _activeTouches.erase(it);

        if (kind == TouchTargetKind::LeftStick) {
            self.leftStickView.active = NO;
            [self.leftStickView updateOffset:CGPointZero pressure:0.0f animated:YES];
            if (!cancelled) [self.haptics playStickRelease];
        } else if (kind == TouchTargetKind::RightStick) {
            self.rightStickView.active = NO;
            [self.rightStickView updateOffset:CGPointZero pressure:0.0f animated:YES];
            if (!cancelled) [self.haptics playStickRelease];
        } else if (kind == TouchTargetKind::ChaosEmerald) {
            self.emeraldView.pressed = NO;
            if (!cancelled) {
                [self.haptics playButtonUp];
                [self toggleQuickBarOpen:!self.quickBarOpen];
            }
        } else if (!cancelled && kind != TouchTargetKind::DPad) {
            [self.haptics playButtonUp];
        }
    }
    [self syncVisualsAndPublishSnapshot];
    if (_activeTouches.empty()) {
        [self scheduleIdleFadeTimer];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self finishTouches:touches cancelled:NO];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    [self finishTouches:touches cancelled:YES];
}

- (void)clearAllInputs {
    _activeTouches.clear();
    self.leftStickView.active = NO;
    [self.leftStickView updateOffset:CGPointZero pressure:0.0f animated:NO];
    self.rightStickView.active = NO;
    [self.rightStickView updateOffset:CGPointZero pressure:0.0f animated:NO];
    self.emeraldView.pressed = NO;
    [self syncVisualsAndPublishSnapshot];
}

- (void)syncVisualsAndPublishSnapshot {
    IOSVirtualPadSnapshot snap{};
    bool aDown = false, bDown = false, xDown = false, yDown = false;
    bool ltDown = false, lbDown = false, l3Down = false;
    bool rtDown = false, rbDown = false, r3Down = false;
    bool startDown = false, backDown = false;
    float ltFill = 0.0f, rtFill = 0.0f;
    float aPress = 0.0f, bPress = 0.0f, xPress = 0.0f, yPress = 0.0f;
    uint16_t dpadMask = 0;

    for (const auto &kv : _activeTouches) {
        const ActiveTouchRecord &rec = kv.second;
        snap.anyActive = true;
        switch (rec.kind) {
            case TouchTargetKind::LeftStick:
                snap.sThumbLX = FloatToXboxAxis(static_cast<float>(rec.stickXY.x));
                // Su Xbox Original +Y è VERSO L'ALTO, in UIKit Y è verso il basso -> invertiamo il segno!
                snap.sThumbLY = FloatToXboxAxis(static_cast<float>(-rec.stickXY.y));
                break;
            case TouchTargetKind::RightStick:
                snap.sThumbRX = FloatToXboxAxis(static_cast<float>(rec.stickXY.x));
                snap.sThumbRY = FloatToXboxAxis(static_cast<float>(-rec.stickXY.y));
                break;
            case TouchTargetKind::DPad:
                dpadMask |= rec.dpadMask;
                break;
            case TouchTargetKind::ABXYCluster: {
                uint8_t val = static_cast<uint8_t>(std::lround(ClampF(215.0f + 40.0f * rec.analogVal, 215.0f, 255.0f)));
                if (rec.subButton == 0)      { aDown = true; aPress = rec.analogVal; snap.bAnalogButtons[kBtnA] = std::max(snap.bAnalogButtons[kBtnA], val); }
                else if (rec.subButton == 1) { bDown = true; bPress = rec.analogVal; snap.bAnalogButtons[kBtnB] = std::max(snap.bAnalogButtons[kBtnB], val); }
                else if (rec.subButton == 2) { xDown = true; xPress = rec.analogVal; snap.bAnalogButtons[kBtnX] = std::max(snap.bAnalogButtons[kBtnX], val); }
                else if (rec.subButton == 3) { yDown = true; yPress = rec.analogVal; snap.bAnalogButtons[kBtnY] = std::max(snap.bAnalogButtons[kBtnY], val); }
                break;
            }
            case TouchTargetKind::LT:
                ltDown = true;
                ltFill = std::max(ltFill, rec.analogVal);
                snap.bAnalogButtons[kBtnLT] = std::max(snap.bAnalogButtons[kBtnLT], static_cast<uint8_t>(std::lround(rec.analogVal * 255.0f)));
                break;
            case TouchTargetKind::RT:
                rtDown = true;
                rtFill = std::max(rtFill, rec.analogVal);
                snap.bAnalogButtons[kBtnRT] = std::max(snap.bAnalogButtons[kBtnRT], static_cast<uint8_t>(std::lround(rec.analogVal * 255.0f)));
                break;
            case TouchTargetKind::LB:
                lbDown = true;
                snap.bAnalogButtons[kBtnWhite] = 0xFF; // Xbox Original WHITE button
                break;
            case TouchTargetKind::RB:
                rbDown = true;
                snap.bAnalogButtons[kBtnBlack] = 0xFF; // Xbox Original BLACK button
                break;
            case TouchTargetKind::L3:
                l3Down = true;
                snap.wButtons |= kXboxLeftThumb;
                break;
            case TouchTargetKind::R3:
                r3Down = true;
                snap.wButtons |= kXboxRightThumb;
                break;
            case TouchTargetKind::Start:
                startDown = true;
                snap.wButtons |= kXboxStart;
                break;
            case TouchTargetKind::Back:
                backDown = true;
                snap.wButtons |= kXboxBack;
                break;
            default:
                break;
        }
    }
    snap.wButtons |= dpadMask;

    // Aggiorna UI visuale
    self.btnAView.pressure = aPress; self.btnAView.pressed = aDown;
    self.btnBView.pressure = bPress; self.btnBView.pressed = bDown;
    self.btnXView.pressure = xPress; self.btnXView.pressed = xDown;
    self.btnYView.pressure = yPress; self.btnYView.pressed = yDown;

    self.ltView.analogFill = ltFill; self.ltView.pressed = ltDown;
    self.rtView.analogFill = rtFill; self.rtView.pressed = rtDown;
    self.lbView.pressed = lbDown;
    self.rbView.pressed = rbDown;
    self.l3View.pressed = l3Down;
    self.r3View.pressed = r3Down;
    self.pauseView.pressed = startDown;
    self.backView.pressed = backDown;
    self.dpadView.activeMask = dpadMask;

    // Pubblica lo snapshot lock-free per il thread CPU Xbox (zero mutex, zero syscalls a 120Hz!)
    uint32_t nextSlot = (g_padActiveSlot.load(std::memory_order_relaxed) + 1u) & 3u;
    g_padSlots[nextSlot] = snap;
    g_padActiveSlot.store(nextSlot, std::memory_order_release);
}

@end

#pragma mark - Singleton Host Attachment & C Bridge

static ShadowTouchOverlayView *g_sharedOverlay = nil;

static UIView *FindActiveHostView(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (![ws.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (!keyWindow) keyWindow = ws.windows.firstObject;
        }
    }
    if (!keyWindow) return nil;
    // Aggancia alla rootViewController.view così i modal iOS (UIDocumentPicker / App File) restano sempre sopra!
    if (keyWindow.rootViewController && keyWindow.rootViewController.view) {
        return keyWindow.rootViewController.view;
    }
    return keyWindow;
}

static void EnsureOverlayAttachedOnMainThread(bool hasPhysical, bool installerVisible, int chaosAura) {
    if (g_sharedOverlay && g_sharedOverlay.tvGamepadMode) {
        // In Modalita TV l'overlay resta ancorato al container dedicato su iPhone (zero bottoni sulla TV)
        [g_sharedOverlay updateExternalPhysical:hasPhysical
                               installerVisible:installerVisible
                                      chaosAura:chaosAura];
        [g_sharedOverlay refreshExternalDisplayAvailabilitySilent:YES];
        return;
    }

    UIView *host = FindActiveHostView();
    if (!host) return;

    if (!g_sharedOverlay) {
        g_sharedOverlay = [[ShadowTouchOverlayView alloc] initWithFrame:host.bounds];
        [host addSubview:g_sharedOverlay];
        [host bringSubviewToFront:g_sharedOverlay];
        g_overlayAttached.store(true, std::memory_order_release);
    } else if (g_sharedOverlay.superview != host) {
        [g_sharedOverlay removeFromSuperview];
        g_sharedOverlay.frame = host.bounds;
        [host addSubview:g_sharedOverlay];
        [host bringSubviewToFront:g_sharedOverlay];
    } else if (host.subviews.lastObject != g_sharedOverlay) {
        // Garantisce che l'overlay resti sempre sopra alla vista Metal creata da SDL3/MoltenVK
        [host bringSubviewToFront:g_sharedOverlay];
    }

    [g_sharedOverlay updateExternalPhysical:hasPhysical
                           installerVisible:installerVisible
                                  chaosAura:chaosAura];
    [g_sharedOverlay refreshExternalDisplayAvailabilitySilent:YES];
}

extern "C" {

void IOSVirtualController_SyncState(bool hasPhysicalController, bool installerVisible, int chaosAuraMode) {
    static uint32_t s_frameCounter = 0;
    bool prevPhys = g_lastPhysicalSDL.exchange(hasPhysicalController, std::memory_order_relaxed);
    bool prevInst = g_lastInstallerVisible.exchange(installerVisible, std::memory_order_relaxed);
    int  prevAura = g_lastChaosAura.exchange(chaosAuraMode, std::memory_order_relaxed);

    bool needsAttach = !g_overlayAttached.load(std::memory_order_acquire);
    bool periodicZOrderCheck = ((++s_frameCounter % 180u) == 0u);
    if (!needsAttach && !periodicZOrderCheck && prevPhys == hasPhysicalController && prevInst == installerVisible && prevAura == chaosAuraMode) {
        return; // Fast-path O(1): zero allocazioni ObjC nei frame normali a 120Hz!
    }

    void (^syncBlock)(void) = ^{
        EnsureOverlayAttachedOnMainThread(hasPhysicalController, installerVisible, chaosAuraMode);
    };

    if ([NSThread isMainThread]) {
        syncBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), syncBlock);
    }
}

bool IOSVirtualController_GetState(IOSVirtualPadSnapshot* outSnapshot) {
    if (!outSnapshot) return false;
    uint32_t cur = g_padActiveSlot.load(std::memory_order_acquire);
    *outSnapshot = g_padSlots[cur];
    return true;
}

void IOSVirtualController_SetRumble(uint16_t leftMotor, uint16_t rightMotor) {
    if (leftMotor < 2000 && rightMotor < 2000) return;
    // Pre-throttle lock-free (45ms) PRIMA di dispatch_async per non intasare il main thread durante esplosioni/zone pesanti!
    static std::atomic<int64_t> s_lastRumbleMs{0};
    int64_t nowMs = static_cast<int64_t>(CACurrentMediaTime() * 1000.0);
    int64_t prevMs = s_lastRumbleMs.load(std::memory_order_relaxed);
    if ((nowMs - prevMs) < 45) return;
    if (!s_lastRumbleMs.compare_exchange_strong(prevMs, nowMs, std::memory_order_relaxed)) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_sharedOverlay && !g_sharedOverlay.hiddenForPhysicalController && !g_sharedOverlay.hiddenForInstaller) {
            [g_sharedOverlay.haptics playGameRumbleLeft:leftMotor right:rightMotor];
        }
    });
}

} // extern "C"
