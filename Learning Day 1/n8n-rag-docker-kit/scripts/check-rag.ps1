$ErrorActionPreference = 'Stop'

$container = 'DB.rag'
$db = 'rag_db'
$user = 'rag_user'

Write-Host "Checking container '$container'..." -ForegroundColor Cyan
docker ps --filter "name=^/$container$"
if ($LASTEXITCODE -ne 0) { throw 'docker ps failed.' }

Write-Host "`nTables in database '$db':" -ForegroundColor Cyan
docker exec $container psql -U $user -d $db -c "\dt"
if ($LASTEXITCODE -ne 0) { throw 'Could not connect to PostgreSQL. Check the container, database, and user.' }

Write-Host "`nDocument and embedding counts:" -ForegroundColor Cyan
docker exec $container psql -U $user -d $db -c "SELECT COUNT(*) AS total_documents, COUNT(embedding) AS documents_with_embeddings FROM documents;"
if ($LASTEXITCODE -ne 0) { throw 'Could not query public.documents. Check whether the table exists.' }

Write-Host "`nRecent chunks (embedding values are not printed):" -ForegroundColor Cyan
docker exec $container psql -U $user -d $db -c "SELECT id, LEFT(text, 120) AS text_preview, embedding IS NOT NULL AS has_embedding FROM documents ORDER BY id LIMIT 5;"
if ($LASTEXITCODE -ne 0) { throw 'Could not read documents.' }
