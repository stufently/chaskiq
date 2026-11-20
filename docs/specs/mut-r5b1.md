# mut-r5b1 — отдельный мутационный прогон по новым тестам R5b-1

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/mut-r5b1.md`, пробники — `docs/specs/mut-r5b1-probes/`.
  Проверяемая веха — `docs/specs/fork-updates-r5b1.md` (влита в `main` коммитом `00b5c909`).
- BASE_SHA: `f43aaa873b50ef62085f7727fc6d86d9a7f16daa` — HEAD `main` после влития R5b-1
  (`00b5c909` + «Update spec queue»; дерево `app/ lib/ config/ spec/ vendor/ db/` равно R5b-1 HEAD `65ace2b8`).
- BASE плавающий: постановщик переносит строку BASE_SHA на коммит, которым кладёт эту спеку в `main`,
  и только потом снимает клон (раздел 2). Все патчи обязаны прикладываться к этому коммиту. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`).
- Исполнитель: **Codex (`cx`)** (R5b-1 писал Qwen — мутации у противоположного исполнителя).
  **Не останавливайся, пока все восемь критериев раздела 7 не зелёные — или пока не сработал пункт
  раздела 9.**
- Цель: каждый из 49 мутантов таблицы `kill_table.json` убит **поведенческим** тестом (только файлы
  под `spec/`, боевой код равен BASE). Мутанты — новые, независимые от 15 мутантов гейта R5b-1
  (`fork-updates-r5b1-probes/r5b1_config.json`, `M01`–`M15`), по коду, который покрывают восемь новых
  спек R5b-1. Эквивалентные постановщик уже исключил (раздел 3); исполнитель эквивалентность не
  объявляет. Убийство проверяет пробник сам: прикладывает патч из `docs/specs/mut-r5b1-probes/patches/`
  (не из файлов исполнителя) и гоняет спеки, которые исполнитель записал в манифест.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `mut-r5b1`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-mutr5b1-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).
- Мутанты НИКОГДА не применяются к дереву клона и не коммитятся: пробник гоняет их на копии
  (`git archive HEAD` → `tmp/mutr-kill/`). Поэтому тесты надо **закоммитить** до прогона гейта.
  Манифест исполнителя — `tmp/mutants-r5b1/manifest.json` (игнорируется git, не коммитится).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-mutr5b1-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5b1-ci $HOME/.cache/chaskiq-mutr5b1-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: `git apply --check` всех `patches/*.patch` на новом HEAD
   (не прикладываются — пересобрать по `old`/`new` описанию); если менялся `spec/` — на чистом
   checkout `main` `CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci bash docs/specs/mut-r5b1-probes/rspec_gate_mutr.sh --write-base`
   и пересчитать sha256 снимков в AC-007.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-007 и строку
   BASE_SHA (= этот коммит или его родитель — `B` вычисляется по `@{u}`). Только после этого — `make_clone.sh`.

## 3. Мутанты и почему

Новые спеки R5b-1 (`git diff --name-only --diff-filter=A 4bd1b924..00b5c909 -- spec`):
`audit_serialize_spec.rb`, `campaign_urls_spec.rb`, `app_user_event_job_spec.rb`,
`calendly_presenter_spec.rb`, `pipedrive_api_spec.rb`, `safe_download_location_spec.rb`,
`slack_api_helpers_spec.rb`, `slack_event_data_spec.rb` (фикс D1). Гейт R5b-1 уже прогнал 15 мутантов
(`M01`–`M15`); здесь — 49 других правок тех же методов: удалить строку, перевернуть условие, сменить
возвращаемое значение, `nil` вместо значения, выбросить ключ, `||` ↔ `&&`, сравнение `>` → `>=`.

Мутантов по файлам: `audit.rb` 7, `campaign.rb` 6, `app_user_event_job.rb` 5, `calendly/presenter.rb` 5,
`pipedrive/api.rb` 7, `safe_download.rb` 7, `slack/api.rb` 12.

