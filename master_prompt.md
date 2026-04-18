# Antigravity Master Prompt — DuttaMessenger Integration
# CTO Task: Local Setup + ngrok + Flutter UI Integration

---

## HOW TO USE THIS PROMPT

Paste this entire file at the start of every Antigravity session about this project.
It contains everything the AI needs to act correctly without guessing.
Replace every `{{PLACEHOLDER}}` with your actual value before pasting.

---

## ═══════════════════════════════════════════════════
## SECTION 1 — PROJECT IDENTITY
## ═══════════════════════════════════════════════════

You are an expert backend and Flutter developer helping build and integrate
**DuttaMessenger** — a private institutional messaging platform (Telegram-like,
self-hosted, invite-only). No public sign-up. Groups can be simple (WhatsApp-style)
or topic-enabled (Telegram Topics-style).

**Repository:** `https://github.com/shreyasananth-3/dutta-messenger-.git`
**Local path:** `/Users/guru/Desktop/Work/Radlabs/DuttaMessenger`

**Your job today has TWO deliverables:**
1. Get the FastAPI backend running locally and exposed via ngrok HTTPS.
2. Produce Flutter integration code that the UI team can drop in and test immediately.

---

## ═══════════════════════════════════════════════════
## SECTION 2 — TECH STACK (non-negotiable, do not deviate)
## ═══════════════════════════════════════════════════

| Layer              | Technology                          |
|--------------------|-------------------------------------|
| Language           | Python 3.12+ (NOT system Python 3.9)|
| Framework          | FastAPI (async)                     |
| Database           | PostgreSQL 17 (Homebrew)            |
| ORM                | SQLAlchemy 2.0 async + Alembic      |
| Cache / Pub-Sub    | Redis 7                             |
| File Storage       | MinIO (dev) / S3 (prod)             |
| Task Queue         | Celery + Redis                      |
| Push               | Firebase Cloud Messaging (FCM)      |
| Frontend           | Flutter (separate repo, Dart)       |
| Tunnel             | ngrok (HTTPS → localhost)           |
| HTTP client Flutter| Dio (with interceptors)             |
| Token storage      | flutter_secure_storage              |
| Local DB Flutter   | drift / sqflite                     |

---

## ═══════════════════════════════════════════════════
## SECTION 3 — PROJECT STRUCTURE (exact paths)
## ═══════════════════════════════════════════════════

```
DuttaMessenger/
├── CLAUDE.md                     ← Project intelligence (must-read)
├── reference-docs/               ← Architecture & design docs
│   ├── ARCHITECTURE.md
│   ├── API_STANDARDS.md
│   ├── CONVENTIONS.md
│   ├── DATABASE.md
│   ├── TESTING.md
│   ├── DEPLOYMENT.md
│   ├── flutter-architecture.md   ← Flutter app structure guide
│   └── modules/
│       ├── auth/MODULE.md        ← Auth flows, JWT, security
│       ├── chat/MODULE.md        ← Core messaging rules
│       ├── chat/WEBSOCKET.md     ← Every WebSocket event
│       └── ...
├── src/
│   ├── main.py                   ← FastAPI app entry
│   ├── config.py                 ← Pydantic Settings (reads .env)
│   ├── shared/
│   │   ├── database.py           ← Async engine + get_db
│   │   ├── redis.py              ← Redis client
│   │   ├── exceptions.py         ← AppException, NotFoundError, etc.
│   │   ├── responses.py          ← success_response(), error handler
│   │   ├── security/
│   │   │   ├── audit.py          ← write_audit(), AuditEvent enum
│   │   │   └── rate_limit.py
│   │   └── middleware/
│   │       ├── auth.py           ← JWT verification, get_current_user
│   │       ├── acl.py            ← require_permission()
│   │       └── idempotency.py    ← require_idempotency() dependency
│   └── modules/
│       ├── auth/                 ← ✅ COMPLETE — use as reference
│       ├── users/                ← In progress
│       ├── acl/
│       ├── groups/
│       ├── chat/
│       ├── media/
│       └── notifications/
├── migrations/versions/          ← Alembic migration files
│   ├── 0001_baseline_schema.py
│   └── ...
├── tests/
│   ├── conftest.py               ← Shared fixtures
│   └── results/                  ← Timestamped test run proofs
├── scripts/
│   ├── seed.py
│   └── run_tests.sh
├── .env                          ← NEVER commit. Created from .env.example
├── .env.example
├── Makefile                      ← make test, make lint, make migrate
└── pyproject.toml
```

