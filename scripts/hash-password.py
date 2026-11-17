#!/usr/bin/env python3
"""Print a SALTED_PASS line for .env from a password typed at the prompt.

Same format changedetection.io checks at login:
base64(salt + PBKDF2-HMAC-SHA256(password, salt, 100000)), 32-byte salt.
"""
import base64
import getpass
import hashlib
import secrets
import sys

password = getpass.getpass("UI password: ")
if password != getpass.getpass("Again: "):
    sys.exit("Passwords do not match.")
if len(password) < 16:
    sys.exit("Use at least 16 characters.")

salt = secrets.token_bytes(32)
key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 100000)
print("SALTED_PASS=" + base64.b64encode(salt + key).decode("ascii"))
