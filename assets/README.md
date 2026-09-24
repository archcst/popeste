# Popeste brand

Application icon: solid yellow `#FFC400` with a white ribbon P. The menu bar retains the monochrome template mark.

- `logo.svg`: original ribbon P, editable vector master.
- `app-icon.png`: 1024 × 1024 application icon preview.
- `Sources/Popaste/BrandIcon.swift`: native drawing of the same mark; the menu bar uses a template image so macOS controls its appearance.

`scripts/build-app.sh` generates the complete iconset and bundles `AppIcon.icns`. To regenerate the PNG preview, copy `.build/AppIcon.iconset/icon_512x512@2x.png` to `assets/app-icon.png` after building.
