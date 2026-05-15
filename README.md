# PPR – Paperless-ngx iOS Client

A native iOS app for scanning, uploading, and managing documents with [paperless-ngx](https://docs.paperless-ngx.com).

## Features

- **Document Capture** – Scan documents with the camera, import from Photos, or pick files
- **Document Management** – Browse, search, and filter your paperless-ngx archive
- **Metadata Editing** – Edit title, date, document type, correspondent, and tags
- **PDF Preview** – View document PDFs inline with full-screen option
- **Smart Filtering** – Filter by document type, correspondent, and tags with document counts
- **Onboarding** – Guided setup for server URL and API token
- **Localization** – Fully translated in 7 languages (DE, EN, FR, ES, IT, NL, PL)
- **Dark Mode** – Custom accent colors and app icons for light and dark appearance

## Requirements

- iOS 17.0+
- A running [paperless-ngx](https://docs.paperless-ngx.com) instance accessible on your network
- An API token (found in paperless-ngx under Settings → Profile → API Token)

## Setup

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Fastlane](https://fastlane.tools) (optional, for screenshots: `brew install fastlane`)

### Build

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Open in Xcode
open PPR.xcodeproj
```

### Configuration

The app stores credentials securely in the iOS Keychain. On first launch, the onboarding screen guides you through setup:

1. Enter your paperless-ngx server URL (e.g., `http://192.168.1.100:8000`)
2. Enter your personal API token

### App Store Screenshots

```bash
# Generate screenshots for all devices and languages
fastlane screenshots
```

Screenshots are saved to `fastlane/screenshots/` organized by language and device.

## Architecture

```
Sources/PPR/
├── API/                    # Networking layer (PaperlessAPI, error handling)
├── Configuration/          # App configuration and keychain storage
├── Models/                 # Data models (Document, Tag, Correspondent, etc.)
├── Networking/             # Local network access utilities
├── Resources/              # Assets, localizations, app icons
├── Supporting/             # Info.plist
├── Views/                  # SwiftUI views
│   ├── CaptureView.swift           # Camera/scanner tab
│   ├── CaptureMetadataView.swift   # Upload metadata form
│   ├── DocumentListView.swift      # Document browser with search & filter
│   ├── DocumentDetailView.swift    # Document detail with PDF & editing
│   ├── OnboardingView.swift        # First-launch setup
│   └── SettingsView.swift          # Server status & configuration
├── PPRApp.swift            # App entry point
└── RootView.swift          # Tab-based root navigation

Sources/PPRUITests/         # Fastlane snapshot UI tests
```

## Project Configuration

The Xcode project is generated from `project.yml` using XcodeGen. After any changes to `project.yml`, run:

```bash
xcodegen generate
```

## License

Private project – all rights reserved.
