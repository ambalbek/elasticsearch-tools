# Elasticsearch 8.x Management Tools

Python scripts to automate Elasticsearch 8.x maintenance tasks:

1. **`update_index_templates`** — Enforce the `mapper_size` component template on all index templates
2. **`update_ilm_policies`** — Enforce a 90-day delete phase on all ILM policies that have no delete phase (unlimited retention)

---

## Project Structure

```
elasticsearch_tools/
├── .env                          # Your credentials (not committed)
├── .env.example                  # Credential template
├── .gitignore
├── .dockerignore
├── Dockerfile
├── requirements.txt
├── classes/
│   └── es_client.py              # Elasticsearch client wrapper
├── functions/
│   ├── config.py                 # Load config from .env
│   ├── logger.py                 # Shared logging setup
│   ├── template_utils.py         # mapper_size helpers
│   └── ilm_utils.py              # delete phase helpers
└── scripts/
    ├── update_index_templates.py
    └── update_ilm_policies.py
```

---

## Requirements

- Python 3.12+
- Docker (for containerized usage)
- Elasticsearch 8.x cluster with API key auth

---

## Setup

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure credentials

```bash
cp .env.example .env
```

Edit `.env`:

```ini
ES_HOST=https://your-cluster:9200
ES_API_KEY=your_api_key_here
ES_VERIFY_CERTS=true        # set to false for self-signed certificates
```

---

## Running Locally

```bash
# Enforce mapper_size on all index templates
python scripts/update_index_templates.py

# Enforce 90-day delete phase on all ILM policies
python scripts/update_ilm_policies.py
```

### Example output

```
2025-01-01 12:00:00 [INFO] update_index_templates: Connected to https://your-cluster:9200
2025-01-01 12:00:00 [INFO] update_index_templates: Found 12 index templates
2025-01-01 12:00:00 [INFO] update_index_templates: SKIP   my-template-1 (mapper_size already present)
2025-01-01 12:00:00 [INFO] update_index_templates: UPDATE my-template-2 (mapper_size added)
2025-01-01 12:00:00 [INFO] update_index_templates: Done. Updated: 1 | Skipped: 11
```

---

## Running with Docker

### Build the image

```bash
docker build -t es-tools .
```

### Build for AMD64 (cross-platform)

```bash
docker buildx create --use
docker buildx build --platform linux/amd64 -t es-tools:amd64 .
```

### Run a script

```bash
# Using .env file
docker run --rm --env-file .env es-tools python scripts/update_index_templates.py
docker run --rm --env-file .env es-tools python scripts/update_ilm_policies.py

# Using inline env vars
docker run --rm \
  --env ES_HOST=https://your-cluster:9200 \
  --env ES_API_KEY=your_key_here \
  --env ES_VERIFY_CERTS=false \
  es-tools python scripts/update_ilm_policies.py
```

---

## Full Docker Image Transfer Process

This section covers the complete end-to-end workflow for building, exporting, transferring, and running the image on another machine — no registry required.

---

### Step 1 — Build the image (source machine)

```bash
# Standard build
docker build -t es-tools:amd64 .

# OR cross-platform build targeting AMD64
docker buildx create --use
docker buildx build --platform linux/amd64 -t es-tools:amd64 .
```

Verify the image was created:

```bash
docker images es-tools
# REPOSITORY   TAG     IMAGE ID       CREATED         SIZE
# es-tools     amd64   a1b2c3d4e5f6   1 minute ago    210MB
```

---

### Step 2 — Save image to a tar file (source machine)

```bash
docker save es-tools:amd64 -o es-tools-amd64.tar
```

Check the file size:

```bash
ls -lh es-tools-amd64.tar
# -rw-r--r-- 1 user user 210M Jan 01 12:00 es-tools-amd64.tar
```

---

### Step 3 — Split into 25MB parts (source machine)

```bash
split -b 25m es-tools-amd64.tar es-tools-amd64.part_
```

This produces numbered parts:

```
es-tools-amd64.part_aa   25MB
es-tools-amd64.part_ab   25MB
es-tools-amd64.part_ac   25MB
...
es-tools-amd64.part_az   <remaining>
```

Verify all parts are present:

```bash
ls -lh es-tools-amd64.part_*
```

---

### Step 4 — Zip the parts (source machine)

```bash
zip es-tools-amd64.zip es-tools-amd64.part_*
```

Verify the zip:

```bash
zip -sf es-tools-amd64.zip
# Archive contains:
#   es-tools-amd64.part_aa
#   es-tools-amd64.part_ab
#   ...
```

Transfer `es-tools-amd64.zip` to the target machine via USB, SCP, SFTP, or any file sharing method.

---

### Step 5 — Unzip on the target machine

```bash
unzip es-tools-amd64.zip
```

Confirm all parts extracted:

```bash
ls -lh es-tools-amd64.part_*
```

---

### Step 6 — Reassemble the tar file (target machine)

```bash
cat es-tools-amd64.part_* > es-tools-amd64.tar
```

> **Important:** `cat` preserves the order of parts alphabetically (`part_aa`, `part_ab`, ...). The order must match exactly or the tar will be corrupt.

Verify the reassembled file is not corrupt:

```bash
tar tf es-tools-amd64.tar > /dev/null && echo "OK" || echo "CORRUPT"
```

---

### Step 7 — Load the image into Docker (target machine)

```bash
docker load -i es-tools-amd64.tar
# Loaded image: es-tools:amd64
```

Confirm the image is available:

```bash
docker images es-tools
# REPOSITORY   TAG     IMAGE ID       CREATED         SIZE
# es-tools     amd64   a1b2c3d4e5f6   ...             210MB
```

---

### Step 8 — Run on the target machine

```bash
# Create your .env file first
cp .env.example .env
# Edit .env with your ES_HOST and ES_API_KEY

# Run update_index_templates
docker run --rm --env-file .env es-tools:amd64 python scripts/update_index_templates.py

# Run update_ilm_policies
docker run --rm --env-file .env es-tools:amd64 python scripts/update_ilm_policies.py
```

Or pass credentials inline without a `.env` file:

```bash
docker run --rm \
  --env ES_HOST=https://your-cluster:9200 \
  --env ES_API_KEY=your_key_here \
  --env ES_VERIFY_CERTS=false \
  es-tools:amd64 python scripts/update_ilm_policies.py
```

---

### Cleanup (optional)

Remove the parts and tar after loading to free up disk space:

```bash
rm es-tools-amd64.part_* es-tools-amd64.tar
```

---

## Environment Variables

| Variable          | Required | Default | Description                                      |
|-------------------|----------|---------|--------------------------------------------------|
| `ES_HOST`         | Yes      | —       | Elasticsearch cluster URL (e.g. `https://host:9200`) |
| `ES_API_KEY`      | Yes      | —       | API key for authentication                       |
| `ES_VERIFY_CERTS` | No       | `true`  | Set to `false` to disable SSL cert verification  |

---

## Verification

After running the scripts, verify in Kibana:

- **Index Templates**: Stack Management → Index Management → Index Templates
- **ILM Policies**: Stack Management → Index Lifecycle Management

Scripts log `SKIP` for already-compliant items and `UPDATE` for modified ones. The final line always shows a summary:

```
Done. Updated: X | Skipped: Y
```
