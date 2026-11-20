# mut-m9-m14b — убить мутанты, которые первый проход записал в «эквивалентные»

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/mut-m9-m14b.md`, пробники — `docs/specs/mut-m9-m14b-probes/`.
  Первый проход — `docs/specs/mut-m9-m14.md`, его итоги — `docs/specs/mut-m9-m14-results/`
  (`manifest.json`: 266 мутантов, 86 killed, 81 killed_new, 99 equivalent; AC-003 красный).
- BASE_SHA: `42d0248ed02162cf93b8068e989b3c862ee0599b` — HEAD `main` с тестами первого прохода и R3b-1.
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (раздел 2). Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-006).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, по одному. **Не останавливайся, пока все семь критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: каждый из 86 мутантов таблицы `kill_table.json` убит тестом (только файлы под `spec/`,
  боевой код не меняется). Что эквивалентно, что не мутант и что — дефект кода, уже решил постановщик
  (`classified.json`, раздел 3); исполнитель эквивалентность не объявляет. Убийство проверяет пробник
  сам: прикладывает патч мутанта из `docs/specs/mut-m9-m14b-probes/patches/` (не из файлов исполнителя)
  и гоняет спеки, которые исполнитель записал в манифест.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `mut-m9-m14b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-mutb-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).
- Мутанты НИКОГДА не применяются к дереву клона и не коммитятся: пробник гоняет их на копии
  (`git archive HEAD` → `tmp/mutb-kill/`). Манифест исполнителя — `tmp/mutants-b/manifest.json`
  (игнорируется git, не коммитится).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-mutb-ci` — копия `chaskiq-r5b1-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5b1-ci $HOME/.cache/chaskiq-mutb-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; `git apply --check` всех патчей
   `patches/*.patch` на новом BASE (если R5b-1 влит раньше — его файлы `safe_download.rb`,
   `dialog360/api.rb`, `telegram/api.rb`, `twilio/api.rb`, `message_bird/api.rb` поменялись: патчи
   пересобрать); если менялся `spec/` — `CHASKIQ_MUTB_CACHE=$HOME/.cache/chaskiq-mutb-ci bash docs/specs/mut-m9-m14b-probes/rspec_gate_mutb.sh --write-base`
   на чистом checkout `main` и пересчитать sha256 снимков в AC-006.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-006 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Мутанты и почему

Первый проход записал 99 мутантов «эквивалентными», в основном с причинами вроде «not loaded in test
env», «no test exercises X», «no spec asserts», «under non-concurrent test conditions» — это описание
дыры в тестах, а не эквивалентность. Постановщик разобрал все 99 по коду:

