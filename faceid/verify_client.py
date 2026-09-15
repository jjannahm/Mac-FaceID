"""Client de test : simule ce que fait le module PAM.

Usage :  python -m faceid.verify_client
Sortie 0 si "OK", 1 si "FAIL", 2 si erreur/daemon injoignable.
"""
import sys
import socket

from . import config


def main(lock=False):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    # The optional method chooser can remain open while the user decides. Match the
    # PAM client's bound so a successful scan is not reported as a client timeout.
    s.settimeout(120)
    try:
        s.connect(str(config.SOCKET_PATH))
        s.sendall(b"VERIFY_LOCK\n" if lock else b"VERIFY\n")
        reply = s.recv(32).decode("ascii", "ignore").strip()
    except OSError as e:
        print(f"ERR {e}", file=sys.stderr)
        return 2
    finally:
        s.close()
    print(reply)
    return 0 if reply == "OK" else 1


if __name__ == "__main__":
    raise SystemExit(main(lock="--lock" in sys.argv))
