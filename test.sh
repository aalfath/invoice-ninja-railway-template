#!/bin/bash
# Usage: test.sh <base_url> <email> <password> [stage]   stage=full (default) or check
B="$1"; E="$2"; P="$3"; STAGE="${4:-full}"
j(){ if command -v php >/dev/null; then php -r '$j=json_decode(stream_get_contents(STDIN),true); foreach(explode(".",$argv[1]) as $k){ $j=$j[$k]??null; } echo is_scalar($j)?$j:json_encode($j);' "$1"; else jq -r "$(echo ".$1" | sed -E 's/\.([0-9]+)/[\1]/g') // empty"; fi; }
H=(-H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest')
echo "health: $(curl -s $B/health)"
echo "GET / -> $(curl -s -o /tmp/idx.html -w '%{http_code}' $B/)"
A=$(grep -o -E '(src|href)="/[^"]+\.(js|css)"' /tmp/idx.html | head -1 | sed -E 's/.*="([^"]+)"/\1/')
echo "asset $A -> $(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$B$A")"
echo "GET /setup -> $(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' $B/setup)"
echo "bad login -> $(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -d "{\"email\":\"$E\",\"password\":\"wrong-password\"}" $B/api/v1/login)"
L=$(curl -s "${H[@]}" -d "{\"email\":\"$E\",\"password\":\"$P\"}" $B/api/v1/login)
T=$(echo "$L" | j data.0.token.token); echo "login token: ${T:0:6}… (len ${#T})"
[ -z "$T" ] && { echo "LOGIN FAILED: ${L:0:300}"; exit 1; }
A=(-H "X-API-TOKEN: $T")
if [ "$STAGE" = full ]; then
  C=$(curl -s "${H[@]}" "${A[@]}" -d '{"name":"Railway Test Client","contacts":[{"first_name":"Rail","last_name":"Way","email":"client@example.com"}]}' $B/api/v1/clients)
  CID=$(echo "$C" | j data.id); echo "client id: $CID"
  I=$(curl -s "${H[@]}" "${A[@]}" -d "{\"client_id\":\"$CID\",\"line_items\":[{\"product_key\":\"Hosting\",\"notes\":\"Railway test line\",\"cost\":123.45,\"quantity\":2}]}" $B/api/v1/invoices)
  IID=$(echo "$I" | j data.id); echo "invoice id: $IID number: $(echo "$I" | j data.number) amount: $(echo "$I" | j data.amount)"
  curl -s -o /dev/null "${H[@]}" "${A[@]}" -d "{\"action\":\"mark_sent\",\"ids\":[\"$IID\"]}" $B/api/v1/invoices/bulk
fi
IL=$(curl -s "${H[@]}" "${A[@]}" "$B/api/v1/invoices?per_page=5&include=invitations")
echo "invoices: $(echo "$IL" | j meta.pagination.total) clients: $(curl -s "${H[@]}" "${A[@]}" "$B/api/v1/clients" | j meta.pagination.total)"
IID=$(echo "$IL" | j data.0.id); KEY=$(echo "$IL" | j data.0.invitations.0.key); echo "status_id: $(echo "$IL" | j data.0.status_id)"
curl -s -o /tmp/inv.pdf -w "PDF download -> %{http_code} %{content_type} %{size_download} bytes\n" "${A[@]}" -H 'X-Requested-With: XMLHttpRequest' "$B/api/v1/invoices/$IID/download"
echo "pdf magic: $(head -c5 /tmp/inv.pdf)"
U=$(curl -s -o /tmp/portal.html -c /tmp/cj -b /tmp/cj -L -w '%{http_code} %{url_effective}' "$B/client/invoice/$KEY")
echo "portal link -> $U"; echo "portal mentions invoice: $(grep -c -i 'invoice' /tmp/portal.html) lines; https links: $(grep -o 'https://[^"/]*' /tmp/portal.html | sort -u | head -3 | tr '\n' ' ')"
TOK=$(grep -o -E 'name="csrf-token" content="[^"]+"' /tmp/portal.html | sed -E 's/.*content="([^"]+)"/\1/')
curl -s -o /tmp/p2.pdf -b /tmp/cj -c /tmp/cj -w "portal PDF download -> %{http_code} %{content_type} %{size_download} bytes, magic " -d "_token=$TOK&invoices[]=$IID" "$B/client/invoices/download"; head -c5 /tmp/p2.pdf; echo
if [ "$STAGE" = full ]; then
  CID=$(curl -s "${H[@]}" "${A[@]}" "$B/api/v1/clients" | j data.0.id)
  printf 'railway-persistence-check %s\n' "$(date -u +%FT%TZ)" > /tmp/persist.txt
  echo "upload doc -> $(curl -s -o /dev/null -w '%{http_code}' "${A[@]}" -H 'X-Requested-With: XMLHttpRequest' -F _method=PUT -F 'documents[]=@/tmp/persist.txt;type=text/plain' "$B/api/v1/clients/$CID/upload")"
fi
DID=$(curl -s "${H[@]}" "${A[@]}" "$B/api/v1/documents" | j data.0.id)
echo "document $DID -> $(curl -s "${A[@]}" -H 'X-Requested-With: XMLHttpRequest' "$B/api/v1/documents/$DID/download")"
