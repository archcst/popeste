#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/tests
swiftc Sources/Popaste/{InterfaceText,Localization,Store,Configuration,Style,Insertion,CompactIcon,NativeControls,NativeEditor,NativeInterface}.swift scripts/render-native-preview.swift -o .build/tests/ui-review
.build/tests/ui-review