**Module build order (strict — never import downward):**
`shared → auth → users → acl → groups → chat → media → notifications`

---

## ═══════════════════════════════════════════════════
## SECTION 4 — WHAT IS CURRENTLY BUILT AND WORKING
## ═══════════════════════════════════════════════════

**auth module is COMPLETE and smoke-tested (last run: 2026-04-17).**

Working endpoints:
```
POST   /api/v1/institutions          ← Create institution (open, no auth)
POST   /api/v1/auth/login            ← Login → access_token + refresh_token
POST   /api/v1/auth/invite           ← Invite user (requires Bearer token)
POST   /api/v1/auth/register         ← Register via invitation token
POST   /api/v1/auth/refresh          ← Refresh access token
GET    /health                       ← {"status": "healthy"}
GET    /metrics                      ← Prometheus metrics
GET    /docs                         ← Swagger UI
GET    /openapi.json                 ← OpenAPI spec
```

**IMPORTANT — Design Rules That Are Non-Negotiable:**
- Direct registration is BLOCKED by design. Users must be invited first.
- Every user belongs to exactly one institution (tenant).
- UUIDs everywhere — no integer IDs.
- Cursor-based pagination only — no offset/page pagination.
- auth module uses port `8765` for local dev (avoids collision with prod `8000`).

**Known gaps (from smoke test — NOT bugs, do not "fix" them):**
- `audit_logs` table exists but has 0 rows — audit wiring is Stage 4 work.
- Some errors return FastAPI's default `{"detail":"..."}` instead of the
  standard `{"error":{"code":"..."}}` envelope. Gap B, tracked, not a blocker.
- Refresh tokens are not yet single-use rotated. Gap C, tracked, not a blocker.

---

## ═══════════════════════════════════════════════════
## SECTION 5 — TASK 1: LOCAL SETUP + SERVER BOOT
## ═══════════════════════════════════════════════════

Execute these steps IN ORDER. Do not skip. If any step fails, stop and
report the exact error — do not try to work around it silently.

### 5.1 Clone

```bash
git clone https://github.com/shreyasananth-3/dutta-messenger-.git
cd dutta-messenger-
```

### 5.2 Python virtualenv (MUST use 3.12+, not system Python)

```bash
/opt/homebrew/bin/python3.13 -m venv .venv
.venv/bin/python --version          # MUST print 3.13.x — if not, stop here
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e ".[dev,test]"
```

**Known pitfalls to handle automatically:**
- If `greenlet` import error → `.venv/bin/pip install greenlet`
- If `HTTPAuthCredentials` import error → it's `HTTPAuthorizationCredentials` in FastAPI
- If `pydantic_core.ValidationError: Extra inputs not permitted` on TEST_DATABASE_URL →
  `Config.extra = "ignore"` is already set in main; if on a branch, grep for `Settings`
- If `asyncpg multi-statement error` → migration must split SQL into individual `op.execute()` calls

### 5.3 Databases

```bash
brew services start postgresql@17
brew services start redis

psql -h localhost -U "$USER" -d postgres -c "CREATE DATABASE dutta_messenger;"
psql -h localhost -U "$USER" -d postgres -c "CREATE DATABASE dutta_messenger_test;"

# Verify both exist
psql -h localhost -U "$USER" -l | grep dutta
```

### 5.4 .env file

```bash
cat > .env <<EOF
DEBUG=true
ENVIRONMENT=development
LOG_LEVEL=debug

DATABASE_URL=postgresql+asyncpg://$(whoami)@localhost:5432/dutta_messenger
TEST_DATABASE_URL=postgresql+asyncpg://$(whoami)@localhost:5432/dutta_messenger_test

REDIS_URL=redis://localhost:6379/0
SECRET_KEY=dev-only-secret-do-not-use-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

ENABLE_USERS=false
ENABLE_ACL=false
ENABLE_GROUPS=false
ENABLE_CHAT=false
ENABLE_MEDIA=false
ENABLE_NOTIFICATIONS=false
EOF
```

### 5.5 Apply schema (must produce 21 tables)

```bash
.venv/bin/alembic upgrade head

# Verify 21 tables:
psql -h localhost -U "$USER" -d dutta_messenger -c "\dt"
```

