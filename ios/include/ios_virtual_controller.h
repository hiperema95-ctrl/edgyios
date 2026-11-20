#pragma once

#include <cstdint>

struct IOSVirtualPadSnapshot {
    uint16_t wButtons;          // XINPUT_GAMEPAD_DPAD_* / START / BACK / LEFT_THUMB / RIGHT_THUMB
    uint8_t  bAnalogButtons[8]; // [0]=A, [1]=B, [2]=X, [3]=Y, [4]=Black(RB), [5]=White(LB), [6]=LT, [7]=RT
    int16_t  sThumbLX;          // -32768..32767
    int16_t  sThumbLY;          // -32768..32767 (+Y = UP su Xbox Original)
    int16_t  sThumbRX;          // -32768..32767
    int16_t  sThumbRY;          // -32768..32767 (+Y = UP su Xbox Original)
    bool     anyActive;         // true se almeno un controllo virtuale è attivo
};

extern "C" {
    // Sincronizza l'overlay UIKit dal main thread (chiamato in input::Update())
    void IOSVirtualController_SyncState(bool hasPhysicalController, bool installerVisible, int chaosAuraMode);
    // Legge lo stato Xbox Original thread-safe (chiamato da input::GetState() sul thread CPU)
    bool IOSVirtualController_GetState(IOSVirtualPadSnapshot* outSnapshot);
    // Inoltra la vibrazione Xbox Original (XboxVibrationPacket) al Taptic Engine (CoreHaptics)
    void IOSVirtualController_SetRumble(uint16_t leftMotor, uint16_t rightMotor);
}
