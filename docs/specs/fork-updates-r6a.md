# fork-updates-r6a — бэклог RuboCop, шаг 6a: `Lint/UselessAssignment` в `app/` и `lib/` автокорректом

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r6a.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — первая часть R6 оттуда, раздел 10).
- BASE_SHA: `cef8ca777d95ad063f1f2a3b310a8ca1f5b73809` — HEAD `main` с влитыми R1–R5, R7a
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (раздел 2). Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 52 КБ
  (64 файла, плюс 64 строки todo) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- **`spec/` веха не трогает** (параллельно идёт mut-m9-m14, он добавляет файлы в `spec/`).
- Цель: в 64 файлах `app/` и `lib/` из секции `Lint/UselessAssignment` todo RuboCop сам убирает
  присваивания в переменные, которые нигде не читаются (119 мест: `x = foo` → `foo`, правая часть и
  её побочные эффекты остаются; `rescue => e` без `e` → `rescue`; `a, b = …` → `a, _ = …`), затем
  сам выравнивает отступы. Эти 64 строки уходят из todo; в секции остаются 12 файлов `spec/` и 11
  файлов `keep`. Ничего, кроме вывода двух команд RuboCop, в коде не меняется — это проверяется
  повтором тех же команд на BASE (AC-002, AC-006).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r6a`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r6a-ci`.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r6a-ci` — копия `chaskiq-r5-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5-ci $HOME/.cache/chaskiq-r6a-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; прогнать раздел 5 на черновике
   (`r6a_config.json` `files`/`keep` и `r6a_removals.txt` пересчитать, если менялись эти файлы
   или todo); если менялся `spec/` — перегенерировать список примеров:
   `CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci bash docs/specs/fork-updates-r6a-probes/rspec_gate_r6a.sh --write-base`
   на чистом checkout `main`. Сейчас в снимках — список примеров `main` cef8ca77.
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Задача и почему

`Lint/UselessAssignment` в todo BASE — 87 файлов: 75 в `app/`+`lib/`, 12 в `spec/`. Автокоррект
RuboCop (безопасный, `-a`) удаляет только запись в переменную; выражение справа остаётся, поэтому
вызовы с эффектом (`@app.conversations.find(id)` — 404 при чужом id) сохраняются, а значение
выражения как результат метода/блока — тоже. Опасные случаи — где локальная переменная читается не
кодом, а динамически: `binding` (ERB-шаблон), `eval` по строке, `local_variables`. Такие файлы — в
`keep`, и AC-002 проверяет, что в 64 файлах таких конструкций нет.

`keep` (11 файлов остаются в todo, причины — в `r6a_config.json`):
- `app/services/message_apis/calendly/presenter.rb`, `app/services/message_apis/twilio_phone/presenter.rb`
  — `template.result(binding)`: «бесполезная» переменная может читаться шаблоном;
- `app/models/audit.rb` — у офенса (`@app = app ||= …`) нет автокоррекции, правка руками — R5b;
- `app/jobs/app_user_event_job.rb`, `app/mailers/campaign_mailer.rb`, `app/models/campaign.rb`,
  `app/services/message_apis/open_ai/presenter.rb`, `app/services/message_apis/pipedrive/api.rb`,
  `app/services/message_apis/slack/api.rb`, `app/services/message_apis/message_bird/api.rb`,
  `app/services/message_apis/telegram/api.rb` — после автокоррекции остаётся литерал/оператор/переменная без
  использования (новый `Lint/Void`): там стоит посмотреть, не потерян ли смысл (R5b вместе с
  `Lint/Void`).

Шаг Layout нужен потому, что удаление `x = ` сдвигает многострочные выражения
(`Layout/MultilineMethodCallIndentation`, `CaseIndentation`, `ElseAlignment`, `EndAlignment`,
`ExtraSpacing`, `IndentationWidth`); `Style/RedundantBegin` (один `begin` стал лишним) и
`Style/TrailingUnderscoreVariable` (`a, _ = x` → `a, = x`) — тоже безопасные автокоррекции.

