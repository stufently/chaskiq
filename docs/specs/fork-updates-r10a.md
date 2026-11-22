# fork-updates-r10a — выбросы RuboCop, шаг 10a: длинные строки в `app/` перенесены, байткод тот же

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-21. Спека —
  `docs/specs/fork-updates-r10a.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10a: «LineLength
  в `app/` вне файлов r9b … перенос; строковые литералы — смежными кусками; 19 из 20 файлов компилируются в
  байткод BASE»), план чистки — `docs/specs/fork-updates-rubocop-plan.md` (R8: выбросы — отдельные вехи
  рефакторинга с тестами). Парная веха — `fork-updates-r10b`, файлы кода не пересекаются. `fork-updates-r9b` уже влита (BASE).
- BASE_SHA: `16682f02e62acae780f15f7027e0d258237d7d16` — HEAD `main` «Record R9b acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10b` или другая веха — раздел 10), постановщик переносит BASE (раздел 2),
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 25 КБ (больше половины — новые спеки).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в 20 файлах `app/` не остаётся `Layout/LineLength` (37 офенсов; их 20 строк уходят из блока todo). Код
  задан патчем постановщика `r10a_rewrite.patch` (руками не править): только переносы строк. Работа
  исполнителя — семь НОВЫХ спек характеризации: каждый метод, в котором перенесён код (не комментарий), пиннится
  точным значением, зелёным на BASE и после; каждый из 13 мутантов постановщика (`r10a_config.json`, `mutants`)
  роняет пример. Сверх этого AC-003 проверяет, что 19 файлов компилируются в байткод BASE.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, исключение, другой вызов. AC-007 (`source_scan.py`) ищет эти приёмы в новых и
изменённых файлах `spec/` и валит критерий на любом совпадении. Байткод сравнивает пробник постановщика, не спеки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10a`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10a-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10a-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r10a_rewrite.patch`; строки 20 файлов в блоке
   `Layout/LineLength` todo на месте (иначе пробник сам падает со «spec defect»); тексты 13 мутантов — каждый ровно
   один раз в своём файле после патча; имена семи новых спек не заняты. Перегенерировать снимки на чистом
   checkout `main`:
   `CHASKIQ_R10A_CACHE=$HOME/.cache/chaskiq-r10a-ci bash docs/specs/fork-updates-r10a-probes/rspec_gate_r10a.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1285 примеров BASE 16682f02.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 16682f02 (Docker, копия кэша `chaskiq-fxb-ci`): всего 254 офенса — только выбросы
Metrics/LineLength (список R8a без трёх, что убрала `r9b`); у вехи — 37 `Layout/LineLength` в 20 файлах, которых
не трогала `r9b`. После патча — 217, новых офенсов нет (ни у одного копа ни в одном файле больше, чем на BASE).

**29 строк — комментарии** (одна и та же справка «Sent when …» в 15 презентерах, закомментированный код
`options:` в `twilio_phone/presenter.rb` и `serialized_content:` в `action_trigger_factory.rb`) — перенесены по
словам. **8 строк — код**, перенос без изменения значения:

| Файл:строка BASE | Что | Метод — что пиннить |
|---|---|---|
| `models/agent.rb:73` | `%w[…]` на 36 слов → 5 строк | `Agent.ransackable_attributes` — массив целиком, по порядку |
| `graphql/chaskiq_schema.rb:25` | строка с интерполяцией → два куска `"…" \` | `ChaskiqSchema.unauthorized_field(error)` — `GraphQL::ExecutionError` с точным текстом |
| `services/dante/migrator.rb:6` | SQL-строка `joins(...)` → три куска | `Dante::Migrator.migrate_conversation_parts(id:)` — конвертирует контент частей разговоров своего app, чужие не трогает |
| `services/dante/renderer.rb:98` | вызов `create_element` с kwargs → 2 строки | `Dante::Renderer#render` для отметки `link` — точные атрибуты `<a>` |
| `message_apis/inbox_sections/presenter.rb:12` | хеш → 2 строки | `InboxSections::Presenter.user_data` — массив целиком |
| `message_apis/slack/api.rb:793` | строка `scope:` → два куска | `Slack::Api#oauth_authorize` — URL авторизации и все параметры запроса |
| `message_apis/twilio_phone/presenter.rb:360` | строка `options:` → два куска | `TwilioPhone::Presenter.definitions_for_content` — действие кнопки по каждой ветке |
| `message_apis/twilio_phone/presenter.rb:311` | то же | `content_definitions` — недостижимо (до строки метод падает `NameError` на `agents_ids`, программа, раздел 5); пиннится только пустой список, строку доказывает байткод |

