# fork-updates-r7b — бэклог RuboCop, шаг 7b: четыре копа R7 настройкой с причиной и MixinUsage в конфиг RSpec

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r7b.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «R7» и «Решения владельца 2026-11-20, вторая партия»:
  «`FormatStringToken` — `unannotated` в `.rubocop.yml` с причиной; `OneClassPerFile` — `plugin_schema_validator.rb`
  в Exclude с причиной …; `PredicateMethod` — `app/graphql/types/**` в Exclude (имена фиксирует схема GraphQL) …;
  `ClassAndModuleChildren` 5 оставленных с R4 — Exclude с причиной …; `MixinUsage` в spec — в блок конфигурации
  RSpec»). Конфигурационная часть R7 с решением владельца; переименования — следующие вехи (раздел 10).
- BASE_SHA: `8e2ddd3ddddf86b4fb6909ef4248950902d3fd04` — HEAD `main` «Record R3b-3 acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: если `main` уйдёт дальше до запуска (в работе R2b и fix-cleanup-3, раздел 10), постановщик
  переносит его (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 10 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: без единой правки `app/`/`lib/` из todo уходят три блока целиком (`Style/FormatStringToken`,
  `Style/ClassAndModuleChildren`, `Style/MixinUsage`) и строки двух блоков (`Naming/PredicateMethod` — шесть
  файлов `app/graphql/types/`, `Style/OneClassPerFile` — `plugin_schema_validator.rb` и устаревшая
  `lib/subdomain_routes.rb`); их заменяют четыре настройки в `.rubocop.yml` с причиной у каждой, а 13
  верхнеуровневых `include ActiveJob::TestHelper` в спеках — одна строка `config.include` в `spec/rails_helper.rb`.
  Весь код задан двумя патчами постановщика; новых спек нет. Полный сьют — тот же список примеров (AC-001),
  гейт тестов (AC-003) доказывает, что `config.include` несущий: без него 15 спек падают.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле. Спек вехи не
пишет, но правит 14 файлов `spec/`: AC-007 (`source_scan.py`) проверяет их добавленные строки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r7b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r7b-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r7b-ci` (если его ещё нет).
2. При переносе BASE (после влития R2b, fix-cleanup-3 или R7c/R7d): `git apply --check` двух патчей по порядку
   (`r7b_mixin`, `r7b_config`); проверить, что в todo BASE ещё есть три блока `cops_whole` и все строки
   `cops_partial` из `r7b_config.json` (пробник сам падает со «spec defect»), что 13 файлов `Style/MixinUsage`
   по-прежнему начинаются с `include ActiveJob::TestHelper` на верхнем уровне и что тексты двух мутантов —
   ровно один раз в `spec/rails_helper.rb` после патчей. Если менялся `spec/` — перегенерировать снимки на
   чистом checkout `main`:
   `CHASKIQ_R7B_CACHE=$HOME/.cache/chaskiq-r7b-ci bash docs/specs/fork-updates-r7b-probes/rspec_gate_r7b.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1059 примеров BASE 8e2ddd3d.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 8e2ddd3d (Docker, копия кэша `chaskiq-fxb-ci`): всего **1090** офенсов, у
мест этой вехи **48** (после вехи 1042).

| Коп | Сейчас (BASE) | План (a6ec4ad4) | Что делает веха |
|---|---|---|---|
| `Style/FormatStringToken` | 0 при любом стиле | секция `EnforcedStyle` | настройка `unannotated` переезжает из todo в `.rubocop.yml` |
| `Style/ClassAndModuleChildren` | 5 (5 файлов) | 5 «KEEP» R4 | Exclude 5 файлов с причиной |
| `Naming/PredicateMethod` | 15, из них 9 в 6 файлах `app/graphql/types/` | 15 | Exclude `app/graphql/types/**/*`; 6 остальных — R7c/следующая веха |
| `Style/OneClassPerFile` | 25: 21 в `plugin_schema_validator.rb`, 4 в 3 файлах | 27 в 5 файлах | Exclude `plugin_schema_validator.rb`; строка `lib/subdomain_routes.rb` устарела (0 офенсов: классы удалены в R5b-2); 3 файла — R7d |
| `Style/MixinUsage` | 13 (13 спек) | 13 | `config.include` в `rails_helper.rb` |

**`r7b_config.patch` — `.rubocop.yml`.** Блок из четырёх настроек с комментарием-причиной у каждой вставлен
сразу после `Rails/InverseOf: Enabled: false` (перед блоками R7a). Место выбрано так, чтобы патч не
пересекался с патчем R2b (тот вставляет `Naming/MemoizedInstanceVariableName` перед `AllCops:`, раздел 10).
Причины: формат-токены проекта — `"%s"`, другого стиля в коде нет (замер: 0 офенсов при `annotated`,
`template` и `unannotated`); пять плагинных файлов компактны после R4 — вложенный `Twilio` в
`twilio_phone/api.rb` стал бы `MessageApis::Twilio`, а четыре презентера вычисляют ERB с `result(binding)`;
методы `app/graphql/types` — резолверы одноимённых полей схемы (`field :online, Boolean` → `def online`;
проверено для всех 9 мест), `?` изменил бы схему; `PluginSchemaValidator` — один валидатор из 21 класса
узлов схемы (22 класса верхнего уровня в файле). `inherit_mode: merge: Exclude` уже стоит — Exclude из
`.rubocop.yml` и todo складываются.

**`r7b_mixin.patch` — `spec/`.** В 13 спеках удалена строка `include ActiveJob::TestHelper` верхнего уровня
(она подмешивала модуль в `Object`); в `RSpec.configure` `spec/rails_helper.rb` добавлена
`config.include ActiveJob::TestHelper` с комментарием. Почему глобально, а не по типу спек:
`spec/controllers/api/v1/hooks_controller_spec.rb` и `spec/models/agent_notifications_spec.rb` зовут
`perform_enqueued_jobs`, не подключая модуль, — работают только за счёт утечки через `Object`; глобальный
`config.include` сохраняет им помощники. Отличие от BASE: у `include` в группе срабатывает
`ActiveJob::TestHelper#before_setup` (тестовый адаптер очередей), который при подмешивании в `Object`
перекрывался пустым `MinitestLifecycleAdapter#before_setup` rspec-rails; девять других спек уже подключают
модуль внутри `describe` с тем же эффектом. Проверено: полный сьют с патчем зелёный, тот же список 1059
примеров и те же 30 pending, новых warning-строк нет (раздел 4).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 8e2ddd3d:

1. Замер RuboCop без todo (раздел 3), стили `FormatStringToken` — `--only` с каждым из трёх стилей.
2. Полный сьют на BASE (`--write-base`): 1059 примеров, 0 failures, 30 pending, сторож 1031; с двумя
   патчами — те же 1059 примеров и 30 pending, 0 failures (снимки совпали построчно).
3. Мутанты B01 (строка `config.include` удалена) и B02 (`type: :controller`) роняют спеки раздела 7, AC-003.
4. Патчи применяются поверх четырёх патчей R2b и наоборот (раздел 10).
5. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: другие гемы и спеки не полагаются на то, что `ActiveJob::TestHelper` подмешан именно в
`Object` (например, вне примеров RSpec); подтверждает AC-001 на полном сьюте.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. Код, спеки и `.rubocop.yml` — **только** `git apply` патчей. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r7b-probes
export CHASKIQ_R7B_CACHE=$HOME/.cache/chaskiq-r7b-ci
```

**Шаг 1. Mixin в конфиг RSpec:**

```bash
git apply $P/r7b_mixin.patch && git commit -qam "Move ActiveJob::TestHelper into RSpec config"
```

**Шаг 2. Настройки копов:**

```bash
git apply $P/r7b_config.patch && git commit -qam "Configure four R7 cops by owner decision"
```

**Шаг 3. todo** — убрать блоки `cops_whole` и строки `cops_partial` конфига (блок без строк файлов уходит
целиком):

```bash
python3 -I - r7b <<'PY'
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
git commit -am "Drop R7b entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r7b

- Changed: RuboCop settings by owner decision, each with its reason in `.rubocop.yml`:
  Style/FormatStringToken keeps `unannotated`; Style/ClassAndModuleChildren excludes the five plugin
  files left compact by R4; Naming/PredicateMethod excludes `app/graphql/types/**` (resolvers named
  after schema fields); Style/OneClassPerFile excludes `plugin_schema_validator.rb`. Their entries
  (and the stale `lib/subdomain_routes.rb` one) left `.rubocop_todo.yml`.
- Changed: `ActiveJob::TestHelper` is included once in the RSpec configuration instead of at the top
  level of 13 spec files (Style/MixinUsage); the suite runs the same examples.
```

```bash
git commit -am "Note fork-updates-r7b in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R7B … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 15 файлов патчей (`.rubocop.yml`, `spec/rails_helper.rb`, 13 спек — только патчами),
  `.rubocop_todo.yml`, `CHANGELOG.md`. Новых файлов нет.
- `app/`, `lib/`, `config/`, `db/`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`.
- Блоки todo всех прочих копов и остальные строки `Naming/PredicateMethod` и `Style/OneClassPerFile`
  (их файлы — R7c/R7d и следующая веха).
- Никаких ручных правок, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R7B_CACHE=$HOME/.cache/chaskiq-r7b-ci bash docs/specs/fork-updates-r7b-probes/rspec_gate_r7b.sh'`

- **AC-002** — пути и конфиг: изменены ровно 15 файлов патчей, todo и CHANGELOG — каждый, с тем же git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патчей побайтно равен BASE с двумя патчами по порядку; todo = BASE без трёх блоков и без строк двух частичных блоков; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7b-probes/r7b_probe.py tree $B'`

- **AC-003** — mixin несущий, на копии HEAD: 15 спек, зависящих от ActiveJob::TestHelper (13 бывших с include и 2 без него), зелёные на дереве и на файлах BASE; каждый из 2 мутантов r7b_config.json (строка config.include удалена; ограничена type: :controller) роняет пример, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7B_CACHE=$HOME/.cache/chaskiq-r7b-ci bash docs/specs/fork-updates-r7b-probes/r7b_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у трёх копов вехи 0 офенсов во всём дереве, у двух частичных — 0 в файлах вехи; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; разрешённый конфиг даёт FormatStringToken EnforcedStyle unannotated; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7B_CACHE=$HOME/.cache/chaskiq-r7b-ci bash docs/specs/fork-updates-r7b-probes/r7b_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r7b-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит mixin меняет ровно 14 файлов спек = BASE + r7b_mixin; коммит настроек — только .rubocop.yml = BASE + r7b_config; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r7b после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7b-probes/r7b_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7b-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "be11737287bc84bbb4bae187247be51982bdcef9b0c54caf09149754d995adb6  docs/specs/fork-updates-r7b-probes/examples_base.txt" "6c66945c162827cd0b7c97ee9199b1dc6debd5f0a15f196e8887f5ff4c4b8487  docs/specs/fork-updates-r7b-probes/pending_allowed.txt" "d5cbe880c918c85d0a78b2c31ac7d2bee7f4ea120d2d1f870eb713f03b8d4530  docs/specs/fork-updates-r7b-probes/r7b_backlog_probe.sh" "ee13f5047bae86e30819013bb0620f19a115fe6096b8ccd868d499efd79ce6b3  docs/specs/fork-updates-r7b-probes/r7b_config.json" "c635825dda6bfac3a76370fca0723339bf81bafa576d9369839499a131488d37  docs/specs/fork-updates-r7b-probes/r7b_config.patch" "0c4671263aa9f9b1b9652d0721b1aac48779b1defe946f1755553f274b87b8e0  docs/specs/fork-updates-r7b-probes/r7b_mixin.patch" "532180fc427855aefeac6d0e6c916e8a09b64752220482b78757b925dfc374bf  docs/specs/fork-updates-r7b-probes/r7b_probe.py" "ee786d70bfe289018cd7be82e35ae90c57abd3694cf9b6096a003f729136f1e7  docs/specs/fork-updates-r7b-probes/r7b_sentinel.rb" "30a652269725025809acc5dc64cb2a7b4a325d6cc7e11172c52aa4ed83d30507  docs/specs/fork-updates-r7b-probes/r7b_tests.rb" "3e7bf42488ac44e5c4de6ea36c219e18781749e31e5ad13768bcfa21d85f97f7  docs/specs/fork-updates-r7b-probes/r7b_tests_gate.sh" "32314032e7d31f09e62b324d603ff40e250cbdabd0a82cba169ccb9fdbf3510d  docs/specs/fork-updates-r7b-probes/rspec_gate_r7b.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fork-updates-r7b-probes/source_scan.py" "a88700524901c3390aaf1445c07ba0a8df09b17d7de0cd47900cf2a8e32cdb2f  docs/specs/fork-updates-r7b-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный
(`R7B paths without the change` / `is not BASE + …`); AC-003 красный (тексты мутантов не найдены в
`spec/rails_helper.rb`); AC-004 красный (`… offenses left`); AC-006 красный (`missing commits`).

Пробный прогон автора (21.11.2026; свежий клон BASE 8e2ddd3d со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально; кэш — копия `chaskiq-fxb-ci`, путь кэша в командах подменён на копию):
- чистый клон: AC-001 (1059 примеров, 0 failures, 30 pending), AC-005, AC-007 (`SOURCE SCAN PASS 0 files`),
  AC-008, AC-009 — rc=0; AC-002, AC-003 (`B01: mutant text occurs 0 times`), AC-004 (`Style/MixinUsage: 13
  offenses left` и т. д.), AC-006 (`missing commits`) красные с сообщениями выше;
- после сборки: все 9 AC rc=0 — rspec 1059 примеров, 0 failures, 30 pending (≈ 6 мин); AC-003
  `R7B TREE PASS 183 examples`, `R7B BASE PASS 183 char / 0 renamed failing / 0 fix failing`,
  `R7B MUTANTS PASS 2/2 killed` (B01 — 78 упавших примеров, B02 — 2; ≈ 5 мин); AC-004 бэклог без todo
  1090 → 1042; AC-007 `SOURCE SCAN PASS 14 files`;
- порченые правки (все ловятся): `config.include …, type: :controller` → AC-002; опечатка в Exclude
  (`app/graphql/type/**/*`) → AC-002, AC-004 (`Naming/PredicateMethod: 9 offenses left`); лишняя строка,
  вынутая из todo (`segment_comparator.rb`) → AC-002, AC-005.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если код после ревью менялся). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r7b.md --exclude "docs/specs/fork-updates-r7b-probes/**" --context "chaskiq fork-updates-r7b: RuboCop R7 по решению владельца без правок app/lib — в .rubocop.yml с причиной FormatStringToken unannotated (0 офенсов при любом стиле), ClassAndModuleChildren Exclude 5 плагинных файлов (Twilio и ERB с binding), PredicateMethod Exclude app/graphql/types (резолверы полей схемы), OneClassPerFile Exclude plugin_schema_validator.rb; MixinUsage: 13 include ActiveJob::TestHelper верхнего уровня -> config.include в rails_helper (две спеки жили за счёт утечки в Object); полный сьют — тот же список примеров; 2 мутанта; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r7b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r7b-probes/**

