---
paths:
  - "**/*.entity.ts"
  - "**/*.repository.ts"
  - "**/migrations/**/*.ts"
  - "**/data-source.ts"
  - "**/*.sql"
---

# TypeORM + PostgreSQL conventions

Project docs and existing entities/migrations win over this file.

## Entities

- Class `XxxEntity`, table `@Entity('snake_case_plural')`.
- Primary key: `@PrimaryGeneratedColumn('uuid')`.
- Column names are explicit snake_case: `@Column({ name: 'tenant_id' })`, property in camelCase.
- Use `!` for required fields; type nullable fields as `T | null` with `nullable: true`.
- Timestamps are `timestamptz`. Audit columns: `created_at`, `created_by`, `updated_at`, `updated_by`.
- Soft delete: `@DeleteDateColumn({ name: 'deleted_at' })` plus `deleted_by`.
- Enums: `type: 'enum', enumName: '<table>_<column>_enum'`. TS enum names end in `Enum`.
- Relations are never `eager`. Load them explicitly.
- Money: integer minor units or `numeric`, never `float`.

## Migrations

- `synchronize: false` everywhere except throwaway tests.
- Every schema change ships as a migration in `src/infrastructure/database/migrations/<timestamp>-PascalName.ts`.
- Prefer hand-written SQL in `up()` with a working `down()`. Add a short comment explaining why.
- Never edit a migration that has run on a shared database; add a new one.
- Run/generate only through the repo's npm scripts.

## Queries

- QueryBuilder for lists, search, dynamic filters and sorting; find options for simple lookups.
- Map sort fields through a whitelist record (`SORT_COLUMNS`). Never interpolate user input into SQL; use parameters.
- Avoid N+1: `relations`, `leftJoinAndSelect`, or batched `In(ids)`.
- Always paginate list endpoints (`take`/`skip` or keyset). No unbounded queries.
- Soft-deleted rows are excluded by default; use `withDeleted()` only on purpose.

## Transactions and concurrency

- Multi-write operations run in one transaction: `dataSource.transaction(async (manager) => ...)`, exposed via the repository.
- Use `manager` inside the transaction, never the default repository.
- Use `setLock('pessimistic_write')` or optimistic versioning when concurrent updates can race.
- Translate unique violations (code `23505`) into domain errors by constraint name.

## PostgreSQL

- Unique constraints on soft-deletable tables are partial: `WHERE deleted_at IS NULL`. Use `lower(col)` for case-insensitive uniqueness.
- Index foreign keys and tenant columns.
- Use `jsonb` (not `json`) for semi-structured data; don't put queryable fields inside it.
- Enforce invariants with CHECK constraints in migrations where cheap.
