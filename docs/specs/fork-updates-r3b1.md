# fork-updates-r3b1 — бэклог RuboCop, шаг 3b-1: `Rails/Blank` и `Rails/Presence` с проверкой типа получателя

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r3b1.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — первая часть R3b оттуда, раздел 10).
- BASE_SHA: `fbfd77f6fd390e41435c184db581e300121a1a1e` — HEAD `main` с влитыми R1–R6b, R7a
  (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (раздел 2). Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 4 КБ
  (7 файлов, 9 мест, 10 строк todo) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- **`spec/` веха не трогает** (параллельно идёт mut-m9-m14, он добавляет файлы в `spec/`).
- Цель: RuboCop сам переписывает 9 мест в 7 файлах `app/`+`lib/`: `return unless x.present?` →
  `return if x.blank?` (`Rails/Blank`, 5) и `x.m if x.present?` → `x.presence&.m` (`Rails/Presence`,
  4), затем выравнивает отступы; блоки этих двух копов уходят из todo целиком (`Rails/Present` —
  нет: его единственное место, `safe_download.rb`, меняет поведение на строке из пробелов). Ничего, кроме вывода команд RuboCop, не меняется (повтор команд на BASE,
  AC-002/AC-003), а равенство до/после доказано для типов получателя в каждом месте (AC-006).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r3b1`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r3b1-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (иначе Docker создаст точку монтирования от root; команды раздела 5 и
  пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r3b1-ci` — копия `chaskiq-r6b-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r6b-ci $HOME/.cache/chaskiq-r3b1-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; прогнать раздел 5 на черновике
   (`r3b1_config.json` `files` и `sites` пересчитать, если менялись эти файлы или todo); если
   менялся `spec/` — перегенерировать список примеров:
   `CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci bash docs/specs/fork-updates-r3b1-probes/rspec_gate_r3b1.sh --write-base`
   на чистом checkout `main`. Сейчас в снимках — список примеров `main` cef8ca77 (`spec/` с тех
   пор не менялся).
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Задача и почему

R3b плана — 8 копов Rails, у каждого своя проверка. Эта веха берёт два, равенство которых
сводится к одному факту о типе получателя: `x.present?` — это `!x.blank?`, а `x.presence` — это
`x if x.present?`, если класс `x` берёт `present?`/`presence` у ActiveSupport (или ActiveRecord::Core:
`present?` true, `blank?` false). Тогда:
- `return unless x.present?` ≡ `return if x.blank?`;
- `x.m(args) if x.present?` ≡ `x.presence&.m(args)`: при пустом `x` оба дают `nil` и не вычисляют
  аргументы (`&.` их не вычисляет), при непустом — оба вызывают `m` один раз; выражение `x` в
  этих местах — локальная переменная, вычисляется без побочных эффектов.

Глобально (для всех классов приложения и гемов) этот факт неверен: свои `present?`/`presence`
есть у `ActionText::RichText`, ячеек `roo`, `scout_apm`, `rspec-mocks`, `snaky_hash` — проверено
вживую. Поэтому тип получателя в каждом месте установлен чтением кода и записан в
`r3b1_config.json` (`sites`), а `r3b1_presence_guard.rb` в загруженном приложении проверяет эти
классы и всех их наследников:

| Место | Получатель |
|---|---|
| `application_cable/connection.rb` `return unless app.present?` | `App` или `nil` (`App.find_by`) |
| `types/app_type.rb` `if conversation.present?` | `Conversation` или `nil` (`find_by`) |
| `types/app_type.rb` `return unless sort.present?` | `String` или `nil` (`argument :sort, String`) |
| `email_chat_notifier_job.rb` `return unless response.present?` | `Mail::Message` или `nil` (`deliver_now`) |
| `action_trigger.rb` ×2 `next_step["controls"].present?` | значение JSON: Hash, Array, String, число, true/false, `nil` |
| `agents/sessions_controller.rb` `token.destroy if token.present?` | `Doorkeeper::AccessToken` или `nil` |
| `article_settings_delete_lang.rb` `translation.destroy if translation.present?` | `ArticleSetting::Translation` или `nil` |
| `lib/app_packages_catalog.rb` `pkg.update(data) if pkg.present?` | `AppPackage` (`find_or_create_by`) |

Шаг Layout нужен из-за одного места: многострочный `if … end` в `app_type.rb` стал одним вызовом
`conversation.presence&.log_async(…)`, аргументы выравниваются.

Остальные копы R3b (`OrderArguments` — SQL меняется на `"таблица"."колонка"`, проверка — по
запросу; `Pluck`, `WhereRange`, `StrongParametersExpect`, `Delegate`) — R3b-2 (раздел 10).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r3b1-ci`) на
клоне BASE fbfd77f6:

