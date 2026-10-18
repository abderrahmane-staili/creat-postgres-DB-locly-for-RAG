# n8n + PostgreSQL + pgvector — RAG Setup Kit

A reusable reference kit for running a local PostgreSQL database with `pgvector` and connecting it to a local n8n Docker container for Retrieval-Augmented Generation (RAG).

> **Important:** This repository is a setup template and notes. It does not include the actual n8n workflow export. Export the workflow from n8n separately if you want to version-control the workflow too.

## What this setup contains

- PostgreSQL image with `pgvector` support
- Database: `rag_db`
- Database user: `rag_user`
- Vector table: `public.documents`
- Embedding column: `VECTOR(1536)`
- A Docker network named `rag-network`
- A sample PowerShell verification script

## Security

- Never commit your real `.env` file, database password, API keys, or credential exports.
- Copy `.env.example` to `.env` and use a strong unique password.
- The sample Compose file binds the database port to `127.0.0.1` so it is not directly exposed on every network interface.
- Do not expose PostgreSQL directly to the public internet.

## A. Fresh setup on a computer

These commands are for a **fresh setup**. If a container named `DB.rag` and a database volume already exist, do not run this Compose setup blindly; see “Existing setup” below.

### 1. Create the environment file

PowerShell:

```powershell
Copy-Item .env.example .env
notepad .env
```

Set `POSTGRES_PASSWORD` in `.env` to a strong, unique password. Do not commit `.env`.

### 2. Create the Docker network

```powershell
docker network create rag-network
```

If Docker says the network already exists, continue.

### 3. Start PostgreSQL with pgvector

```powershell
docker compose up -d
```

Check the container:

```powershell
docker ps
```

The first start on a new empty volume runs `sql/01_init.sql` automatically. PostgreSQL only runs scripts in `/docker-entrypoint-initdb.d` when the data directory is empty.

## B. Existing setup: connect local n8n to the database

If both containers already exist and are named `n8n` and `DB.rag`, run these only if they are not already connected to `rag-network`:

```powershell
docker network create rag-network
docker network connect rag-network n8n
docker network connect --alias db-rag rag-network DB.rag
```

If Docker reports that the network or endpoint already exists, it may already be connected. Inspect the network before retrying:

```powershell
docker network inspect rag-network
```

### n8n PostgreSQL credential values

For the **local n8n container** talking to PostgreSQL over the Docker network:

- Host: `db-rag`
- Port: `5432` (container port, not the Windows host port)
- Database: `rag_db`
- User: `rag_user`
- Password: the password set when the database was initialized
- SSL: disabled for this local Docker network

For a PostgreSQL client running directly on Windows, use host `localhost` and host port `5433` (unless you changed `POSTGRES_PORT`). These are two different connection contexts.

## C. PostgreSQL commands

### Open a psql shell

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db
```

Run these inside `psql`:

```sql
\dt
\d documents
SELECT COUNT(*) AS total_documents,
       COUNT(embedding) AS documents_with_embeddings
FROM documents;
```

Show a few chunks without printing the full embedding vector:

```sql
SELECT id,
       LEFT(text, 150) AS text_preview,
       metadata,
       embedding IS NOT NULL AS has_embedding
FROM documents
LIMIT 10;
```

Exit `psql` with:

```sql
\q
```

If query output opens in a pager showing `(END)`, press `q` to return to `psql` first.

### Run a one-line query from PowerShell

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT COUNT(*) AS total_documents, COUNT(embedding) AS documents_with_embeddings FROM documents;"
```

### Confirm the extensions

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT extname FROM pg_extension WHERE extname IN ('vector','pgcrypto');"
```

## D. Database schema

`sql/01_init.sql` creates the vector extension and a table compatible with the n8n PGVector node configuration used in this project. The expected text column is called `text` (not `content`).

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    text TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    embedding VECTOR(1536)
);
```

The embedding model must produce 1536 dimensions for this schema. For example, OpenAI `text-embedding-3-small` uses 1536 dimensions by default. If you use another embedding model or change its dimensions, update the schema and make sure all documents and queries use the same model/dimensions.

## E. n8n RAG ingestion workflow

Typical node layout:

1. Trigger or file source
2. Extract from File (for a PDF, if needed)
3. PGVector Vector Store in `Insert Documents` mode
4. Default Data Loader connected to the PGVector `Document` input
5. Embeddings model connected to the PGVector `Embedding` input

In the PGVector node, select the PostgreSQL credential and table `documents`. Execute the workflow, then verify that both counts are greater than zero:

```sql
SELECT COUNT(*) AS total_documents,
       COUNT(embedding) AS documents_with_embeddings
FROM documents;
```

The row count may be greater than one PDF because the loader can split a PDF into multiple document chunks.

## F. n8n RAG query workflow

Typical node layout:

1. Chat Trigger
2. AI Agent
3. Chat Model connected to the AI Agent's Chat Model input
4. PGVector Vector Store in `Retrieve Documents (As Tool for AI Agent)` mode connected to the Agent's Tool input
5. The same embedding model connected to the retrieval PGVector node

Use the same table (`documents`) and the same embedding model as ingestion. A sample tool description:

`Search the stored handbook for information relevant to the user's question. Use retrieved documents to answer accurately. If the information is not in the documents, say it is not specified.`

## G. Useful Docker commands

```powershell
# List running containers
docker ps

# Show all containers, including stopped ones
docker ps -a

# Show networks
docker network ls

# Inspect the RAG network
docker network inspect rag-network

# View PostgreSQL logs
docker logs DB.rag

# Restart PostgreSQL
docker restart DB.rag

# Stop PostgreSQL (does not delete its data volume)
docker stop DB.rag

# Start PostgreSQL again
docker start DB.rag
```

**Avoid `docker rm -v`, `docker volume rm`, or `docker compose down -v` unless you intentionally want to delete the database data.**

## H. Push these files to GitHub

Create an empty repository on GitHub first, then from this folder run:

```powershell
git init
git add .
git commit -m "Add n8n RAG Docker setup kit"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/n8n-rag-docker-kit.git
git push -u origin main
```

Replace `YOUR-USERNAME` with your GitHub username and use the actual repository URL. If `origin` is already configured, check it with `git remote -v` instead of adding it again.
