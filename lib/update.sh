#!/usr/bin/env bash

HEXTUNNEL_UPDATE_CHANNEL="${HEXTUNNEL_UPDATE_CHANNEL:-stable}"
HEXTUNNEL_UPDATE_PUBLIC_KEY="${HEXTUNNEL_UPDATE_PUBLIC_KEY:-/etc/hextunnel/update-public.pem}"
HEXTUNNEL_STABLE_MANIFEST_URL="${HEXTUNNEL_STABLE_MANIFEST_URL:-}"
HEXTUNNEL_TESTING_MANIFEST_URL="${HEXTUNNEL_TESTING_MANIFEST_URL:-}"
UPDATE_ARTIFACT_SHA256=""

update_manifest_url() {
  case "$HEXTUNNEL_UPDATE_CHANNEL" in
    stable) printf '%s' "$HEXTUNNEL_STABLE_MANIFEST_URL" ;;
    testing) printf '%s' "$HEXTUNNEL_TESTING_MANIFEST_URL" ;;
    *) die "Canal de actualización inválido: $HEXTUNNEL_UPDATE_CHANNEL" ;;
  esac
}

update_validate_url() {
  local url="$1"
  if [[ "$url" == https://* ]]; then
    return 0
  fi
  if [[ "${HEXTUNNEL_UPDATE_ALLOW_HTTP_LOOPBACK:-0}" == 1 \
    && "$url" =~ ^http://(127\.0\.0\.1|localhost)(:[0-9]+)?/ ]]; then
    return 0
  fi
  die "La actualización exige HTTPS; solo CI puede habilitar HTTP loopback."
}

update_validate_public_key() {
  [[ -s "$HEXTUNNEL_UPDATE_PUBLIC_KEY" ]] || die "Falta la clave pública de actualización: $HEXTUNNEL_UPDATE_PUBLIC_KEY"
  validate_private_env_file "$HEXTUNNEL_UPDATE_PUBLIC_KEY"
  openssl pkey -pubin -in "$HEXTUNNEL_UPDATE_PUBLIC_KEY" -noout >/dev/null 2>&1 \
    || die "La clave pública de actualización no es válida."
}

update_validate_manifest_schema() {
  local manifest="$1" channel
  jq -e '
    type == "object"
    and (.channel | type == "string")
    and (.released_at | type == "string")
    and (.components | type == "object")
    and all(.components[];
      (.version | type == "string" and length > 0)
      and (.artifacts | type == "object")
      and all(.artifacts[];
        (.url | type == "string" and length > 0)
        and (.sha256 | type == "string" and test("^[A-Fa-f0-9]{64}$"))
      )
    )
  ' "$manifest" >/dev/null || die "El manifiesto firmado no cumple el esquema requerido."
  channel="$(jq -r '.channel' "$manifest")"
  [[ "$channel" == "$HEXTUNNEL_UPDATE_CHANNEL" ]] \
    || die "El manifiesto pertenece al canal $channel, no a $HEXTUNNEL_UPDATE_CHANNEL."
}

update_fetch_verified_manifest() {
  local directory="$1" url
  url="$(update_manifest_url)"
  [[ -n "$url" ]] || die "Configura la URL del manifiesto para el canal $HEXTUNNEL_UPDATE_CHANNEL."
  update_validate_url "$url"
  update_validate_public_key
  run_cmd curl -fL --retry 3 --connect-timeout 10 -o "$directory/manifest.json" "$url"
  run_cmd curl -fL --retry 3 --connect-timeout 10 -o "$directory/manifest.sig" "${url}.sig"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  openssl dgst -sha256 -verify "$HEXTUNNEL_UPDATE_PUBLIC_KEY" \
    -signature "$directory/manifest.sig" "$directory/manifest.json" >/dev/null \
    || die "La firma del manifiesto de actualización no es válida."
  jq empty "$directory/manifest.json" >/dev/null || die "El manifiesto no es JSON válido."
  update_validate_manifest_schema "$directory/manifest.json"
}

update_manifest_artifact_fields() {
  local manifest="$1" component="$2" arch
  arch="${HEXTUNNEL_ARCH:-$(normalize_architecture)}"
  jq -r --arg component "$component" --arg arch "$arch" '
    (.components[$component].artifacts[$arch] // .components[$component].artifacts.all // empty)
    | [.url, .sha256] | @tsv
  ' "$manifest"
}

update_download_artifact() {
  local manifest="$1" component="$2" destination="$3" fields url expected actual
  fields="$(update_manifest_artifact_fields "$manifest" "$component")"
  IFS=$'\t' read -r url expected <<< "$fields"
  [[ -n "$url" && "$expected" =~ ^[A-Fa-f0-9]{64}$ ]] \
    || die "El manifiesto no contiene $component para ${HEXTUNNEL_ARCH:-$(normalize_architecture)}."
  update_validate_url "$url"
  run_cmd curl -fL --retry 3 --connect-timeout 10 -o "$destination" "$url"
  UPDATE_ARTIFACT_SHA256="${expected,,}"
  [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && return 0
  actual="$(sha256sum "$destination" | awk '{print tolower($1)}')"
  [[ "$actual" == "$UPDATE_ARTIFACT_SHA256" ]] \
    || die "El SHA-256 del componente $component no coincide."
}

update_validate_archive_paths() {
  local archive="$1" entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* && "$entry" != ../* && "$entry" != */../* && "$entry" != *'/..' ]] \
      || die "El archivo de actualización contiene una ruta insegura: $entry"
  done < <(tar -tzf "$archive")
}

update_install_xray_archive() {
  local archive="$1" expected="$2" work actual
  work="$(mktemp -d /tmp/hextunnel-update-xray.XXXXXX)"
  actual="$(sha256sum "$archive" | awk '{print tolower($1)}')"
  [[ "$actual" == "${expected,,}" ]] || { rm -rf "$work"; die "El archivo Xray cambió después de verificarse."; }
  unzip -q "$archive" -d "$work"
  [[ -x "$work/xray" || -f "$work/xray" ]] || { rm -rf "$work"; die "El artefacto firmado de Xray no contiene el binario."; }
  backup_paths /usr/local/bin/xray /usr/local/share/xray/geoip.dat /usr/local/share/xray/geosite.dat
  install -d -m 755 /usr/local/share/xray
  install -m 755 "$work/xray" /usr/local/bin/xray.new
  [[ -f "$work/geoip.dat" ]] && install -m 644 "$work/geoip.dat" /usr/local/share/xray/geoip.dat
  [[ -f "$work/geosite.dat" ]] && install -m 644 "$work/geosite.dat" /usr/local/share/xray/geosite.dat
  if [[ -s /etc/xray/config.json ]]; then
    /usr/local/bin/xray.new run -test -config /etc/xray/config.json \
      || { rm -f /usr/local/bin/xray.new; rm -rf "$work"; die "El Xray firmado rechazó la configuración actual."; }
  fi
  mv -f /usr/local/bin/xray.new /usr/local/bin/xray
  rm -rf "$work"
}

update_install_hysteria2_binary() {
  local artifact="$1" expected="$2" actual
  actual="$(sha256sum "$artifact" | awk '{print tolower($1)}')"
  [[ "$actual" == "${expected,,}" ]] || die "El binario Hysteria 2 cambió después de verificarse."
  backup_path /usr/local/bin/hysteria2
  install -m 755 "$artifact" /usr/local/bin/hysteria2.new
  /usr/local/bin/hysteria2.new version >/dev/null 2>&1 \
    || { rm -f /usr/local/bin/hysteria2.new; die "El artefacto firmado de Hysteria 2 no es ejecutable."; }
  mv -f /usr/local/bin/hysteria2.new /usr/local/bin/hysteria2
}

update_install_zivpn_binary() {
  local artifact="$1" expected="$2" actual
  actual="$(sha256sum "$artifact" | awk '{print tolower($1)}')"
  [[ "$actual" == "${expected,,}" ]] || die "El binario ZiVPN cambió después de verificarse."
  backup_path /usr/local/bin/zivpn
  install -m 755 "$artifact" /usr/local/bin/zivpn.new
  /usr/local/bin/zivpn.new --help >/dev/null 2>&1 \
    || /usr/local/bin/zivpn.new version >/dev/null 2>&1 \
    || { rm -f /usr/local/bin/zivpn.new; die "El artefacto firmado de ZiVPN no es ejecutable."; }
  mv -f /usr/local/bin/zivpn.new /usr/local/bin/zivpn
}

update_framework_from_manifest() {
  local manifest="$1" work archive root
  work="$(mktemp -d /tmp/hextunnel-update-framework.XXXXXX)"
  archive="$work/framework.tar.gz"
  update_download_artifact "$manifest" framework "$archive"
  if [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]]; then
    rm -rf "$work"
    return 0
  fi
  update_validate_archive_paths "$archive"
  mkdir -p "$work/unpacked"
  tar -xzf "$archive" -C "$work/unpacked"
  root="$(find "$work/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$root" && -f "$root/install.sh" && -f "$root/lib/common.sh" ]] \
    || { rm -rf "$work"; die "El paquete firmado del framework es inválido."; }
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
  local component="$1" work manifest version changelog artifact=""
  work="$(mktemp -d /tmp/hextunnel-update.XXXXXX)"
  update_fetch_verified_manifest "$work"
  manifest="$work/manifest.json"
  version="$(jq -r --arg component "$component" '.components[$component].version // empty' "$manifest")"
  changelog="$(jq -r --arg component "$component" '.components[$component].changelog // empty' "$manifest")"
  [[ -n "$version" ]] || { rm -rf "$work"; die "Componente desconocido en el manifiesto: $component"; }
  log_info "Actualizando $component a $version"
  [[ -z "$changelog" ]] || log_info "Cambios: $changelog"
  transaction_begin "update-$component-$version"
  trap 'transaction_fail "$?" "$BASH_LINENO" "$BASH_COMMAND"' ERR INT TERM
  case "$component" in
    framework)
      update_framework_from_manifest "$manifest"
      ;;
    xray)
      artifact="$work/xray.zip"
      update_download_artifact "$manifest" xray "$artifact"
      [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || update_install_xray_archive "$artifact" "$UPDATE_ARTIFACT_SHA256"
      xray_validate
      safe_restart_service xray "/usr/local/bin/xray run -test -config /etc/xray/config.json"
      ;;
    hysteria2)
      artifact="$work/hysteria2"
      update_download_artifact "$manifest" hysteria2 "$artifact"
      [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || update_install_hysteria2_binary "$artifact" "$UPDATE_ARTIFACT_SHA256"
      hysteria2_validate
      safe_restart_service hysteria2
      ;;
    zivpn)
      artifact="$work/zivpn"
      update_download_artifact "$manifest" zivpn "$artifact"
      [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] || update_install_zivpn_binary "$artifact" "$UPDATE_ARTIFACT_SHA256"
      zivpn_validate
      safe_restart_service zivpn "jq empty /etc/zivpn/config.json"
      ;;
    *)
      die "La actualización individual de $component no está implementada."
      ;;
  esac
  transaction_commit
  trap - ERR INT TERM
  rm -rf "$work"
  log_success "$component actualizado a $version"
}

update_show_manifest() {
  local work status=0
  work="$(mktemp -d /tmp/hextunnel-update.XXXXXX)"
  if update_fetch_verified_manifest "$work"; then
    jq '{channel, released_at, components: (.components | with_entries(.value |= {version, changelog}))}' "$work/manifest.json"
  else
    status=$?
  fi
  rm -rf "$work"
  return "$status"
}
