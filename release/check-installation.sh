#!/usr/bin/env bash

set -u

SERVICE_NAME="microscope-picam2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/usr/bin/python3"
PYTHON_DIR="$ROOT_DIR/python"
PYTHON_TAG_FILE="$PYTHON_DIR/.python-tag"
RUN_USER="${SUDO_USER:-$(id -un)}"
POWEROFF_HELPER="/usr/local/sbin/microscope-picam2-poweroff"
SUDOERS_FILE="/etc/sudoers.d/microscope-picam2-poweroff"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'OK    %s\n' "$1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf 'WARN  %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL  %s\n' "$1"
}

check_file() {
  if [ -f "$1" ]; then
    pass "$2"
  else
    fail "$2 is missing: $1"
  fi
}

check_executable() {
  if [ -x "$1" ]; then
    pass "$2"
  else
    fail "$2 is missing or not executable: $1"
  fi
}

echo "MicroRasp installation check"
echo "Directory: $ROOT_DIR"
echo "User:      $RUN_USER"
echo

check_executable "$PYTHON" "System Python"
check_file "$ROOT_DIR/backend/app/entry.py" "Backend"
check_file "$ROOT_DIR/frontend/dist/index.html" "Frontend"
check_file "$ROOT_DIR/requirements.txt" "Python requirements"
check_executable "$ROOT_DIR/run.sh" "Start script"
check_executable "$ROOT_DIR/resources/mertens.sh" "Canonical Mertens script"
check_executable "$ROOT_DIR/photos/mertens.sh" "Mertens-script in photos"

if [ -f "$ROOT_DIR/resources/mertens.sh" ] && [ -f "$ROOT_DIR/photos/mertens.sh" ]; then
  if cmp -s "$ROOT_DIR/resources/mertens.sh" "$ROOT_DIR/photos/mertens.sh"; then
    pass "Mertens script in photos is up to date"
  else
    fail "Mertens script in photos differs from the canonical copy"
  fi

  MERTENS_MODE="$(stat -c '%a' "$ROOT_DIR/photos/mertens.sh" 2>/dev/null || true)"
  if [ "$MERTENS_MODE" = "555" ]; then
    pass "Mertens-script in photos is read-only (0555)"
  else
    fail "Mertens script in photos has mode $MERTENS_MODE instead of 0555"
  fi
fi

if [ -d "$ROOT_DIR/photos" ]; then
  pass "Photos-directory"
else
  fail "Photos directory is missing: $ROOT_DIR/photos"
fi

if [ -d "$PYTHON_DIR" ]; then
  pass "Local Python directory"
else
  fail "Local Python directory is missing: $PYTHON_DIR"
fi

if [ -x "$PYTHON" ] && [ -f "$PYTHON_TAG_FILE" ]; then
  CURRENT_PYTHON_TAG="$("$PYTHON" - <<'PY'
