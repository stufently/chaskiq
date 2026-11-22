# fork-updates-r10c — выбросы RuboCop, шаг 10c: длинные строки в файлах r9b перенесены, байткод тот же

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10c.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10c: «LineLength
  в файлах, которые меняла r9b (9 файлов) … Подход как в R10a: байткод там, где только перенос; характеризация
  `Campaign.config_fields`, `AppUser.ransackable_attributes`, символа ransack»), план чистки —
  `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10a` (та же механика). Соседние вехи —
  `fork-updates-r10a`, `fork-updates-r10b`, `fork-updates-r10cfg`; файлы кода ни с одной не пересекаются (раздел 10).
- BASE_SHA: `d1c1cd5cbda3e92a5c0175cbdb19d6d14b8081d3` — HEAD `main` «Record R10b acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10a`, `r10b`, `r10cfg` или другая веха — раздел 10), постановщик переносит BASE
  (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 18 КБ (больше половины — новые спеки).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в 9 файлах, которые меняла `r9b`, не остаётся `Layout/LineLength` (17 офенсов; их 9 строк уходят из блока
  todo). Код задан патчем постановщика `r10c_rewrite.patch` (руками не править): переносы строк и одна
  пересборка символа. Работа исполнителя — четыре НОВЫХ спеки характеризации (раздел 5): каждая зелёная на BASE
  и после; каждый из 14 мутантов постановщика (`r10c_config.json`, `mutants`) роняет пример. Сверх этого AC-003
  проверяет, что 7 из 9 файлов компилируются в байткод BASE.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, исключение, другой вызов (в том числе другие аргументы вызова застабленного
соавтора). AC-007 (`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на
любом совпадении. Байткод сравнивает пробник постановщика, не спеки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10c`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10c-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10c-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r10c_rewrite.patch`; строки 9 файлов в блоке
   `Layout/LineLength` todo на месте (иначе пробник сам падает со «spec defect»); тексты 14 мутантов — каждый ровно
   один раз в своём файле после патча; имена четырёх новых спек не заняты. Перегенерировать снимки на чистом
   checkout `main`:
   `CHASKIQ_R10C_CACHE=$HOME/.cache/chaskiq-r10c-ci bash docs/specs/fork-updates-r10c-probes/rspec_gate_r10c.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1384 примера BASE d1c1cd5c (после r10a+r10b).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 16682f02 (Docker, копия кэша `chaskiq-fxb-ci`): всего 254 офенса; у вехи — 17
`Layout/LineLength` в 9 файлах, которые меняла `r9b`. После патча — 237, новых офенсов нет (ни у одного копа ни в
одном файле больше, чем на BASE; `MethodLength` `Campaign#config_fields` и `AppUser#search_data` тоже не выросли).

**4 строки — комментарии** (`campaign.rb` закомментированное поле `replyEmail`, `block_manager.rb` пример блока
draft.js, `twilio_phone/api.rb` пояснение к `get_profile`, `lib/tasks/utils.rake` справка `gh run --status`) —
перенесены по словам. **13 строк — код**:

| Файл:строка BASE | Что | Доказательство |
|---|---|---|
| `controllers/api/v1/hooks_controller.rb:236` | условие `elsif (val = …find…&.dig("value")) && …` → 2 строки | спека: `handle_conversation_part` с заголовком `X-Forwarded-To` |
| `controllers/api/v1/hooks_controller.rb:265` | HTML-строка `<img …>` с четырьмя интерполяциями → два куска `"…" \` | спека: `process_attachment` — точный HTML (пробел на стыке кусков) |
| `graphql/types/app_type.rb:271` | символ ransack на 232 символа → `%w[]` шести полей, `:"#{query_fields.join('_or_')}_i_cont_any"` | спека: аргумент `Conversation.ransack` — тот же символ |
| `models/app_user.rb:139` | `%w[…]` на 50 слов → 5 строк | байткод + спека `AppUser.ransackable_attributes` |
| `models/app_user.rb:363` | блок `{ \|o\| {…} }` в хеше `search_data` → `do … end` на 3 строки | байткод |
| `models/campaign.rb:15,17,26,27` | хеши полей формы → по 2 строки | байткод + спека `Campaign#config_fields` |
| `models/concerns/globalize_accessors.rb:36` | тернарный оператор геттера → `if/else` | байткод |
| `services/message_apis/twilio/api.rb:40` | строка `hint:` → два куска | байткод |
| `services/message_apis/twilio_phone/api.rb:123,564` | цепочка вызовов, вызов с kwargs → 2 строки | байткод |

