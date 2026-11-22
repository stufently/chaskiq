# fork-updates-r10e — выбросы RuboCop, шаг 10e: длинные строки спек, литералы — в фикстуры (К3)

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10e.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10e: «LineLength
  в спеках (39) … Подход по К3. Доказательство: пробник — байты фикстуры = значение литерала BASE; полный rspec
  (примеры BASE те же); мутанты не нужны (кода нет), вместо них — порча байта фикстуры ловится пробником»; решение
  координатора по К3 — фикстуры в `spec/fixtures/requests/<provider>/`), план чистки —
  `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10cfg` (та же механика: патч постановщика,
  todo, CHANGELOG, без спек и мутантов). Соседние вехи — `fork-updates-r10c`, `fork-updates-r10cfg` (раздел 10).
- BASE_SHA: `a813c6dd165ccddf8d60af1b09ac2421b28effb7` — HEAD `main` «Record R10c acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Веха ставится ПОСЛЕ
  влития `r10c` и `r10cfg`: постановщик переносит BASE (раздел 2), коммитит новое значение в строку BASE_SHA и
  только потом снимает клон. Команды критериев считают `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от
  BASE_SHA он отличается только `docs/specs`). В `report.json` поле `base_sha` равно значению строки BASE_SHA.
  Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 30 КБ (из них ≈ 20 КБ — 21 файл фикстур).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: в 10 спеках не остаётся `Layout/LineLength` (39 офенсов; их 10 строк уходят из блока todo). Правка задана
  патчем постановщика `r10e_rewrite.patch` (руками не править): 22 длинных литерала полезной нагрузки — в 21 файл
  `spec/fixtures/requests/<provider>/`, остальное — переносы. Ни одной строки кода `app/`/`lib/`, ни одного
  нового или переименованного примера. Работа исполнителя — применить патч, убрать строки todo, записать CHANGELOG,
  прогнать критерии и ревью.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

Чтение исходников `app/`, `lib/`, `config/` как текста в спеках запрещено (`Rails.root.join("app/...").read`,
`File.read` путей кода, `source_location`, парсеры кода, `` `cat`/`grep` `` в шелле). Чтение фикстур
`spec/fixtures/**` — это данные, не исходники, оно разрешено. AC-007 (`source_scan.py`) проверяет новые и
изменённые файлы `spec/`. Литералы BASE разбирает пробник постановщика (Prism), не спеки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10e`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10e-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main` после влития `r10c` и `r10cfg`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10e-ci` (уже сделан при написании спеки).
2. Перенос BASE. Патч перегенерировать не нужно, пока всё ниже сходится:
   - `git apply --check docs/specs/fork-updates-r10e-probes/r10e_rewrite.patch` на новом `main` чист (проверено:
     патч ложится после `r10c_rewrite.patch` и `r10cfg_rewrite.patch` в любом из 6 порядков);
   - строки 10 спек в блоке `Layout/LineLength` todo на месте (иначе AC-002 сам падает со «spec defect»). После
     влития `r10c` в блоке остаются ТОЛЬКО эти 10 строк, и скрипт шага 3 убирает блок целиком, с комментариями —
     это ожидаемо, так считает и AC-002;
   - **перемерить** RuboCop без todo с патчем и без (на копии нового `main`): у 10 спек `Layout/LineLength` ровно
     39 → 0, ни одна пара (коп, файл) не выросла, итог падает ровно на 39 — число `39` в команде AC-004. Сейчас:
     BASE bba1d7ce 211 → 172; BASE + патчи `r10c` + `r10cfg` 120 → 81;
   - фикстурный пробник на копии нового `main` с применённым патчем:
     `bash docs/specs/fork-updates-r10e-probes/r10e_fixture_gate.sh <новый BASE>` → `R10E FIXTURES PASS 22 literals,
     21 fixtures, 10 files` (номера строк `line` в `r10e_config.json` — строки BASE; другая веха, тронувшая эти 10
     спек, их сдвинет — тогда пробник скажет `0 string literals`/`ISEQ … DIFF`, и патч с конфигом надо пересобрать);
   - перегенерировать снимки на чистом checkout `main`:
     `CHASKIQ_R10E_CACHE=$HOME/.cache/chaskiq-r10e-ci bash docs/specs/fork-updates-r10e-probes/rspec_gate_r10e.sh --write-base`
     и пересчитать sha256 в AC-008. Сейчас в снимках — 1394 примера BASE a813c6dd (после r10c+r10cfg); перемер на нём: 120 → 81, фикстурный
     пробник PASS.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Что меняется и почему

Замер — RuboCop без todo на BASE bba1d7ce (Docker, копия кэша `chaskiq-fxb-ci`): 211 офенсов, из них 39
`Layout/LineLength` в 10 спеках. После патча — 172; ни у одного копа ни в одном файле офенсов не прибавилось.

| Спека | Строк | Что с ними |
|---|---|---|
| `spec/services/dante_renderer_spec.rb` | 11 | 11 JSON-строк (ProseMirror и draft.js) → `requests/dante/*.json` |
| `spec/controllers/api/v1/hooks/pipedrive_spec.rb` | 10 | 7 хешей вебхука (`meta`/`current`/`previous`) → JSON; 2 одинаковых ответа `create_person` → один `person_created.json`; 2 комментария (один указывает на фикстуру, другой перенесён) |
| `spec/controllers/api/v1/hooks_controller_spec.rb` | 9 | `"Message"` SNS (5768 символов) → `requests/amazon_ses/received_notification.json`; 8 значений заголовков письма — смежными кусками `"…" \` |
| `spec/controllers/api/v1/hooks/dialog_360_spec.rb` | 3 | два `eq([…])` — массив с новой строки; аргументы `to_return` — на новой строке |
| `message_bird_spec.rb`, `vonage_spec.rb` | 1 + 1 | `eq([…])` — массив с новой строки |
| `twilio_spec.rb` | 1 | аргумент `with(headers: …)` — на новой строке |
| `twitter_spec.rb` | 1 | событие `message_create` → `requests/twitter/message_create_event.json` |
| `spec/models/app_package_spec.rb` | 1 | JSON настроек — смежными кусками `"…" \` |
| `spec/models/campaign_spec.rb` | 1 | `let(:premailer_template) { … }` → `do … end` |

Фикстура читается на месте литерала: `Rails.root.join("spec/fixtures/requests/<provider>/<имя>.json").read`
(строка), `JSON.parse(…)` (хеш); два хеша `update_data_for` содержат `"id" => profile_id` — там
`{ "id" => profile_id }.merge(JSON.parse(…))` (ключ `id` первым, как на BASE). Строковая фикстура — ровно байты
литерала (14 файлов без перевода строки в конце); хешевая — `JSON.pretty_generate` хеша без `id` + `"\n"`.

**Почему поведение то же — пробник `r10e_fixture_probe.rb` (AC-003).** Для каждого из 22 литералов: (1) находит
литерал в BASE-версии спеки (Prism) и вычисляет его значение; (2) байты фикстуры равны значению (строка) или
каноническому JSON хеша; (3) самопроверка — та же проверка на копии фикстуры с перевёрнутым первым, средним,
последним байтом, отрезанным байтом и лишним `"\n"` обязана упасть (5 порч на каждую фикстуру); (4) выражение
`ref` из конфига, вычисленное против дерева, даёт ровно значение BASE (порядок ключей, кодировка и байты строк).
Затем для всех 10 спек: BASE-файл, в котором каждый литерал заменён своим `ref`, компилируется в тот же
YARV-байткод, что файл дерева (без номеров строк). Значит, кроме подстановки фикстур, правка — только раскладка:
смежные куски строки без интерполяции Ruby склеивает при разборе; перенос аргументов, элементов массива,
`{ }` → `do end` у блока `let(:x)` и комментарии байткод не меняют. Подмена фикстуры между примерами, потерянный
пробел на стыке кусков, другой ключ хеша — `ISEQ … DIFF`/`BYTES`/`VALUE` (раздел 7, порченые правки).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10e-ci` — копия
`chaskiq-fxb-ci`) на клонах BASE bba1d7ce:

1. Замер без todo до и после патча (раздел 3): 211 → 172, у 10 спек `Layout/LineLength` 0, роста нет; строгий
   RuboCop с урезанным todo — ноль офенсов.
2. Фикстурный пробник: 22 литерала, 21 фикстура, 10 файлов `ISEQ SAME`; порча байта фикстуры, обмен двух
   фикстур dante между примерами и потерянный пробел в куске заголовка — каждый ловится (раздел 7).
3. Полный сьют на BASE a813c6dd: 1394 примера, 0 failures, 30 pending (снимки `--write-base`); с патчем — те же
   примеры (пробный прогон — на bba1d7ce, 1384).
4. С патчами `r10c` и `r10cfg`: применяются в любом из 6 порядков; без todo 120 → 81 (те же 39, роста нет).
5. Предположение: Rails ставит `Encoding.default_external = UTF-8` (по умолчанию `config.encoding = "utf-8"`),
   поэтому `Pathname#read` фикстуры даёт строку UTF-8, как литерал; пробник проверяет `ref` с той же настройкой,
   полный сьют — в настоящем Rails. Отличие одно: прочитанная строка не заморожена (литерал под
   `frozen_string_literal` заморожен); ни одна из этих строк в спеках не мутируется и не проверяется на `frozen?`.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Спеки и фикстуры — **только** `git apply` патча. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10e-probes
export CHASKIQ_R10E_CACHE=$HOME/.cache/chaskiq-r10e-ci
```

**Шаг 1. Патч.**

```bash
git apply $P/r10e_rewrite.patch
git add spec
git status --short        # ожидается: 10 строк "M  spec/…_spec.rb" и 21 строка "A  spec/fixtures/requests/…"
git commit -qm "Move long spec literals into fixtures"
bash $P/r10e_fixture_gate.sh $(git merge-base HEAD @{u})   # ожидается последней строкой: R10E FIXTURES PASS 22 literals, 21 fixtures, 10 files
```

**Шаг 2. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10e <<'PY'
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
git commit -am "Drop R10e entries from RuboCop todo"
```

**Шаг 3. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10e

- Changed: no spec line is over 140 characters any more (Layout/LineLength outliers of R8a in ten spec
  files, decision K3 of the R10 programme): 22 long request payloads of the Dante renderer, Pipedrive,
  Twitter and Amazon SES specs moved into 21 files under spec/fixtures/requests/<provider>/, read in
  place of the literal; header values, a settings string, expected arrays and call arguments are
  wrapped. Each fixture is byte for byte the old literal and every spec compiles to its old bytecode
  with the fixture read in place of the literal (probe of the milestone); the suite runs the same
  examples. Their 10 entries leave the Layout/LineLength block of the todo.
```

```bash
git commit -am "Note fork-updates-r10e in changelog"
```

**Шаг 4.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строка `R10E FIXTURES PASS …`; AC-004 — строки `backlog without todo: …` и `drop: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 10 спек и 21 фикстуры патча (только патчем), `.rubocop_todo.yml` (только скриптом шага 2),
  `CHANGELOG.md`.
- Любой код (`app/`, `lib/`, `config/`, `db/`), прочие спеки и фикстуры (в том числе `spec/fixtures/requests/idn.txt`
  с CRLF), гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `.rubocop.yml`, `.gitattributes`;
  файлы вех `r10c`, `r10cfg`.
- Прочие блоки todo, в том числе `Metrics/MethodLength` у `dialog_360_spec.rb` и `twitter_spec.rb` (их методы-билдеры
  патч не трогает).
- Никаких `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, новых или переименованных примеров, ручных
  правок фикстур (байт в байт — AC-003), переводов строки в конце строковых фикстур.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены ровно примеры BASE (ни одного пропавшего, ни одного нового), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10E_CACHE=$HOME/.cache/chaskiq-r10e-ci bash docs/specs/fork-updates-r10e-probes/rspec_gate_r10e.sh'`

- **AC-002** — пути: изменены ровно 10 спек патча, добавлена ровно 21 фикстура (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патча побайтно равен BASE с патчем; todo = BASE без 10 строк блока Layout/LineLength (пустой блок уходит целиком); .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10e-probes/r10e_probe.py tree $B'`

- **AC-003** — фикстуры: каждая из 21 побайтно равна значению своего литерала BASE (строка — байты, хеш — канонический JSON); самопроверка — 5 порч каждой фикстуры отвергнуты; каждое выражение-замена даёт ровно значение BASE; каждая из 10 спек = BASE с литералами, заменёнными чтением фикстур, по YARV-байткоду (без номеров строк).
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-r10e-probes/r10e_fixture_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; у Layout/LineLength 0 офенсов в 10 спеках вехи; ни у одного копа ни в одном файле офенсов не больше, чем на BASE; итог упал ровно на измеренные 39.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10E_CACHE=$HOME/.cache/chaskiq-r10e-ci bash docs/specs/fork-updates-r10e-probes/r10e_backlog_probe.sh $B > tmp/r10e-backlog.txt; rc=$?; cat tmp/r10e-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 39)}" tmp/r10e-backlog.txt'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10e-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит патча меняет ровно 10 спек = BASE + патч и добавляет ровно 21 фикстуру; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10e после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10e-probes/r10e_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10e-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "7bd9ef2ac1ca4266448de027694dcb19554b796109f88c49905eb0d95128340e  docs/specs/fork-updates-r10e-probes/examples_base.txt" "a0f0c1ae835336c23a27820b4ad4e2a71307602a2c56e221ac480b3da2c8ad40  docs/specs/fork-updates-r10e-probes/pending_allowed.txt" "99fc22a232c842cff5f29d01c2934c5373a3c43b4835e9cadeae2d632e8154bb  docs/specs/fork-updates-r10e-probes/r10e_backlog_probe.sh" "c71932f9ef34c93d07ed8865a49fcdd0bdc0bdfaced6911ffbdbbe3368ad3fa2  docs/specs/fork-updates-r10e-probes/r10e_config.json" "1a1d5e460439bb54a8acf2ae004596cfebe461b91fed75bf2c856b33ff4b78bc  docs/specs/fork-updates-r10e-probes/r10e_fixture_gate.sh" "fc48e1a5cdc2105dee4bc2ecb77fba50d92f8acaf8abff3e5406d3f88ab19f53  docs/specs/fork-updates-r10e-probes/r10e_fixture_probe.rb" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10e-probes/r10e_probe.py" "6f3520a1abde2923f7e2985524611492fe1d55d38982e3c3f6bcae3df000f13d  docs/specs/fork-updates-r10e-probes/r10e_rewrite.patch" "e80b5a81241e18227273404414209e46208b0a2f21058fb779e00e7fac75c0a9  docs/specs/fork-updates-r10e-probes/r10e_sentinel.rb" "bee00079b10cf634ac02e48c81070509a2039b98fcbc2849ebfb85b73ad27dc6  docs/specs/fork-updates-r10e-probes/rspec_gate_r10e.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10e-probes/source_scan.py" "990f1da8cf3db4c78b3259bf0a02bcea07e034048902ac3d6c48c189316c3ffe  docs/specs/fork-updates-r10e-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10E paths without the
change`, `is not BASE + r10e_rewrite.patch`, `.rubocop_todo.yml is not BASE without the R10E entries`); AC-003
красный (`BYTES … missing`, `VALUE … ref raises Errno::ENOENT`, `ISEQ … DIFF`); AC-004 красный
(`Layout/LineLength: 39 offenses left in the files of this milestone`, `total did not go down`); AC-006 красный
(`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10e-ci`).** Граница: клон от коммита спеки
поверх bba1d7ce (upstream — коммит спеки) — AC-001 (1384 примера, тот же набор), AC-005, AC-007, AC-008, AC-009
rc=0; AC-002, AC-003, AC-004 (`39 offenses left`), AC-006 красные ровно с сообщениями выше. Сборка по разделу 5:
все 9 критериев зелёные (AC-001 — 1384 примера, 0 failures, 30 pending; AC-003 — `R10E FIXTURES PASS 22 literals,
21 fixtures, 10 files`; AC-004 — `backlog without todo: BASE 211, tree 172`, `drop: 39`; AC-007 — 31 файл).
Порченые правки поверх сборки (лишним коммитом): (а) в `amazon_ses/received_notification.json` перевёрнут один
байт посередине — AC-002 (`is not BASE + r10e_rewrite.patch`), AC-003 (`BYTES … first difference at byte 2878`,
`VALUE … ref does not give the BASE value`), AC-006 (`extra commit after the changelog commit`); (б) в
`dante_renderer_spec.rb` обменяны фикстуры `draft_links.json` и `draft_lists.json` между примерами (сьют при этом
зелёный — проверки примеров слабые) — AC-002, AC-003 (`ISEQ spec/services/dante_renderer_spec.rb … DIFF`), AC-006.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10e.md --exclude "docs/specs/fork-updates-r10e-probes/**" --exclude docs/specs/fork-updates-r10c.md --exclude "docs/specs/fork-updates-r10c-probes/**" --exclude docs/specs/fork-updates-r10cfg.md --exclude "docs/specs/fork-updates-r10cfg-probes/**" --context "chaskiq fork-updates-r10e: решение К3 программы R10 — Layout/LineLength 39 выбросов в 10 спеках: 22 длинных литерала полезной нагрузки (dante_renderer_spec JSON ProseMirror/draft.js, хеши вебхука и ответ create_person Pipedrive, событие Twitter, Message SNS/Amazon SES) вынесены в 21 файл spec/fixtures/requests/<provider>/ и читаются Rails.root.join(...).read на месте литерала (хеши — JSON.parse, два с id => profile_id через merge); заголовки письма и JSON настроек AppPackage — смежными кусками строки, eq([...]) и аргументы вызовов — переносы, let { } → do end. Пробник: байты фикстуры = значение литерала BASE (самопроверка порчей байта), спеки = BASE с подстановкой по байткоду; полный rspec — те же примеры; кода app/lib нет; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10e.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10e-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10c.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10c-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg-probes/**

Контекст ревьюеру: фикстура, которая отличается от литерала (лишний перевод строки, другая кодировка, потерянный
ключ хеша, `id` не первым), фикстура, прочитанная не в том примере, перенос, меняющий значение строки (пробел на
стыке кусков), правка вне 10 спек. Спеки и фикстуры править нельзя иначе, чем патчем, — замечание по месту решает
постановщик (раздел 9).

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10e.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10e.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, фикстурный пробник шага 1
  красный — дефект спеки;
- после шагов 1–2 AC-003 или AC-004 красные (офенс остался, вырос в другой паре, разница итогов не 39, `BYTES`,
  `VALUE`, `ISEQ`) — дефект спеки (замер или конфиг устарели); приложи вывод;
- AC-001 красный на примере 10 спек (значение фикстуры ведёт себя иначе, чем литерал) — пример и вывод;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл фикстуру или перенос, меняющие значение, — файл, строка, довод;
- пробник противоречит спеке или BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки спек, фикстур, кода, `.rubocop.yml` и todo, правка пробников и патча, `# rubocop:`
директивы, `pending`/`skip`, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на bba1d7ce (`r10c_rewrite.patch`, `r10cfg_rewrite.patch`, `r10e_rewrite.patch`):

- **Код и спеки.** `r10c` меняет 9 файлов `app/`/`lib/` и добавляет 4 НОВЫЕ спеки (`hooks_controller_wrapped_lines_spec.rb`
  и др.), `r10cfg` — только `.rubocop.yml`; ни одна не трогает 10 спек и `spec/fixtures/` этой вехи. Три патча
  применяются `git apply` в любом из 6 порядков.
- **`.rubocop_todo.yml`.** `r10c` убирает 9 строк `app/`/`lib/` блока `Layout/LineLength`, `r10e` — 10 строк `spec/`
  того же блока: вместе они опустошают блок, и последний скрипт удаляет его с комментариями. Ставим `r10e` после
  `r10c` — конфликта нет (перенос BASE). Блоки `r10cfg` (`MethodLength`/`ClassLength`/`BlockLength`) не пересекаются.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Вместе.** BASE + `r10c` + `r10cfg`: 120 офенсов без todo; + `r10e`: 81 (те же 39, роста нет; `CountAsOne` к
  этим спекам не добавляет и не снимает офенсов).
- **Перенос BASE — раздел 2, п. 2** (`--write-base` с примерами `r10c`, перемер 39, фикстурный пробник, sha256
  AC-008). Патч перегенерировать не нужно, пока `git apply --check` чист и фикстурный пробник зелёный.
- Остаток `Layout/LineLength` после R10a + R10c + R10e — ноль; блок todo исчезает. Дальше — Metrics-вехи программы
  `fork-updates-r10-programme.md`, затем R9 (удалить todo).