### 5.6 Boot server

```bash
mkdir -p /tmp/dm-smoke
.venv/bin/uvicorn src.main:app --host 127.0.0.1 --port 8765 \
  > /tmp/dm-smoke/uvicorn.log 2>&1 &
echo $! > /tmp/dm-smoke/uvicorn.pid
sleep 2
tail -5 /tmp/dm-smoke/uvicorn.log
# MUST show: "Application startup complete."

curl -s http://127.0.0.1:8765/health
# MUST return: {"status":"healthy"}
```

### 5.7 Seed admin and get JWT (for smoke test)

```bash
# Create institution
STAMP=$(date +%s)
curl -sS -H "Content-Type: application/json" \
  -d "{\"name\":\"SmokeSchool-$STAMP\",\"domain\":\"smoke-$STAMP.test\"}" \
  http://127.0.0.1:8765/api/v1/institutions \
  > /tmp/dm-smoke/inst.json

INST_ID=$(python3 -c \
  "import json; print(json.load(open('/tmp/dm-smoke/inst.json'))['data']['id'])")
echo "institution = $INST_ID"

# Seed admin user via Python service layer
cat > /tmp/dm-smoke/seed_user.py <<'PY'
import asyncio, os, sys
sys.path.insert(0, os.getcwd())
from src.shared.database import SessionLocal
from src.modules.auth.services.auth_service import AuthService
INST_ID, EMAIL, PASSWD = sys.argv[1], sys.argv[2], sys.argv[3]
async def main():
    async with SessionLocal() as db:
        user = await AuthService.register_user(
            db=db, institution_id=INST_ID,
            email=EMAIL, password=PASSWD, full_name="Smoke Admin",
        )
        await db.commit()
        print(f"user_id={user.id}")
asyncio.run(main())
PY

.venv/bin/python /tmp/dm-smoke/seed_user.py \
  "$INST_ID" "admin@smoke.test" "Sup3rStr0ng!"

# Login and capture token
curl -sS -H "Content-Type: application/json" \
  -d '{"email":"admin@smoke.test","password":"Sup3rStr0ng!"}' \
  http://127.0.0.1:8765/api/v1/auth/login \
  > /tmp/dm-smoke/login.json

ACCESS=$(python3 -c \
  "import json; print(json.load(open('/tmp/dm-smoke/login.json'))['data']['access_token'])")
REFRESH=$(python3 -c \
  "import json; print(json.load(open('/tmp/dm-smoke/login.json'))['data']['refresh_token'])")
echo "Token acquired: ${ACCESS:0:30}..."
```

### 5.8 Verify all 6 auth endpoints (from MANUAL_SMOKE.md)

```bash
# 1. Health
curl -s http://127.0.0.1:8765/health
# → {"status":"healthy"}

# 2. Invite (authenticated)
curl -sS -H "Authorization: Bearer $ACCESS" \
     -H "Content-Type: application/json" \
     -d '{"email":"invitee@smoke.test"}' \
     http://127.0.0.1:8765/api/v1/auth/invite
# → 201

# 3. Invite without auth (must reject)
curl -sS -o /dev/null -w "%{http_code}\n" \
     -H "Content-Type: application/json" \
     -d '{"email":"nope@smoke.test"}' \
     http://127.0.0.1:8765/api/v1/auth/invite
# → 401

# 4. Register via invitation token
TOKEN=$(psql -h localhost -U "$USER" -d dutta_messenger -At \
  -c "SELECT token FROM user_invitations WHERE email='invitee@smoke.test' \
      ORDER BY created_at DESC LIMIT 1;")
curl -sS -H "Content-Type: application/json" \
  -d "{\"email\":\"invitee@smoke.test\",\"password\":\"Inv1teeP@ss!\",\
      \"full_name\":\"Invitee User\",\"invitation_token\":\"$TOKEN\"}" \
  http://127.0.0.1:8765/api/v1/auth/register
# → 201

# 5. Refresh
curl -sS -H "Authorization: Bearer $ACCESS" \
     -H "Content-Type: application/json" \
     -d "{\"refresh_token\":\"$REFRESH\"}" \
     http://127.0.0.1:8765/api/v1/auth/refresh
# → 200

# 6. DB verification
psql -h localhost -U "$USER" -d dutta_messenger <<'SQL'
SELECT 'institutions' tbl, count(*) FROM institutions
UNION ALL SELECT 'users',            count(*) FROM users
UNION ALL SELECT 'user_invitations', count(*) FROM user_invitations
UNION ALL SELECT 'refresh_tokens',   count(*) FROM refresh_tokens;
SQL
# institutions ≥1, users ≥2, user_invitations ≥1, refresh_tokens ≥1
```

