#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT="${1:-$ROOT/config/component-lock.env}"
WORK="$(mktemp -d /tmp/hextunnel-component-lock.XXXXXX)"
trap 'rm -rf "${WORK:-}"' EXIT
mkdir -p "$(dirname "$OUTPUT")"

UDP_REF="${HEXTUNNEL_LOCK_UDP_REF:-d7bb82abb6b36f1320bc349f36c0746b335a9ff9}"
SLOWDNS_REF="${HEXTUNNEL_LOCK_SLOWDNS_REF:-b667b0d15be0589cd89cd2f997873296ceb07ce2}"
BADVPN_REF="${HEXTUNNEL_LOCK_BADVPN_REF:-1.999.130}"
SINGBOX_VERSION="${HEXTUNNEL_LOCK_SINGBOX_VERSION:-1.12.22}"
ZIVPN_VERSION="${HEXTUNNEL_LOCK_ZIVPN_VERSION:-udp-zivpn_1.4.9}"

UDP_URL="https://raw.githubusercontent.com/mahpud896/UDP-Custom/${UDP_REF}/bin/udp-custom-linux-amd64"
SLOWDNS_URL="https://raw.githubusercontent.com/fisabiliyusri/SLDNS/${SLOWDNS_REF}/slowdns/sldns-server"
BADVPN_URL="https://codeload.github.com/ambrop72/badvpn/tar.gz/refs/tags/${BADVPN_REF}"

fetch() {
  local url="$1" output="$2"
  curl -fL --retry 4 --retry-all-errors --connect-timeout 15 --max-time 300 \
    -H 'Accept: application/octet-stream' \
    -o "$output" "$url"
  [[ -s "$output" ]] || { printf 'ERROR: descarga vacía: %s\n' "$url" >&2; exit 1; }
}

release_asset() {
  local repository="$1" tag="$2" asset="$3" output="$4" metadata url api_digest actual
  metadata="$(curl -fsSL --retry 4 --retry-all-errors \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repository}/releases/tags/${tag}")"
  url="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' <<< "$metadata" | head -n1)"
  api_digest="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | (.digest // empty)' <<< "$metadata" | head -n1)"
  [[ -n "$url" && "$url" != null ]] || { printf 'ERROR: falta %s en %s %s\n' "$asset" "$repository" "$tag" >&2; exit 1; }
  fetch "$url" "$output"
  actual="$(sha256sum "$output" | awk '{print tolower($1)}')"
  if [[ "$api_digest" == sha256:* && "${api_digest#sha256:}" != "$actual" ]]; then
    printf 'ERROR: digest de GitHub no coincide para %s\n' "$asset" >&2
    exit 1
  fi
  printf '%s\t%s\n' "$url" "$actual"
}

emit_default() {
  local name="$1" value="$2"
  printf '%s="${%s:-%s}"\n' "$name" "$name" "$(printf '%q' "$value")"
}

fetch "$UDP_URL" "$WORK/udp-custom"
UDP_SHA="$(sha256sum "$WORK/udp-custom" | awk '{print tolower($1)}')"
fetch "$SLOWDNS_URL" "$WORK/sldns-server"
SLOWDNS_SHA="$(sha256sum "$WORK/sldns-server" | awk '{print tolower($1)}')"
fetch "$BADVPN_URL" "$WORK/badvpn.tar.gz"
BADVPN_SHA="$(sha256sum "$WORK/badvpn.tar.gz" | awk '{print tolower($1)}')"

IFS=$'\t' read -r SINGBOX_URL SINGBOX_SHA < <(
  release_asset SagerNet/sing-box "v${SINGBOX_VERSION}" \
    "sing-box_${SINGBOX_VERSION}_linux_amd64.deb" "$WORK/sing-box.deb"
)
IFS=$'\t' read -r ZIVPN_AMD64_URL ZIVPN_AMD64_SHA < <(
  release_asset zahidbd2/udp-zivpn "$ZIVPN_VERSION" \
    udp-zivpn-linux-amd64 "$WORK/zivpn-amd64"
)
IFS=$'\t' read -r ZIVPN_ARM64_URL ZIVPN_ARM64_SHA < <(
  release_asset zahidbd2/udp-zivpn "$ZIVPN_VERSION" \
    udp-zivpn-linux-arm64 "$WORK/zivpn-arm64"
)

{
  printf '%s\n' '# Generado por scripts/resolve-component-lock.sh. No editar manualmente.'
  printf '%s\n' '# Se carga como valores predeterminados; el entorno o /etc/hextunnel/hextunnel.env pueden anularlos.'
  printf '%s\n' 'HEXTUNNEL_COMPONENT_LOCK_VERSION=1'
  emit_default HEXTUNNEL_UDP_CUSTOM_REF "$UDP_REF"
  emit_default HEXTUNNEL_UDP_CUSTOM_BINARY_URL "$UDP_URL"
  emit_default HEXTUNNEL_UDP_CUSTOM_SHA256 "$UDP_SHA"
  emit_default HEXTUNNEL_SLOWDNS_REF "$SLOWDNS_REF"
  emit_default HEXTUNNEL_SLOWDNS_BINARY_URL "$SLOWDNS_URL"
  emit_default HEXTUNNEL_SLOWDNS_SHA256 "$SLOWDNS_SHA"
  emit_default HEXTUNNEL_BADVPN_REF "$BADVPN_REF"
  emit_default HEXTUNNEL_BADVPN_SOURCE_URL "$BADVPN_URL"
  emit_default HEXTUNNEL_BADVPN_SHA256 "$BADVPN_SHA"
  emit_default HEXTUNNEL_SINGBOX_VERSION "$SINGBOX_VERSION"
  emit_default HEXTUNNEL_SINGBOX_BINARY_URL "$SINGBOX_URL"
  emit_default HEXTUNNEL_SINGBOX_SHA256 "$SINGBOX_SHA"
  emit_default HEXTUNNEL_ZIVPN_VERSION "$ZIVPN_VERSION"
  emit_default HEXTUNNEL_ZIVPN_AMD64_BINARY_URL "$ZIVPN_AMD64_URL"
  emit_default HEXTUNNEL_ZIVPN_AMD64_SHA256 "$ZIVPN_AMD64_SHA"
  emit_default HEXTUNNEL_ZIVPN_ARM64_BINARY_URL "$ZIVPN_ARM64_URL"
  emit_default HEXTUNNEL_ZIVPN_ARM64_SHA256 "$ZIVPN_ARM64_SHA"
  # Compatibilidad con instalaciones y herramientas que todavía leen las variables genéricas.
  emit_default HEXTUNNEL_ZIVPN_BINARY_URL "$ZIVPN_AMD64_URL"
  emit_default HEXTUNNEL_ZIVPN_SHA256 "$ZIVPN_AMD64_SHA"
} > "$OUTPUT"
chmod 600 "$OUTPUT"

bash -n "$OUTPUT"
grep -Eq '^HEXTUNNEL_COMPONENT_LOCK_VERSION=1$' "$OUTPUT"
for sha in \
  "$UDP_SHA" "$SLOWDNS_SHA" "$BADVPN_SHA" "$SINGBOX_SHA" \
  "$ZIVPN_AMD64_SHA" "$ZIVPN_ARM64_SHA"; do
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { printf 'ERROR: lock contiene SHA-256 inválido\n' >&2; exit 1; }
done

printf 'Component lock: %s\n' "$OUTPUT"
cat "$OUTPUT"