- **Эквивалентные (15)** — правка не меняет поведение ни при каком входе (довод по коду):
  - `M040` — `return unless x` and `return nil unless x` compile to the same value: nil.
  - `M053` — `return if x` and `return nil if x` both return nil.
  - `M059` — `return if x` and `return nil if x` both return nil (two identical sites).
  - `M068` — `return if x` and `return nil if x` both return nil.
  - `M150` — `return if x` and `return nil if x` both return nil.
  - `M081` — nightfury.rb defines redis=, namespace= and both readers explicitly right after attr_accessor, so attr_reader yields the same methods.
  - `M093` — redis 4.8.1 command_helper.rb build_command calls to_s on every argument; set(key, v) and set(key, v.to_s) send the same bytes.
  - `M108` — default_meta is defined once (TimeSeries#default_meta returns {}) and no class in app/, lib/, vendor/ overrides it.
  - `M134` — rack 3.2.8 utils.rb maps the obsolete :unprocessable_entity to 422 (OBSOLETE_SYMBOLS_TO_STATUS_CODES); same status, only a deprecation warning.
  - `M172` — kredis 1.5.0 types/hash.rb: Hash#[]=(key, value) is `update key => value`.
  - `M174` — kredis 1.5.0 scalar.rb: for Kredis.string (typed :string, default nil) #value and #to_s both return get, or nil.
  - `M045` — the advisory lock key is derived only in with_session_lock; every holder uses the same derivation, so byte order does not change which callers exclude each other.
  - `M137` — same: the key is derived only in with_session_lock from the identity array; to_s and to_json are both injective for these arrays of strings/integers.
  - `M248` — same: single derivation site; MD5 and SHA256 both give a stable 64-bit key per identity.
  - `M253` — Array#join without an argument uses the separator $, - nil unless reassigned, and nothing in app/, lib/, config/, vendor/ assigns it - so join and join("") give the same string.
- **Не мутанты (2)** — синтаксическое дерево не меняется, из учёта выброшены:
  - `M226` — the patch changes only the first-line comment: the syntax tree is unchanged, not a mutant.
  - `M261` — the patch only appends a comment to the def line: the syntax tree is unchanged, not a mutant.
- **Дефект кода (2)** — убивать нельзя, тест закрепил бы ошибку (раздел 10):
  - `M259` — delete_key deletes from hash(namespace(k)) = a double-namespaced key, so it never removes data written by set; the mutant fixes that. Killing it would pin the defect - Codex fix milestone.
  - `M267` — same defect as M259 (delete_key double namespace).
- Остальные 80 и новые `N01`–`N06` — убить (таблица ниже). Доля эквивалентных у каждой цели после этого ≤ 20%.

**Патчи.** Код целей с BASE первого прохода (7553575c) переформатировали R1–R4 (вложенные модули),
поэтому 94 патча пересобраны на BASE по совпадению строк без отступов (смысл правки тот же — сверено
построчно), 5 пустых или пропавших (`M199`, `M207`, `M208`, `M216`, `M217`) написаны заново по
описанию; `N01`–`N06` — новые мутанты трёх целей, у которых первый проход не дал ни одного
мутанта своей вехи при `min_mutants` 2: `config/initializers/rack_bad_request.rb` (m13, `N01`, `N02`),
`conversation_part_channel_source.rb` (m14 — передача блока и `uncached`, `N03`, `N04`) и
`telnyx_sms/api.rb` (m14 — нормализация `+` в номере, `N05`, `N06`).

**Что убить** (86; файл спеки — предложение, можно свой; `(exists)` — файл уже есть, можно дописать
в него новые примеры, существующие не трогать):

`ma/` = `app/services/message_apis/`, `nf/` = `vendor/nightfury/lib/nightfury/`, спека — от `spec/`.

| id | файл | мутант | как убить | спека |
|---|---|---|---|---|
| M024 | `ma/safe_download.rb` | open_timeout 5 to 0 | WebMock-stubbed SafeDownload.fetch; spy on Net::HTTP#open_timeout= (and_call_original) - set to 5 | `services/message_apis/safe_download_timeouts_spec.rb` |
| M028 | `ma/base_package.rb` | Always store message_id | plugin_class < BasePackage with PROVIDER and RESUMABLE_DELIVERY = true, part with media blocks: notify_message with on_success storing per delivery_index - no extra source row with delivery_index nil | `services/message_apis/base_package_resumable_spec.rb` |
| M029 | `ma/base_package.rb` | Disable resumable_delivery? | same plugin_class: delivery_hooks(conversation, part) has :already_sent and :on_success keys | `services/message_apis/base_package_resumable_spec.rb` |
| M031 | `ma/base_package.rb` | Remove URL truncation | add_error_event via report_delivery_failure with a 300-char text holding https://x.y/z: event action/message have [url], squished, <= 200 chars | `services/message_apis/base_package_errors_spec.rb` |
| M032 | `ma/base_package.rb` | Skip dedup check | status nil failure reported twice for the same part: exactly one ConversationPartEvent errored part (dedup) | `services/message_apis/base_package_errors_spec.rb` |
| M033 | `ma/base_package.rb` | Replace create_or_find_by | store_message_id(part, response, delivery_index: 1) twice with different ids: one row for index 1, message_source_id of the first call | `services/message_apis/base_package_resumable_spec.rb` |
| M034 | `ma/base_package.rb` | Always use add_message_event | status nil: add_error_event goes through add_error_event_once (second identical call adds no part) | `services/message_apis/base_package_errors_spec.rb` |
| M043 | `app/models/conversation_part_channel_source.rb` | Disable re-raise | with_delivery_lock: stub connection select_value for pg_advisory_unlock to raise PG::ConnectionBad after the block completed - error propagates, throw_away! called | `models/conversation_part_channel_source_lock_spec.rb` |
| M044 | `app/models/conversation_part_channel_source.rb` | Return true for non-wait | hold the advisory lock key from a second connection (pg_advisory_lock on a separate checkout): with_delivery_lock does not yield | `models/conversation_part_channel_source_lock_spec.rb` |
| M136 | `app/models/conversation_part_channel_source.rb` | RETRY_INTERVAL 0.05 to 0.5 | with_status_event_lock: select_value false then true, stub sleep - slept with 0.05 | `models/conversation_part_channel_source_lock_spec.rb` |
| M046 | `ma/helpers.rb` | keygen sample 8 to 4 | keygen: 8 lowercase letters (/\A[a-z]{8}\z/) | `services/message_apis/helpers_spec.rb` |
| M047 | `ma/message_bird/api.rb` | Invert get_media success | get_media: successful download returns the file data, failed response returns nil (WebMock) | `services/message_apis/message_bird_media_spec.rb` |
| M049 | `ma/telegram/api.rb` | PROVIDER telegram to telegram_bot | MessageApis::Telegram::Api::PROVIDER is "telegram" - conversation_channels/external_profiles created with provider "telegram" are found by the API lookups | `services/message_apis/telegram_provider_spec.rb` |
| M055 | `ma/twilio/api.rb` | Remove whatsapp: prefix | send_message for a WhatsApp profile posts From=whatsapp:<phone> (WebMock request body) | `services/message_apis/twilio_whatsapp_spec.rb` |
| M060 | `ma/dialog360/api.rb` | Remove process_read | process_event with statuses [{status: read, id: X}] for a stored source: read handling runs (process_read effect visible) | `services/message_apis/dialog360_statuses_spec.rb` |
| M061 | `ma/dialog360/api.rb` | Rollback to return nil | prepare_initiator_channel_for with blank profile_id: no ConversationChannel/ExternalProfile rows left (transaction rolled back) | `services/message_apis/dialog360_statuses_spec.rb` |
| M062 | `ma/dialog360/api.rb` | return unless to return if blank | add_participant("", message, contacts) with empty-string sender: participant created ("" is truthy) | `services/message_apis/dialog360_statuses_spec.rb` |
| M165 | `app/controllers/api/v1/hooks_controller.rb` | ok to ack | SNS notification and subscription paths answer body "ok" | `controllers/api/v1/hooks_body_spec.rb` |
| M072 | `app/jobs/offline_checker_job.rb` | return true for non-redis | cable adapter async (stub ActionCable.server.config.cable): perform marks the user offline (subscribed? false) | `jobs/offline_checker_adapter_spec.rb` |
| M076 | `lib/rack/health_check.rb` | StandardError to Exception | redis.ping raises a non-StandardError (Class.new(Exception)): call raises it, not 503 | `lib/rack_health_check_errors_spec.rb` |
| M078 | `vendor/nightfury/lib/nightfury.rb` | namespace :nf to :nightfury | Nightfury.namespace default is :nf (save/restore @namespace in ensure) | `lib/nightfury_module_spec.rb` |
| M084 | `nf/identity.rb` | Return tags when nil | identity with tags {tag: v} declared via tag: key_prefix ends with :<tag>.<v> | `lib/nightfury_identity_spec.rb` |
| M086 | `nf/identity.rb` | Remove tag sorting | two tags given in reverse order: key_prefix lists them sorted | `lib/nightfury_identity_spec.rb` |
| M090 | `nf/metric.rb` | blank? to nil? | Metric::Base.new(:x, redis_key_prefix: "").redis_key == "x" | `lib/nightfury_metric_spec.rb` |
| M100 | `nf/metric/time_series.rb` | Return {} for missing | after delete: get/get_exact/get_range/get_all return nil (not {}) | `lib/nightfury_time_series_spec.rb` |
| M101 | `nf/metric/time_series.rb` | Expand zremrange ±1 | set at t and at t+1 step: both points kept; set twice at t: only the last value | `lib/nightfury_time_series_spec.rb` |
| M102 | `nf/metric/time_series.rb` | Return {} for nil point | get(timestamp before the first point) returns nil; get_exact of an empty step returns nil | `lib/nightfury_time_series_spec.rb` |
| M103 | `nf/metric/time_series.rb` | Return {} for zero score | fresh series (only the meta at score 0): get returns nil | `lib/nightfury_time_series_spec.rb` |
| M104 | `nf/metric/time_series.rb` | index to rindex | set("a:b"): get_all value is "a:b" | `lib/nightfury_time_series_spec.rb` |
| M107 | `nf/metric/time_series.rb` | Meta score 0 to 1 | meta = {"k" => 1}: a new instance reads meta {"k" => 1}; get_all does not contain it | `lib/nightfury_time_series_spec.rb` |
| M112 | `nf/metric/avg_time_series.rb` | Zero pad 0.0 to 1.0 | get_padded_range over an empty step returns "0.0" for it | `lib/nightfury_avg_time_series_spec.rb` |
| M115 | `nf/metric/count_time_series.rb` | Subtract extra 1 from decr | incr(3, t) then decr(1, t): value "2" | `lib/nightfury_count_time_series_spec.rb` |
| M116 | `nf/metric/count_time_series.rb` | Zero pad 0 to 1 | get_padded_range over an empty step returns "0" | `lib/nightfury_count_time_series_spec.rb` |
| M117 | `nf/metric/count_time_series.rb` | Shift time back 60s | incr with default time (travel_to a fixed time): point at the current minute | `lib/nightfury_count_time_series_spec.rb` |
| M118 | `nf/metric/count_time_series.rb` | Use original time | incr at t = step + 17 s: stored under the step start (get_exact(step) hit, get_all key is the step) | `lib/nightfury_count_time_series_spec.rb` |
| M123 | `config/initializers/rack_attack.rb` | Simplify path regex | POST /oauth/tokenX and /oauth/token/extra are not throttled by the oauth rule; /oauth/token and /oauth/token.json are | `requests/rack_attack_oauth_path_spec.rb` |
| M133 | `config/middleware/maintenance_mode.rb` | 200 to 503 | Rack middleware instantiated directly with a lambda app: status 200 (existing spec may already kill) | `middleware/maintenance_mode_spec.rb (exists)` |
| M138 | `app/services/dante/utils.rb` | Remove trailing space | extract_plain_text of two text nodes: words separated by a space | `services/dante/utils_spec.rb` |
| M139 | `app/services/dante/utils.rb` | content to blocks | get_blocks of serialized content {content: [...]}: returns the content array | `services/dante/utils_spec.rb` |
| M146 | `ma/telnyx_sms/api.rb` | MAX_MEDIA_BYTES 5MB to 1KB | media of 2 KB is accepted, of 5 MB + 1 byte rejected (SafeDownload limit / content-length) | `services/message_apis/telnyx_media_limit_spec.rb` |
| M155 | `ma/telnyx_sms/api.rb` | Remove empty line rejection | inbound text "a\n\nb": two blocks, no empty paragraph | `services/message_apis/telnyx_media_limit_spec.rb` |
| M145 | `config/initializers/redis.rb` | exists_returns_integer to false | Redis.new(url: ENV.fetch("REDIS_URL")).exists("absent") returns 0 (Integer) | `initializers/redis_initializer_spec.rb` |
| M175 | `config/initializers/redis.rb` | Change pool size from 5 to 1 | the ConnectionPool behind Redis::Objects.redis (ConnectionPoolProxy, @pool) has size 5 | `initializers/redis_initializer_spec.rb` |
| M176 | `config/initializers/redis.rb` | Change pool timeout from 5 to 30 | that pool's timeout is 5 (@timeout of the ConnectionPool in the proxy's @pool) | `initializers/redis_initializer_spec.rb` |
| M177 | `config/initializers/redis.rb` | Change fallback Redis URL db from 1 to 2 | load the initializer in isolation (remove_const REDIS_URL, Chaskiq::Config.fetch returns its default; restore constants and Redis::Objects.redis in ensure): REDIS_URL == redis://localhost:6379/1 | `initializers/redis_initializer_spec.rb` |
| M182 | `app/controllers/api/graphql_controller.rb` | Change rescue StandardError to Exception | schema execute raises a non-StandardError: it propagates (not rendered as 422) | `controllers/api/graphql_errors_spec.rb` |
| M183 | `config/middleware/maintenance_mode.rb` | Change text/html to application/json | content-type text/html | `middleware/maintenance_mode_spec.rb (exists)` |
| M184 | `config/middleware/maintenance_mode.rb` | Change maintenance.html to error.html | body is public/maintenance.html | `middleware/maintenance_mode_spec.rb (exists)` |
| M185 | `config/middleware/maintenance_mode.rb` | Change File.read to File.exist? | body is the file content, not true | `middleware/maintenance_mode_spec.rb (exists)` |
| M186 | `config/middleware/maintenance_mode.rb` | Change content-type case | header key is lowercase content-type (Rack::Lint) | `middleware/maintenance_mode_spec.rb (exists)` |
| M190 | `ma/helpers.rb` | Change doc type to document | ProseMirror helper output: root type "doc" | `services/message_apis/helpers_spec.rb` |
| M191 | `ma/helpers.rb` | Change text type to paragraph | inner node type "text" with the text | `services/message_apis/helpers_spec.rb` |
| M192 | `ma/helpers.rb` | Change keygen range from a-z to a-m | keygen over many calls uses letters beyond m (srand fixed or 200 samples include n..z) | `services/message_apis/helpers_spec.rb` |
| M199 | `nf/metric.rb` | Remove prefix from redis_key in set | redis_key with prefix "p" is "p:x" | `lib/nightfury_metric_spec.rb` |
| M203 | `nf/metric/count_time_series.rb` | Change step_time calculation | get_padded_range runs and returns one entry per step | `lib/nightfury_count_time_series_spec.rb` |
| M204 | `nf/metric/count_time_series.rb` | Change zero padding format | padding value is "0" | `lib/nightfury_count_time_series_spec.rb` |
| M205 | `nf/metric/count_time_series.rb` | Shift time by 1 hour | incr with default time lands in the current minute (travel_to) | `lib/nightfury_count_time_series_spec.rb` |
| M206 | `nf/metric/count_time_series.rb` | Use wrong key for set | incr at a non-aligned time stores at the step start | `lib/nightfury_count_time_series_spec.rb` |
| M207 | `nf/metric/time_series.rb` | Change seconds multiplier | TimeSeries.seconds_in_step(:minute, t) == 60 | `lib/nightfury_time_series_spec.rb` |
| M208 | `nf/metric/time_series.rb` | Change hour step from 3600 to 1800 | seconds_in_step(:hour, t) == 3600 | `lib/nightfury_time_series_spec.rb` |
| M210 | `nf/metric/time_series.rb` | Return nil for nil data_point always | get(nil, true) on an empty series returns [nil, {}] | `lib/nightfury_time_series_spec.rb` |
| M211 | `nf/metric/time_series.rb` | Remove zremrangebyscore call | set twice in the same step: one point with the last value | `lib/nightfury_time_series_spec.rb` |
| M213 | `nf/metric/time_series.rb` | Change meta key format | meta = {"k" => 1} round-trips as JSON (JSON.parse of the stored member) | `lib/nightfury_time_series_spec.rb` |
| M215 | `nf/identity.rb` | Remove demodulize from identity name | a nested identity class (Module::FooIdentity): name == "foo_identity" | `lib/nightfury_identity_spec.rb` |
| M216 | `nf/identity.rb` | Change key prefix separator | key_prefix is "<name>.<id>" | `lib/nightfury_identity_spec.rb` |
| M217 | `nf/identity.rb` | Reverse tag key order | tags a and b: key_prefix ends with ":a.1:b.2" | `lib/nightfury_identity_spec.rb` |
| M224 | `config/initializers/redis.rb` | Change pool timeout to 0 | that pool's timeout is 5, not 0 | `initializers/redis_initializer_spec.rb` |
| M229 | `lib/middleware/rack_bad_request.rb` | Change response to empty body | body is "Bad Request" | `middleware/rack_bad_request_spec.rb (exists)` |
| M231 | `ma/base_package.rb` | Change store_message_id condition | non-resumable plugin: successful notify stores the message id source (delivery_index nil) | `services/message_apis/base_package_resumable_spec.rb` |
| M232 | `ma/base_package.rb` | Change resumable check | plugin without RESUMABLE_DELIVERY: delivery_hooks has only :on_failure | `services/message_apis/base_package_resumable_spec.rb` |
| M234 | `ma/base_package.rb` | Change find_or_create_by | store_message_id with a new delivery_index creates the row (no RecordNotFound) | `services/message_apis/base_package_resumable_spec.rb` |
| M237 | `ma/dialog360/api.rb` | Remove profile_id blank check | prepare_initiator_channel_for with blank profile_id returns nil and creates nothing | `services/message_apis/dialog360_statuses_spec.rb` |
| M247 | `app/models/conversation_part_channel_source.rb` | Change RETRY_INTERVAL to 0.01 | retry sleep is 0.05 (stubbed sleep) | `models/conversation_part_channel_source_lock_spec.rb` |
| M249 | `app/models/conversation_part_channel_source.rb` | Change return value for non-wait | free lock: with_delivery_lock yields and returns the block value (in a NEW file: with this mutant the existing conversation_part_channel_source_spec.rb hangs past the 300 s limit) | `models/conversation_part_channel_source_lock_spec.rb` |
| M251 | `ma/helpers.rb` | Change doc content array | root type "doc" | `services/message_apis/helpers_spec.rb` |
| M252 | `ma/helpers.rb` | Change text content | inner node type "text" | `services/message_apis/helpers_spec.rb` |
| M254 | `app/services/dante/utils.rb` | Change text extraction separator | nested node content is walked (text of children extracted) | `services/dante/utils_spec.rb` |
| M255 | `app/services/dante/utils.rb` | Change content key to type | Dante::Utils.extract_plain_text exists and returns the text | `services/dante/utils_spec.rb` |
| M260 | `ma/twilio_phone/store.rb` | Change locked_agents path from locked_agents to agents | locked_agents(key).key ends with /locked_agents/<key>; data written via a raw Kredis.unique_list at that key is visible | `services/message_apis/twilio_phone/store_spec.rb (exists)` |
| M265 | `ma/twilio_phone/store.rb` | Change del_callblock to set empty | del_callblock: key no longer exists (Kredis.string(key).assigned? false) | `services/message_apis/twilio_phone/store_spec.rb (exists)` |
| N01 | `config/initializers/rack_bad_request.rb` | insert_after Rack::MethodOverride instead of insert_before | Rails.application.middleware: RackBadRequest sits before Rack::MethodOverride | `middleware/rack_bad_request_order_spec.rb` |
| N02 | `config/initializers/rack_bad_request.rb` | middleware not installed (use Rack::Head instead) | Rails.application.middleware includes Middleware::RackBadRequest | `middleware/rack_bad_request_order_spec.rb` |
| N03 | `app/models/conversation_part_channel_source.rb` | block not forwarded to hold_session_lock | with_delivery_lock(part_id, provider) { :done } returns :done (the block runs inside the lock) | `models/conversation_part_channel_source_lock_spec.rb` |
| N04 | `app/models/conversation_part_channel_source.rb` | lock taken outside uncached (query cache can answer pg_try_advisory_lock) | inside ActiveRecord::Base.cache: take and release the delivery lock once, then hold the same key from a second connection - a second with_delivery_lock must not yield (no cached true) | `models/conversation_part_channel_source_lock_spec.rb` |
| N05 | `ma/telnyx_sms/api.rb` | to without the leading + | send_sms_message("15550001", "hi") posts to: "+15550001" (WebMock request body) | `services/message_apis/telnyx_media_limit_spec.rb` |
| N06 | `ma/telnyx_sms/api.rb` | leading + not stripped (delete("-")) | send_sms_message("+15550001", "hi") posts to: "+15550001", not "++15550001" | `services/message_apis/telnyx_media_limit_spec.rb` |

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-mutb-ci`) на
клоне `main` 36b7cc76/42d0248e:

1. Все 86 патчей таблицы применяются к BASE (`git apply --check`) и меняют свой файл; пересобранные
   сверены с исходными построчно (те же удаляемые и добавляемые строки без отступов).
2. Предпроверка: каждый патч таблицы приложен к копии `main` и прогнаны спеки, которые первый проход
   записал для этого мутанта (`mutb_kill_gate.sh --jobs …`): без мутантов всё зелёное (267 примеров в
   20 файлах); с мутантом существующие спеки уже роняют только `M044`, `M199`, `M216`, `M229`, `N01`,
   `N02` (их можно записать `killed` с этими спеками); остальные 76 выживают — им нужны новые тесты.
   С `M249` существующая `conversation_part_channel_source_spec.rb` зависает (> 300 с, пробник считает
   это «не убит») — тест на него — в новом файле.
3. Черновик механики ровно по разделу 5 на подмножестве (итоги — раздел 7).

Предположение: каждый мутант таблицы убиваем тестом без правки боевого кода (подходы — в таблице);
если нет — раздел 9.

## 5. Что сделать — по шагам

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей.
Перед шагом 1:

```bash
P=docs/specs/mut-m9-m14b-probes
export CHASKIQ_MUTB_CACHE=$HOME/.cache/chaskiq-mutb-ci CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutb-ci
mkdir -p tmp/mutants-b vendor/bundle
```

**Шаг 1. Манифест.** Создай `tmp/mutants-b/manifest.json` со всеми 86 id таблицы
(`jq '{mutants: map({id, status: "killed_new", specs: [], test_added: null})}' $P/kill_table.json >
tmp/mutants-b/manifest.json`) и заполняй по мере работы: `status` — `killed_new` (убит новым тестом;
`test_added` — путь spec-файла с этим тестом, он же в `specs`) или `killed` (уже убит существующими
спеками — `specs` их перечисляет, `test_added` — `null`); `specs` — файлы, которые надо прогнать с
мутантом.

**Шаг 2. Тесты — по одной строке таблицы.** Для каждого id: прочитай патч `$P/patches/<id>.patch` и
код вокруг; напиши пример по подходу из таблицы (проверяет поведение, которое мутант ломает, а не
реализацию); проверь быстро:

```bash
bash $P/mutb_kill_gate.sh --only M024            # можно списком: --only M024,M028
```

Нужно `MUTB BASELINE …` (без мутанта всё зелёное) и `KILLED <id>`. `SURVIVED` — усиль пример. Мутанты
одного файла удобно делать пачкой (`--only` со списком). Новые spec-файлы — `# frozen_string_literal: true`,
`require "rails_helper"`, двойные кавычки, строки ≤ 120; HTTP — только WebMock; Redis — тот, что в
тестовой среде (ключи с уникальным префиксом, удалять в `after`); глобальное состояние (`Nightfury.namespace`,
константы, `Redis::Objects.redis`, `ActionCable.server.config`) — сохранять и возвращать в `ensure`.