---

## ═══════════════════════════════════════════════════
## SECTION 6 — TASK 2: ngrok HTTPS TUNNEL
## ═══════════════════════════════════════════════════

```bash
# Install
brew install ngrok

# Authenticate (one-time — token from https://dashboard.ngrok.com/auth)
ngrok config add-authtoken 3CW9Ya5MoNLRgXglVQ2xplwRuKX_5L2PKc1mFDeCHzKmiz6dm

# Expose the server (keep server running first from Section 5.6)
ngrok http 8765
```

You will see output like:
```
Forwarding  https://abc123.ngrok-free.app → http://localhost:8765
```

**Save this URL.** It changes every time you restart ngrok.

### Validate ngrok is working:

```bash
NGROK_URL="https://pried-unbent-prelude.ngrok-free.dev"

# Test health
curl -s -H "ngrok-skip-browser-warning: 1" $NGROK_URL/health
# → {"status":"healthy"}

# Test login through ngrok
curl -sS -H "Content-Type: application/json" \
     -H "ngrok-skip-browser-warning: 1" \
     -d '{"email":"admin@smoke.test","password":"Sup3rStr0ng!"}' \
     $NGROK_URL/api/v1/auth/login
# → 200 with access_token

# Test Swagger UI in browser:
# Open: $NGROK_URL/docs
```

**⚠️ CRITICAL:** Every HTTP request through ngrok MUST include this header:
```
ngrok-skip-browser-warning: 1
```
Without it, ngrok intercepts the request and returns an HTML browser warning
page instead of the API response. This applies to curl AND Flutter Dio.

---

## ═══════════════════════════════════════════════════
## SECTION 7 — TASK 3: FLUTTER INTEGRATION CODE
## ═══════════════════════════════════════════════════

The Flutter app follows Feature-First + Clean Architecture. Generate code
that fits exactly into this structure:

```
lib/
├── core/
│   ├── config/app_config.dart        ← base URL lives here
│   ├── network/
│   │   ├── api_client.dart           ← Dio client with interceptors
│   │   └── interceptors/
│   │       └── auth_interceptor.dart ← attach JWT, handle 401 + auto-refresh
│   ├── storage/secure_storage.dart   ← flutter_secure_storage for tokens
│   └── errors/
│       ├── app_exception.dart
│       └── api_error.dart            ← parse backend error envelope
├── features/
│   └── auth/
│       ├── data/
│       │   ├── auth_repository.dart
│       │   └── auth_api.dart         ← raw Dio calls
│       ├── domain/
│       │   └── auth_models.dart      ← Dart model classes
│       └── presentation/
│           └── login_screen.dart
```

---

### 7.1 pubspec.yaml additions

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.4.0
  flutter_secure_storage: ^9.0.0
  uuid: ^4.3.3
  json_annotation: ^4.8.1

dev_dependencies:
  json_serializable: ^6.7.1
  build_runner: ^2.4.8
```

---

### 7.2 lib/core/config/app_config.dart

```dart
/// App-wide configuration. Update ngrokBaseUrl every time you restart ngrok.
class AppConfig {
  // ⚠️  Update this every time ngrok restarts — it generates a new URL.
  // In production this becomes your real domain.
  static const String ngrokBaseUrl = 'https://pried-unbent-prelude.ngrok-free.dev';

  static const String apiVersion = '/api/v1';
  static String get baseUrl => '$ngrokBaseUrl$apiVersion';

  // Required on every request to ngrok tunnels.
  static const Map<String, String> ngrokHeaders = {
    'ngrok-skip-browser-warning': '1',
  };
}
```

---

### 7.3 lib/core/errors/api_error.dart

Matches the exact backend error envelope:
`{"error": {"code": "ERROR_CODE", "message": "...", "details": {...}}}`

```dart
import 'package:dio/dio.dart';

