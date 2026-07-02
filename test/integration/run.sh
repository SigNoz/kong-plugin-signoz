#!/usr/bin/env bash
# Integration matrix for kong-plugin-signoz.
#
#   KONG_VERSION=3.9 test/integration/run.sh
#
# Layers:
#   1. schema  — kong config parse accepts the valid fixture, rejects
#                grpc:// endpoints and the removed instrumentations field
#   2. e2e     — real gateway + echo upstream + OTLP sink: traces and logs
#                must arrive with the full attribute set, zero queue errors
#   3. guards  — tracer-off misconfiguration must warn exactly once
set -euo pipefail

KONG_VERSION="${KONG_VERSION:-3.9}"
IMG="kong:${KONG_VERSION}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="$ROOT/test/integration/fixtures"
SUFFIX="$$"
NET="signoz-it-$SUFFIX"

RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
FAILURES=0

pass() { echo "${GREEN}ok${RESET}    $1"; }
fail() { echo "${RED}FAIL${RESET}  $1"; FAILURES=$((FAILURES + 1)); }

cleanup() {
  docker rm -f "it-kong-$SUFFIX" "it-sink-$SUFFIX" "it-echo-$SUFFIX" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kong_parse() {
  docker run --rm \
    -v "$ROOT/kong:/custom/kong:ro" \
    -v "$1:/kong.yml:ro" \
    -e KONG_DATABASE=off \
    -e KONG_PLUGINS=bundled,signoz \
    -e KONG_LUA_PACKAGE_PATH='/custom/?.lua;/custom/?/init.lua;;' \
    "$IMG" kong config parse /kong.yml >/dev/null 2>&1
}

echo "=== kong-plugin-signoz integration • Kong $KONG_VERSION ==="

# --- 1. schema ---------------------------------------------------------------
if kong_parse "$FIX/kong-valid.yml"; then
  pass "schema: valid config parses"
else
  fail "schema: valid config parses"
fi

if kong_parse "$FIX/kong-invalid-grpc.yml"; then
  fail "schema: grpc:// endpoint rejected"
else
  pass "schema: grpc:// endpoint rejected"
fi

if kong_parse "$FIX/kong-invalid-instrumentations.yml"; then
  fail "schema: removed logs.instrumentations rejected"
else
  pass "schema: removed logs.instrumentations rejected"
fi

# --- 2. e2e ------------------------------------------------------------------
docker network create "$NET" >/dev/null

docker run -d --name "it-sink-$SUFFIX" --network "$NET" --network-alias sink \
  -v "$ROOT/test/integration/otlp_sink.py:/sink.py:ro" \
  python:3.12-alpine python /sink.py >/dev/null

docker run -d --name "it-echo-$SUFFIX" --network "$NET" --network-alias echo \
  -e HTTP_PORT=8080 mendhak/http-https-echo:34 >/dev/null

docker run -d --name "it-kong-$SUFFIX" --network "$NET" --network-alias kong \
  -v "$ROOT/kong:/custom/kong:ro" \
  -v "$FIX/kong-valid.yml:/kong/declarative/kong.yml:ro" \
  -e KONG_DATABASE=off \
  -e KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml \
  -e KONG_PLUGINS=bundled,signoz \
  -e KONG_LUA_PACKAGE_PATH='/custom/?.lua;/custom/?/init.lua;;' \
  -e KONG_TRACING_INSTRUMENTATIONS=all \
  -e KONG_TRACING_SAMPLING_RATE=1.0 \
  -e KONG_LOG_LEVEL=notice \
  "$IMG" >/dev/null

# wait for the proxy to answer
for _ in $(seq 1 30); do
  if docker exec "it-kong-$SUFFIX" kong health >/dev/null 2>&1; then break; fi
  sleep 1
done
sleep 3

docker run --rm --network "$NET" curlimages/curl:8.10.1 \
  -s -o /dev/null -A "it-agent/1.0" http://kong:8000/payments
docker run --rm --network "$NET" curlimages/curl:8.10.1 \
  -s -o /dev/null http://kong:8000/broken
sleep 6  # queue max_coalescing_delay is 3s

SINK_LOGS="$(docker logs "it-sink-$SUFFIX" 2>&1)"
KONG_LOGS="$(docker logs "it-kong-$SUFFIX" 2>&1)"

echo "$SINK_LOGS" | grep -q "== POST /v1/traces" \
  && pass "e2e: traces delivered" || fail "e2e: traces delivered"
echo "$SINK_LOGS" | grep -q "== POST /v1/logs" \
  && pass "e2e: logs delivered" || fail "e2e: logs delivered"

for key in \
  kong.latency.gateway_ms kong.latency.total_ms \
  kong.request.size kong.response.size \
  http.route user_agent.original error.type \
  kong.service.name service.version message.type
do
  echo "$SINK_LOGS" | grep -q "$key" \
    && pass "e2e: attribute $key" || fail "e2e: attribute $key"
done

if echo "$KONG_LOGS" | grep -qiE "could not process|traceback|signoz.*\[error\]"; then
  fail "e2e: no plugin/queue errors"
else
  pass "e2e: no plugin/queue errors"
fi

docker rm -f "it-kong-$SUFFIX" >/dev/null

# --- 3. guards ---------------------------------------------------------------
docker run -d --name "it-kong-$SUFFIX" --network "$NET" \
  -v "$ROOT/kong:/custom/kong:ro" \
  -v "$FIX/kong-valid.yml:/kong/declarative/kong.yml:ro" \
  -e KONG_DATABASE=off \
  -e KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml \
  -e KONG_PLUGINS=bundled,signoz \
  -e KONG_LUA_PACKAGE_PATH='/custom/?.lua;/custom/?/init.lua;;' \
  -e KONG_TRACING_INSTRUMENTATIONS=off \
  "$IMG" >/dev/null
for _ in $(seq 1 30); do
  if docker exec "it-kong-$SUFFIX" kong health >/dev/null 2>&1; then break; fi
  sleep 1
done
sleep 3

WARNS="$(docker logs "it-kong-$SUFFIX" 2>&1 | grep -c 'gateway tracer is off' || true)"
if [ "$WARNS" -eq 1 ]; then
  pass "guards: tracer-off warns exactly once (got $WARNS)"
else
  fail "guards: tracer-off warns exactly once (got $WARNS)"
fi

# --- summary -----------------------------------------------------------------
echo
if [ "$FAILURES" -gt 0 ]; then
  echo "${RED}$FAILURES check(s) failed on Kong $KONG_VERSION${RESET}"
  exit 1
fi
echo "${GREEN}all checks passed on Kong $KONG_VERSION${RESET}"