import sys
print(sys.implementation.cache_tag or f"python-{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
  INSTALLED_PYTHON_TAG="$(cat "$PYTHON_TAG_FILE")"

  if [ "$CURRENT_PYTHON_TAG" = "$INSTALLED_PYTHON_TAG" ]; then
    pass "Python ABI matches ($CURRENT_PYTHON_TAG)"
  else
    fail "Python ABI mismatch: installed=$INSTALLED_PYTHON_TAG, current=$CURRENT_PYTHON_TAG"
  fi
else
  fail "Python ABI tag is missing: $PYTHON_TAG_FILE"
fi

if [ -x "$PYTHON" ]; then
  if "$PYTHON" - <<'PY' >/tmp/microrasp-check-system-python.$$ 2>&1
from pathlib import Path
import libcamera
import picamera2

path = Path(picamera2.__file__).resolve()
print(path)
PY
  then
    PICAMERA_PATH="$(tail -n 1 /tmp/microrasp-check-system-python.$$)"
    if [[ "$PICAMERA_PATH" == "$PYTHON_DIR/"* ]]; then
      fail "Picamera2 comes from MicroRasp/python instead of the host system: $PICAMERA_PATH"
    else
      pass "Picamera2/libcamera via system Python ($PICAMERA_PATH)"
    fi
  else
    fail "Picamera2/libcamera cannot be imported with system Python"
    sed 's/^/      /' /tmp/microrasp-check-system-python.$$ 2>/dev/null || true
  fi
  rm -f /tmp/microrasp-check-system-python.$$

  if PYTHONPATH="$PYTHON_DIR" "$PYTHON" - <<'PY' >/tmp/microrasp-check-local-python.$$ 2>&1
import fastapi
import piexif
import pydantic
import uvicorn

print(
    f"fastapi={fastapi.__version__}, "
    f"pydantic={pydantic.__version__}, "
    f"uvicorn={uvicorn.__version__}"
)
PY
  then
    pass "MicroRasp Python-dependencies ($(tail -n 1 /tmp/microrasp-check-local-python.$$))"
  else
    fail "MicroRasp Python dependencies cannot be imported"
    sed 's/^/      /' /tmp/microrasp-check-local-python.$$ 2>/dev/null || true
  fi
  rm -f /tmp/microrasp-check-local-python.$$
fi

if [ -d "$ROOT_DIR/photos" ]; then
  if [ "$(id -u)" -eq 0 ] && [ "$RUN_USER" != "root" ]; then
    if sudo -u "$RUN_USER" test -w "$ROOT_DIR/photos"; then
      pass "Photos directory is writable by $RUN_USER"
    else
      fail "Photos directory is not writable by $RUN_USER"
    fi
  elif [ -w "$ROOT_DIR/photos" ]; then
    pass "Photos directory is writable by $RUN_USER"
  else
    fail "Photos directory is not writable by $RUN_USER"
  fi
fi

if [ -f "$ROOT_DIR/.env.local" ]; then
  if grep -qE '^[[:space:]]*VITE_SATURATION_FACTOR=' "$ROOT_DIR/.env.local"; then
    warn ".env.local still contains VITE_SATURATION_FACTOR; use SATURATION_FACTOR"
  fi

  if "$PYTHON" - "$ROOT_DIR/.env.local" <<'PY' >/dev/null 2>&1
import sys

path = sys.argv[1]
values = {}

with open(path, encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")

if "AEB_STOPS" in values and float(values["AEB_STOPS"].replace(",", ".")) <= 0:
    raise ValueError("AEB_STOPS must be > 0")

if "SATURATION_FACTOR" in values and float(values["SATURATION_FACTOR"].replace(",", ".")) <= 1:
    raise ValueError("SATURATION_FACTOR must be > 1")
PY
  then
    pass ".env.local is valid"
  else
    fail ".env.local contains an invalid AEB_STOPS or SATURATION_FACTOR"
  fi
else
  pass "No .env.local: built-in defaults are used"
fi

if systemctl cat "$SERVICE_NAME.service" >/dev/null 2>&1; then
  pass "Systemd service is installed"
else
  fail "Systemd service is missing: $SERVICE_NAME.service"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME.service" 2>/dev/null; then
  pass "Systemd-service is enabled"
else
  fail "Systemd service is not enabled"
fi

if systemctl is-active --quiet "$SERVICE_NAME.service" 2>/dev/null; then
  pass "Systemd service is running"
else
  fail "Systemd service is running niet"
fi

check_executable "$POWEROFF_HELPER" "Poweroff-helper"

if [ -f "$SUDOERS_FILE" ]; then
  if sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    pass "Poweroff sudoers configuration"
  else
    fail "Poweroff sudoers configuration is invalid"
  fi
else
  fail "Poweroff sudoers configuration is missing: $SUDOERS_FILE"
fi

if [ -x "$PYTHON" ]; then
  API_RESULT="$("$PYTHON" - <<'PY' 2>/dev/null
import json
import time
import urllib.request

url = "http://127.0.0.1:8000/api/status"
last_error = None

for _ in range(20):
    try:
        with urllib.request.urlopen(url, timeout=1.0) as response:
            data = json.load(response)
        connected = bool(data.get("camera", {}).get("connected"))
        error = data.get("camera", {}).get("error") or ""
        print(json.dumps({
            "reachable": True,
            "connected": connected,
            "error": error,
            "status": data.get("status"),
        }))
        raise SystemExit(0)
    except Exception as exc:
        last_error = str(exc)
        time.sleep(0.25)

print(json.dumps({
    "reachable": False,
    "connected": False,
    "error": last_error or "unknown error",
    "status": None,
}))
raise SystemExit(1)
PY
)"
  API_RC=$?

  if [ "$API_RC" -eq 0 ]; then
    pass "Webserver responds on /api/status"

    CAMERA_CONNECTED="$("$PYTHON" -c 'import json,sys; print("yes" if json.loads(sys.argv[1]).get("connected") else "no")' "$API_RESULT")"
    if [ "$CAMERA_CONNECTED" = "yes" ]; then
      pass "Camera is connected"
    else
      CAMERA_ERROR="$("$PYTHON" -c 'import json,sys; print(json.loads(sys.argv[1]).get("error") or "")' "$API_RESULT")"
      if [ -n "$CAMERA_ERROR" ]; then
        warn "Camera not connected or not started: $CAMERA_ERROR"
      else
        warn "Camera not connected or not started"
      fi
    fi
  else
    fail "Webserver does not respond on http://127.0.0.1:8000/api/status"
    [ -n "$API_RESULT" ] && printf '      %s\n' "$API_RESULT"
  fi
fi

echo
echo "Result: $PASS_COUNT OK, $WARN_COUNT warning(s), $FAIL_COUNT failure(s)."

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "MicroRasp installation is NOT fully operational."
  exit 1
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  echo "MicroRasp installation is operational, with the warning(s) above."
else
  echo "MicroRasp installation is fully operational."
fi
