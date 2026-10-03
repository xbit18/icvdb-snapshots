#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# CARICAMENTO CONFIGURAZIONE
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERRORE: file .env non trovato."
    echo
    echo "Crea il file partendo da .env.example:"
    echo
    echo "  cp .env.example .env"
    echo
    echo "Poi configura i parametri necessari."
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ==========================================
# VALIDAZIONE CONFIGURAZIONE
# ==========================================

required_vars=(
    REPO
    DB_HOST
    DB_PORT
    DB_NAME
    DB_USER
    DB_PASSWORD
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERRORE: variabile ${var} non configurata nel file .env."
        exit 1
    fi
done

export PGPASSWORD="$DB_PASSWORD"

# ==========================================
# DATI SNAPSHOT
# ==========================================

DATE="$(date +%F)"
TAG="db-${DATE}"
ASSET="icvdb-${DATE}.dump"

WORKDIR="$(mktemp -d)"
DUMP_PATH="${WORKDIR}/${ASSET}"
CHECKSUM_PATH="${DUMP_PATH}.sha256"

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT

echo
echo "=========================================="
echo " ICVDB snapshot publisher"
echo "=========================================="
echo
echo "Repository: ${REPO}"
echo "Tag:        ${TAG}"
echo "Database:   ${DB_NAME}"
echo "Host:       ${DB_HOST}:${DB_PORT}"
echo

# ==========================================
# CONTROLLO / INSTALLAZIONE DIPENDENZE
# ==========================================

echo "==> Controllo dipendenze..."

missing=()

command -v psql >/dev/null 2>&1 || missing+=("postgresql-client")
command -v pg_dump >/dev/null 2>&1 || missing+=("postgresql-client")
command -v pg_restore >/dev/null 2>&1 || missing+=("postgresql-client")
command -v gh >/dev/null 2>&1 || missing+=("gh")
command -v sha256sum >/dev/null 2>&1 || missing+=("coreutils")

# Rimuove eventuali duplicati, ad esempio postgresql-client
if [ "${#missing[@]}" -gt 0 ]; then
    mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)

    echo
    echo "Mancano le seguenti dipendenze:"
    printf '  - %s\n' "${missing[@]}"
    echo

    if command -v apt-get >/dev/null 2>&1; then
        echo "Sistema Debian/Ubuntu rilevato."
        read -r -p "Vuoi installare automaticamente le dipendenze mancanti? [y/N] " answer

        case "$answer" in
            [yY]|[yY][eE][sS])
                echo
                echo "==> Aggiornamento indice pacchetti..."
                sudo apt-get update

                echo
                echo "==> Installazione dipendenze..."
                sudo apt-get install -y "${missing[@]}"
                ;;
            *)
                echo
                echo "Installazione annullata."
                echo "Installa manualmente:"
                echo
                echo "  sudo apt-get install ${missing[*]}"
                exit 1
                ;;
        esac
    else
        echo "Installazione automatica non supportata su questo sistema."
        echo
        echo "Installa manualmente gli equivalenti di:"
        printf '  - %s\n' "${missing[@]}"
        exit 1
    fi
fi

# Verifica finale
for cmd in psql pg_dump pg_restore gh sha256sum; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERRORE: ${cmd} non disponibile dopo il controllo dipendenze."
        exit 1
    fi
done

echo "Dipendenze OK."

# ==========================================
# CONTROLLO GITHUB
# ==========================================

echo "==> Controllo autenticazione GitHub..."

gh auth status >/dev/null || {
    echo "ERRORE: GitHub CLI non autenticata."
    echo "Eseguire:"
    echo
    echo "  gh auth login"
    exit 1
}

echo "==> Controllo repository..."

gh repo view "$REPO" >/dev/null || {
    echo "ERRORE: impossibile accedere alla repository ${REPO}."
    exit 1
}

echo "==> Controllo eventuale release esistente..."

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "ERRORE: la release ${TAG} esiste già."
    echo "Nessuna modifica effettuata."
    exit 1
fi

# ==========================================
# CONTROLLO DATABASE
# ==========================================

echo
echo "==> Controllo connessione PostgreSQL..."

if ! psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -c "SELECT 1;" \
    >/dev/null 2>&1; then

    echo "ERRORE: impossibile connettersi al database."
    exit 1
fi

echo "Connessione PostgreSQL OK."

# ==========================================
# CONTROLLO VERSIONE POSTGRESQL
# ==========================================

echo
echo "==> Controllo compatibilità versione PostgreSQL..."

SERVER_VERSION="$(
    psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -Atc "SHOW server_version;" \
    | xargs
)"

PG_DUMP_VERSION="$(pg_dump --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"

SERVER_MAJOR="${SERVER_VERSION%%.*}"
PG_DUMP_MAJOR="${PG_DUMP_VERSION%%.*}"

echo "Server PostgreSQL: ${SERVER_VERSION}"
echo "pg_dump:           ${PG_DUMP_VERSION}"

if [ "$PG_DUMP_MAJOR" -lt "$SERVER_MAJOR" ]; then
    echo
    echo "ERRORE: versione di pg_dump incompatibile."
    echo
    echo "Il server utilizza PostgreSQL ${SERVER_VERSION},"
    echo "mentre pg_dump installato è versione ${PG_DUMP_VERSION}."
    echo
    echo "pg_dump deve avere una major version uguale o superiore"
    echo "a quella del server PostgreSQL."
    echo
    echo "Installa PostgreSQL client ${SERVER_MAJOR} o una versione più recente."
    exit 1
fi

echo "Versione pg_dump compatibile."

# ==========================================
# CREAZIONE DUMP
# ==========================================

echo
echo "==> Creazione dump PostgreSQL..."

pg_dump \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -Fc \
    --no-owner \
    --no-privileges \
    -f "$DUMP_PATH"

echo
echo "==> Dump creato:"
ls -lh "$DUMP_PATH"

# ==========================================
# VERIFICA DUMP
# ==========================================

echo
echo "==> Verifica integrità dump..."

pg_restore --list "$DUMP_PATH" >/dev/null

echo "Dump PostgreSQL valido."

# ==========================================
# CHECKSUM
# ==========================================

echo
echo "==> Calcolo SHA256..."

(
    cd "$WORKDIR"
    sha256sum "$ASSET" > "${ASSET}.sha256"
)

cat "$CHECKSUM_PATH"

# ==========================================
# CREAZIONE RELEASE
# ==========================================

echo
echo "==> Creazione GitHub Release ${TAG}..."

gh release create "$TAG" \
    "$DUMP_PATH" \
    "$CHECKSUM_PATH" \
    --repo "$REPO" \
    --title "ICVDB snapshot – ${DATE}" \
    --notes "$(cat <<EOF
Snapshot PostgreSQL del database ICVDB.

Data snapshot: ${DATE}

Formato: PostgreSQL custom dump (\`pg_dump -Fc\`).

SHA256:

\`\`\`
$(cat "$CHECKSUM_PATH")
\`\`\`

Il database può essere ripristinato tramite \`pg_restore\`.
EOF
)"

# ==========================================
# VERIFICA RELEASE
# ==========================================

echo
echo "==> Verifica release..."

gh release view "$TAG" \
    --repo "$REPO"

echo
echo "=========================================="
echo " Snapshot pubblicato correttamente"
echo "=========================================="
echo
echo "Tag:  ${TAG}"
echo "File: ${ASSET}"
echo