- **Эквивалентные (6), исключены из таблицы** (`classified.json`, довод по коду):
  - `E1` `safe_download.rb` `response["location"]` → `response["Location"]` — Net::HTTPHeader#[] ищет по `key.downcase`.
  - `E2` `safe_download.rb` `String.new(encoding: Encoding::BINARY)` → `String.new` — без аргументов и так пустая ASCII-8BIT строка.
  - `E3` `slack/api.rb` `v.blank? or [...]` → `v.blank? || [...]` — единственное выражение блока, присваивания нет.
  - `E4` `audit.rb` `agent.try(:display_name)` → `agent&.display_name` — Agent#display_name определён всегда, на nil оба дают nil.
  - `E5` `campaign.rb` `default_url_options[:host]` → `.fetch(:host, nil)` — у Hash без default proc одно и то же.
  - `E6` `calendly/presenter.rb` `URI.parse(uri).try(:host)` → `.host` — URI::Generic всегда определяет host.
- Правок только комментариев в таблице нет (каждый патч проверен: мутант синтаксически валиден, `ruby -c`).
- **Остальные 49 — убить.** «уже убит» в таблице — выживает ли мутант против спек BASE (раздел 4):
  такие можно записать `killed` со спеками BASE; остальным нужен новый тест (`killed_new`).

`ma/` = `app/services/message_apis/`, спека — от `spec/` (предложение, можно свой файл; существующие
примеры не трогать):