Контекст ревьюеру: спека, которой глобальный `config.include ActiveJob::TestHelper` меняет поведение (тестовый
адаптер очередей вместо прежнего — job, который раньше исполнялся сразу); метод `app/graphql/types`, который
не резолвер поля; причина в `.rubocop.yml`, не совпадающая с фактом. Код править нельзя — замечание по месту
решает постановщик (раздел 9).

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 9 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r7b.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r7b.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после патчей
  AC-004/AC-005 красные — дефект спеки;
- полный сьют красный с патчем mixin (пример, которому глобальный `config.include` меняет поведение) —
  приложи вывод; сужать `config.include`, возвращать `include` в файлы или править спеки ЗАПРЕЩЕНО;
- мутант выжил — id и вывод (пробник или спеки BASE противоречат разделу 3 — дефект спеки);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл резолвер-не-поле в `app/graphql/types` или спеку, сломанную `config.include` — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, спек и `.rubocop.yml`, правка пробников, патчей и мутантов, `pending`/`skip`,
запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

- **R2b (`fork-updates-r2b`, qw2) — идёт сейчас.** Общие файлы: `.rubocop.yml` (R2b вставляет
  `Naming/MemoizedInstanceVariableName` перед `AllCops:`, эта веха — блок после `Rails/InverseOf`; хунки не
  пересекаются), `.rubocop_todo.yml` (разные блоки, удаление скриптом, не патчем) и `CHANGELOG.md` (обе
  вставляют блок после `# Changelog`). Код R2b (`Gemfile`, `app.rb`, `oauth_utils.rb`, `open_ai/api.rb`,
  `twilio/api.rb`) здесь не трогается. Проверено на 8e2ddd3d: четыре патча R2b и два патча этой вехи
  применяются в любом порядке.
- **fix-cleanup-3 (qw2) — идёт сейчас:** только `app/models/lead.rb`; общий — `CHANGELOG.md`.
- **R7c и R7d** (следующие спеки серии): общие только todo (разные блоки и разные строки `PredicateMethod` и
  `OneClassPerFile` — блок, оставшийся без строк, удаляет та веха, что вливается последней; пробник считает
  ожидаемое от BASE) и `CHANGELOG.md`.
- **Кто вливается вторым, тому — перенос BASE и `--write-base`** (раздел 2, п. 2): пробники todo и CHANGELOG
  считают ожидаемое от BASE, а снимки rspec — список примеров BASE.
- Четыре `Naming/PredicateMethod` (`segment_comparator.rb`, `slack/api.rb`, `zapier/api.rb`,
  `plugins/tar_downloader.rb`) — отдельная веха после решения координатора по двум командным методам
  (`receive_oauth_code`, `download_plugin`): имя с `?` у метода с побочными эффектами вводит в заблуждение.
