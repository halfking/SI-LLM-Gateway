#!/usr/bin/env python3
"""
verify_secret_key.py — DB-hash cross-check guard for LLM_GATEWAY_SECRET_KEY rotation.

Problem this prevents:
  - The exact "Invalid or expired API key" failure that hit 71 on 2026-07-05.
  - Root cause: someone (deploy-71-data-bindmounts.sh skeleton, or a stale
    secrets.env) wrote LLM_GATEWAY_SECRET_KEY=foo into env-file, but the DB
    api_keys.key_hash column was computed against SECRET_KEY=bar (the
    real production key). The gateway then couldn't validate any Bearer
    admin key, returning 401.

How this guard works:
  1. Read CURRENT_SECRET_KEY and NEW_SECRET_KEY (and the existing admin
     api_key from env-file).
  2. Query DB for the api_keys row matching the admin api_key's prefix.
  3. Compute HMAC-SHA256(admin_api_key, new_secret_key) and compare
     against the DB row's key_hash.
  4. If equal → safe to apply.
  5. If not equal → refuse with a loud error message.

The function exits 0 on PASS, exits 2 on FAIL with stderr details.
"""

import hashlib
import hmac
import os
import sys
import urllib.parse


def err(msg):
    print(f"GUARD_FAIL={msg}", file=sys.stderr)
    sys.exit(2)


if len(sys.argv) != 4:
    err("usage: verify_secret_key.py CURRENT_SECRET NEW_SECRET ADMIN_API_KEY")

current_secret = sys.argv[1]
new_secret = sys.argv[2]
admin_api_key = sys.argv[3]

if not current_secret or not new_secret:
    err("empty secret key (refusing to verify)")
if not admin_api_key:
    err("empty admin api key (refusing to verify)")

# Read DB connection from env (inherited from the parent bash invocation).
db_url = os.environ.get("DATABASE_URL", "")
if not db_url:
    err("DATABASE_URL env var not set")

# Parse the URL. Format: postgres://user:pass@host:port/dbname?sslmode=...
parsed = urllib.parse.urlparse(db_url)
db_user = parsed.username
db_pass = parsed.password
db_host = parsed.hostname
db_port = parsed.port or 5432
db_name = parsed.path.lstrip("/").split("?")[0]


# Try to import psycopg. If not available, fall back to a subprocess psql call.
def query_key_hash(prefix):
    """Return the key_hash for the api_keys row whose key_prefix starts with `prefix`,
    or empty string if not found."""
    sql = (
        "SELECT ak.key_hash FROM api_keys ak "
        "WHERE ak.key_prefix LIKE %s AND ak.enabled = TRUE "
        "AND COALESCE(ak.status, 'active') <> 'revoked' "
        "LIMIT 1"
    )
    prefix8 = prefix[:8] if len(prefix) >= 8 else prefix
    try:
        import psycopg

        with psycopg.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_pass,
            dbname=db_name,
            connect_timeout=5,
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (prefix8 + "%",))
                row = cur.fetchone()
                return row[0] if row else ""
    except ImportError:
        # Fall back to subprocess+psql
        import subprocess

        prefix_escaped = prefix8.replace("'", "''")
        sql_plain = (
            "SELECT ak.key_hash FROM api_keys ak "
            f"WHERE ak.key_prefix LIKE '{prefix_escaped}%' "
            "AND ak.enabled = TRUE "
            "AND COALESCE(ak.status, 'active') <> 'revoked' "
            "LIMIT 1"
        )
        env = {
            **os.environ,
            "PGPASSWORD": db_pass,
            "PGUSER": db_user,
            "PGHOST": db_host,
            "PGPORT": str(db_port),
            "PGDATABASE": db_name,
        }
        try:
            r = subprocess.run(
                ["psql", "-tAc", sql_plain],
                capture_output=True,
                text=True,
                env=env,
                timeout=10,
            )
            if r.returncode != 0:
                return ""
            return r.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return ""


# Compute HMAC-SHA256(admin_api_key, secret) per admin/auth.go:hashAPIKey.
def hmac_sha256_hex(key, msg):
    return hmac.new(key.encode(), msg.encode(), hashlib.sha256).hexdigest()


# Step 1: query DB for the key_hash that should match admin_api_key.
expected_hash = query_key_hash(admin_api_key)
if not expected_hash:
    err(f"DB has no api_keys row matching admin_api_key prefix {admin_api_key[:8]!r}")

print(
    f"GUARD_INFO=DB key_hash for {admin_api_key[:8]}... = {expected_hash[:16]}...",
    file=sys.stderr,
)

# Step 2: compute HMAC for CURRENT_SECRET_KEY. We expect this to match.
current_hash = hmac_sha256_hex(current_secret, admin_api_key)
print(
    f"GUARD_INFO=HMAC(current_secret, admin_api_key) = {current_hash[:16]}...",
    file=sys.stderr,
)

if current_hash != expected_hash:
    # The CURRENT secret is wrong! That means the env-file is already
    # broken. Don't apply the new value blindly — refuse.
    err(
        f"CURRENT LLM_GATEWAY_SECRET_KEY in env-file is ALREADY WRONG: "
        f"HMAC against DB key_hash does not match. "
        f"This means the env-file is currently in a broken state. "
        f"Fix the env-file FIRST (restore from a known-good backup or "
        f"regenerate the key in DB) before applying any change."
    )

# Step 3: if NEW differs from CURRENT, check whether NEW also matches.
if new_secret != current_secret:
    new_hash = hmac_sha256_hex(new_secret, admin_api_key)
    print(
        f"GUARD_INFO=HMAC(new_secret, admin_api_key) = {new_hash[:16]}...",
        file=sys.stderr,
    )
    if new_hash != expected_hash:
        err(
            f"NEW LLM_GATEWAY_SECRET_KEY would BREAK admin auth: "
            f"HMAC(new_secret, admin_api_key) does NOT match DB key_hash. "
            f"This is the exact bug that hit 71 on 2026-07-05. "
            f"Refusing to overwrite. Restore the correct key into "
            f"/root/.llm-gateway/secrets.env (likely {current_secret[:8]}...)."
        )

print("GUARD_PASS=secret key verified against DB api_keys.key_hash")
