**English** | [العربية (الدارجة)](README.ar.md)

# PostgreSQL + pgvector for RAG with n8n (Docker)

Step-by-step notes for running **PostgreSQL with pgvector** in Docker and using it as the Vector Store for an **AI Agent / RAG** workflow in **n8n**.

## Background

- The stock `postgres:16` image does **not** ship the `vector` extension, so you get:
  ```
  ERROR: extension "vector" is not available
  ```
- Fix: run the prebuilt `pgvector/pgvector:pg16` image in a **new, separate container**.
- Your existing container (`postgres_db`) and its data stay untouched.

## Requirements

- Docker Desktop running
- n8n (local install or Docker)
- PowerShell (Windows) or any terminal

## 1) Create the container

Pull the image:

```powershell
docker pull pgvector/pgvector:pg16
```

Run the container (port `5433` avoids a clash with the old PostgreSQL on `5432`):

```powershell
docker run -d --name DB.rag --restart unless-stopped `
  -p 5433:5432 `
  -e POSTGRES_DB=rag_db `
  -e POSTGRES_USER=rag_user `
  -e POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD `
  -v DB_rag_data:/var/lib/postgresql/data `
  pgvector/pgvector:pg16
```

| Item | Value |
|---|---|
| Container | `DB.rag` |
| Database | `rag_db` |
| User | `rag_user` |
| Host port | `5433` |
| Data volume | `DB_rag_data` |

> ⚠️ Replace `CHANGE_ME_STRONG_PASSWORD` with your own strong password. **Never commit your real password to GitHub.**

## 2) Enable pgvector and create the table

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE TABLE IF NOT EXISTS documents (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), content TEXT NOT NULL, metadata JSONB DEFAULT '{}'::jsonb, embedding VECTOR(1536));"
```

`VECTOR(1536)` means each embedding has 1536 numbers (for example OpenAI `text-embedding-3-small`). If you change the embeddings model, change this number to match.

## 3) Verify

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT extname FROM pg_extension WHERE extname = 'vector';"
```

If `vector` is listed, the extension is active.

Inspect the table:

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "\d documents"
```

## 4) Connect to n8n

In n8n: **Credentials → Postgres**, then fill in:

| Field | Value |
|---|---|
| Host | `host.docker.internal` (if n8n runs in Docker) or `localhost` (if n8n is installed directly on Windows) |
| Port | `5433` |
| Database | `rag_db` |
| User | `rag_user` |
| Password | the password you chose |
| SSL | Disable (local use) |

Then use the **PGVector Vector Store** node in your workflow:

- **Insert Documents**: store documents
- **Retrieve (as Tool for AI Agent)**: let the agent search them

Important node settings:

- Table Name: `documents`
- Under **Options → Column Names**: set the Content Column to `content` (our table uses `content`, not n8n's default `text`). Keep `embedding` and `metadata` as they are.
- The Embeddings Model must output **1536 dimensions** to match `VECTOR(1536)`.

## 5) Everyday commands

```powershell
# list running containers
docker ps

# stop / start / restart
docker stop DB.rag
docker start DB.rag
docker restart DB.rag

# view logs
docker logs DB.rag --tail 50

# open psql
docker exec -it DB.rag psql -U rag_user -d rag_db
```

Useful psql commands (inside psql):

```sql
\dt                          -- list tables
\d documents                 -- table structure
SELECT count(*) FROM documents;
\q                           -- quit
```

## 6) Backup and restore

Backup:

```powershell
docker exec DB.rag pg_dump -U rag_user -d rag_db > rag_backup.sql
```

Restore:

```powershell
Get-Content rag_backup.sql | docker exec -i DB.rag psql -U rag_user -d rag_db
```

## 7) (Optional) Index for faster search

Once the table grows, add an index:

```sql
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

## 8) Remove everything (start from scratch)

```powershell
docker stop DB.rag
docker rm DB.rag
docker volume rm DB_rag_data   # permanently deletes the data!
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `extension "vector" is not available` | You are using a plain `postgres:16` image. Use `pgvector/pgvector:pg16` |
| `type "vector" does not exist` | `CREATE EXTENSION vector` was not run before creating the table |
| n8n cannot connect | Try `host.docker.internal`, or put n8n and DB.rag on the same Docker network and use `DB.rag` as the host |
| Port `5433` already in use | Change the number in `-p` and in n8n |
| Dimension mismatch | The embeddings model does not output 1536. Change `VECTOR(n)` or the model |

## Security

- Never put your real password in the README or on GitHub.
- Use a `.env` file and add it to `.gitignore`:
  ```
  POSTGRES_PASSWORD=your_strong_password
  ```
- Rotate any password that appeared in a screenshot or chat.

## docker-compose (simpler alternative)

```yaml
services:
  db-rag:
    image: pgvector/pgvector:pg16
    container_name: DB.rag
    restart: unless-stopped
    ports:
      - "5433:5432"
    environment:
      POSTGRES_DB: rag_db
      POSTGRES_USER: rag_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - DB_rag_data:/var/lib/postgresql/data

volumes:
  DB_rag_data:
```

Start it:

```powershell
docker compose up -d
```
