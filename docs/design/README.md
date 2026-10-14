# Publit design language: Ink & Dot

Flat like Bevel, with one layer of glass. Draft for iOS, Android and the web; values in `tokens.json`,
clickable preview in `prototype.html` (sample data, not the app).

## Principles
1. **Flat content.** Opaque cards on a light warm grey (dark: near black), large radius (22), hairlines instead of shadows, no blur.
2. **One glass layer.** Only floating controls are glass: tab bar, live trip bar, map chips. Nothing with content.
3. **Ink, not colour.** The interface is black/white/grey. The primary action is ink (black; white in dark mode). Selected chips are ink.
4. **Colour means something.** Line colours (badges, route tracks) are the main colour. Green/orange/red only for on time / late / cancelled.
5. **The dot is the signature.** The yellow dot of the logo (#FFC531) appears only where it means "you" or "live": your position, the trip in progress, the current tab. Never as a fill or background.
6. **The stroke comes from the logo.** Route lines and progress bars use the logo's thick stroke with round caps; stops are rings.
7. **Numbers first.** Minutes and times are large, bold and tabular; units small and grey.

## Per platform
- iOS: SF Pro, system materials only for the glass layer. Every `List`/`Form` gets `.inkList()`, main actions `.buttonStyle(.ink)`, swipe actions `.tint(Color.inkAction)`; no system colours (`.blue`, `.borderedProminent`, `systemGroupedBackground`). The app tint and the `AccentColor` asset are ink.
- Android: Roboto Flex / system font with the same scale; Compose with these tokens, not default Material colours or tonal elevation.
- Web: system font stack (Inter as fallback), CSS variables from the tokens.
