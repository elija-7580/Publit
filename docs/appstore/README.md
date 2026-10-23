# App Store screenshots

**Rule: every mockup shows the app inside Apple's real device bezel** (official Product Bezels from
https://developer.apple.com/design/resources/). No drawn or imitated frames, for any device.

| Folder | Device and bezel | Size | App Store Connect slot |
| --- | --- | --- | --- |
| `mockups/iphone` | iPhone 18 Pro Max, Black | 1320×2868 | 6.9″ iPhone |
| `mockups/ipad` | iPad Pro (M5) 13″, Space Black, landscape | 2752×2064 | 13″ iPad |
| `mockups/duo` | iPhone Duo, Night Sky (cover display and unfolded inner display) | 1398×2034, 2853×2007, 2007×2853 | iPhone Duo |
| `mockups/watch` | Apple Watch Ultra 3, Black, Ocean Band | 422×514 | Apple Watch Ultra |

Each folder has `en/` and `de/`. The screen opening of every bezel PNG matches the raw screenshot size exactly,
so the screenshots are placed 1:1.

- Raw screenshots: `raw/<device>/<lang>/` (from the UI tests `testF29AppStoreShots`, the Duo shots, and the watch demo screens).
  The watch screens exist in English only; the German watch set has German captions over them.
- Build: `tools/appstore/compose.py` (captions are in the file). The workflow **App Store mockups**
  (`.github/workflows/appstore-mockups.yml`) downloads the bezels, composes and commits everything here;
  a commit message with `[mockups]` runs it, `[mockups] [upload]` also replaces the screenshots in App Store Connect
  (`tools/appstore/upload.py`, result in `upload-report.txt`).
- The last iPhone slide (Europe coverage map) has no device and is kept as it was.
