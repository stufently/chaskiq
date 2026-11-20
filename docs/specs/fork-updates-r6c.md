# fork-updates-r6c — бэклог RuboCop, шаг 6c: Lint в spec/

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r6c.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (R6: «`UselessAssignment` в `spec/` — R6c»; раздел 10 спеки R5b-1).
- BASE_SHA: `6b5a573ad6ad0e5dcf3369d69df5442e65bdce16` — HEAD `main` с влитой R5b-1 и спекой R5b-2 (код и spec/ = b9e3c4ec)
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд (влиты R5b-1, mut-m9-m14b, R5b-2), постановщик
  коммитит новое значение в строку BASE_SHA и только потом снимает клон (раздел 2). Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 15 КБ
  (19 файлов `spec/` одним патчем, todo, CHANGELOG) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: в `spec/` не остаётся `Lint/UselessAssignment` (27 мест в 12 файлах), `Lint/Void` (3),
  `Lint/AmbiguousBlockAssociation` (4), `Lint/AmbiguousOperatorPrecedence` (5 офенсов, 3 строки) и
  `Lint/EmptyFile` (1) — 40 офенсов, 19 файлов. Код `app/`/`lib/` не меняется. Правка задана патчем
  постановщика `r6c_specs.patch` (решение по каждому месту — раздел 3); работа исполнителя — применить
  его, убрать записи из todo, CHANGELOG и доказать критериями, что сьют тот же: все примеры BASE
  выполнены и зелёные (AC-001).

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Проверка — только поведение.
Эта веха новых тестов не пишет, но AC-006 (`source_scan.py`) всё равно проверяет все изменённые строки
`spec/`.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r6c`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r6c-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (иначе Docker создаст точку монтирования от root; пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r6c-ci` — копия `chaskiq-r5b1-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5b1-ci $HOME/.cache/chaskiq-r6c-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; `git apply --check` патча на новом BASE; если
   влитые вехи правили эти 19 файлов (mut-m9-m14b может дописывать существующие спеки) — пересобрать
   патч теми же правками (раздел 3) и сверить офенсы rubocop без todo по `spec/`. После R5b-1 в блоках
   `Lint/UselessAssignment` и `Lint/Void` todo останутся только строки `spec/` — шаг 3 и пробник удаляют
   опустевший блок целиком. Перегенерировать список примеров
   `CHASKIQ_R6C_CACHE=$HOME/.cache/chaskiq-r6c-ci bash docs/specs/fork-updates-r6c-probes/rspec_gate_r6c.sh --write-base`
   на чистом checkout `main` и пересчитать sha256 в AC-007. Сейчас в снимках — список примеров BASE
   b9e3c4ec (с 32 примерами R5b-1).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места и решение по каждому

Строки — по BASE. «Автокоррекция» — `rubocop -a --only Lint/UselessAssignment,Lint/Void,
Lint/AmbiguousBlockAssociation,Lint/AmbiguousOperatorPrecedence` (запись убрана, правая часть осталась).

- **Значение не нужно, вызов нужен (побочный эффект) — автокоррекция:**
  `hooks_controller_spec.rb:1038,1055,1069,1133,1160,1196,1232,1254` (`response = send_data(…)` — запрос
  нужен, значение не читается; закомментированный `# expect(response.status)` в контроллерной спеке
  и так видит встроенный `response`); `csat_spec.rb:61`, `openai_spec.rb:125`
  (`message = conversation.add_message(…)`); `graphql/app_user_spec.rb:91` (`r = graphql_post(…)` —
  ответ читается через `graphql_response`); `graphql/article_spec.rb:143,226` (`article = app.articles.create(…)`
  в `before`); `models/app_spec.rb:119,120,131` (`agentN = app.add_agent(…).agent` — агенты нужны как
  данные, переменные нет); `user_auto_message_spec.rb:100` (`notification = message.show_notification_for(…)`).
- **Последнее выражение метода — автокоррекция (значение метода то же):** `pipedrive_spec.rb:20`
  (`data = {…}` в `def data_for`), `spec/support/graphql_queries.rb:61` (`data = {…}` в `def data_for`).
- **Чистое чтение — строка удалена целиком:** `slack_spec.rb:416,437,542,563` и `openai_spec.rb:106`
  (`channel = conversation.conversation_channels.find_by(…)` — запрос без эффекта, канал создан строкой
  выше); `twitter_spec.rb:533` (`conversation = app.conversations.first`).
- **Значение должно было проверяться — проверка добавлена (G1):** `graphql/app_spec.rb:257`
  `count = app.agents.count` в примере «return app unprivileged» — запись оставлена, после
  `expect(graphql_response.errors).to be_present` добавлено `expect(app.agents.count).to eq(count)`
  (приглашение без прав агента не добавляет). Пример зелёный на BASE (проверено, раздел 4).
