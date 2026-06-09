# LevelIt Aliyun backend

This is the ECS-ready Node backend for LevelIt account auth, profile sync, PK challenges, and optional APNs push notifications.

## Endpoints

Auth and profile:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `PUT /api/auth/profile`
- `GET /health`

PK challenges:

- `POST /api/pk/challenges`
- `GET /api/pk/challenges`
- `GET /api/pk/challenges/:id`
- `PUT /api/pk/challenges/:id`
- `DELETE /api/pk/challenges/:id`
- `POST /api/pk/claim`
- `PUT /api/pk/challenges/:id/progress`
- `PUT /api/pk/challenges/:id/device-token`

The iOS app expects:

```json
{
  "token": "bearer-token",
  "userId": "user-id",
  "profile": {}
}
```

for register/login, and:

```json
{
  "userId": "user-id",
  "identifier": "phone-or-email",
  "profile": {}
}
```

for `/me` and profile updates.

## Run

Local development uses port `3000` by default:

```bash
export LEVELIT_AUTH_SECRET="change-to-a-long-random-secret"
export LEVELIT_DB_FILE="./users.json"
export LEVELIT_PK_DB_FILE="./pk.json"
export PORT=3000
npm start
```

Production deployment should run behind Nginx with HTTPS, under the same host that serves the existing `/api/analyze` API.

```bash
bash deploy-auth.sh 39.105.196.84
```

The deployment script installs the service under `/opt/levelit-auth`, stores runtime data under `/var/lib/levelit`, and writes `/etc/levelit/auth.env`.

Production uses `PORT=3001` so Nginx can proxy:

```nginx
location /api/auth/ {
    proxy_pass http://127.0.0.1:3001;
}

location /api/pk/ {
    proxy_pass http://127.0.0.1:3001;
}
```

## Environment Variables

Required for production:

- `LEVELIT_AUTH_SECRET`: long random HMAC secret for bearer tokens.
- `LEVELIT_DB_FILE`: user database JSON path.
- `LEVELIT_PK_DB_FILE`: PK challenge database JSON path.
- `PORT`: Node listen port. Use `3001` when deployed behind the included Nginx config.
- `NODE_ENV`: set to `production` on ECS.

Optional APNs push settings:

- `APNS_KEY_PATH`: absolute path to the `.p8` private key.
- `APNS_KEY_ID`: Apple Developer Key ID.
- `APNS_TEAM_ID`: Apple Developer Team ID.
- `APNS_BUNDLE_ID`: iOS app bundle ID.
- `APNS_ENV`: `development` or `production`.

If APNs is not configured, the backend still works and push notifications are skipped.

## Safety Notes

- Do not commit `/etc/levelit/auth.env`, APNs `.p8` files, R2 credentials, or real API keys.
- The backend stores JSON files on disk, so production writes are serialized with Promise locks to avoid concurrent write corruption.
- For a larger team or heavier traffic, migrate the JSON files to a managed database before scaling beyond one Node process.
