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
#import <CoreGraphics/CoreGraphics.h>
#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>

#include <ios_virtual_controller.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <unordered_map>

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

std::mutex g_padMutex;
IOSVirtualPadSnapshot g_padSnapshot{};
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
          initialVelocity:0.9
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
              initialVelocity:1.2
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
    QuickBar
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

// Quick HUD Bar (Opacità / Aptica / Auto-Hide 4s) aperta dal Chaos Emerald
@property (nonatomic, strong) UIView *quickBarView;
@property (nonatomic, strong) UILabel *quickOpacityLabel;
@property (nonatomic, strong) UILabel *quickHapticsLabel;
@property (nonatomic, strong) UILabel *quickAutoHideLabel;
@property (nonatomic, assign) BOOL quickBarOpen;

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
@end

@implementation ShadowTouchOverlayView {
    std::unordered_map<uintptr_t, ActiveTouchRecord> _activeTouches;
    CGRect _abxyClusterRect;
    CGRect _quickOpacityRect;
    CGRect _quickHapticsRect;
    CGRect _quickAutoHideRect;
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

        // Container animabile (il root view resta alpha=1.0 così hitTest intercetta sempre il risveglio!)
        _controlsContainer = [[UIView alloc] initWithFrame:self.bounds];
        _controlsContainer.backgroundColor = [UIColor clearColor];
        _controlsContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _controlsContainer.userInteractionEnabled = NO;
        _controlsContainer.alpha = _preferredOpacity;
        [self addSubview:_controlsContainer];

        [self buildControls];
        [self buildQuickBar];
        [self registerNotifications];
        [self refreshPhysicalControllerState];
        [self scheduleIdleFadeTimer];
    }
    return self;
}

- (void)dealloc {
    [_idleFadeTimer invalidate];
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
        l.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        l.layer.cornerRadius = 10.0;
        l.layer.masksToBounds = YES;
        return l;
    };

    _quickOpacityLabel = makePill();
    _quickHapticsLabel = makePill();
    _quickAutoHideLabel = makePill();
    [_quickBarView addSubview:_quickOpacityLabel];
    [_quickBarView addSubview:_quickHapticsLabel];
    [_quickBarView addSubview:_quickAutoHideLabel];
    [_controlsContainer addSubview:_quickBarView];
    [self refreshQuickBarLabels];
}

- (void)refreshQuickBarLabels {
    int pct = static_cast<int>(std::lround(self.preferredOpacity * 100.0));
    self.quickOpacityLabel.text = [NSString stringWithFormat:@"Opacità %d%%", pct];
    self.quickHapticsLabel.text = self.haptics.enabled ? @"Aptica ON" : @"Aptica OFF";
    self.quickAutoHideLabel.text = self.autoHideEnabled ? @"Fade 4s" : @"Fisso";
}

