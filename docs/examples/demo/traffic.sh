#!/bin/sh
# Weighted traffic generator: realistic mix of consumers, user agents,
# status classes and latencies against the demo gateway.
KONG="http://kong:8000"

req() { # $1 path, $2 apikey (optional), $3 user-agent
  if [ -n "$2" ]; then
    curl -s -o /dev/null -m 5 -H "apikey: $2" -A "$3" "$KONG$1"
  else
    curl -s -o /dev/null -m 5 -A "$3" "$KONG$1"
  fi
}

echo "traffic generator started against $KONG"
i=0
while true; do
  i=$(( (i + 1) % 100 ))
  case $i in
    # ~40% payments (auth'd, fast)
    [0-3]?) if [ $((i % 2)) -eq 0 ]; then
              req /payments demo-key-mobile "acme-mobile/2.1 (iOS)"
            else
              req /payments demo-key-web "acme-web/1.4 (Mozilla/5.0)"
            fi ;;
    # ~25% orders (auth'd, slower)
    [4-6]?) req /orders demo-key-mobile "acme-mobile/2.1 (iOS)" ;;
    # ~15% auth (open, instant)
    7?)     req /auth "" "acme-web/1.4 (Mozilla/5.0)" ;;
    # ~8% inventory (500s)
    8[0-7]) req /inventory "" "sync-daemon/0.9" ;;
    # ~5% orders archive (404s)
    8[89]|9[0-2]) req /orders/archive "" "acme-web/1.4 (Mozilla/5.0)" ;;
    # ~4% legacy (unreachable upstream, 503 + retries)
    9[3-6]) req /legacy "" "sync-daemon/0.9" ;;
    # ~3% payments without a key (401s)
    9[7-9]) req /payments "" "curl/8.10" ;;
  esac
  sleep 0.3
done
