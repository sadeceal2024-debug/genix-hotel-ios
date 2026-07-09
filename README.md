# Genix Hotel — iOS

Hybrid WKWebView wrapper for **https://hotel.genixsoft.com.tr** (English / international
edition of Genix Otel PMS).

| | |
|---|---|
| Bundle ID | `com.genixsoft.hotel` |
| Display name | Genix Hotel |
| IAP product | `com.genixsoft.hotel.pro.yearly` ($119 / year, auto-renewable) |
| APNs topic | `com.genixsoft.hotel` (Team `3NQBF82PXT`, Key `H442HYVV92`) |
| Xcode scheme | `Otel PMS` (internal name kept on purpose — renaming targets breaks signing) |

## Differences from the Turkish app (`genix-otel-ios`)

* Points at `hotel.genixsoft.com.tr`, not `otel.genixsoft.com.tr`
* Emerald app icon (the Turkish app is indigo) — App Store 4.3 differentiation
* **No voice assistant.** The native `SFSpeechRecognizer` code was removed, so the app
  requests **no microphone and no speech-recognition permission**.
* All Swift comments and user-facing strings are English (Turkish characters broke builds)
* e-Invoice (GİB) and KBS (Turkish police reporting) are hidden in the web app

## Build (Codemagic, no Mac needed)

1. Add this repo in Codemagic.
2. Environment group **`ios_signing`** must contain the secure var `CERTIFICATE_PRIVATE_KEY_B64`.
3. App Store Connect integration must be named **`GENIX_ASC_KEY`**.
4. After creating the app in App Store Connect, paste its numeric Apple ID into
   `APP_STORE_APPLE_ID` in `codemagic.yaml`.
5. Run the `ios-appstore` workflow → uploads to TestFlight.

## Review accounts (App Store Connect → App Review Information)

* `apple@genixsoft.com.tr` / `Apple2026!` — unlimited subscription, own hotel with full demo data
* Payments on iOS go through Apple IAP only; the web checkout is never shown in the app.
