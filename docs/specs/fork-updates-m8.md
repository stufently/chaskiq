# fork-updates-m8 — config.load_defaults 7.0 → 8.1 без разлогина и потери токенов

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m8.md`.
- BASE_SHA: `2648dc617db371c731c2b13f6760ed2e0c5b7d9a` — `main` с влитыми m6 (Rails 8.1.4.1, `load_defaults 7.0`), m7 и правками CI (Ruby 3.3.14).
- BASE плавающий: если до запуска `main` уйдёт вперёд (например, влита веха m7), постановщик
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев
  считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- Исполнитель: Codex (`cx`). Мутации и приёмка — постановщик; исправления внутри вехи — тот же Codex.
- Цель: `config.load_defaults 8.1`, файлы `new_framework_defaults_*` удалены, всё, что живые
  установки выдали при старых defaults (сессии агентов, remember-cookie, токены мессенджера и
  плагинов, signed id, кэш, счётчики Rack::Attack), продолжает приниматься.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m8`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push запрещён,
  постановщик заберёт работу `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (`docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.5 (с YJIT), libpq, libvips, node |
| гемы Rails 8.1 | `$HOME/.cache/chaskiq-m6/bundle` | гейт и пробники; гемы в этой вехе не меняются |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках, сборка фронта на стенде |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4/m8 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m8-probes
bash $P/rspec_gate_m8.sh                    # полный строгий rspec, ~5 мин
bash $P/rspec_gate_m8.sh --only <spec-файл> # один файл
bash $P/m8_boot_probe.sh                    # 4 среды грузятся с LD=8.1 без деприкейшенов
bash $P/m8_compat_probe.sh                  # BASE выдаёт cookie/токены/кэш, дерево их принимает (~4 мин)
```

## 3. Задача и почему

После m6 приложение на Rails 8.1.4.1, но `config.load_defaults 7.0`: поведение 7.1–8.1 выключено,
а `new_framework_defaults_6_0.rb` и `_7_0.rb` — пустые (одни комментарии) остатки прошлых
апгрейдов. Rails upgrade guide предлагает после включения всех флагов поднять `load_defaults` и
удалить эти файлы. Опасность — не тесты, а живые установки: если новые defaults перестанут читать
то, что выдано при старых, разлогинятся все агенты, слетят сессии посетителей мессенджера
(`CHASKIQ_VERIFIER`, purpose `:login`), сломаются iframe плагинов (`CHASKIQ_FRAME_VERIFIER`) и
ссылки на файлы Active Storage. Пробник `m8_compat_probe.sh` проверяет ровно это.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker на клоне от `bcfdbc9d` и на черновике (черновик — только для
проверки достижимости, в веху не идёт):

1. Полный список флагов взят из установленного railties 8.1.4.1
   (`lib/rails/application/configuration.rb`, ветки `load_defaults` "7.1"…"8.1"); таблица — раздел 5.
2. **SHA1 → SHA256 ключей не будет:** `key_generator_hash_digest_class = SHA256` уже включён
   `load_defaults 7.0`. `config/initializers/rotator.rb` оставляет SHA1-ротацию только для старых
   ссылок Active Storage — не трогать. `cookies_serializer :json` и `cookie_store` уже заданы явно.
3. Черновик (только `load_defaults 8.1` + `git rm` двух пустых `new_framework_defaults_*`):
   полный rspec 503 примера / 0 падений / 30 pending (как на BASE, тесты не правились);
   `m8_boot_probe.sh` зелёный во всех 4 средах; `m8_compat_probe.sh` зелёный (14 проверок);
   на чистом BASE оба красные по `LD=7.0`.
4. Чтение старого при новых defaults (cache_format_version 7.1, marshalling_format_version 7.1,
   message_serializer `:json_allow_marshal`, use_message_serializer_for_metadata) — проверено
   пробником: старые FileStore/RedisCacheStore записи (строка, Hash с символами, AR-запись),
   Marshal-токены `CHASKIQ_VERIFIER`/`CHASKIQ_FRAME_VERIFIER`, токен `message_verifier` с purpose и
   сроком, `Blob#signed_id`, AR `signed_id`, signed GlobalID, session/signed/remember cookie.
