# fork-updates-r5b1 — бэклог RuboCop, шаг 5b-1: хвосты Lint после R5/R6a/R6b — сначала тесты, потом правка

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r5b1.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — первая часть R5b оттуда, раздел 10).
- BASE_SHA: `42d0248ed02162cf93b8068e989b3c862ee0599b` — HEAD `main` с влитыми R1–R6b, R7a, R3b-1 и тестами mut-m9-m14
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (раздел 2). Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 30 КБ
  (25 файлов кода по четырём патчам, 8 новых спек, todo, CHANGELOG) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: в `app/` не остаётся `Lint/UselessAssignment`, `Lint/Void`, `Lint/UselessOr`,
  `Lint/UnusedMethodArgument` и `Rails/Present`. **Поведение меняется в одном месте — D1** (решение
  владельца: отправка события в Slack больше не падает на `data` = `nil`/массив); в остальных не
  меняется. Код правки задан патчами постановщика (руками Ruby в `app/` не править), а работа
  исполнителя — спеки: семь характеризационных (зелёные на BASE и после правки), одна спека правки D1
  (красная на BASE, зелёная после), и каждый из 15 мутантов постановщика (`r5b1_config.json`,
  `mutants` — «правка, сделанная неправильно») роняет пример. D2–D4 владелец решил оставить как есть.
- **`spec/`: только 8 НОВЫХ файлов** (раздел 5); существующие спеки не трогать — параллельно идёт
  mut-m9-m14 (его файлы: `spec/controllers/api/v1/hooks_sns_signature_spec.rb`,
  `spec/lib/{nightfury_value,php_serialize}_spec.rb`, `spec/models/conversation_part_channel_source_spec.rb`,
  `spec/services/message_apis/{base_package,block_manager,safe_download_headers}_spec.rb`,
  `spec/services/message_apis/twilio_phone/` — имена этой вехи с ними не пересекаются).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r5b1`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r5b1-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (иначе Docker создаст точку монтирования от root; пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r5b1-ci` — копия `chaskiq-r3b1-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r3b1-ci $HOME/.cache/chaskiq-r5b1-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; проверить `git apply --check` четырёх патчей на
   новом BASE; если менялся `spec/` — перегенерировать список примеров
   `CHASKIQ_R5B1_CACHE=$HOME/.cache/chaskiq-r5b1-ci bash docs/specs/fork-updates-r5b1-probes/rspec_gate_r5b1.sh --write-base`
   на чистом checkout `main`, проверить, что имена восьми новых спек не заняты, и пересчитать sha256
   трёх снимков в AC-007. Сейчас в снимках — список примеров BASE 42d0248e (с тестами mut-m9-m14).
3. Решения владельца D1–D4 получены 2026-11-20 (раздел 3) и уже учтены в патчах и мутантах.
4. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE. Во всех местах ниже правка поведения не меняет; где вывод держится на факте о коде,
факт назван.

**`r5b1_assign.patch` — `Lint/UselessAssignment` (11 файлов `keep` из R6a) и `Lint/UnusedMethodArgument`
(2 презентера `keep` из R6b).** Удаляется запись в переменную; если правая часть — последнее выражение
метода, она остаётся (значение метода то же); если нет — удаляется целиком, только когда она без
побочных эффектов и не бросает там, где не бросила бы следующая строка:
- `app_user_event_job.rb:11` `key = "…"` (чтение атрибутов); `campaign_mailer.rb:16` `attrs =
  subscriber.attributes`, `:34` `content_type = "text/html"` (локальная переменная — не заголовок письма:
  тип и раньше не ставился); `open_ai/presenter.rb:64-65` (литерал и чтение ассоциации; `ctx[:package]`
  читается строкой ниже); `message_bird/api.rb:96,204,211`, `telegram/api.rb:79,184` (чтение хеша
  `params`/`message`, который читается следующей строкой); `slack/api.rb:801` (литерал), `:914`
  (`conversation.main_participant` — чтение ассоциации), `:1050` (`data["files"]` — `data` уже Hash);
  `twilio_phone/presenter.rb:324` (`conversation&.main_participant`); `pipedrive/api.rb:158` (литерал);
  `campaign.rb:106` `link_prefix` (`host` всегда строка — `Message#host` с запасным значением;
  `subscriber.encoded_id` — `URLcrypt` от email; при `subscriber == nil` следующая строка бросает тот же
  `NoMethodError`).