**Шаг 3. Коммиты** — только `spec/`, по вехам или по файлам, например `Add tests for nightfury mutants`.

**Шаг 4.** Все семь критериев раздела 7. AC-004 (все 86 мутантов, ≈ 45 мин) гони последним.
**Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-003 — строка `mutants: …`; AC-004 —
`MUTB KILL PASS 86/86 killed`; AC-001 — итог примеров.

## 6. Не трогать

- Ничего вне `spec/`: `app/`, `lib/`, `config/`, `vendor/`, `db/`, `Gemfile*`, `.rubocop*`, `.rspec`,
  `bin/`, workflows. Мутанты не применять к дереву клона.
- Существующие примеры под `spec/` не удалять, не skip-ать, не ослаблять (AC-001 требует все примеры
  BASE). Не добавлять `.rspec-local` и игнорируемые файлы под `spec/`.
- `docs/specs/**` — не править (AC-006, sha256): ни таблицу, ни классификацию, ни патчи.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec с новыми тестами строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_MUTB_CACHE=$HOME/.cache/chaskiq-mutb-ci bash docs/specs/mut-m9-m14b-probes/rspec_gate_mutb.sh'`

- **AC-002** — изменён только spec/: против BASE и в каждом коммите — только добавленные или изменённые обычные файлы под spec/; вне spec/ HEAD и рабочее дерево равны BASE; нет лишних неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec/vendor.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-m9-m14b-probes/mutb_probe.py scope $B'`

