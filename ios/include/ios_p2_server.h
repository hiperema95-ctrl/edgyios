#pragma once

#include <cstddef>
#include <cstdint>
#include <ios_virtual_controller.h>

extern "C" {
    typedef void (*IOSRemoteP2StateCallback)(bool serverRunning, bool p2Connected, const char* url);

    // Avvia il mini server locale HTTP + WebSocket (porta default 8765) su Hotspot / Wi-Fi
    bool IOSRemoteP2_StartServer(uint16_t preferredPort);
    // Ferma il server locale e azzera lo stato del Giocatore 2
    void IOSRemoteP2_StopServer(void);
    // Stato attuale del server e della connessione di Smartphone 2
    bool IOSRemoteP2_IsServerRunning(void);
    bool IOSRemoteP2_IsConnected(void);
    // Restituisce il link locale (es. http://172.20.10.1:8765) aggiornato dall'interfaccia Hotspot/Wi-Fi
    void IOSRemoteP2_GetURL(char* outBuf, size_t bufLen);
    // Legge lo stato Xbox Original del Giocatore 2 thread-safe (chiamato da input::GetState per dwUserIndex == 2)
    bool IOSRemoteP2_GetState(IOSVirtualPadSnapshot* outSnapshot);
    // Inoltra la vibrazione Xbox Original del Giocatore 2 a Smartphone 2 via WebSocket
    void IOSRemoteP2_SetRumble(uint16_t leftMotor, uint16_t rightMotor);
    // Registra callback UIKit (eseguita sempre sul main thread) per aggiornare Pairing <-> Connected
    void IOSRemoteP2_SetStateCallback(IOSRemoteP2StateCallback cb);
}