/// Parses the backend's standard error envelope.
/// Backend format: {"error": {"code": "...", "message": "...", "details": {...}}}
class ApiError implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? statusCode;

  const ApiError({
    required this.code,
    required this.message,
    this.details,
    this.statusCode,
  });

  factory ApiError.fromDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    // Standard backend error envelope
    if (data is Map && data.containsKey('error')) {
      final err = data['error'] as Map<String, dynamic>;
      return ApiError(
        code: err['code'] as String? ?? 'UNKNOWN_ERROR',
        message: err['message'] as String? ?? 'An error occurred.',
        details: err['details'] as Map<String, dynamic>?,
        statusCode: statusCode,
      );
    }

    // FastAPI default format (Gap B — some endpoints still use this)
    if (data is Map && data.containsKey('detail')) {
      return ApiError(
        code: _statusToCode(statusCode),
        message: data['detail'] as String? ?? 'An error occurred.',
        statusCode: statusCode,
      );
    }

    // Network / timeout errors
    return ApiError(
      code: 'NETWORK_ERROR',
      message: e.message ?? 'Network error occurred.',
      statusCode: statusCode,
    );
  }

  static String _statusToCode(int? status) => switch (status) {
        400 => 'VALIDATION_ERROR',
        401 => 'UNAUTHORIZED',
        403 => 'FORBIDDEN',
        404 => 'NOT_FOUND',
        409 => 'CONFLICT',
        429 => 'RATE_LIMIT_EXCEEDED',
        _ => 'INTERNAL_ERROR',
      };

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'ApiError($code): $message';
}
```

---

### 7.4 lib/core/storage/secure_storage.dart

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for JWT tokens. Never store tokens in SharedPreferences.
class SecureTokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _institutionIdKey = 'institution_id';
  static const _userIdKey = 'user_id';

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: _accessTokenKey);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  static Future<void> saveUserContext({
    required String institutionId,
    required String userId,
  }) async {
    await Future.wait([
      _storage.write(key: _institutionIdKey, value: institutionId),
      _storage.write(key: _userIdKey, value: userId),
    ]);
  }

  static Future<String?> getInstitutionId() =>
      _storage.read(key: _institutionIdKey);

  static Future<void> clearAll() => _storage.deleteAll();
}
```

---

### 7.5 lib/core/network/api_client.dart

```dart
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../errors/api_error.dart';
import '../storage/secure_storage.dart';

/// Global Dio HTTP client with auth, logging, and ngrok headers.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  static const _uuid = Uuid();

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        // Required for ngrok tunnels — prevents browser warning interception
        'ngrok-skip-browser-warning': '1',
      },
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_dio),
      _RequestIdInterceptor(),
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    ]);
  }

  Dio get dio => _dio;
}

/// Attaches JWT to every request. Handles 401 by refreshing token once.
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureTokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Auto-refresh on 401 (token expired)
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureTokenStorage.getRefreshToken();
        final accessToken = await SecureTokenStorage.getAccessToken();
        if (refreshToken != null && accessToken != null) {
          final response = await _dio.post(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(
              headers: {'Authorization': 'Bearer $accessToken'},
            ),
          );
          final data = response.data['data'];
          await SecureTokenStorage.saveTokens(
            accessToken: data['access_token'] as String,
            refreshToken: data['refresh_token'] as String,
          );
          // Retry original request
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] =
              'Bearer ${data['access_token']}';
          final retryResponse = await _dio.fetch(retryOptions);
          handler.resolve(retryResponse);
          return;
        }
      } catch (_) {
        // Refresh failed — clear tokens, user must log in again
        await SecureTokenStorage.clearAll();
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(DioException(
      requestOptions: err.requestOptions,
      error: ApiError.fromDioException(err),
      response: err.response,
      type: err.type,
    ));
  }
}

/// Attaches a unique X-Request-ID to every request for backend tracing.
class _RequestIdInterceptor extends Interceptor {
  static const _uuid = Uuid();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Request-ID'] = _uuid.v4();
    options.headers['X-Client-Version'] = '1.0.0';
    handler.next(options);
  }
}
```

---

### 7.6 lib/features/auth/domain/auth_models.dart

Matches the exact backend response fields from the auth module.