- Последнее выражение — запись убрана, значение осталось: `campaign.rb:122,127` (`campaign_url`,
  `campaign_api_url`), `:209` (`decode_email` возвращает кампанию), `:205-206` (`addr, =`, `_, encoded =`),
  `message_bird/api.rb:250`, `telegram/api.rb:223` (`find_conversation_by_channel`), `pipedrive/api.rb:170,198,213`,
  `slack/api.rb:124,353,777,1020,1051-1053`, `twilio_phone/presenter.rb:176,235,375`, `calendly/presenter.rb:6`
  (`valid_url?` возвращает хост).
- `calendly/presenter.rb:14` `url = …` — удалён (тот же хеш читается строкой ниже).
- `audit.rb:50` `@app = app ||= auditable.app.key` → `@app = app || auditable.app.key` (то же значение;
  у офенса нет автокоррекции).
- `calendly/presenter.rb:163`, `twilio_phone/presenter.rb:7,135` — `params` → `_params` (решение
  владельца по R6b). `result(binding)` в этих файлах — только в `sheet_view`; у переименованных методов
  своё тело, шаблон их переменные не видит.
- Выравнивание (`rubocop -a --only Layout`) после удаления `conversation =` в цепочках — внутри патча.

**`r5b1_void.patch` — `Lint/Void` (14 мест `app/`) и `Lint/UselessOr`.** `self` последней строкой
`initialize` — 12 плагинов и `paddle.rb` (значение `initialize` `new` выбрасывает); `@id` в
`ActionTriggerFactory#initialize` (чтение); `telegram/api.rb:259` `else "photo"` → `else # "photo"`
(литерал ничего не делал; `k.first` — один из шести ключей, `else` и так ловит только `photo`);
`audit.rb:25` `to_s || "--"` → `to_s` (`"--"` недостижим — `to_s` всегда строка).

**`r5b1_leftovers.patch` — три места-кандидата из R6a и `Rails/Present`.**
- `hooks_controller.rb:108` `json_message["mail"]["messageId"]` — голое чтение, оставленное R6a; удалено
  (`json_message["mail"]["headers"]` читается в начале метода, так что `json_message["mail"]` — Hash).
- `dialog360/presenter.rb:112-113` `templates["offset"]` и `nil` — то же; `templates` — Hash (выше уже
  вызывается `templates.dig`).
- `hooks_controller.rb:273` `image_mark.dup << message` — **не баг**: это последнее выражение ветки,
  значение возвращается вызывающему (`message = process_attachment(…)`), как и до R6a. Не меняется.
- `safe_download.rb:148` `return [nil, location] if location && !location.empty?` →
  `return [nil, location] unless location.to_s.empty?` — то же поведение (`nil` и `""` — нет перехода,
  строка из пробелов — есть); `location.present?` поменял бы его (D4).

**Решения владельца (2026-11-20):**
- **D1 `slack/api.rb:888` — УДАЛИТЬ (правка поведения, `r5b1_slack.patch`).** `data_label = data["label"]`
  в ветке `ConversationPartEvent` не используется, но чтение бросает `NoMethodError`/`TypeError`, когда
  `data` события — `nil` или массив (`jsonb`; `ConversationPart#event=` пишет `params[:data]` как есть),
  и `notify_message` падает, в Slack ничего не уходит. После правки такое событие уходит блоком
  `*event*: <action>` без данных. (Чтение `data["email"]` ниже — только для `action == "assigned"`,
  не трогаем.) Спека правки — `slack_event_data_spec.rb`, мутант M15 возвращает чтение.
- **D2 `pipedrive/api.rb:114` — ОСТАВИТЬ исключение**: `id = find_response["data"]["id"]` →
  `find_response["data"]["id"] # kept: raises on a malformed reply (R5b-1 D2)`; при ответе
  `success: true` без `data` по-прежнему бросает, сохранённые данные профиля не затираются `nil`.
