# PPR – Paperless-ngx for iOS

A friendly, native iOS companion for your [paperless-ngx](https://docs.paperless-ngx.com) archive. Snap a receipt at the kitchen table, drop a PDF in from Files, and find that one contract from 2022 in seconds — all without leaving your phone.

PPR talks to **your** server. Nothing is uploaded anywhere else, no account is required, and your API token lives in the iOS Keychain.

## What it does

- **Capture from anywhere** – Use the document scanner (`VisionKit`), pick from Photos, or import any file. They all flow into the same upload screen.
- **Quick metadata before upload** – Set title, document type, correspondent, and tags up front, so things land in the right place from the start.
- **Browse, search, filter** – Full-text search runs server-side via the paperless index (debounced so it stays snappy). Filter by type, correspondent, and tags; group and sort to taste.
- **iOS 18 floating search** – The search field appears as the new floating element on the Documents tab, just like Apple's own apps.
- **Edit on the fly** – Tap any document to edit its metadata, preview the PDF inline, or open it full-screen.
- **Server health at a glance** – A status view shows queue, index, classifier, and storage (`GET /api/status/`) — handy for self-hosters.
- **Always knows the network** – PPR distinguishes "device offline", "server unreachable", and "all good", with helpful empty states and a one-tap shortcut to Settings. When the connection comes back, the document list refreshes itself.
- **7 languages** – DE (source), EN, FR, ES, IT, NL, PL.
- **Polished icons & splash** – Light, dark, and iOS 18 *tinted* app icons, plus a launch animation that smoothly hands off from the system splash.

## Requirements

- **iOS 18.0+**
- **Xcode 16+**
- A reachable [paperless-ngx](https://docs.paperless-ngx.com) instance
- An API token (paperless-ngx → Settings → Profile → API Token)

> Plain HTTP servers on local networks work out of the box (`NSAllowsArbitraryLoads` is enabled in `Info.plist`). For anything reachable from the public internet, please use HTTPS.

## Getting started

### Tools you'll need

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [Fastlane](https://fastlane.tools) — *optional*, only for App Store screenshots: `brew install fastlane`
- `sips` (already on macOS) — used by the App Icon build phase

### Build & run

```bash
# Generate the Xcode project from project.yml
xcodegen generate

# Open in Xcode and hit Run
open PPR.xcodeproj
```

On first build, an Xcode pre-build phase regenerates `Assets.xcassets/AppIcon.appiconset` from `assets/app-icon-light.png` and `assets/app-icon-dark.png`. Alpha is flattened (the App Store rejects alpha on marketing icons), and the dark variant is wired up via the `appearances` key.

### First launch

The onboarding flow walks you through it:

1. Enter your paperless-ngx server URL — e.g. `http://192.168.1.100:8000` or `https://paperless.example.com`
2. Paste your personal API token

Both are stored in the iOS Keychain. You can change them anytime under **Settings**.

### Local development secrets

`.secrets` (gitignored) holds defaults used by tooling and UI tests. The runtime app does **not** read this file — it reads from the Keychain.

```dotenv
PAPERLESS_SERVER_URL=...
PAPERLESS_USER=...
PAPERLESS_USER_TOKEN=...
```

### App Store screenshots

```bash
# Generate screenshots for all configured devices and languages
fastlane screenshots

# Optional: add device frames
fastlane frame

# Both in one go
fastlane screenshots_framed
```

Configured in [fastlane/Snapfile](fastlane/Snapfile):

- Devices: iPhone 17 Pro Max, iPhone 17, iPad Pro 13-inch (M5)
- Languages: `de-DE`, `en-US`

Output lands in `fastlane/screenshots/<lang>/<device>-<screen>.png` (gitignored).

## Project layout

```text
.
├── assets/                                 # Master source PNGs (icons, logos, art)
│   ├── app-icon-{light,dark,tinted}.png    # → drives AppIcon.appiconset via build script
│   ├── logo-{light,dark}.png
│   ├── error-{light,dark}.png
│   ├── success-{light,dark}.png
│   ├── upload-{light,dark}.png
│   └── document-capture-{light,dark}.png
├── fastlane/                               # Fastfile, Snapfile, generated screenshots
├── scripts/
│   └── build_app_icons.sh                  # AppIcon regeneration (Xcode pre-build phase)
├── Sources/
│   ├── PPR/                                # Main app target
│   │   ├── API/                            # PaperlessAPI client + error formatting
│   │   ├── Configuration/                  # AppConfiguration, Keychain, TabRouter
│   │   ├── Models/                         # Document, Tag, Correspondent, DocumentType, …
│   │   ├── Networking/                     # NetworkMonitor, LocalNetworkAccess (Bonjour warm-up)
│   │   ├── Resources/
│   │   │   ├── Assets.xcassets             # Generated icon set + image sets
│   │   │   └── Localizable.xcstrings       # 7-language string catalog
│   │   ├── Supporting/Info.plist
│   │   ├── Views/
│   │   │   ├── CaptureView.swift
│   │   │   ├── CaptureMetadataView.swift
│   │   │   ├── DocumentScannerView.swift
│   │   │   ├── PhotoPickerView.swift
│   │   │   ├── DocumentPickerView.swift
│   │   │   ├── DocumentListView.swift
│   │   │   ├── DocumentDetailView.swift
│   │   │   ├── OnboardingView.swift
│   │   │   ├── SettingsView.swift
│   │   │   ├── StatusView.swift
│   │   │   ├── ServerStatusDetailView.swift
│   │   │   └── ErrorDetailSheet.swift
│   │   ├── PPRApp.swift                    # @main entry
│   │   └── RootView.swift                  # 3-tab TabView + splash
│   └── PPRUITests/                         # Fastlane snapshot UI tests
├── project.yml                             # XcodeGen spec — regenerate after edits
├── project.md                              # Product scope + roadmap (incl. AI roadmap)
├── PPR.xcodeproj/                          # Generated — please don't hand-edit
└── README.md
```

## How it's wired

A handful of small ideas keep the codebase calm:

- **Observable state, injected via environment.** `AppConfiguration`, `NetworkMonitor`, `ImportQueue`, and `TabRouter` are all `@Observable` classes pushed into the SwiftUI environment from `PPRApp`. Views read what they need.
- **One shared tab router.** `TabRouter` exposes a single `selectedTab: Int`, so any view can deep-link the user to another tab — for example, the Documents empty state has a "Settings" shortcut, and a fresh share import jumps straight to Capture.
- **Plain `Codable` API.** `PaperlessAPI` is a small set of static methods that return decoded `count / next / previous / results` envelopes. Auth is `Authorization: Token <token>`.
- **Helpful errors.** Every API error is formatted by `PaperlessAPI.formattedUserError(_:)`. The UI shows a one-line summary, with a tap-to-expand `ErrorDetailSheet` for the curious or the debugging.
- **Self-healing connection state.** `NetworkMonitor` tracks `offline / serverUnreachable / connected`. When it flips back to `connected`, screens that were stuck on an error reload themselves quietly.
- **UI state remembers itself.** Filter selections, sort order, and group-by are persisted in `UserDefaults`; the values are reapplied as soon as metadata loads on launch.
- **Friendlier first launch.** `LocalNetworkAccess.warmUpBonjourBrowse()` runs early so iOS shows the local-network permission prompt at a sensible moment, not when you're mid-scan.

## Working on the project

Whenever you change `project.yml`, regenerate the Xcode project:

```bash
xcodegen generate
```

Avoid hand-editing `PPR.xcodeproj/project.pbxproj` — XcodeGen will overwrite it on the next run.

## Roadmap

See [project.md](project.md) for the full product scope and the AI-assisted document analysis roadmap (Apple Foundation Models and/or Ollama).

Not yet built:

- Share Extension target (in scope; planned)
- AI metadata suggestions (title / tags / type) at capture time
- Semantic search ("all invoices over €100 from 2025")

Suggestions and ideas are welcome.

## License

Private project — all rights reserved.

---

Made with care for a paperless household. Have fun with it.