```dart
/// User authentication response from POST /api/v1/auth/login
class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  const LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Backend wraps in {"data": {...}}
    final data = json['data'] as Map<String, dynamic>;
    return LoginResponse(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }
}

/// User object returned after login or register
class AuthUser {
  final String id;
  final String institutionId;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String status;
  final DateTime createdAt;

  const AuthUser({
    required this.id,
    required this.institutionId,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    required this.status,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        institutionId: json['institution_id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        avatarUrl: json['avatar_url'] as String?,
        status: json['status'] as String? ?? 'active',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Invitation response from POST /api/v1/auth/invite
class InviteResponse {
  final String email;
  final String message;

  const InviteResponse({required this.email, required this.message});

  factory InviteResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return InviteResponse(
      email: (data['invitation'] as Map<String, dynamic>?)?['email']
              as String? ??
          '',
      message: data['message'] as String? ?? '',
    );
  }
}

/// Token pair from POST /api/v1/auth/refresh
class TokenPair {
  final String accessToken;
  final String refreshToken;

  const TokenPair({required this.accessToken, required this.refreshToken});

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return TokenPair(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }
}
```

---

### 7.7 lib/features/auth/data/auth_api.dart

Raw Dio calls. No business logic here — just HTTP.

```dart
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';
import '../../../core/errors/api_error.dart';

/// Raw API calls for the auth module.
/// All endpoints are at /api/v1/auth/* and /api/v1/institutions
class AuthApi {
  final Dio _dio;

  AuthApi() : _dio = ApiClient().dio;

  /// POST /api/v1/institutions
  /// Create an institution. Open endpoint — no auth required.
  Future<Map<String, dynamic>> createInstitution({
    required String name,
    required String domain,
  }) async {
    try {
      final response = await _dio.post(
        '/institutions',
        data: {'name': name, 'domain': domain},
      );
      return response.data['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/login
  /// Login with email + password. Returns access_token + refresh_token.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/invite
  /// Invite a user by email. Requires Bearer token.
  /// IMPORTANT: Direct registration is blocked. Users MUST be invited first.
  Future<InviteResponse> inviteUser({required String email}) async {
    try {
      final response = await _dio.post(
        '/auth/invite',
        data: {'email': email},
        // Authorization header is attached automatically by AuthInterceptor
      );
      return InviteResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/register
  /// Complete registration using an invitation token.
  /// The invitation_token comes from the email that the invitee receives.
  /// In dev/test — read it directly from the DB (see smoke test docs).
  Future<LoginResponse> registerWithInvite({
    required String email,
    required String password,
    required String fullName,
    required String invitationToken,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'invitation_token': invitationToken,
        },
      );
      return LoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/refresh
  /// Exchange a refresh token for a new token pair.
  Future<TokenPair> refreshTokens({
    required String refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        // Current access token attached by AuthInterceptor
      );
      return TokenPair.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
```

---

### 7.8 lib/features/auth/data/auth_repository.dart

Business logic layer. Coordinates API calls + secure storage.

```dart
import '../../../core/storage/secure_storage.dart';
import '../../../core/errors/api_error.dart';
import 'auth_api.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  final AuthApi _api;

  AuthRepository() : _api = AuthApi();

  /// Login and persist tokens securely.
  /// Returns the authenticated user on success.
  /// Throws [ApiError] on failure.
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.login(email: email, password: password);

    await SecureTokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    await SecureTokenStorage.saveUserContext(
      institutionId: response.user.institutionId,
      userId: response.user.id,
    );

    return response.user;
  }

  /// Send an invitation email to a new user.
  /// The invitee will receive an email with a registration link.
  Future<InviteResponse> inviteUser({required String email}) =>
      _api.inviteUser(email: email);

  /// Complete registration with an invitation token.
  /// [invitationToken] comes from the invitation email link.
  Future<AuthUser> registerWithInvite({
    required String email,
    required String password,
    required String fullName,
    required String invitationToken,
  }) async {
    final response = await _api.registerWithInvite(
      email: email,
      password: password,
      fullName: fullName,
      invitationToken: invitationToken,
    );
    await SecureTokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    await SecureTokenStorage.saveUserContext(
      institutionId: response.user.institutionId,
      userId: response.user.id,
    );
    return response.user;
  }

  /// Logout — clear all stored tokens.
  Future<void> logout() => SecureTokenStorage.clearAll();

  /// Check if user is currently logged in.
  Future<bool> isLoggedIn() async {
    final token = await SecureTokenStorage.getAccessToken();
    return token != null;
  }
}
```

---

