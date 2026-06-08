# LevelIt Aliyun auth backend

This is a small ECS-ready Node backend for the iOS auth flow.

## Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `PUT /api/auth/profile`

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

```bash
export LEVELIT_AUTH_SECRET="change-to-a-long-random-secret"
export LEVELIT_DB_FILE="/var/lib/levelit/users.json"
export PORT=3000
npm start
```

For production, put this behind Nginx with HTTPS and proxy it under the same host that serves the existing `/api/analyze` API.
