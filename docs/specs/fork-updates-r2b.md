# fork-updates-r2b — бэклог RuboCop, шаг 2b: четыре копа с решением владельца, тест на каждую смену поведения

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r2b.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «R2b» и «Решения владельца 2026-11-20, вторая партия»:
  «`ReturnNilInPredicateMethodDefinition` — принять с тестом; `MutableConstant` `HEADERS` — `.freeze`;
  `MemoizedInstanceVariableName` — переименовать `api_controller.rb:93` и `app.rb:256`, `api_controller.rb:139`
  … — в Exclude с причиной; `Bundler/OrderedGems` — сортировать, доказать полным rspec и загрузкой приложения»).
- BASE_SHA: `a631554ca85cb5175b29096f83ae2db330ec54e4` — HEAD `main` «Record mut-fxb acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, Bundler 4.0.20).
- BASE плавающий: если `main` уйдёт дальше до запуска, постановщик переносит его (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-010).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 12 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все одиннадцать критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: в дереве не остаётся `Style/ReturnNilInPredicateMethodDefinition` (3), `Style/MutableConstant` (1),
  `Naming/MemoizedInstanceVariableName` (3: одно переименование, два — Exclude с причиной),
  `Bundler/OrderedGems` (2) — 9 офенсов, их четыре блока уходят из todo. Код задан патчами постановщика
  (автокоррекция RuboCop плюс Exclude в `.rubocop.yml`, руками не править). Работа исполнителя — одна
  характеризационная спека (зелёная на BASE и после) и три спеки смены поведения (`nil` → `false`, `.freeze`;
  красные на BASE по причине самой смены, зелёные после); каждый из 11 мутантов постановщика
  (`r2b_config.json`, `mutants`) роняет пример. Сортировка Gemfile доказывается полным rspec, загрузкой
  приложения (AC-009) и неизменным `Gemfile.lock` (AC-008).