- **D3 `audit.rb:25` — ОСТАВИТЬ `""`** у агента без имени (`|| "--"` удалён как недостижимый).
- **D4 `safe_download.rb:148` — ОСТАВИТЬ** `unless location.to_s.empty?` (строка из пробелов — переход).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r5b1-ci`) на
клоне BASE 42d0248e (первый черновик — на 81dbd3ce):

1. Четыре патча применяются к BASE по порядку; после них rubocop без todo по 25 файлам: пять копов —
   0 офенсов в этих файлах, ни у одного другого копа счёт не вырос (`Metrics/*` уменьшились).
2. Образцы восьми спек постановщика (раздел 5 описывает их содержание): 32 примера зелёные на
   дереве; на BASE 29 характеризационных зелёные, спека D1 красная; 15/15 мутантов убиты.
3. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: удалённые выражения без побочных эффектов — по чтению кода (раздел 3); места без
наблюдаемого поведения (`self`/`@id` в `initialize`, литералы) тестом не фиксируются. Подкреплено полным
rspec (AC-001).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код `app/` — **только** `git apply` патчей, руками не править. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r5b1-probes
export CHASKIQ_R5B1_CACHE=$HOME/.cache/chaskiq-r5b1-ci
```

**Шаг 1. Характеризационные спеки** — семь НОВЫХ файлов, код = BASE. В каждом
`# frozen_string_literal: true`, `require "rails_helper"`; HTTP — только WebMock (`require "webmock"`,
`include WebMock::API`, `WebMock.enable!`/`reset!`/`disable!` в `around`, как
`spec/models/campaign_premailer_fetch_spec.rb`); `app.add_agent({ email:, name: }).agent`,
`app.add_user(email:)`, `FactoryBot.create(:app)`, `FactoryBot.create(:campaign, app: app)`. Никаких
`pending`/`skip`/`xit`, `# rubocop:` директив. Что проверить (значения — точные):
- `spec/models/audit_serialize_spec.rb` — `agent_name`: имя агента; у агента без имени — `""`.
  `serialize_properties(app)`: для `Audit.create!(agent:, auditable: agent, action: "agent_log_in", data: {})`
  — `auditable_link` `"[<имя>](/apps/<key>/agents/<id>)"`, `agent_email` `"[<email>](/apps/<key>/agents/<id>)"`;
  для разговора — `"[<conv.key>](/apps/<key>/conversations/<conv.key>)"`.
- `spec/models/campaign_urls_spec.rb` — `Rails.application.routes.default_url_options` → `{host: "https://mail.example.com"}`:
  `campaign_url`, `campaign_api_url` (полные строки); `Campaign.decode_email("campaigns+#{Campaign.encode_email("<key>-<id>")}@x")`
  → эта кампания; несуществующий id → `nil`; адрес без `+` → `nil`; `mustache_template_for(user, html:
  "<p>{{email}} %7B%7Bcampaign_url%7D%7D</p>")` → строка с email и `campaign_url`.
- `spec/services/message_apis/pipedrive_api_spec.rb` (`Api.new(config: {"api_secret" => "tok"})`,
  `https://api.pipedrive.com/v1/...?api_token=tok`): `create_person` → разобранный JSON-ответ (Hash);
  `delete_webhook(7).status` → 200; `register_contact` пользователя с профилем `pipedrive`/`"42"`: ответ с
  `data` → `data` сохранено в профиле; ответ `{"success": true, "data": null}` → `NoMethodError`, прежние
  данные профиля не тронуты.
- `spec/services/message_apis/slack_api_helpers_spec.rb` (`Api.new(config: {"access_token" => "x"})`,
  `authorize_bot!` заглушен): `get_slack_user_by_email` → объект `user` ответа
  `https://slack.com/api/users.lookupByEmail?email=…`; не-JSON ответ → `nil`. `serialize_content` (заглушки
  `attachment_block` → `"attachments"`, `process_blocks` → `"blocks"`): с ключом `"files"` →
  `"attachments"`, без → `"blocks"`.
- `spec/services/message_apis/safe_download_location_spec.rb` — `described_class.send(:read_response,
  Net::HTTPFound.new("1.1", "302", "Found") с Location, 10)`: `"/next"` → `[nil, "/next"]`; `"  "` →
  `[nil, "  "]`; `""` → `nil`; без Location → `nil`.
- `spec/jobs/app_user_event_job_spec.rb` — `perform_now(app_key:, user_id:)`: `Tour.broadcast_tour_to_user`
  вернул `true` → результат `true`, `BotTask` не вызван; оба `nil` → результат `UserAutoMessage.broadcast_message_to_user(user)`;
  пользователь другого приложения → `ActiveRecord::RecordNotFound`.
- `spec/services/message_apis/calendly_presenter_spec.rb` — `valid_url?("https://calendly.com/x")` →
  `"calendly.com"`; `"https://exa mple.com"` → `false`; `sheet_hook({})` → `{a: 11_111}`;
  `initialize_hook(ctx: {values: {url: …, invitation_text: "Book"}})[:definitions].first` включает
  `type: "text", text: "Book"`.

```bash
git add spec/models/audit_serialize_spec.rb spec/models/campaign_urls_spec.rb spec/services/message_apis/pipedrive_api_spec.rb spec/services/message_apis/slack_api_helpers_spec.rb spec/services/message_apis/safe_download_location_spec.rb spec/jobs/app_user_event_job_spec.rb spec/services/message_apis/calendly_presenter_spec.rb
git status --short        # ожидается: ровно 7 строк "A  spec/…"
git commit -m "Add R5b-1 characterization specs"
```

**Шаги 2–4. Патчи** (после каждого — ровно эта команда и коммит):

```bash
git apply $P/r5b1_assign.patch && git commit -qam "Remove useless assignments"
git apply $P/r5b1_void.patch && git commit -qam "Remove void statements"
git apply $P/r5b1_leftovers.patch && git commit -qam "Drop dead reads, keep redirect check"
```

**Шаг 5. Правка D1 и её спека** — новый файл `spec/services/message_apis/slack_event_data_spec.rb`
(`Api.new(config: {"access_token" => "x", "channel_id" => "C1"})`, `post_message` заглушен и возвращает
`instance_double(Faraday::Response, body: {ok: false}.to_json)`; у разговора канал
`conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")`; часть —
`conversation.messages.create!(authorable: user, event: {action: "closed", data: <данные>})`; вызов
`notify_message(conversation:, part:, channel: nil)`): `data: nil` → не бросает, `post_message`
вызван с блоком, у которого `text.text` = `"*event*: closed \n "`; `data: ["a", "b"]` → не бросает,
`post_message` вызван; `data: {"label" => "Done", "status" => "ok", "id" => "1"}` → текст
`"*event*: closed \n *LABEL*: Done *STATUS*: ok"`.

```bash
git apply $P/r5b1_slack.patch
git add spec/services/message_apis/slack_event_data_spec.rb
git status --short        # ожидается: "M  app/services/message_apis/slack/api.rb" и "A  spec/…/slack_event_data_spec.rb"
git commit -qam "Fix Slack event crash on nil data"
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r5b1_tests_gate.sh $B` (≈ 8 мин). Нужны три
строки: `R5B1 TREE PASS …`, `R5B1 BASE PASS 29 char / 1 fix failing` (числа примеров — твои),
`R5B1 MUTANTS PASS 15/15 killed`. Пример красный или мутант выжил — поправь спеку его места (код и
мутантов не трогать), не добавляя новых коммитов:

```bash
mkdir -p tmp/r5b1-keep && cp spec/services/message_apis/slack_event_data_spec.rb tmp/r5b1-keep/
C1=$(git log --format=%H -1 --grep '^Add R5b-1 characterization specs$')
git reset --hard "$C1" && git reset --soft HEAD~1   # 7 спек остаются, патчи сняты
cp tmp/r5b1-keep/slack_event_data_spec.rb spec/services/message_apis/
# поправь спеки, затем — команды шагов 1–5 (в шаге 1 git add только семи файлов), затем снова шаг 6
```

**Шаг 7. todo** — убрать блоки `Lint/UnusedMethodArgument`, `Lint/UselessOr`, `Rails/Present` и строки
`app/` в блоках `Lint/UselessAssignment` и `Lint/Void`:

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r5b1-probes/r5b1_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
out = ["\n".join(l for l in b.split("\n") if not re.match(r"^    - '(app|lib)/", l)) if has(b, cfg["cops_partial"]) else b for b in out]
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R5b-1 entries from RuboCop todo"
```

**Шаг 8. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r5b1

- Fixed: Slack notification of a conversation event no longer raises when the event data is nil or
  an array (unused `data["label"]` read removed).
- Changed: Lint/UselessAssignment, Lint/Void, Lint/UselessOr, Lint/UnusedMethodArgument and
  Rails/Present cleaned up in 25 files of app/ without other behaviour changes; characterization specs added.
```

```bash
git commit -am "Note fork-updates-r5b1 in changelog"
```

**Шаг 9.** Все восемь критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 10.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R5B1 … PASS`; AC-004 — строка `backlog without todo: …`.

## 6. Не трогать

- Всё, кроме 25 файлов кода (только патчами), восьми новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
  Существующие файлы `spec/` не менять.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`.
- Никаких ручных правок `app/`/`lib/`, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R5B1_CACHE=$HOME/.cache/chaskiq-r5b1-ci bash docs/specs/fork-updates-r5b1-probes/rspec_gate_r5b1.sh'`

- **AC-002** — пути и код: изменены ровно 25 файлов кода, восемь новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с четырьмя патчами по порядку; todo = BASE без записей R5b-1; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5b1-probes/r5b1_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры восьми файлов зелёные на коде дерева; на коде BASE характеризационные зелёные, а в спеке правки D1 есть упавший пример, ошибок вне примеров нет; каждый из 15 мутантов r5b1_config.json (текст мутанта найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5B1_CACHE=$HOME/.cache/chaskiq-r5b1-ci bash docs/specs/fork-updates-r5b1-probes/r5b1_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Lint/UnusedMethodArgument, Lint/UselessOr, Rails/Present 0 офенсов, у Lint/UselessAssignment и Lint/Void 0 в app/ и lib/; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5B1_CACHE=$HOME/.cache/chaskiq-r5b1-ci bash docs/specs/fork-updates-r5b1-probes/r5b1_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r5b1-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно семь спек при коде BASE; каждый коммит патча оставляет код = BASE + патчи до своего включительно; коммит правки D1 добавляет ровно свою спеку, остальные — ничего; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r5b1 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5b1-probes/r5b1_probe.py commits $B'`

- **AC-007** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "45af9bd8f73a7efb64ff1250a44b29504c4c85a0189ec23ba6371acb2eabb044  docs/specs/fork-updates-r5b1-probes/r5b1_probe.py" "7e12d3d1492daab9b7bdb20bab847afeab5c44bfe9866bca227eee5cad411c88  docs/specs/fork-updates-r5b1-probes/r5b1_config.json" "3566e6d2676b2ddf657639af0b4857ac7b22b22410697e0e9227d336389a35ed  docs/specs/fork-updates-r5b1-probes/r5b1_tests.rb" "d28741ff879b0a7c299070836b4b1fda7e2b3dcbfcfc88d77036d99534c1ea74  docs/specs/fork-updates-r5b1-probes/r5b1_tests_gate.sh" "7389a3748813cfbd90d673cacb54f06a95feca71f5acf02c54f48dd6df3ad84f  docs/specs/fork-updates-r5b1-probes/r5b1_backlog_probe.sh" "bedb497bde35fe549c2fec8d4977ddcc04001107dc32a19acdd276e851fe101d  docs/specs/fork-updates-r5b1-probes/r5b1_assign.patch" "c2882a883eda7ff8da39f1bcddd1647239ec4feca17948d6266343b9aae83dc3  docs/specs/fork-updates-r5b1-probes/r5b1_void.patch" "9d260fbd9d87eefa13ea9535b77dc01e80be5853e55dff6958b232f12754b25b  docs/specs/fork-updates-r5b1-probes/r5b1_leftovers.patch" "a61b7d368680ed67f12f0779e432937e294ed799aa1876c0de3d509dfc170e8e  docs/specs/fork-updates-r5b1-probes/r5b1_slack.patch" "ac62cd18783c557014c874911ef95b0f316b31bc6e43ddde936761ef8075a6df  docs/specs/fork-updates-r5b1-probes/rspec_gate_r5b1.sh" "bd457f8fd8000e12334b4bda4999367746f35a8e7604b189443c74f2c66267c7  docs/specs/fork-updates-r5b1-probes/r5b1_sentinel.rb" "ac8af0c152e44834a5d064017e05df2831f6229adeec21218ddfe5427b345554  docs/specs/fork-updates-r5b1-probes/examples_base.txt" "ed7e0e71a8b3eda1e62bedbe3e37cea10e49c5ec63e84e108fb670a3f5b6e565  docs/specs/fork-updates-r5b1-probes/pending_allowed.txt" "088837bb067355e8fd5b43f6e48ba9904c6570b452da47b38f5b9650327ccd87  docs/specs/fork-updates-r5b1-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008 зелёные; AC-002 красный (`… is not BASE +
r5b1_assign.patch, …`); AC-003 красный (спек нет — `no examples ran`); AC-004 красный (`… offenses left`);
AC-006 красный (`missing commits`).

Пробный прогон автора (20.11.2026, свежий клон от BASE 42d0248e, сборка по разделу 5 буквально, спеки
шагов 1 и 5 — образцы постановщика):
- чистый клон: AC-002/003/004/006 красные с сообщениями выше (AC-003 — `no examples ran`, тексты
  мутантов не найдены); AC-007/008 зелёные;
- после сборки: все 8 AC зелёные — rspec 795 examples (32 новых), 0 failures, 30 pending, сторож 767;
  AC-003 `R5B1 TREE PASS 32 examples`, `R5B1 BASE PASS 29 char / 1 fix failing`,
  `R5B1 MUTANTS PASS 15/15 killed`; AC-004 backlog без todo BASE 1282 → 1218; файлов от root нет.
- порченые правки (все ловятся; прогнаны на черновике от 81dbd3ce, патчи и пробники с тех пор те же): ручная правка `pipedrive/api.rb` вместо патча → AC-002 и AC-006;
  правка существующей `spec/models/audit_spec.rb` → AC-002 «not an R5b-1 path»; лишняя удалённая
  строка `spec/` в блоке `Lint/Void` → AC-002; спека, фиксирующая `"--"`, спека без примера D2 и спека
  D1 без примеров `nil`/массив → AC-003 (красный на BASE, «no example fails on BASE», выжили M01, M09, M15).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r5b1.md --exclude "docs/specs/fork-updates-r5b1-probes/**" --context "chaskiq fork-updates-r5b1: Lint/UselessAssignment, Void, UselessOr, UnusedMethodArgument, Rails/Present в 25 файлах app/ патчами постановщика без смены поведения; 7 характеризационных спек (зелёные на BASE), 14 мутантов; правка D1 (Slack: нет падения на data nil/массив) со спекой, красной на BASE; D2-D4 оставлены по решению владельца; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r5b1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r5b1-probes/**

Контекст ревьюерам: найти удалённое выражение с побочным эффектом или исключением, которого нет
строкой ниже (раздел 3); спеки проверяют поведение, а не реализацию. Код править нельзя — замечание
по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r5b1.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r5b1.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004/AC-005 красные — дефект спеки;
- характеризационный пример не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение
  (BASE ведёт себя иначе) — приложи вывод;
- мутант не убивается спекой, проверяющей описанное поведение (эквивалентен) — id и почему;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл удалённое выражение с наблюдаемым эффектом — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки `app/`/`lib/`, правка существующих спек, пробников, патчей и мутантов,
`pending`/`skip`, глушить вывод и коды возврата.

## 10. Стыки

- R5b-2 (остальные `Lint` в `app/`+`lib/`, 17 мест решения + 26 `BooleanSymbol`): `AssignmentInCondition` 7
  (скобки), `SymbolConversion` 5, `UnderscorePrefixedVariableName`, `RedundantSafeNavigation`,
  `RedundantTypeConversion`, `MisplacedMagicComment` (`paddle.rb:97` — дубль, верхний уже есть),
  `NonLocalExitFromIterator` 5 (`return nil`), `BooleanSymbol` 26 (`presence: :true` ≡ `true`),
  `SafeNavigationChain` (`app_user_trigger_job.rb:48`), `UnreachableCode` (`api_controller.rb:199`,
  `eu_location?` — `return true`-заглушка) и `InterpolationCheck` (`lib/subdomain_routes.rb` — маршрутизация);
  последние два — решения владельца (раздел 3 плана).
- `Lint/*` в `spec/` (UselessAssignment 12 файлов, Void 3, AmbiguousBlockAssociation, AmbiguousOperatorPrecedence,
  EmptyFile) — после mut-m9-m14 (R6c).