5. Новые токены `CHASKIQ_VERIFIER`/`CHASKIQ_FRAME_VERIFIER` при 8.1 по-прежнему возвращают Hash с
   СИМВОЛЬНЫМИ ключами (их читают `api_controller.rb`, `channels/application_cable/connection.rb`
   `u[:email]`, `package_iframe_behavior.rb` `data[:app_id]`) — проверено пробником.
6. Миграции: все имена `db/migrate` — 14 цифр и не в будущем (`validate_migration_timestamps`).
   `serialize`, `attr_readonly`, `has_secure_token`, `encrypts`, относительных `redirect_to "x"`,
   `select_all`/`exec_query`, `to_json` во view в коде нет (поиск по `app lib config`).
   `require "link_renamer"`/`"dummy_name"` берут `lib/` из `$LOAD_PATH` (railties добавляет `lib`
   сам) — `add_autoload_paths_to_load_path = false` их не ломает (загрузка production зелёная).
7. Мутации пробника (`m8_mutation_gate.py`) на черновике: KG1, MS1, SA1, FV1 — все убиты.
   Эквивалентны на чтении (в гейт не вошли): `cookies_serializer :marshal` и
   `use_authenticated_cookie_encryption = false` — Rails 8.1 всё равно читает JSON- и AES-GCM-cookie.
   MS1 показывает, что явные `ActiveSupport::MessageVerifier.new` (CHASKIQ_*) не зависят от
   `message_serializer`: при `:json` падают app-verifier, Blob signed id и GlobalID, а CHASKIQ_* — нет.

Предположения: Regexp.timeout = 1 с не задевает тяжёлые регулярки в рантайме (тесты зелёные, но
нагрузочно не проверялось); YJIT в production (+память на процесс) приемлем для установок.

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. `config/application.rb`: `config.load_defaults 7.0` → `config.load_defaults 8.1`. Больше в
   файле ничего не менять.
2. `git rm config/initializers/new_framework_defaults_6_0.rb config/initializers/new_framework_defaults_7_0.rb`.
3. Ни один флаг из таблицы ниже не переопределять (решение по каждому — «включить»). Если какой-то
   флаг ломает тест, загрузку или пробник — это контракт на невыполнимое (раздел 9), а не повод
   вернуть старое значение.
4. Тесты не обязательны (черновик зелёный без правок). Если правишь — только ДОБАВЛЕНИЕ строк.

| Флаг (версия) | Решение | Почему |
|---|---|---|
| add_autoload_paths_to_load_path=false (7.1) | вкл | `lib/` в `$LOAD_PATH` даёт railties; production грузится |
| precompile_filter_parameters (7.1) | вкл | только скорость фильтрации логов |
| dom_testing_default_html_version :html5 (7.1) | вкл | тесты, rspec зелёный |
| log_file_size 100 МБ в local (7.1) | вкл | dev/test |
| run_commit_callbacks_on_first_saved_instances_in_transaction=false (7.1) | вкл | after_commit в event/app_user/external_profile — тесты зелёные |
| sqlite3_adapter_strict_strings_by_default (7.1) | вкл | sqlite не используется |
| query_log_tags_format :sqlcommenter (7.1) | вкл | query log tags не включены |
| raise_on_assign_to_attr_readonly (7.1) | вкл | attr_readonly нет |
| belongs_to_required_validates_foreign_key=false (7.1) | вкл | меньше запросов, поведение то же |
| before_committed_on_all_records (7.1) | вкл | колбэков before_committed! нет |
| default_column_serializer=nil (7.1) | вкл | `serialize` без coder нет |
| active_record.encryption.* SHA256 (7.1) | вкл | `encrypts` не используется |
| marshalling_format_version 7.1 (7.1) | вкл | старые AR-записи в кэше читаются (пробник) |
| run_after_transaction_callbacks_in_order_defined (7.1) | вкл | тесты зелёные |
| generate_secure_token_on :initialize (7.1) | вкл | has_secure_token нет |
| default_headers без X-XSS-Protection 1 (7.1) | вкл | рекомендация браузеров, X-XSS-Protection: 0 |
| debug_exception_log_level :error (7.1) | вкл | логи |
| cache_format_version 7.1 (7.1) | вкл | старые записи FileStore/Redis читаются (пробник); откат см. раздел 10 |
| message_serializer :json_allow_marshal (7.1) | вкл | старые Marshal-токены читаются; CHASKIQ_* сохраняют символы (пробник) |
| use_message_serializer_for_metadata (7.1) | вкл | старые токены с purpose/сроком читаются (пробник) |
| raise_on_invalid_cache_expiration_time (7.1) | вкл | expires_in везде положительный/nil |
| sanitizer_vendor HTML5 (action_view, action_text, 7.1) | вкл | тесты экранирования (campaign) зелёные |
| yjit=true → 8.1: !local (7.2/8.1) | вкл | образ ruby 3.3.5 с YJIT; память — раздел 10 |
| web_image_content_types +webp (7.2) | вкл | webp обрабатывается вариантами |
| postgresql_adapter_decode_dates (7.2) | вкл | сырых select_all нет |
| validate_migration_timestamps (7.2) | вкл | все таймстемпы валидны |
| strict_freshness (8.0) | вкл | If-None-Match приоритетнее If-Modified-Since — по RFC |
| Regexp.timeout ||= 1 (8.0) | вкл | защита от ReDoS; предположение — раздел 4 |
| escape_json_responses=false (8.1) | вкл | JSON-ответы с content-type json |
| action_on_path_relative_redirect :raise (8.1) | вкл | относительных redirect_to нет |
| raise_on_missing_required_finder_order_columns (8.1) | вкл | тесты зелёные |
| escape_js_separators_in_json=false (8.1) | вкл | to_json в `<script>` view не встраивается |
| render_tracker :ruby, remove_hidden_field_autocomplete (8.1) | вкл | view-слой, тесты зелёные |