| id | файл | мутант | как убить | спека | уже убит |
|---|---|---|---|---|---|
| R01 | `app/models/audit.rb` | agent_name without .to_s | Audit.new without an agent: agent_name == "" (not nil) | `models/audit_mutants_spec.rb` |  |
| R02 | `app/models/audit.rb` | Agent auditable link path /agents/ to /users/ | serialize_properties(app) of an Agent auditable: auditable_link ends with /agents/<id>) | `models/audit_mutants_spec.rb` | да |
| R03 | `app/models/audit.rb` | AppUser auditable link name display_name to email | AppUser auditable with a name: auditable_link == "[<display_name>](/apps/<key>/users/<id>)" | `models/audit_mutants_spec.rb` |  |
| R04 | `app/models/audit.rb` | serialize_properties drops agent_name | serialize_properties(app)["agent_name"] == agent display name | `models/audit_mutants_spec.rb` |  |
| R05 | `app/models/audit.rb` | serialize_properties drops sdata | audit with data {"a" => 1}: serialize_properties(app)["sdata"] parses to {"a" => 1} | `models/audit_mutants_spec.rb` |  |
| R06 | `app/models/audit.rb` | attach_app does nothing | Audit.create! with a Conversation auditable: the saved row has app_id == conversation.app_id | `models/audit_mutants_spec.rb` |  |
| R07 | `app/models/audit.rb` | sdata to_json to to_s | audit with data {"a" => 1}: sdata == {"a" => 1}.to_json (JSON.parse round-trips) | `models/audit_mutants_spec.rb` |  |
| R08 | `app/models/campaign.rb` | campaign_url /campaigns/ to /campaign/ | campaign_url == "<host>/campaigns/<id>" | `models/campaign_mutants_spec.rb` | да |
| R09 | `app/models/campaign.rb` | decode_email looks up App.first instead of the key | two apps, the campaign belongs to the one created second: decode_email returns that campaign | `models/campaign_mutants_spec.rb` |  |
| R10 | `app/models/campaign.rb` | decode_email splits on _ instead of - | decode_email of a valid address returns the campaign | `models/campaign_mutants_spec.rb` | да |
| R11 | `app/models/campaign.rb` | mustache_template_for drops subscriber properties | subscriber with properties {"plan" => "pro"}, html "{{plan}}": rendered "pro" | `models/campaign_mutants_spec.rb` |  |
| R12 | `app/models/campaign.rb` | mustache_template_for prefers premailer over html: | campaign with premailer column "P" (update_column) and html: "H": rendered "H" | `models/campaign_mutants_spec.rb` |  |
| R13 | `app/models/campaign.rb` | campaign_unsubscribe /delete to /destroy | html "{{campaign_unsubscribe}}": "<campaign_url>/subscribers/<encoded_id>/delete" | `models/campaign_mutants_spec.rb` |  |
| R14 | `app/jobs/app_user_event_job.rb` | perform looks up App.first instead of the key | another app created first; perform for a user of the second app: Tour receives that user, no RecordNotFound | `jobs/app_user_event_job_mutants_spec.rb` | да |
| R15 | `app/jobs/app_user_event_job.rb` | Tour gets nil instead of the user | Tour.broadcast_tour_to_user received with(the app user) | `jobs/app_user_event_job_mutants_spec.rb` |  |
| R16 | `app/jobs/app_user_event_job.rb` | BotTask gets nil instead of the user | Tour returns nil: BotTask.broadcast_task_to_user received with(the app user) | `jobs/app_user_event_job_mutants_spec.rb` |  |
| R17 | `app/jobs/app_user_event_job.rb` | Tour || BotTask to && | Tour returns true: result true, BotTask not called | `jobs/app_user_event_job_mutants_spec.rb` | да |
| R18 | `app/jobs/app_user_event_job.rb` | UserAutoMessage fallback removed | Tour and BotTask nil: UserAutoMessage result returned | `jobs/app_user_event_job_mutants_spec.rb` | да |
| R19 | `ma/calendly/presenter.rb` | valid_url? returns scheme instead of host | valid_url?("https://calendly.com/x") == "calendly.com" | `services/message_apis/calendly_presenter_mutants_spec.rb` | да |
| R20 | `ma/calendly/presenter.rb` | initialize_hook button label from invitation_text | initialize_hook with values label "Go": second definition label "Go" | `services/message_apis/calendly_presenter_mutants_spec.rb` |  |
| R21 | `ma/calendly/presenter.rb` | initialize_hook kind initialize to submit | initialize_hook result kind == "initialize" | `services/message_apis/calendly_presenter_mutants_spec.rb` |  |
| R22 | `ma/calendly/presenter.rb` | initialize_hook values dropped | initialize_hook result values == the ctx values | `services/message_apis/calendly_presenter_mutants_spec.rb` |  |
| R23 | `ma/calendly/presenter.rb` | initialize_hook frame url changed | second definition action == {type: "frame", url: "/package_iframe_internal/Calendly"} | `services/message_apis/calendly_presenter_mutants_spec.rb` |  |
| R24 | `ma/pipedrive/api.rb` | url api_token param renamed | WebMock stub on ...?api_token=tok answers | `services/message_apis/pipedrive_api_mutants_spec.rb` | да |
| R25 | `ma/pipedrive/api.rb` | create_person sends an empty body | create_person: WebMock request body JSON == the params | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R26 | `ma/pipedrive/api.rb` | create_person drops the Content-Type header | create_person: WebMock stub with headers Content-Type application/json is the request made | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R27 | `ma/pipedrive/api.rb` | register_contact ignores success of the find reply | profile_id set, find reply {success: false}: create_person called (POST), profile updated from it, no error | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R28 | `ma/pipedrive/api.rb` | register_contact ignores success of the create reply | no profile_id, create reply {success: false, data: nil}: no error, profile_id stays nil | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R29 | `ma/pipedrive/api.rb` | register_contact does not store the created profile_id | no profile_id, create reply {success: true, data: {id: 5}}: profile_id == "5" | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R30 | `ma/pipedrive/api.rb` | create params name from email | user with name "Ann": POST body name "Ann" | `services/message_apis/pipedrive_api_mutants_spec.rb` |  |
| R31 | `ma/safe_download.rb` | redirect check limited to 301 | 302 with location: [nil, location] | `services/message_apis/safe_download_read_response_spec.rb` | да |
| R32 | `ma/safe_download.rb` | non-success responses are read | 404 response (read_body stubbed to yield bytes): nil | `services/message_apis/safe_download_read_response_spec.rb` | да |
| R33 | `ma/safe_download.rb` | content-length limit > to >= | 200 with content-length == max_bytes and that many bytes: body returned | `services/message_apis/safe_download_read_response_spec.rb` |  |
| R34 | `ma/safe_download.rb` | content-length check removed | 200 with content-length > max_bytes, read_body yields fewer bytes: nil | `services/message_apis/safe_download_read_response_spec.rb` |  |
| R35 | `ma/safe_download.rb` | chunk limit > to >= | 200 without content-length, chunks totalling exactly max_bytes: body returned | `services/message_apis/safe_download_read_response_spec.rb` |  |
| R36 | `ma/safe_download.rb` | chunks not appended | 200 body chunks "ab", "cd": result body reads "abcd" | `services/message_apis/safe_download_read_response_spec.rb` |  |
| R37 | `ma/safe_download.rb` | body content_type dropped | 200 with content-type "image/png; x=y": body.content_type and mime_type "image/png" | `services/message_apis/safe_download_read_response_spec.rb` |  |
| R38 | `ma/slack/api.rb` | lookupByEmail query email to user | WebMock stub on ...?email=... answers | `services/message_apis/slack_notify_event_spec.rb` | да |
| R39 | `ma/slack/api.rb` | notify_message posts again for an already sent part | part with a slack ConversationPartChannelSource: post_message not called | `services/message_apis/slack_notify_event_spec.rb` |  |
| R40 | `ma/slack/api.rb` | event data keeps blank values | event data {"label" => "Done", "status" => ""}: text "*event*: closed \n *LABEL*: Done" | `services/message_apis/slack_notify_event_spec.rb` |  |
| R41 | `ma/slack/api.rb` | event data Hash check to truthiness | event data a JSON string "abc" (or [["k", "v"]]): no error, text "*event*: closed \n " | `services/message_apis/slack_notify_event_spec.rb` |  |
| R42 | `ma/slack/api.rb` | assigned && email to || | closed event with nil data: no error | `services/message_apis/slack_notify_event_spec.rb` | да |
| R43 | `ma/slack/api.rb` | assigned lookup without the email check | assigned event without email: get_slack_user_by_email not called, no <@ in text | `services/message_apis/slack_notify_event_spec.rb` |  |
| R44 | `ma/slack/api.rb` | assigned mention uses name instead of id | assigned event with email, lookup stubbed {"id" => "U1", "name" => "bob"}: text ends "\n <@U1>" | `services/message_apis/slack_notify_event_spec.rb` |  |
| R45 | `ma/slack/api.rb` | notify_message posts without a slack channel | conversation without a slack conversation_channel: post_message not called | `services/message_apis/slack_notify_event_spec.rb` |  |
| R46 | `ma/slack/api.rb` | thread_ts dropped | post_message options thread_ts == the channel's provider_channel_id | `services/message_apis/slack_notify_event_spec.rb` |  |
| R47 | `ma/slack/api.rb` | channel option dropped | config channel_id "C1": post_message options channel == "C1" | `services/message_apis/slack_notify_event_spec.rb` |  |
| R48 | `ma/slack/api.rb` | source row stored even when slack says not ok | post_message reply {ok: false}: no slack ConversationPartChannelSource for the part | `services/message_apis/slack_notify_event_spec.rb` |  |
| R49 | `ma/slack/api.rb` | message_source_id not stored | post_message reply {ok: true, ts: "9.9"}: source row message_source_id "9.9" | `services/message_apis/slack_notify_event_spec.rb` |  |

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-mutr5b1-ci`) на
клоне `main` `5d3379dd` (дерево кода и спек равно R5b-1 HEAD `65ace2b8`):

1. Все 49 патчей применяются к BASE (`git apply --check`), меняют свой файл, мутант проходит `ruby -c`;
   ни один не совпадает с `M01`–`M15` гейта R5b-1.
2. Предпроверка (`mutr_kill_gate.sh --jobs`, у каждого мутанта — спека R5b-1 его файла): без мутантов
   32 примера в 8 файлах зелёные; спеки BASE уже убивают 12 (`R02`, `R08`, `R10`, `R14`, `R17`, `R18`,
   `R19`, `R24`, `R31`, `R32`, `R38`, `R42` — колонка «уже убит»); остальные 37 выживают.
3. Снимки AC-001 сняты `--write-base` на BASE: 795 примеров, 0 failures, 30 pending.
4. Пробный прогон конструктора (клон, где спека и пробники закоммичены поверх BASE, как сделает
   постановщик):
   - чистый клон без работы: AC-001, AC-002, AC-003, AC-006, AC-007, AC-008 — rc=0; AC-004 и AC-005 —
     rc=1 (манифеста ещё нет) — так и задумано;
   - пять образцовых поведенческих спек (R04, R09, R15, R33, R48) плюс R02, R42 со спеками BASE:
     `mutr_kill_gate.sh --only R04,R09,R15,R33,R48,R02,R42` → `MUTR KILL PASS 7/7 killed`;
   - слабый тест (R16 записан на спеку, которая аргумент BotTask не проверяет) → `SURVIVED R16`, rc=1;
     `blocked` в манифесте → AC-004 FAIL; правка `app/models/audit.rb` → AC-002 FAIL;
   - спека, читающая `app/models/audit.rb` через `Rails.root.join(...).read` и `File.read`, **проходит
     гейт убийства** (`MUTR KILL PASS 1/1` на R01) — и именно поэтому есть AC-003: он падает
     (`FAIL: … Rails.root …`, `FAIL: … file/IO access …`, rc=1).

Предположение: каждый мутант таблицы убиваем поведенческим тестом без правки боевого кода (подходы — в
таблице); если нет — раздел 9.

## 5. Что сделать — по шагам

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей.
Перед шагом 1:

```bash
P=docs/specs/mut-r5b1-probes
export CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci
mkdir -p tmp/mutants-r5b1 vendor/bundle
```

**Шаг 1. Манифест.** `jq '{mutants: map({id, status: "killed_new", specs: [], test_added: null})}'
$P/kill_table.json > tmp/mutants-r5b1/manifest.json` и заполняй: `killed_new` — убит новым тестом
(`test_added` — spec-файл с ним, он же в `specs`); `killed` — убит уже существующими спеками (`specs` их
перечисляет, `test_added` — `null`). Других статусов нет: не убил — раздел 9 (`blocked` в `report.json`
с конкретной причиной; AC-004 и AC-005 тогда красные — так и задумано).

**Шаг 2. Тесты — по строке таблицы.** Прочитай патч `$P/patches/<id>.patch` и код вокруг; напиши пример,
который проверяет **поведение**, сломанное мутантом: вызов кода и его результат, строки БД, поднятую
ошибку, двойник или шпион на соседе (WebMock-запрос, `have_received(...).with(...)`). **Чтение исходников
как текста — запрещено и убийством не считается** (AC-003): `Rails.root`, `File`/`IO`/`Dir`/`Pathname`,
пути к `.rb` под `app/ lib/ config/`, `source_location`, `.source`, `RubyVM`, `Ripper`, `Prism`,
`__FILE__`, `open`/`system`/обратные кавычки (их нет и в строках описаний). Проверь:

```bash
git add spec && git commit -qm "Add tests for audit mutants"
bash $P/mutr_kill_gate.sh --only R01,R02        # список id через запятую
```

Нужно `MUTR BASELINE …` (без мутанта всё зелёное) и `KILLED <id>`. `SURVIVED` — усиль пример.
Новые spec-файлы — `# frozen_string_literal: true`, `require "rails_helper"`, двойные кавычки, строки
≤ 120; HTTP — только WebMock (как в `pipedrive_api_spec.rb`); глобальное состояние — вернуть в `ensure`.