- **Остальные 12 копов раздела R2b плана в веху не входят** — решения владельца по ним нет (раздел 3, «Вне
  вехи»); их блоки в todo остаются (AC-002).

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, незамороженный объект, другой запрос клиенту, новый объект расписания. AC-007
(`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r2b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r2b-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r2b-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` четырёх патчей по порядку (`r2b_predicate`, `r2b_freeze`,
   `r2b_memo`, `r2b_gems`); не применяются — пересобрать теми же командами (раздел 3) и перепроверить тексты
   11 мутантов (каждый ровно один раз в своём файле после патчей) и имена четырёх новых спек. Если менялся
   `spec/` — перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/rspec_gate_r2b.sh --write-base`
   и пересчитать sha256 в AC-010. Сейчас в снимках — 1051 пример BASE a631554c.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-010 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE a631554c (Docker, кэш `chaskiq-fxb-ci`): всего 1093 офенса; у четырёх
копов вехи 9, у 16 копов R2b плана — 42 (`Style/StringConcatenation` 15 и т. д., раздел «Вне вехи»).
Патчи — вывод `rubocop -A --only <коп>` по файлам офенсов (плюс Exclude в `r2b_memo`).

**`r2b_predicate.patch` — `Style/ReturnNilInPredicateMethodDefinition`, 3 места (план: «2 (+1 из R2)»).**
- `open_ai/api.rb:90` `locked_for_channel?` — `return unless …` → `return false unless …` (автор части не
  агент или бот). Единственный вызывающий — `open_ai/api.rb:106` `return true if locked_for_channel?(…)`:
  проверка истинности, `nil` и `false` дают одно и то же.
- `twilio/api.rb:247,248` `new_conversation_thread?` — `return if from.blank?` и `return if
  new_thread_in_hours.blank?` → `return false …`. Единственный вызывающий — `twilio/api.rb:271`
  (`if conversation.blank? || conversation.closed? || new_conversation_thread?(…)`): истинность та же.
Наблюдаемо меняется только возвращаемое значение (`nil` → `false`) — его и проверяют спеки (красные на BASE).

**`r2b_freeze.patch` — `Style/MutableConstant`, `oauth_utils.rb:7`:** `HEADERS = {…}.freeze`. Модуль
`MessageApis::OauthUtils` в `app/`, `lib/` никто не подключает (`git grep OauthUtils` — только сам файл; у
`slack/api.rb:91` и `twitter/api.rb:79` свои замороженные `HEADERS`), так что мутировать константу некому;
спека проверяет `frozen?` (красная на BASE) и что `make_post_request` по-прежнему передаёт эти заголовки.

**`r2b_memo.patch` — `Naming/MemoizedInstanceVariableName`, 3 места.**
- `app.rb:256` `availability` — `@biz ||=` → `@availability ||=` (автокоррекция). `@biz` больше нигде не
  читается и не пишется (`git grep '@biz'` — одна строка), `@availability` у `App` не занят.
- `api_controller.rb:93` (`get_user_data`, `@user_data`) и `api_controller.rb:136` (`get_app_user`,
  `@app_user`; в плане строка 139 — сдвинулась) — **оба в Exclude** `.rubocop.yml` с причиной в комментарии.
  **Отступление от буквы решения по `:93` (решение координатора по делегированию, причина та же, что у
  владельца для `:139`):** `@user_data` — общее состояние: его пишут `get_user_data_from_auth`
  (`api_controller.rb:17-26`) и `Api::GraphqlController#auth` (`api/graphql_controller.rb:68`), читают
  `set_locale`, `merge_user_data`, `add_user`-ветка (`:45-51`), а `Api::GraphqlController` отдаёт его через
  `attr_reader :user_data`. Автокоррекция (`@get_user_data ||=`) разорвала бы мемоизацию с этими методами
  (повторное вычисление вместо значения из `auth`), а переименование метода в `user_data` столкнулось бы с
  `attr_reader :user_data` подкласса (там без мемоизации). Exclude — на весь файл (оба офенса в нём).
- Блок `Naming/MemoizedInstanceVariableName` уходит из todo; новая запись в `.rubocop.yml` — часть патча.

**`r2b_gems.patch` — `Bundler/OrderedGems`, 2 места:** `gem "pg"` переезжает после `gem "ostruct"`
(было перед `cgi`), `gem "aws-actionmailer-ses"` — перед `gem "aws-sdk-rails"`. Меняется только порядок
`Bundler.require` (`config/application.rb:7`) для этих четырёх гемов. `Gemfile.lock` не меняется вовсе:
проверено — `bundle lock --local` на BASE и после сортировки оставляет его побайтно тем же (секция
`DEPENDENCIES` у Bundler и так отсортирована по имени); законных изменений в нём нет, поэтому AC-008
требует побайтного равенства BASE. Загрузка приложения с `eager_load!` в Docker — AC-009.

**Вне вехи (решения владельца нет, блоки в todo остаются; по `main` a631554c):** `Style/StringConcatenation` 15
(4 в `app/`, 11 в `spec/`), `SymbolProc` 3, `SingleArgumentDig` 3, `MapIntoArray` 2, `InverseMethods` 2,
`MultipleComparison` 2, `SafeNavigation` 1, `HashEachMethods` 1, `FloatDivision` 1, `CaseLikeIf` 1,
`ModuleMemberExistenceCheck` 1, `RedundantRegexpEscape` 1 — 33 офенса. Числа совпадают с планом (d8c82e37).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE a631554c:

1. Замер RuboCop без todo (раздел 3) и вывод автокоррекции по копам — патчи.
2. `bundle lock --local` без сети: на BASE и после `r2b_gems` `Gemfile.lock` побайтно равен BASE;
   `bin/rails runner` с `Rails.application.eager_load!` (RAILS_ENV=test, без сети, без БД) на BASE и после
   сортировки — `R2B BOOT OK 63 models`.
3. Образцы четырёх спек постановщика (содержание — раздел 5): характеризационная зелёная на BASE и дереве;
   три спеки смены красные на BASE по причине смены (`expected: false got: nil`, `….frozen?` to be truthy);
   11/11 мутантов убиты поведением.
4. Патчи применяются поверх двух патчей R3b-3 и наоборот (раздел 10).
5. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: другие гемы не зависят от порядка `require` `pg`/`cgi` и `aws-sdk-rails`/`aws-actionmailer-ses`
(Bundler грузит зависимости гема раньше него самого); подтверждают AC-001 и AC-009, продакшен-группу
(`RAILS_ENV=production`) веха не грузит — Gemfile менялся только в группе по умолчанию.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код, `Gemfile` и `.rubocop.yml` — **только** `git apply` патчей. В каждой спеке
`# frozen_string_literal: true`, `require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:`
директив, чтения исходников (раздел 1). Экземпляры API — `described_class.allocate` (конструкторы ходят в
сеть и конфиг), ivar — `instance_variable_set`. Возвращаемые значения проверяй точно: `eq(false)` /
`eq(true)`, не `be_falsey`. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r2b-probes
export CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci
```

**Шаг 1. Характеризационная спека** `spec/models/app_availability_memo_spec.rb` (`RSpec.describe App`), код =
BASE: `app = FactoryBot.create(:app)`, затем `app.update!(timezone: "UTC", team_schedule: [{ day: "tue", from:
"01:00", to: "01:30" }])` (фабрика перезаписывает расписание, поэтому — после создания); `app.availability` —
`Biz::Schedule`, второй вызов возвращает ТОТ ЖЕ объект (`equal`); `in_business_hours?(Time.utc(2019, 9, 3, 1,
15))` — ровно `true`, `(…, 2, 15)` — ровно `false`.

```bash
git add spec/models/app_availability_memo_spec.rb
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 1 files
git commit -m "Add R2b characterization specs"
```

**Шаг 2. Предикаты.** Спеки (`app = FactoryBot.create(:app)`):
- `spec/services/message_apis/open_ai_locked_for_channel_spec.rb` (`RSpec.describe MessageApis::OpenAi::Api`):
  разговор пользователя `app.start_conversation(message: { text_content: "hi" }, from: user)`; часть —
  `double(authorable: …)`. Автор — пользователь → `eq(false)`; агент с `update!(bot: true)` → `eq(false)`;
  агент-человек (`app.add_agent({ email: }).agent`) при канале
  `conversation.conversation_channels.create!(provider: "open_ai", provider_channel_id: conversation.id)` →
  `eq(true)`, канала `open_ai` у разговора больше нет.
- `spec/services/message_apis/twilio_new_thread_spec.rb` (`RSpec.describe MessageApis::Twilio::Api`): `@package`
  — `double(settings: settings)`; `new_conversation_thread?(nil)` при `{ new_conversations_after: "2" }` →
  `eq(false)`; при `{}` и `3.hours.ago` → `eq(false)`; при `"2"`: `3.hours.ago` → `eq(true)`, `1.hour.ago` →
  `eq(false)`.

```bash
git apply $P/r2b_predicate.patch
git add spec/services/message_apis/open_ai_locked_for_channel_spec.rb spec/services/message_apis/twilio_new_thread_spec.rb
git commit -qam "Return false from predicate methods"
```

**Шаг 3. HEADERS.** Спека `spec/services/message_apis/oauth_utils_headers_spec.rb`
(`RSpec.describe MessageApis::OauthUtils`): `described_class::HEADERS == { "content-type" => "application/json" }`
и `be_frozen`; объект `Class.new { include MessageApis::OauthUtils }.new` с `@client` — double, который
ожидает `post("/path", "{}", { "content-type" => "application/json" })` и отдаёт `double(code: "200", body:
"ok")` → `make_post_request("/path", "{}") == "ok"`.

```bash
git apply $P/r2b_freeze.patch
git add spec/services/message_apis/oauth_utils_headers_spec.rb
git commit -qam "Freeze the OAuth JSON headers"
```

**Шаги 4–5. Мемоизация и Gemfile** (после каждого — ровно эта команда):

```bash
git apply $P/r2b_memo.patch && git commit -qam "Name the availability memo after it"
git apply $P/r2b_gems.patch && git commit -qam "Sort the Gemfile"
git diff --quiet HEAD~1 HEAD -- Gemfile.lock && echo "lock untouched"   # ожидается: lock untouched
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r2b_tests_gate.sh $B` (≈ 2–3 мин). Нужны три
строки: `R2B TREE PASS …`, `R2B BASE PASS 2 char / 3 fix failing for the change` (число char-примеров —
твоё), `R2B MUTANTS PASS 11/11 killed`. Пример красный на дереве, характеризационный красный на BASE, спека
смены зелёная на BASE или красная не по той причине, мутант выжил — поправь спеку (код, патчи и мутантов не
трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Add R2b characterization specs$')
mkdir -p tmp/r2b-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r2b-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r2b-specs (tmp/ игнорируется)
# поправь спеки в tmp/r2b-specs/spec/…, затем: cp -r tmp/r2b-specs/spec/. spec/
# затем — команды шагов 1–5 (каждый шаг добавляет только свои спеки), затем снова шаг 6
```

**Шаг 7. todo** — убрать блоки четырёх копов вехи (`cops_whole` конфига; остальные блоки не трогать):

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r2b-probes/r2b_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R2b entries from RuboCop todo"
```

**Шаг 8. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r2b

- Changed: `MessageApis::OpenAi::Api#locked_for_channel?` and `MessageApis::Twilio::Api#new_conversation_thread?`
  return `false` instead of `nil` on their early exits (Style/ReturnNilInPredicateMethodDefinition); callers
  only test truthiness.
- Changed: `MessageApis::OauthUtils::HEADERS` is frozen (Style/MutableConstant).
- Changed: `App#availability` memoizes in `@availability` (was `@biz`); ApiController's memoized ivars are
  excluded from Naming/MemoizedInstanceVariableName in `.rubocop.yml` with the reason.
- Changed: Gemfile gems sorted within their sections (Bundler/OrderedGems); Gemfile.lock unchanged.
```

```bash
git commit -am "Note fork-updates-r2b in changelog"
```

**Шаг 9.** Все одиннадцать критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 10.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R2B … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`; AC-008 —
`R2B GEMLOCK PASS`; AC-009 — строка `R2B BOOT OK …`.

## 6. Не трогать

- Всё, кроме шести файлов патчей (`.rubocop.yml`, `Gemfile`, `app/models/app.rb`, `oauth_utils.rb`,
  `open_ai/api.rb`, `twilio/api.rb` — только патчами), четырёх новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- `Gemfile.lock` (ни байта), `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`,
  `app/controllers/**` (Exclude вместо правки `api_controller.rb`), существующие спеки.
- Блоки todo 12 копов «Вне вехи» и всех прочих копов.
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, `bundle update`,
  `bundle lock` в клоне, чтения исходников в спеках.
- `docs/specs/**` — не править (AC-010, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/rspec_gate_r2b.sh'`

- **AC-002** — пути и код: изменены ровно 6 файлов патчей, 4 новых файла спек (новые обычные файлы), todo и CHANGELOG — каждый; Gemfile.lock не тронут; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патчей побайтно равен BASE с четырьмя патчами по порядку; todo = BASE без блоков четырёх копов вехи; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r2b-probes/r2b_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 4 спек зелёные на коде дерева; на коде BASE характеризационная зелёная, в каждой из 3 спек смены есть пример, упавший на ожидании с текстом смены (base_reason), ошибок вне примеров нет; каждый из 11 мутантов r2b_config.json (текст найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/r2b_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у четырёх копов вехи 0 офенсов во всём дереве; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/r2b_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r2b-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно свою спеку при коде BASE; каждый коммит патча оставляет файлы патчей = BASE + патчи до своего включительно и добавляет ровно свои спеки; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r2b после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r2b-probes/r2b_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r2b-probes/source_scan.py $B'`

- **AC-008** — сортировка не меняет разрешение гемов: Gemfile.lock в HEAD и в дереве побайтно равен BASE; Gemfile HEAD — те же строки, что BASE, только в другом порядке; на копии HEAD bundle lock --local без сети оставляет Gemfile.lock побайтно BASE, bundle check проходит.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/r2b_gemlock.sh $B'`

- **AC-009** — приложение грузится с отсортированным Gemfile: на копии HEAD в образе bin/ci-local без сети bin/rails runner с Rails.application.eager_load! завершился 0 и напечатал R2B BOOT OK.
  `bash -c 'CHASKIQ_R2B_CACHE=$HOME/.cache/chaskiq-r2b-ci bash docs/specs/fork-updates-r2b-probes/r2b_boot.sh'`

- **AC-010** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "a4c06a2b450a67ab7eb9223d31b38f739b2975b1f899cf2659137758e4b7ca31  docs/specs/fork-updates-r2b-probes/r2b_probe.py" "119e6f5fa59b104ca85e82d6a24204d928195d94f2b6dc1cd08cf59a1da003b5  docs/specs/fork-updates-r2b-probes/r2b_config.json" "c6b7ab464f582a915f973771660a9b413ee1b267743801228ebfce81670f59a8  docs/specs/fork-updates-r2b-probes/r2b_tests.rb" "506fdc1fa18a5932e02116abc44de6b25cdb97215b3b6aa42b1b2a81f5025359  docs/specs/fork-updates-r2b-probes/r2b_tests_gate.sh" "e1ab408d4624462ac704d261562e824727e826d28200680481c33cc344c2b3c1  docs/specs/fork-updates-r2b-probes/r2b_backlog_probe.sh" "00529054264541782fc423cf333d57f274b0b99bc5bb95a94e5f3f9b71d55570  docs/specs/fork-updates-r2b-probes/r2b_gemlock.sh" "ea7b3d9fe6bac10b29fc660f32623d94220c7bdd9a697ec685c70cd17c85f445  docs/specs/fork-updates-r2b-probes/r2b_boot.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fork-updates-r2b-probes/source_scan.py" "a9ef2d87c33c498de214a94dec1ebe6e7bb70afb526c9e249feeb8ca1bfee345  docs/specs/fork-updates-r2b-probes/r2b_predicate.patch" "9cda243c4bc92eedac902fef8bfd47cf09ec90cd923ead1a13de2a301eea73f5  docs/specs/fork-updates-r2b-probes/r2b_freeze.patch" "055c052c24f8f7683cb717189442a5defd4ee8d948da822645f994b9fa20b55d  docs/specs/fork-updates-r2b-probes/r2b_memo.patch" "15f44f4a2b13acac442f778eb59811466d457244c7301dec8cba09c62d905395  docs/specs/fork-updates-r2b-probes/r2b_gems.patch" "2dfde71ae9b0856ef8262bfaaed2b5fc16ece98dab566d886be20c0c291fb2c8  docs/specs/fork-updates-r2b-probes/rspec_gate_r2b.sh" "8183241b1253f1eb1314e6f2a87d64f0a275ed9b71bdea5ada438314b5e5e34f  docs/specs/fork-updates-r2b-probes/r2b_sentinel.rb" "8e31edd84bb61503b519b157dacb96e47b4acc4ff55820e73497d209fb3f1b5f  docs/specs/fork-updates-r2b-probes/examples_base.txt" "926162de991d184e8db868d462b90c9b5c809c3d5d32d1893fdf7202ce421f7e  docs/specs/fork-updates-r2b-probes/pending_allowed.txt" "734b97928f3e3092e9c0c4436bbbc02efad4c647f8cefa8603c6aad6e339ee4f  docs/specs/fork-updates-r2b-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-011** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-009, AC-010, AC-011 зелёные; AC-002 красный
(`fork-updates-r2b paths without the change` / `is not BASE + …`); AC-003 красный (тексты мутантов не
найдены, спек нет); AC-004 красный (`… offenses left`); AC-006 красный (`missing commits`); AC-008 красный
(`the Gemfile of HEAD is BASE's (not sorted)`).

Пробный прогон автора (21.11.2026; свежий клон BASE a631554c со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия `chaskiq-fxb-ci`):
- чистый клон: AC-005, AC-007, AC-009, AC-010, AC-011 — rc=0; AC-002, AC-003, AC-004, AC-006, AC-008 красные
  с сообщениями выше (AC-001 = снимок `--write-base` на BASE: 1051 пример, 0 failures);
- после сборки: все 11 AC rc=0 — rspec 1062 примера (11 новых), 0 failures, 30 pending (≈ 7 мин); AC-003
  `R2B BASE PASS 2 char / 3 fix failing for the change`, `R2B MUTANTS PASS 11/11 killed`; AC-004 бэклог без todo
  1093 → 1084; AC-008 `R2B GEMLOCK PASS`; AC-009 `R2B BOOT OK 63 models`;
- порченые правки (все ловятся): `be_falsey` вместо `eq(false)` → AC-003 (выжили B04, B05); лишний байт в
  `Gemfile.lock` → AC-002, AC-008; `gem "pg", "~> 1.5"` → AC-008; переименование `@user_data` в
  `api_controller.rb` → AC-002; без Exclude в `.rubocop.yml` → AC-002, AC-004, AC-005.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если код после ревью менялся). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r2b.md --exclude "docs/specs/fork-updates-r2b-probes/**" --context "chaskiq fork-updates-r2b: RuboCop ReturnNilInPredicateMethodDefinition 3 (return false вместо nil, вызывающие проверяют истинность), MutableConstant 1 (OauthUtils::HEADERS.freeze, модуль никто не подключает), MemoizedInstanceVariableName 3 (App#availability @biz -> @availability; api_controller.rb в Exclude .rubocop.yml с причиной: @user_data и @app_user — общее состояние с другими методами и Api::GraphqlController), Bundler/OrderedGems 2 (Gemfile.lock побайтно тот же, загрузка с eager_load! проверена); 1 характеризационная спека и 3 спеки смены, красные на BASE; 11 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r2b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r2b-probes/**

Контекст ревьюеру: найти вызывающего предиката, которому важно `nil` против `false` (`== nil`, `.nil?`,
сериализация); код, мутирующий `HEADERS`; чтение `@biz` где-либо ещё; гем, чья загрузка зависит от
порядка `pg`/`cgi` или `aws-sdk-rails`/`aws-actionmailer-ses`; и спеку, которая проверяет текст, а не поведение.
Код править нельзя — замечание по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 11 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 11: AC-001…AC-011. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r2b.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r2b.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все одиннадцать критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004/AC-005 красные — дефект спеки;
- `Gemfile.lock` меняется (`bundle` переписал его при любом запуске) или приложение не грузится (AC-009) —
  приложи дифф и вывод; чинить `bundle lock`/`bundle update`, правкой Gemfile или `--no-deps` ЗАПРЕЩЕНО;
- характеризационный пример не может быть зелёным на BASE или пример смены — красным на BASE по причине
  смены, проверяя описанное в разделе 5 поведение — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл вызывающего, которому важен `nil`, мутацию `HEADERS` или зависимость от порядка гемов —
  файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, Gemfile, `.rubocop.yml` и существующих спек, правка пробников, патчей и
мутантов, `pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и
коды возврата.

## 10. Стыки

- **R3b-3 (`fork-updates-r3b3`, qw2) — может идти параллельно.** Её файлы кода —
  `api/v1/hooks/provider_controller.rb`, `application_controller.rb`, `concerns/package_iframe_behavior.rb`;
  с патчами этой вехи общих нет (`api_controller.rb` здесь не меняется). Общие файлы — `.rubocop_todo.yml`
  (здесь уходят четыре блока, там — блок `Rails/StrongParametersExpect`; оба удаляют блок целиком скриптом,
  а не патчем) и `CHANGELOG.md` (оба вставляют блок после `# Changelog`). Проверено на a631554c: патчи обеих вех
  применяются в любом порядке; второй влитой вехе — перенос BASE и `--write-base`.
- **fix-cleanup-3 (qw2) — может идти параллельно:** там только `app/models/lead.rb`; общий — `CHANGELOG.md`.
- Мутационный прогон по четырём спекам этой вехи — у противоположного исполнителя (cx), после снятия
  запрета на Codex 2026-11-22 11:39Z.
- Следующие вехи R2b (12 копов «Вне вехи») — после решений владельца по каждому.