## 6. Не трогать

- Всё вне списка AC-009. В частности: `Gemfile`, `Gemfile.lock` (гемы не меняются), `app/**`,
  `lib/**`, `db/**`, `config/initializers/{rotator,plugin_verifier,cookies_serializer,session_store,devise,rack_attack}.rb`
  (AC-007 сверяет побайтно), `config/environments/**`, workflows, `Dockerfile*`, `docker-compose.yml`.
- Всё, что принесли m1–m6, не откатывать.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — только добавлять. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-009, sha256). Чужие спеки
  (`fork-updates-m7*`) и их клоны не трогать.
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 503 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m8-probes/rspec_gate_m8.sh`

- **AC-002** — production, staging, development и test грузятся на Rails 8.1.4.1+ с load_defaults 8.1, защитой libvips и без единого деприкейшена.
  `bash docs/specs/fork-updates-m8-probes/m8_boot_probe.sh`

- **AC-003** — всё выданное при load_defaults 7.0 принимается: сессия и remember-cookie агента, signed cookie, токены мессенджера и плагинов, verifier с purpose, signed id, GlobalID, кэш, счётчик; новые токены сохраняют символьные ключи.
  `bash docs/specs/fork-updates-m8-probes/m8_compat_probe.sh`

- **AC-004** — пробник совместимости убивает мутанты SHA1-ключа, JSON-сериализатора без Marshal, соли шифрования cookie и JSON-верификатора плагинов.
  `python3 -I docs/specs/fork-updates-m8-probes/m8_mutation_gate.py`

- **AC-005** — нет регрессий рантайма m1–m5: пробные спеки m1, m2, m3, m4 и m5 зелёные.
  `bash -c 'G=docs/specs/fork-updates-m8-probes/rspec_gate_m8.sh; bash $G --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $G --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb && bash $G --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb'`

- **AC-006** — нет регрессий загрузки m1–m4: пробники загрузки m2, m3 и m4, redis из compose, puma и конфиг m1.
  `bash -c 'export CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle; bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-007** — целостность: ровно load_defaults 8.1, файлы new_framework_defaults удалены, ни один флаг 7.1–8.1 не переопределён, совместимый код и гемы побайтно как в BASE, спеки только дополнены, supply-chain чистый.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m8-probes/m8_integrity_probe.py $B && python3 -I docs/specs/fork-updates-m4-probes/m4_tree_probe.py $B'`

- **AC-008** — живой стенд production: фронт собирается, ассеты отдаются, лимит входа срабатывает на всех вариантах пути.
  `bash -c 'CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh'`

- **AC-009** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "445dd167b9b8979cae6976360d49c3fc558a0b72eac7767bcbb5b375be40ccf5  docs/specs/fork-updates-m8-probes/examples_base.txt" "a1a59995949847d5d24663d17400ffccf256eb8bc1a6bbd50ed2f5ecb1c811a5  docs/specs/fork-updates-m8-probes/m8_boot_probe.sh" "0b3a986820a8f4404dbfcc2f35224f73b1a54c7e77b04ae27a0fbc5a773d6aaa  docs/specs/fork-updates-m8-probes/m8_compat_probe.sh" "4ca7007f655950f9443db1abb522727995dfc4cfa7be03408beb9693b809a9fd  docs/specs/fork-updates-m8-probes/m8_integrity_probe.py" "fcfbc992ca77390d940a2d96708e5b101eba791cdf4712ca727b00d17a5c216e  docs/specs/fork-updates-m8-probes/m8_mutation_gate.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m8-probes/pending_allowed.txt" "3b518684b07438001d8da152f5a6291f3b046eb7b3acd56b1c063a69fb6a3b19  docs/specs/fork-updates-m8-probes/rspec_gate_m8.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "config/application[.]rb|config/initializers/new_framework_defaults_(6_0|7_0)[.]rb|spec/.+")"'`

