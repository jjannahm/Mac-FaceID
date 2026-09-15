# FaceKey for Mac

FaceKey is a native macOS menu-bar utility for **local, convenience-grade face authorization**. It enrolls a face on-device, can approve actions requested through `FaceKeyKit`, and can optionally let a successful match satisfy `sudo` while retaining the normal Touch ID/password fallback.

> **Not Apple Face ID.** A normal RGB webcam has no infrared depth sensor and can be fooled by a photograph or video. FaceKey cannot unlock FileVault or the first login after restart, authorize Apple Pay or App Store purchases, or replace Touch ID. Never use it as the only protection for sensitive data or real payments.

## Features

- Guided enrollment and alternate appearances using YuNet + SFace.
- AES-256-GCM encrypted embeddings; the encryption key stays in macOS Keychain.
- No saved camera frames, analytics, cloud processing, or network API.
- Versioned `FaceKeyKit` Swift API with expiry, caller allowlisting, replay rejection, one-request-at-a-time enforcement, and explicit approval UI.
- Demo checkout app that makes no charge and clearly shows integration behavior.
- Optional PAM integration for `sudo`, configured as `sufficient` so failure always falls through to the system authentication stack.
- Optional convenience unlock for an already logged-in session, using a device-only
  Keychain password and Accessibility typing after a face match.
- Diagnostics and an uninstaller that restores PAM configuration.

## Optional lock-screen unlock

Open FaceKey settings, save your macOS login password in Keychain, grant Accessibility,
and enable **Convenience Lock-Screen Unlock**. When the current session locks, FaceKey
uses only the MacBook's built-in camera; after a match it types the saved password once.

This is password automation, not Secure Enclave authentication. It does not operate at
FileVault, the first login after restart, fast user switching, purchases, or macOS
authorization dialogs. Three failed recognition cycles suspend attempts until manual
unlock. Uninstalling FaceKey always deletes the saved login password.

## Requirements and build

FaceKey requires an Apple Silicon Mac, macOS 14+, a webcam, Xcode Command Line Tools, and Python 3.12.

```bash
./install.sh
```

The setup downloads the published OpenCV Zoo models, creates a virtual environment, builds the helpers and app, and installs a development app in `/Applications`. Enabling `sudo` is optional and requires administrator approval.

Build without installing:

```bash
bash scripts/setup.sh
bash scripts/build-standalone.sh
bash scripts/build-demo.sh
```

Development builds are ad-hoc signed and are not notarized.

## FaceKeyKit

Add `sdk/` as a local Swift package:

```swift
let request = FaceKeyAuthorizationRequest(
    action: "approve an order",
    reason: "Confirm the Pro workspace purchase",
    merchant: "Example Merchant", currency: "USD", amount: 24
)
let result = try await FaceKeyClient.shared.authorize(request)
```

The calling bundle identifier must be in `FACEKEY_ALLOWED_CLIENTS`; the demo bundle `com.jjannahm.FaceKey.Demo` is allowed by default. The service returns only a result—never images, embeddings, or confidence scores.

The first release uses a versioned, user-only Unix-domain transport because the camera engine runs in the login session. The privileged helper uses native XPC only for PAM installation/removal. Cryptographic identity enforcement for arbitrary third-party clients requires Developer ID signing and is deferred from ad-hoc builds.

## Tests

```bash
python -m faceid.selftest
python tests/test_engine.py
(cd sdk && swift test)
bash scripts/check-i18n.sh
```

Camera and PAM end-to-end checks require an interactive Mac.

## Packaging, privacy, and removal

`scripts/build-release.sh` expects Developer ID Application and Installer certificates plus a `notarytool` profile named `facekey-notary`. Review signing identifiers before publishing.

Runtime data lives in `~/Library/Application Support/FaceKey` with mode `0700`; encrypted enrollment data uses mode `0600`. FaceKey can remove the enrollment, PAM rule, helper, login item, and app. Its Keychain item is `com.jjannahm.FaceKey.embeddings`.

## Attribution and license

FaceKey derives from Lorenzo Coslado's MIT-licensed [Mugshot](https://github.com/Lorenzo-Coslado/macos-faceid). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). It copies no Sapphire code; Sapphire's lock-screen feature displays information and is not biometric authentication.

FaceKey is licensed under GNU AGPL-3.0. Third-party components retain their licenses.
