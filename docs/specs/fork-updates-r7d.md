# fork-updates-r7d — бэклог RuboCop, шаг 7d: лишние классы — в свои файлы под Zeitwerk, локальные имена

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r7d.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «Решения владельца 2026-11-20, вторая партия»:
  «`OneClassPerFile` — `plugin_schema_validator.rb` в Exclude с причиной …, остальные 4 разнести по файлам
  Zeitwerk; … `VariableName`/`VariableNumber` — переименовать локальные»).
- BASE_SHA: `8e2ddd3ddddf86b4fb6909ef4248950902d3fd04` — HEAD `main` «Record R3b-3 acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, Zeitwerk-режим автозагрузки).
- BASE плавающий: если `main` уйдёт дальше до запуска (R2b, fix-cleanup-3, R7b, R7c — раздел 10), постановщик
  переносит его (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 20 КБ (почти
  весь — перенос классов без правок).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все десять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в дереве не остаётся `Style/OneClassPerFile` в трёх файлах (4 офенса; их строки уходят из todo — в
  блоке остаётся только то, что вынимает R7b) и `Naming/VariableName` (6) / `Naming/VariableNumber` (2) —
  их блоки уходят из todo. Четыре класса переезжают в свои файлы с ТЕМИ ЖЕ именами констант, байт в байт
  (плюс `# frozen_string_literal: true`); имена констант не меняются — по ним живут маршрутизация Zeitwerk,
  `rescue` в контроллере и спеки. Код задан двумя патчами постановщика (руками не править). Работа
  исполнителя — шесть НОВЫХ характеризационных спек (зелёные на BASE и после); каждый из 19 мутантов
  постановщика (`r7d_config.json`, `mutants`) роняет пример. Zeitwerk проверяет AC-008.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `Object.const_source_location`, `.source`,
парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` ``
в шелле — и затем `expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя**
иначе: другое сообщение, другой запрос, другой ответ, другая схема мутации. AC-007 (`source_scan.py`) ищет эти
приёмы в новых и изменённых файлах `spec/` и валит критерий на любом совпадении. Где лежит файл класса,
проверяет пробник постановщика (AC-008), не спеки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r7d`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r7d-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r7d-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` двух патчей по порядку (`r7d_split`, `r7d_locals`); блоки
   `cops_whole` и строки `cops_partial` в todo на месте (пробник сам падает со «spec defect»); тексты 19
   мутантов — каждый ровно один раз в своём файле после патчей; имена шести новых спек и четырёх новых файлов
   не заняты. Если менялся `spec/` — перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci bash docs/specs/fork-updates-r7d-probes/rspec_gate_r7d.sh --write-base`
   и пересчитать sha256 в AC-009. Сейчас в снимках — 1059 примеров BASE 8e2ddd3d.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-009 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 8e2ddd3d: `Style/OneClassPerFile` 25 (план — 27 в 5 файлах: в
`lib/subdomain_routes.rb` после R5b-2 класс один, 0 офенсов; 21 в `plugin_schema_validator.rb` — Exclude в R7b;
4 в трёх файлах — здесь); `Naming/VariableName` 6 (план — 7; строка `hooks_controller.rb` в todo устарела,
офенсов там 0 — уходит вместе с блоком); `Naming/VariableNumber` 2. Всего 1090, после вехи 1078. Перенесённый
код не приносит новых офенсов ни одного копа (замер: после патчей отличаются только эти 12).

**`r7d_split.patch` — Style/OneClassPerFile.** Класс вырезан из файла-хозяина вместе с пустой строкой перед
ним и вставлен в новый файл без единой правки, с `# frozen_string_literal: true` и пустой строкой сверху:

| Константа | Была в | Новый файл (корень Zeitwerk) | Кто ссылается |
|---|---|---|---|
| `OauthExeption < StandardError` | `app/controllers/graphql_controller.rb:106` | `app/controllers/oauth_exeption.rb` | `GraphqlController`: `rescue OauthExeption` (:45), `raise` (:95) |
| `AttachProfileAvatar < GraphQL::Schema::Mutation` | `app/graphql/mutations/articles/article_blob_attach.rb:32` | `app/graphql/attach_profile_avatar.rb` | никто (в схеме не подключена) |
| `ExternalApiClient` | `app/models/app_package_integration.rb:253` | `app/models/external_api_client.rb` | `AppPackageIntegration#message_api_klass` (:88); 2 спеки |
| `ExternalPresenterManager` | `app/models/app_package_integration.rb:315` | `app/models/external_presenter_manager.rb` | `AppPackageIntegration#get_presenter_manager` (:189, :197); 1 спека |

Имена (в том числе опечатка `OauthExeption`) не меняются: ни одна из четырёх констант не модель Active Record
и не job (AC-008 это проверяет), так что STI-столбцы `type` и полезная нагрузка Sidekiq их не называют, но
на них ссылаются `rescue`, `==` и спеки. Что меняется наблюдаемо: в ленивом режиме (development, test без
`CI`) на BASE константа существовала только после загрузки файла-хозяина — `ExternalApiClient` до первого
обращения к `AppPackageIntegration` давал `NameError`; теперь Zeitwerk грузит её из своего файла
(`Object.autoload?` до любой загрузки — AC-008). В eager-режиме (production, CI) разницы нет.

**`r7d_locals.patch` — Naming/VariableName, Naming/VariableNumber.** `MessageApis::Helpers#get_aspect_ratio`:
`maxWidth` → `max_width`, `maxHeight` → `max_height` (6 мест); `ActionTriggerFactory.infer_for`: `step_7` →
`step7` (8 мест, одно — в комментарии); `spec/models/segment_spec.rb:302`: `let(:predicates_on_tags_contains_multiple_2)`
→ `…_multiple2` и обе ссылки (описания примеров не меняются — AC-001 сверяет их со списком BASE). Локальные
имена снаружи не видны: поведение то же, что закрепляют спеки.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 8e2ddd3d:

1. Замер RuboCop без todo до и после патчей (раздел 3); каждый новый файл = вырезанный блок + шапка.
2. `bin/rails zeitwerk:check` после патчей — «All is good!»; `eager_load!` + `Zeitwerk::Loader.eager_load_all`
   на BASE и после: поверхность семи классов (четыре перенесённых и три хозяина — суперкласс, предки, методы)
   совпадает; на BASE `Object.autoload?` для четырёх констант — `nil`, после — их новые файлы.
3. Образцы шести спек постановщика (содержание — раздел 5): 16 примеров зелёные на BASE и дереве; 19/19
   мутантов убиты поведением.
4. Патчи применяются поверх патчей R2b, fix-cleanup-3, R7b, R7c и наоборот (раздел 10).
5. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: код вне репозитория (внешние плагины) не полагается на то, что `ExternalApiClient` появляется
только вместе с `AppPackageIntegration`.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. Код — **только** `git apply` патчей. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников
(раздел 1); спеки чисты под RuboCop (AC-004, AC-005: например, `.pluck(:step_uid)`, а не `map`;
`I18n.with_locale`, а не присваивание `I18n.locale`). Значения — точно (`eq`). Гейт тестов гоняет спеки с
`CI=1` (eager load, как на GitHub Actions), чтобы на BASE все четыре константы были загружены. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r7d-probes
export CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci
```

**Шаг 1. Характеризационные спеки** — 6 НОВЫХ файлов, код = BASE:
- `spec/models/oauth_exeption_spec.rb` (`RSpec.describe OauthExeption`): суперкласс `StandardError`;
  `OauthExeption.new.message == "This is a custom exception"`, `instance_variable_get(:@exception_type) ==
  "custom"`; `OauthExeption.new("Oauth Exception!", "oauth")` — эти два значения.
- `spec/graphql/attach_profile_avatar_spec.rb` (`RSpec.describe AttachProfileAvatar`): суперкласс
  `GraphQL::Schema::Mutation`; `arguments.keys == ["blobId"]`, `arguments["blobId"].type.non_null? == true`;
  в `fields` есть `"user"`, `fields["user"].type.non_null? == false`; `description` ровно
  `"Update the current user's avatar\n(by attaching a blob via signed ID)\n"`.
- `spec/models/external_api_client_spec.rb` (`RSpec.describe ExternalApiClient`): клиент
  `ExternalApiClient.new(config: { "package" => double(app_package: double(api_url: "https://ext.test/hook")) })`,
  `conn` заглушён (`allow(client).to receive(:conn)`) двойником, чей `post(url, json, headers)` запоминает
  аргументы и отдаёт `double(body: '{"ok":true}')`. `api_url` — этот адрес; `trigger(event)` (event — двойник с
  `action`, `created_at` = `Time.utc(2026, 1, 2, 3, 4, 5)`, `properties`, `eventable` с `to_json`) → ответ
  `{"ok" => true}`, url — адрес, заголовки ровно `{"Content-Type" => "application/json"}`, JSON тела ровно
  `{"action", "created_at" (as_json), "data" => {"subject" => <to_json eventable>, "properties"}}`;
  `enqueue_process_event({ "x" => 1 }, double(as_json: { "id" => 3 }))` → тело `{"x" => 1, "package" => {"id" => 3}}`;
  `subject_data(Conversation.new(key: "k1")) == conversation.to_json` (ветка `when Conversation` у
  `case eventable.class` не срабатывает никогда — это поведение BASE, его и закрепить); у НЕзаглушённого
  клиента `conn.options.timeout == 2`.
- `spec/models/external_presenter_manager_spec.rb` (`RSpec.describe ExternalPresenterManager`): `FactoryBot.create(:app)`,
  агент `app.add_agent({ email: }).agent`; `allow(Faraday).to receive(:post)` запоминает `[url, JSON.parse(body),
  headers]` и отдаёт `double(body: '{"kind":"ok"}')`; данные `{ package: double(app_package: <двойник с пятью
  *_url>), ctx: { app:, current_user: agent } }`. `post(url, data)` → `{"kind" => "ok"}`, заголовки ровно
  `{"Content-Type" => "application/json"}`, `ctx.app` ровно `{"key" => app.key, "name" => app.name}`,
  `ctx.current_user["email"]` — почта агента; каждый из `initialize_hook`, `configure_hook`, `submit_hook`,
  `sheet_hook`, `content_hook` шлёт на свой адрес.
- `spec/services/message_apis/helpers_aspect_ratio_spec.rb` (`RSpec.describe MessageApis::Helpers`, объект
  `Class.new { include MessageApis::Helpers }.new`): `get_aspect_ratio(2000.0, 500.0) == { width: 1000.0,
  height: 250.0, ratio: 25.0 }`; `(500.0, 2000.0) == { width: 250.0, height: 1000.0, ratio: 400.0 }`;
  `(500.0, 900.0) == { width: 500.0, height: 900.0, ratio: 180.0 }`; `(500, 400) == { width: 500, height: 400, ratio: 0 }`.
- `spec/services/action_trigger_factory_infer_spec.rb` (`RSpec.describe ActionTriggerFactory`):
  `FactoryBot.create(:app)`, бот `app.add_agent({ email:, name: "Bot" }, bot: true)`; `around` с
  `I18n.with_locale(I18n.locale)`; пользователю перед вызовом `lang = "en"`; шаги пути `"yes"` из
  `infer_for(app:, user:).paths` — `pluck(:step_uid)`: пользователь с почтой → `[7, 4]`; `app.update!(email_requirement:
  "Always")` и `app.add_anonymous_user({})` → `[7, 2, 3, 4]`; `email_requirement: "never"` → `[7, 4]`.

```bash
git add spec/models/oauth_exeption_spec.rb spec/graphql/attach_profile_avatar_spec.rb spec/models/external_api_client_spec.rb spec/models/external_presenter_manager_spec.rb spec/services/message_apis/helpers_aspect_ratio_spec.rb spec/services/action_trigger_factory_infer_spec.rb
git status --short        # ожидается: ровно 6 строк "A  spec/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 6 files
git commit -m "Add R7d characterization specs"
```

**Шаги 2–3. Перенос классов и локальные имена** (после каждого — ровно эта команда):

```bash
git apply $P/r7d_split.patch && git add app && git commit -qm "Move extra top-level classes to own files"
git apply $P/r7d_locals.patch && git commit -qam "Rename camelCase and numbered locals"
```

**Шаг 4. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r7d_tests_gate.sh $B` (≈ 5 мин). Нужны три
строки: `R7D TREE PASS … examples`, `R7D BASE PASS … char / 0 renamed failing / 0 fix failing`,
`R7D MUTANTS PASS 19/19 killed`. Пример красный на дереве или на BASE, мутант выжил — поправь спеку (код,
патчи и мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Add R7d characterization specs$')
mkdir -p tmp/r7d-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r7d-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r7d-specs (tmp/ игнорируется)
# поправь спеки в tmp/r7d-specs/spec/…, затем: cp -r tmp/r7d-specs/spec/. spec/
# затем — команды шагов 1–3, затем снова шаг 4
```

**Шаг 5. todo** — убрать блоки `cops_whole` и строки `cops_partial` конфига (блок без строк файлов уходит
целиком):

```bash
python3 -I - r7d <<'PY'
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
git commit -am "Drop R7d entries from RuboCop todo"
```

**Шаг 6. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r7d

- Changed: classes that shared a file with another top-level class moved to their own files under
  Zeitwerk, names unchanged (Style/OneClassPerFile): `OauthExeption` (app/controllers),
  `AttachProfileAvatar` (app/graphql), `ExternalApiClient` and `ExternalPresenterManager`
  (app/models). They now autoload on first use instead of only after their former host file loaded.
- Changed: local variables renamed (Naming/VariableName, Naming/VariableNumber): `maxWidth`/`maxHeight`
  in `MessageApis::Helpers#get_aspect_ratio`, `step_7` in `ActionTriggerFactory.infer_for`, and a
  `let` in `segment_spec.rb`; no behaviour change. Specs pin the moved classes and both methods.
```

```bash
git commit -am "Note fork-updates-r7d in changelog"
```

**Шаг 7.** Все десять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 8.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R7D … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`; AC-008 —
строка `R7D BOOT PASS`.

## 6. Не трогать

- Всё, кроме шести файлов патчей (три файла-хозяина, `helpers.rb`, `action_trigger_factory.rb`,
  `spec/models/segment_spec.rb` — только патчами), четырёх новых файлов из `r7d_split`, шести новых спек,
  `.rubocop_todo.yml`, `CHANGELOG.md`.
- Имена констант (в том числе опечатку `OauthExeption`), код внутри перенесённых классов, вызывающих.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`
  (в том числе `config.eager_load` и настройки Zeitwerk).
- Строки `plugin_schema_validator.rb` и `lib/subdomain_routes.rb` блока `Style/OneClassPerFile` (R7b) и блоки
  других копов.
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-009, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci bash docs/specs/fork-updates-r7d-probes/rspec_gate_r7d.sh'`

- **AC-002** — пути и код: изменены ровно 6 файлов патчей, добавлены ровно 4 файла классов и 6 файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патчей и каждый новый файл класса побайтно равен BASE с двумя патчами по порядку; todo = BASE без двух блоков и без трёх строк OneClassPerFile; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7d-probes/r7d_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD с CI=1: все примеры 6 спек зелёные на коде дерева и на коде BASE (файлы-хозяева BASE, четыре новых файла убраны); ошибок вне примеров нет; каждый из 19 мутантов r7d_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci bash docs/specs/fork-updates-r7d-probes/r7d_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у VariableName и VariableNumber 0 офенсов во всём дереве, у OneClassPerFile 0 в трёх файлах вехи; ни у одного другого копа ни в одном файле (новые файлы классов и спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci bash docs/specs/fork-updates-r7d-probes/r7d_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r7d-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно 6 спек при коде BASE; коммит переноса меняет ровно 3 файла-хозяина и добавляет ровно 4 файла классов = BASE + r7d_split; коммит локальных имён меняет ровно 3 файла = + r7d_locals; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r7d после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7d-probes/r7d_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7d-probes/source_scan.py $B'`

- **AC-008** — Zeitwerk на копиях BASE и HEAD без сети: bin/rails zeitwerk:check на HEAD проходит; на HEAD каждая из 4 констант автозагружается из своего нового файла; после Rails.application.eager_load! и Zeitwerk::Loader.eager_load_all суперкласс, предки и методы 4 перенесённых классов и 3 хозяев те же, что на BASE; ни один перенесённый класс не модель Active Record и не job.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7D_CACHE=$HOME/.cache/chaskiq-r7d-ci bash docs/specs/fork-updates-r7d-probes/r7d_boot.sh $B'`

- **AC-009** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "be11737287bc84bbb4bae187247be51982bdcef9b0c54caf09149754d995adb6  docs/specs/fork-updates-r7d-probes/examples_base.txt" "6c66945c162827cd0b7c97ee9199b1dc6debd5f0a15f196e8887f5ff4c4b8487  docs/specs/fork-updates-r7d-probes/pending_allowed.txt" "4ebab4c7d9852a4d675bc2ea156ec4b50fb76b45f9981568c0b1b9844861e2a2  docs/specs/fork-updates-r7d-probes/r7d_backlog_probe.sh" "4cf5ff3d68ce3ab71fd8b0996d9bb7fd7e1431fc2d05c036814c08e4f7fdf2fa  docs/specs/fork-updates-r7d-probes/r7d_boot.rb" "027c58dd3a0ac79042a45c88452d67e8b16491b199898a47003734d6bd20e953  docs/specs/fork-updates-r7d-probes/r7d_boot.sh" "0d88717646d4b91a0398ed59753d524f3cadfd246f076e6bae3051d677b88c17  docs/specs/fork-updates-r7d-probes/r7d_config.json" "11ab196b969190b261ba162fc44ffaf36e7100a5fb82ca9fe55899729fc5a27f  docs/specs/fork-updates-r7d-probes/r7d_locals.patch" "532180fc427855aefeac6d0e6c916e8a09b64752220482b78757b925dfc374bf  docs/specs/fork-updates-r7d-probes/r7d_probe.py" "7fc26593ea4ab3f5332d844774ffa2686f87435008ccf00bae01b89c84fffd48  docs/specs/fork-updates-r7d-probes/r7d_sentinel.rb" "c8bcc80dfb8f48e157691436f37035edfe6efaf1d6358e5c8b7c777d5f4b6a88  docs/specs/fork-updates-r7d-probes/r7d_split.patch" "d6cf8b89a6e94674af58a0dfd7cf643502889bf4e35561495e48a75913eebd85  docs/specs/fork-updates-r7d-probes/r7d_tests.rb" "fb551bd2ea823aaab1b5eae1ae084e0970d5cd9ef063972d114db7ab0a0be770  docs/specs/fork-updates-r7d-probes/r7d_tests_gate.sh" "6f6bb3ddf3dd771e8e7fa27e9c934d0f9c75d706b58ba8cc3aac3d8d1ef732f8  docs/specs/fork-updates-r7d-probes/rspec_gate_r7d.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fork-updates-r7d-probes/source_scan.py" "a88700524901c3390aaf1445c07ba0a8df09b17d7de0cd47900cf2a8e32cdb2f  docs/specs/fork-updates-r7d-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-010** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-009, AC-010 зелёные; AC-002 красный
(`R7D paths without the change` / `is not BASE + …`); AC-003 красный (спек нет, тексты мутантов не найдены);
AC-004 красный (`… offenses left`); AC-006 красный (`missing commits`); AC-008 красный (`HEAD autoloads it from
None`).

Пробный прогон автора (21.11.2026; свежий клон BASE 8e2ddd3d со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия `chaskiq-fxb-ci`, путь кэша в
командах подменён на копию):
- чистый клон: AC-001 (1059 примеров, 0 failures, 30 pending), AC-005, AC-007, AC-009, AC-010 — rc=0; AC-002,
  AC-003, AC-004 (`Naming/VariableName: 6 offenses left` …), AC-006, AC-008 (`HEAD autoloads it from None`)
  красные с сообщениями выше;
- после сборки: все 10 AC rc=0 — rspec 1075 примеров (16 новых), 0 failures, 30 pending; AC-003
  `R7D BASE PASS 16 char / 0 renamed failing / 0 fix failing`, `R7D MUTANTS PASS 19/19 killed` (≈ 1,5 мин);
  AC-004 бэклог без todo 1090 → 1078; AC-007 `SOURCE SCAN PASS 7 files`; AC-008 `R7D BOOT PASS`;
- порченые правки (все ловятся): `AttachProfileAvatar` в `app/graphql/mutations/` → AC-002, AC-008
  (`zeitwerk:check`); правка сообщения внутри перенесённого `OauthExeption` → AC-002; из спеки
  `ExternalApiClient` убран пример таймаута → AC-003 (выжил D09).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если код после ревью менялся). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r7d.md --exclude "docs/specs/fork-updates-r7d-probes/**" --context "chaskiq fork-updates-r7d: Style/OneClassPerFile — OauthExeption, AttachProfileAvatar, ExternalApiClient, ExternalPresenterManager перенесены в свои файлы Zeitwerk байт в байт, имена констант те же (zeitwerk:check, eager_load_all, поверхность классов = BASE); Naming/VariableName maxWidth/maxHeight и VariableNumber step_7 и let в segment_spec переименованы; 6 характеризационных спек зелёные на BASE; 19 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r7d.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r7d-probes/**

Контекст ревьюеру: перенесённый класс, чей код изменился при переносе; код, который зависел от того, что
константа определена только после загрузки хозяина (`defined?`, `const_defined?`, порядок `require`);
константа, которую сериализуют по имени; локальная переменная, переименованная не во всех местах; спека,
которая проверяет текст, а не поведение. Код править нельзя — замечание по месту решает постановщик
(раздел 9); спеки — можно, одним заходом.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 10 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r7d.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r7d.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все десять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после патчей
  AC-004/AC-005/AC-008 красные — дефект спеки;
- характеризационный пример не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник или
  место файла класса, чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл код, зависящий от прежнего места константы, или сериализацию её имени — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, переименование констант, правка `config/` и настроек
Zeitwerk, правка пробников, патчей и мутантов, `pending`/`skip`, чтение исходников в спеках, запуск Codex или
Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

- **R2b (qw2) и fix-cleanup-3 (qw2) — идут сейчас.** Общих файлов кода нет; общие — `.rubocop_todo.yml`
  (разные блоки, удаление скриптом) и `CHANGELOG.md`. Проверено на 8e2ddd3d: патчи применяются в любом порядке.
- **R7b** вынимает две другие строки того же блока `Style/OneClassPerFile`; **R7c** — общий только todo.
  Блок, оставшийся без строк файлов, удаляет та веха, что вливается последней (пробник считает ожидаемое от BASE;
  проверено для всех 24 порядков влития R2b/R7b/R7c/R7d — итоговый todo один и тот же).
- **Кто вливается вторым, тому — перенос BASE и `--write-base`** (раздел 2, п. 2).
- Мутационный прогон по шести спекам этой вехи — у противоположного исполнителя (cx), после снятия запрета на
  Codex 2026-11-22 11:39Z.
