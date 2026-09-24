#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/tests
swiftc Sources/Popaste/{InterfaceText,Localization,Store,Configuration,Style,Insertion,CompactIcon,NativeControls,NativeEditor,NativeInterface,GlassSurface}.swift scripts/render-readme.swift -o .build/tests/readme-preview
.build/tests/readme-preview
