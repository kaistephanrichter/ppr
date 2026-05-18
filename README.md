# PPR – Paperless-ngx iOS Client

A native iOS app for scanning, uploading, and managing documents with [paperless-ngx](https://docs.paperless-ngx.com).

## Features

- **Document Capture** – Scan documents with `VisionKit` (`VNDocumentCameraViewController`), import from Photos, or pick files
- **Metadata Before Upload** – Set title, document type, correspondent, and tags before sending to the server
- **Document Management** – Browse, search, filter, group, and sort your paperless-ngx archive
- **Floating iOS 18 Search** – `.searchable()` on the Documents tab renders as the new floating search element
- **Server-Side Search** – Full-text search executed by the paperless-ngx index (debounced, 400 ms)
- **Smart Filtering** – Filter by document type, correspondent, and tags; top 7 tags by usage with "show all" toggle
- **Pagination** – Infinite scroll for ungrouped lists; full pagination when grouping is active
- **Metadata Editing** – Edit title, date, document type, correspondent, and tags on existing documents
- **PDF Preview** – View document PDFs inline with full-screen option
- **Server Status** – Health view (queue, index, classifier, storage) backed by `GET /api/status/`
- **Onboarding** – Guided setup for server URL and API token, persisted in the iOS Keychain
- **Localization** – 7 languages (DE source; EN, FR, ES, IT, NL, PL translated)
- **Light/Dark/Tinted Icons** – iOS 18 tinted app-icon variant included
- **Splash Screen** – Custom launch animation matching the asset catalog launch logo
- **Network Awareness** – `NetworkMonitor` distinguishes offline vs. server-unreachable vs. ready

## Requirements

- **iOS 18.0+** (deployment target)
- **Xcode 16+**
- A reachable [paperless-ngx](https://docs.paperless-ngx.com) instance
- An API token (paperless-ngx → Settings → Profile → API Token)

> Plain HTTP servers on local networks are supported via `NSAllowsArbitraryLoads` in `Info.plist`. For production deployments, prefer HTTPS.

## Setup

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Fastlane](https://fastlane.tools) (optional, for App Store screenshots: `brew install fastlane`)
- ImageMagick / `sips` (already on macOS) for the App Icon build phase

### Build

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Open in Xcode
open PPR.xcodeproj
```

The first build runs `scripts/build_app_icons.sh` automatically as a pre-build phase. It regenerates `Assets.xcassets/AppIcon.appiconset` from `assets/app-icon-light.png` and `assets/app-icon-dark.png` (alpha channel flattened, dark variant included via `appearances`).

### Configuration

Credentials are stored in the iOS Keychain. On first launch, onboarding guides you through:

1. Enter your paperless-ngx server URL (e.g. `http://192.168.1.100:8000` or `https://paperless.example.com`)
2. Enter your personal API token

You can change server/token later via the Settings tab.

### Local Development Secrets

`.secrets` (gitignored) holds developer-side defaults used by tooling/UI tests, not by the app itself:

```dotenv
PAPERLESS_SERVER_URL=...
PAPERLESS_USER=...
PAPERLESS_USER_TOKEN=...
```

The runtime app reads only from the Keychain.

### App Store Screenshots

```bash
# Generate screenshots for all configured devices and languages
fastlane screenshots

# (Optional) Add device frames
fastlane frame

# Both in one go
fastlane screenshots_framed
```

Configured in [fastlane/Snapfile](fastlane/Snapfile):

- Devices: iPhone 17 Pro Max, iPhone 17, iPad Pro 13-inch (M5)
- Languages: `de-DE`, `en-US`

Output: `fastlane/screenshots/<lang>/<device>-<screen>.png` (gitignored).

## Project Layout

```text
.
├── assets/                                 # Master source PNGs (app icon, logos, etc.)
│   ├── app-icon-{light,dark,tinted}.png    # → drives AppIcon.appiconset via build script
│   ├── logo-{light,dark}.png
│   ├── error-{light,dark}.png
│   ├── success-{light,dark}.png
│   ├── upload-{light,dark}.png
│   └── document-capture-{light,dark}.png
├── fastlane/                               # Fastfile, Snapfile, generated screenshots
├── scripts/
│   └── build_app_icons.sh                  # AppIcon regeneration (runs as Xcode pre-build)
├── Sources/
│   ├── PPR/                                # Main app target
│   │   ├── API/                            # PaperlessAPI client + error formatting
│   │   ├── Configuration/                  # AppConfiguration, Keychain storage
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
├── project.yml                             # XcodeGen spec (regenerate after edits)
├── project.md                              # Product scope + roadmap (incl. AI roadmap)
├── PPR.xcodeproj/                          # Generated by XcodeGen
└── README.md
```

## Architecture Notes

- **State management:** SwiftUI's `@Observable` macro on `AppConfiguration`, `NetworkMonitor`, `ImportQueue`, injected via `.environment(...)`.
- **Navigation:** `TabView` with `Tab(value:)` API (iOS 18) — three tabs: Capture, Documents, Settings.
- **API layer:** `PaperlessAPI` static methods returning `Codable` envelopes (`count`, `next`, `previous`, `results`). Authorization via `Token <token>` header.
- **Error handling:** All API errors are formatted via `PaperlessAPI.formattedUserError(_:)`; UI shows summary plus tappable detail sheet (`ErrorDetailSheet`).
- **Persistence of UI state:** filter selections, sort order, and group-by are persisted in `UserDefaults` (and restored once metadata is loaded).
- **Bonjour warm-up:** On launch, `LocalNetworkAccess.warmUpBonjourBrowse()` triggers the iOS local-network permission prompt early.

## Project Configuration

The Xcode project is **generated** from `project.yml` using XcodeGen. After any change to `project.yml`, regenerate:

```bash
xcodegen generate
```

Don't edit `PPR.xcodeproj/project.pbxproj` by hand — your changes will be overwritten on the next regeneration.

## Roadmap

See [project.md](project.md) for product scope and the AI-assisted document analysis roadmap (Apple Foundation Models / Ollama).

Currently not yet implemented:

- Share Extension target (in scope per `project.md`, not built yet)
- AI metadata suggestions (titles/tags/types) on capture
- Semantic search

## License

Private project — all rights reserved.
