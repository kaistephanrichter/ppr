# PPR - Paperless NGX Client for iOS

## Overview

A native iOS client that connects to a **self-hosted Paperless-ngx** instance over its **REST API**. The app is for a single user (or small household): you supply the server URL and an API token; there is no bundled Paperless service—everything lives on your server.

## Scope

Product goals (from this document), aligned with what Paperless-ngx already provides:

- Capture documents with the device camera
- Set tags and document type on documents before uploading
- Upload documents via the system share sheet (Share extension)
- Search documents on the server and open/view them
- Show server health: errors, task queue, index/classifier status, storage, etc.

**Out of scope for an initial version (unless you explicitly pull them in):** full admin of users/groups, mail rules, workflows, web-only features, and replacing the Paperless web UI. The app focuses on **ingest + find + read + status**.

### Capture documents

**Understanding:** Users photograph paper (or import from Photos), optionally crop or multi-page scan, then send the result into the same upload/metadata flow as other sources.

**Needs:** Camera and photo-library access (permissions), capture UI (e.g. `UIImagePickerController` / `PHPicker` or a scanning-oriented flow), PDF or image encoding as the server expects (`POST /api/documents/post_document/` and related upload semantics per OpenAPI). After capture, the user should land on metadata (tags, document type) before upload.

### Edit captured document metadata

**Understanding:** Before upload, the user picks **document type** and **tags** (and optionally title or other fields the API allows on create). Values come from the server (`GET /api/document_types/`, `GET /api/tags/`) so labels stay in sync with Paperless.

**Needs:** Local form state, searchable pickers, respect server pagination for large tag/type lists, validation against server rules, then attach fields to the multipart or JSON upload request as required by the API.

### Share-upload documents

**Understanding:** From Safari, Mail, Files, etc., the user uses **Share → PPR**; the share extension receives a file or URL, optionally shows the same metadata screen, then uploads to the same endpoint as in-app capture.

**Needs:** An **app extension** target, shared networking + models + auth (App Group or Keychain access group) so the extension can read **base URL + API token** stored by the main app. Handle common UTTypes (PDF, images, possibly multiple items).

### Search and view documents

**Understanding:** Search is **server-side** (Paperless index), not only local string match on one page of results. The app lists results, shows thumbnails, and opens the PDF (or preview) via authenticated requests.

**Needs:** `GET /api/documents/` with query parameters matching Paperless search/filter semantics (see OpenAPI for `documents_list`), optional `GET /api/search/autocomplete/` for suggestions, list UI with pagination (`next` / `previous` or `page`). For viewing: `GET /api/documents/{id}/thumb/`, `GET /api/documents/{id}/download/` or preview endpoint, always sending `Authorization: Token …`. **Note:** list payloads can include large OCR `content` fields; we should confirm whether the API allows omitting or truncating fields for list views to save bandwidth and memory on device.

### Server status

**Understanding:** A read-only “health” screen for operators: queue stuck, index errors, storage low, etc.—similar in spirit to the web admin status.

**Needs:** `GET /api/status/` (and optionally `GET /api/statistics/` for counts). Parse JSON for database/redis/celery/index/classifier/sanity fields and present clear human-readable status + last-run timestamps where available.

---

## What we need to do (engineering)

1. **Xcode project** — SwiftUI (or hybrid) iOS app + Share Extension target; bundle IDs, App Group if sharing credentials with the extension.
2. **Configuration & security** — Store **server URL** and **API token** in Keychain; settings UI in the main app; never log `GET /api/profile/` responses (they echo `auth_token`). Support your LAN/server URL and TLS as you deploy (HTTP only where you explicitly allow it, e.g. lab network).
3. **API client layer** — Base URL + token header (`Authorization: Token <token>`), `Codable` models, decoding of paginated envelopes (`count`, `next`, `previous`, `results`, `all`). Prefer one small module the app and extension both use.
4. **OpenAPI reference** — Treat `GET /api/schema/` as the source of truth for request/response shapes; optionally generate Swift types later; until then, hand-model the endpoints we actually call.
5. **Vertical slices (suggested order)**  
   - Status + simple “connection test” (proves URL/token).  
   - Search + document list + thumbnail + PDF viewer.  
   - Upload from in-app (pick file) + metadata form + `post_document`.  
   - Camera capture wired into the same pipeline.  
   - Share extension reusing upload + metadata.
6. **Polish** — Loading/error states, offline messaging (first version can be “network required”), large PDF behavior, and App Store privacy strings for camera/photos/network.

---

## Ausbaustufe: KI-gestützte Dokumentenanalyse

Ziel: Beim Erfassen (und optional für bestehende Dokumente) schlägt die App automatisch Titel, Tags, Dokumenttyp und Korrespondent vor — auf Basis des erkannten Textes (OCR) oder des Dokumentinhalts aus Paperless.

### Option A: Apple Foundation Models (on-device, iOS 26+)

Das `FoundationModels`-Framework gibt direkten Zugriff auf das Apple-Intelligence-Modell, das lokal auf dem Gerät läuft (A17 Pro / M-Chip erforderlich). Keine externe Abhängigkeit, vollständig privat.

```swift
import FoundationModels

let session = LanguageModelSession()
let result = try await session.respond(
    to: "Analysiere dieses Dokument und schlage Titel, Tags und Dokumenttyp vor:\n\(documentText)"
)
```

**Vorteile:** Offline, privat, keine Serverkosten, native Integration.
**Einschränkungen:** Nur neuere Geräte, ~3B Parameter (weniger leistungsfähig als große Modelle), englischsprachiges Basismodell (Deutsch funktioniert, aber eingeschränkt).

### Option B: Ollama auf dem Home-Server

Ollama kann neben Paperless auf demselben Docker-Host betrieben werden und bietet eine OpenAI-kompatible HTTP-API. Die App ruft sie wie die Paperless-API auf.

```http
POST http://192.168.178.x:11434/api/generate
{ "model": "llama3.2", "prompt": "..." }
```

**Vorteile:** Leistungsfähigere Modelle (Llama 3.2, Mistral, Gemma), kein Apple-Silicon nötig, volle Kontrolle über Modellauswahl.
**Einschränkungen:** Server muss laufen und erreichbar sein, keine Offline-Nutzung.

### Mögliche Features

- **Beim Erfassen:** OCR-Text → automatisch Titel, Tags, Dokumenttyp und Korrespondent vorschlagen (Nutzer bestätigt/korrigiert vor Upload)
- **Dokumentenliste:** Kurzzusammenfassung (1–2 Sätze) pro Dokument anzeigen
- **Intelligente Suche:** Semantische Suche statt nur Volltextsuche — "Alle Rechnungen über 100€ aus 2025" auch ohne exakte Schlagwörter

### Empfehlung

Beide Optionen können kombiniert werden: Ollama als Primärquelle (leistungsfähiger), Apple Foundation Models als Fallback wenn kein Server erreichbar.

---

## Setup

- Self-hosted **Paperless-ngx** with the REST API enabled and an **API token** for the app user.
- **Native iOS app** built in Xcode; device or simulator must reach the server (same LAN/VPN as appropriate).