- (void)registerNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onControllerConnectionChanged:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onControllerConnectionChanged:) name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(onAppWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onAppDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
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

- (void)onAppDidBecomeActive:(NSNotification *)note {
    (void)note;
    [self.haptics ensureStarted];
    [self refreshPhysicalControllerState];
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
    CGFloat targetAlpha = shouldHideCompletely ? 0.0 : (self.isIdleFaded ? 0.0 : self.preferredOpacity);
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

    if (!self.autoHideEnabled || self.hiddenForPhysicalController || self.hiddenForInstaller || self.quickBarOpen) {
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
        if (!strongSelf->_activeTouches.empty() || !strongSelf.autoHideEnabled || strongSelf.quickBarOpen) return;
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

    BOOL wasFaded = self.isIdleFaded || (self.controlsContainer.alpha < self.preferredOpacity - 0.03);
    self.isIdleFaded = NO;

    if (wasFaded) {
        [UIView animateWithDuration:animated ? 0.20 : 0.0
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut
                         animations:^{
            self.controlsContainer.alpha = self.preferredOpacity;
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

    // 3. Mid-Left: L-Analog Stick (Shadow Emblem + anello uncinato)
    CGFloat lStickSize = 114.0 * s;
    CGFloat lStickX = leftPad + 14.0 * s;
    CGFloat lStickY = CGRectGetMaxY(self.lbView.frame) + 14.0 * s;
    self.leftStickView.frame = CGRectMake(lStickX, lStickY, lStickSize, lStickSize);

    // 4. Bottom-Left: D-Pad 8-direzioni
    CGFloat dpadSize = 112.0 * s;
    CGFloat dpadX = leftPad + 16.0 * s;
    CGFloat dpadY = H - bottomPad - dpadSize;
    // Evita sovrapposizione su schermi più bassi
    if (dpadY < CGRectGetMaxY(self.leftStickView.frame) + 6.0 * s) {
        CGFloat overlap = (CGRectGetMaxY(self.leftStickView.frame) + 6.0 * s) - dpadY;
        self.leftStickView.frame = CGRectOffset(self.leftStickView.frame, 0, -overlap * 0.55);
        dpadY += overlap * 0.15;
    }
    self.dpadView.frame = CGRectMake(dpadX, dpadY, dpadSize, dpadSize);

    // 5. Mid-Right: Diamante Action Buttons (Y, X, B, A)
    CGFloat btnSize = 52.0 * s;
    CGFloat diamondSpread = 45.0 * s;
    CGFloat abxyCenterX = W - rightPad - 76.0 * s;
    CGFloat abxyCenterY = CGRectGetMaxY(self.rbView.frame) + 74.0 * s;

    self.btnYView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY - diamondSpread - btnSize * 0.5, btnSize, btnSize);
    self.btnAView.frame = CGRectMake(abxyCenterX - btnSize * 0.5, abxyCenterY + diamondSpread - btnSize * 0.5, btnSize, btnSize);
    self.btnXView.frame = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
    self.btnBView.frame = CGRectMake(abxyCenterX + diamondSpread - btnSize * 0.5, abxyCenterY - btnSize * 0.5, btnSize, btnSize);
    _abxyClusterRect = CGRectMake(abxyCenterX - diamondSpread - btnSize * 0.65,
                                  abxyCenterY - diamondSpread - btnSize * 0.65,
                                  (diamondSpread + btnSize * 0.65) * 2.0,
                                  (diamondSpread + btnSize * 0.65) * 2.0);

    // 6. Bottom-Right: R-Analog Camera Stick
    CGFloat rStickSize = 86.0 * s;
    CGFloat rStickX = abxyCenterX - rStickSize * 0.5 - 26.0 * s;
    CGFloat rStickY = H - bottomPad - rStickSize - 2.0 * s;
    if (rStickY < CGRectGetMaxY(self.btnAView.frame) + 6.0 * s) {
        rStickX = abxyCenterX - diamondSpread - rStickSize - 6.0 * s;
    }
    self.rightStickView.frame = CGRectMake(rStickX, rStickY, rStickSize, rStickSize);

    // 7. Bottom-Center: Navigazione (Pausa, Chaos Emerald, Indietro)
    CGFloat navSize = 40.0 * s;
    CGFloat navGap  = 16.0 * s;
    CGFloat navY    = H - bottomPad - navSize - 2.0 * s;
    CGFloat midX    = W * 0.5;

    self.emeraldView.frame = CGRectMake(midX - navSize * 0.5, navY, navSize, navSize);
    self.pauseView.frame   = CGRectMake(midX - navSize * 1.5 - navGap, navY, navSize, navSize);
    self.backView.frame    = CGRectMake(midX + navSize * 0.5 + navGap, navY, navSize, navSize);

    // 8. Quick-HUD Bar sopra al Chaos Emerald
    CGFloat qbW = 286.0 * s;
    CGFloat qbH = 38.0 * s;
    self.quickBarView.frame = CGRectMake(midX - qbW * 0.5, navY - qbH - 10.0 * s, qbW, qbH);
    CGFloat pad = 5.0 * s;
    CGFloat itemW = (qbW - pad * 4.0) / 3.0;
    CGFloat itemH = qbH - pad * 2.0;
    self.quickOpacityLabel.frame  = CGRectMake(pad, pad, itemW, itemH);
    self.quickHapticsLabel.frame  = CGRectMake(pad * 2.0 + itemW, pad, itemW, itemH);
    self.quickAutoHideLabel.frame = CGRectMake(pad * 3.0 + itemW * 2.0, pad, itemW, itemH);

    _quickOpacityRect  = [self convertRect:self.quickOpacityLabel.frame fromView:self.quickBarView];
    _quickHapticsRect  = [self convertRect:self.quickHapticsLabel.frame fromView:self.quickBarView];
    _quickAutoHideRect = [self convertRect:self.quickAutoHideLabel.frame fromView:self.quickBarView];
}

#pragma mark - Hit Testing & Passthrough

- (TouchTargetKind)targetKindAtPoint:(CGPoint)p {
    if (self.quickBarOpen && CGRectContainsPoint(CGRectInset(self.quickBarView.frame, -6, -6), p)) {
        return TouchTargetKind::QuickBar;
    }
    if (CGRectContainsPoint(CGRectInset(self.leftStickView.frame, -16, -16), p))  return TouchTargetKind::LeftStick;
    if (CGRectContainsPoint(CGRectInset(self.rightStickView.frame, -14, -14), p)) return TouchTargetKind::RightStick;
    if (CGRectContainsPoint(CGRectInset(self.dpadView.frame, -10, -10), p))       return TouchTargetKind::DPad;
    if (CGRectContainsPoint(_abxyClusterRect, p))                                 return TouchTargetKind::ABXYCluster;
    if (CGRectContainsPoint(CGRectInset(self.ltView.frame, -6, -6), p))           return TouchTargetKind::LT;
    if (CGRectContainsPoint(CGRectInset(self.lbView.frame, -6, -6), p))           return TouchTargetKind::LB;
    if (CGRectContainsPoint(CGRectInset(self.l3View.frame, -5, -5), p))           return TouchTargetKind::L3;
    if (CGRectContainsPoint(CGRectInset(self.r3View.frame, -5, -5), p))           return TouchTargetKind::R3;
    if (CGRectContainsPoint(CGRectInset(self.rtView.frame, -6, -6), p))           return TouchTargetKind::RT;
    if (CGRectContainsPoint(CGRectInset(self.rbView.frame, -6, -6), p))           return TouchTargetKind::RB;
    if (CGRectContainsPoint(CGRectInset(self.pauseView.frame, -8, -8), p))        return TouchTargetKind::Start;
    if (CGRectContainsPoint(CGRectInset(self.emeraldView.frame, -8, -8), p))      return TouchTargetKind::ChaosEmerald;
    if (CGRectContainsPoint(CGRectInset(self.backView.frame, -8, -8), p))         return TouchTargetKind::Back;
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
    // Tocchi fuori dai comandi: chiudi eventuale Quick-Bar e lascia passare il tocco a SDL3/ImGui
    if (self.quickBarOpen) {
        [self toggleQuickBarOpen:NO];
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
        [self refreshQuickBarLabels];
        self.quickBarView.hidden = NO;
        [self.idleFadeTimer invalidate];
        self.idleFadeTimer = nil;
    }
    [UIView animateWithDuration:0.18 animations:^{
        self.quickBarView.alpha = open ? 1.0 : 0.0;
        self.quickBarView.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.92, 0.92);
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

    // Pubblica lo snapshot atomico per il thread CPU Xbox (input::GetState)
    std::lock_guard<std::mutex> lock(g_padMutex);
    g_padSnapshot = snap;
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
}

extern "C" {

void IOSVirtualController_SyncState(bool hasPhysicalController, bool installerVisible, int chaosAuraMode) {
    static uint32_t s_frameCounter = 0;
    bool prevPhys = g_lastPhysicalSDL.exchange(hasPhysicalController, std::memory_order_relaxed);
    bool prevInst = g_lastInstallerVisible.exchange(installerVisible, std::memory_order_relaxed);
    int  prevAura = g_lastChaosAura.exchange(chaosAuraMode, std::memory_order_relaxed);

    bool needsAttach = !g_overlayAttached.load(std::memory_order_acquire);
    bool periodicZOrderCheck = ((++s_frameCounter % 60u) == 0u);
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
    std::lock_guard<std::mutex> lock(g_padMutex);
    *outSnapshot = g_padSnapshot;
    return true;
}

void IOSVirtualController_SetRumble(uint16_t leftMotor, uint16_t rightMotor) {
    if (leftMotor < 2000 && rightMotor < 2000) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_sharedOverlay && !g_sharedOverlay.hiddenForPhysicalController && !g_sharedOverlay.hiddenForInstaller) {
            [g_sharedOverlay.haptics playGameRumbleLeft:leftMotor right:rightMotor];
        }
    });
}

} // extern "C"
