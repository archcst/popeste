#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/tests
swiftc Sources/Popaste/Localization.swift Sources/Popaste/Store.swift Sources/Popaste/Configuration.swift Sources/Popaste/Placement.swift Tests/PopasteTests/StoreTests.swift -o .build/tests/store-tests
.build/tests/store-tests

node --test Tests/search-input.test.cjs Tests/vim-editor.test.cjs Tests/editor-exit.test.cjs