**Почему поведение то же.** Смежные строковые литералы без интерполяции Ruby склеивает при разборе; перенос
аргументов, элементов `%w[]`, пар хеша и звеньев цепочки меняет только номера строк; `cond ? a : b` и
`if cond then a else b end`, `{ }` и `do end` у блока внутри скобок аргумента дают один байткод. Пробник
`r10c_iseq.rb` (AC-003) сравнивает YARV-байткод BASE и дерева без номеров строк (инструкции, операнды,
литералы с кодировкой и байтами): 7 файлов `SAME`. Два файла — нет, их пиннят спеки:
- `hooks_controller.rb`: Prism (Ruby 4) не склеивает куски интерполированной строки (`concatstrings` в два
  приёма), к тому же файл «чувствителен к строкам» (`redis.eval`), и пробник сравнивал бы номера строк;
- `app_type.rb`: символ строится вызовом `join` — другой байткод, тот же символ.

**Находка (вне бэклога, решение координатора):** поиск разговоров по `term` (`Types::AppType#conversations`)
на BASE всегда падает: `Conversation` не объявляет `ransackable_attributes`, Ransack 4.2.1 поднимает
`RuntimeError "Ransack needs Conversation attributes explicitly allowlisted …"` до того, как разбирает поля.
Значит, поиск в инбоксе по тексту сейчас не работает. Веха не чинит, а пиннит: пример «raises today» спеки
`app_type_conversations_term_spec.rb` обязан быть зелёным на BASE и после; веха фиксов, добавив allowlist,
поменяет этот пример (программа, раздел 5).

**`r10c_rewrite.patch`** — 9 файлов, +44/−17 строк; `.rubocop.yml` не меняется.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 16682f02:

1. Замер RuboCop без todo до и после патча (раздел 3): 254 → 237, у 9 файлов `Layout/LineLength` 0, других
   изменений нет; строгий RuboCop с урезанным todo чист.
2. Байткод: 7 файлов `SAME`; `hooks_controller.rb` и `app_type.rb` `DIFF` (ожидаемо, раздел 3). Отдельно: только
   первый перенос `hooks_controller.rb` (условие) даёт `SAME` без номеров строк.
3. Образцы четырёх спек постановщика: 9 примеров зелёные на BASE и на дереве; 14/14 мутантов убиты.
4. Полный сьют на BASE d1c1cd5c: 1384 примера, 0 failures, 30 pending.
5. Патч применяется вместе с патчами `r10a`, `r10b`, `r10cfg` в любом из 24 порядков; todo и CHANGELOG — раздел
   10. Пробный прогон и порченая правка — раздел 7.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код — **только** `git apply` патча. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников (раздел 1);
