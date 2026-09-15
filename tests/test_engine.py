#!/usr/bin/env python3
"""Tests du moteur qui ne demandent ni caméra ni visage.

Ils couvrent ce que `faceid.selftest` ne voit pas : le comportement du daemon autour de
la reconnaissance — préchauffage, abandon, enrôlement cumulatif, lecture des réglages —
et le protocole de sa socket. Chacun correspond à un défaut réel rencontré.

    python tests/test_engine.py
"""
import os
import base64
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import numpy as np                                          # noqa: E402
import cv2                                                  # noqa: E402

from faceid import config, daemon, recognizer               # noqa: E402

# Keep tests deterministic and independent of the developer's login keychain.
os.environ["FACEKEY_STORAGE_KEY"] = base64.urlsafe_b64encode(b"t" * 32).decode()

FAILURES = []


def check(name, ok, detail=""):
    print(f"  {'OK  ' if ok else 'FAIL'}  {name}" + (f"  → {detail}" if detail else ""))
    if not ok:
        FAILURES.append(name)


# --------------------------------------------------------------------------- warmup
class FakeCapture:
    """Caméra factice qui débite une suite de luminosités connues."""

    def __init__(self, brightnesses):
        self.queue = list(brightnesses)
        self.last = 0
        self.reads = 0

    def read(self):
        self.reads += 1
        if self.queue:
            self.last = self.queue.pop(0)
        return True, np.full((8, 8, 3), self.last, dtype=np.uint8)


def test_warmup():
    print("préchauffage adaptatif")
    cap = FakeCapture([100] * 8)
    daemon._adaptive_warmup(cap)
    check("s'arrête dès que l'exposition est stable", cap.reads == 2,
          f"{cap.reads} frames")

    cap = FakeCapture([10, 40, 70, 100, 130, 160, 190, 220])
    daemon._adaptive_warmup(cap)
    check("garde le plafond quand elle bouge encore",
          cap.reads == config.CAMERA_WARMUP_FRAMES, f"{cap.reads} frames")


# ---------------------------------------------------------------------- annulation
class SlowCapture:
    """Caméra qui ne montre jamais de visage : sans abandon, on attend le budget."""

    def __init__(self):
        self.released = False

    def isOpened(self):                                     # noqa: N802 (API OpenCV)
        return True

    def set(self, *_):
        pass

    def read(self):
        time.sleep(0.01)
        return True, np.zeros((480, 640, 3), dtype=np.uint8)

    def release(self):
        self.released = True


def test_cancel():
    print("abandon depuis la capsule")
    fake = SlowCapture()
    original = cv2.VideoCapture
    cv2.VideoCapture = lambda *a, **k: fake
    try:
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.enrolled = np.random.rand(4, 128).astype(np.float32)
        d.enrolled_mtime = 0.0
        d._mtime = lambda: 0.0
        d.engine = type("E", (), {"frame_feature": lambda self, f: (None, None)})()

        cancelled = threading.Event()
        threading.Timer(0.25, cancelled.set).start()
        started = time.time()
        ok, reason = d._verify_face_camera(timeout=30, cancelled=cancelled)
        elapsed = time.time() - started

        check("le clic interrompt la reconnaissance",
              not ok and "cancelled" in reason, reason)
        check("il rend la main sans attendre le budget", elapsed < 2.0,
              f"{elapsed:.2f}s au lieu de 30s")
        check("la caméra est relâchée", fake.released)
    finally:
        cv2.VideoCapture = original


# ------------------------------------------------------------------- apparences
def test_append():
    print("apparences cumulatives")
    with tempfile.TemporaryDirectory() as tmp:
        saved_dir, saved_path = config.APP_DIR, config.EMBEDDINGS_PATH
        config.APP_DIR = Path(tmp)
        config.EMBEDDINGS_PATH = config.APP_DIR / "embeddings.facekey"
        try:
            first = np.random.rand(8, 128).astype(np.float32)
            recognizer.save_embeddings(first)
            merged = np.vstack([recognizer.load_embeddings(),
                                np.random.rand(8, 128).astype(np.float32)])
            recognizer.save_embeddings(merged)
            after = recognizer.load_embeddings()
            check("ajouter concatène au lieu de remplacer", len(after) == 16,
                  f"8 → {len(after)}")
            check("les vecteurs d'origine sont intacts", np.allclose(after[:8], first))
            raw = config.EMBEDDINGS_PATH.read_bytes()
            check("les embeddings ne sont jamais stockés en clair",
                  not raw.startswith(b"\\x93NUMPY") and raw.startswith(b"FACEKEY1"))
        finally:
            config.APP_DIR, config.EMBEDDINGS_PATH = saved_dir, saved_path


# ----------------------------------------------------------------------- réglages
def test_flags():
    print("lecture des réglages")
    check("le panneau de choix est absent par défaut", config.MODAL_ENABLED is False)
    check("la capsule est présente par défaut", config.HUD_ENABLED is True)
    check("capture en 640×480",
          (config.CAPTURE_WIDTH, config.CAPTURE_HEIGHT) == (640, 480))
    # Une variable posée mais vide valait « activé », parce que "" n'est pas "0".
    check("une variable vide vaut le défaut", config._flag("ABSENTE_ICI", "0") is False)


