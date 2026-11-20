# fork-updates-r6b — бэклог RuboCop, шаг 6b: `Lint/UnusedMethodArgument` — `_` позиционным, keyword разрешены

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r6b.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — R6b оттуда; решение владельца — в блоке
  «Решения владельца» плана).
- BASE_SHA: `21c1f7018a4138d51de46519d79257331c9613d0` — HEAD `main` с влитыми R1–R5, R6a, R7a
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (раздел 2). Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 10 КБ
  (28 файлов по 1–3 строки, `.rubocop.yml`, todo) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- **`spec/` веха не трогает** (параллельно идёт mut-m9-m14, он добавляет файлы в `spec/`).
- Цель (решение владельца 2026-11-20): в `.rubocop.yml` — `Lint/UnusedMethodArgument:
  AllowUnusedKeywordArguments: true` с записанной причиной (имена keyword-аргументов — часть
  интерфейса плагинов и интеграций); неиспользуемые позиционные аргументы в 28 файлах `app/`+`lib/`
  RuboCop переименовывает в `_имя` (45 мест; вызывающий код не меняется — позиционные передаются по
  месту). Секция копа в todo сокращается до двух файлов `keep`. Ничего, кроме вывода команды RuboCop
  и двух заданных текстов конфигов, не меняется — это проверяется повтором команды на BASE и
  статической проверкой каждого переименования (AC-002, AC-003).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r6b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r6b-ci`.

**Порядок с R6a.** Спека написана от HEAD `main` 648533e9 (R6a ещё не влита) и перенесена на
21c1f701 после мержа R6a: обе вехи правят `.rubocop_todo.yml` (разные секции) и часть одних файлов
`app/`. После переноса `files` (28) и `todo_only` (26) не изменились, `spec/` не менялся — снимки
списка примеров (сняты на cef8ca77, `spec/` с тех пор тот же) остались.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r6b-ci` — копия `chaskiq-r6a-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r6a-ci $HOME/.cache/chaskiq-r6b-ci`.
2. Перенос BASE (после R6a — обязательно): новое значение BASE_SHA; на черновике по разделу 5
   пересчитать `r6b_config.json` (`files` — файлы, которые меняет шаг 3; `todo_only` — остальные
   строки секции, кроме `keep`; проверка — `r6b_probe.py tree` зелёный), прогнать все критерии
   раздела 7; если менялся `spec/` — перегенерировать список примеров:
   `CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci bash docs/specs/fork-updates-r6b-probes/rspec_gate_r6b.sh --write-base`
   на чистом checkout `main`. Числа в разделах 1, 4, 7 обновить.
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Задача и почему

На BASE `Lint/UnusedMethodArgument` в todo — 56 файлов (45 в `app/`+`lib/`, 11 в `spec/`). С
`AllowUnusedKeywordArguments: true` keyword-офенсы исчезают (вместе с ними — все 11 файлов `spec/`
и 15 файлов `app/`+`lib/`: у них были только keyword); остаются 48 позиционных в 30 файлах.
Автокоррект (безопасный, `-a`) переименовывает аргумент `x` в `_x` в сигнатуре: `def
delete_integration(id)` → `def delete_integration(_id)`. Позиционный аргумент передаётся по месту,
поэтому вызывающий код не меняется.

Где переименование может изменить поведение — всё это проверяет `r6b_guard.rb` для каждого
переименования (AC-002, AC-003), а файлы с такими местами — в `keep`:
- метод читает аргумент динамически: `binding` (ERB-шаблон с `result(binding)`), `eval`/`*_eval`/
  `*_exec` по строке, `local_variables`;
- `super` без аргументов (zsuper передаёт текущие значения параметров, а для keyword — и имена);
- самоанализ сигнатуры: `method(...)`, `__method__`, `.parameters`;
- имя `_x` уже занято в методе, или `x`/`_x` где-то в теле используется.