- **`twitter_spec.rb:573`** `options = {…}` — пример «send message» без проверок (тело вызова
  закомментировано): автокоррекция оставляет хеш-литерал без присваивания; судьбу примера (удалить или
  дописать проверку) решает владелец отдельно — раздел 10.
- **`Lint/Void`** `dialog_360_spec.rb:233`, `message_bird_spec.rb:189`, `telegram_spec.rb:339` — строка `1`
  в начале блока `let(:app_package)` удалена (литерал ничего не делал).
- **`Lint/AmbiguousBlockAssociation`** `pipedrive_spec.rb:127,150`, `graphql/app_package_integration_spec.rb:91,174` —
  `.to change { … }` → `.to(change { … })`, `.to_not change { … }` → `.to_not(change { … })`: фигурный блок
  и так привязан к `change`, скобки только убирают двусмысленность; матчер тот же.
- **`Lint/AmbiguousOperatorPrecedence`** `hooks_controller_spec.rb:1083`, `create_url_upload_spec.rb:42`,
  `rack_attack_spec.rb:137` — скобки по приоритету (`*`, `/` раньше `+`): те же значения.
- **`Lint/EmptyFile`** `spec/controllers/graphql/agent_spec.rb` (0 байт, примеров нет) — файл удалён.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r6c-ci`) на
клоне BASE 4bd1b924 (снимки примеров и патч перепроверены на b9e3c4ec):

1. Rubocop без todo на BASE: у пяти копов вехи в `spec/` 40 офенсов в 19 файлах (план называл 22
   `UselessAssignment` в 12 файлах — на BASE их 27 в тех же 12 файлах). Патч применяется; полный rubocop
   по 18 изменённым файлам с todo без записей вехи — 0 офенсов.
2. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: удалённые чтения без побочных эффектов — по чтению кода; подкреплено полным rspec (AC-001:
все примеры BASE выполнены и зелёные).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Файлы `spec/` — **только** `git apply` патча, руками не править. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r6c-probes
export CHASKIQ_R6C_CACHE=$HOME/.cache/chaskiq-r6c-ci
```

**Шаг 1. Патч:**

```bash
git apply $P/r6c_specs.patch
git status --short        # ожидается: 18 строк " M spec/…" и " D spec/controllers/graphql/agent_spec.rb"
git add -A spec && git commit -qm "Fix Lint offenses in specs"
```

**Шаг 2. Проверка до todo** (ничего не коммитит): `bash $P/rspec_gate_r6c.sh` (≈ 15 мин) — нужна строка
`PASS: full suite green, same examples as BASE`. Красный — раздел 9 (патч и спеки не править).

**Шаг 3. todo** — убрать блоки `Lint/AmbiguousBlockAssociation`, `Lint/AmbiguousOperatorPrecedence`,
`Lint/EmptyFile` и строки `spec/` в блоках `Lint/UselessAssignment` и `Lint/Void` (опустевший блок —
целиком):

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r6c-probes/r6c_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
res = []
for b in out:
    if has(b, cfg["cops_partial"]):
        b = "\n".join(l for l in b.split("\n") if not re.match(r"^    - 'spec/", l))
        if not re.search(r"(?m)^    - '", b):
            continue
    res.append(b)
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + res) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R6c entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r6c

- Changed: Lint offenses in spec/ cleaned up in 18 files (useless assignments, void literals, ambiguous
  block association and operator precedence); the empty spec/controllers/graphql/agent_spec.rb removed;
  the unprivileged agent invite spec now checks that no agent is added.
```

```bash
git commit -am "Note fork-updates-r6c in changelog"
```

**Шаг 5.** Все восемь критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — строка
`backlog without todo: …`; AC-006 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 19 файлов `spec/` (только патчем), `.rubocop_todo.yml`, `CHANGELOG.md`.
- `app/`, `lib/`, `config/`, `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows,
  `bin/*`, `db/`.
- Никаких ручных правок `spec/`, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R6C_CACHE=$HOME/.cache/chaskiq-r6c-ci bash docs/specs/fork-updates-r6c-probes/rspec_gate_r6c.sh'`

- **AC-002** — пути и код: изменены ровно 19 файлов spec/ (agent_spec.rb удалён, остальные — правка содержимого), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл побайтно равен BASE с r6c_specs.patch; todo = BASE без записей R6c; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r6c-probes/r6c_probe.py tree $B'`

- **AC-003** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Lint/AmbiguousBlockAssociation, Lint/AmbiguousOperatorPrecedence, Lint/EmptyFile 0 офенсов, у Lint/UselessAssignment и Lint/Void 0 в spec/; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R6C_CACHE=$HOME/.cache/chaskiq-r6c-ci bash docs/specs/fork-updates-r6c-probes/r6c_backlog_probe.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r6c-ci bin/ci-local --only rubocop'`