**Шаг 3.** Коммиты — только `spec/`. **Шаг 4.** Все восемь критериев раздела 7; AC-005 (все 49, ≈ 20 мин)
— последним. **Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-004 — строка `mutants: …`;
AC-005 — `MUTR KILL PASS 49/49 killed`; AC-001 — итог примеров.

## 6. Не трогать

- Ничего вне `spec/`: `app/`, `lib/`, `config/`, `vendor/`, `db/`, `Gemfile*`, `.rubocop*`, `.rspec`,
  `bin/`, workflows. Мутанты не применять к дереву клона. Боевой код равен BASE.
- Существующие примеры под `spec/` не удалять, не skip-ать, не ослаблять (AC-001 требует все примеры
  BASE). Не добавлять `.rspec-local` и игнорируемые файлы под `spec/`.
- `docs/specs/**` — не править (AC-007, sha256): ни таблицу, ни классификацию, ни патчи.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec с новыми тестами строго зелёный: SPEC_OPTS не задан, .rspec-local нет, тела примеров выполнены (сторож); 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет новых warning-строк.
  `bash -c 'CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci bash docs/specs/mut-r5b1-probes/rspec_gate_mutr.sh'`

- **AC-002** — изменён только spec/: против BASE и в каждом коммите — только добавленные или изменённые обычные файлы под spec/; вне spec/ HEAD и рабочее дерево равны BASE; нет лишних неотслеживаемых и игнорируемых файлов.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b1-probes/mutr_probe.py scope $B'`

