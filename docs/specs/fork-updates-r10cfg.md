# fork-updates-r10cfg — выбросы RuboCop, шаг 10cfg: литералы считаются одной строкой (К1), кода нет

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10cfg.md`, программа — `docs/specs/fork-updates-r10-programme.md` (решение К1, раздел 2:
  «`CountAsOne: [array, hash, heredoc]` для `Metrics/MethodLength`, `Metrics/ClassLength`, `Metrics/BlockLength` …
  исполняет одна маленькая веха R10cfg (строка `.rubocop.yml` с причиной + строки todo; доказательство —
  бэклог-пробник: ни одного нового офенса, ни одного кода)»; решение координатора 2026-11-22 — К1 принято, К5 нет),
  план чистки — `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10a` (та же механика без спек
  и мутантов). Соседние вехи — `fork-updates-r10a`, `fork-updates-r10b`, `fork-updates-r10c` (раздел 10).
- BASE_SHA: `d1c1cd5cbda3e92a5c0175cbdb19d6d14b8081d3` — HEAD `main` «Record R10b acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10a`, `r10b`, `r10c` или другая веха — раздел 10), постановщик переносит BASE
  (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-006).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 5 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все семь критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: в `.rubocop.yml` три копа длины получают `CountAsOne: [array, hash, heredoc]` с причиной (патч постановщика
  `r10cfg_rewrite.patch`, руками не править); из todo уходят ровно те 35 строк, которые настройка снимает
  (`MethodLength` 29 файлов, `ClassLength` 4, `BlockLength` 2). Ни одной строки кода, ни одной спеки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10cfg`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10cfg-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10cfg-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r10cfg_rewrite.patch`; строки 35 файлов в блоках
   `Metrics/MethodLength`, `Metrics/ClassLength`, `Metrics/BlockLength` todo на месте (иначе пробник сам падает со
   «spec defect»); **перемерить** RuboCop без todo с патчем и без: список `cops_partial` в `r10cfg_config.json` —
   ровно пары (коп, файл), у которых офенсы уходят в 0, и число `74` в команде AC-003 — разница итогов (на 16682f02
   и на BASE + r10a + r10b + r10c обе величины те же: 35 пар, 74). Перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R10CFG_CACHE=$HOME/.cache/chaskiq-r10cfg-ci bash docs/specs/fork-updates-r10cfg-probes/rspec_gate_r10cfg.sh --write-base`
   и пересчитать sha256 в AC-006. Сейчас в снимках — 1384 примера BASE d1c1cd5c (после r10a+r10b).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-006 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Что меняется и почему

Замер — RuboCop без todo на BASE 16682f02 (Docker, копия кэша `chaskiq-fxb-ci`): 254 офенса. С патчем — **180**:

| Коп | BASE | с К1 | строк todo уходит |
|---|---|---|---|
| `Metrics/MethodLength` | 82 | 16 | 29 (24 файла `app/`/`lib/` и 5 спек провайдеров `spec/controllers/api/v1/hooks/*`) |
| `Metrics/ClassLength` | 5 | 1 (`app_type.rb`) | 4 (`app.rb`, `app_user.rb`, `segment.rb`, `action_trigger_factory.rb`) |
| `Metrics/BlockLength` | 7 | 3 | 2 (`dialog360/api.rb`, `twitter/api.rb`) |
| остальные копы | 160 | 160 | — |

Ни у одного копа ни в одном файле офенсов не прибавилось. 74 = 52 офенса в 35 парах, которые уходят целиком
(их строки todo удаляются), + 22 в 11 парах, где офенсы уменьшаются, но не до нуля (`slack/api.rb` 6 → 1,
`content_showcase/presenter.rb` 6 → 1, `action_trigger_factory.rb` `MethodLength` 3 → 1 и `BlockLength` 3 → 1 и др.):
их строки todo остаются.

**Почему.** Многострочный литерал хеша/массива/heredoc — декларативные данные: `definition_info` плагинов, схемы
презентеров мессенджера, фикстуры провайдеров в спеках. Длина литерала — не сложность; дробление схемы на
методы-куски ухудшает чтение. Логику по-прежнему держат `AbcSize`, `CyclomaticComplexity`, `PerceivedComplexity`
(их числа не меняются). Многострочные вызовы методов считаются построчно (вариант с `method_call` отклонён:
прячет логику в аргументах). Цена: новый длинный литерал не будет пойман.

**`r10cfg_rewrite.patch`** — только `.rubocop.yml`, +9 строк: `CountAsOne: [array, hash, heredoc]` в трёх копах,
причина — комментарием над `Metrics/MethodLength` (над `BlockLength` — ссылка на неё).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`):

1. Замер без todo до и после патча (раздел 3): 254 → 180, ни одной пары (коп, файл) с ростом.
2. Строгий RuboCop с патчем и урезанным todo — ноль офенсов.
3. Вместе с патчами `r10a`, `r10b`, `r10c`: 194 → 120 (те же 74, те же 35 пар в 0); строгий RuboCop с
   объединённым todo — ноль офенсов (раздел 10).
4. Полный сьют на BASE d1c1cd5c: 1384 примера, 0 failures, 30 pending. Настройка RuboCop
   на rspec не влияет; AC-001 — общий гейт шаблона.
5. Пробный прогон и порченые правки — раздел 7.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Конфиг — **только** `git apply` патча. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10cfg-probes
export CHASKIQ_R10CFG_CACHE=$HOME/.cache/chaskiq-r10cfg-ci
```

**Шаг 1. Настройка.**

```bash
git apply $P/r10cfg_rewrite.patch
git status --short        # ожидается: ровно одна строка " M .rubocop.yml"
git commit -qam "Count literals as one line in Metrics"
```

**Шаг 2. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10cfg <<'PY'
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
git commit -am "Drop R10cfg entries from RuboCop todo"
```

**Шаг 3. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10cfg

- Changed: Metrics/MethodLength, Metrics/ClassLength and Metrics/BlockLength count a multi-line array,
  hash or heredoc literal as one line (`CountAsOne`, decision K1 of the R10 programme): plugin
  definitions, messenger presenter schemas and provider fixtures are data, not complexity. No code
  changes; 74 length outliers disappear and their 35 entries leave the todo.
```

```bash
git commit -am "Note fork-updates-r10cfg in changelog"
```

**Шаг 4.** Все семь критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строки `backlog without todo: …` и `drop: …`; AC-004 — строка `rubocop: …`.

## 6. Не трогать

- Всё, кроме `.rubocop.yml` (только патчем), `.rubocop_todo.yml` (только скриптом шага 2), `CHANGELOG.md`.
- Любой код (`app/`, `lib/`, `config/`, `db/`), любые спеки (`spec/**` — ни новых, ни изменённых), гемы, `Gemfile*`,
  `.ruby-version`, `Dockerfile*`, workflows, `bin/*`; файлы вех `r10a`, `r10b`, `r10c` (раздел 10).
- Прочие блоки todo и строки файлов, у которых офенс остаётся (в том числе 11 пар, где офенсов стало меньше, но не
  ноль — раздел 3).
- Никаких `# rubocop:` директив, `--auto-gen-config`, других ключей `.rubocop.yml` (`Max`, `Exclude`,
  `AllowedMethods` — К5 отклонено).
- `docs/specs/**` — не править (AC-006, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10CFG_CACHE=$HOME/.cache/chaskiq-r10cfg-ci bash docs/specs/fork-updates-r10cfg-probes/rspec_gate_r10cfg.sh'`

- **AC-002** — дерево ровно BASE + настройка + todo: изменены ровно .rubocop.yml, .rubocop_todo.yml и CHANGELOG.md — каждый (ни одного файла кода или спеки); нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; .rubocop.yml побайтно равен BASE с патчем; todo = BASE без 35 строк блоков MethodLength/ClassLength/BlockLength из конфига; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10cfg-probes/r10cfg_probe.py tree $B'`

- **AC-003** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; в 35 парах (коп, файл) конфига 0 офенсов; ни у одного копа ни в одном файле офенсов не больше, чем на BASE; итог упал ровно на измеренные 74.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10CFG_CACHE=$HOME/.cache/chaskiq-r10cfg-ci bash docs/specs/fork-updates-r10cfg-probes/r10cfg_backlog_probe.sh $B > tmp/r10cfg-backlog.txt; rc=$?; cat tmp/r10cfg-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 74)}" tmp/r10cfg-backlog.txt'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, новая настройка, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10cfg-ci bin/ci-local --only rubocop'`

- **AC-005** — каждый коммит отдельно, ровно в порядке раздела 5: коммит настройки меняет только .rubocop.yml = BASE + патч; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10cfg после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10cfg-probes/r10cfg_probe.py commits $B'`

- **AC-006** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "9e691ffba34a62ae2bf060972b2237ef17601c2d0bc8b5ff92512cd7f719ed82  docs/specs/fork-updates-r10cfg-probes/examples_base.txt" "7d37f103fb728f464b2dbc54e5244b4ab383c21c2747d62e33cc67bf76f3fab4  docs/specs/fork-updates-r10cfg-probes/pending_allowed.txt" "b3d67e007abefca07582f38c9d6347351cb88bba93918099bbd80dcfaa58f0f3  docs/specs/fork-updates-r10cfg-probes/r10cfg_backlog_probe.sh" "cf83be3b47d4db9f9547b4e0bc55ca612ad5b7cfc7cf58c31205f125e9515af7  docs/specs/fork-updates-r10cfg-probes/r10cfg_config.json" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10cfg-probes/r10cfg_probe.py" "a05761a78ea2440c48a1fea7e7313c291542552254cde3f59f95ae42955d7b1d  docs/specs/fork-updates-r10cfg-probes/r10cfg_rewrite.patch" "f23cfaaff0011e432307d62111735e2043c87ec1fd14f57490dbfd7b08a0ddb4  docs/specs/fork-updates-r10cfg-probes/r10cfg_sentinel.rb" "1c4ea9bf2fb5cf85914a8180527163eaa4683808b1cf3897de5cc7329b492c1e  docs/specs/fork-updates-r10cfg-probes/rspec_gate_r10cfg.sh" "57734c4f69bb0c93dffb46c790cfb7bc1e98a2cfa95ae6e795d5c77eb2f4af31  docs/specs/fork-updates-r10cfg-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-007** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-004, AC-006, AC-007 зелёные; AC-002 красный (`R10CFG paths without the
change`, `.rubocop_todo.yml is not BASE without the R10CFG entries`); AC-003 красный
(`Metrics/BlockLength: 2 …`, `Metrics/ClassLength: 4 …`, `Metrics/MethodLength: 46 offenses left in the files of
this milestone`, `total did not go down`); AC-005
красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, копия кэша `chaskiq-fxb-ci`).** Граница: клон `make_clone.sh` от
коммита спеки поверх 0165d570 — AC-001 (1285 примеров, 421 с), AC-004, AC-006, AC-007 rc=0; AC-002, AC-003, AC-005
красные ровно с сообщениями выше. Сборка по разделу 5: все 7 критериев зелёные (AC-003 — `backlog without todo:
BASE 254, tree 180`, `drop: 74`). Порченые правки: (а) лишний коммит с правкой кода (комментарий в строке `def` в
`app_type.rb`) — AC-002 (`changed, but not an R10CFG path`), AC-004 (новый офенс), AC-005 (`extra commit after the
changelog commit`); (б) в коммите todo убрана посторонняя строка (`lib/tasks/utils.rake` блока `Layout/LineLength`)
— AC-002 (todo не равен ожидаемому), AC-004 (офенс вернулся), AC-005.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10cfg.md --exclude "docs/specs/fork-updates-r10cfg-probes/**" --exclude docs/specs/fork-updates-r10c.md --exclude "docs/specs/fork-updates-r10c-probes/**" --exclude docs/specs/fork-updates-r10a.md --exclude "docs/specs/fork-updates-r10a-probes/**" --exclude docs/specs/fork-updates-r10b.md --exclude "docs/specs/fork-updates-r10b-probes/**" --context "chaskiq fork-updates-r10cfg: решение К1 программы R10 — в .rubocop.yml CountAsOne: [array, hash, heredoc] для Metrics/MethodLength, ClassLength, BlockLength с причиной (литералы — данные, не сложность; вызовы методов по-прежнему построчно); из .rubocop_todo.yml уходят ровно 35 строк, у которых офенсы уходят в 0 (MethodLength 29, ClassLength 4, BlockLength 2); бэклог без todo 254 -> 180, ни одного нового офенса; кода и спек нет; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10cfg-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10c.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10c-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b-probes/**

Контекст ревьюеру: удалённая строка todo, у которой офенс остался (AC-004 её поймал бы), оставленная строка, у
которой офенса нет, ключ не в том копе, причина в комментарии, которая расходится с настройкой. Конфиг и todo
править нельзя иначе, чем шагами раздела 5 — замечание по месту решает постановщик (раздел 9).

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 7 критериев зелёные. Если agy упал или не дал
вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 7: AC-001…AC-007. `blocked` у критерия —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10cfg.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10cfg.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все семь критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` — дефект спеки;
- после шагов 1–2 AC-003 или AC-004 красные (офенс остался в паре конфига, вырос в другой паре, разница итогов не
  74) — дефект спеки (замер устарел); приложи вывод;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл строку todo, которую нельзя убирать или которую надо убрать, — коп, файл, довод;
- пробник противоречит спеке или BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: правки кода и спек, ручные правки `.rubocop.yml` и todo, правка пробников и патча, `# rubocop:`
директивы, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на 16682f02 (`r10a_rewrite.patch`, `r10b_rewrite.patch`, `r10c_rewrite.patch`, `r10cfg_rewrite.patch`):

- **`.rubocop.yml`** меняет только эта веха. Все четыре патча применяются `git apply` в любом из 24 порядков.
- **`.rubocop_todo.yml`.** r10cfg убирает строки блоков `MethodLength`/`ClassLength`/`BlockLength` (строки BASE
  96–176); r10a и r10c — строки `Layout/LineLength` (11–45), r10b — `AbcSize`/`Cyclomatic`/`Perceived` (61–119,
  182–191). Ни один блок не пустеет. Git сливает todo r10cfg с каждой из трёх чисто (проверено слиянием веток);
  итог равен последовательному прогону скриптов, результат во всех 24 порядках четырёх скриптов один. Каждый
  скрипт todo добавляет перевод строки в конце файла (на BASE его нет) — изменение одинаковое у всех, слиянию не
  мешает, но отдельные дифы todo друг на друга `git apply` не ложатся (общий хвостовой хунк).
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog` — конфликт при любой паре, решается
  вставкой обоих блоков.
- **Код других вех под К1.** BASE + r10a + r10b + r10c: 194 офенса без todo; с r10cfg — 120: те же 74, те же 35
  пар в 0, роста нет; строгий RuboCop с объединённым todo чист. Переносы r10a/r10c внутри литералов под К1 не
  удлиняют методы.
- **Кто вливается вторым, тому — перенос BASE** (раздел 2, п. 2: перемерить пары и 74, `--write-base`, sha256
  AC-006). Патч перегенерировать не нужно, пока `git apply --check` чист.
- С К1 снимаются вехи R10d, R10f, R10j программы; в R10h, R10k–R10u уходит часть офенсов (колонка «CA1»).