- **AC-003** — классификация: в tmp/mutants-b/manifest.json ровно id kill_table.json, каждый killed/killed_new со своими spec-файлами (killed_new — test_added изменён с BASE и есть в specs); итог (первый проход + таблица + classified.json) без survived; ни одна причина equivalent не короче 20 символов и не про тесты (test|spec|not loaded|exercis|assert|concurren|normal conditions); у каждой цели targets.json не меньше min_mutants убитых и не больше 20% equivalent.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-m9-m14b-probes/mutb_probe.py check $B'`

- **AC-004** — убийство переприложением: на копии HEAD без мутантов спеки всех мутантов без failed-примеров; каждый из 86 патчей пробника приложен по одному и меняет файл; с ним спеки из манифеста дают упавший пример (killed_new — в своём test_added) и ни одной ошибки вне примеров; файл возвращён.
  `bash -c 'CHASKIQ_MUTB_CACHE=$HOME/.cache/chaskiq-mutb-ci bash docs/specs/mut-m9-m14b-probes/mutb_kill_gate.sh'`

- **AC-005** — строгий RuboCop как в CI: все отслеживаемые файлы (с новыми spec-файлами), оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutb-ci bin/ci-local --only rubocop'`

- **AC-006** — коммитов в docs/specs нет, пробники, патчи, таблицы, снимки и итоги первого прохода не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "8f091dac5097729e1264cbfca881b05c1211279aa747064172958d059b92447b  docs/specs/mut-m9-m14b-probes/mutb_probe.py" "34b5a72e5620c0106cad8e34427d5fc153a01e9796ae12e43e7426938ad5dd5c  docs/specs/mut-m9-m14b-probes/mutb_kill.rb" "d284c591cf01cf9e7df3ce6655654c8b818ae08b186a1e4052b25312091f5b3e  docs/specs/mut-m9-m14b-probes/mutb_kill_gate.sh" "2878bba00e135439dffd242752eb75eee39a2deea65602077a131c43897a3ddc  docs/specs/mut-m9-m14b-probes/kill_table.json" "ead9c5242013339c752c6c6e60191316ed329e210ab66295a4ce32d2b64845eb  docs/specs/mut-m9-m14b-probes/classified.json" "536fd6145bd7a6ef7b96de4932cfbdffcc63cad6ca0c72ccdd0b32b4afd10efe  docs/specs/mut-m9-m14b-probes/patches.sha256" "c5f0ccc9033e03ac7ce1572b73955280b5997ada6848489cdcdde78389cbe118  docs/specs/mut-m9-m14b-probes/rspec_gate_mutb.sh" "8bca68177683fc34dbbd09f16bd51a2836ea239591c6a56076cde62aaecb9948  docs/specs/mut-m9-m14b-probes/mutb_sentinel.rb" "ac8af0c152e44834a5d064017e05df2831f6229adeec21218ddfe5427b345554  docs/specs/mut-m9-m14b-probes/examples_base.txt" "ed7e0e71a8b3eda1e62bedbe3e37cea10e49c5ec63e84e108fb670a3f5b6e565  docs/specs/mut-m9-m14b-probes/pending_allowed.txt" "088837bb067355e8fd5b43f6e48ba9904c6570b452da47b38f5b9650327ccd87  docs/specs/mut-m9-m14b-probes/warnings_base.txt" "4cf228ffe83b47d710546cd234494158a48a07edaa416fcf9dc5ae7d97bce9a4  docs/specs/mut-m9-m14-results/manifest.json" "8b9fec61052434caeab459072fb230183a2d72b23f50f27d76a4a49e7adca7c2  docs/specs/mut-m9-m14-probes/targets.json" | sha256sum -c --quiet - && sha256sum -c --quiet docs/specs/mut-m9-m14b-probes/patches.sha256 && test "$(ls docs/specs/mut-m9-m14b-probes/patches | wc -l)" = 86 && git diff --quiet $B HEAD -- docs/specs'`

