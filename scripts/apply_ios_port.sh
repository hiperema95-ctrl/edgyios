#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_DIR="$1"
PORT_DIR="$2"

echo "==> Applicazione patch iOS a FoxWorkshop/ShadowRecomp..."
mkdir -p "${UPSTREAM_DIR}/ios"
cp -R "${PORT_DIR}/ios/"* "${UPSTREAM_DIR}/ios/"

if ! grep -q "SHADOW_IOS_PORT" "${UPSTREAM_DIR}/CMakeLists.txt"; then
  cat "${PORT_DIR}/cmake/iOSPortTarget.cmake" >> "${UPSTREAM_DIR}/CMakeLists.txt"
fi

echo "==> Patch iOS applicata con successo."
