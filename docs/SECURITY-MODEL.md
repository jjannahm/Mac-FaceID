# Security model

FaceKey protects against accidental approval and casual use by another person. It does not protect against an attacker who can present a high-quality image/video, compromise the login account, inject into FaceKey, or modify an ad-hoc signed build.

Enrollment embeddings are AES-256-GCM encrypted with a random key stored in the login Keychain. Raw frames are processed in memory and discarded. Logs record operational outcomes only—not frames, embeddings, purchase metadata, reasons, or app-authorization similarity scores.

App requests are restricted to the current UID, an allowlisted claimed bundle ID, protocol v1, a unique nonce, a maximum 120-second expiry, bounded fields, and one active request. In ad-hoc builds, the bundle ID is not cryptographic caller identity. A production release must add Developer ID signature validation before allowing third-party clients.

The PAM rule is `sufficient`, never `required`. Unavailability, rejection, timeout, crash, removal, or recognition failure proceeds to Touch ID/password. FaceKey does not support the login window, FileVault, Apple Pay, App Store, Apple Books, browser payments, or SecurityAgent replacement.
