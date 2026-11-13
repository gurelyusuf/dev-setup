---
paths:
  - "**/*.module.ts"
  - "**/*.controller.ts"
  - "**/*.service.ts"
  - "**/*.guard.ts"
  - "**/*.interceptor.ts"
  - "**/*.filter.ts"
  - "**/*.pipe.ts"
  - "**/dto/**/*.ts"
  - "**/main.ts"
  - "**/test/**/*.ts"
  - "**/*.spec.ts"
---

# NestJS best practices

The repo's own docs (`CLAUDE.md`, `docs/`) and existing patterns win over this file. Check the installed `@nestjs/*` version before using an API; look it up in Context7 when unsure.

## Structure

- One feature module per domain (`users/`, `orders/`), each with its controller, service, DTOs and entities. Shared code lives in a `common/` or `shared/` module; don't create cross-feature imports that form cycles.
- Export only the providers other modules need. Avoid `forwardRef`; a circular dependency means the boundary is wrong.
- Use `@Global()` only for true app-wide infrastructure (config, logger, database).
- File names are kebab-case with a role suffix: `create-user.dto.ts`, `users.service.ts`.

## Layering

- Controllers handle HTTP only: routing, params, DTOs, status codes. No business logic, no data access.
- Services hold business logic and are framework-agnostic where practical (no `Request`/`Response` objects).
- Data access goes through repositories, injected via DI. Don't query the database from controllers.
- Constructor injection with `private readonly`. Depend on abstractions (an injection token or abstract class) where the implementation may change.

## HTTP API

- Set the prefix and versioning once in `main.ts`: `app.setGlobalPrefix('api')` and `app.enableVersioning({ type: VersioningType.URI })`, then `@Controller({ path: 'users', version: '1' })`. Follow the repo if it already hard-codes prefixes.
- Plural, kebab-case resource paths. Correct status codes: `201` on create, `204` on delete with no body.
- Validate route params with built-in pipes (`ParseUUIDPipe`, `ParseIntPipe`).
- Never return entities. Map to response DTOs so internal fields (password hashes, internal ids) never leak.
- Document endpoints with `@nestjs/swagger` (`@ApiTags`, `@ApiOperation`, response types). Prefer the Swagger CLI plugin over repetitive `@ApiProperty`.
- Paginate every list endpoint with a max page size.

## Validation

- One global `ValidationPipe` with `whitelist: true`, `forbidNonWhitelisted: true`, `transform: true`. Register it via `APP_PIPE` (testable) or `app.useGlobalPipes`.
- DTOs are classes with `class-validator` decorators. Use `PartialType`/`PickType`/`OmitType` (from `@nestjs/swagger` when Swagger is used) instead of duplicating fields.
- Query and param numbers need `@Type(() => Number)` or `transform`. Whitelist sortable/filterable fields.

## Configuration

- `ConfigModule.forRoot({ isGlobal: true, ... })` with startup validation: a `validationSchema` (Zod/Joi/Standard Schema) or a `validate()` function. Missing or invalid env fails the boot.
- Group settings with `registerAs()` namespaces; read them via `ConfigService` (typed, `{ infer: true }`) or the injected namespace.
- No `process.env` outside config files and `main.ts`. No magic numbers: limits, TTLs and timeouts come from config or named constants.

## Errors

- Throw Nest HTTP exceptions (`NotFoundException`, `ConflictException`, ...) or the repo's own domain errors, never raw `Error` for expected cases.
- Map errors to responses in one global exception filter; keep a consistent error body. Never leak stack traces or SQL errors to clients.
- Don't catch an error just to rethrow it unchanged. Log 5xx with context, not 4xx noise.

## Security

- Global auth: register the auth guard with `APP_GUARD` and mark open routes with a `@Public()` decorator, so new routes are protected by default. Authorize with roles/permissions guards.
- Security headers: `app.useSecurityHeaders()` on Nest >= 12.1, otherwise `helmet`.
- CORS: `app.enableCors({ origin: <allowed origins from config> })`. Never `origin: '*'` with credentials.
- Rate limiting with `@nestjs/throttler` (`ThrottlerGuard` via `APP_GUARD`); stricter limits on auth endpoints.
- Hash passwords with bcrypt/argon2. Secrets only from config.

## Lifecycle and async

- Call `app.enableShutdownHooks()` so connections, queues and jobs close cleanly on SIGTERM. Release resources in `onModuleDestroy`/`onApplicationShutdown`.
- Await every promise. Intentional fire-and-forget is `void promise` with its own error handling.
- Scheduled jobs (`@Cron`) and queue consumers must be idempotent.
- Request-scoped providers are slow and bubble up the scope chain; use them only when necessary.

## Logging

- Use the Nest `Logger` (`new Logger(ClassName.name)`) or the repo's logger (pino/winston). No `console.log`.
- Structured logs in production. Never log secrets, tokens or PII.

## Testing

- Unit test services with `Test.createTestingModule` and mocked providers (`useValue`), or direct construction with typed mocks.
- E2E tests boot the app (`createNestApplication()`), apply the same global pipes/filters as `main.ts`, and hit it with `supertest`. Close the app in `afterAll`.
- Test behavior and error paths, not implementation details. Follow the repo's test folder and naming layout.
- Before finishing: run the repo's `lint`, `typecheck` and test scripts.
