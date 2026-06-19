#!/usr/bin/env bash
set -euo pipefail

# A real Apple Development identity is preferred and Xcode handles it itself.
# For local Debug builds without one, replace the unstable linker signature
# with a complete ad-hoc signature whose designated requirement is based on
# the bundle identifier instead of a changing CDHash. This keeps macOS TCC
# permissions usable across rebuilds.
if [[ "${CONFIGURATION:-}" != "Debug" || -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    exit 0
fi

APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-cn.hungryhenry.sttformac}"

if [[ ! -d "$APP" ]]; then
    echo "warning: Cannot apply local signature; app not found at $APP"
    exit 0
fi

/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --identifier "$IDENTIFIER" \
    --requirements "=designated => identifier \"$IDENTIFIER\"" \
    "$APP"
