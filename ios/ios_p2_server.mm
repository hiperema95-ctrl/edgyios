// ios/ios_p2_server.mm
// Mini server locale HTTP/1.1 + WebSocket (RFC 6455) integrato in ShadowRecomp iOS
// per collegare un secondo smartphone (iPhone o Android) via Hotspot Personale o Wi-Fi come Controller Giocatore 2.

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <ios_p2_server.h>

#include <arpa/inet.h>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ifaddrs.h>
#include <mutex>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {

static const char* const kP2ControllerHtml = R"SHADOW_P2_HTML(<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="theme-color" content="#08080b">
<title>ShadowRecomp — Controller 2P</title>
<style>
  :root {
    --bg: #08080c;
    --panel: rgba(20, 20, 28, 0.92);
    --crimson: #ef233c;
    --crimson-dim: rgba(239, 35, 60, 0.55);
    --crimson-glow: rgba(239, 35, 60, 0.85);
    --text: rgba(255, 255, 255, 0.92);
    --muted: rgba(255, 255, 255, 0.52);
  }
  * {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    user-select: none;
    -webkit-user-select: none;
    -webkit-touch-callout: none;
    -webkit-tap-highlight-color: transparent;
  }
  html, body {
    width: 100%;
    height: 100%;
    height: 100dvh;
    overflow: hidden;
    touch-action: none;
    background: radial-gradient(circle at 50% 45%, #17121a 0%, #09090e 65%, #050507 100%);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  #pad {
    position: fixed;
    inset: 0;
    padding: max(8px, env(safe-area-inset-top)) max(12px, env(safe-area-inset-right)) max(8px, env(safe-area-inset-bottom)) max(12px, env(safe-area-inset-left));
    display: block;
    overflow: hidden;
  }
  #pad.rumble {
    box-shadow: inset 0 0 36px rgba(239, 35, 60, 0.65);
  }

  /* Top status strip (compact, centered, zero clutter) */
  #hud {
    position: absolute;
    top: max(8px, env(safe-area-inset-top));
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    z-index: 20;
    pointer-events: auto;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    border-radius: 999px;
    background: rgba(14, 14, 20, 0.88);
    border: 1.5px solid rgba(239, 35, 60, 0.55);
    font-size: 12px;
    font-weight: 800;
    letter-spacing: 0.4px;
    color: #fff;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.5);
  }
  .pill.ok {
    border-color: rgba(46, 224, 126, 0.85);
    background: rgba(12, 34, 22, 0.9);
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #f59e0b;
    box-shadow: 0 0 8px #f59e0b;
  }
  .pill.ok .dot {
    background: #2ee07e;
    box-shadow: 0 0 8px #2ee07e;
  }
  #fsBtn {
    cursor: pointer;
    border: 1.5px solid rgba(255, 255, 255, 0.25);
    background: rgba(22, 22, 30, 0.88);
    color: rgba(255, 255, 255, 0.85);
    border-radius: 999px;
    padding: 5px 10px;
    font-size: 11px;
    font-weight: 700;
  }

  /* Shared button styles matching ShadowRecomp native iOS controller */
  .ctrl {
    position: absolute;
    display: flex;
    align-items: center;
    justify-content: center;
    touch-action: none;
    transition: transform 45ms ease-out, box-shadow 50ms ease-out, border-color 50ms ease-out;
  }

  /* Oversized Top Shoulders (LT / LB-W / L3 and RT / RB-B / R3) */
  .shoulder {
    background: linear-gradient(180deg, rgba(36, 36, 46, 0.92), rgba(14, 14, 20, 0.94));
    border: 2px solid var(--crimson-dim);
    border-radius: 14px;
    font-weight: 900;
    letter-spacing: 0.8px;
    color: var(--text);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.14), 0 4px 14px rgba(0, 0, 0, 0.55);
  }
  .shoulder.active {
    transform: scale(0.95);
    border-color: var(--crimson);
    background: linear-gradient(180deg, rgba(160, 22, 40, 0.85), rgba(54, 10, 18, 0.95));
    box-shadow: 0 0 18px var(--crimson-glow), inset 0 1px 0 rgba(255, 255, 255, 0.28);
  }
  .shoulder .sub {
    font-size: 0.68em;
    color: #ef233c;
    margin-left: 5px;
    font-weight: 900;
  }

  #btn-lt { top: max(8px, env(safe-area-inset-top)); left: max(12px, env(safe-area-inset-left)); width: 15vw; min-width: 96px; max-width: 150px; height: 11.5vh; min-height: 40px; font-size: clamp(14px, 3.6vh, 20px); border-radius: 16px 26px 12px 12px; }
  #btn-lb { top: calc(max(8px, env(safe-area-inset-top)) + max(40px, 11.5vh) + 6px); left: max(12px, env(safe-area-inset-left)); width: 15vw; min-width: 96px; max-width: 150px; height: 10vh; min-height: 36px; font-size: clamp(13px, 3.2vh, 18px); }
  #btn-l3 { top: max(8px, env(safe-area-inset-top)); left: calc(max(12px, env(safe-area-inset-left)) + clamp(96px, 15vw, 150px) + 8px); width: 9.5vw; min-width: 64px; max-width: 96px; height: 13vh; min-height: 46px; font-size: clamp(13px, 3.4vh, 18px); border-radius: 12px 12px 24px 12px; }

  #btn-rt { top: max(8px, env(safe-area-inset-top)); right: max(12px, env(safe-area-inset-right)); width: 15vw; min-width: 96px; max-width: 150px; height: 11.5vh; min-height: 40px; font-size: clamp(14px, 3.6vh, 20px); border-radius: 26px 16px 12px 12px; }
  #btn-rb { top: calc(max(8px, env(safe-area-inset-top)) + max(40px, 11.5vh) + 6px); right: max(12px, env(safe-area-inset-right)); width: 15vw; min-width: 96px; max-width: 150px; height: 10vh; min-height: 36px; font-size: clamp(13px, 3.2vh, 18px); }
  #btn-r3 { top: max(8px, env(safe-area-inset-top)); right: calc(max(12px, env(safe-area-inset-right)) + clamp(96px, 15vw, 150px) + 8px); width: 9.5vw; min-width: 64px; max-width: 96px; height: 13vh; min-height: 46px; font-size: clamp(13px, 3.4vh, 18px); border-radius: 12px 12px 12px 24px; }

  /* HUGE Blind-Playable Shadow L-Analog Stick (Left Center) */
  #stick-l {
    left: max(16px, env(safe-area-inset-left));
    top: 56%;
    transform: translateY(-50%);
    width: clamp(140px, 42vh, 215px);
    height: clamp(140px, 42vh, 215px);
    border-radius: 50%;
    background: radial-gradient(circle, rgba(28, 28, 38, 0.72) 0%, rgba(10, 10, 15, 0.94) 76%);
    border: 2.5px solid rgba(239, 35, 60, 0.45);
    box-shadow: inset 0 0 28px rgba(0, 0, 0, 0.85), 0 0 20px rgba(239, 35, 60, 0.16);
  }
  #stick-l.active {
    border-color: var(--crimson);
    box-shadow: inset 0 0 28px rgba(0, 0, 0, 0.85), 0 0 28px rgba(239, 35, 60, 0.55);
  }
  #stick-l-knob {
    width: 56%;
    height: 56%;
    border-radius: 50%;
    pointer-events: none;
    display: flex;
    align-items: center;
    justify-content: center;
    will-change: transform;
    filter: drop-shadow(0 6px 12px rgba(0, 0, 0, 0.8));
  }

  /* Large 8-Way D-Pad (Bottom Left Inner) */
  #dpad {
    left: calc(max(16px, env(safe-area-inset-left)) + clamp(130px, 38vh, 195px));
    bottom: max(12px, env(safe-area-inset-bottom));
    width: clamp(104px, 30vh, 146px);
    height: clamp(104px, 30vh, 146px);
    border-radius: 50%;
    background: radial-gradient(circle, rgba(22, 22, 30, 0.86), rgba(10, 10, 14, 0.94));
    border: 2px solid rgba(239, 35, 60, 0.42);
    box-shadow: inset 0 0 18px rgba(0, 0, 0, 0.75);
  }
  .dpad-arm {
    position: absolute;
    display: flex;
    align-items: center;
    justify-content: center;
    color: rgba(239, 35, 60, 0.8);
    font-weight: 900;
    font-size: clamp(14px, 4vh, 22px);
    pointer-events: none;
    border-radius: 8px;
    background: rgba(28, 28, 38, 0.8);
    border: 1.5px solid rgba(239, 35, 60, 0.45);
  }
  .dpad-arm.active {
    background: rgba(239, 35, 60, 0.85);
    color: #fff;
    box-shadow: 0 0 14px var(--crimson-glow);
  }
  #dp-u { top: 6%; left: 33%; width: 34%; height: 34%; }
  #dp-d { bottom: 6%; left: 33%; width: 34%; height: 34%; }
  #dp-l { left: 6%; top: 33%; width: 34%; height: 34%; }
  #dp-r { right: 6%; top: 33%; width: 34%; height: 34%; }

  /* HUGE Blind-Playable ABXY Diamond (Right Center) */
  #abxy-zone {
    position: absolute;
    right: max(14px, env(safe-area-inset-right));
    top: 56%;
    transform: translateY(-50%);
    width: clamp(168px, 48vh, 240px);
    height: clamp(168px, 48vh, 240px);
    pointer-events: none;
  }
  .face {
    pointer-events: auto;
    width: 39%;
    height: 39%;
    border-radius: 50%;
    font-size: clamp(22px, 6.2vh, 34px);
    font-weight: 900;
    background: radial-gradient(circle at 35% 30%, rgba(44, 44, 56, 0.96), rgba(12, 12, 18, 0.98) 78%);
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.7), inset 0 2px 3px rgba(255, 255, 255, 0.16);
  }
  .face.active {
    transform: scale(0.91);
  }
  #btn-y { top: 0; left: 30.5%; border: 3px solid rgba(250, 204, 21, 0.78); color: #facc15; }
  #btn-y.active { background: radial-gradient(circle, rgba(250, 204, 21, 0.45), rgba(80, 56, 8, 0.95)); box-shadow: 0 0 24px rgba(250, 204, 21, 0.9); color: #fff; }
  #btn-a { bottom: 0; left: 30.5%; border: 3px solid rgba(34, 197, 94, 0.78); color: #22c55e; }
  #btn-a.active { background: radial-gradient(circle, rgba(34, 197, 94, 0.45), rgba(10, 68, 30, 0.95)); box-shadow: 0 0 24px rgba(34, 197, 94, 0.9); color: #fff; }
  #btn-x { left: 0; top: 30.5%; border: 3px solid rgba(59, 130, 246, 0.78); color: #3b82f6; }
  #btn-x.active { background: radial-gradient(circle, rgba(59, 130, 246, 0.45), rgba(16, 40, 96, 0.95)); box-shadow: 0 0 24px rgba(59, 130, 246, 0.9); color: #fff; }
  #btn-b { right: 0; top: 30.5%; border: 3px solid rgba(239, 35, 60, 0.85); color: #ef233c; }
  #btn-b.active { background: radial-gradient(circle, rgba(239, 35, 60, 0.55), rgba(92, 10, 22, 0.95)); box-shadow: 0 0 24px rgba(239, 35, 60, 0.95); color: #fff; }

  /* Large R-Analog Camera Stick (Bottom Right Inner) */
  #stick-r {
    right: calc(max(14px, env(safe-area-inset-right)) + clamp(150px, 44vh, 218px));
    bottom: max(12px, env(safe-area-inset-bottom));
    width: clamp(98px, 28vh, 140px);
    height: clamp(98px, 28vh, 140px);
    border-radius: 50%;
    background: radial-gradient(circle, rgba(28, 28, 38, 0.78) 0%, rgba(10, 10, 15, 0.95) 78%);
    border: 2px solid rgba(239, 35, 60, 0.42);
    box-shadow: inset 0 0 20px rgba(0, 0, 0, 0.85);
  }
  #stick-r.active {
    border-color: var(--crimson);
    box-shadow: 0 0 20px rgba(239, 35, 60, 0.5);
  }
  #stick-r-knob {
    width: 52%;
    height: 52%;
    border-radius: 50%;
    pointer-events: none;
    background: radial-gradient(circle at 35% 30%, #4b4b5c, #14141c 74%);
    border: 2.5px solid rgba(239, 35, 60, 0.78);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.8);
    will-change: transform;
  }

  /* Bottom Center: START & BACK */
  #nav-center {
    position: absolute;
    bottom: max(12px, env(safe-area-inset-bottom));
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 14px;
    align-items: center;
  }
  .mini-round {
    position: relative;
    width: clamp(46px, 13vh, 62px);
    height: clamp(46px, 13vh, 62px);
    border-radius: 50%;
    background: radial-gradient(circle at 35% 30%, rgba(36, 36, 48, 0.94), rgba(12, 12, 18, 0.96));
    border: 2px solid var(--crimson-dim);
    color: var(--crimson);
    font-size: clamp(11px, 2.8vh, 14px);
    font-weight: 900;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.6);
  }
  .mini-round.active {
    transform: scale(0.92);
    background: rgba(239, 35, 60, 0.85);
    color: #fff;
    border-color: #fff;
    box-shadow: 0 0 18px var(--crimson-glow);
  }

  /* Portrait orientation prompt */
  #rotate-hint {
    position: fixed;
    inset: 0;
    z-index: 100;
    background: rgba(8, 8, 12, 0.96);
    display: none;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 24px;
    gap: 12px;
  }
  #rotate-hint h2 { font-size: 20px; color: #ef233c; }
  #rotate-hint p { font-size: 14px; color: rgba(255,255,255,0.75); max-width: 300px; line-height: 1.45; }
  @media (orientation: portrait) {
    #rotate-hint { display: flex; }
  }