`keep` (2 файла остаются в todo): `app/services/message_apis/calendly/presenter.rb`,
`app/services/message_apis/twilio_phone/presenter.rb` — оба вычисляют ERB с `result(binding)`.
В 28 файлах `files` таких мест нет (проверено guard'ом на BASE и в дереве).

`todo_only` (26 строк секции уходят без правки кода — только keyword-офенсы, теперь разрешённые) —
список в `r6b_config.json`.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r6b-ci`) на
клоне BASE 648533e9, повторно — на 21c1f701 (после R6a), числа пп. 1–3 те же:

1. С настройкой владельца — 48 офенсов копа, все позиционные, все в `app/`+`lib/` (0 в `spec/`).
2. Шаг 3: 45 исправлений в 28 файлах (3 — в двух файлах `keep`); после шагов 1–3 строгий
   `rubocop` по всему дереву — 0 офенсов, Layout после переименования не нужен.
3. `r6b_guard.rb`: самопроверка (zsuper, `binding`, `local_variables`, `method(__method__).parameters`,
   переименование keyword, занятое `_x`, переименованный метод) — все ловятся; на 28 файлах —
   `R6B GUARD PASS 28 files, 45 renames`.
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: внешний код (плагины из appstore) вызывает эти методы позиционно, а не через
`method(:x).parameters`/keyword с тем же именем; в репозитории так и есть (`.parameters` и
`local_variables` в `app/`+`lib/` не встречаются).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Перед шагом 1 один раз задай переменные (`mkdir -p vendor/bundle` —
чтобы точку монтирования создал твой пользователь, а не Docker от root):

```bash
P=docs/specs/fork-updates-r6b-probes
export CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci
RUBOCOP_IN_DOCKER() { mkdir -p vendor/bundle && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true -v "$PWD:/app" -v "$CHASKIQ_R6B_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04 bash -c "bundle install --quiet; mapfile -t f < <(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))[\"files\"]' $P/r6b_config.json); bundle exec rubocop --cache false -a --only $1 \"\${f[@]}\""; }
```

**Шаг 1.** Настройка владельца в `.rubocop.yml` (текст — из `r6b_config.json`, вставляется сразу после
блока `Naming/MethodParameterName`):

```bash
python3 -I - <<'EOF'
import json
c = json.load(open("docs/specs/fork-updates-r6b-probes/r6b_config.json"))
text = open(".rubocop.yml").read()
assert text.count(c["rubocop_yml_anchor"]) == 1, "anchor not found once - stop, section 9"
open(".rubocop.yml", "w").write(text.replace(c["rubocop_yml_anchor"], c["rubocop_yml_anchor"] + c["rubocop_yml_insert"]))
EOF
git diff --stat            # ожидается: 1 file changed, 5 insertions(+)
git commit -am "Allow unused keyword arguments"
```

**Шаг 2.** Секцию копа в todo сократить до двух файлов `keep`:

```bash
python3 -I - <<'EOF'
import json, re
keep = set(json.load(open("docs/specs/fork-updates-r6b-probes/r6b_config.json"))["keep"])
text = open(".rubocop_todo.yml").read()
head, *blocks = text.rstrip("\n").split("\n\n")
out = []
for b in blocks:
    if re.search(r"(?m)^Lint/UnusedMethodArgument:$", b):
        b = "\n".join(l for l in b.split("\n") if not (l.startswith("    - '") and l[7:].rstrip("'") not in keep))
    out.append(b)
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: 1 file changed, 54 deletions(-)
git commit -am "Drop R6b files from UnusedMethodArgument todo"
```

**Шаг 3.** Автокоррект копа:

```bash
RUBOCOP_IN_DOCKER Lint/UnusedMethodArgument
git diff --stat | tail -1  # ожидается: 28 files changed, 45 insertions(+), 45 deletions(-)
git commit -am "Autocorrect Lint/UnusedMethodArgument"
```

**Шаг 4.** Запись в CHANGELOG: вставь сразу после первой строки `# Changelog` файла `CHANGELOG.md`
этот блок (с пустой строкой до и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r6b

- Changed: Lint/UnusedMethodArgument allows unused keyword arguments (plugin interface, owner
  decision); unused positional arguments renamed to `_name` in 28 files of app/ and lib/ (45 places,
  RuboCop autocorrect); two ERB presenters stay in the todo.
```

```bash
git commit -am "Note fork-updates-r6b in changelog"
```

**Шаг 5.** Прогнать все восемь критериев раздела 7 (каждая команда — как написана). Если какой-то
красный — читай вывод, сверяйся с разделом 9. Ручная правка Ruby-файлов запрещена; если шаг 3 дал не
то — `git reset --hard <коммит шага 2>` и повтори шаги 3–4 командами выше.

**Шаг 6.** Ревью и `report.json` — раздел 8. В `report.json`: `note` AC-002 — строка `files: …`;
AC-004 — строка `backlog without todo: …`.

## 6. Не трогать

- Всё, кроме `.rubocop.yml` (только блок шага 1), `.rubocop_todo.yml`, `CHANGELOG.md` и 28 файлов из
  `r6b_config.json` `files`. **`spec/` не трогать.** Файлы `keep` и `todo_only` не трогать.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`.
- Никаких ручных правок Ruby, `# rubocop:` директив, `--auto-gen-config`, `-A` (только `-a`),
  переименования keyword-аргументов.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci bash docs/specs/fork-updates-r6b-probes/rspec_gate_r6b.sh'`

- **AC-002** — дерево: files/keep/todo_only совпадают со списком копа на BASE; изменены ровно .rubocop.yml, todo, CHANGELOG и все 28 файлов, обычные файлы с прежним git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; .rubocop.yml = BASE с блоком владельца, todo = BASE с секцией копа, сокращённой до keep; ни одной добавленной rubocop-директивы; каждый из 28 файлов побайтно равен повтору шага 3 на версии BASE; guard: только позиционные x -> _x, в теле метода нет x/_x, zsuper, binding, eval/*_eval/*_exec, local_variables, __method__, method(...), .parameters, в файле нет ERB/binding.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci python3 -I docs/specs/fork-updates-r6b-probes/r6b_probe.py tree $B'`

- **AC-003** — каждый коммит отдельно, ровно в порядке раздела 5: коммит настройки — только .rubocop.yml, равный ожидаемому; коммит todo — только todo, равный ожидаемому; коммит автокорректа — ровно 28 файлов, каждый = повтор шага 3 на родителе, guard проходит родитель → коммит; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r6b после «# Changelog»; ни один коммит не меняет git-режим, не добавляет/удаляет путь, не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci python3 -I docs/specs/fork-updates-r6b-probes/r6b_probe.py commits $B'`

- **AC-004** — бэклог без todo (каждая сторона со своим .rubocop.yml): RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Lint/UnusedMethodArgument 0 офенсов вне keep; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6B_CACHE=$HOME/.cache/chaskiq-r6b-ci bash docs/specs/fork-updates-r6b-probes/r6b_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r6b-ci bin/ci-local --only rubocop'`

- **AC-006** — история ветки: не меньше четырёх коммитов от BASE, ни одного merge.
  `bash -c 'B=$(git merge-base HEAD @{u}) && test "$(git rev-list --merges $B..HEAD | wc -l)" = 0 && test "$(git rev-list --count $B..HEAD)" -ge 4'`

- **AC-007** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "8c0bb6a09dbfa6fab219103a322d8c30d5c125261565708a51ec46afe7aa384e  docs/specs/fork-updates-r6b-probes/r6b_probe.py" "ed4ad9bb7e3f40756b03b81a969161efef2cce36f48f9f485e2f64334a247cbf  docs/specs/fork-updates-r6b-probes/r6b_config.json" "725d6a4d795091275566307d805e79fa138bc7112f162e5c817f27fb726aa6fc  docs/specs/fork-updates-r6b-probes/r6b_guard.rb" "4ec92e505ac7227f7207ee71269ec341d9b55689e9d5001bff2e7db55967a283  docs/specs/fork-updates-r6b-probes/r6b_backlog_probe.sh" "20f0d63af35f43a2904f77818ccce5f82bf50571e0052ea2d4fe74f2b7055dc3  docs/specs/fork-updates-r6b-probes/rspec_gate_r6b.sh" "540b90a6850de5a94fb3d7355dda618e420405d2689095964d76c26e9124ee34  docs/specs/fork-updates-r6b-probes/r6b_sentinel.rb" "b438830e81c10d4b35e0095f343b9e11ade9bb26e46dd829c3474acf09b1a6b9  docs/specs/fork-updates-r6b-probes/examples_base.txt" "4b5ec632f43df67904d82736c78e3ac65ee5e4b65366684fadbbbb33b528c68f  docs/specs/fork-updates-r6b-probes/pending_allowed.txt" "0a2ddcd0094d26569d0c95dcc5d0236304708a5669449beaf20c793853ff8874  docs/specs/fork-updates-r6b-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008 зелёные; AC-002 красный (`R6b paths without
the change`); AC-003 красный (`missing commits`); AC-004 красный (`… offenses left`); AC-006 красный.

Проверено на черновике, собранном командами раздела 5 дословно (свежий клон с закоммиченными
спекой и пробниками, BASE 21c1f701): AC-001…AC-008 зелёные — rspec 700/0/30, сторож 672; AC-002 —
`files: 28 (keep 2, todo only 26), 28 equal to the replay; R6B GUARD PASS 28 files, 45 renames`;
AC-004 — без todo BASE 1453 → дерево 1291 (keyword-офенсы ушли настройкой). Плохие правки (каждая →
FAIL названного критерия):
- AC-002: переименованный keyword-аргумент (`create_quick_reply.rb`) — «not an R6b path»; `super`
  без аргументов в методе с переименованным аргументом — «guard: … zsuper» и «not the replay»;
  из блока `.rubocop.yml` выпала строка причины — «.rubocop.yml is not BASE with the owner's … block»
  (AC-003 — «extra commit»); переименование в `keep`-презентере — «not an R6b path».
- AC-003: настройка и todo в одном коммите — «only .rubocop.yml allowed», порядок коммитов сбит.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r6b.md --exclude "docs/specs/fork-updates-r6b-probes/**" --context "chaskiq fork-updates-r6b: решение владельца — Lint/UnusedMethodArgument AllowUnusedKeywordArguments: true в .rubocop.yml с причиной; rubocop -a переименовал неиспользуемые позиционные аргументы x -> _x в 28 файлах app/ lib/ (45 мест); риск — метод, который читает аргумент через binding/eval/super без аргументов/самоанализ; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r6b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r6b-probes/**

Контекст ревьюерам: искать переименованный аргумент, который всё-таки нужен (переопределение
метода, чей родитель зовётся через `super`; вызов по имени аргумента; DSL, читающий сигнатуру), и
правки сверх вывода RuboCop. Исправлять в коде нельзя — замечание по месту отправляет файл в `keep`,
решает постановщик (раздел 9).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r6b.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r6b.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- шаг 1 не находит якорь, шаг 3 меняет не 28 файлов, или после шага 3 AC-005 красный, или AC-004
  показывает рост другого копа — приложи вывод; это дефект спеки;
- AC-002/AC-003 говорят «not the replay» или «guard: …» после повтора шагов 3–4 с `git reset --hard` —
  приложи вывод;
- сьют красный (AC-001) — приложи вывод; если причина в переименованном аргументе — файл, метод;
- ревьюер нашёл место, где аргумент нужен, — файл, метод, довод ревьюера;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов, другие правки `.rubocop.yml`, перегенерация
`.rubocop_todo.yml`, правка пробников, удалять/skip-ать тесты, глушить вывод и коды возврата.

## 10. Стыки

- R6a (`Lint/UselessAssignment`, идёт сейчас) — до R6b; после её мержа BASE переносится (раздел 2).
- R6c: `Lint/UselessAssignment` в `spec/` (22 места, 12 файлов) — после mut-m9-m14.
- R5b: два файла `keep` (ERB-презентеры) вместе с остальными местами `binding`.
