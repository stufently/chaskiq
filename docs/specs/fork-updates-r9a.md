# fork-updates-r9a — бэклог RuboCop, шаг 9a: `===` → `==`, два предиката переименованы, два — в AllowedMethods

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r9a.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (разделы «Решения 2026-11-21 по оставшимся не-Metrics копам»:
  «`Style/CaseEquality`: `AllowOnConstant: true` …; строковые и прочие `===` → `==` с характеризационными
  тестами» и «Решение 2026-11-21: R7, остаток `Naming/PredicateMethod`»: «`segment_comparator.rb#compare` и
  `zapier/api.rb#event_identifier_available?` — переименовать с alias … `receive_oauth_code` и `download_plugin`
  … — в `AllowedMethods` с причиной»). Парная веха — `fork-updates-r9b` (остальные Style), файлы кода не пересекаются.
- BASE_SHA: `51ffdcadcc5c122fb41a818bb2d74511d65d4e88` — HEAD `main` «Record decisions for remaining Style cops»
  (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r9b` или другая веха — раздел 10), постановщик переносит BASE (раздел 2),
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 40 КБ (половина — новые спеки).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в дереве не остаётся `Style/CaseEquality` (33 офенса, блок уходит из todo), `Naming/PredicateMethod`
  (4, блок уходит) и четырёх соседних офенсов в тех же файлах (`IfUnlessModifier`, `MapIntoArray` в
  `messenger/api.rb`, `InverseMethods` в `segment_comparator.rb`, два `SingleArgumentDig` в `sns_receiver_job.rb` —
  их строки уходят из своих блоков). Код и `.rubocop.yml` заданы патчем постановщика (руками не править).
  Работа исполнителя — десять НОВЫХ спек: каждое изменённое место пиннится примерами, зелёными на BASE и после
  (характеризация); для двух переименований — вложенный `describe "renamed"` на новых именах (красный на BASE,
  зелёный после); каждый из 41 мутанта постановщика (`r9a_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, исключение, другой вызов. AC-007 (`source_scan.py`) ищет эти приёмы в новых и
изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r9a`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r9a-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r9a-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r9a_rewrite.patch`; блоки `Style/CaseEquality`,
   `Naming/PredicateMethod` и строки `cops_partial` конфига в todo на месте (иначе пробник сам падает со «spec
   defect»); тексты 41 мутанта — каждый ровно один раз в своём файле после патча; имена десяти новых спек не
   заняты. Перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R9A_CACHE=$HOME/.cache/chaskiq-r9a-ci bash docs/specs/fork-updates-r9a-probes/rspec_gate_r9a.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1155 примеров BASE 51ffdcad.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 51ffdcad (Docker, копия кэша `chaskiq-fxb-ci`): всего 345 офенсов, не-Metrics
— 88; у копов вехи — 42 (CaseEquality 33, PredicateMethod 4, соседние 5). После патча — 303, новых офенсов нет
(ни у одного копа ни в одном файле больше, чем на BASE).

**`===` → `==`: поведение то же, потому что получатель `===` во всех 30 местах кода — `String`, `Integer` или
`nil`** (значение из JSON/params/столбца БД, `model_name.name`, `#to_s`, id). У `String#===`, `Integer#===` это
тот же метод, что `==`; у `nil` и `Hash`/`Array` (JSON) — `Object#===` = `equal? || ==`, для них совпадает с `==`.
Отличие было бы только у получателя-`Regexp`/`Range`/`Proc`/`Class`/`Set` (`match`/`cover?`/`call`/`is_a?`/`include?`)
— таких мест нет (`git grep` по каждому: ни одна переменная слева не бывает регэкспом, диапазоном, классом).
`Class === obj` не встречается вовсе (без todo 0 офенсов на константе), `AllowOnConstant: true` — запись решения.

| Файл | Места (строка BASE: левый операнд) |
|---|---|
| `graphql/types/messenger_type.rb` | 81 `@user.model_name.name` |
| `graphql/types/role_type.rb` | 39 `object.app.owner_id` (Integer) |
| `jobs/sns_receiver_job.rb` | 13, 30, 34 `o["name"]` (JSON SNS); + 31, 35 `end.dig("value")` → `end["value"]` (Hash: `dig(k)` ≡ `[k]`; `nil` → `NoMethodError` и там, и там) |
| `models/conversation.rb` | 177 `assignee.id` |
| `services/action_trigger_factory.rb` | 194, 204 ×2 `kind` (`model_name.name`), 251, 256 `app.email_requirement`, 356 `a["step_uid"].to_s` |
| `message_apis/{article_search,calendly,content_showcase,dialog360,open_ai,ui_catalog,zoom}/presenter.rb` | `ctx.dig(:field, :action, :type)` (JSON ctx) — по одному; `ui_catalog` ещё 11 `type_value` |
| `message_apis/{inbox_sections,zapier}/presenter.rb` | 24 / 12 `type_value = ctx.dig(:values, :type)` |
| `message_apis/csat/presenter.rb`, `csat/api.rb` | 98 `ctx[:field]["id"]`; 62 `d[:id]` (строковые id опций) |
| `message_apis/messenger/api.rb` | 67 `mode`, `token` (params); + 87 `IfUnlessModifier` (автокоррект), 233 `MapIntoArray` → `map` |
| `message_apis/slack/api.rb` | 736 `event["subtype"]`, 738 `event["text"]`, 1054 `o["type"]` |
| `message_apis/zapier/api.rb` | 89 `package.access_token` (столбец, String/nil) |
| `spec/.../paddle_hooks_controller_spec.rb` | 143, 154, 165 `expect(x).to be === "…"` → `eq("…")` (String: тот же матч) |

**`Naming/PredicateMethod`.** `SegmentComparator#compare` (возвращает `true`/`false`) → `compare?`, сразу после
`end` метода — `alias compare compare?`; там же `select { … != "match" }` → `reject { … == "match" }`
(`InverseMethods`). `MessageApis::Zapier::Api#event_identifier_available?` (возвращает пару `[event, url]`, не
логическое) → `event_identifier_and_url`, `alias event_identifier_available? event_identifier_and_url`. Вызывающие
(`messenger_type.rb`, `assignment_rule.rb`, `bot_task.rb`, `message.rb`, `action_trigger_factory.rb`, `zapier/api.rb`
:230, :242, `segment_spec.rb`) не меняются: идут через алиас. Алиасы RuboCop не проверяет. `Slack::Api#receive_oauth_code`
(метод интерфейса плагина, получает и сохраняет OAuth-токен) и `Plugins::TarDownloader#download_plugin` (качает
архив плагина в `tmp/`) возвращают `true`/`false`, но действуют — имя с `?` скрыло бы это: **настройка вместо
переименования**, `AllowedMethods: [call, receive_oauth_code, download_plugin]` (`call` — умолчание RuboCop) в
существующем блоке `Naming/PredicateMethod` `.rubocop.yml` с причиной в комментарии.

**`r9a_rewrite.patch`** — 22 файла: 19 файлов кода, спека paddle, `.rubocop.yml` (два хунка: блок
`Naming/PredicateMethod` — причина и `AllowedMethods`; новый блок `Style/CaseEquality: AllowOnConstant: true`).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 51ffdcad:

1. Замер RuboCop без todo до и после патча (раздел 3); тела всех методов раздела 3 и раздела 5 прочитаны.
2. Образцы десяти спек постановщика (раздел 5): 57 примеров характеризации зелёные на BASE и дереве, 5
   примеров `renamed` красные на BASE (`NoMethodError`), зелёные на дереве; 41/41 мутант убит.
3. Полный сьют на BASE (`--write-base`): 1155 примеров, 0 failures, 30 pending.
4. Патч применяется до и после патчей `r9b`; todo обеих вех в любом порядке даёт один результат (раздел 10);
   пробный прогон и порченые правки — раздел 7. Предположение: внешние плагины зовут старые имена — они остаются.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. Код — **только** `git apply` патча. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников
(раздел 1); спеки чисты под RuboCop (AC-004, AC-005). Значения проверяй точно (`eq(true)`, `eq("42")`,
`be_nil`), не `be_truthy`. GraphQL-тип — `described_class.send(:new, object, context)`. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r9a-probes
export CHASKIQ_R9A_CACHE=$HOME/.cache/chaskiq-r9a-ci
```

**Шаг 1. Десять спек** (для каждого изменённого места — пример, где сравнение истинно, и где ложно):

- `spec/graphql/types/case_equality_types_spec.rb`: `Types::MessengerType#enabled_for_user` при
  `inbound_settings` `{"users"=>{"enabled"=>true,"segment"=>"all"},"visitors"=>{"enabled"=>false}}`, контекст
  `{ set_locale: -> {}, get_app_user: -> { user } }` — `app.add_user(email:)` → `true`, `app.add_anonymous_user({})` →
  `nil`; `Types::RoleType#owner` (роль из `app.add_agent({email:})`, `app.update!(owner_id: role.agent_id)`) — `true`
  для этой роли, `false` для другой.
- `spec/jobs/sns_receiver_job_headers_spec.rb`: `SnsReceiverJob.new.perform("click", {"mail"=>{"headers"=>…},
  "click"=>{"ipAddress"=>…}}, nil)` со стабами `Campaign.find_by(id: "5")`, `AppUser.find_by(id: "7")` и
  `track_click`: заголовки `X-CHASKIQ-CAMPAIGN-ID`=5 и `X-CHASKIQ-CAMPAIGN-TO`=7 среди прочих → `track_click(host:,
  trackable: campaign, data:)`; только `…-TO` → `track_click` не вызван; только `…-ID` → `raise_error(NoMethodError)`.
- `spec/models/conversation_assign_same_user_spec.rb`: разговор `app.start_conversation`, назначен агент;
  `assign_user(тот же)` → `nil`, число `messages` не меняется; `assign_user(другой)` → +1 сообщение, `assignee` — другой.
- `spec/services/action_trigger_factory_kind_spec.rb`: шаги путей `infer_for` (`user.lang = "en"`): путь
  `typical_reply_time` — `[1]` у `add_user`, `[5, 6]` у `add_lead({})` и у `add_anonymous_user({})`; путь `yes` при
  `email_requirement: "office"` и `in_business_hours?` false → `[7, 2, 3, 4]`, true → `[7, 4]`; `find_task(data:
  {"trigger"=>"infer","step"=>"8"})` → путь `"no"`, `"step"=>4` → путь `"yes"`.
- `spec/services/message_apis/presenters_case_equality_spec.rb`: `configure_hook(kind: "configure", ctx:)` с
  `field: {id:/name:, action: {type: "submit"}}` и с `type: "click"` — ArticleSearch (`id: "activate-action"`),
  Calendly (`name: "set_url"`, `values` с `calendar`/`label`/`invitation_text`, `package: double(app: double(name:))`),
  ContentShowcase (`id: "announcement"`; при click — `described_class::AnnouncementRecord.new.base_schema`),
  OpenAi (`id: "add-prompt"`, `package: double(settings: {"main_prompt"=>…})`), UiCatalog (`id: "aaaaaaaa"`), Zoom
  (`name: "set_url"`, `values: {zoom_user:}`), Dialog360 (ctx `with_indifferent_access`: `conversation_key`, `field`
  `name: "submit-template"`, `id` — Base64 JSON шаблона, `title`; `package: double(message_api_klass:
  double(retrieve_templates: {"offset"=>0,"total"=>0,"waba_templates"=>[]}.to_json))`) — submit даёт `results` /
  `kind: "initialize"`, click — нет; Csat (`field: {"id"=>"command-confirm"}` → `{kind: "initialize", definitions:
  [csat_buttons]}`, другой id → kind сохранён); `initialize_hook` UiCatalog, InboxSections, Zapier с `values: {type:
  "content"}` и `type: "other"`.
- `spec/services/message_apis/csat_report_label_spec.rb`: `Csat::Api.new(config: {}).report("general",
  integration, nil)` с `custom_counts` → `[double(val: "2", freq: 1), double(val: "4", freq: 3)]`: подписи —
  тексты опций `"2"` и `"4"` из `Presenter.csat_buttons`, значения `"25.0%"`, `"75.0%"`.
- `spec/services/message_apis/messenger_api_hook_spec.rb`: `create_hook_from_params` (`package: double(settings:
  {"verify_token"=>"secret"})`) — subscribe + верный токен → `"42"` (challenge), чужой токен → `nil`, другой mode →
  `nil`; `process_event` с тем же subscribe → `"42"`, с другим mode — `create_hook_from_params` не вызван;
  `attachment_block` с тремя вложениями (image, audio, image) равен `main_doc` из двух `photo_block` по порядку.
- `spec/services/message_apis/slack_process_message_spec.rb` (`authorize_bot!` и `find_conversation_by_slack_ts`
  застаблены): `process_message` с `subtype "channel_join"` и с текстом `"New conversation from Chaskiq"` —
  поиск разговора не вызван, ответ в треде — вызван с `thread_ts`; `process_blocks` (JSON-строка) — блок image
  даёт ровно один лишний блок с его URL, section — ни одного.
- `spec/services/message_apis/zapier_api_auth_spec.rb`: `process_message({auth: "tok"}, package)` →
  `{status: :ok, app_name: "Acme"}`, чужой ключ → `{status: :error, message: "auth key invalid"}`;
  `event_identifier_available?` — `double(action: "users.created")` → `[{identifier: :user_created, name:
  "users.created"}, <URL из package.settings["user_created"]>]`, неизвестное → `[nil, nil]`; то же в `describe "renamed"`
  на `event_identifier_and_url`.
- `spec/models/segment_comparator_compare_spec.rb`: предикаты `{"attribute"=>"email","comparison"=>"eq",
  "type"=>"string","value"=>…}` и `{"type"=>"match","value"=>"and"|"or",…}`: and, все верны → `true`; and, одно
  неверно → `false`; or, одно верно → `true`; только match → `true`; три из них в `describe "renamed"` на `compare?`.

Гейт тестов узнаёт пример «renamed» по подстроке ` renamed ` в полном описании — больше этого слова нигде нет.

```bash
git apply $P/r9a_rewrite.patch
git add spec/graphql/types/case_equality_types_spec.rb spec/jobs/sns_receiver_job_headers_spec.rb spec/models/conversation_assign_same_user_spec.rb spec/services/action_trigger_factory_kind_spec.rb spec/services/message_apis/presenters_case_equality_spec.rb spec/services/message_apis/csat_report_label_spec.rb spec/services/message_apis/messenger_api_hook_spec.rb spec/services/message_apis/slack_process_message_spec.rb spec/services/message_apis/zapier_api_auth_spec.rb spec/models/segment_comparator_compare_spec.rb
git status --short        # ожидается: 10 строк "A  spec/…" и 22 строки " M …"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 11 files
git commit -qam "Use == for equality, rename two predicates"
```

**Шаг 2. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r9a_tests_gate.sh $B` (≈ 5 мин). Нужны три
строки: `R9A TREE PASS … examples`, `R9A BASE PASS … char / 5 renamed failing / 0 fix failing`,
`R9A MUTANTS PASS 41/41 killed`. Пример красный на дереве, характеризация красная на BASE, `renamed` зелёный на
BASE или мутант выжил — поправь спеку (код, патч и мутантов не трогать; убийство — только поведением), не
добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Use == for equality, rename two predicates$')
mkdir -p tmp/r9a-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r9a-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r9a-specs (tmp/ игнорируется)
# поправь спеки в tmp/r9a-specs/spec/…, затем: cp -r tmp/r9a-specs/spec/. spec/
# затем — команды шага 1, затем снова шаг 2
```

**Шаг 3. todo** — убрать блоки `cops_whole` и строки `cops_partial` конфига:

```bash
python3 -I - r9a <<'PY'
import json, re, sys
n = sys.argv[1]
cfg = json.load(open(f"docs/specs/fork-updates-{n}-probes/{n}_config.json"))
has = lambda b, c: re.search(rf"(?m)^{re.escape(c)}:$", b)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not any(has(b, c) for c in cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
for cop, paths in cfg.get("cops_partial", {}).items():
    i = next(i for i, b in enumerate(out) if has(b, cop))
    gone = {f"    - '{p}'" for p in paths}
    assert gone <= set(out[i].split("\n")), "stop: section 9"
    out[i] = "\n".join(l for l in out[i].split("\n") if l not in gone)
out = [b for b in out if re.search(r"(?m)^    - '", b) or not re.search(r"(?m)^  Exclude:$", b)]
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
PY
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R9a entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r9a

- Changed: every `a === b` whose receiver is a String, Integer or nil is written `a == b` (30 places in
  app/, three `be ===` matchers in a spec): the same method for those receivers. `Style/CaseEquality`
  allows `Klass === obj` (`AllowOnConstant`); its todo block is gone.
- Changed: `SegmentComparator#compare` -> `compare?` and `Zapier::Api#event_identifier_available?` ->
  `event_identifier_and_url`, each old name kept as an `alias`; Slack's `receive_oauth_code` and
  `TarDownloader#download_plugin` act, so they stay and go to `Naming/PredicateMethod` AllowedMethods.
- Changed: in the same files `select { != }` -> `reject { == }`, `.dig("value")` -> `["value"]`, a
  modifier `if` and `each`+`<<` -> `map`. Ten specs pin the behaviour of every changed place.
```

```bash
git commit -am "Note fork-updates-r9a in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка
`paths: …`; AC-003 — три строки `R9A … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 22 файлов патча (только патчем), десяти новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Вызывающих старых имён и существующие спеки — не переводить на новые имена; `segment_spec.rb` не трогать.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`; файлы вехи `r9b`
  (раздел 10).
- Прочие блоки todo и строки блоков `IfUnlessModifier`, `InverseMethods`, `MapIntoArray`, `SingleArgumentDig`
  других файлов (их убирает `r9b`).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R9A_CACHE=$HOME/.cache/chaskiq-r9a-ci bash docs/specs/fork-updates-r9a-probes/rspec_gate_r9a.sh'`

- **AC-002** — пути и код: изменены ровно 22 файла патча, 10 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патча побайтно равен BASE с патчем; todo = BASE без блоков CaseEquality и PredicateMethod и без строк cops_partial; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9a-probes/r9a_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 10 спек зелёные на коде дерева; на коде BASE примеры характеризации зелёные, каждый пример renamed упал, в двух спеках с переименованием есть оба вида; ошибок вне примеров нет; каждый из 41 мутанта r9a_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R9A_CACHE=$HOME/.cache/chaskiq-r9a-ci bash docs/specs/fork-updates-r9a-probes/r9a_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у CaseEquality и PredicateMethod 0 офенсов во всём дереве, у копов cops_partial 0 в файлах вехи; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; разрешённый конфиг даёт AllowOnConstant true; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R9A_CACHE=$HOME/.cache/chaskiq-r9a-ci bash docs/specs/fork-updates-r9a-probes/r9a_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r9a-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит правки меняет ровно 22 файла = BASE + патч и добавляет ровно 10 спек; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r9a после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9a-probes/r9a_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9a-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "443be9f456abeb22b532b68cba12f2704974292ad6beed694fab28daf40313a5  docs/specs/fork-updates-r9a-probes/examples_base.txt" "453f9ebd073a5cc110cd7b42d566af4a6c23ee0bbb8ece0751e2182c18b2cae5  docs/specs/fork-updates-r9a-probes/pending_allowed.txt" "e99cef07475933905158810bbe66244e89f2780a277f8c3dfc0d624269f6d4be  docs/specs/fork-updates-r9a-probes/r9a_backlog_probe.sh" "b7154bd68f64697f7f0084a467569e67ba32d43719264231cdd78cbd8e845f6a  docs/specs/fork-updates-r9a-probes/r9a_config.json" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r9a-probes/r9a_probe.py" "77be397d1e8a4b0fd24a6849b72f494792fafb0a74f15611445039342b847cfd  docs/specs/fork-updates-r9a-probes/r9a_rewrite.patch" "4084acd14099ea1ed100e5505373105846f44926744e7e2d4f89977bf7070335  docs/specs/fork-updates-r9a-probes/r9a_sentinel.rb" "b35be4a35585fe2c1890f2482313fc4ca6d175e532da9fd77b21c16741d4689b  docs/specs/fork-updates-r9a-probes/r9a_tests.rb" "01666e32cf0fb76c607cda1397cbc9d19d093f994c1b5b1abcbc075f32bef3a1  docs/specs/fork-updates-r9a-probes/r9a_tests_gate.sh" "ec1a0ef0dc1d52d4bc99c6b84d45227f463e4c2c6e68f46f0c1780bf7a722621  docs/specs/fork-updates-r9a-probes/rspec_gate_r9a.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fork-updates-r9a-probes/source_scan.py" "54db6575dc30d0d729e0881922a03a2a594b27f632e8f871f321fd27eb8de0f4  docs/specs/fork-updates-r9a-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный
(`R9A paths without the change` / `is not BASE + r9a_rewrite.patch`); AC-003 красный (спек нет — `no examples
ran`, тексты мутантов не найдены); AC-004 красный (`Style/CaseEquality: 33 offenses left`); AC-006 красный
(`missing commits`).

Пробный прогон автора (21.11.2026; свежий клон BASE 51ffdcad со спекой и пробниками одним коммитом поверх,
ветка с upstream `origin/main`, сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия
`chaskiq-fxb-ci`, путь кэша в командах подменён на копию):
- чистый клон: AC-001 (1155 примеров, 0 failures, 30 pending, ≈ 7 мин), AC-005, AC-007 (`0 files`), AC-008, AC-009 —
  rc=0; AC-002, AC-003, AC-004 (`Style/CaseEquality: 33 offenses left`), AC-006 красные с сообщениями выше;
- после сборки: все 9 AC rc=0 — rspec 1217 примеров (62 новых), 0 failures, 30 pending; AC-003
  `R9A BASE PASS 57 char / 5 renamed failing / 0 fix failing`, `R9A MUTANTS PASS 41/41 killed` (≈ 3 мин);
  AC-004 бэклог без todo 345 → 303; AC-007 `SOURCE SCAN PASS 11 files`;
- порченые правки (все ловятся): из спеки SNS убран пример `NoMethodError` → AC-003 (выжил A08);
  `Rails.root.join("app/models/segment_comparator.rb").read` в спеке → AC-007; вызывающий `messenger_type.rb`
  переведён на `compare?` → AC-002, AC-006.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r9a.md --exclude "docs/specs/fork-updates-r9a-probes/**" --exclude docs/specs/fork-updates-r9b.md --exclude "docs/specs/fork-updates-r9b-probes/**" --context "chaskiq fork-updates-r9a: RuboCop Style/CaseEquality 33 — каждый a === b с получателем String/Integer/nil записан a == b (тот же метод), AllowOnConstant true; Naming/PredicateMethod 4 — SegmentComparator#compare -> compare? и Zapier event_identifier_available? -> event_identifier_and_url со старым именем alias, receive_oauth_code и download_plugin в AllowedMethods с причиной; соседние InverseMethods, SingleArgumentDig x2, IfUnlessModifier, MapIntoArray; 10 спек характеризации зелёные на BASE, describe renamed красный на BASE; 41 мутант; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r9a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r9a-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r9b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r9b-probes/**

Контекст ревьюеру: левый операнд `===`, который бывает Regexp/Range/Class/Proc/Set (тогда `==` меняет смысл),
вызывающий по новому имени, которого нет (JS, GraphQL, `send` со строкой), подкласс со своим старым именем,
спека, проверяющая текст, а не поведение. Код править нельзя — замечание по месту решает постановщик
(раздел 9); спеки — можно, одним заходом.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 9 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r9a.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "qwen", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>"],
    "verification_receipts": [],
    "resolutions": []
  },
  "handoff_status": "blocked",
  "criteria": [
    {"id": "AC-001", "status": "pass|fail|blocked",
     "command": "<команда ИЗ ЭТОЙ СПЕКИ, посимвольно>", "rc": 0, "note": "…"}
  ]
}
```

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r9a.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после патча
  AC-004/AC-005 красные — дефект спеки;
- пример характеризации не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл `===`, у которого левый операнд бывает не String/Integer/nil, вызывающего по новому имени или
  подкласс со старым именем — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, перевод вызывающих на новые имена, правка пробников, патча
и мутантов, `pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и
коды возврата.

