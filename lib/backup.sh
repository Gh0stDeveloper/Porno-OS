#!/usr/bin/env bash
transaction_path_key() { printf '%s' "$1" | sed 's#^/##; s#/#__#g'; }
backup_path() { local path="$1" key manifest backup; [[ -n "${HEXTUNNEL_TRANSACTION_DIR:-}" ]] || return 0; [[ "${HEXTUNNEL_DRY_RUN:-0}" == 1 ]] && { log_dry "respaldar $path"; return 0; }; key="$(transaction_path_key "$path")"; manifest="$HEXTUNNEL_TRANSACTION_DIR/files.manifest"; backup="$HEXTUNNEL_TRANSACTION_DIR/files/$key"; grep -Fq "|$path|" "$manifest" 2>/dev/null && return 0; mkdir -p "$HEXTUNNEL_TRANSACTION_DIR/files"; if [[ -e "$path" || -L "$path" ]]; then cp -a -- "$path" "$backup"; printf 'EXISTS|%s|%s\n' "$path" "$key" >> "$manifest"; else printf 'MISSING|%s|%s\n' "$path" "$key" >> "$manifest"; fi; }
backup_paths() { local path; for path in "$@"; do backup_path "$path"; done; }