</style>
</head>
<body>
<div id="pad">
  <div id="hud">
    <div id="statusPill" class="pill"><span class="dot"></span><span id="statusText">P2 Connessione...</span></div>
    <button id="fsBtn" type="button">Schermo Intero</button>
  </div>

  <!-- Top Shoulders -->
  <div id="btn-lt" class="ctrl shoulder" data-analog="lt">LT</div>
  <div id="btn-lb" class="ctrl shoulder" data-analog="wh">LB<span class="sub">W</span></div>
  <div id="btn-l3" class="ctrl shoulder" data-bit="64">L3</div>

  <div id="btn-rt" class="ctrl shoulder" data-analog="rt">RT</div>
  <div id="btn-rb" class="ctrl shoulder" data-analog="bl"><span class="sub" style="margin-left:0;margin-right:5px">B</span>RB</div>
  <div id="btn-r3" class="ctrl shoulder" data-bit="128">R3</div>

  <!-- Huge Shadow Emblem L-Analog Stick -->
  <div id="stick-l" class="ctrl">
    <div id="stick-l-knob">
      <svg viewBox="0 0 120 120" width="100%" height="100%" aria-hidden="true">
        <defs>
          <radialGradient id="sCap" cx="35%" cy="30%" r="70%">
            <stop offset="0%" stop-color="#3a1620"/>
            <stop offset="68%" stop-color="#14141d"/>
            <stop offset="100%" stop-color="#09090d"/>
          </radialGradient>
        </defs>
        <polygon fill="#ef233c" fill-opacity="0.92" points="60,2 69,16 86,8 88,24 106,24 100,40 116,49 104,61 116,74 100,82 104,98 86,98 84,114 68,105 60,118 52,105 36,114 34,98 16,98 20,82 4,74 16,61 4,49 20,40 14,24 32,24 34,8 51,16"/>
        <circle cx="60" cy="60" r="44" fill="url(#sCap)" stroke="#ef233c" stroke-width="3"/>
        <path d="M36,78 C36,56 49,38 78,34 C65,44 62,50 84,50 C70,58 66,64 82,70 C65,75 56,74 52,85 C44,85 38,83 36,78 Z" fill="#ef233c"/>
        <circle cx="52" cy="59" r="5" fill="#09090d"/>
      </svg>
    </div>
  </div>

  <!-- 8-Way D-Pad -->
  <div id="dpad" class="ctrl">
    <div id="dp-u" class="dpad-arm"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M12 6L19 16H5Z" fill="currentColor"/></svg></div>
    <div id="dp-d" class="dpad-arm"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M12 18L5 8H19Z" fill="currentColor"/></svg></div>
    <div id="dp-l" class="dpad-arm"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M6 12L16 5V19Z" fill="currentColor"/></svg></div>
    <div id="dp-r" class="dpad-arm"><svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M18 12L8 19V5Z" fill="currentColor"/></svg></div>
  </div>

  <!-- Huge ABXY Face Diamond -->
  <div id="abxy-zone">
    <div id="btn-y" class="ctrl face" data-analog="y">Y</div>
    <div id="btn-x" class="ctrl face" data-analog="x">X</div>
    <div id="btn-b" class="ctrl face" data-analog="b">B</div>
    <div id="btn-a" class="ctrl face" data-analog="a">A</div>
  </div>

  <!-- R-Analog Camera Stick -->
  <div id="stick-r" class="ctrl">
    <div id="stick-r-knob"></div>
  </div>

  <!-- Center Start / Back -->
  <div id="nav-center">
    <div id="btn-start" class="ctrl mini-round" data-bit="16" aria-label="Start"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><rect x="6.5" y="5" width="3.8" height="14" rx="1.6" fill="currentColor"/><rect x="13.7" y="5" width="3.8" height="14" rx="1.6" fill="currentColor"/></svg></div>
    <div id="btn-back" class="ctrl mini-round" data-bit="32" aria-label="Back"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 10H15.5A4.5 4.5 0 0 1 15.5 19H10"/><path d="M12.5 6.5L8.5 10L12.5 13.5"/></svg></div>
  </div>