**Почему поведение то же.** Смежные строковые литералы без интерполяции Ruby склеивает при разборе: байткод
тот же. Перенос аргументов, элементов `%w[]` и пар хеша меняет только номера строк. Пробник `r10a_iseq.rb`
(AC-003) сравнивает YARV-байткод 19 файлов BASE и дерева без номеров строк (инструкции, операнды, литералы с
кодировкой и байтами): все `SAME`. Исключение — `chaskiq_schema.rb`: Prism (Ruby 4) не склеивает куски
интерполированной строки, байткод другой (`concatstrings` в два приёма), результат — та же строка; её пиннит
спека точным текстом и два мутанта.

**`r10a_rewrite.patch`** — 20 файлов `app/`, +79/−37 строк; `.rubocop.yml` не меняется.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 16682f02:

1. Замер RuboCop без todo до и после патча (раздел 3): 254 → 217, у 20 файлов `Layout/LineLength` 0, других
   изменений нет; строгий RuboCop с урезанным todo чист.
2. Байткод: 19 файлов `SAME`, `chaskiq_schema.rb` `DIFF` (ожидаемо, раздел 3).
3. Образцы семи спек постановщика: 13 примеров зелёные на BASE и на дереве; 13/13 мутантов убиты.
4. Полный сьют на BASE (`--write-base`): 1285 примеров, 0 failures, 30 pending.
5. Патч применяется до и после патча `r10b` (оба порядка; раздел 10); пробный прогон и порченые правки — раздел 7.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код — **только** `git apply` патча. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников (раздел 1);
спеки чисты под RuboCop (AC-004, AC-005). Значения проверяй точно (`eq([...])`, `eq("…")`, `raise_error(Класс,
"текст")`), не `be_truthy`/`include` там, где известно всё значение. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10a-probes
export CHASKIQ_R10A_CACHE=$HOME/.cache/chaskiq-r10a-ci
```

**Шаг 1. Семь спек** (каждая — точное значение метода, зелёное и на BASE, и после патча):

- `spec/models/agent_ransackable_attributes_spec.rb`: `Agent.ransackable_attributes` `eq` полного списка из 36
  имён по порядку BASE (`available bot confirmation_sent_at … unlock_token updated_at`); с аргументом — то же.
- `spec/graphql/chaskiq_schema_unauthorized_spec.rb`: `error = double(field: double(graphql_name: "secretField"),
  type: double(graphql_name: "AppType"))`; `ChaskiqSchema.unauthorized_field(error)` →
  `raise_error(GraphQL::ExecutionError, "The field secretField on an object of type AppType was hidden due to
  permissions")`; `unauthorized_object(error)` → `"An object of type AppType was hidden due to permissions"`.
- `spec/services/dante/migrator_conversation_parts_spec.rb`: два app (`FactoryBot.create(:app)`), в каждом
  разговор `app.start_conversation(message: { html_content:, serialized_content: { "content" => [], "draft" => x
  }.to_json }, from: app.add_user(email:))` (ключ `"content"` обязателен — его читает `assign_agent_by_rules`);
  `allow(Dante::Converter).to receive(:draftjs_to_prosemirror) { |raw| { "converted" => raw } }`;
  `migrate_conversation_parts(id: app.id)` → `serialized_content` частей своего app = `{ "converted" => <прежний>
  }.to_json`, чужого — без изменений, конвертер вызван ровно один раз; второй пример — исключение конвертера на
  одной части не мешает следующей.
- `spec/services/dante/renderer_link_mark_spec.rb`: `Dante::Renderer.new(raw: {content: [{type: "paragraph",
  content: [{type: "text", text: "site", marks: [{type: "link", attrs: {href:, target: "_blank"}}]}]}]}, domain:
  …).render` — у `<a>` (Nokogiri) атрибуты ровно `class` = `"graf markup--anchor markup--anchor-readOnly"`, `href`,
  `target`, `rel` = `"noopener noreferrer nofollow"` (`anchor.to_h` `eq`), текст `"site"`.
- `spec/services/message_apis/inbox_sections_user_data_spec.rb`: `InboxSections::Presenter.user_data` `eq` всего
  массива (`data-table` с тремя `field-value`, третье значение — длинная строка целиком).
- `spec/services/message_apis/slack_oauth_authorize_spec.rb`: `Slack::Api.new(config: {"api_key" => "client-1",
  "api_secret" => "secret-1"}).oauth_authorize(nil, double(oauth_url: "https://app.example.com/oauth/slack"))` —
  схема/хост/путь `https://slack.com/oauth/v2/authorize`, `Rack::Utils.parse_query(query)` `eq` `{client_id,
  response_type: "code", redirect_uri, user_scope, scope}` с полными строками scope.
- `spec/services/message_apis/twilio_phone/presenter_call_window_spec.rb`: `definitions_for_content(kind:
  "content", ctx: {package: double(id: 77, app: app), conversation_key:, lang: "en", location:, current_user: nil})
  .last[:action]` — в существующем разговоре при `location: "conversation"`: ключи ровно `%i[type url options]`,
  `type: "url"`, `url` начинается с `"#{Chaskiq::Config.get(:host)}/package_iframe/TwilioPhone?token="`, `options`
  `eq` полной строки окна; несуществующий разговор и `location: "home"` → `{type: "submit"}`;
  `content_definitions` с `conferences_list` `[]` → только заголовок `[{type: "text", text: "Pick a template",
  style: "header"}]`.

```bash
git apply $P/r10a_rewrite.patch
git add spec/models/agent_ransackable_attributes_spec.rb spec/graphql/chaskiq_schema_unauthorized_spec.rb spec/services/dante/migrator_conversation_parts_spec.rb spec/services/dante/renderer_link_mark_spec.rb spec/services/message_apis/inbox_sections_user_data_spec.rb spec/services/message_apis/slack_oauth_authorize_spec.rb spec/services/message_apis/twilio_phone/presenter_call_window_spec.rb
git status --short        # ожидается: 7 строк "A  spec/…" и 20 строк " M app/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 7 files
git commit -qam "Wrap long lines in app/"
```

**Шаг 2. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10a_tests_gate.sh $B` (≈ 3 мин). Нужны четыре строки:
`R10A TREE PASS … examples`, `R10A BASE PASS … char / 0 renamed failing / 0 fix failing`, `R10A MUTANTS PASS 13/13
killed`, `R10A ISEQ PASS 19 files`. Пример красный на дереве или на BASE, мутант выжил — поправь спеку (код,
патч и мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Wrap long lines in app/$')
mkdir -p tmp/r10a-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r10a-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r10a-specs (tmp/ игнорируется)
# поправь спеки в tmp/r10a-specs/spec/…, затем: cp -r tmp/r10a-specs/spec/. spec/
# затем — команды шага 1, затем снова шаг 2
```

`ISEQ` красный — это не про спеки: раздел 9.

**Шаг 3. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10a <<'PY'
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
git commit -am "Drop R10a entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r10a

- Changed: every line over 140 characters in 20 files of app/ (Layout/LineLength outliers of R8a) is
  wrapped: 29 comments, a `%w[]` list, a hash, an argument list and five string literals split into
  adjacent pieces. Nineteen files compile to the same bytecode as before; the twentieth (the GraphQL
  schema error message) and every other method whose code was wrapped are pinned by seven new specs.
  Their 20 lines leave the Layout/LineLength block of the todo.
```

```bash
git commit -am "Note fork-updates-r10a in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — четыре строки `R10A … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 20 файлов патча (только патчем), семи новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Существующие спеки (в том числе `spec/services/dante_renderer_spec.rb`, `presenters_case_equality_spec.rb`,
  `slack_*_spec.rb`) — не править.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`; файлы вехи
  `r10b` (раздел 10).
- Прочие блоки todo и строки других файлов в блоке `Layout/LineLength` (их убирают R10c/R10e).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10A_CACHE=$HOME/.cache/chaskiq-r10a-ci bash docs/specs/fork-updates-r10a-probes/rspec_gate_r10a.sh'`