- **AC-003** — нет чтения исходников как текста: ни одна добавленная строка под spec/ не содержит Rails.root, File/IO/Dir/Pathname/FileUtils/Tempfile, путь к .rb под app/lib/config/vendor/db, source_location, .source, RubyVM, Ripper, Prism, __FILE__, __dir__, ObjectSpace, open/system/spawn/exec, %x, обратные кавычки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b1-probes/mutr_probe.py scan $B'`

- **AC-004** — классификация: в tmp/mutants-r5b1/manifest.json ровно id kill_table.json, каждый killed или killed_new (blocked, survived, equivalent — провал) со своими spec-файлами; у killed_new test_added изменён с BASE и есть в specs.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b1-probes/mutr_probe.py check $B'`

- **AC-005** — убийство переприложением: на копии HEAD без мутантов спеки всех мутантов без failed-примеров; каждый из 49 патчей пробника приложен по одному и меняет файл; с ним спеки из манифеста дают упавший пример (killed_new — в своём test_added) и ни одной ошибки вне примеров; статусы исполнителя не учитываются.
  `bash -c 'CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci bash docs/specs/mut-r5b1-probes/mutr_kill_gate.sh'`

- **AC-006** — строгий RuboCop как в CI: все отслеживаемые файлы (с новыми spec-файлами), ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutr5b1-ci bin/ci-local --only rubocop'`

