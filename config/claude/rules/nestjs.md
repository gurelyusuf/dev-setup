---
paths:
  - "**/*.module.ts"
  - "**/*.controller.ts"
  - "**/*.service.ts"
  - "**/*.guard.ts"
  - "**/*.interceptor.ts"
  - "**/*.filter.ts"
  - "**/dto/**/*.ts"
  - "**/main.ts"
  - "**/test/**/*.ts"
  - "**/*.spec.ts"
---

# NestJS conventions

Project docs (`CLAUDE.md`, `docs/`) and the existing code win over this file. Match what the repo already does.

## Layout

- Feature folders under `src/modules/<feature>/` with layers:
  `domain/` (entities, enums, errors, interfaces), `infrastructure/` (repositories),
  `application/` (services), `interface/` (controllers, `dto/`, `dto/responses/`).
- Cross-cutting code goes in `src/shared/`, `src/core/` (global guards, errors), `src/infrastructure/` (db, http, config).
- File names are kebab-case: `patient-tag.controller.ts`, `create-patient-tag.dto.ts`.
- Use relative imports unless the repo already defines path aliases.

## Layering

- Controller: HTTP only (params, DTOs, decorators, response mapping). No business logic.
- Service: business rules; throws domain errors; never touches `Repository<T>` directly when a custom repository exists.
- Repository: a custom class wrapping `@InjectRepository(Entity) private readonly repo: Repository<Entity>`. All queries live here.
- Inject by class. Avoid `forwardRef`; restructure instead.

## Controllers

- Version in the route: `@Controller('api/v1/<kebab-plural>')`.
- Set `@HttpCode(HttpStatus.X)` explicitly. `DELETE` returns `204`.
- Validate ids with `ParseUUIDPipe`.
- Document every handler with Swagger (`@ApiTags`, `@ApiOperation`, response decorators).
- Map entities to response DTOs explicitly. Never return entities.
- Keep the repo's response envelope. Do not invent a new one.

## Validation

- DTOs use `class-validator` and `class-transformer`. The global `ValidationPipe` uses `whitelist`, `forbidNonWhitelisted`, `transform`.
- Update DTOs: `PartialType(CreateDto)` from `@nestjs/swagger`.
- Numeric query params: `@Type(() => Number)`.
- Sorting: whitelist sortable fields; never interpolate user input into column names.
- Reuse existing shared validators/constants (e.g. sort orders, pagination). Don't copy-paste them into new DTOs.

## Errors and logging

- Throw domain errors with stable codes (`X_NOT_FOUND`), not built-in `NotFoundException` and friends, when the repo has a domain error system.
- One global exception filter maps errors to HTTP. Don't catch-and-rethrow without adding information.
- Logger: `private readonly logger = new Logger(ClassName.name)`. Never log secrets or full request bodies with PII.

## Config

- `ConfigModule.forRoot({ isGlobal: true, validate })` with a schema (zod or Joi).
- Read values via `ConfigService<EnvConfig, true>` and `.get('KEY', { infer: true })`.
- No `process.env` outside bootstrap/config files. No magic numbers for limits, TTLs or timeouts; put them in env or a named constant.

## Async

- Await every promise. Intentional fire-and-forget is written `void promise` and must handle its own errors.
- Scheduled jobs (`@Cron`) must be idempotent.

## Testing

- Tests live in `test/` mirroring `src/`: `test/unit`, `test/integration`, `test/e2e` (`*.e2e-spec.ts`).
- Unit tests: construct the class directly with typed `jest.fn()` mocks; use `Test.createTestingModule` when DI wiring matters.
- Shared fixtures in `test/helpers/`.
- Before finishing: run `lint`, `typecheck` and the relevant tests with the repo's own scripts.
