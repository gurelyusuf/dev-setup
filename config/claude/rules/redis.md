---
paths:
  - "**/*redis*"
  - "**/*cache*"
  - "**/*queue*"
  - "**/*.processor.ts"
  - "**/*.worker.ts"
  - "**/*lock*"
---

# Redis + BullMQ best practices

The repo's own docs and existing code win over this file. Check installed `ioredis`/`bullmq` versions; look up APIs in Context7 when unsure.

## Client

- One shared client per purpose (cache, queues, pub/sub subscriber), created in a module and injected. Never create a client per request.
- Connection settings come from config. Handle the client's `error` event (log it) so connection errors don't crash the process.
- Close clients on shutdown (`onApplicationShutdown` -> `quit()`).
- Use TLS and auth (ACL user/password) outside local development.

## Keys and data

- Key format: `<app>:<entity>:<id>[:<field>]`, e.g. `shop:user:42:profile`. Use `keyPrefix` per app/env; prefix per tenant when multi-tenant.
- Every cache key has a TTL. Document intentionally permanent keys. TTLs come from config.
- Keep values small; store large blobs elsewhere. Serialize consistently (JSON) and version the format when it may change.
- Never use `KEYS` or other O(N) commands on large data in production; use `SCAN`/`scanStream`.
- Batch round trips with `pipeline()`; use `multi()` when the commands must be atomic.

## Caching

- Redis is a cache, not the source of truth. The app must work (slower) on a miss or when Redis is down.
- Cache-aside: read cache, on miss read the DB and set with TTL. Invalidate (delete) on write in the same code path.
- Prevent stampedes on hot keys: TTL jitter, a short lock while one caller rebuilds, or stale-while-revalidate.
- Never cache per-user or sensitive data under shared keys.

## Locks and atomic operations

- Lock: `SET key <unique-token> NX PX <ttl>`. Release with a Lua compare-and-delete so only the owner unlocks. Pick a TTL longer than the work; extend it for long jobs.
- Redis locks are best-effort, not a correctness guarantee. When correctness matters, back them with database constraints or fencing tokens.
- Read-modify-write sequences use Lua scripts or `WATCH`/`MULTI`, never separate GET then SET.

## BullMQ

- Workers' Redis connection must use `maxRetriesPerRequest: null`. The Redis instance used for queues needs `maxmemory-policy noeviction`.
- Queue and job names are constants. Producers depend on an abstraction, not on BullMQ directly, where testability matters.
- Jobs must be idempotent; they can run more than once. Deduplicate with a deterministic `jobId` when the same job can be enqueued twice.
- Keep job data small: pass ids, not whole entities.
- Set `attempts` with exponential `backoff`, plus `removeOnComplete` and a bounded `removeOnFail` so Redis doesn't grow forever.
- Distinguish retryable from permanent failures: throw `UnrecoverableError` for errors that should not retry.
- Concurrency comes from config. Use the queue `limiter` for rate-limited third-party APIs.
- Close workers gracefully on shutdown (`await worker.close()`). Run heavy workers in a separate process/role from the API.
- Listen to `failed` and `error` events and log them with job id and attempt count.
