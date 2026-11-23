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
| fork-updates-m14 | Ruby 3.3 → latest supported | m13 | ACCEPTED |
| fork-updates-r10m | Telegram, Twitter and Twilio Phone metrics | R10l | ACCEPTED. Removed seven offenses. Full RSpec 1,729 examples, 0 failures, 30 existing pending. New characterization 39/39 on BASE and final code, 8/8 mutations detected. [Spec](specs/fork-updates-r10m.md) |
| fork-updates-r10n | OpenAI and CSAT report metrics | R10m | ACCEPTED. Removed two offenses. Full RSpec 1,745 examples, 0 failures, 30 existing pending. New characterization 16/16 on BASE and final code, 4/4 mutations detected. [Spec](specs/fork-updates-r10n.md) |
| fork-updates-r10o | Attachment delivery, Dante rendering and bot-task migration | R10n | ACCEPTED. Removed eight offenses. New characterization 24/24 on BASE and final code, 6/6 mutations detected. [Spec](specs/fork-updates-r10o.md) |
| fork-updates-r10p1 | Segment tag predicates | R10o | ACCEPTED. Removed five offenses. Preserved independent EXCEPT subqueries for negative filters. Targeted RSpec 35 examples, 0 failures. [Spec](specs/fork-updates-r10p1.md) |
| fork-updates-r10p2 | Segment Elasticsearch predicates | R10p1 | ACCEPTED. Removed five offenses. Request snapshots matched BASE and all four mutations were detected. [Spec](specs/fork-updates-r10p2.md) |
| fork-updates-r10q | Bot templates and action triggers | R10a | ACCEPTED. Removed seven offenses. [Spec](specs/fork-updates-r10q.md) |
| fork-updates-r10r | GraphQL controllers, package iframe and inbound mail | R10c | ACCEPTED. Removed five offenses. [Spec](specs/fork-updates-r10r.md) |
| fork-updates-r10s | Conversation creation and notification mail | R10p1 | ACCEPTED. Removed six offenses. [Spec](specs/fork-updates-r10s.md) |
| fork-updates-r10t | AppType and conversation resolver | R10c | ACCEPTED. Removed three offenses. GraphQL SDL and field order matched BASE. [Spec](specs/fork-updates-r10t.md) |
| fork-updates-r10u | Integration hooks, plugins and localized attributes | R10c | ACCEPTED. Removed four offenses. [Spec](specs/fork-updates-r10u.md) |
| fork-updates-r10v | UserHandler and agent management | R10p1 | ACCEPTED. Restored the default module length limit. [Spec](specs/fork-updates-r10v.md) |
| fork-updates-r9 | Remove the RuboCop backlog configuration | R10p2–R10v | ACCEPTED. [Plan](specs/fork-updates-rubocop-plan.md#r9--удалить-rubocop_todoyml) |
| fork-updates-m15+ | RuboCop backlog (.rubocop_todo.yml) in chunks | m9–m14 merged | R1, R2, R3, R7a, R4, R5, R6a, R6b, R3b-1, R5b-1 ACCEPTED; mut-r5b1 (cx) 49/49, mut-r5b2 (cx) 48/48, mut-fxb (qw2) 37/37, R6c, R5b-2, fix-cleanup-bugs, fix-cleanup-2, R3b-2, R3b-3, fix-cleanup-3, R2b, R7d, R7b, R7c, R8a, R9a, R9b, R10a, R10b, R10cfg, R10c, R10e, R10g, R10h1, R10i, R10h2, R10k, R10l ACCEPTED; mut m9-m14 PARTIAL (81 + 75 kills merged, 11 survivors documented) (plan: docs/specs/fork-updates-rubocop-plan.md) |