- **AC-005** — каждый коммит отдельно, ровно в порядке раздела 5: коммит патча меняет ровно 19 файлов spec/ (= BASE + патч, agent_spec.rb удалён); коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r6c после «# Changelog»; удалять можно только agent_spec.rb; ни один коммит не меняет git-режим и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r6c-probes/r6c_probe.py commits $B'`

- **AC-006** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r6c-probes/source_scan.py $B'`

- **AC-007** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "b226faee896d26b3fd8e41c344fa275b2cca9219e1e0203f19773068824eb8e2  docs/specs/fork-updates-r6c-probes/r6c_probe.py" "ae3f52cf3fcc4adf9196c7447c90ecdc70eedc4a7b6829bca71122bcb0adcac6  docs/specs/fork-updates-r6c-probes/r6c_config.json" "2052a5c96353802ad33ddbfeb5bd59ace58e2ecc256fe974f2967e6ea0a08ef6  docs/specs/fork-updates-r6c-probes/r6c_specs.patch" "92f4ba6c2ce006d010c42feb1f7a616ce9cb915735f02e4b7b59b07edc38d029  docs/specs/fork-updates-r6c-probes/r6c_backlog_probe.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fork-updates-r6c-probes/source_scan.py" "4b15bd2b24518cda8ff76c2c7a284db6f3d5285f14d3cdc0338109d6fe220ff1  docs/specs/fork-updates-r6c-probes/rspec_gate_r6c.sh" "914d301efe8dc3415b596afc22c3f6e8d5e3446d85bad93859cf35bd5afc02c0  docs/specs/fork-updates-r6c-probes/r6c_sentinel.rb" "6bafd8110e4f6b29b55ca38bae691c5058400b4668fe6da9d1c9efb49a782b9f  docs/specs/fork-updates-r6c-probes/examples_base.txt" "1b0af0b341480b51ac3f41b11b932beda947078c0e71fc32bb0ecf00b1be8081  docs/specs/fork-updates-r6c-probes/pending_allowed.txt" "1d9ee377b84570373fac45f2d0cebe803db89e35f2c48c7e25e21fcd6c3621a5  docs/specs/fork-updates-r6c-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-004, AC-006, AC-007, AC-008 зелёные; AC-002 красный (`… is not BASE +
r6c_specs.patch`); AC-003 красный (`… offenses left`); AC-005 красный (`missing commits`).

Пробный прогон автора (20.11.2026, свежий клон от BASE 4bd1b924, сборка по разделу 5 буквально):
- чистый клон: AC-004, AC-006 (`SOURCE SCAN PASS 0 files`), AC-007, AC-008 зелёные; AC-002, AC-003,
  AC-005 красные с сообщениями выше (AC-003 — `Lint/UselessAssignment: 27 offenses left … under spec/`);
- после сборки: все 8 AC зелёные — rspec 763 examples (= BASE), 0 failures, 30 pending, сторож 735;
  AC-003 backlog без todo BASE 1282 → 1242; AC-006 `SOURCE SCAN PASS 18 files`; файлов от root нет;
- порченые правки (все ловятся): убранная проверка G1 → AC-002; строка
  `File.read(Rails.root.join("app/models/app.rb"))` в спеке → AC-006; правка `app/models/lead.rb` → AC-002
  «not an R6c path»; пустой `agent_spec.rb` оставлен → AC-002 «must be deleted».

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r6c.md --exclude "docs/specs/fork-updates-r6c-probes/**" --context "chaskiq fork-updates-r6c: Lint в spec/ (UselessAssignment 27, Void 3, AmbiguousBlockAssociation 4, AmbiguousOperatorPrecedence, EmptyFile) одним патчем постановщика; app/ не тронут; одна добавленная проверка (приглашение без прав не добавляет агента); только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r6c.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r6c-probes/**

Контекст ревьюерам: найти удалённую строку с побочным эффектом, ослабленный матчер и присваивание,
значение которого спека должна была проверять, но не проверяет (раздел 3). Спеки править нельзя —
замечание по месту решает постановщик (раздел 9).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r6c.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r6c.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после него AC-003/AC-004 красные — дефект спеки;
- пример красный после патча (в том числе добавленная проверка G1), и это не флап — приложи вывод;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл удалённую строку с эффектом или ослабленную проверку — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки `spec/`/`app/`/`lib/`, правка пробников и патча, `pending`/`skip`, глушить
вывод и коды возврата.

## 10. Стыки

- `twitter_spec.rb` «send message» (около строки 524) — пример без единой проверки: тело доставки
  закомментировано, остаётся только приём вебхука. Удалить или дописать проверку — вопрос владельцу.
- После R5b-1 и этой вехи в todo не остаётся записей `Lint/UselessAssignment` и `Lint/Void`.
