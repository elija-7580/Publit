# App icon sources

The app icon PNGs are kept here as base64 text so every file in the repo stays
plain text. The "Decode app icon" pre-build script in `project.yml` writes them
to `Sources/App/Assets.xcassets/AppIcon.appiconset/` before the asset catalog is
compiled. Vector masters live in `docs/brand/` (`icon-light.svg`, `icon-dark.svg`,
`icon-tinted.svg`). All three appearances are 1024×1024, 8-bit RGB, no alpha.

To change the icon, export 1024×1024 PNGs (8-bit RGB, no alpha) and run:

    for f in AppIcon AppIcon-Dark AppIcon-Tinted; do base64 -i $f.png -o Config/AppIcon/$f.png.b64; done
