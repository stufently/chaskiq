# Spec queue (fork updates, round 2 — 2026-11-19)

Status: TODO → SPEC → RUNNING → ACCEPTED (merged). One line per milestone.

| Milestone | Scope | Depends on | Status |
|---|---|---|---|
| ci-parity (direct, no spec) | bin/ci-local: GCC 15 like runners, gems in vendor/bundle, push drop with --docker | — | ACCEPTED |
| fork-updates-m9 | multi-attachment send: report later failures; store every provider id per part (Vonage, Dialog360 receipts) | — | ACCEPTED |
| fork-updates-m10 | SNS: verify message signatures | — | ACCEPTED |
| fork-updates-m11 | Telnyx MMS (media send/receive) | — | ACCEPTED |
| fork-updates-m12 | third-party deprecations: nightfury `Redis.current`, rspec old `any_instance` syntax, other boot warnings | — | ACCEPTED |
| fork-updates-m13 | rack 2.2 → 3 | m12 | ACCEPTED |
| fork-updates-m14 | Ruby 3.3 → latest supported | m13 | SPEC |
| fork-updates-m15+ | RuboCop backlog (.rubocop_todo.yml) in chunks | m9–m14 merged | TODO |