- **AC-010** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-005, AC-006, AC-008, AC-009,
AC-010 зелёные; AC-002 красный (`LD=7.0`); AC-003 красный (`tree load_defaults is 7.0`); AC-004
красный (пробник не зелёный на чистом дереве); AC-007 красный (`load_defaults lines: ['7.0']`,
`new_framework_defaults files still present`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<B>..REVIEW_SHA` (B — из
`git merge-base HEAD @{u}`, подставить значение); один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <B> --range <B>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m8.md --exclude "docs/specs/fork-updates-m8-probes/**" --context "chaskiq fork-updates-m8: config.load_defaults 7.0 -> 8.1, удалены пустые new_framework_defaults_6_0/7_0; проверить совместимость cookie, сессий, verifier-токенов, кэша; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m8.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m8-probes/**

Контекст ревьюерам: не перестанет ли что-то, выданное при старых defaults, приниматься; не ушёл
ли дифф за раздел 6; не ослаблены ли спеки.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-004 — строка по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m8.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "codex", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>", "<квитанция qwen>"],
    "verification_receipts": [],
    "resolutions": []
  },
  "handoff_status": "ready",
  "criteria": [
    {"id": "AC-001", "status": "pass|fail|blocked",
     "command": "<команда ИЗ ЭТОЙ СПЕКИ, посимвольно>", "rc": 0, "note": "…"}
  ]
}
```

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m8.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- какой-то флаг 7.1–8.1 ломает тест, загрузку или пробник и требует переопределения (опиши флаг,
  падение и вариант решения — переопределять самому запрещено, AC-007);
- зелёное состояние недостижимо без правки `app/`, `lib/`, гемов или существующей строки теста;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-m6`, `node_modules` или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, глушить коды возврата,
подменять окружение.

## 10. Стыки

- **Откат после выката необратим по форматам:** записи кэша 7.1 и новые JSON-токены
  `message_verifier`/AR signed id, выданные после апгрейда, не читаются при `load_defaults 7.0`.
  Сессии агентов (`cookies_serializer :json`) и токены `CHASKIQ_*` (Marshal) откат переживают.
  Откат — с принятием того, что ссылки, выданные после апгрейда, перестанут работать.
  `Rails.cache.clear` НЕ делать: Redis общий с Sidekiq и Rack::Attack (FLUSHDB), а кэш
  Rails 8.1 читает при обоих defaults (поправка по ревью Codex).
- YJIT включается в production/staging (Rails 8.1 default): +память на процесс puma/sidekiq;
  при жёстком лимите памяти контейнера — следить за RSS после выката.
- Остальное вне вехи: rack 3, Ruby 3.4, продовый `Dockerfile` на bookworm/trixie, деприкейшены
  сторонних гемов (`URLcrypt.key=`, `Redis.current` в nightfury), `any_instance` старым синтаксисом
  в `graphql_controller_spec.rb`.
