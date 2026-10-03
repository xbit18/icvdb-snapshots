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

## Utilizzo

### 1. Clona la repository

```bash
git clone https://github.com/xbit18/icvdb-snapshots.git
cd icvdb-snapshots
```

### 2. Crea il file di configurazione

Copia il file di esempio:

```bash
cp .env.example .env
```

Apri `.env` e configura la connessione al database PostgreSQL:

```env
REPO=xbit18/icvdb-snapshots

DB_HOST=localhost
DB_PORT=5432
DB_NAME=icv_db
DB_USER=icv
DB_PASSWORD=change-me
```

`REPO` indica la repository GitHub sulla quale verranno pubblicati gli snapshot.

Le variabili `DB_*` devono puntare al database ICVDB da esportare.

Il file `.env` è escluso da Git e non deve essere committato.

### 3. Rendi eseguibile lo script

Solo al primo utilizzo:

```bash
chmod +x publish_snapshot.sh
```

### 4. Autenticazione GitHub

Prima di eseguire lo script, assicurati di essere autenticato a Github tramite Github CLI

Esegui:

```bash
gh auth login
```

L'account utilizzato deve avere permessi di scrittura sulla repository indicata da `REPO`.


### 5. Avvia la pubblicazione

```bash
./publish_snapshot.sh
```

Lo script esegue automaticamente:

```text
controllo dipendenze
        ↓
controllo autenticazione GitHub
        ↓
controllo connessione PostgreSQL
        ↓
controllo compatibilità pg_dump
        ↓
creazione dump PostgreSQL
        ↓
verifica dump
        ↓
calcolo SHA256
        ↓
creazione GitHub Release
        ↓
upload dump + checksum
```

Se alcune dipendenze non sono installate e il sistema utilizza Debian/Ubuntu, lo script può proporne automaticamente l'installazione.

### 6. Risultato

Per uno snapshot creato il `2026-10-03` verrà pubblicata automaticamente una release:

```text
Tag:    db-2026-10-03
Titolo: ICVDB snapshot – 2026-10-03
```

contenente:

```text
icvdb-2026-10-03.dump
icvdb-2026-10-03.dump.sha256
```

Il dump viene generato nel formato PostgreSQL custom (`pg_dump -Fc`) e può essere ripristinato tramite `pg_restore`.

Lo script non modifica il database sorgente e i file temporanei generati durante la procedura vengono eliminati automaticamente al termine.

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

Questo endpoint può essere utilizzato da client automatici, ad esempio dall'updater di `icvdb-torznab`.

La risposta contiene informazioni come:

```json
{
  "tag_name": "db-2026-10-03",
  "assets": [
    {
      "name": "icvdb-2026-10-03.dump",
      "size": 340000000,
      "digest": "sha256:...",
      "browser_download_url": "https://github.com/..."
    }
  ]
}
```

Il client può quindi:

```text
leggere tag_name
        ↓
confrontarlo con la versione locale
        ↓
scaricare il nuovo dump se necessario
        ↓
verificare il checksum
        ↓
ripristinare il database
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

Se il database si trova su un host o una porta specifici:

```bash
pg_restore \
  -h HOST \
  -p PORT \
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
psql
pg_dump
pg_restore
gh
sha256sum
```

Su Debian/Ubuntu le principali dipendenze corrispondono a:

```text
postgresql-client
gh
coreutils
```

Lo script verifica automaticamente la presenza degli strumenti richiesti.

Se alcune dipendenze risultano mancanti e il sistema utilizza Debian/Ubuntu, può proporne automaticamente l'installazione tramite `apt`.

## Compatibilità della versione PostgreSQL

La versione di `pg_dump` utilizzata dallo script deve essere **uguale o più recente della major version del server PostgreSQL** da cui viene creato lo snapshot.

Esempi:

```text
Server PostgreSQL 14 + pg_dump 16 → OK
Server PostgreSQL 16 + pg_dump 16 → OK
Server PostgreSQL 16 + pg_dump 14 → NON supportato
```

Lo script controlla automaticamente la versione del server e quella di `pg_dump` prima di creare il dump.

In caso di incompatibilità interrompe l'esecuzione mostrando un messaggio esplicativo.

## Sicurezza

Non inserire password o credenziali direttamente nello script.

Le credenziali PostgreSQL devono essere configurate tramite `.env`.

Il file `.env` è escluso da Git tramite `.gitignore`.

Anche dump, backup e checksum locali devono rimanere fuori dalla Git history.

## Note

Gli snapshot vengono distribuiti tramite GitHub Releases per evitare di inserire file binari di grandi dimensioni nella Git history.

La repository contiene soltanto gli strumenti necessari alla creazione e pubblicazione degli snapshot.

La release GitHub più recente rappresenta lo snapshot da utilizzare come riferimento per i client automatici.

## Licenza

MIT