- **AC-002** — пути и код: изменены ровно 20 файлов патча, 7 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патча побайтно равен BASE с патчем; todo = BASE без 20 строк блока Layout/LineLength; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10a-probes/r10a_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 7 спек зелёные на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 13 мутантов r10a_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки; 19 файлов iseq_same компилируются в байткод BASE (без номеров строк), новых предупреждений ruby -wc нет.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10A_CACHE=$HOME/.cache/chaskiq-r10a-ci bash docs/specs/fork-updates-r10a-probes/r10a_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Layout/LineLength 0 офенсов в 20 файлах вехи; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10A_CACHE=$HOME/.cache/chaskiq-r10a-ci bash docs/specs/fork-updates-r10a-probes/r10a_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10a-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит правки меняет ровно 20 файлов = BASE + патч и добавляет ровно 7 спек; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10a после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10a-probes/r10a_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10a-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "35649d1370a6d3171ccf5f23b7e3641fe3a3a4baf297e7a0a799e93701681781  docs/specs/fork-updates-r10a-probes/examples_base.txt" "48b58c4ac146e9a424754da1fcc1217da36739ee472edcb539d780c16cfc13ea  docs/specs/fork-updates-r10a-probes/pending_allowed.txt" "babbba7fd1b6f291ba6b48583df5027bba37e167da0524a19458a0653c9e0f64  docs/specs/fork-updates-r10a-probes/r10a_backlog_probe.sh" "f57a6ba4710db51f4389f8f757795b1e44b7f2003432354727c1c8557cbd8b5f  docs/specs/fork-updates-r10a-probes/r10a_config.json" "1350318673274725ae0f0dbf29f9942ea39afcf812a5cd78610110718e53ca93  docs/specs/fork-updates-r10a-probes/r10a_iseq.rb" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10a-probes/r10a_probe.py" "884567d4f909cef520de6aca84faca8c5c27168f1978da1e79de166ab8427d08  docs/specs/fork-updates-r10a-probes/r10a_rewrite.patch" "a8b54d63c230ebabaf884bb66d1634a42ba811a48d5c71469f56bf5882e0785a  docs/specs/fork-updates-r10a-probes/r10a_sentinel.rb" "b3c123fb67b6de3aca7a6d96b73adf3d4314d8b284a8a4bf10d9a8aa530a9a07  docs/specs/fork-updates-r10a-probes/r10a_tests.rb" "beaf2bb31cbe463dff945db4324348b7458a440e4a30ef8f1edb4558fc8dac21  docs/specs/fork-updates-r10a-probes/r10a_tests_gate.sh" "05303fe0b17e651efd0b93ded3aea0d6bd89ebe2ed98f6effe4879f0eb157aaa  docs/specs/fork-updates-r10a-probes/rspec_gate_r10a.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10a-probes/source_scan.py" "6b4db091732fa5c109d1ac0bbe4af6468713ff8291d6ff7d22dbbd01d1646645  docs/specs/fork-updates-r10a-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10A paths without
the change` / `is not BASE + r10a_rewrite.patch`); AC-003 красный (спек нет — `no examples ran`, тексты мутантов
не найдены); AC-004 красный (`Layout/LineLength: 37 offenses left in the files of this milestone`); AC-006
красный (`missing commits`).

Пробный прогон постановщика на 16682f02: все 9 критериев зелёные, бэклог 254 → 217. Приёмка 2026-11-22: исполнитель qw2, все 9 критериев зелёные на перезапуске постановщика, ISEQ совпал в 19 файлах, agy — без находок.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10a.md --exclude "docs/specs/fork-updates-r10a-probes/**" --exclude docs/specs/fork-updates-r10b.md --exclude "docs/specs/fork-updates-r10b-probes/**" --context "chaskiq fork-updates-r10a: RuboCop Layout/LineLength 37 выбросов в 20 файлах app/ — только переносы: 29 комментариев, %w[] Agent.ransackable_attributes, хеш InboxSections.user_data, kwargs Dante::Renderer, строки-литералы смежными кусками (SQL Dante::Migrator, scope Slack OAuth, options окна TwilioPhone, сообщение ChaskiqSchema с интерполяцией); 19 файлов — байткод BASE, chaskiq_schema.rb — точный текст в спеке; 7 спек характеризации зелёные на BASE, 13 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b-probes/**

Контекст ревьюеру: перенос, который меняет значение (пробел на стыке кусков строки, потерянная запятая в
`scope`, слово `%w[]`), спека, которая проверяет не всё значение (`include` вместо `eq`) или читает исходник.
Код править нельзя — замечание по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 9 критериев зелёные. Если agy упал или не дал
вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` у критерия —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10a.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10a.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, `R10A ISEQ` красный или
  после патча AC-004/AC-005 красные — дефект спеки;