Список всех 119 удалённых присваиваний — `docs/specs/fork-updates-r6a-probes/r6a_removals.txt`
(файл:строка, переменная) для ревью. Подозрительные на баг, но поведение не меняющие (значение и
раньше не использовалось): `hooks_controller.rb:273` (`message = image_mark.dup << message` — новое
значение не возвращалось вызывающему), `hooks_controller.rb:108` (`messageId`),
`dialog360/presenter.rb:112` (`offset`). Они остаются как есть по поведению; разбор — R5b.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r6a-ci`) на
клоне BASE cef8ca77:

1. Шаг 2 раздела 5: 119 исправлений в 64 файлах; шаг 3 выравнивает; после этого `rubocop` по
   64 файлам — 0 офенсов, дифф кода ≈ 52 КБ (66 файлов вместе с todo и CHANGELOG, +204/−264). Без `message_bird/api.rb` и `telegram/api.rb` (первый
   черновик с ними дал рост `Lint/Void` — AC-004 красный; они ушли в `keep`).
2. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: анализ переменных RuboCop (`VariableForce`) верен для кода без `binding`/`eval`/
`local_variables` — запись в переменную, которую никто не читает, ненаблюдаема. Это подкреплено
полным rspec (AC-001), но тестами покрыты не все 119 мест.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Перед шагом 1 один раз задай переменные:

```bash
P=docs/specs/fork-updates-r6a-probes
export CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci
RUBOCOP_IN_DOCKER() { docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true -v "$PWD:/app" -v "$CHASKIQ_R6A_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04 bash -c "bundle install --quiet; mapfile -t f < <(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))[\"files\"]' $P/r6a_config.json); bundle exec rubocop --cache false -a --only $1 \"\${f[@]}\""; }
```

**Шаг 1.** Убрать 64 файла из секции todo:

```bash
python3 -I - <<'EOF'
import json, re
files = set(json.load(open("docs/specs/fork-updates-r6a-probes/r6a_config.json"))["files"])
text = open(".rubocop_todo.yml").read()
head, *blocks = text.rstrip("\n").split("\n\n")
out = []
for b in blocks:
    if re.search(r"(?m)^Lint/UselessAssignment:$", b):
        b = "\n".join(l for l in b.split("\n") if not (l.startswith("    - '") and l[7:].rstrip("'") in files))
    out.append(b)
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: 1 file changed, 64 deletions(-)
git commit -am "Drop R6a files from UselessAssignment todo"
```

**Шаг 2.** Автокоррект копа:

```bash
RUBOCOP_IN_DOCKER Lint/UselessAssignment
git diff --stat | tail -1  # ожидается: 64 files changed
git commit -am "Autocorrect Lint/UselessAssignment"
```

**Шаг 3.** Выравнивание после него:

```bash
RUBOCOP_IN_DOCKER Layout,Style/RedundantBegin,Style/TrailingUnderscoreVariable
git commit -am "Fix layout after UselessAssignment"
```

**Шаг 4.** Запись в CHANGELOG: вставь сразу после первой строки `# Changelog` файла `CHANGELOG.md`
этот блок (с пустой строкой до и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r6a

- Changed: Lint/UselessAssignment autocorrected in 64 files of app/ and lib/ (119 unused local
  assignments removed, right-hand sides kept), layout re-aligned; eleven files stay in the todo.
```

```bash
git commit -am "Note fork-updates-r6a in changelog"
```

**Шаг 5.** Прогнать все восемь критериев раздела 7 (каждая команда — как написана). Если какой-то
красный — читай вывод, сверяйся с разделом 9. Ручная правка Ruby-файлов запрещена; если шаг 2 или 3
дал не то — `git reset --hard <коммит шага 1>` и повтори шаги 2–4 командами выше.

**Шаг 6.** Ревью и `report.json` — раздел 8. В `report.json`: `note` AC-002 — строка `files: …`;
AC-004 — строка `backlog without todo: …`.

## 6. Не трогать

- Всё, кроме `.rubocop_todo.yml`, `CHANGELOG.md` и 64 файлов из `r6a_config.json` `files`.
  **`spec/` не трогать.** Файлы `keep` не трогать.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`,
  `config/`.
- Никаких ручных правок Ruby, `# rubocop:` директив, `--auto-gen-config`, `-A` (только `-a`).
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci bash docs/specs/fork-updates-r6a-probes/rspec_gate_r6a.sh'`

- **AC-002** — дерево: files/keep совпадают со списком копа в app/ и lib/ на BASE; изменены ровно todo, CHANGELOG и все 64 файла, обычные файлы с прежним git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; todo = BASE без 64 строк копа; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы; в 64 файлах нет binding, eval по строке, *_eval по строке, local_variables, ERB; каждый из 64 файлов побайтно равен повтору шагов 2 и 3 на версии BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci python3 -I docs/specs/fork-updates-r6a-probes/r6a_probe.py tree $B'`

- **AC-003** — каждый коммит отдельно, ровно в порядке раздела 5: коммит todo — только todo, равный ожидаемому; коммит автокорректа — ровно 64 файла, каждый = повтор шага 2 на родителе; коммит выравнивания — ровно те файлы, что меняет повтор шага 3 на родителе, каждый равен ему; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r6a после «# Changelog»; ни один коммит не меняет git-режим, не добавляет/удаляет путь, не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci python3 -I docs/specs/fork-updates-r6a-probes/r6a_probe.py commits $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Lint/UselessAssignment 0 офенсов вне spec/ и keep; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6A_CACHE=$HOME/.cache/chaskiq-r6a-ci bash docs/specs/fork-updates-r6a-probes/r6a_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r6a-ci bin/ci-local --only rubocop'`

- **AC-006** — git-статус веток: ровно четыре коммита раздела 5 (или больше — только CHANGELOG), все — потомки BASE без merge.
  `bash -c 'B=$(git merge-base HEAD @{u}) && test "$(git rev-list --merges $B..HEAD | wc -l)" = 0 && test "$(git rev-list --count $B..HEAD)" -ge 4'`

- **AC-007** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "f39e64c2eb5a89528bc6fd16dab3a91bfe2a56f587c36cd55e0065fa2bd543e3  docs/specs/fork-updates-r6a-probes/r6a_probe.py" "37dfea4003ea2e8377a884ba82b973d09e4dd0e4794b54c4adbe530c29128ac8  docs/specs/fork-updates-r6a-probes/r6a_config.json" "d297871ca1457e42b96ff4a9bca423ce201e26cc03a56b76a577f683719f6d2b  docs/specs/fork-updates-r6a-probes/r6a_backlog_probe.sh" "68b2e784b4781b1e703fcd5dbc231de5c07063b709f5d6a76ee26caceba32779  docs/specs/fork-updates-r6a-probes/r6a_removals.txt" "96326769f0bb1289ef6917356f275cb3195ca67479ccfa320cc6dc440d024676  docs/specs/fork-updates-r6a-probes/rspec_gate_r6a.sh" "cb15028b74d6642f031105649d048df854b6ea0c4530802893fae0fbc591e11b  docs/specs/fork-updates-r6a-probes/r6a_sentinel.rb" "b438830e81c10d4b35e0095f343b9e11ade9bb26e46dd829c3474acf09b1a6b9  docs/specs/fork-updates-r6a-probes/examples_base.txt" "4b5ec632f43df67904d82736c78e3ac65ee5e4b65366684fadbbbb33b528c68f  docs/specs/fork-updates-r6a-probes/pending_allowed.txt" "0a2ddcd0094d26569d0c95dcc5d0236304708a5669449beaf20c793853ff8874  docs/specs/fork-updates-r6a-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008 зелёные; AC-002 красный (`R6a paths without
the change`); AC-003 красный (`missing commits`); AC-004 красный (`… offenses left`); AC-006 красный.

Проверено на черновике, собранном командами раздела 5 дословно (свежий клон с закоммиченными
спекой и пробниками): AC-001…AC-008 зелёные — rspec 700/0/30, сторож 672; AC-002 — `files: 64
(keep 11), 64 equal to the replay`; AC-003 — коммит выравнивания меняет 11 файлов; AC-004 — без todo
BASE 1576 → дерево 1453. Плохие правки (каждая → FAIL названного критерия):
- AC-002 и AC-003: лишняя ручная строка в одном из 64 файлов — «not the replay…» / «extra commit
  after the changelog commit».
- AC-002: правка `keep`-файла (`calendly/presenter.rb`) — «not an R6a path»; один из 64 файлов
  возвращён к BASE — «R6a paths without the change»; из todo выпала строка `keep` (`audit.rb`) —
  «.rubocop_todo.yml is not BASE with the 64 files removed».
- AC-003: шаги 2 и 3 слиты в один коммит — «is not the replay of step 1 on the parent».

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r6a.md --exclude "docs/specs/fork-updates-r6a-probes/**" --context "chaskiq fork-updates-r6a: rubocop -a Lint/UselessAssignment в 64 файлах app/ lib/ (x = foo -> foo, rescue => e -> rescue) + Layout/RedundantBegin/TrailingUnderscoreVariable; 11 файлов keep; риск — переменная, которую читает binding/eval; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r6a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r6a-probes/**

Контекст ревьюерам: искать удалённое присваивание, значение которого всё-таки нужно (читается
позже под другим именем, через `binding`/`send`/`instance_variable_get`, возвращается из метода
иначе, чем раньше) и правки сверх вывода RuboCop. Исправлять в коде нельзя — замечание по месту
отправляет файл в `keep`, решает постановщик (раздел 9).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r6a.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r6a.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- шаг 2 меняет не 64 файла, или после шага 3 AC-005 красный, или AC-004 показывает рост другого
  копа — приложи вывод; это дефект спеки;
- AC-002/AC-003 говорят «not the replay» после повтора шагов 2–4 с `git reset --hard` — приложи вывод;
- сьют красный (AC-001) — приложи вывод; если причина в удалённом присваивании — файл, строка;
- ревьюер нашёл место, где значение нужно, — файл, строка, довод ревьюера;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов, перегенерация `.rubocop_todo.yml`, правка пробников,
удалять/skip-ать тесты, глушить вывод и коды возврата.

## 10. Стыки

- R6b: `Lint/UnusedMethodArgument` (165 офенсов; сигнатуры API плагинов — решение владельца, план
  R6) и `Lint/UselessAssignment` в `spec/` (22 места в 12 файлах) — после mut-m9-m14.
- R5b: 11 файлов `keep` (ERB, `audit.rb`, новые `Lint/Void`) и три места-кандидата на баг из раздела 3.