</div>

<div id="rotate-hint">
  <h2>Ruota lo smartphone in orizzontale</h2>
  <p>Il Controller Giocatore 2 di ShadowRecomp usa tutto lo schermo in orizzontale con tasti grandi per giocare guardando la TV o lo Smartphone 1.</p>
</div>

<script>
(() => {
  'use strict';

  const state = {
    wButtons: 0,
    a: 0, b: 0, x: 0, y: 0, bl: 0, wh: 0, lt: 0, rt: 0,
    lx: 0, ly: 0, rx: 0, ry: 0
  };

  let ws = null;
  let connected = false;
  let dirty = true;
  let lastSentAt = 0;

  const padEl = document.getElementById('pad');
  const statusPill = document.getElementById('statusPill');
  const statusText = document.getElementById('statusText');
  const fsBtn = document.getElementById('fsBtn');

  function vib(ms) {
    if (navigator.vibrate) {
      try { navigator.vibrate(ms); } catch (_) {}
    }
  }

  function setStatus(ok, label) {
    connected = ok;
    statusPill.classList.toggle('ok', ok);
    statusText.textContent = label;
  }

  function serializeState() {
    return 'S,' + state.wButtons + ',' +
      state.a + ',' + state.b + ',' + state.x + ',' + state.y + ',' +
      state.bl + ',' + state.wh + ',' + state.lt + ',' + state.rt + ',' +
      state.lx + ',' + state.ly + ',' + state.rx + ',' + state.ry;
  }

  function sendNow(force) {
    if (!ws || ws.readyState !== 1) return;
    const now = performance.now();
    if (!force && !dirty && (now - lastSentAt) < 1000) return;
    try {
      ws.send(serializeState());
      dirty = false;
      lastSentAt = now;
    } catch (_) {}
  }

  function connectWS() {
    const proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
    const url = proto + location.host + '/ws';
    setStatus(false, 'P2 Connessione...');
    try {
      ws = new WebSocket(url);
    } catch (_) {
      setTimeout(connectWS, 700);
      return;
    }
    ws.onopen = () => {
      setStatus(true, 'P2 Connected');
      dirty = true;
      sendNow(true);
    };
    ws.onmessage = (ev) => {
      if (typeof ev.data === 'string' && ev.data.startsWith('R,')) {
        const parts = ev.data.split(',');
        const l = parseInt(parts[1] || '0', 10);
        const r = parseInt(parts[2] || '0', 10);
        const strength = Math.max(l, r);
        if (strength > 6000) {
          vib(Math.min(80, Math.max(15, Math.round(strength / 900))));
          padEl.classList.add('rumble');
          clearTimeout(padEl._rt);
          padEl._rt = setTimeout(() => padEl.classList.remove('rumble'), 90);
        }
      }
    };
    ws.onclose = () => {
      setStatus(false, 'Riconnessione...');
      setTimeout(connectWS, 550);
    };
    ws.onerror = () => {
      try { ws.close(); } catch (_) {}
    };
  }

  // 60Hz tick for smooth low-latency streaming + 1Hz heartbeat
  setInterval(() => sendNow(false), 16);

  // Fullscreen & Wake Lock
  fsBtn.addEventListener('click', () => {
    const docEl = document.documentElement;
    if (!document.fullscreenElement && docEl.requestFullscreen) {
      docEl.requestFullscreen().catch(() => {});
    } else if (document.exitFullscreen) {
      document.exitFullscreen().catch(() => {});
    }
    if (navigator.wakeLock && navigator.wakeLock.request) {
      navigator.wakeLock.request('screen').catch(() => {});
    }
  });

  // Multi-touch tracking map: touchId -> { type, el, bit, analog }
  const active = new Map();

  const stickL = document.getElementById('stick-l');
  const stickLKnob = document.getElementById('stick-l-knob');
  const stickR = document.getElementById('stick-r');
  const stickRKnob = document.getElementById('stick-r-knob');
  const dpadEl = document.getElementById('dpad');
  const dpU = document.getElementById('dp-u');
  const dpD = document.getElementById('dp-d');
  const dpL = document.getElementById('dp-l');
  const dpR = document.getElementById('dp-r');

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  function updateStick(which, clientX, clientY) {
    const box = (which === 'L' ? stickL : stickR).getBoundingClientRect();
    const cx = box.left + box.width * 0.5;
    const cy = box.top + box.height * 0.5;
    const maxR = box.width * 0.36;
    let dx = clientX - cx;
    let dy = clientY - cy;
    const dist = Math.hypot(dx, dy);
    if (dist > maxR) {
      dx = (dx / dist) * maxR;
      dy = (dy / dist) * maxR;
    }
    const nx = clamp(dx / maxR, -1, 1);
    const ny = clamp(-dy / maxR, -1, 1); // +Y = UP on Xbox Original
    const knob = which === 'L' ? stickLKnob : stickRKnob;
    knob.style.transform = 'translate3d(' + dx.toFixed(1) + 'px,' + dy.toFixed(1) + 'px,0)';
    if (which === 'L') {
      state.lx = Math.round(nx * 32767);
      state.ly = Math.round(ny * 32767);
      stickL.classList.add('active');
    } else {
      state.rx = Math.round(nx * 32767);
      state.ry = Math.round(ny * 32767);
      stickR.classList.add('active');
    }
    dirty = true;
    sendNow(true);
  }

  function resetStick(which) {
    if (which === 'L') {
      state.lx = 0; state.ly = 0;
      stickLKnob.style.transform = 'translate3d(0,0,0)';
      stickL.classList.remove('active');
    } else {
      state.rx = 0; state.ry = 0;
      stickRKnob.style.transform = 'translate3d(0,0,0)';
      stickR.classList.remove('active');
    }
    dirty = true;
    sendNow(true);
  }

  function updateDpad(clientX, clientY) {
    const box = dpadEl.getBoundingClientRect();
    const dx = clientX - (box.left + box.width * 0.5);
    const dy = clientY - (box.top + box.height * 0.5);
    const dead = box.width * 0.12;
    let mask = 0;
    if (dy < -dead) mask |= 1; // Up
    if (dy >  dead) mask |= 2; // Down
    if (dx < -dead) mask |= 4; // Left
    if (dx >  dead) mask |= 8; // Right
    state.wButtons = (state.wButtons & ~0x000F) | mask;
    dpU.classList.toggle('active', !!(mask & 1));
    dpD.classList.toggle('active', !!(mask & 2));
    dpL.classList.toggle('active', !!(mask & 4));
    dpR.classList.toggle('active', !!(mask & 8));
    dirty = true;
    sendNow(true);
  }

  function clearDpad() {
    state.wButtons &= ~0x000F;
    dpU.classList.remove('active');
    dpD.classList.remove('active');
    dpL.classList.remove('active');
    dpR.classList.remove('active');
    dirty = true;
    sendNow(true);
  }

  function recomputeButtons() {
    let bits = state.wButtons & 0x000F; // keep dpad bits
    state.a = state.b = state.x = state.y = state.bl = state.wh = state.lt = state.rt = 0;
    document.querySelectorAll('.shoulder, .face, .mini-round').forEach(el => el.classList.remove('active'));
    for (const rec of active.values()) {
      if (rec.type === 'btn') {
        rec.el.classList.add('active');
        if (rec.bit) bits |= rec.bit;
        if (rec.analog) state[rec.analog] = 255;
      }
    }
    state.wButtons = bits;
    dirty = true;
    sendNow(true);
  }

  function findTarget(x, y) {
    const el = document.elementFromPoint(x, y);
    if (!el) return null;
    if (el === stickL || stickL.contains(el)) return { type: 'L' };
    if (el === stickR || stickR.contains(el)) return { type: 'R' };
    if (el === dpadEl || dpadEl.contains(el)) return { type: 'D' };
    const btn = el.closest('[data-bit],[data-analog]');
    if (btn) {
      return {
        type: 'btn',
        el: btn,
        bit: btn.dataset.bit ? parseInt(btn.dataset.bit, 10) : 0,
        analog: btn.dataset.analog || ''
      };
    }
    return null;
  }

  function onDown(id, x, y) {
    const target = findTarget(x, y);
    if (!target) return;
    active.set(id, target);
    if (target.type === 'L' || target.type === 'R') {
      vib(10);
      updateStick(target.type, x, y);
    } else if (target.type === 'D') {
      vib(10);
      updateDpad(x, y);
    } else if (target.type === 'btn') {
      vib(14);
      recomputeButtons();
    }
  }

  function onMove(id, x, y) {
    const rec = active.get(id);
    if (!rec) return;
    if (rec.type === 'L' || rec.type === 'R') {
      updateStick(rec.type, x, y);
    } else if (rec.type === 'D') {
      updateDpad(x, y);
    }
  }

  function onUp(id) {
    const rec = active.get(id);
    if (!rec) return;
    active.delete(id);
    if (rec.type === 'L' || rec.type === 'R') {
      resetStick(rec.type);
    } else if (rec.type === 'D') {
      clearDpad();
    } else if (rec.type === 'btn') {
      recomputeButtons();
    }
  }

  // Native multi-touch listeners (iPhone Safari + Android Chrome)
  padEl.addEventListener('touchstart', (e) => {
    if (e.target === fsBtn) return;
    e.preventDefault();
    for (const t of e.changedTouches) onDown(t.identifier, t.clientX, t.clientY);
  }, { passive: false });

  padEl.addEventListener('touchmove', (e) => {
    e.preventDefault();
    for (const t of e.changedTouches) onMove(t.identifier, t.clientX, t.clientY);
  }, { passive: false });

  padEl.addEventListener('touchend', (e) => {
    if (e.target === fsBtn) return;
    e.preventDefault();
    for (const t of e.changedTouches) onUp(t.identifier);
  }, { passive: false });

  padEl.addEventListener('touchcancel', (e) => {
    e.preventDefault();
    for (const t of e.changedTouches) onUp(t.identifier);
  }, { passive: false });

  // Desktop / Pointer fallback (also useful for testing)
  let mouseDown = false;
  padEl.addEventListener('mousedown', (e) => {
    if (e.target === fsBtn) return;
    mouseDown = true;
    onDown('mouse', e.clientX, e.clientY);
  });
  window.addEventListener('mousemove', (e) => {
    if (mouseDown) onMove('mouse', e.clientX, e.clientY);
  });
  window.addEventListener('mouseup', () => {
    if (mouseDown) { mouseDown = false; onUp('mouse'); }
  });

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && (!ws || ws.readyState > 1)) {
      connectWS();
    }
  });

  connectWS();
})();
</script>
</body>
</html>)SHADOW_P2_HTML";