- пример характеризации не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник, чтобы
  «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл перенос, меняющий значение, — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патча и мутантов, `pending`/`skip`, чтение
исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

- **`fork-updates-r10b` (qw2) может идти параллельно.** Общих файлов кода нет (r10b: `segment_comparator.rb`,
  `app_policy.rb`, `dante/converter.rb`, `visit_collector.rb`, `messenger_type.rb`, `fetch_link_card_service.rb`).
  Общие: `.rubocop_todo.yml` (r10a — строки блока `Layout/LineLength`; r10b — строки блоков `Metrics/AbcSize`,
  `CyclomaticComplexity`, `PerceivedComplexity`; ни один блок не пустеет) и `CHANGELOG.md` (блок после
  `# Changelog`). Проверено на 16682f02: оба патча применяются в любом порядке, скрипты todo — тоже, итог один.
- `fork-updates-r9b` влита в BASE 16682f02 (её файлы с этой вехой не пересекались; патч на db853da1 и на
  16682f02 одинаков).
- **Кто вливается вторым, тому — перенос BASE, `--write-base` (новые примеры первой вехи) и sha256 AC-008**
  (раздел 2, п. 2). Патч перегенерировать не нужно, пока `git apply --check` чист.
- Остаток `Layout/LineLength` (файлы бывшей r9b — R10c; спеки — R10e) и Metrics-выбросы — следующие вехи программы
  `fork-updates-r10-programme.md`, затем R9 (удалить todo).
- Мутационный прогон по семи спекам — у противоположного исполнителя (cx), после снятия запрета на Codex
  2026-11-22 11:39Z.
