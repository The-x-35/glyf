#!/bin/sh
# Bundles signer.src.js with viem for JavaScriptCore and regenerates SignerScript.swift.
set -e
cd "$(dirname "$0")/../../../server"
NODE_PATH=$PWD/node_modules ./node_modules/.bin/esbuild ../app/ios/signer/signer.src.js --bundle --format=iife \
  --platform=browser --target=es2020 --minify --inject:../app/ios/signer/polyfill.js --outfile=../app/ios/signer/glyf-signer.js
cd ../app/ios
python3 -c "import base64;b=base64.b64encode(open('signer/glyf-signer.js','rb').read()).decode();open('GlyfKeyboard/Engine/SignerScript.swift','w').write('// Generated from app/ios/signer/signer.src.js (esbuild + viem); rebuild with\n// app/ios/signer/build.sh. The keyboard\'s own signer for the ETHGlobal demo.\nenum SignerScript {\n    static let base64 = \"'+b+'\"\n}\n')"
