# Publit design language: Ink & Dot

Flat, matte and platform-neutral. Draft for iOS, Android and the web; values in `tokens.json`,
clickable preview in `prototype.html` (sample data, not the app).

## Principles
1. **Flat content.** Opaque cards on a light warm grey (dark: near black), large radius (22), hairlines instead of shadows, no blur.
2. **Matte floating layer.** Live trip bars and map chips are opaque surfaces with a hairline, not blurred glass. The four-tab dock is an opaque app-owned pill; pushed navigation and system sheets remain native; the same content treatment works in Compose and on the web.
3. **Ink, not colour.** The interface is black/white/grey. The primary action is ink (black; white in dark mode). Selected chips are ink.
4. **Colour means something.** Line colours (badges, route tracks) are the main colour. Green/orange/red only for on time / late / cancelled.
5. **The dot is the signature.** The yellow dot of the logo (#FFC531) appears only where it means "you" or "live": your position, the trip in progress, the current tab. Never as a fill or background.
6. **The stroke comes from the logo.** Route lines and progress bars use the logo's thick stroke with round caps; stops are rings.
7. **Numbers first.** Minutes and times are large, bold and tabular; units small and grey.

## Per platform
- iOS: SF Pro, opaque `Color.surface` for floating app controls; no material blur. Every `List`/`Form` gets `.inkList()`, main actions `.buttonStyle(.ink)`, swipe actions `.tint(Color.inkAction)`; no system colours (`.blue`, `.borderedProminent`, `systemGroupedBackground`). The app tint and the `AccentColor` asset are ink.
- Android: Roboto Flex / system font with the same scale; Compose with these tokens, not default Material colours or tonal elevation.
- Web: system font stack (Inter as fallback), CSS variables from the tokens.

## Live bar and loading
- Install `.liveTripBar()` on each tab's NavigationStack. It overlays the matte navigation dock plus live bar, measures their combined height and supplies `liveBarInset`; `.inkList()` and vertical `.liveBarPadding()` scrollers reserve that space. Sheet roots without the bar reset the inset to zero. Error banners reserve their own space above it.
- Pull the live bar up or tap it to open the trip. Countdown transitions and the pull settle respect Reduce Motion.
- Loading uses `LogoLoader`, the logo stroke and landing dot. Reduced Motion shows a static mark; no relative-date self-redraw or TimelineView loop.
- `DurationFigure` keeps localized units small and numbers large, bold and tabular. Timeline labels show each leg's minutes when there is enough room.

## Reference layout
Production layout and verification boundaries for build 32 are documented in `IMPLEMENTATION.md`. The prototype is a visual reference, not proof that the SwiftUI app matches it. Native screenshots come from UI test F18.