спеки чисты под RuboCop (AC-004, AC-005; строки ≤ 140). Значения проверяй точно (`eq([...])`, `eq("…")`,
`raise_error(Класс, …)`), не `be_truthy`/`include` там, где известно всё значение. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10c-probes
export CHASKIQ_R10C_CACHE=$HOME/.cache/chaskiq-r10c-ci
```

**Шаг 1. Четыре спеки** (каждая — точное значение, зелёное и на BASE, и после патча):

- `spec/controllers/api/v1/hooks_controller_wrapped_lines_spec.rb` (`RSpec.describe Api::V1::HooksController`,
  `subject(:hooks) { described_class.new }`, приватные методы — через `hooks.send(...)`):
  - `handle_conversation_part(mail, json)` с `mail = double(recipients: ["someone@example.com"])` и
    `json = { "mail" => { "headers" => [...] } }`, `handle_inbound_recipient_from_forwarded` застаблен
    (`allow(hooks).to receive(...)`): (а) заголовки `[{ "name" => "Subject", "value" => "inbound+x" }, { "name" =>
    "X-Forwarded-To", "value" => "inbound+abc@example.com" }]` — возвращает значение стаба, стаб вызван ровно раз
    с `(mail, "inbound+abc@example.com")`; (б) `X-Forwarded-To` = `"other@example.com"` — `nil`, стаб не вызван;
    (в) заголовков нет — `nil`, стаб не вызван;
  - `process_attachment(attachment, message)` с `attachment = double(filename: "photo.png")` и
    `allow(hooks).to receive(:handle_direct_upload).with(attachment).and_return({ url:
    "https://cdn.example.com/photo.png", width: 640, height: 480 })`: сообщение `+"Hi [image: photo.png] there"` →
    `eq("Hi <img src='https://cdn.example.com/photo.png' title='photo.png' width='640' height='480' /> there")`;
    сообщение `+"Hi"` → тот же тег, к которому дописано `"Hi"`. Строку тега пиши в спеке целиком одним литералом.
- `spec/graphql/types/app_type_conversations_term_spec.rb` (`RSpec.describe Types::AppType, type: :graphql`): app
  (`FactoryBot.create(:app)`), агент `app.add_agent({ email: … }).agent`, один разговор
  `app.start_conversation(message: { html_content: "kiwi marmalade" }, from: app.add_user({ email: … }))`; резолвер —
  `described_class.send(:new, app, { current_user: agent })`, `allow(type).to receive(:authorize!).and_return(true)`,
  `type.conversations(per: 20, page: 1, filter: nil, sort: nil, term: "marmal")`. Два примера:
  - «raises today»: без стабов — `raise_error(RuntimeError, /\ARansack needs Conversation attributes explicitly
    allowlisted/)` (находка раздела 3);
  - условие поиска: `allow(Conversation).to receive(:ransack) do |*args, **opts| conditions << (args.first || opts);
    double(result: Conversation.none) end` — результат `to_a` `eq([])`, `conditions` `eq([{ key => "marmal" }])`, где
    `key` — символ, записанный в спеке смежными кусками ОДНОЙ строки и `.to_sym`:
    `"main_participant_full_name_or_main_participant_name_or_main_participant_email_or_main_participant_postal_or_main_participant_phone_or_messages_messageable_of_ConversationPartContent_type_text_content_i_cont_any"`
    (не собирай его `join` по списку полей — спека должна знать значение, а не повторять код). Форма, чистая под
    RuboCop: `key = "…_or_" \` / `"…_or_" \` / `"…_i_cont_any"` (продолжения выровнены по первой кавычке), затем
    `key.to_sym`; скобки вокруг кусков `("…" \ "…").to_sym` RuboCop не пропускает.
- `spec/models/campaign_config_fields_spec.rb`: `I18n.with_locale(:en) { Campaign.new.config_fields }` `eq` всего
  массива из 7 хешей по порядку: `name` («Campaign Name», hint «This will not be shown in the email», `"string"`,
  grid `w-full`/`w-full`), `fromName` («From Name», `"string"`, `w-full`/`w-1/2`), `subject` («Email Subject», hint
  «This is the email subject itself», `"text"`, `w-full`/`w-full`), `description` (`"textarea"`), `timezone`
  (`"timezone"`, `options: ActiveSupport::TimeZone.all.map { |o| o.tzinfo.name }`, `multiple: false`), `scheduledAt`
  («Scheduled at», `"datetime"`, `w-full`/`w-1/2`), `scheduledTo` («Scheduled to», `"datetime"`, `w-full`/`w-1/2`);
  плюс порядок ключей каждого хеша (`fields.map(&:keys)` `eq`).
- `spec/models/app_user_ransackable_attributes_spec.rb`: `AppUser.ransackable_attributes` `eq` полного списка из
  50 имён по порядку BASE (`app_id browser browser_language … updated_at web_sessions`); с аргументом — то же.

```bash
git apply $P/r10c_rewrite.patch
git add spec/controllers/api/v1/hooks_controller_wrapped_lines_spec.rb spec/graphql/types/app_type_conversations_term_spec.rb spec/models/campaign_config_fields_spec.rb spec/models/app_user_ransackable_attributes_spec.rb
git status --short        # ожидается: 4 строки "A  spec/…" и 9 строк " M app/…|lib/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 4 files
git commit -qam "Wrap long lines in files r9b touched"
```

**Шаг 2. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10c_tests_gate.sh $B` (≈ 3 мин). Нужны четыре строки:
`R10C TREE PASS 9 examples` (или больше), `R10C BASE PASS … char / 0 renamed failing / 0 fix failing`,
`R10C MUTANTS PASS 14/14 killed`, `R10C ISEQ PASS 7 files`. Пример красный на дереве или на BASE, мутант выжил —
поправь спеку (код, патч и мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Wrap long lines in files r9b touched$')
mkdir -p tmp/r10c-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r10c-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r10c-specs (tmp/ игнорируется)
# поправь спеки в tmp/r10c-specs/spec/…, затем: cp -r tmp/r10c-specs/spec/. spec/
# затем — команды шага 1, затем снова шаг 2
```

`ISEQ` красный — это не про спеки: раздел 9.

**Шаг 3. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10c <<'PY'
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
git commit -am "Drop R10c entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10c

- Changed: every line over 140 characters in the nine files fork-updates-r9b touched (Layout/LineLength
  outliers of R8a) is wrapped: four comments, a `%w[]` list, form-field hashes, a block inside a hash,
  a ternary turned into if/else, a condition, a method chain, a call with keywords and two string
  literals split into adjacent pieces; the 232-character ransack symbol of the conversation search is
  built from its field list.
  Seven files compile to the same bytecode as before; the hooks controller, the conversation search
  and the form-field and ransack lists are pinned by four new specs. Their 9 lines leave the
  Layout/LineLength block of the todo.
```

```bash
git commit -am "Note fork-updates-r10c in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — четыре строки `R10C … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 9 файлов патча (только патчем), четырёх новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Существующие спеки (в том числе `hooks_controller_spec.rb`, `campaign_*_spec.rb`, `app_user_spec.rb`,
  `app_type_*_spec.rb`) — не править.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`; файлы вех
  `r10a`, `r10b`, `r10cfg` (раздел 10). Allowlist Ransack для `Conversation` не добавлять (находка раздела 3 —
  решение координатора).
- Прочие блоки todo и строки других файлов в блоке `Layout/LineLength` (их убирают R10a/R10e).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10C_CACHE=$HOME/.cache/chaskiq-r10c-ci bash docs/specs/fork-updates-r10c-probes/rspec_gate_r10c.sh'`

- **AC-002** — пути и код: изменены ровно 9 файлов патча, 4 новых файла спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патча побайтно равен BASE с патчем; todo = BASE без 9 строк блока Layout/LineLength; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10c-probes/r10c_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 4 спек зелёные на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 14 мутантов r10c_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки; 7 файлов iseq_same компилируются в байткод BASE (без номеров строк), новых предупреждений ruby -wc нет.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10C_CACHE=$HOME/.cache/chaskiq-r10c-ci bash docs/specs/fork-updates-r10c-probes/r10c_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Layout/LineLength 0 офенсов в 9 файлах вехи; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10C_CACHE=$HOME/.cache/chaskiq-r10c-ci bash docs/specs/fork-updates-r10c-probes/r10c_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10c-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит правки меняет ровно 9 файлов = BASE + патч и добавляет ровно 4 спеки; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10c после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10c-probes/r10c_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10c-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "9e691ffba34a62ae2bf060972b2237ef17601c2d0bc8b5ff92512cd7f719ed82  docs/specs/fork-updates-r10c-probes/examples_base.txt" "7d37f103fb728f464b2dbc54e5244b4ab383c21c2747d62e33cc67bf76f3fab4  docs/specs/fork-updates-r10c-probes/pending_allowed.txt" "e20a4e3ff838dffaa0d3114faf355f69c2f7a658b48d31966aa914b85377a70e  docs/specs/fork-updates-r10c-probes/r10c_backlog_probe.sh" "0b34bf858917156d30f733c29b257a799f490709af8a5d8a1e991f28f1b91020  docs/specs/fork-updates-r10c-probes/r10c_config.json" "4a5dbae2c63ba8618cb081fa789993d3b2cd3362bb5c9307b53cd69a4425b13f  docs/specs/fork-updates-r10c-probes/r10c_iseq.rb" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10c-probes/r10c_probe.py" "4fc9d53f75e3460d3f1c7a93bf03ec2c51866084f5aad8821d47165bc64823d7  docs/specs/fork-updates-r10c-probes/r10c_rewrite.patch" "40b951502eb2a492442b13021a85b4ed0e6ba926bf103f3641af3cf54f42e897  docs/specs/fork-updates-r10c-probes/r10c_sentinel.rb" "f37fe58b48edc93c95ae7fc881932096f08ad43f0fd677304e9ba78702baa8f1  docs/specs/fork-updates-r10c-probes/r10c_tests.rb" "dd4010511a926a418fc017610966d236d900148537ebea8ecdc5db650b9d3abe  docs/specs/fork-updates-r10c-probes/r10c_tests_gate.sh" "5cfde3b4d06f88bc6761d9c001d38c9b12452e177872198b913177e7431b2747  docs/specs/fork-updates-r10c-probes/rspec_gate_r10c.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10c-probes/source_scan.py" "57734c4f69bb0c93dffb46c790cfb7bc1e98a2cfa95ae6e795d5c77eb2f4af31  docs/specs/fork-updates-r10c-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10C paths without
the change` / `is not BASE + r10c_rewrite.patch`); AC-003 красный (спек нет — `no examples ran`, тексты мутантов
не найдены); AC-004 красный (`Layout/LineLength: 17 offenses left in the files of this milestone`); AC-006
красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, копия кэша `chaskiq-fxb-ci`).** Граница: клон `make_clone.sh` от
коммита спеки поверх 0165d570 — AC-001 (1285 примеров, 420 с), AC-005, AC-007, AC-008, AC-009 rc=0; AC-002, AC-003,
AC-004 (`17 offenses left`), AC-006 красные ровно с сообщениями выше. Сборка по разделу 5 со спеками-образцами
постановщика: все 9 критериев зелёные (AC-001 — 1294 примера; AC-003 — 9 примеров, 14/14 мутантов, ISEQ 7 файлов;
AC-004 — 254 → 237). Порченые правки поверх сборки: (а) в `hint:` Twilio пропал пробел на стыке кусков — AC-002
(`is not BASE + r10c_rewrite.patch`), AC-003 (`DIFF app/services/message_apis/twilio/api.rb`, `iseq_same: 6 of 7`),
AC-006 (лишний коммит); (б) `"width='…'height="` в теге `<img>` — AC-002, AC-003 (оба примера `process_attachment`
красные), AC-006. Первый прогон поймал дефект самих образцов: символ, записанный `("…" \ "…").to_sym`, дал в спеке
`Style/RedundantParentheses` и `Layout/LineEndStringConcatenationIndentation` (AC-004, AC-005) — отсюда форма в шаге 1.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10c.md --exclude "docs/specs/fork-updates-r10c-probes/**" --exclude docs/specs/fork-updates-r10cfg.md --exclude "docs/specs/fork-updates-r10cfg-probes/**" --exclude docs/specs/fork-updates-r10a.md --exclude "docs/specs/fork-updates-r10a-probes/**" --exclude docs/specs/fork-updates-r10b.md --exclude "docs/specs/fork-updates-r10b-probes/**" --context "chaskiq fork-updates-r10c: RuboCop Layout/LineLength 17 выбросов в 9 файлах, которые меняла r9b — только переносы: 4 комментария, %w[] AppUser.ransackable_attributes, хеши Campaign#config_fields, блок в search_data, тернарный геттер GlobalizeAccessors → if/else, цепочка и kwargs TwilioPhone::Api, строки-литералы смежными кусками (hint Twilio, HTML <img> HooksController#process_attachment с интерполяцией), условие X-Forwarded-To; символ ransack AppType#conversations собран из %w[] полей; 7 файлов — байткод BASE, hooks_controller.rb и app_type.rb — спеки (точный HTML, аргумент Conversation.ransack); 4 спеки характеризации зелёные на BASE, 14 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10c.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10c-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b-probes/**

Контекст ревьюеру: перенос, который меняет значение (пробел на стыке кусков строки, потерянное слово `%w[]`,
другой символ ransack, `do … end`, привязавшийся не к тому вызову), спека, которая проверяет не всё значение
(`include` вместо `eq`) или читает исходник. Код править нельзя — замечание по месту решает постановщик (раздел 9);
спеки — можно, одним заходом.

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10c.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10c.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, `R10C ISEQ` красный или
  после патча AC-004/AC-005 красные — дефект спеки;
- пример характеризации не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник, чтобы
  «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл перенос, меняющий значение, — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патча и мутантов, `pending`/`skip`, чтение
исходников в спеках, починка поиска Ransack, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на 16682f02 (`r10a_rewrite.patch`, `r10b_rewrite.patch`, `r10c_rewrite.patch`, `r10cfg_rewrite.patch`):

- **Код.** Общих файлов кода нет ни с одной вехой (r10a — 20 других файлов `app/`, r10b — шесть, r10cfg — только
  `.rubocop.yml`). Все четыре патча применяются `git apply` в любом из 24 порядков.
- **`.rubocop_todo.yml`.** r10c убирает 9 строк блока `Layout/LineLength`, r10a — 20 строк ТОГО ЖЕ блока: строки
  перемежаются (строки BASE 11–45), поэтому **слияние r10a и r10c даёт конфликт в этом блоке** (один хунк). Решение
  при влитии — взять todo первой влитой вехи и прогнать на нём шаг 3 второй (скрипт идемпотентен по строкам;
  результат во всех 24 порядках четырёх скриптов один). С r10b (блоки `AbcSize`/`Cyclomatic`/`Perceived`) и r10cfg
  (блоки `MethodLength`/`ClassLength`/`BlockLength`) git сливает чисто. Каждый скрипт todo ещё и добавляет перевод
  строки в конце файла (на BASE его нет) — изменение одинаковое, слиянию не мешает, но отдельные дифы todo
  друг на друга `git apply` не ложатся.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog` — конфликт при любой паре, решается
  вставкой обоих блоков.
- **Вместе.** BASE + r10a + r10b + r10c: 254 → 194 офенса без todo; + r10cfg: 120 (r10cfg снимает те же 74);
  строгий RuboCop с объединённым todo — ноль офенсов.
- **Кто вливается вторым, тому — перенос BASE, `--write-base` (новые примеры первой вехи) и sha256 AC-008**
  (раздел 2, п. 2). Патч перегенерировать не нужно, пока `git apply --check` чист.
- Остаток `Layout/LineLength` (спеки — R10e) и Metrics-выбросы — следующие вехи программы
  `fork-updates-r10-programme.md`, затем R9 (удалить todo).
- Мутационный прогон по четырём спекам — у противоположного исполнителя (cx), после снятия запрета на Codex
  2026-11-22 11:39Z.
