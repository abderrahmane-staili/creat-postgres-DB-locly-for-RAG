# PostgreSQL + pgvector لـ RAG مع n8n (Docker)

هاد المشروع فيه الخطوات باش نجهزو قاعدة بيانات **PostgreSQL مع pgvector** فـ Docker، باش نستعملوها كـ Vector Store لـ **AI Agent / RAG** فـ **n8n**.

## الفكرة

- صورة `postgres:16` العادية **ما فيهاش** extension `vector`، وكتعطي هاد الخطأ:
  ```
  ERROR: extension "vector" is not available
  ```
- الحل: نستعملو الصورة الجاهزة `pgvector/pgvector:pg16` فـ container جديد مستقل.
- الـ container القديم (`postgres_db`) وبياناتو كيبقاو بلا تغيير.

## المتطلبات

- Docker Desktop خدام
- n8n (محلي أو Docker)
- PowerShell (Windows) أو أي terminal

## 1) إنشاء الـ container

حمّل الصورة:

```powershell
docker pull pgvector/pgvector:pg16
```

شغّل الـ container (port `5433` باش ما يتعارضش مع PostgreSQL القديم اللي فـ `5432`):

```powershell
docker run -d --name DB.rag --restart unless-stopped `
  -p 5433:5432 `
  -e POSTGRES_DB=rag_db `
  -e POSTGRES_USER=rag_user `
  -e POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD `
  -v DB_rag_data:/var/lib/postgresql/data `
  pgvector/pgvector:pg16
```

| العنصر | القيمة |
|---|---|
| Container | `DB.rag` |
| Database | `rag_db` |
| User | `rag_user` |
| Port على الـ PC | `5433` |
| Volume (البيانات) | `DB_rag_data` |

> ⚠️ بدّل `CHANGE_ME_STRONG_PASSWORD` بكلمة سر قوية ديالك. **ما تحطش كلمة السر الحقيقية فـ GitHub.**

## 2) تفعيل pgvector وإنشاء الجدول

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE TABLE IF NOT EXISTS documents (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), content TEXT NOT NULL, metadata JSONB DEFAULT '{}'::jsonb, embedding VECTOR(1536));"
```

`VECTOR(1536)` معناها أن الـ embeddings ديالك فيهم 1536 رقم (مثلا `text-embedding-3-small` ديال OpenAI). إلا بدلتي الموديل، بدّل الرقم.

## 3) التحقق

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "SELECT extname FROM pg_extension WHERE extname = 'vector';"
```

إلا ظهر `vector` راه كلشي مزيان.

شوف الجدول:

```powershell
docker exec -it DB.rag psql -U rag_user -d rag_db -c "\d documents"
```

## 4) الربط مع n8n

فـ n8n: **Credentials → Postgres** وعمّر:

| الحقل | القيمة |
|---|---|
| Host | `host.docker.internal` (إلا n8n كيخدم فـ Docker) أو `localhost` (إلا n8n مثبت مباشرة فـ Windows) |
| Port | `5433` |
| Database | `rag_db` |
| User | `rag_user` |
| Password | كلمة السر اللي حطيتي |
| SSL | Disable (استعمال محلي) |

من بعد استعمل node **PGVector Vector Store** فـ workflow:

- **Insert Documents**: باش تخزن الوثائق
- **Retrieve (as Tool for AI Agent)**: باش الـ Agent يقلب فالوثائق

ملاحظات مهمة فـ إعدادات الـ node:

- Table Name: `documents`
- فـ **Options → Column Names**: حط `content` فـ Content Column (حيت الجدول ديالنا سميتو `content` ماشي `text`)، و `embedding` و `metadata` كيف هوما.
- الـ Embeddings Model خاصو يعطي **1536 dimension** باش يتوافق مع `VECTOR(1536)`.

## 5) أوامر مفيدة (للمرة الجاية)

```powershell
# شوف الـ containers خدامين
docker ps

# وقف / شغّل / أعد التشغيل
docker stop DB.rag
docker start DB.rag
docker restart DB.rag

# شوف logs
docker logs DB.rag --tail 50

# دخل لـ psql
docker exec -it DB.rag psql -U rag_user -d rag_db
```

أوامر psql مفيدة (من داخل psql):

```sql
\dt                          -- لائحة الجداول
\d documents                 -- هيكل الجدول
SELECT count(*) FROM documents;
\q                           -- خروج
```

## 6) Backup و Restore

Backup:

```powershell
docker exec DB.rag pg_dump -U rag_user -d rag_db > rag_backup.sql
```

Restore:

```powershell
Get-Content rag_backup.sql | docker exec -i DB.rag psql -U rag_user -d rag_db
```

## 7) (اختياري) Index باش البحث يكون سريع

إلا كبرات البيانات، زيد index:

```sql
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

## 8) حذف كلشي (إلا بغيتي تبدا من الصفر)

```powershell
docker stop DB.rag
docker rm DB.rag
docker volume rm DB_rag_data   # كيمسح البيانات نهائيا!
```

## مشاكل شائعة

| المشكل | الحل |
|---|---|
| `extension "vector" is not available` | كتستعمل صورة `postgres:16` عادية. استعمل `pgvector/pgvector:pg16` |
| `type "vector" does not exist` | ما دّرتيش `CREATE EXTENSION vector` قبل إنشاء الجدول |
| n8n ما كيتكونيكطاش | جرب `host.docker.internal`، أو حط n8n و DB.rag فنفس Docker network واستعمل `DB.rag` كـ Host |
| Port `5433` مستعمل | بدّل الرقم فـ `-p` وفـ n8n |
| dimension mismatch | الـ embeddings model ما كيعطيش 1536. بدّل `VECTOR(n)` أو بدّل الموديل |

## أمان (Security)

- ما تحطش كلمة السر فـ README ولا فـ GitHub.
- استعمل ملف `.env` وزيدو فـ `.gitignore`:
  ```
  POSTGRES_PASSWORD=your_strong_password
  ```
- بدّل أي كلمة سر ظهرات فـ screenshot أو فـ chat.

## docker-compose (بديل أبسط)

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

التشغيل:

```powershell
docker compose up -d
```
