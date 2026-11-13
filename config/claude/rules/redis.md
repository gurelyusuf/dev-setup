---
paths:
  - "**/*redis*"
  - "**/*cache*"
  - "**/*queue*"
  - "**/*.processor.ts"
  - "**/*.worker.ts"
  - "**/*lock*"
---

# Redis + BullMQ conventions

Project docs and existing code win over this file.

## Client

- One shared `ioredis` client provided by a `RedisModule`, injected by class (`Redis`).
- Close it on shutdown (`onApplicationShutdown` -> `quit()`).
- Connection settings and every TTL come from config. No hardcoded TTLs.

## Keys and data

- Key format: `<namespace>:<entity>:<id>`, e.g. `lock:user:<id>`. Prefix keys per tenant when the app is multi-tenant.
- Every key gets a TTL unless it is intentionally permanent; document permanent keys.
- Redis is a cache or coordination layer, never the source of truth. The app must work (slower) on a cache miss.
- Invalidate cache on write in the same code path as the write.

## Locks and atomic ops

- Locks: `SET key token NX PX ttl`; release with a Lua compare-and-delete so only the owner unlocks.
- Use Lua scripts or `MULTI` for read-modify-write sequences. No read-then-write races.

## BullMQ

- Domain depends on an abstract port (`abstract class XQueue`); a `BullMqXQueue` adapter uses `@InjectQueue`.
- Queue and job names are constants (`QUEUE_NAME`, `JOB_NAME`).
- Deduplicate with a deterministic `jobId` when the same job can be enqueued twice.
- Default job options in `registerQueue`: `attempts`, exponential `backoff`, `removeOnComplete`, bounded `removeOnFail`.
- Workers: `@Processor` + `WorkerHost`. Jobs must be idempotent. Concurrency comes from config.
- Log failures via `@OnWorkerEvent('failed')`.
- If the app splits roles, load processors only in the worker role (e.g. `APP_ROLE=api|worker|all`).
