# ICVDB Snapshots

Repository dedicata alla pubblicazione degli snapshot PostgreSQL di ICVDB.

Gli snapshot vengono pubblicati come GitHub Releases e sono pensati per essere consumati da progetti self-hosted come `icvdb-torznab`.

## Struttura

La repository contiene principalmente:

```text
publish_snapshot.sh
.env.example
README.md
LICENSE.md
```

I dump del database non vengono committati nel repository Git.

Ogni snapshot viene invece pubblicato come asset di una GitHub Release.

## Configurazione

Copia il file di esempio:

```bash
cp .env.example .env
```

Poi modifica `.env`:

```env
REPO=xbit18/icvdb-snapshots

DB_HOST=localhost
DB_PORT=5432
DB_NAME=icv_db
DB_USER=icv
DB_PASSWORD=change-me
```

Il file `.env` non deve essere committato.

## Pubblicazione di uno snapshot

Rendi eseguibile lo script, se necessario:

```bash
chmod +x publish_snapshot.sh
```

Poi esegui:

```bash
./publish_snapshot.sh
```

Lo script:

1. controlla le dipendenze necessarie;
2. verifica l'autenticazione GitHub;
3. verifica la connessione PostgreSQL;
4. crea un dump con `pg_dump -Fc`;
5. verifica il dump con `pg_restore --list`;
6. calcola lo SHA256;
7. crea una GitHub Release;
8. carica dump e checksum come asset;
9. verifica che la nuova release sia disponibile correttamente.

## Formato delle release

Ogni release usa questo formato:

```text
Tag:
db-YYYY-MM-DD

Titolo:
ICVDB snapshot – YYYY-MM-DD
```

Asset:

```text
icvdb-YYYY-MM-DD.dump
icvdb-YYYY-MM-DD.dump.sha256
```

Esempio:

```text
db-2026-10-03

├── icvdb-2026-10-03.dump
└── icvdb-2026-10-03.dump.sha256
```

## Latest release

La release più recente è recuperabile tramite GitHub API:

```text
https://api.github.com/repos/xbit18/icvdb-snapshots/releases/latest
```

Questo endpoint è pensato per essere utilizzato da client automatici, ad esempio dall'updater di `icvdb-torznab`.

La risposta contiene informazioni come:

```json
{
  "tag_name": "db-2026-10-03",
  "assets": [
    {
      "name": "icvdb-2026-10-03.dump",
      "browser_download_url": "https://github.com/..."
    }
  ]
}
```

## Ripristino di uno snapshot

Uno snapshot può essere ripristinato con:

```bash
pg_restore \
  -U USER \
  -d DATABASE \
  --no-owner \
  --no-privileges \
  icvdb-YYYY-MM-DD.dump
```

## Dipendenze

Lo script utilizza:

```text
bash
pg_dump
pg_restore
psql
gh
sha256sum
```

Su Debian/Ubuntu le principali dipendenze corrispondono a:

```text
postgresql-client
gh
coreutils
```

Lo script verifica automaticamente la presenza degli strumenti richiesti e può proporre l'installazione dei pacchetti mancanti sui sistemi Debian/Ubuntu.

## Compatibilità della versione PostgreSQL

La versione di `pg_dump` utilizzata dallo script deve essere **uguale o più recente della major version del server PostgreSQL** da cui viene creato lo snapshot.

Esempi:

```text
Server PostgreSQL 14 + pg_dump 16 → OK
Server PostgreSQL 16 + pg_dump 16 → OK
Server PostgreSQL 16 + pg_dump 14 → NON supportato

## Sicurezza

Non inserire password o credenziali direttamente nello script.

Le credenziali PostgreSQL devono essere configurate tramite `.env`.

Il file `.env` è escluso da Git tramite `.gitignore`.

## Note

Gli snapshot vengono distribuiti tramite GitHub Releases per evitare di inserire file binari di grandi dimensioni nella Git history.

La repository contiene solo gli strumenti necessari alla creazione e pubblicazione degli snapshot.

## Licenza

MIT