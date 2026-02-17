# Provider Setup Guide

How to obtain cloud configuration values for each supported provider.

All values go into OpenClaw config (`~/.openclaw/openclaw.json`):

- `skills.entries.cloud-backup.config.*` — non-secrets (bucket, region, endpoint)
- `skills.entries.cloud-backup.env.*` — secrets (access keys)

---

## AWS S3

### 1) Create bucket

- AWS Console → S3 → Create bucket
- Keep "Block Public Access" enabled
- Enable bucket versioning (recommended)

### 2) Create IAM user/key with least privilege

- IAM → Users → Create user (programmatic access)
- Attach a policy similar to:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::YOUR_BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::YOUR_BUCKET/*"
    }
  ]
}
```

### 3) Configure

```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="YOUR_BUCKET"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-east-1"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="<from IAM>"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="<from IAM>"'
```

---

## Cloudflare R2

### 1) Create bucket

- Cloudflare Dashboard → R2 → Create bucket

### 2) Create API token

- R2 → API Tokens
- Create token scoped to only this bucket
- Permissions: Object Read and Object Write

### 3) Configure

```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="<r2-bucket-name>"'
openclaw config patch 'skills.entries.cloud-backup.config.region="auto"'
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://<account_id>.r2.cloudflarestorage.com"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="<r2_access_key_id>"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="<r2_secret_access_key>"'
```

---

## Backblaze B2 (S3 API)

### 1) Create bucket

- Backblaze Console → B2 Cloud Storage → Create bucket (private)

### 2) Create application key

- App Keys → Create New Application Key
- Restrict to target bucket; allow read/write/list/delete

### 3) Configure

```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="<b2-bucket-name>"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-west-004"'
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://s3.us-west-004.backblazeb2.com"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="<b2_key_id>"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="<b2_application_key>"'
```

---

## MinIO

### 1) Create bucket and access key

- In MinIO console: create bucket (private), create access key pair

### 2) Configure

```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="<minio-bucket>"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-east-1"'
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://minio.example.com"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="<minio_access_key>"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="<minio_secret_key>"'
```

---

## DigitalOcean Spaces

### 1) Create Space

- DigitalOcean → Spaces → Create Space (private)

### 2) Create access key pair

- API → Spaces Keys → Generate New Key

### 3) Configure

```bash
openclaw config patch 'skills.entries.cloud-backup.config.bucket="<space-name>"'
openclaw config patch 'skills.entries.cloud-backup.config.region="us-east-1"'
openclaw config patch 'skills.entries.cloud-backup.config.endpoint="https://nyc3.digitaloceanspaces.com"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_ACCESS_KEY_ID="<spaces_key>"'
openclaw config patch 'skills.entries.cloud-backup.env.AWS_SECRET_ACCESS_KEY="<spaces_secret>"'
```

---

## Verify

```bash
bash scripts/openclaw-cloud-backup.sh status
bash scripts/openclaw-cloud-backup.sh backup full
bash scripts/openclaw-cloud-backup.sh list
```

If backup or list fails, see `references/security-troubleshooting.md`.