## 10. Стыки

- **`fork-updates-r9b` (qw2) — парная веха, может идти параллельно.** Общих файлов кода нет. Общие:
  `.rubocop.yml` (r9a — блоки `Naming/PredicateMethod` и новый `Style/CaseEquality` ниже `ClassAndModuleChildren`;
  r9b — новый блок `Style/StringConcatenation` после `Rails/EnvironmentVariableAccess`), `.rubocop_todo.yml` (r9a
  убирает строки `messenger/api.rb`, `segment_comparator.rb`, `sns_receiver_job.rb` из блоков `IfUnlessModifier`,
  `InverseMethods`, `MapIntoArray`, `SingleArgumentDig`; r9b — остальные строки этих блоков; опустевший блок
  удаляет та веха, что вливается второй — её ожидаемый todo считается от нового BASE сам) и `CHANGELOG.md`.
  Проверено на 51ffdcad: патчи и скрипты todo применяются в любом порядке, итог один, строгий RuboCop чист.
- **Кто вливается вторым, тому — перенос BASE, `--write-base` (новые примеры первой вехи) и sha256 AC-008**
  (раздел 2, п. 2).
- После r9a и r9b в todo остаются только выбросы Metrics/LineLength (R8a) — вехи рефакторинга, затем R9 (удалить todo).
- Мутационный прогон по десяти спекам — у противоположного исполнителя (cx), после снятия запрета на Codex
  2026-11-22 11:39Z.