std::mutex g_p2StateMutex;
IOSVirtualPadSnapshot g_p2Snapshot{};

std::mutex g_p2NetMutex;
std::string g_p2Url = "http://172.20.10.1:8765";
uint16_t g_p2Port = 8765;
int g_listenFd = -1;
int g_wsClientFd = -1;

std::atomic<bool> g_serverRunning{false};
std::atomic<bool> g_p2Connected{false};
std::atomic<bool> g_stopRequested{false};
std::atomic<IOSRemoteP2StateCallback> g_stateCallback{nullptr};

std::thread g_serverThread;

static void NotifyStateChanged() {
    IOSRemoteP2StateCallback cb = g_stateCallback.load(std::memory_order_acquire);
    if (!cb) return;
    bool running = g_serverRunning.load(std::memory_order_acquire);
    bool connected = g_p2Connected.load(std::memory_order_acquire);
    std::string urlCopy;
    {
        std::lock_guard<std::mutex> lock(g_p2NetMutex);
        urlCopy = g_p2Url;
    }
    NSString *nsUrl = [NSString stringWithUTF8String:urlCopy.c_str()];
    dispatch_async(dispatch_get_main_queue(), ^{
        cb(running, connected, nsUrl ? nsUrl.UTF8String : "http://172.20.10.1:8765");
    });
}

