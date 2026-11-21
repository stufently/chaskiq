# mut-r5b2 — отдельный мутационный прогон по новым тестам R5b-2

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/mut-r5b2.md`, пробники — `docs/specs/mut-r5b2-probes/`.
  Проверяемая веха — `docs/specs/fork-updates-r5b2.md` (влита в `main` коммитом `7392c442`).
- BASE_SHA: `ff28cdb92caabb5d77c2329e6a3e39bf3953182e` — HEAD `main` после влития R5b-2, R6c и mut-m9-m14b.
- BASE плавающий: постановщик переносит строку BASE_SHA на коммит, которым кладёт эту спеку в `main`,
  и только потом снимает клон (раздел 2). Все патчи обязаны прикладываться к этому коммиту. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`).
- Исполнитель: **Codex (`cx`)** (R5b-2 писал Qwen — мутации у противоположного исполнителя).
  **Не останавливайся, пока все восемь критериев раздела 7 не зелёные — или пока не сработал пункт
  раздела 9.**
- Цель: каждый из 48 мутантов таблицы `kill_table.json` убит **поведенческим** тестом (только файлы
  под `spec/`, боевой код равен BASE). Мутанты — новые, независимые от 20 мутантов гейта R5b-2
  (`fork-updates-r5b2-probes/r5b2_config.json`, `M01`–`M20`), по коду, который покрывают 12 новых
  спек R5b-2. Эквивалентные постановщик уже исключил (раздел 3); **исполнитель эквивалентность не
  объявляет.** Убийство проверяет пробник сам: прикладывает патч из `docs/specs/mut-r5b2-probes/patches/`
  (не из файлов исполнителя) и гоняет спеки, которые исполнитель записал в манифест.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается
