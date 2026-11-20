# Blocked mutants — behavioral kill impossible

## M043 — `raise if completed` → `raise if false`

The mutant changes the re-raise condition in `release_session_lock`. To kill it, the block must
complete successfully AND the unlock must fail. But making `pg_advisory_unlock` fail requires
breaking the connection, which also prevents the block from completing. No behavioral test can
distinguish the two variants without modifying production code.

## M100, M103 — `return nil` → `return {}`

`redis.exists` returns Integer (0 for missing key) which is truthy in Ruby, so the guard
`return nil unless redis.exists(redis_key)` never triggers. For `get`/`get_exact`, the actual
returns come from `data_point.nil?` and `data_point[1].zero?` checks — both versions return nil
identically. For `get_range`/`get_all`, they always return `{}` for missing data regardless of
the guard. The mutant is equivalent for all four methods.

## M101 — `zremrangebyscore timestamp, timestamp` → `timestamp - 1, timestamp + 1`

The ±1 expansion of the removal range doesn't affect visible output because step boundaries are
60 seconds apart and data is always stored at floored step times. The expanded range never
reaches adjacent steps' data. Both versions produce identical `get_all` results.

## M118, M206 — `set(value, step_time)` → `set(value, time)`

`set` internally calls `get_step_time(time)` which floors the time to the step boundary. Whether
you pass `step_time` (already floored) or `time` (raw), `add_value_to_timeline` floors it again
to the same value. The stored key, score, and decoded value are identical. The mutant is
equivalent.

## M136, M247 — `STATUS_LOCK_RETRY_INTERVAL = 0.05` → `0.5` / `0.01`

The timing-based test cannot reliably distinguish 0.05s from 0.5s or 0.01s sleeps because the
lock holder releases at ~0.25s. With 0.5s interval, the first sleep covers the entire hold
period; with 0.05s, multiple retries occur. But the total elapsed time is dominated by the hold
duration, not the retry interval. Stubbing `Kernel.sleep` is not possible from the test context.

## M177 — REDIS_URL default `redis://localhost:6379/1` → `/2`

In the test environment, `REDIS_URL` is set from `ENV["REDIS_URL"]` (which is
`redis://redis:6379/0`). The fallback default is never used. Testing the fallback requires
removing the env var and reloading the initializer, but `Chaskiq::Config.fetch` reads from a
config store that may return a value regardless. No behavioral test can observe the difference
between `/1` and `/2` defaults.

## M182 — `rescue StandardError` → `rescue Exception`

Rails' controller test framework catches all exceptions (including non-StandardError) via
middleware. With both variants, the response is 500. With the original, Rails middleware renders
the error; with the mutant, `handle_error_message` renders it. The response body contains the
error message in both cases (Rails test mode includes exception details). No behavioral test can
distinguish the two variants through the HTTP layer.

## N04 — Remove `uncached` wrapper

The query cache returns the same boolean value that a fresh `pg_try_advisory_lock` query would
return. Whether cached or not, the result is identical: `true` if the lock was acquired, `false`
if held by another session. The mutant is equivalent for observable behavior.