// Rileva il miglior IPv4 locale dando priorità all'Hotspot Personale iOS (bridge100 -> 172.20.10.1),
// poi al Wi-Fi LAN (en0), poi ad eventuali altre interfacce bridge/en non cellulari.
static std::string DetectBestHostIPv4() {
    struct ifaddrs* ifaddr = nullptr;
    if (getifaddrs(&ifaddr) != 0 || !ifaddr) {
        return "172.20.10.1";
    }

    std::string hotspotIp;
    std::string wifiIp;
    std::string fallbackIp;

    for (struct ifaddrs* ifa = ifaddr; ifa != nullptr; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK)) continue;

        char ipBuf[INET_ADDRSTRLEN] = {};
        auto* sin = reinterpret_cast<struct sockaddr_in*>(ifa->ifa_addr);
        if (!inet_ntop(AF_INET, &sin->sin_addr, ipBuf, sizeof(ipBuf))) continue;

        std::string ip(ipBuf);
        if (ip.rfind("169.254.", 0) == 0 || ip.rfind("127.", 0) == 0) continue;

        std::string name(ifa->ifa_name ? ifa->ifa_name : "");
        if (name.rfind("pdp_ip", 0) == 0 || name.rfind("utun", 0) == 0 || name.rfind("ipsec", 0) == 0) {
            continue;
        }

        if (name == "bridge100" || name.rfind("bridge", 0) == 0 || ip.rfind("172.20.10.", 0) == 0) {
            if (hotspotIp.empty()) hotspotIp = ip;
        } else if (name == "en0") {
            if (wifiIp.empty()) wifiIp = ip;
        } else if (name.rfind("en", 0) == 0 || name.rfind("ap", 0) == 0) {
            if (fallbackIp.empty()) fallbackIp = ip;
        }
    }

    freeifaddrs(ifaddr);

    if (!hotspotIp.empty()) return hotspotIp;
    if (!wifiIp.empty()) return wifiIp;
    if (!fallbackIp.empty()) return fallbackIp;
    return "172.20.10.1";
}