(AC-003 — сканер добавленных строк `spec/`). Сравнение `to_sql` с текстом — тоже не убийство: проверяй
записи, которые вернул запрос (так слаб пример R5b-2 `bot_task_infix_spec.rb` «SQL содержит `@>`» —
мутант Q13 он не ловит).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `mut-r5b2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-mutr5b2-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).
- Мутанты НИКОГДА не применяются к дереву клона и не коммитятся: пробник гоняет их на копии
  (`git archive HEAD` → `tmp/mutr-kill/`). Поэтому тесты надо **закоммитить** до прогона гейта.
  Манифест исполнителя — `tmp/mutants-r5b2/manifest.json` (игнорируется git, не коммитится).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-mutr5b2-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r3b2-ci $HOME/.cache/chaskiq-mutr5b2-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: `git apply --check` всех `patches/*.patch` на новом HEAD
   (не прикладываются — пересобрать по описанию таблицы); если менялся `spec/` — на чистом
   checkout `main` `CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci bash docs/specs/mut-r5b2-probes/rspec_gate_mutr.sh --write-base`
   и пересчитать sha256 снимков в AC-007. **Пересечения:** R3b-2 и fix-cleanup-bugs не трогают файлы
   этих мутантов, кроме `app/models/message.rb` (R3b-2, строка 22 `scope :ordered`; мутанты Q13–Q15 —
   строки 106-119). Проверено: все 48 патчей применяются и поверх собранных деревьев R3b-2 и fix-cleanup-bugs (обе сразу);
   вливание любой из них перед запуском требует только переноса BASE и `--write-base`.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-007 и строку
   BASE_SHA (= этот коммит или его родитель — `B` вычисляется по `@{u}`). Только после этого — `make_clone.sh`.

## 3. Мутанты и почему

Новые спеки R5b-2: `subdomain_or_domain_spec.rb`, `list_importer_leads_spec.rb`,
`action_trigger_factory_segment_spec.rb`, `bot_task_infix_spec.rb`, `app_package_integration_presenter_spec.rb`,
`application_controller_cookie_spec.rb`, `update_conversation_state_spec.rb`, `sns_receiver_job_campaign_spec.rb`,
`subscribable_payment_attribute_spec.rb`, `safe_download_limits_spec.rb`, `app_user_trigger_job_spec.rb`,
`conversation_authors_spec.rb`. Гейт R5b-2 уже прогнал 20 мутантов (`M01`–`M20`); здесь — 48 других правок
тех же методов.

Мутантов по файлам: `subdomain_routes.rb` 3, `list_importer.rb` 6, `action_trigger_factory.rb` 3, `message.rb` 3, `app_package_integration.rb` 2, `application_controller.rb` 1, `update_state.rb` 5, `sns_receiver_job.rb` 4, `subscribable.rb` 2, `safe_download.rb` 8, `app_user_trigger_job.rb` 5, `insert_comment.rb` 3, `start_conversation.rb` 1, `create_app.rb` 2.

**Два слабых места R5b-2 (ревью Codex) — мутанты, которые их вскрывают:**
- `bot_task_infix_spec.rb`: положительный пример хранит ровно предикат фильтра, поэтому направление
  содержания (`@>`) ловит только пример с текстом SQL. **Q13** меняет местами операнды `@>` (фильтр
  содержит сегменты): SQL по-прежнему содержит `@>`, а запись с ровно предикатом фильтра находится обоими.
  Убивает только запись, у которой в `segments` есть предикат типа И ещё один.
- `safe_download_limits_spec.rb`: пример предела редиректов проверяет только `nil`. **Q31** останавливается
  на редирект раньше (`hop + 1 == max_redirects`) — тоже `nil`, но второй адрес не запрашивается; **Q30**
  делает на один проход меньше (`max_redirects.times`) — тоже `nil` на тесте предела, но не доходит до
  тела в пределах лимита. Убивают: проверка, какие адреса запрошены (WebMock::API `assert_requested(..., times: 1)` /
  `assert_not_requested`; матчеров `have_been_made` без `webmock/rspec` нет), и цепочка `a → b → 200` при `max_redirects: 1`.

- **Эквивалентные (7), исключены из таблицы** (`classified.json`, довод по коду):
  - `E1` `list_importer.rb` — data is built from row before the delete and row is not read afterwards in the callback: the same email and properties reach add_user/add_lead.
  - `E2` `list_importer.rb` — @row_count is never read (no notification or mail uses it).
  - `E3` `app_package_integration.rb` — "...".constantize of a missing package raises NameError; nothing else in the method can raise.
  - `E4` `subscribable.rb` — payment_service returns only Paddle or StripeService, so after the Stripe branch the Paddle comparison is always true.
  - `E5` `app_user_trigger_job.rb` — without the guard a nil first_path raises NoMethodError on with_indifferent_access; with it, step is nil and step[:messages] raises the same NoMethodError on the next line.
  - `E6` `safe_download.rb` — the loop already returns nil at hop == max_redirects, so the extra iteration is never reached (kept: return nil if hop == limits.max_redirects).
  - `E7` `safe_download.rb` — removing the check only lets the loop run out after hop max_redirects without downloading again: same nil and same requests (R5b-2 dropped it as equivalent too).
- **Остальные 48 — убить.** «уже убит» — мутант падает на спеках R5b-2 его файла (раздел 4): такие
  можно записать `killed` со спеками BASE; остальным нужен новый тест (`killed_new`).

`ma/` = `app/services/message_apis/`, `mut/` = `app/graphql/mutations/`, спека — от `spec/` (предложение,
можно свой файл; существующие примеры не трогать):

| id | файл | мутант | как убить | спека | уже убит |
|---|---|---|---|---|---|
| Q01 | `lib/subdomain_routes.rb` | one subdomain treated as none | help.example.com: true | `lib/subdomain_or_domain_mutants_spec.rb` | да |
| Q02 | `lib/subdomain_routes.rb` | bare domain returns false instead of nil | example.com: nil (not false) | `lib/subdomain_or_domain_mutants_spec.rb` | да |
| Q03 | `lib/subdomain_routes.rb` | multi-segment subdomain reduced to its last segment | APP_SUBDOMAINS stubbed ["www.help"]: www.help.example.com false; stubbed ["help"]: www.help.example.com true | `lib/subdomain_or_domain_mutants_spec.rb` | да |
| Q04 | `app/importers/list_importer.rb` | type leads imported as users | type leads: two Lead rows, no AppUser of type AppUser | `importers/list_importer_mutants_spec.rb` | да |
| Q05 | `app/importers/list_importer.rb` | row properties dropped | imported contact properties include name "Lead" and last_name "One" | `importers/list_importer_mutants_spec.rb` |  |
| Q06 | `app/importers/list_importer.rb` | column names not normalised | column "last name": property key "last_name" (not "last name") | `importers/list_importer_mutants_spec.rb` |  |
| Q07 | `app/importers/list_importer.rb` | import tag not saved | reloaded contact tag_list starts with "import " | `importers/list_importer_mutants_spec.rb` | да |
| Q08 | `app/importers/list_importer.rb` | import mail not sent | import: ImportMailer.notify received with(app:, agent:) and the mail delivered | `importers/list_importer_mutants_spec.rb` |  |
| Q09 | `app/importers/list_importer.rb` | import mail to the first agent | two agents, agent_id of the second: ImportMailer.notify with agent: the second | `importers/list_importer_mutants_spec.rb` |  |
| Q10 | `app/services/action_trigger_factory.rb` | rule without predicates crashes | rule {"trigger" => bot.id} without predicates: returns bot | `services/action_trigger_factory_mutants_spec.rb` |  |
| Q11 | `app/services/action_trigger_factory.rb` | only the first rule is checked | rules [non-matching for bot A, matching for bot B]: returns B | `services/action_trigger_factory_mutants_spec.rb` |  |
| Q12 | `app/services/action_trigger_factory.rb` | trigger looked up outside the app | matching rule whose trigger is a bot of another app: raises ActiveRecord::RecordNotFound | `services/action_trigger_factory_mutants_spec.rb` |  |
| Q13 | `app/models/message.rb` | @> operands swapped (filter contains segments) | task whose segments = type predicate for AppUser PLUS another predicate (e.g. email eq): found by infix(["AppUser"]) | `models/bot_task_infix_mutants_spec.rb` |  |
| Q14 | `app/models/message.rb` | type predicate comparison in to eq | segments written as literal JSON [{value: ["AppUser"], type: "string", attribute: "type", comparison: "in"}] (update_column): found by infix(["AppUser"]) | `models/bot_task_infix_mutants_spec.rb` |  |
| Q15 | `app/models/message.rb` | type predicate attribute renamed | type_predicate_for(["Lead"]) == [{value: ["Lead"], type: "string", attribute: "type", comparison: "in"}]; literal segments found | `models/bot_task_infix_mutants_spec.rb` |  |
| Q16 | `app/models/app_package_integration.rb` | unknown package presenter nil | unknown package: presenter == ExternalPresenterManager, external_package? true | `models/app_package_integration_mutants_spec.rb` | да |
| Q17 | `app/models/app_package_integration.rb` | presenter ignores the package | Calendly integration: presenter == MessageApis::Calendly::Presenter, external_package? false | `models/app_package_integration_mutants_spec.rb` |  |
| Q18 | `app/controllers/application_controller.rb` | cookie name a String, not a Symbol | cookie_namespace is a Symbol equal to :chaskiq_session_id_<key without dashes> | `controllers/application_controller_cookie_mutants_spec.rb` | да |
| Q19 | `mut/conversations/update_state.rb` | state change not logged | close: Conversation#log_async received with(action: "close", user: agent, ip: request.remote_ip) | `graphql/mutations/update_conversation_state_mutants_spec.rb` |  |
| Q20 | `mut/conversations/update_state.rb` | logged action renamed | close: log_async action "close"; reopen: action "reopen" | `graphql/mutations/update_conversation_state_mutants_spec.rb` |  |
| Q21 | `mut/conversations/update_state.rb` | logged ip dropped | log_async ip == context[:request].remote_ip | `graphql/mutations/update_conversation_state_mutants_spec.rb` |  |
| Q22 | `mut/conversations/update_state.rb` | errors not returned | resolve result: conversation == the conversation, errors is an empty ActiveModel::Errors | `graphql/mutations/update_conversation_state_mutants_spec.rb` |  |
| Q23 | `mut/conversations/update_state.rb` | state matched case-insensitively | state "Close": state stays opened, no log_async | `graphql/mutations/update_conversation_state_mutants_spec.rb` |  |
| Q24 | `app/jobs/sns_receiver_job.rb` | tracks with a missing campaign | campaign not found (find_by nil), user found: user does not receive track_click | `jobs/sns_receiver_job_mutants_spec.rb` |  |
| Q25 | `app/jobs/sns_receiver_job.rb` | bounces no longer unsubscribe | permanent bounce of the user's email: user state unsubscribed | `jobs/sns_receiver_job_mutants_spec.rb` |  |
| Q26 | `app/jobs/sns_receiver_job.rb` | bounce type check inverted | permanent bounce: unsubscribed; transient bounce: stays subscribed | `jobs/sns_receiver_job_mutants_spec.rb` |  |
| Q27 | `app/jobs/sns_receiver_job.rb` | campaign detected by the TO header | headers with X-CHASKIQ-CAMPAIGN-TO only (no CAMPAIGN-ID): no tracking, no error | `jobs/sns_receiver_job_mutants_spec.rb` |  |
| Q28 | `app/models/concerns/subscribable.rb` | payment service on nil instead of present | paddle_subscription_plan_id nil: payment_attribute returns the stripe value | `models/concerns/subscribable_mutants_spec.rb` | да |
| Q29 | `app/models/concerns/subscribable.rb` | paddle falls back to stripe | paddle app with paddle_subscription_status nil, stripe "active": payment_attribute nil | `models/concerns/subscribable_mutants_spec.rb` |  |
| Q30 | `ma/safe_download.rb` | one hop fewer | max_redirects: 1, a -> b (302) -> 200 body: body returned; a and b requested once | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q31 | `ma/safe_download.rb` | stops one redirect early (still nil on the limit test) | max_redirects: 1, a -> b -> c (all 302): nil, a and b requested once each, c never; a -> b -> 200: body | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q32 | `ma/safe_download.rb` | url_allowed inverted | url_allowed -> true: body returned | `services/message_apis/safe_download_limits_mutants_spec.rb` | да |
| Q33 | `ma/safe_download.rb` | url_allowed only on the first hop | a -> 302 to other.example.com, url_allowed rejects other.example.com: nil, other host never requested | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q34 | `ma/safe_download.rb` | headers forwarded to redirect targets | headers {"Authorization" => "x"}: first request has it, the redirected request does not | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q35 | `ma/safe_download.rb` | relative Location not resolved | 302 Location "/b": https://cdn.example.com/b requested, its body returned | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q36 | `ma/safe_download.rb` | default redirect limit 3 to 2 | default limits, three 302 hops then 200: body returned | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q37 | `ma/safe_download.rb` | deadline guard inverted (always nil) | plain 200 fetch with default limits: body returned | `services/message_apis/safe_download_limits_mutants_spec.rb` |  |
| Q38 | `app/jobs/app_user_trigger_job.rb` | last message of the step | step with two messages: add_message gets the first one's html_content | `jobs/app_user_trigger_job_mutants_spec.rb` |  |
| Q39 | `app/jobs/app_user_trigger_job.rb` | lock ignored | trigger_locked.value set: perform adds no message | `jobs/app_user_trigger_job_mutants_spec.rb` |  |
| Q40 | `app/jobs/app_user_trigger_job.rb` | lock not set | after perform: user.trigger_locked.value present | `jobs/app_user_trigger_job_mutants_spec.rb` |  |
| Q41 | `app/jobs/app_user_trigger_job.rb` | existing conversation ignored | perform with an existing conversation key: message added there, no new conversation | `jobs/app_user_trigger_job_mutants_spec.rb` |  |
| Q42 | `app/jobs/app_user_trigger_job.rb` | new conversation without the bot initiator | perform without a conversation: new conversation initiator == app.agent_bots.first | `jobs/app_user_trigger_job_mutants_spec.rb` |  |
| Q43 | `mut/conversations/insert_comment.rb` | insert_comment ignores the text | message text "plain", html "<p>rich</p>": part text_content "plain" | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |
| Q44 | `mut/conversations/insert_comment.rb` | insert_comment html not stripped | html "<p>rich</p>": part html_content "rich" | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |
| Q45 | `mut/conversations/insert_comment.rb` | insert_comment serialized content dropped | part serialized_content == the serialized JSON | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |
| Q46 | `mut/conversations/start_conversation.rb` | start_conversation subject dropped | subject "Hi": conversation subject "Hi" | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |
| Q47 | `mut/apps/create_app.rb` | blank operation creates an app | operation nil: app not persisted, agent apps unchanged | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |
| Q48 | `mut/apps/create_app.rb` | operation new creates an app | operation "new": app not persisted | `graphql/mutations/conversation_authors_mutants_spec.rb` |  |

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-mutr5b2-ci`) на
клоне BASE ff28cdb9:

1. Все патчи применяются к BASE, меняют свой файл и грузятся (у выживших 0 ошибок вне примеров);
   ни один не совпадает с `M01`–`M20` гейта R5b-2.
2. Предпроверка (`mutr_kill_gate.sh --jobs`, у каждого мутанта — спека R5b-2 его файла): без мутантов
   29 примеров в 12 файлах зелёные; спеки BASE уже убивают 9 (`Q01`–`Q04`, `Q07`, `Q16`, `Q18`, `Q28`,
   `Q32` — колонка «уже убит», все — проваленной проверкой); остальные 39 выживают, в том числе Q13, Q30, Q31.
3. Снимки AC-001 сняты `--write-base` на BASE: 945 примеров, 0 failures, 30 pending.
4. Пробный прогон конструктора (свежий клон `main` ff28cdb9, спека и пробники закоммичены поверх, как
   сделает постановщик):
   - чистый клон без работы: AC-002, AC-003, AC-006, AC-007, AC-008 — rc=0; AC-004 — rc=1 (манифеста ещё
     нет), AC-005 тоже красный — так и задумано;
   - четыре образцовые поведенческие спеки (Q13 — запись с предикатом типа и ещё одним; Q30/Q31 — какие
     адреса запрошены и цепочка `a → b → 200`; Q19/Q21 — `log_async` с действием, агентом и ip; Q47 —
     `operation: nil` не сохраняет приложение) плюс Q01 со спекой BASE:
     `mutr_kill_gate.sh --only Q13,Q30,Q31,Q19,Q21,Q47,Q01` → `MUTR KILL PASS 7/7 killed`; с ними AC-001
     (950 примеров, 0 failures, сторож 922), AC-002, AC-003, AC-006–AC-008 зелёные;
   - слабый тест (Q14 записан на спеку Q13, которая пишет сегменты через `type_predicate_for`) →
     `SURVIVED Q14`; `blocked` в манифесте → AC-004 FAIL; правка `app/models/lead.rb` → AC-002 FAIL;
     спека с `Rails.root.join("app/models/message.rb").read` → AC-003 FAIL; файлов от root нет.

Предположение: каждый мутант таблицы убиваем поведенческим тестом без правки боевого кода (подходы — в
таблице); если нет — раздел 9.

## 5. Что сделать — по шагам

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей.
Перед шагом 1:

```bash
P=docs/specs/mut-r5b2-probes
export CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci
mkdir -p tmp/mutants-r5b2 vendor/bundle
```

**Шаг 1. Манифест.** `jq '{mutants: map({id, status: "killed_new", specs: [], test_added: null})}'
$P/kill_table.json > tmp/mutants-r5b2/manifest.json` и заполняй: `killed_new` — убит новым тестом
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
git add spec && git commit -qm "Add tests for infix mutants"
bash $P/mutr_kill_gate.sh --only Q13,Q14        # список id через запятую
```

Нужно `MUTR BASELINE …` (без мутанта всё зелёное) и `KILLED <id>`. `SURVIVED` — усиль пример.
Новые spec-файлы — `# frozen_string_literal: true`, `require "rails_helper"`, двойные кавычки, строки
≤ 120; HTTP — только WebMock (как в `safe_download_limits_spec.rb`); глобальное состояние — вернуть в `ensure`.

**Шаг 3.** Коммиты — только `spec/`. **Шаг 4.** Все восемь критериев раздела 7; AC-005 (все 48, ≈ 20 мин)
— последним. **Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-004 — строка `mutants: …`;
AC-005 — `MUTR KILL PASS 48/48 killed`; AC-001 — итог примеров.

## 6. Не трогать

- Ничего вне `spec/`: `app/`, `lib/`, `config/`, `vendor/`, `db/`, `Gemfile*`, `.rubocop*`, `.rspec`,
  `bin/`, workflows. Мутанты не применять к дереву клона. Боевой код равен BASE.
- Существующие примеры под `spec/` не удалять, не skip-ать, не ослаблять (AC-001 требует все примеры
  BASE). Не добавлять `.rspec-local` и игнорируемые файлы под `spec/`.
- `docs/specs/**` — не править (AC-007, sha256): ни таблицу, ни классификацию, ни патчи.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec с новыми тестами строго зелёный: SPEC_OPTS не задан, .rspec-local нет, тела примеров выполнены (сторож); 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет новых warning-строк.
  `bash -c 'CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci bash docs/specs/mut-r5b2-probes/rspec_gate_mutr.sh'`

- **AC-002** — изменён только spec/: против BASE и в каждом коммите — только добавленные или изменённые обычные файлы под spec/; вне spec/ HEAD и рабочее дерево равны BASE; нет лишних неотслеживаемых и игнорируемых файлов.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py scope $B'`

- **AC-003** — нет чтения исходников как текста: ни одна добавленная строка под spec/ не содержит Rails.root, File/IO/Dir/Pathname/FileUtils/Tempfile, путь к .rb под app/lib/config/vendor/db, source_location, .source, RubyVM, Ripper, Prism, __FILE__, __dir__, ObjectSpace, open/system/spawn/exec, %x, обратные кавычки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py scan $B'`

- **AC-004** — классификация: в tmp/mutants-r5b2/manifest.json ровно id kill_table.json, каждый killed или killed_new (blocked, survived, equivalent — провал) со своими spec-файлами; у killed_new test_added изменён с BASE и есть в specs.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py check $B'`

- **AC-005** — убийство переприложением: на копии HEAD без мутантов спеки всех мутантов без failed-примеров; каждый из 48 патчей пробника приложен по одному и меняет файл; с ним спеки из манифеста дают упавший пример (killed_new — в своём test_added) и ни одной ошибки вне примеров; статусы исполнителя не учитываются.
  `bash -c 'CHASKIQ_MUTR_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci bash docs/specs/mut-r5b2-probes/mutr_kill_gate.sh'`

- **AC-006** — строгий RuboCop как в CI: все отслеживаемые файлы (с новыми spec-файлами), ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutr5b2-ci bin/ci-local --only rubocop'`

- **AC-007** — коммитов в docs/specs нет, пробники, патчи, таблицы и снимки не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "78d0d459d7c89db2d0229c077ae9d7434d2f87eb43bd21d482845e7aa3bb6dda  docs/specs/mut-r5b2-probes/mutr_probe.py" "1bc84dbd67a08dbec9c364a04c1450f7119db4ed1dc927ec0a5b668514efb3a8  docs/specs/mut-r5b2-probes/mutr_kill.rb" "d179b236f247f2d5cab8a3de3f8155faea22401a03aecd4ec0b7a2ddea293654  docs/specs/mut-r5b2-probes/mutr_kill_gate.sh" "f255f3a43ecbdef5e50b1b3685f23bc658482590243019c685d1d077ac368d00  docs/specs/mut-r5b2-probes/kill_table.json" "752348936c5e2b47231be3be0de1261ce9b37e97a44f6a33823a92e3b03f5cdd  docs/specs/mut-r5b2-probes/classified.json" "032d53b4e259435d0e7bf1b492e9956e8855463552f7311a5618ce3b52bc383e  docs/specs/mut-r5b2-probes/patches.sha256" "24b439f13e29a17ba7b5299013bdd4d274ab87418f38f60a5f3bcf7f1d7b0e3c  docs/specs/mut-r5b2-probes/rspec_gate_mutr.sh" "8bab133d7b4b501311443463369a4930c1a9128f28ba24d3977d567731a30cc7  docs/specs/mut-r5b2-probes/mutr_sentinel.rb" "a0a9778af2766c14c28c330b1ad90e9d437a981c4c613fea580a56cfa0063f28  docs/specs/mut-r5b2-probes/examples_base.txt" "8481b827024aa1f161b519d586a46805aca4f976f0e157c228ce85d28ea97fe5  docs/specs/mut-r5b2-probes/pending_allowed.txt" "20fab06f2294ae690784481c9314ea7c4c67d1be288b8a98bed48cb9971c921a  docs/specs/mut-r5b2-probes/warnings_base.txt" | sha256sum -c --quiet - && sha256sum -c --quiet docs/specs/mut-r5b2-probes/patches.sha256 && test "$(ls docs/specs/mut-r5b2-probes/patches | wc -l)" = 48 && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), кроме untracked report.json и report-blocked.md; нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-002, AC-003, AC-006, AC-007, AC-008 зелёные; AC-004 и AC-005
красные (`tmp/mutants-r5b2/manifest.json: … No such file`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Codex);
один заход исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/mut-r5b2.md --exclude "docs/specs/mut-r5b2-probes/**" --context "chaskiq mut-r5b2: тесты только под spec/ на 48 новых мутантов кода, который покрывают спеки R5b-2; убийство только поведенческое (чтение исходников запрещено), проверяет пробник переприложением патчей; боевой код не меняется; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/mut-r5b2.md
REVIEW_EXCLUDE: docs/specs/mut-r5b2-probes/**

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
  "spec_sha256": "<sha256 файла docs/specs/mut-r5b2.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/mut-r5b2.md --dry-run`, добиться кода 2.

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

- 20 мутантов гейта R5b-2 (`M01`–`M20`) этот прогон не повторяет и не перепроверяет.
- Найденный дефект кода (раздел 9) — отдельная веха с тестом «красный на BASE».