# ------------------------------------------------------------------------- i18n
def test_i18n():
    print("traductions du moteur")
    table = ROOT / "i18n" / "engine.json"
    if not table.exists():
        check("i18n/engine.json est généré", False, "lancer scripts/make_i18n.py")
        return
    import json
    data = json.loads(table.read_text(encoding="utf-8"))
    check("toutes les langues sont présentes", len(data) == 11, f"{len(data)} langues")
    keys = set(data["en"])
    check("chaque langue a les mêmes clés",
          all(set(v) == keys for v in data.values()))
    check("aucune traduction vide",
          all(all(s.strip() for s in v.values()) for v in data.values()))


# ---------------------------------------------------------------------- socket
def test_socket():
    print("protocole de la socket")
    # Chemin court obligatoire : une socket UNIX est limitée à ~104 caractères.
    runtime = tempfile.mkdtemp(dir="/tmp", prefix="mg")
    env = dict(os.environ)
    env.update({
        "HOME": runtime,             # isole APP_DIR → aucun enrôlement, aucune caméra
        "FACEID_HUD": "0",
        "PYTHONUNBUFFERED": "1",
        "FACEID_I18N": str(ROOT / "i18n"),
    })
    models = os.environ.get(
        "FACEID_MODELS_DIR",
        os.path.expanduser("~/Library/Application Support/FaceKey/models"))
    env["FACEID_MODELS_DIR"] = models
    # Le daemon refuse de démarrer sans les modèles, et l'échec ressemblait alors à une
    # régression du protocole plutôt qu'à un dépôt incomplet.
    if not os.path.exists(os.path.join(models, "face_detection_yunet_2023mar.onnx")):
        check("les modèles de reconnaissance sont présents", False,
              f"absents de {models} — lancer scripts/download-models.sh")
        return
    os.makedirs(f"{runtime}/Library/Application Support/FaceKey/logs", exist_ok=True)

    proc = subprocess.Popen([sys.executable, "-m", "faceid.daemon"],
                            cwd=str(ROOT), env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sock_path = f"{runtime}/Library/Application Support/FaceKey/facekey.sock"
    for _ in range(150):
        if os.path.exists(sock_path):
            break
        if proc.poll() is not None:
            check("le daemon démarre", False, proc.stdout.read()[:200])
            return
        time.sleep(0.1)
    else:
        check("le daemon crée sa socket", False)
        proc.kill()
        return

    def ask(command):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(20)
        try:
            s.connect(sock_path)
            s.sendall(command + b"\n")
            return s.recv(64).decode().strip()
        finally:
            s.close()

    try:
        check("le daemon démarre et écoute", True)
        check("PING répond PONG", ask(b"PING") == "PONG")
        check("VERIFY répond sans enrôlement", ask(b"VERIFY") == "FAIL")
        check("VERIFY_LOCK répond aussi", ask(b"VERIFY_LOCK") == "FAIL")
        check("une commande inconnue est rejetée", ask(b"NAWAK").startswith("ERR"))
        for _ in range(5):
            ask(b"PING")
        check("il survit à des connexions successives", proc.poll() is None)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


# ---------------------------------------------------------- app authorization protocol
def test_app_authorization():
    print("protocole d'autorisation d'app")
    d = daemon.Daemon.__new__(daemon.Daemon)
    d._active_request = threading.Lock()
    d._used_nonces = set()
    now = time.time()
    base = {
        "version": 1, "nonce": "abcdefghijklmnop", "bundleID": "allowed.demo",
        "action": "approve an order", "reason": "Confirm the example order",
        "expiresAt": now + 30,
    }
    previous_clients = config.ALLOWED_CLIENTS
    try:
        config.ALLOWED_CLIENTS = {"allowed.demo"}
        check("client inconnu refusé", d._authorize_action(
            dict(base, bundleID="unknown.app")) == "ERR forbidden-client")
        check("requête expirée refusée", d._authorize_action(
            dict(base, nonce="expirednoncevalue1", expiresAt=now - 1)) == "ERR expiry")
        check("nonce malformé refusé", d._authorize_action(
            dict(base, nonce="short")) == "ERR nonce")
        d._used_nonces.add(base["nonce"])
        check("rejeu refusé", d._authorize_action(base) == "ERR replay")
        busy = dict(base, nonce="busynoncevalue0001")
        d._active_request.acquire()
        try:
            check("requêtes concurrentes refusées", d._authorize_action(busy) == "ERR busy")
        finally:
            d._active_request.release()
    finally:
        config.ALLOWED_CLIENTS = previous_clients


def main():
    for test in (test_warmup, test_cancel, test_append,
                 test_flags, test_i18n, test_socket, test_app_authorization):
        test()
    print()
    if FAILURES:
        print(f"ÉCHECS ({len(FAILURES)}) : " + ", ".join(FAILURES))
        return 1
    print("Tous les tests passent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
