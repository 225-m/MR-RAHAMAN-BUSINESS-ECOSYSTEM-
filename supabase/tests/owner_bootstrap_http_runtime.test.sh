#!/usr/bin/env bash
# Runtime HTTP negative tests against disposable local Supabase only.
# No hosted Supabase URL or Production credentials are accepted here.
set -euo pipefail

: "${API_URL:?API_URL is required}"
: "${ANON_KEY:?ANON_KEY is required}"
: "${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY is required}"

ALLOWED_ORIGIN="http://localhost:54321"
ALLOWED_USER_ID="00000000-0000-4000-8000-000000000299"
FUNCTION_URL="${API_URL}/functions/v1/owner-bootstrap"
TMP_DIR="$(mktemp -d)"
FUNCTION_PID=""

cleanup() {
  if [[ -n "$FUNCTION_PID" ]]; then
    kill "$FUNCTION_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/function.env" <<EOF
SUPABASE_URL=$API_URL
SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
OWNER_BOOTSTRAP_ALLOWED_USER_ID=$ALLOWED_USER_ID
OWNER_BOOTSTRAP_ALLOWED_ORIGIN=$ALLOWED_ORIGIN
EOF

supabase functions serve owner-bootstrap --no-verify-jwt --env-file "$TMP_DIR/function.env" >"$TMP_DIR/function.log" 2>&1 &
FUNCTION_PID=$!

ready=0
for _ in $(seq 1 40); do
  code="$(curl -sS -o "$TMP_DIR/ready.body" -w '%{http_code}' \
    -H "Origin: $ALLOWED_ORIGIN" "$FUNCTION_URL" || true)"
  if [[ "$code" == "405" ]]; then ready=1; break; fi
  sleep 1
done
if [[ "$ready" != "1" ]]; then
  cat "$TMP_DIR/function.log"
  echo "Edge Function did not become ready" >&2
  exit 1
fi

assert_status() {
  local expected="$1"; shift
  local actual
  actual="$(curl -sS -o "$TMP_DIR/response.body" -w '%{http_code}' "$@")"
  if [[ "$actual" != "$expected" ]]; then
    cat "$TMP_DIR/response.body" >&2 || true
    echo "Expected HTTP $expected, got $actual" >&2
    cat "$TMP_DIR/function.log" >&2 || true
    exit 1
  fi
}

# Wrong browser origin is rejected before any auth or RPC work.
assert_status 403 -X POST "$FUNCTION_URL" \
  -H "Origin: https://attacker.example" -H "Content-Type: application/json" -d '{}'

# CORS preflight from the exact configured origin is accepted.
assert_status 200 -X OPTIONS "$FUNCTION_URL" -H "Origin: $ALLOWED_ORIGIN"

# Unsupported methods and missing bearer credentials are rejected.
assert_status 405 -X GET "$FUNCTION_URL" -H "Origin: $ALLOWED_ORIGIN"
assert_status 401 -X POST "$FUNCTION_URL" -H "Origin: $ALLOWED_ORIGIN" -H "Content-Type: application/json" -d '{}'
assert_status 403 -X POST "$FUNCTION_URL" -H "Origin: $ALLOWED_ORIGIN" -H "Authorization: Bearer invalid-token" -H "Content-Type: application/json" -d '{}'

# Create a confirmed but non-allowlisted Auth user, then verify that a valid
# JWT alone cannot satisfy the one-user Founder bootstrap allowlist.
email="runtime-http-ci-$RANDOM@example.test"
password="CI-Only-Strong-Password-2026!"
created="$(curl -fsS "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true}")"
user_id="$(printf '%s' "$created" | jq -r '.id // empty')"
if [[ -z "$user_id" ]]; then
  echo "Could not create disposable confirmed Auth fixture" >&2
  printf '%s\n' "$created" >&2
  exit 1
fi

session="$(curl -fsS "$API_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$email\",\"password\":\"$password\"}")"
access_token="$(printf '%s' "$session" | jq -r '.access_token // empty')"
if [[ -z "$access_token" ]]; then
  echo "Could not sign in disposable Auth fixture" >&2
  printf '%s\n' "$session" >&2
  exit 1
fi

assert_status 403 -X POST "$FUNCTION_URL" \
  -H "Origin: $ALLOWED_ORIGIN" -H "Authorization: Bearer $access_token" \
  -H "Content-Type: application/json" -d '{}'

echo "Owner Bootstrap runtime HTTP negative tests passed."