static bool SendAll(int fd, const void* data, size_t len) {
    const uint8_t* ptr = static_cast<const uint8_t*>(data);
    size_t remaining = len;
    while (remaining > 0) {
        ssize_t n = send(fd, ptr, remaining, 0);
        if (n <= 0) return false;
        ptr += n;
        remaining -= static_cast<size_t>(n);
    }
    return true;
}

static void SendWsFrame(int fd, uint8_t opcode, const void* payload, size_t len) {
    if (fd < 0) return;
    uint8_t header[10];
    size_t hdrLen = 0;
    header[0] = static_cast<uint8_t>(0x80u | (opcode & 0x0Fu));
    if (len < 126) {
        header[1] = static_cast<uint8_t>(len);
        hdrLen = 2;
    } else if (len < 65536) {
        header[1] = 126;
        header[2] = static_cast<uint8_t>((len >> 8) & 0xFFu);
        header[3] = static_cast<uint8_t>(len & 0xFFu);
        hdrLen = 4;
    } else {
        return;
    }
    if (SendAll(fd, header, hdrLen) && len > 0) {
        SendAll(fd, payload, len);
    }
}

static std::string ComputeWebSocketAcceptKey(const std::string& clientKey) {
    static const char* kGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    std::string combined = clientKey + kGuid;
    unsigned char sha1[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(combined.data(), static_cast<CC_LONG>(combined.size()), sha1);
    @autoreleasepool {
        NSData *digest = [NSData dataWithBytes:sha1 length:CC_SHA1_DIGEST_LENGTH];
        NSString *b64 = [digest base64EncodedStringWithOptions:0];
        return b64 ? std::string(b64.UTF8String) : std::string();
    }
}

static void ResetP2Snapshot() {
    std::lock_guard<std::mutex> lock(g_p2StateMutex);
    std::memset(&g_p2Snapshot, 0, sizeof(g_p2Snapshot));
}

static void ParseP2StateMessage(const std::string& msg) {
    if (msg.size() < 3 || msg[0] != 'S' || msg[1] != ',') return;
    int wButtons = 0;
    int a = 0, b = 0, x = 0, y = 0, bl = 0, wh = 0, lt = 0, rt = 0;
    int lx = 0, ly = 0, rx = 0, ry = 0;
    int parsed = std::sscanf(
        msg.c_str(),
        "S,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
        &wButtons, &a, &b, &x, &y, &bl, &wh, &lt, &rt, &lx, &ly, &rx, &ry
    );
    if (parsed < 13) return;

    auto clampU8 = [](int v) -> uint8_t {
        if (v < 0) return 0;
        if (v > 255) return 255;
        return static_cast<uint8_t>(v);
    };
    auto clampI16 = [](int v) -> int16_t {
        if (v < -32768) return -32768;
        if (v > 32767) return 32767;
        return static_cast<int16_t>(v);
    };

    IOSVirtualPadSnapshot snap{};
    snap.wButtons = static_cast<uint16_t>(wButtons & 0xFFFF);
    snap.bAnalogButtons[0] = clampU8(a);
    snap.bAnalogButtons[1] = clampU8(b);
    snap.bAnalogButtons[2] = clampU8(x);
    snap.bAnalogButtons[3] = clampU8(y);
    snap.bAnalogButtons[4] = clampU8(bl);
    snap.bAnalogButtons[5] = clampU8(wh);
    snap.bAnalogButtons[6] = clampU8(lt);
    snap.bAnalogButtons[7] = clampU8(rt);
    snap.sThumbLX = clampI16(lx);
    snap.sThumbLY = clampI16(ly);
    snap.sThumbRX = clampI16(rx);
    snap.sThumbRY = clampI16(ry);
    snap.anyActive = (snap.wButtons != 0) ||
        snap.bAnalogButtons[0] || snap.bAnalogButtons[1] || snap.bAnalogButtons[2] || snap.bAnalogButtons[3] ||
        snap.bAnalogButtons[4] || snap.bAnalogButtons[5] || snap.bAnalogButtons[6] || snap.bAnalogButtons[7] ||
        (snap.sThumbLX != 0) || (snap.sThumbLY != 0) || (snap.sThumbRX != 0) || (snap.sThumbRY != 0);

    std::lock_guard<std::mutex> lock(g_p2StateMutex);
    g_p2Snapshot = snap;
}

static std::string ExtractHeaderValue(const std::string& req, const char* headerName) {
    std::string lowerReq = req;
    for (char& c : lowerReq) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    std::string needle = std::string("\r\n") + headerName + ":";
    for (char& c : needle) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    size_t pos = lowerReq.find(needle);
    if (pos == std::string::npos) return {};
    size_t valStart = pos + needle.size();
    while (valStart < req.size() && (req[valStart] == ' ' || req[valStart] == '\t')) valStart++;
    size_t valEnd = req.find("\r\n", valStart);
    if (valEnd == std::string::npos) valEnd = req.size();
    while (valEnd > valStart && (req[valEnd - 1] == ' ' || req[valEnd - 1] == '\r')) valEnd--;
    return req.substr(valStart, valEnd - valStart);
}

static void CloseWsClientLocked() {
    if (g_wsClientFd >= 0) {
        shutdown(g_wsClientFd, SHUT_RDWR);
        close(g_wsClientFd);
        g_wsClientFd = -1;
    }
    ResetP2Snapshot();
    bool wasConnected = g_p2Connected.exchange(false, std::memory_order_acq_rel);
    if (wasConnected) {
        NotifyStateChanged();
    }
}

static void ServerThreadMain() {
    std::vector<uint8_t> wsRxBuf;
    wsRxBuf.reserve(4096);
    auto lastWsActivity = std::chrono::steady_clock::now();

    while (!g_stopRequested.load(std::memory_order_acquire)) {
        int listenFd = -1;
        int wsFd = -1;
        {
            std::lock_guard<std::mutex> lock(g_p2NetMutex);
            listenFd = g_listenFd;
            wsFd = g_wsClientFd;
        }
        if (listenFd < 0) break;

        struct pollfd fds[2];
        int nfds = 0;
        fds[nfds].fd = listenFd;
        fds[nfds].events = POLLIN;
        fds[nfds].revents = 0;
        nfds++;

        if (wsFd >= 0) {
            fds[nfds].fd = wsFd;
            fds[nfds].events = POLLIN;
            fds[nfds].revents = 0;
            nfds++;
        }

        int ret = poll(fds, nfds, 60);
        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }

        // 1. Accetta nuove connessioni HTTP / WebSocket
        if ((fds[0].revents & POLLIN) != 0) {
            struct sockaddr_in cliAddr{};
            socklen_t cliLen = sizeof(cliAddr);
            int cfd = accept(listenFd, reinterpret_cast<struct sockaddr*>(&cliAddr), &cliLen);
            if (cfd >= 0) {
                int one = 1;
                setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
                setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
                struct timeval tv{};
                tv.tv_sec = 1;
                tv.tv_usec = 500000;
                setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

                char reqBuf[4096];
                std::string req;
                while (req.find("\r\n\r\n") == std::string::npos && req.size() < 8192) {
                    ssize_t n = recv(cfd, reqBuf, sizeof(reqBuf), 0);
                    if (n <= 0) break;
                    req.append(reqBuf, static_cast<size_t>(n));
                }

                std::string wsKey = ExtractHeaderValue(req, "Sec-WebSocket-Key");
                if (!wsKey.empty() && req.find("GET /ws") == 0) {
                    // Upgrade a RFC 6455 WebSocket
                    std::string acceptKey = ComputeWebSocketAcceptKey(wsKey);
                    std::string resp =
                        "HTTP/1.1 101 Switching Protocols\r\n"
                        "Upgrade: websocket\r\n"
                        "Connection: Upgrade\r\n"
                        "Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n";
                    if (SendAll(cfd, resp.data(), resp.size())) {
                        struct timeval noTimeout{};
                        setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &noTimeout, sizeof(noTimeout));
                        {
                            std::lock_guard<std::mutex> lock(g_p2NetMutex);
                            if (g_wsClientFd >= 0) {
                                shutdown(g_wsClientFd, SHUT_RDWR);
                                close(g_wsClientFd);
                            }
                            g_wsClientFd = cfd;
                        }
                        wsRxBuf.clear();
                        ResetP2Snapshot();
                        lastWsActivity = std::chrono::steady_clock::now();
                        g_p2Connected.store(true, std::memory_order_release);
                        NotifyStateChanged();
                    } else {
                        close(cfd);
                    }
                } else if (req.find("GET /ping") == 0) {
                    static const char kPingResp[] =
                        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";
                    SendAll(cfd, kPingResp, sizeof(kPingResp) - 1);
                    close(cfd);
                } else if (req.find("GET ") == 0) {
                    const size_t htmlLen = std::strlen(kP2ControllerHtml);
                    std::string hdr =
                        "HTTP/1.1 200 OK\r\n"
                        "Content-Type: text/html; charset=utf-8\r\n"
                        "Cache-Control: no-store, no-cache, must-revalidate\r\n"
                        "Connection: close\r\n"
                        "Content-Length: " + std::to_string(htmlLen) + "\r\n\r\n";
                    SendAll(cfd, hdr.data(), hdr.size());
                    SendAll(cfd, kP2ControllerHtml, htmlLen);
                    close(cfd);
                } else {
                    close(cfd);
                }
            }
        }

        // 2. Leggi frame WebSocket dal client Giocatore 2 connesso
        if (nfds == 2 && wsFd >= 0) {
            bool dropClient = false;
            if ((fds[1].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                dropClient = true;
            } else if ((fds[1].revents & POLLIN) != 0) {
                uint8_t tmp[2048];
                ssize_t n = recv(wsFd, tmp, sizeof(tmp), 0);
                if (n <= 0) {
                    dropClient = true;
                } else {
                    lastWsActivity = std::chrono::steady_clock::now();
                    wsRxBuf.insert(wsRxBuf.end(), tmp, tmp + n);

                    // Decodifica tutti i frame completi nel buffer
                    size_t off = 0;
                    while (wsRxBuf.size() - off >= 2) {
                        uint8_t b0 = wsRxBuf[off];
                        uint8_t b1 = wsRxBuf[off + 1];
                        uint8_t opcode = b0 & 0x0Fu;
                        bool masked = (b1 & 0x80u) != 0;
                        uint64_t payloadLen = b1 & 0x7Fu;
                        size_t hdrLen = 2;

                        if (payloadLen == 126) {
                            if (wsRxBuf.size() - off < 4) break;
                            payloadLen = (static_cast<uint64_t>(wsRxBuf[off + 2]) << 8) | wsRxBuf[off + 3];
                            hdrLen = 4;
                        } else if (payloadLen == 127) {
                            dropClient = true;
                            break;
                        }

                        size_t maskLen = masked ? 4 : 0;
                        if (wsRxBuf.size() - off < hdrLen + maskLen + payloadLen) break;

                        const uint8_t* maskKey = masked ? &wsRxBuf[off + hdrLen] : nullptr;
                        const uint8_t* payloadPtr = &wsRxBuf[off + hdrLen + maskLen];

                        std::string decoded(static_cast<size_t>(payloadLen), '\0');
                        for (size_t i = 0; i < static_cast<size_t>(payloadLen); i++) {
                            decoded[i] = static_cast<char>(masked ? (payloadPtr[i] ^ maskKey[i & 3]) : payloadPtr[i]);
                        }

                        off += hdrLen + maskLen + static_cast<size_t>(payloadLen);

                        if (opcode == 0x8) {
                            dropClient = true;
                            break;
                        } else if (opcode == 0x9) {
                            SendWsFrame(wsFd, 0xA, decoded.data(), decoded.size());
                        } else if (opcode == 0x1) {
                            ParseP2StateMessage(decoded);
                        }
                    }
                    if (off > 0) {
                        wsRxBuf.erase(wsRxBuf.begin(), wsRxBuf.begin() + static_cast<std::ptrdiff_t>(off));
                    }
                    if (wsRxBuf.size() > 16384) {
                        wsRxBuf.clear();
                    }
                }
            } else {
                auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - lastWsActivity).count();
                if (elapsedMs > 5000) {
                    dropClient = true;
                }
            }

            if (dropClient) {
                std::lock_guard<std::mutex> lock(g_p2NetMutex);
                CloseWsClientLocked();
                wsRxBuf.clear();
            }
        }
    }

    {
        std::lock_guard<std::mutex> lock(g_p2NetMutex);
        CloseWsClientLocked();
        if (g_listenFd >= 0) {
            close(g_listenFd);
            g_listenFd = -1;
        }
    }
    g_serverRunning.store(false, std::memory_order_release);
    NotifyStateChanged();
}

} // namespace