1. Шаг 2 раздела 5: `-a` исправляет только 4 места `Presence`, `Blank` — небезопасный автокоррект,
   нужен `-A`; с `-A --only Rails/Blank,Rails/Presence` — 9 из 9. Шаг 3 (`-a --only Layout`) —
   8 исправлений в одном месте; после этого rubocop по 7 файлам без todo — других офенсов не
   прибавилось, блоки двух копов из todo можно убрать. Первый черновик убирал и блок `Rails/Present`
   (считал его устаревшим) — AC-004/AC-005 красные: офенс в `safe_download.rb` есть.
2. `r3b1_guard_gate.sh` — `R3B1 GUARD PASS 75 classes` (классы мест + наследники); глобальный
   вариант той же проверки (все модули) красный из-за классов, которых в этих местах нет (раздел 3).
3. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: типы в таблице раздела 3 установлены чтением кода (`find_by` возвращает запись или
`nil`, GraphQL приводит аргумент к `String`, `deliver_now` возвращает `Mail::Message`); значение
`next_step["controls"]` приходит из JSON-конфига бота. Подкреплено полным rspec (AC-001).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Перед шагом 1 один раз задай переменные:

```bash
P=docs/specs/fork-updates-r3b1-probes
export CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci
RUBOCOP_IN_DOCKER() { mkdir -p vendor/bundle && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true -v "$PWD:/app" -v "$CHASKIQ_R3B1_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04 bash -c "bundle install --quiet; mapfile -t f < <(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))[\"files\"]' $P/r3b1_config.json); bundle exec rubocop --cache false $1 --only $2 \"\${f[@]}\""; }
```

**Шаг 1.** Убрать из todo блоки двух копов целиком:

```bash
python3 -I - <<'EOF'
import json, re
cops = json.load(open("docs/specs/fork-updates-r3b1-probes/r3b1_config.json"))["cops"]
text = open(".rubocop_todo.yml").read()
head, *blocks = text.rstrip("\n").split("\n\n")
out = [b for b in blocks if not any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cops)]
assert len(out) == len(blocks) - len(cops), "not one block per cop - stop, section 9"
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: 1 file changed, … deletions(-) — только .rubocop_todo.yml
git commit -am "Drop R3b1 cops from RuboCop todo"
```

**Шаг 2.** Автокоррект двух копов (`-A`: у `Rails/Blank` автокоррект помечен небезопасным):

```bash
RUBOCOP_IN_DOCKER -A Rails/Blank,Rails/Presence
git diff --stat | tail -1  # ожидается: 7 files changed
git commit -am "Autocorrect Rails/Blank and Rails/Presence"
```

**Шаг 3.** Выравнивание:

```bash
RUBOCOP_IN_DOCKER -a Layout
git diff --stat | tail -1  # ожидается: 1 file changed (app/graphql/types/app_type.rb)
git commit -am "Fix layout after Rails/Presence"
```