### 7.9 Quick integration test (paste in any widget's button press)

```dart
// In any StatefulWidget:
void _testIntegration() async {
  final repo = AuthRepository();

  try {
    // Test 1 — Login
    final user = await repo.login(
      email: 'admin@smoke.test',
      password: 'Sup3rStr0ng!',
    );
    debugPrint('✅ Login OK: ${user.fullName} (${user.institutionId})');

    // Test 2 — Invite (now authenticated)
    final invite = await repo.inviteUser(email: 'flutter-test@smoke.test');
    debugPrint('✅ Invite OK: ${invite.message}');

    // Test 3 — Logout
    await repo.logout();
    debugPrint('✅ Logout OK');

  } on ApiError catch (e) {
    debugPrint('❌ ApiError ${e.statusCode} [${e.code}]: ${e.message}');
  } catch (e) {
    debugPrint('❌ Unexpected: $e');
  }
}
```

---

## ═══════════════════════════════════════════════════
## SECTION 8 — API REFERENCE (what's available today)
## ═══════════════════════════════════════════════════

**Base URL:** `https://pried-unbent-prelude.ngrok-free.dev/api/v1`

| Method | Path                        | Auth?  | Purpose                        | Success |
|--------|-----------------------------|--------|--------------------------------|---------|
| POST   | `/institutions`             | No     | Create institution             | 201     |
| POST   | `/auth/login`               | No     | Login → JWT pair               | 200     |
| POST   | `/auth/invite`              | Bearer | Invite user by email           | 201     |
| POST   | `/auth/register`            | No     | Register with invitation token | 201     |
| POST   | `/auth/refresh`             | Bearer | Refresh token pair             | 200     |
| GET    | `/health`                   | No     | Health check                   | 200     |
| GET    | `/metrics`                  | No     | Prometheus metrics             | 200     |
| GET    | `/docs`                     | No     | Swagger UI                     | 200     |
| GET    | `/openapi.json`             | No     | OpenAPI spec (6 paths)         | 200     |

**Response envelopes (always):**
```
Success single:  {"data": {...}}
Success list:    {"data": [...], "pagination": {"has_more": bool, "next_cursor": str, "limit": int}}
Error:           {"error": {"code": "ERROR_CODE", "message": "...", "details": {...}}}
```

**Rate limits:**
```
Auth endpoints:   10 req/min
General API:     120 req/min
Message sending:  60 msg/min
File upload:      10 uploads/min
```

**Error codes you will encounter during integration testing:**
```
AUTHENTICATION_FAILED    401  Bad credentials or expired token
TOKEN_EXPIRED            401  Access token expired — call /auth/refresh
NOT_AUTHENTICATED        401  No Authorization header sent
RATE_LIMIT_EXCEEDED      429  Slow down requests
VALIDATION_ERROR         422  Request body failed Pydantic validation
```

---

## ═══════════════════════════════════════════════════
## SECTION 9 — CODING STANDARDS (non-negotiable)
## ═══════════════════════════════════════════════════

When writing or modifying any backend Python code:

1. **Every function has full type hints** — args and return type. No exceptions.
2. **Every public function has a Google-style docstring** — Args, Returns, Raises.
3. **Structured logging with structlog** — `logger.info("event_name", key=value)`.
   NEVER f-string log messages.
4. **No raw SQL string formatting** — SQLAlchemy parameterised queries only.
5. **No `except Exception: pass`** — catch specific exceptions, log them.
6. **No business logic in route handlers** — max 15 lines, delegate to service layer.
7. **No hardcoded secrets** — use `src/config.py` loaded from `.env`.
8. **UUID4 primary keys everywhere** — no auto-increment integers.
9. **Cursor-based pagination only** — no offset/page parameters.
10. **Error response format:**
    ```python
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={"error_code": "NOT_MEMBER", "message": "Human readable.", "context": str(id)},
    )
    ```

When writing Flutter code:
1. Use `Dio` — never `http` package in this project.
2. Store tokens in `flutter_secure_storage` — never `SharedPreferences`.
3. Parse the backend error envelope through `ApiError.fromDioException()`.
4. Add `ngrok-skip-browser-warning: 1` header to ALL requests in dev.
5. Generate `client_message_id` with `Uuid().v4()` for all POST message calls.
6. Handle `ApiError.isUnauthorized` → trigger token refresh or re-login.

---

