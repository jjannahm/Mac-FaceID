"""Encrypted, user-local storage for face embeddings.

The encryption key lives in the user's login keychain.  Tests and headless builds can
provide FACEKEY_STORAGE_KEY as a URL-safe base64 encoded 32-byte key.
"""
from __future__ import annotations

import base64
import io
import os
import subprocess
from pathlib import Path

import numpy as np
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SERVICE = "com.jjannahm.FaceKey.embeddings"
ACCOUNT = "local-user"
MAGIC = b"FACEKEY1\0"


class StorageError(RuntimeError):
    pass


def _key() -> bytes:
    override = os.environ.get("FACEKEY_STORAGE_KEY")
    if override:
        key = base64.urlsafe_b64decode(override.encode("ascii"))
        if len(key) != 32:
            raise StorageError("FACEKEY_STORAGE_KEY must encode exactly 32 bytes")
        return key

    found = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", SERVICE,
         "-a", ACCOUNT, "-w"], capture_output=True, timeout=5,
    )
    if found.returncode == 0:
        return base64.urlsafe_b64decode(found.stdout.strip())

    key = AESGCM.generate_key(bit_length=256)
    encoded = base64.urlsafe_b64encode(key)
    saved = subprocess.run(
        ["/usr/bin/security", "add-generic-password", "-U", "-s", SERVICE,
         "-a", ACCOUNT, "-w", encoded.decode("ascii")],
        capture_output=True, timeout=5,
    )
    if saved.returncode != 0:
        raise StorageError("could not store the FaceKey encryption key in Keychain")
    return key


def save(path: Path, embeddings) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    buffer = io.BytesIO()
    np.save(buffer, np.asarray(embeddings, dtype=np.float32), allow_pickle=False)
    nonce = os.urandom(12)
    ciphertext = AESGCM(_key()).encrypt(nonce, buffer.getvalue(), MAGIC)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(MAGIC + nonce + ciphertext)
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def load(path: Path):
    if not path.exists():
        return None
    payload = path.read_bytes()
    if not payload.startswith(MAGIC) or len(payload) < len(MAGIC) + 13:
        raise StorageError("face data is not an encrypted FaceKey enrollment")
    offset = len(MAGIC)
    nonce, ciphertext = payload[offset:offset + 12], payload[offset + 12:]
    clear = AESGCM(_key()).decrypt(nonce, ciphertext, MAGIC)
    return np.load(io.BytesIO(clear), allow_pickle=False)
