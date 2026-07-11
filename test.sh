#!/bin/sh
# automated smoke test for the samba container (MAIN image)
# builds the image, starts smbd with one account + one share (configured purely
# via env - NO host bind-mounts) and asserts samba actually serves SMB:
#   - smbd process comes up and port 445 speaks SMB (negotiate)
#   - smbclient can browse the server and the configured share is listed
#   - the account can authenticate and write/read a file through the share
#   - a wrong password is rejected
# the share data dir is created inside the container via 'docker exec' (no mounts).
set -eu

IMAGE=samba-test
NAME=samba-test-run

# credentials + share used for the whole test (configured via env only)
SMB_USER=tester
SMB_PASS=testpass
SHARE=TestShare
SHARE_PATH=/shares/test

FAILED=0
fail() {
  echo "FAIL: $*" >&2
  FAILED=1
}

cleanup() {
  echo ">> cleanup: removing container $NAME"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo ">> building image $IMAGE"
docker build -t "$IMAGE" .

echo ">> (re)starting container $NAME"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# minimal config to bring smbd up: one account + one share it can serve.
# ACCOUNT_* and SAMBA_VOLUME_CONFIG_* are consumed by the entrypoint (';' -> newline).
docker run -d --name "$NAME" \
  -e ACCOUNT_${SMB_USER}=${SMB_PASS} \
  -e SAMBA_VOLUME_CONFIG_testshare="[${SHARE}]; path=${SHARE_PATH}; valid users = ${SMB_USER}; guest ok = no; read only = no; browseable = yes" \
  "$IMAGE"

echo ">> waiting for smbd to come up (up to ~60s)"
READY=0
i=0
while [ "$i" -lt 30 ]; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
    echo "!! container is not running anymore, dumping logs:" >&2
    docker logs "$NAME" >&2 2>&1 || true
    fail "container exited during startup"
    break
  fi
  if docker exec "$NAME" ps aux 2>/dev/null | grep -q '[s]mbd --foreground'; then
    READY=1
    break
  fi
  i=$((i + 1))
  sleep 2
done

if [ "$READY" -ne 1 ] && [ "$FAILED" -eq 0 ]; then
  echo "!! smbd did not come up in time, dumping logs:" >&2
  docker logs "$NAME" >&2 2>&1 || true
  fail "timed out waiting for smbd"
fi

# only run the deeper assertions if the container is still up
if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then

  echo ">> assert: container is running"
  docker ps --format '{{.Names}}' | grep -q "^${NAME}$" \
    && echo "ok - container running" || fail "container not running"

  echo ">> assert: smbd process present"
  if docker exec "$NAME" ps aux | grep -q '[s]mbd --foreground'; then
    echo "ok - smbd running"
  else
    fail "smbd process not found"
  fi

  # the share data dir is not auto-created for a static path -> create it here.
  # done via 'docker exec' (NOT a bind-mount) to honour the no-mounts rule.
  echo ">> preparing share directory ${SHARE_PATH} (via docker exec, no mounts)"
  docker exec "$NAME" sh -c "mkdir -p '${SHARE_PATH}' && chown ${SMB_USER} '${SHARE_PATH}'" \
    && echo "ok - share dir ready" || fail "could not create share dir"

  echo ">> assert: port 445 speaks SMB and smbclient lists the share '${SHARE}'"
  LISTING=$(docker exec "$NAME" smbclient -L //127.0.0.1 -U "${SMB_USER}%${SMB_PASS}" 2>/dev/null || true)
  if echo "$LISTING" | grep -qw "${SHARE}"; then
    echo "ok - smbclient negotiated SMB and listed share '${SHARE}'"
  else
    echo "$LISTING" >&2
    fail "share '${SHARE}' not listed by smbclient (SMB negotiate/browse failed)"
  fi

  echo ">> assert: authenticate + write/read a file through the share"
  if docker exec "$NAME" sh -c "
      set -e
      echo 'samba-testsuite-payload' > /tmp/payload.txt
      # write into the share over SMB (authenticated)
      smbclient //127.0.0.1/${SHARE} -U '${SMB_USER}%${SMB_PASS}' -c 'put /tmp/payload.txt uploaded.txt'
      # read it back over SMB into a fresh file and compare
      smbclient //127.0.0.1/${SHARE} -U '${SMB_USER}%${SMB_PASS}' -c 'get uploaded.txt /tmp/downloaded.txt'
      cmp /tmp/payload.txt /tmp/downloaded.txt
      # and confirm it actually landed on the served path
      test -f '${SHARE_PATH}/uploaded.txt'
    "; then
    echo "ok - authenticated SMB write/read round-trip through the share succeeded"
  else
    echo "!! dumping container logs:" >&2
    docker logs "$NAME" >&2 2>&1 || true
    fail "authenticated SMB round-trip failed"
  fi

  echo ">> assert: a wrong password is rejected"
  if docker exec "$NAME" smbclient //127.0.0.1/${SHARE} -U "${SMB_USER}%wrong-${SMB_PASS}" -c 'ls' >/dev/null 2>&1; then
    fail "smbd accepted a wrong password (auth not enforced)"
  else
    echo "ok - wrong password rejected"
  fi

fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
