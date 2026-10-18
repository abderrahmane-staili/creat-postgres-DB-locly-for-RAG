# PostgreSQL / Docker command cheatsheet (PowerShell)

## Connect to PostgreSQL

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db
```

## Inside psql

```sql
\l                  -- list databases
\dt                 -- list tables in current schema
\d documents        -- describe documents table
SELECT COUNT(*) FROM documents;
SELECT COUNT(embedding) FROM documents;
\q                  -- exit psql
```

If output shows `(END)`, press `q` to close the pager.

## Run a query without opening psql

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT COUNT(*) AS total_documents, COUNT(embedding) AS documents_with_embeddings FROM documents;"
```

## Check table content without printing vectors

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT id, LEFT(text, 150) AS preview, metadata, embedding IS NOT NULL AS has_embedding FROM documents LIMIT 10;"
```

## Docker network

```powershell
docker network inspect rag-network
docker network connect rag-network n8n
docker network connect --alias db-rag rag-network DB.rag
```

Run `docker network connect` only if that container is not already connected.