extern "C" {

bool IOSRemoteP2_StartServer(uint16_t preferredPort) {
    if (preferredPort == 0) preferredPort = 8765;

    if (g_serverRunning.load(std::memory_order_acquire)) {
        // Aggiorna comunque l'URL con l'IP Hotspot/Wi-Fi più recente
        std::string ip = DetectBestHostIPv4();
        {
            std::lock_guard<std::mutex> lock(g_p2NetMutex);
            g_p2Url = "http://" + ip + ":" + std::to_string(g_p2Port);
        }
        NotifyStateChanged();
        return true;
    }

    if (g_serverThread.joinable()) {
        g_stopRequested.store(true, std::memory_order_release);
        g_serverThread.join();
    }

    int fd = -1;
    uint16_t boundPort = preferredPort;
    for (uint16_t attempt = 0; attempt < 10; attempt++) {
        uint16_t port = static_cast<uint16_t>(preferredPort + attempt);
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s < 0) continue;

        int one = 1;
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

        struct sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(port);

        if (bind(s, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == 0 && listen(s, 8) == 0) {
            fd = s;
            boundPort = port;
            break;
        }
        close(s);
    }

    if (fd < 0) {
        return false;
    }

    std::string ip = DetectBestHostIPv4();
    {
        std::lock_guard<std::mutex> lock(g_p2NetMutex);
        g_listenFd = fd;
        g_p2Port = boundPort;
        g_p2Url = "http://" + ip + ":" + std::to_string(boundPort);
    }

    ResetP2Snapshot();
    g_p2Connected.store(false, std::memory_order_release);
    g_stopRequested.store(false, std::memory_order_release);
    g_serverRunning.store(true, std::memory_order_release);
    g_serverThread = std::thread(ServerThreadMain);
    NotifyStateChanged();
    return true;
}

void IOSRemoteP2_StopServer(void) {
    g_stopRequested.store(true, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(g_p2NetMutex);
        if (g_listenFd >= 0) {
            shutdown(g_listenFd, SHUT_RDWR);
        }
        if (g_wsClientFd >= 0) {
            shutdown(g_wsClientFd, SHUT_RDWR);
        }
    }
    if (g_serverThread.joinable()) {
        g_serverThread.join();
    }
    ResetP2Snapshot();
    g_p2Connected.store(false, std::memory_order_release);
    g_serverRunning.store(false, std::memory_order_release);
    NotifyStateChanged();
}

bool IOSRemoteP2_IsServerRunning(void) {
    return g_serverRunning.load(std::memory_order_acquire);
}

bool IOSRemoteP2_IsConnected(void) {
    return g_p2Connected.load(std::memory_order_acquire);
}

void IOSRemoteP2_GetURL(char* outBuf, size_t bufLen) {
    if (!outBuf || bufLen == 0) return;
    std::string ip = DetectBestHostIPv4();
    std::string url;
    {
        std::lock_guard<std::mutex> lock(g_p2NetMutex);
        g_p2Url = "http://" + ip + ":" + std::to_string(g_p2Port);
        url = g_p2Url;
    }
    std::snprintf(outBuf, bufLen, "%s", url.c_str());
}

bool IOSRemoteP2_GetState(IOSVirtualPadSnapshot* outSnapshot) {
    if (!outSnapshot || !g_p2Connected.load(std::memory_order_acquire)) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_p2StateMutex);
    *outSnapshot = g_p2Snapshot;
    return true;
}

void IOSRemoteP2_SetRumble(uint16_t leftMotor, uint16_t rightMotor) {
    if (!g_p2Connected.load(std::memory_order_acquire)) return;
    static std::atomic<uint32_t> s_lastSentVal{0};
    uint32_t packed = (static_cast<uint32_t>(leftMotor) << 16) | rightMotor;
    if (s_lastSentVal.exchange(packed, std::memory_order_relaxed) == packed) return;

    char msg[32];
    int len = std::snprintf(msg, sizeof(msg), "R,%u,%u", leftMotor, rightMotor);
    if (len <= 0) return;

    std::lock_guard<std::mutex> lock(g_p2NetMutex);
    if (g_wsClientFd >= 0) {
        SendWsFrame(g_wsClientFd, 0x1, msg, static_cast<size_t>(len));
    }
}

void IOSRemoteP2_SetStateCallback(IOSRemoteP2StateCallback cb) {
    g_stateCallback.store(cb, std::memory_order_release);
}

} // extern "C"