- **AC-007** — дерево чистое (сбой git — тоже FAIL), кроме untracked report.json и report-blocked.md; нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-002, AC-005, AC-006, AC-007 зелёные; AC-003 и AC-004 красные
(`tmp/mutants-b/manifest.json: … No such file`).

**Пробный прогон конструктора (BASE `42d0248e`, чистые клоны).**

- Чистый клон без работы: AC-002, AC-005, AC-006, AC-007 — rc=0; AC-003 и AC-004 — rc=1
  (манифеста `tmp/mutants-b/manifest.json` ещё нет) — так и задумано. Все 86 патчей проходят
  `git apply --check` на BASE.
- Проверочная сборка на пяти образцовых спеках (M104, M175, N01, N02, M078):
  `mutb_kill_gate.sh --only M104,M175,N01,N02,M078` → `MUTB KILL PASS 5/5 killed`; AC-001 —
  768 примеров, 0 failures, 30 pending; AC-002 `MUTB SCOPE PASS`; AC-005, AC-006, AC-007 — rc=0.
  AC-003/AC-004 красные, пока в манифесте 5 из 86 — ожидаемо.
- `check` с полным манифестом (все 86 со статусом killed) → `MUTB CHECK PASS`, доли
  эквивалентных по целям ≤ 20%.
