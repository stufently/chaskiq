# fork-updates-r8a — бэклог RuboCop, шаг 8a: лимиты Metrics и LineLength настройкой с причиной, в todo — только выбросы

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r8a.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «R8 — Metrics и `Layout/LineLength`» и «Решения владельца
  2026-11-20, вторая партия»: «`MethodLength` Max 30, `AbcSize` 30, `CyclomaticComplexity`/`PerceivedComplexity`
  13, `ClassLength` 300 с Exclude `app/services/message_apis/**` …, `BlockLength` Exclude `lib/tasks/**` и
  `config/routes.rb`, `ParameterLists` 7, `ModuleLength` — Max по `concerns/user_handler.rb` с вехой
  рефакторинга, `LineLength` 140 + `AllowedPatterns` для URL и base64»). Конфигурационная часть R8; рефакторинг
  выбросов — следующие вехи (раздел 10).
- BASE_SHA: `6f57608185205e001aa0061bab9ec137e36a8b88` — HEAD `main` «Record R7c acceptance» (R7b, R7c, R7d влиты)
  (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: если `main` уйдёт дальше до запуска (раздел 10), постановщик
  переносит его (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 20 КБ (почти весь —
  удалённые строки todo).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все восемь критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: без единой правки `app/`, `lib/`, `spec/`, `config/` в `.rubocop.yml` встают лимиты R8 с причиной у
  каждого (один патч постановщика), а блоки девяти копов R8 в todo сужаются до файлов, которые и с новыми
  лимитами остаются выше них (выбросы, 150 строк вместо 443; блок `Metrics/ModuleLength` уходит целиком). Пять
  новых `Style/IfUnlessModifier` (при Max 140 модификаторная форма влезает в строку) — новый блок todo.
  Поведение кода не меняется, мутантов нет; полный сьют — тот же список примеров (AC-001), дифф кода пуст
  (AC-003).

### Правило: тест проверяет поведение, а не текст кода (обязательно)

Веха не пишет и не правит ни одного файла `spec/` (AC-002, AC-003), поэтому критерия `source_scan.py` нет.
Если по какой-то причине тянет тронуть `spec/` — это пункт раздела 9, а не правка.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r8a`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r8a-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r8a-ci` (если его ещё нет).
2. При переносе BASE (влилась другая веха): `git apply --check` патча `r8a_config.patch`; на
   временном дереве BASE + патч прогнать `r8a_backlog_probe.sh <BASE>`, затем
   `python3 -I docs/specs/fork-updates-r8a-probes/r8a_outliers.py tmp/r8a-backlog/tree.json` — он перепишет
   `outliers`/`cops_keep` в `r8a_config.json` и `outliers.tsv`; сверить `todo_additions` с выводом пробника
   (строки `… the change created new ones`) и цифры раздела 3. Перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R8A_CACHE=$HOME/.cache/chaskiq-r8a-ci bash docs/specs/fork-updates-r8a-probes/rspec_gate_r8a.sh --write-base`
   и пересчитать sha256 в AC-007. Сейчас в снимках — 1155 примеров BASE 6f576081.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-007 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 6f576081 (Docker, копия кэша `chaskiq-fxb-ci`): всего **1012** офенсов, у
девяти копов R8 — **929** (ровно как в плане, a6ec4ad4); с лимитами вехи остаётся **257** выбросов, всего
**345** (с пятью новыми `IfUnlessModifier`). Влитые R7b/c/d копы R8 не задели: числа и файлы те же,
что на 3075fee6 (сдвинулись только номера строк в спеках, откуда R7b убрал `include`).

| Коп | Лимит | Офенсов BASE / план | Выбросов после | Файлов (строк todo: было → стало) |
|---|---|---|---|---|
| `Metrics/MethodLength` | 10 → **30** | 417 / 418 | 83 | 153 → 44 |
| `Metrics/AbcSize` | 17 → **30** | 174 / 173 | 44 | 93 → 34 |
| `Metrics/CyclomaticComplexity` | 7 → **13** | 52 / 53 | 14 | 37 → 12 |
| `Metrics/PerceivedComplexity` | 8 → **13** | 38 / 39 | 9 | 30 → 9 |
| `Metrics/ParameterLists` | 5 → **7** | 9 / 9 | 1 | 9 → 1 |
| `Metrics/ClassLength` | 100 → **300**, Exclude `message_apis/**` | 46 / 46 | 5 | 45 → 5 |
| `Metrics/BlockLength` | 25, Exclude + `lib/tasks/**`, `config/routes.rb` | 12 / 11 | 8 | 7 → 6 |
| `Metrics/ModuleLength` | 100 → **123** | 1 / — | 0 | 1 → блок уходит |
| `Layout/LineLength` | 120 → **140** + 2 `AllowedPatterns` | 180 / 179 | 93 | 68 → 39 |

**`r8a_config.patch` — `.rubocop.yml`**, три хунка, у каждой настройки комментарий-причина:
1. блок `Metrics/BlockLength` (стоял с `spec/**/*`): + `lib/tasks/**/*` и `config/routes.rb` — DSL rake и
   маршрутов, длина блока = список задач/маршрутов. `config/**` и так вне `AllCops` (ошибка плана, раздел 10):
   запись фиксирует решение на случай, если `config/` начнут линтить;
2. блок `Metrics/ModuleLength` (стоял с Exclude `helpers.rb`): + `Max: 123` — длина `user_handler.rb`,
   единственного модуля выше 100; после его рефакторинга Max опускается;
3. новый блок перед `AllCops:` — `MethodLength`/`AbcSize` 30, обе Complexity 13, `ParameterLists` 7,
   `ClassLength` 300 с Exclude `app/services/message_apis/**/*` (адаптер = API провайдера) и `LineLength` 140.

**`AllowedPatterns` у `LineLength`** — URL или base64 не переносятся. Строка может быть длиннее 140, только если
такой токен начинается в первых 139 колонках и идёт до конца строки (кроме закрывающих кавычек, скобок, `,`/`;`):
- URL: `\A.{0,139}https?://[^\s"'`<>]+["'`]?[\s,;)\]}]*\z` — расширяет встроенный `AllowURI` на URL в кавычках
  с хвостом `" },`;
- base64: `\A.{0,139}(?=[A-Za-z0-9+/]*\d)(?=[A-Za-z0-9+/]*[A-Z])(?=[A-Za-z0-9+/]*[a-z])[A-Za-z0-9+/]{40,}={0,2}["']?[\s,;)\]}]*\z`
  — 40+ символов алфавита с цифрой, заглавной и строчной (не слово и не путь из одних строчных).

Покрытие на BASE: из 107 строк длиннее 140 шаблоны снимают **14** — 10 строк URL (`twilio_spec.rb` ×5,
`dialog_360_spec.rb` ×2, `messenger_spec.rb` ×3, `hooks_controller_spec.rb:913`) и 4 base64 (подписи SNS/Paddle,
`hooks_controller_spec.rb:788,910`, `paddle_hooks_controller_spec.rb:36`) — все 14 просмотрены глазами, других
нет. На строках любой длины base64-шаблон совпадает с 22 строками: блобы, id Telegram/Twilio, два пути URL —
только непрозрачные токены. Встроенный `AllowURI` (`{…}`-строка с URL, оканчивающаяся на `}`, или URL до
следующего пробела) действует и сейчас. Пробный файл пробника (AC-004) обходит его: четыре разрешаемые строки
(`{ "url" => "https://…" },`, вложенный хэш с URL, base64 в массиве и в хэше) без шаблонов — офенсы (проверено на
BASE), шесть других (URL с хвостом, URL после колонки 140, строчные буквы без цифр, base64 с хвостом, проза,
JSON) — офенсы и с шаблонами.

**Пять `Style/IfUnlessModifier`** (`app_type.rb:164`, `app.rb:228`, `globalize_accessors.rb:62`,
`messenger/api.rb:87`, `twilio_phone/api.rb:169`): при Max 140 однострочное тело `if`/`unless` влезает в
модификаторную форму. Это следствие лимита, а не правка кода: блок todo с пятью файлами (порядок —
алфавитный, как у `--auto-gen-config`); безопасный автокоррект — следующая веха кода (раздел 10).

**Почему `rubocop -a` по `LineLength` здесь нельзя** (проверено на копии BASE+патч, 10 файлов `spec/` с
длинными строками): исправлено 9 строк из 41, остальные — строки JSON/подписей, которые автокоррект не делит;
зато появились 9 `Style/StringConcatenation` (строку разрезало на `"…" + "…"`), 8 `TrailingWhitespace`,
`HashAlignment`, `FirstHashElementIndentation`, `MultilineHashBraceLayout`, `BlockDelimiters`, а продолжения
строк ушли в колонку 0. Это не чистый перенос — отдельной вехи r8b нет, длинные строки — в списке выбросов.

### Выбросы (вход для вех рефакторинга)

Полный список — `docs/specs/fork-updates-r8a-probes/outliers.tsv` (257 строк: коп, `файл:строка`, метод/класс/
блок, значение, лимит). Методов-выбросов 107; больше всего — `segment.rb` (12 офенсов), `slack/api.rb` (11),
`action_trigger_factory.rb` (10), `content_showcase/presenter.rb` (9). Верх по копам:

| Коп (лимит) | Значение — место |
|---|---|
| MethodLength (30) | 814 `ui_catalog/presenter.rb` `self.configure_hook`; 224 `dialog360/presenter.rb` `self.configure_hook`; 201 `inbox_sections/presenter.rb` `self.content_hook`; 162 `content_showcase/presenter.rb` `self.configure_hook`; 129 `action_trigger_factory.rb` `self.infer_for`; 96 `slack/api.rb` `thread_head`; 86 `segment.rb` `tagged_result`; ещё 76 (8 из них — `spec/controllers/api/v1/hooks/*`) |
| AbcSize (30) | 111 `segment.rb` `tagged_result`; 103.5 `dialog360/presenter.rb` `configure_hook`; 93.5 `inbox_sections/presenter.rb` `content_hook`; 90.64 `content_showcase/presenter.rb` `configure_hook`; 80.78 `action_trigger_factory.rb` `infer_for`; 73.7 `chat_notifier_mailer.rb` `notify`; ещё 38 |
| CyclomaticComplexity (13) | 27 `block_manager.rb` `deliver_attachments`; 27 `segment.rb` `tagged_result`; 24 `dialog360/presenter.rb` `configure_hook`; 23 `slack/api.rb` `notify_message`; ещё 10 |
| PerceivedComplexity (13) | 30 `block_manager.rb` `deliver_attachments`; 25 `slack/api.rb` `notify_message`; 24 `inbox_sections/presenter.rb` `content_hook`; 24 `segment.rb` `tagged_result`; ещё 5 |
| ClassLength (300) | 563 `Types::AppType`; 401 `Segment`; 366 `ActionTriggerFactory`; 354 `AppUser`; 342 `App` |
| BlockLength (25) | 122, 40, 29 `action_trigger_factory.rb` (`subject.config do`); 56 `globalize_accessors.rb` `included do`; 45 `segment.rb`; 39 `twitter/api.rb`; 32 `dialog360/api.rb`; 27 `app.rb` |
| ParameterLists (7) | 8 `app_type.rb` `conversations` |
| ModuleLength (123) | 0; `user_handler.rb` = 123 — веха рефакторинга опустит Max |
| LineLength (140) | 93 строки в 39 файлах: 37 кода и 2 комментария в `spec/` (фикстуры JSON, заголовки письма, хэши), 26 одинаковых комментариев-описаний хуков в презентерах, 7 прочих комментариев, 21 строка кода в `app/`/`lib/`; максимум 5768 `hooks_controller_spec.rb:906` |

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 6f576081:

1. Замер RuboCop без todo до и после патча (раздел 3), `--show-cops` без todo — значения и списки.
2. Полный сьют на BASE (`--write-base`): 1155 примеров, 0 failures, 30 pending.
3. Строгий `bin/ci-local --only rubocop` с патчем и todo по шагу 2 — `rubocop: clean`.
4. Патч перегенерирован от BASE 6f576081 (после R7b хунк перед `AllCops:` сдвинулся); скрипт todo — тот же.
5. Пробный прогон по разделу 5 и порченые правки: итоги — раздел 7.

Предположение: ни один пример сьюта не зависит от `.rubocop.yml`/todo (подтверждает AC-001).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. `.rubocop.yml` — **только** `git apply` патча, todo — **только** скрипт ниже. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r8a-probes
export CHASKIQ_R8A_CACHE=$HOME/.cache/chaskiq-r8a-ci
```

**Шаг 1. Лимиты:**

```bash
git apply $P/r8a_config.patch && git commit -qam "Set R8 metric limits by owner decision"
```

**Шаг 2. todo** — в блоках `cops_keep` конфига остаются только перечисленные там файлы (блок без строк файлов
уходит целиком, с комментариями), блоки `todo_additions` встают на алфавитное место:

```bash
python3 -I - r8a <<'PY'
import json, re, sys
n = sys.argv[1]
cfg = json.load(open(f"docs/specs/fork-updates-{n}-probes/{n}_config.json"))
has = lambda b, c: re.search(rf"(?m)^{re.escape(c)}:$", b)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = []
for b in blocks:
    cop = next((c for c in cfg["cops_keep"] if has(b, c)), None)
    if cop:
        keep = {f"    - '{p}'" for p in cfg["cops_keep"][cop]}
        lines = b.split("\n")
        assert keep <= set(lines), "stop: section 9"
        b = "\n".join(l for l in lines if not l.startswith("    - '") or l in keep)
        if not keep:
            continue
    out.append(b)
for cop, add in cfg["todo_additions"].items():
    assert not any(has(b, cop) for b in out), "stop: section 9"
    block = "\n".join([add["comment"], f"{cop}:", "  Exclude:"] + [f"    - '{p}'" for p in add["files"]])
    names = [re.search(r"(?m)^([A-Z]\w+/\w+):$", b).group(1) for b in out]
    out.insert(next((i for i, x in enumerate(names) if x > cop), len(out)), block)
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
PY
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Keep only R8 outliers in RuboCop todo"
```

**Шаг 3. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r8a

- Changed: RuboCop metric limits by owner decision (R8), each with its reason in `.rubocop.yml`:
  MethodLength and AbcSize 30, Cyclomatic/PerceivedComplexity 13, ParameterLists 7, ClassLength 300
  (integration adapters under `app/services/message_apis/**` excluded), ModuleLength 123 (the length of
  `user_handler.rb`, until its refactor), BlockLength excludes `lib/tasks/**` and `config/routes.rb`,
  LineLength 140 with AllowedPatterns for a URL or base64 blob running to the end of the line.
- Changed: `.rubocop_todo.yml` keeps only the files still above the new limits (outliers, listed for
  refactor milestones) and five Style/IfUnlessModifier entries that Max 140 created; no code changed.
```

```bash
git commit -am "Note fork-updates-r8a in changelog"
```

**Шаг 4.** Все восемь критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-004 — строка `backlog without todo: …`; AC-005 — строка `rubocop: clean`.

## 6. Не трогать

- Всё, кроме `.rubocop.yml` (только патчем), `.rubocop_todo.yml` (только скриптом шага 2), `CHANGELOG.md`.
  Новых файлов нет.
- `app/`, `lib/`, `spec/`, `config/`, `db/`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`.
- Блоки todo всех копов, кроме девяти копов R8; строки выбросов в блоках R8 (их уберут вехи рефакторинга).
- Никаких ручных правок, `rubocop -a`/`-A`, `# rubocop:` директив, `--auto-gen-config`, `pending`/`skip`.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R8A_CACHE=$HOME/.cache/chaskiq-r8a-ci bash docs/specs/fork-updates-r8a-probes/rspec_gate_r8a.sh'`

- **AC-002** — пути и конфиг: изменены ровно .rubocop.yml, todo и CHANGELOG, с тем же git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; .rubocop.yml побайтно равен BASE с патчем; todo = BASE, где в блоках девяти копов R8 остались только файлы-выбросы конфига и добавлен блок IfUnlessModifier; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r8a-probes/r8a_probe.py tree $B'`

- **AC-003** — код не тронут: дифф app/, lib/, spec/, config/, db/, Gemfile и Gemfile.lock от BASE пуст и в коммитах, и в рабочем дереве.
  `bash -c 'B=$(git merge-base HEAD @{u}) && git diff --quiet $B HEAD -- app lib spec config db Gemfile Gemfile.lock && git diff --quiet $B -- app lib spec config db Gemfile Gemfile.lock && echo "CODE DIFF EMPTY"'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у девяти копов R8 офенсы ровно по списку выбросов конфига (коп, файл, число), блок каждого в todo перечисляет ровно файлы с офенсами; у прочих копов ни в одном файле не больше, чем на BASE, кроме пяти IfUnlessModifier из todo_additions; разрешённый конфиг без todo даёт лимиты, списки Exclude и AllowedPatterns конфига; пробный файл шаблонов: 4 строки URL/base64 разрешены, 6 прочих — офенсы; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R8A_CACHE=$HOME/.cache/chaskiq-r8a-ci bash docs/specs/fork-updates-r8a-probes/r8a_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r8a-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит лимитов — только .rubocop.yml = BASE + r8a_config; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r8a после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r8a-probes/r8a_probe.py commits $B'`

- **AC-007** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "7efd3fe4f5c4b159941fac30b6001b53ecc20ec9234b61ee57ef19dcfd77e512  docs/specs/fork-updates-r8a-probes/examples_base.txt" "c1008745bb43802684016b161a0f3f72ca66da7c347c7f3db5368ef464a237d7  docs/specs/fork-updates-r8a-probes/outliers.tsv" "a9a18dd638639ef609959370ca553ec0c1fd55b80e029c1cc5dde7c8b54ca737  docs/specs/fork-updates-r8a-probes/pending_allowed.txt" "9d2039e813911e6bc261843618f28b96442bea376f0e76c46032c6f242bbcc7b  docs/specs/fork-updates-r8a-probes/r8a_backlog_probe.sh" "06da3f9d2d9d03cfbfc7a861244b732c352413d961dedb7c5be56b39c1047d28  docs/specs/fork-updates-r8a-probes/r8a_config.json" "8a4f8a3d76fe938b8f658953a83f38e26b5fc18662009e5197bc9e73bb66bc5d  docs/specs/fork-updates-r8a-probes/r8a_config.patch" "eace25ad7b720a424bf06ffd6afe7a49c11d00d3e65ae647ab01b7e2d350d786  docs/specs/fork-updates-r8a-probes/r8a_outliers.py" "fb9249b8a69c9a0e211f40e47b505205090e828af7b3d1ed9b2a2056d9d678b6  docs/specs/fork-updates-r8a-probes/r8a_probe.py" "ebf9d84a39d6b75b910c6fadc4ab216a98e074195bdca916768a13ea40358034  docs/specs/fork-updates-r8a-probes/r8a_sentinel.rb" "3ef6fc129dda4c400f6c459d80a44f3cfa9cda3d78dbd9a14745dbbf297901f1  docs/specs/fork-updates-r8a-probes/rspec_gate_r8a.sh" "168acdc9ae4a4f45894df3ae23abf5dca2bcea185c36a20ac34ed2584f56f922  docs/specs/fork-updates-r8a-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-003, AC-005, AC-007, AC-008 зелёные; AC-002 красный
(`R8A paths without the change` / `is not BASE + …`); AC-004 красный (`… outlier list has …`, `todo …: lists …`);
AC-006 красный (`missing commits`).

Пробный прогон автора (21.11.2026; свежий клон BASE 6f576081 со спекой и пробниками одним коммитом поверх,
ветка с upstream `origin/main`, сборка по разделу 5 буквально; кэш — копия `chaskiq-fxb-ci`, путь кэша в командах
подменён на копию):
- чистый клон: AC-001 (1155 примеров, 0 failures, 30 pending, ≈ 6,5 мин), AC-003 (`CODE DIFF EMPTY`), AC-005
  (`rubocop: clean`), AC-007, AC-008 — rc=0; AC-002, AC-004 (`AllowedPatterns is None`, четыре строки пробного
  файла — офенсы, `total did not go down: BASE 1012, tree 1012`), AC-006 (`missing commits`) красные;
- после сборки: все 8 AC rc=0 — rspec 1155/0/30; AC-002 `R8A TREE PASS`; AC-004 бэклог без todo 1012 → 345,
  копы R8 929 → 257, `pattern probe: 4 allowed, 6 offenses`; AC-006 `R8A COMMITS PASS`;
- порченые правки (все ловятся AC-002, AC-004 и AC-006): опечатка лимита (`MethodLength` `Max: 31`) — AC-004
  `has no 'Max: 30'`, четыре файла с офенсами меньше списка, `app_type.rb` в todo без офенса; лишний Exclude
  (`app/models/segment.rb` в `ClassLength`) — AC-004 `segment.rb: 0 offenses, outlier list has 1` и список
  Exclude; блок todo оставлен (`Metrics/ModuleLength` с `user_handler.rb`) — AC-004 `lists 1 files, offending
  files 0`, AC-002/AC-006 todo не равен ожидаемому. AC-005 во всех трёх зелёный (порча только ослабляет).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r8a.md --exclude "docs/specs/fork-updates-r8a-probes/**" --context "chaskiq fork-updates-r8a: RuboCop R8 по решению владельца без правок кода — в .rubocop.yml с причиной MethodLength/AbcSize 30, Complexity 13, ParameterLists 7, ClassLength 300 c Exclude app/services/message_apis/**, ModuleLength Max 123 (user_handler.rb), BlockLength Exclude lib/tasks/** и config/routes.rb, LineLength 140 + AllowedPatterns (URL или base64 от колонки <140 до конца строки); в todo блоки девяти копов R8 сужены до выбросов (443 -> 150 строк), новый блок Style/IfUnlessModifier на 5 файлов (следствие Max 140); полный сьют — тот же список примеров; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r8a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r8a-probes/**

Контекст ревьюеру: шаблон `AllowedPatterns`, который пропускает длинную строку не из-за URL/base64; причина в
`.rubocop.yml`, не совпадающая с фактом; файл todo, оставшийся без офенса или пропавший с офенсом. Правки
`.rubocop.yml` и todo вне патча и скрипта нельзя — замечание по месту решает постановщик (раздел 9).

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 8 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r8a.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r8a.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после шагов 1–2
  AC-002/AC-004/AC-005 красные — дефект спеки (обычно BASE ушёл, а список выбросов не перегенерирован);
- полный сьют красный — приложи вывод (конфиг RuboCop на тесты не влияет: это среда или флап); если причина не
  в дереве — приложи два прогона;
- ревьюер нашёл строку, которую шаблон пропускает не из-за URL/base64, или неверную причину — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: правки кода, спек, `.rubocop.yml` и todo руками (только патч и скрипт), `rubocop -a`, правка
пробников, патча и снимков, новые Exclude, `pending`/`skip`, запуск Codex или Qwen как ревьюеров, глушить вывод
и коды возврата.

## 10. Стыки

- **R7b, R7c, R7d влиты до BASE** (bce73df7, 84bc1e6e, 4c2f0cb9): патч и список выбросов посчитаны уже от их
  кода. Параллельных вех, правящих `.rubocop.yml`, `.rubocop_todo.yml` или копы R8, сейчас нет. Общий у любой
  вехи — `CHANGELOG.md` (блок после `# Changelog`).
- **Если до влития этой вехи в `main` попадёт другая** — перенос BASE, `--write-base` и `r8a_outliers.py`
  (раздел 2, п. 2): пробники todo и CHANGELOG считают ожидаемое от BASE, снимки rspec — список примеров BASE,
  список выбросов — от кода BASE.
- **Вехи рефакторинга выбросов (после этой, с характеризационными тестами, по файлу):** вход — `outliers.tsv`.
  Первыми — `ui_catalog/presenter.rb#configure_hook` (814 строк, DSL-схема), `segment.rb` (`tagged_result`,
  `es_search`, `nested_preds_group`, класс 401), `action_trigger_factory.rb` (`infer_for`, блоки `config`),
  `block_manager.rb#deliver_attachments`, `slack/api.rb#notify_message`; `user_handler.rb` — веха с понижением
  `ModuleLength` Max. Каждая веха убирает свои строки из todo.
- **Следующая веха кода:** `rubocop -a --only Style/IfUnlessModifier` по пяти файлам (безопасный автокоррект,
  полный сьют) — блок уходит из todo; длинные строки `spec/` — ручной перенос фикстур (heredoc/файл фикстуры),
  не автокоррект (раздел 3).
- **Ошибки плана:** `config/routes.rb` и так вне линтинга (`AllCops: Exclude: config/**/*`), запись в BlockLength —
  только фиксация решения; `ModuleLength` в таблице плана отсутствует (1 офенс, `user_handler.rb` 123/100);
  счёты плана на 1–2 офенса расходятся с BASE (код ушёл вперёд); побочный эффект Max 140 на
  `Style/IfUnlessModifier` в плане не учтён. Справка: Exclude `message_apis/**` снимает 26 из 46 `ClassLength`
  (как в плане), из них 8 классов длиннее 300 — скрыты решением, а не выбросы; Max 300 снимает ещё 15.