**Шаг 4.** Запись в CHANGELOG: вставь сразу после первой строки `# Changelog` файла `CHANGELOG.md`
этот блок (с пустой строкой до и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r3b1

- Changed: Rails/Blank and Rails/Presence autocorrected in 7 files of app/ and lib/ (9 places;
  receiver types checked per site).
```

```bash
git commit -am "Note fork-updates-r3b1 in changelog"
```

**Шаг 5.** Прогнать все восемь критериев раздела 7 (каждая команда — как написана). Если какой-то
красный — читай вывод, сверяйся с разделом 9. Ручная правка Ruby-файлов запрещена; если шаг 2 или 3
дал не то — `git reset --hard <коммит шага 1>` и повтори шаги 2–4 командами выше.

**Шаг 6.** Ревью и `report.json` — раздел 8. В `report.json`: `note` AC-002 — строка `files: …`;
AC-004 — строка `backlog without todo: …`; AC-006 — строка `R3B1 GUARD PASS …`.

## 6. Не трогать

- Всё, кроме `.rubocop_todo.yml`, `CHANGELOG.md` и 7 файлов из `r3b1_config.json` `files`.
  **`spec/` не трогать.**
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`,
  `config/`.
- Никаких ручных правок Ruby, `# rubocop:` директив, `--auto-gen-config`, других копов в `--only`.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci bash docs/specs/fork-updates-r3b1-probes/rspec_gate_r3b1.sh'`

- **AC-002** — дерево: files совпадают со списками Rails/Blank и Rails/Presence на BASE; изменены ровно todo, CHANGELOG и все 7 файлов, обычные файлы с прежним git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; todo = BASE без блоков двух копов; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы; каждый из 7 файлов побайтно равен повтору шагов 2 и 3 на версии BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci python3 -I docs/specs/fork-updates-r3b1-probes/r3b1_probe.py tree $B'`

- **AC-003** — каждый коммит отдельно, ровно в порядке раздела 5: коммит todo — только todo, равный ожидаемому; коммит автокорректа — ровно 7 файлов, каждый = повтор шага 2 на родителе; коммит выравнивания — ровно те файлы, что меняет повтор шага 3 на родителе, каждый равен ему; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r3b1 после «# Changelog»; ни один коммит не меняет git-режим, не добавляет/удаляет путь, не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci python3 -I docs/specs/fork-updates-r3b1-probes/r3b1_probe.py commits $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Rails/Blank и Rails/Presence 0 офенсов; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci bash docs/specs/fork-updates-r3b1-probes/r3b1_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r3b1-ci bin/ci-local --only rubocop'`

- **AC-006** — тип получателя: в загруженном приложении (test) у каждого класса из sites r3b1_config.json и у всех его наследников presence — Object из activesupport, present? — из activesupport core_ext/*/blank.rb или activerecord core.rb; самопроверка (класс со своим present?, класс со своим presence) ловится.
  `bash -c 'CHASKIQ_R3B1_CACHE=$HOME/.cache/chaskiq-r3b1-ci bash docs/specs/fork-updates-r3b1-probes/r3b1_guard_gate.sh'`

- **AC-007** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "82870c7d3c2e0eac154bae10f69a8021dabfb0a66d69f181b100cdfd0b308c18  docs/specs/fork-updates-r3b1-probes/r3b1_probe.py" "2110b1d14fb3c39d4bc52161a0f98fb6c6e209b44f55c004bd4325c601f43cde  docs/specs/fork-updates-r3b1-probes/r3b1_config.json" "1984e2339fbe70a0101e69925502bd17363d9f1489082b00620e6007ae368b3e  docs/specs/fork-updates-r3b1-probes/r3b1_presence_guard.rb" "070dd6773e1d13fdf5b0140ed342c5dda0c2bb8cb3e2f93ce7241037a633f06d  docs/specs/fork-updates-r3b1-probes/r3b1_guard_gate.sh" "7625ed00435613d9142315ac077e134d8e8dbf40ad9fd5668fd6901e93271041  docs/specs/fork-updates-r3b1-probes/r3b1_backlog_probe.sh" "3aa910e495ac95c18854468a048f0cecbf6befef45173ee24d4d5e29e6cdeaf9  docs/specs/fork-updates-r3b1-probes/rspec_gate_r3b1.sh" "cc19b85ea5d29e131d418d9125f773f6ab0e28c5c10cff63d2a819f2b28c8de2  docs/specs/fork-updates-r3b1-probes/r3b1_sentinel.rb" "b438830e81c10d4b35e0095f343b9e11ade9bb26e46dd829c3474acf09b1a6b9  docs/specs/fork-updates-r3b1-probes/examples_base.txt" "4b5ec632f43df67904d82736c78e3ac65ee5e4b65366684fadbbbb33b528c68f  docs/specs/fork-updates-r3b1-probes/pending_allowed.txt" "0a2ddcd0094d26569d0c95dcc5d0236304708a5669449beaf20c793853ff8874  docs/specs/fork-updates-r3b1-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-006, AC-007, AC-008 зелёные; AC-002 красный (`not the replay of both
autocorrect steps on BASE`); AC-003 красный (`missing commits`); AC-004 красный (`… offenses left`).

Пробный прогон автора (20.11.2026, свежий клон от BASE, сборка по §5 буквально):
- чистый клон: AC-002/003/004 красные с сообщениями выше; AC-006/007/008 зелёные (AC-001/005 на
  чистом клоне не гонялись: дерево вне app/lib то же, что после сборки, где они зелёные);
- после сборки: все 8 AC зелёные — rspec 700 examples, 0 failures, 30 pending; AC-002 «files: 7, 7
  equal to the replay»; AC-004 backlog без todo BASE 1291 → 1282; AC-006 «R3B1 GUARD PASS 75 classes»;
  файлов от root в клоне нет. Диффы коммитов: todo −17 строк; автокоррект 7 файлов +10/−14; layout
  1 файл +2/−2; CHANGELOG +6.
- порченые правки (все ловятся): ручная правка `token.presence&.destroy` → AC-002 и AC-003 красные;
  свой `present?` в `AppPackage` → AC-006 и AC-002 красные; лишний удалённый блок `Rails/Pluck` в todo →
  AC-002 красный; `ActionText::RichText` в классах сайта → AC-006 красный (и AC-007 по sha256).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r3b1.md --exclude "docs/specs/fork-updates-r3b1-probes/**" --context "chaskiq fork-updates-r3b1: rubocop -A Rails/Blank,Rails/Presence в 7 файлах app/ lib/ (return unless x.present? -> return if x.blank?; x.m if x.present? -> x.presence&.m) + Layout; блоки двух копов из todo; тип получателя в каждом месте проверен guard-ом; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r3b1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r3b1-probes/**

Контекст ревьюерам: проверить таблицу типов получателя (раздел 3) по коду — не может ли в месте
оказаться объект со своим `present?`/`presence` (например, `ActionText::RichText`), и что выражение
перед `.presence&.` вычисляется без побочных эффектов; правки сверх вывода RuboCop. Исправлять в коде
нельзя — замечание по месту решает постановщик (раздел 9).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r3b1.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r3b1.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- шаг 2 меняет не 7 файлов, или после шага 3 AC-005 красный, или AC-004 показывает рост другого
  копа — приложи вывод; это дефект спеки;
- AC-006 красный (у класса места свой `present?`/`presence`) — приложи вывод;
- AC-002/AC-003 говорят «not the replay» после повтора шагов 2–4 с `git reset --hard` — приложи вывод;
- сьют красный (AC-001) — приложи вывод; если причина в переписанном месте — файл, строка;
- ревьюер нашёл место, где получатель может быть другого типа, — файл, строка, довод ревьюера;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов, перегенерация `.rubocop_todo.yml`, правка пробников,
удалять/skip-ать тесты, глушить вывод и коды возврата.

## 10. Стыки

- `Rails/Present` (1, `safe_download.rb:148`: `location && !location.empty?` → `location.present?`
  отвергает и строку из пробелов) — ручное решение, R5b.
- R3b-2: `Rails/OrderArguments` (19; SQL `ORDER BY id desc` → `ORDER BY "t"."id" DESC` — проверка по
  запросу в каждом месте, особенно с `joins`/`union_scope`), `Pluck` (2 вне `spec/`), `WhereRange`
  (1), `StrongParametersExpect` (3; контракт API), `Delegate` (2) — каждое со своей проверкой.
- `Pluck` в `spec/` (7) — после mut-m9-m14.
