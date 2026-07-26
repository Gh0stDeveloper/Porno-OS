#!/usr/bin/env bash

HEXTUNNEL_UPDATE_CHANNEL="${HEXTUNNEL_UPDATE_CHANNEL:-stable}"
HEXTUNNEL_UPDATE_PUBLIC_KEY="${HEXTUNNEL_UPDATE_PUBLIC_KEY:-/etc/hextunnel/update-public.pem}"
HEXTUNNEL_STABLE_MANIFEST_URL="${HEXTUNNEL_STABLE_MANIFEST_URL:-}"
HEXTUNNEL_TESTING_MANIFEST_URL="${HEXTUNNEL_TESTING_MANIFEST_URL:-}"

update_manifest_url() {
  case "$HEXTUNNEL_UPDATE_CHANNEL" in
    stable) printf '%s' "$HEXTUNNEL_STABLE_MANIFEST_URL" ;;
    testing) printf '%s' "$HEXTUNNEL_TESTING_MANIFEST_URL" ;;
    *) die "Canal de actualización inválido: $HEXTUNNEL_UPDATE_CHANNEL" ;;
  esac
}

update_fetch_verified_manifest() {
  local directory="$1" url signature
  url="$(update_manifest_url)"
  [[ -n "$url" ]] || die "Configura la URL del manifiesto para el canal $HEXTUNNEL_UPDATE_CHANNEL."
  [[ -s "$HEXTUNNEL_UPDATE_PUBLIC_KEY" ]] || die "Falta la clave pública de actualización: $HEXTUNNEL_UPDATE_PUBLIC_KEY"
  run_cmd curl -fL --retry 3 -o "$directory/manifest.json" "$url"
  run_cmd curl -fL --retry 3 -o "$directory/manifest.sig" "${url}.sig"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  openssl dgst -sha256 -verify "$HEXTUNNEL_UPDATE_PUBLIC_KEY" -signature "$directory/manifest.sig" "$directory/manifest.json" >/dev/null || die "La firma del manifiesto de actualización no es válida."
  jq empty "$directory/manifest.json" || die "El manifiesto no es JSON válido."
}

update_download_artifact() {
  local manifest="$1" component="$2" destination="$3" arch url expected actual
  arch="${HEXTUNNEL_ARCH:-$(normalize_architecture)}"
  url="$(jq -r --arg component "$component" --arg arch "$arch" '.components[$component].artifacts[$arch].url // .components[$component].artifacts.all.url // empty' "$manifest")"
  expected="$(jq -r --arg component "$component" --arg arch "$arch" '.components[$component].artifacts[$arch].sha256 // .components[$component].artifacts.all.sha256 // empty' "$manifest")"
  [[ -n "$url" && -n "$expected" ]] || die "El manifiesto no contiene $component para $arch."
  run_cmd curl -fL --retry 3 -o "$destination" "$url"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  actual="$(sha256sum "$destination" | awk '{print tolower($1)}')"
  [[ "$actual" == "${expected,,}" ]] || die "El SHA-256 del componente $component no coincide."
}

update_framework_from_manifest() {
  local manifest="$1" work archive root
  work="$(mktemp -d /tmp/hextunnel-update-framework.XXXXXX)"
  archive="$work/framework.tar.gz"
  update_download_artifact "$manifest" framework "$archive"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  mkdir -p "$work/unpacked"
  tar -xzf "$archive" -C "$work/unpacked"
  root="$(find "$work/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$root" && -f "$root/install.sh" && -f "$root/lib/common.sh" ]] || die "El paquete del framework es inválido."
  bash -n "$root/install.sh"
  while IFS= read -r -d '' file; do bash -n "$file"; done < <(find "$root" -type f -name '*.sh' -print0)
  backup_path "$HEXTUNNEL_INSTALL_DIR"
  rm -rf "$HEXTUNNEL_INSTALL_DIR"
  install -d -m 755 "$HEXTUNNEL_INSTALL_DIR"
  tar -C "$root" --exclude=.git -cf - . | tar -C "$HEXTUNNEL_INSTALL_DIR" -xf -
  chmod 755 "$HEXTUNNEL_INSTALL_DIR/install.sh" "$HEXTUNNEL_INSTALL_DIR"/bin/*
  rm -rf "$work"
}

update_component() {
  local component="$1" work manifest version changelog
  work="$(mktemp -d /tmp/hextunnel-update.XXXXXX)"
  trap 'rm -rf "${work:-}"' RETURN
  update_fetch_verified_manifest "$work"
  manifest="$work/manifest.json"
  version="$(jq -r --arg component "$component" '.components[$component].version // empty' "$manifest")"
  changelog="$(jq -r --arg component "$component" '.components[$component].changelog // empty' "$manifest")"
  [[ -n "$version" ]] || die "Componente desconocido en el manifiesto: $component"
  log_info "Actualizando $component a $version"
  [[ -z "$changelog" ]] || log_info "Cambios: $changelog"
  transaction_begin "update-$component-$version"
  trap 'transaction_fail "$?" "$BASH_LINENO" "$BASH_COMMAND"' ERR INT TERM
  case "$component" in
    framework) update_framework_from_manifest "$manifest" ;;
    xray) xray_install_verified_binary; xray_validate; safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json" ;;
    hysteria2) hysteria2_install_binary; hysteria2_validate; safe_restart_service hysteria2 ;;
    zivpn) zivpn_install_binary; zivpn_validate; safe_restart_service zivpn "jq empty /etc/zivpn/config.json" ;;
    *) die "La actualización individual de $component no está implementada." ;;
  esac
  transaction_commit
  trap - ERR INT TERM
  log_success "$component actualizado a $version"
}

update_show_manifest() {
  local work
  work="$(mktemp -d /tmp/hextunnel-update.XXXXXX)"
  update_fetch_verified_manifest "$work"
  jq '{channel, released_at, components: (.components | with_entries(.value |= {version, changelog}))}' "$work/manifest.json"
  rm -rf "$work"
}