- Существующие спеки BASE уже убивают M044, M199, M216, M229, N01, N02, N05; остальные — нет;
  M249 вешает существующую спеку (отсюда лимит 300 с и новый файл спеки).
- Плохие правки ловятся: слабый тест → `SURVIVED M104` (AC-004 rc=1); эквивалентный с причиной
  «no test exercises…» → AC-003 FAIL на M024; правка `app/models/audit.rb` → AC-002 FAIL.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/mut-m9-m14b.md --exclude "docs/specs/mut-m9-m14b-probes/**" --context "chaskiq mut-m9-m14b: тесты только под spec/ на 86 мутантов (80 ошибочно записанных первым проходом в эквивалентные и 6 новых); убийство проверяет пробник переприложением патчей; боевой код не меняется; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/mut-m9-m14b.md
REVIEW_EXCLUDE: docs/specs/mut-m9-m14b-probes/**

Контекст ревьюерам: убивает ли каждый тест именно поведение мутанта (а не падает на загрузке или
опечатке); не ослаблены ли существующие тесты; нет ли зависимости от порядка, сети, времени без
`travel_to`; возвращено ли глобальное состояние.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 7: AC-001…AC-007. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/mut-m9-m14b.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "qwen", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>", "<квитанция codex>"],
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/mut-m9-m14b.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все семь критериев зелёные, ревью и `report.json`
готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md` (id, патч, что
пробовал, дословный вывод `mutb_kill_gate.sh --only <id>`) и доложи, НЕ обходя:
- мутант нельзя убить тестом без правки боевого кода (код недостижим из теста) — id и почему;
- мутант кажется эквивалентным — id и довод по коду (не «тесты этого не проверяют»); объявлять
  эквивалентность сам не вправе;
- тест на правильное поведение красный и без мутанта (настоящий дефект кода) — не чинить код, тест не
  коммитить, описать;
- сьют BASE красный или флапает (приложи два прогона), образ/кэш/сервисы недоступны;
- пробник противоречит спеке или коду BASE (дефект спеки).
Запрещено: файлы вне `spec/`, правка пробников/таблиц/патчей, удалять/ослаблять/skip-ать тесты,
`equivalent` в манифесте, глушить вывод и коды возврата.

## 10. Стыки

- Дефект `MessageApis::TwilioPhone::Store.delete_key` (двойной namespace, M259/M267) — отдельная веха
  Codex с тестом «красный на BASE»; тогда M259/M267 станут обычными мутантами.
- 86 killed и 81 killed_new первого прохода этот проход не перепроверяет (их проверял AC-003 первого
  прохода выборкой); при сомнении — `mutb_kill.rb` с их патчами.