## ═══════════════════════════════════════════════════
## SECTION 10 — CTO DEMO CHECKLIST
## ═══════════════════════════════════════════════════

Before your 12pm demo, verify each item:

```
[ ] Server running:  tail /tmp/dm-smoke/uvicorn.log → "Application startup complete."
[ ] Health OK:       curl -s http://127.0.0.1:8765/health → {"status":"healthy"}
[ ] ngrok active:    copy the https://xxx.ngrok-free.app URL from terminal
[ ] ngrok health:    curl -H "ngrok-skip-browser-warning:1" $NGROK_URL/health → {"status":"healthy"}
[ ] Swagger UI:      open $NGROK_URL/docs in browser — shows 6 endpoints
[ ] Metrics:         curl -H "ngrok-skip-browser-warning:1" $NGROK_URL/metrics | grep dutta_
[ ] DB rows:         psql query shows institutions≥1, users≥2, user_invitations≥1
[ ] Flutter login:   app calls $NGROK_URL/api/v1/auth/login → prints user object
[ ] Flutter invite:  app calls /auth/invite with Bearer token → 201
[ ] Token stored:    flutter_secure_storage has access_token after login
[ ] Error handled:   bad password → ApiError(AUTHENTICATION_FAILED) shown in UI
```

---

## ═══════════════════════════════════════════════════
## SECTION 11 — COMMON FAILURES AND EXACT FIXES
## ═══════════════════════════════════════════════════

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| `ModuleNotFoundError: greenlet` | Missing package | `.venv/bin/pip install greenlet` |
| `ImportError: HTTPAuthCredentials` | Wrong FastAPI symbol | `HTTPAuthorizationCredentials` |
| `pydantic ValidationError: Extra inputs not permitted — TEST_DATABASE_URL` | Pydantic strict mode | Add `Config.extra = "ignore"` to Settings |
| `asyncpg cannot insert multiple commands` | Multi-statement SQL in migration | Split into individual `op.execute()` calls |
| `Python 3.9 used` | System Python | Always use `/opt/homebrew/bin/python3.13 -m venv .venv` |
| `Postgres role does not exist` | Using docker role on local | Use `$USER` in DATABASE_URL not `messenger` |
| `connection refused` postgres | Service not running | `brew services start postgresql@17` |
| Flutter: `DioException 502` through ngrok | Server not running | Boot uvicorn first, then ngrok |
| Flutter: `DioException` returns HTML | Missing ngrok header | Add `ngrok-skip-browser-warning: 1` to ALL headers |
| Flutter: 401 on every request | No Authorization header | Auth interceptor must run; check `ApiClient` setup |
| Flutter: 400 on `/auth/register` | Missing invitation token | Pull token from DB: `SELECT token FROM user_invitations ...` |
| `audit_logs` is empty | Known Gap A — not a bug | Ignore during demo. Stage 4 work. |
| Error response is `{"detail":"..."}` | Known Gap B — not a bug | Parse both formats in `ApiError.fromDioException()` |

---

## ═══════════════════════════════════════════════════
## SECTION 12 — WHAT TO BUILD NEXT (after demo)
## ═══════════════════════════════════════════════════

The following modules are in reference-docs but NOT yet built.
Build in strict order:

1. **users module** — Profile, search, online status → `src/modules/users/`
2. **acl module** — Roles, permissions, three-level access → `src/modules/acl/`
3. **groups module** — Dual mode (simple + topics), membership → `src/modules/groups/`
4. **chat module** — Core messaging + WebSocket → `src/modules/chat/`
5. **media module** — Presigned S3 upload, recycle bin → `src/modules/media/`
6. **notifications module** — FCM push, token lifecycle → `src/modules/notifications/`

Before building each module:
1. Read `reference-docs/modules/{name}/MODULE.md`
2. Read `reference-docs/modules/{name}/SCHEMA.sql`
3. Read `reference-docs/modules/{name}/API.md`
4. Copy those files into `src/modules/{name}/docs/`
5. Then write code that matches them exactly.

---

*End of Antigravity Master Prompt — DuttaMessenger Integration*
*Generated: 2026-04-18 | Based on: LOCAL_SETUP.md, MANUAL_SMOKE.md, LOCAL_TESTING.md,*
*API_STANDARDS.md, flutter-architecture.md, CLAUDE.md, CONVENTIONS.md, README.md*