- **AC-007** — коммитов в docs/specs нет, пробники, патчи, таблицы и снимки не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "b3391e8b9ce549f0ab3b99075afa0960f333f5fe666d9f2ea556ad7f3bd9965a  docs/specs/mut-r5b1-probes/mutr_probe.py" "d92b8231bf0243f6260678eea391786f46206628e085d80eddae8d2f2efaaf3a  docs/specs/mut-r5b1-probes/mutr_kill.rb" "74b8ff629d2695351ec6cab1863296f0c42687c6bf5758c60ebafed663c7ce75  docs/specs/mut-r5b1-probes/mutr_kill_gate.sh" "5f3774a12b3f9f8fd2f143d905894f02397b5f0ee06261e8d8c918d03afbb087  docs/specs/mut-r5b1-probes/kill_table.json" "491b63a904ec5c40caa250a5042f131b1141879a56d635d4b7efcc4da3aa92a1  docs/specs/mut-r5b1-probes/classified.json" "d5692add8a9df664a46cb5a2399420e851d9995af16574200d316da8ff8bab23  docs/specs/mut-r5b1-probes/patches.sha256" "6be748cba6b6a46fb0134fa0b3f7841c6c2debcb6b3661f9069a7ce61819d2e7  docs/specs/mut-r5b1-probes/rspec_gate_mutr.sh" "8bab133d7b4b501311443463369a4930c1a9128f28ba24d3977d567731a30cc7  docs/specs/mut-r5b1-probes/mutr_sentinel.rb" "be7e6ae830e699796dfa37294fc3002c960fd56ba1ecaa5406d15665519f3b1c  docs/specs/mut-r5b1-probes/examples_base.txt" "414373dc4a98d50070835a8ee1f811789902db649830d168740ef7cec9a83bfa  docs/specs/mut-r5b1-probes/pending_allowed.txt" "9c6685303a1a585c36970ed04b32cb869ad1f123026d074db42f66de122c5d0f  docs/specs/mut-r5b1-probes/warnings_base.txt" | sha256sum -c --quiet - && sha256sum -c --quiet docs/specs/mut-r5b1-probes/patches.sha256 && test "$(ls docs/specs/mut-r5b1-probes/patches | wc -l)" = 49 && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), кроме untracked report.json и report-blocked.md; нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-002, AC-003, AC-006, AC-007, AC-008 зелёные; AC-004 и AC-005
красные (`tmp/mutants-r5b1/manifest.json: … No such file`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Codex);
один заход исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/mut-r5b1.md --exclude "docs/specs/mut-r5b1-probes/**" --context "chaskiq mut-r5b1: тесты только под spec/ на 49 новых мутантов кода, который покрывают спеки R5b-1; убийство только поведенческое (чтение исходников запрещено), проверяет пробник переприложением патчей; боевой код не меняется; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/mut-r5b1.md
REVIEW_EXCLUDE: docs/specs/mut-r5b1-probes/**

Контекст ревьюерам: убивает ли каждый тест именно поведение мутанта (а не падает на загрузке, опечатке
или на чтении кода); не ослаблены ли существующие тесты; нет ли зависимости от порядка, сети, времени без
`travel_to`; возвращено ли глобальное состояние.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда критерий выполнить нельзя: `"rc": null` и дословная ошибка или причина в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/mut-r5b1.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/mut-r5b1.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и `report.json`
готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md` (id, патч, что
пробовал, дословный вывод `mutr_kill_gate.sh --only <id>`), в `report.json` у AC-004/AC-005 — `blocked`
с этими id и конкретной причиной, и доложи, НЕ обходя:
- мутант нельзя убить поведенческим тестом без правки боевого кода — id и почему (довод по коду);
- мутант кажется эквивалентным — id и довод по коду (не «тесты этого не проверяют»); объявлять
  эквивалентность сам не вправе, в манифест `equivalent` не писать;
- тест на правильное поведение красный и без мутанта (настоящий дефект кода) — не чинить код, тест не
  коммитить, описать;
- сьют BASE красный или флапает (приложи два прогона), образ/кэш/сервисы недоступны;
- пробник противоречит спеке или коду BASE (дефект спеки).
Запрещено: файлы вне `spec/`, правка пробников/таблиц/патчей, удалять/ослаблять/skip-ать тесты,
чтение исходников в тестах, глушить вывод и коды возврата.

## 10. Стыки

- 15 мутантов гейта R5b-1 (`M01`–`M15`) этот прогон не повторяет и не перепроверяет.
- Найденный дефект кода (раздел 9) — отдельная веха с тестом «красный на BASE».
