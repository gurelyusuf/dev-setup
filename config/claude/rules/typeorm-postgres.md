---
paths:
  - "**/*.entity.ts"
  - "**/*.repository.ts"
  - "**/migrations/**/*.ts"
  - "**/data-source.ts"
  - "**/*.sql"
---

# TypeORM + PostgreSQL best practices

The repo's own docs and existing entities/migrations win over this file. Check the installed `typeorm` version first: 1.x removed deprecated 0.3 APIs and changed some defaults; look up the API in Context7 when unsure.

## Entities

- Follow the repo's naming. Without one: table names snake_case plural, columns snake_case (explicit `name:` or a snake-case naming strategy), properties camelCase.
- Primary keys: `uuid` (or `bigint` identity for internal, high-volume tables). Never expose sequential ids publicly.
- Timestamps are `timestamptz`, stored in UTC. Use `@CreateDateColumn`/`@UpdateDateColumn` unless the repo manages them manually.
- Soft delete with `@DeleteDateColumn` only where the domain needs it; remember unique constraints and queries must account for it.
- Nullable columns are explicit: `nullable: true` and typed `T | null`. Everything else is `NOT NULL`.
- Postgres enums (`type: 'enum'`, stable `enumName`) or a lookup table/CHECK for values that change often. Adding enum values needs a migration.
- Money: integer minor units or `numeric(p, s)`. Never `float`/`real`.
- Relations are never `eager`. Set `onDelete` explicitly on foreign keys.
- Entities are persistence models, not API shapes. Don't put HTTP or validation concerns on them.

## Migrations

- `synchronize: false` and `migrationsRun: false` outside throwaway local/test databases. Run migrations as an explicit deploy step.
- Every schema change is a migration with a working `down()`. Review generated SQL; hand-edit when needed.
- Never edit a migration that has run on a shared database; add a new one.
- Zero-downtime changes use expand/contract: add nullable column, backfill, then add constraints; rename = add + copy + drop in later releases.
- Large tables: `CREATE INDEX CONCURRENTLY` in a migration with `transaction = false` (needs `migrationsTransactionMode` `each` or `none`). Avoid long table locks; batch big backfills.
- Data migrations are separate from schema migrations and idempotent.

## Queries

- Parameterize everything. Never interpolate user input into SQL, column names or `ORDER BY`; map sort fields through a whitelist.
- Find options for simple lookups; QueryBuilder for dynamic filters, joins and aggregates. Raw SQL only when needed, still parameterized.
- Select only needed columns for heavy queries. Avoid N+1: `relations`, `leftJoinAndSelect`, or batched `In(ids)`.
- Paginate every list (`take`/`skip` for small offsets, keyset pagination for large or infinite lists). Always use a deterministic `ORDER BY`.
- Use `IsNull()` for null checks; don't pass `null`/`undefined` in `where` and expect TypeORM to guess.
- Check slow queries with `EXPLAIN (ANALYZE, BUFFERS)` before adding indexes.

## Transactions and concurrency

- Multi-write operations run in one transaction: `dataSource.transaction(async (manager) => ...)`. Use only `manager` inside it, never injected repositories.
- Keep transactions short: no HTTP calls or slow I/O inside them.
- Prevent lost updates: `@VersionColumn` (optimistic) or `setLock('pessimistic_write')` (`SELECT ... FOR UPDATE`) for hot rows.
- Use a stricter isolation level only when needed, and retry on serialization failures (`40001`).
- Translate constraint violations (`23505` unique, `23503` foreign key) into domain errors by constraint name; let the database enforce invariants instead of check-then-insert.

## PostgreSQL schema

- Index every foreign key and the columns used in `WHERE`, `JOIN` and `ORDER BY` of hot queries. Composite index order follows the query.
- Unique constraints on soft-deleted tables are partial: `WHERE deleted_at IS NULL`. Case-insensitive uniqueness: unique index on `lower(col)` (or `citext`).
- Enforce invariants with `NOT NULL`, `CHECK`, `UNIQUE` and foreign keys, not only in application code.
- `text` over `varchar(n)` unless a length limit is a real rule. `jsonb` (not `json`) for semi-structured data; don't hide queryable or relational fields in it.
- Set connection pool size and `statement_timeout`/`idle_in_transaction_session_timeout` via config.
