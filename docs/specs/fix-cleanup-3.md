# fix-cleanup-3 — два дефекта Lead#verify! с приёмки fix-cleanup-2: тест «красный на BASE» на каждый

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fix-cleanup-3.md`; решения — план `docs/specs/fork-updates-rubocop-plan.md`,
  раздел «Вне бэклога: находки Codex на приёмке fix-cleanup-2».
- BASE_SHA: `a631554ca85cb5175b29096f83ae2db330ec54e4` — HEAD `main` «Record mut-fxb acceptance» (после
  влития fix-cleanup-2, R3b-2 и mut-fxb; Ruby 4.0.10, Rails 8.1.4.1).
- BASE плавающий: если `main` уйдёт дальше до запуска, постановщик переносит его (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 4 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не
  зелёные — или пока не сработал пункт раздела 9.**
- Цель: **две правки поведения** в `app/models/lead.rb` (раздел 3), код каждой задан патчем постановщика
  (руками не править). Работа исполнителя — две НОВЫЕ спеки, каждая коммитится ДО своего фикса и **красная
  на BASE по причине самого дефекта** (провал ожидания, а не исключение), зелёная после патча; каждый из 7
  мутантов постановщика (`fxd_config.json`, `mutants`) роняет пример. Каждый фикс — свой коммит; запись
  `Fixed` в CHANGELOG на каждый.
- RuboCop-копов эта веха не касается: `.rubocop_todo.yml` и `.rubocop.yml` не меняются.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Сравнение `to_sql` с текстом тоже не убийство. Мутант убит, только если код
с мутантом **ведёт себя** иначе: другой тип записи, другой пользователь получил данные. AC-006
(`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fix-cleanup-3`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу
  заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-fxc3-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-fxc3-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` двух патчей по порядку (`fxd_type`, `fxd_order`); не применяется —
   пересобрать той же правкой (раздел 3). Проверить тексты 7 мутантов (каждый ровно один раз в
   `lead.rb` после патчей) и что имена двух новых спек не заняты. Если менялся `spec/` — перегенерировать
   снимки на чистом checkout `main`:
   `CHASKIQ_FXD_CACHE=$HOME/.cache/chaskiq-fxc3-ci bash docs/specs/fix-cleanup-3-probes/rspec_gate_fxd.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1051 пример BASE a631554c.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE a631554c, файл `app/models/lead.rb` (единственный файл кода вехи).

**(а) `fxd_type.patch` — строка 15, `Lead#clone_records_and_discard`.** Было
`deep_clone.attributes.except("id", "created_at", "updated_at", "session_id")`: в копируемых атрибутах
остаётся `type` (`"Lead"`), и `app_user.update(attributes)` переписывает тип найденного AppUser на `Lead` —
после слияния настоящий пользователь становится лидом (проверено на BASE: `user.reload.type == "Lead"`).
Повторный `verify!` того же лида уже не находит AppUser с этим email и уходит в ветку `else` — превращает
сам лид в AppUser. Стало `.except(…, "session_id", "type")`: тип цели не меняется, повторный `verify!`
снова сливает лид в того же AppUser, сам лид остаётся записью типа `Lead`.

**(б) `fxd_order.patch` — строка 5, `Lead#verify!`.** Было
`app.app_users.find_by(type: "AppUser", email: email)` — `LIMIT 1` без `ORDER BY`. Уникальности email в
приложении нет (ни индекса, ни валидации), при дублях PostgreSQL отдаёт первую попавшуюся строку
физического порядка (проверено: после `update_column` строки «переезжают» в конец таблицы, и `find_by`
возвращает бо́льший id). Стало `app.app_users.where(type: "AppUser", email: email).order(:id).first` — всегда
пользователь с меньшим id (как до fix-cleanup-2 у `where(...).first`). Примечание: `where(...).first`
без `order` в ActiveRecord тоже сортирует по первичному ключу, поэтому такая замена — эквивалентный мутант, в
список не входит; `take` (поведение BASE) — входит (D02).

Вызывающих `verify!` в `app/`, `lib/` нет (`git grep`), только спеки `spec/models/lead_verify*_spec.rb` и
`spec/models/app_user_spec.rb` — они должны остаться зелёными (AC-001).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE a631554c:

1. Образцы двух спек постановщика (содержание — раздел 5): на BASE обе красные по причине дефекта —
   `expected: "AppUser" got: "Lead"` (тип цели) и `expected: "peru" got: "chile"` (выбран бо́льший id); на
   дереве — оба примера зелёные.
2. 7/7 мутантов убито поведением; `where(...).first` вместо `.order(:id).first` выжил как эквивалентный
   (неявный `ORDER BY id`) и заменён на `take`.
3. Патчи применяются к BASE, поверх двух патчей R3b-3 (`r3b3_path`, `r3b3_iframe`) и наоборот — общих
   файлов кода нет (раздел 10).
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение (подтверждено на этом образе, но это свойство планировщика PostgreSQL 14): на маленькой
таблице `find_by` по email идёт seq scan или index scan по `index_app_users_on_email`; в обоих случаях
строка, обновлённая позже, читается позже. Если пример дублей окажется зелёным на BASE — раздел 9.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код — **только** `git apply` патчей. В каждой спеке
`# frozen_string_literal: true`, `require "rails_helper"`, `RSpec.describe Lead`,
`let(:app) { FactoryBot.create(:app) }`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения
исходников (раздел 1). Лид: `visitor = app.add_anonymous_user({})`, `visitor.update!(attrs)`,
`visitor.become_lead!`, затем `Lead.find(visitor.id)` (как в `spec/models/lead_verify_spec.rb`). Второго
AppUser с тем же email через `app.add_user` не создать (он найдёт существующую запись) — создавай с другим
email и затем `update_column(:email, "a@test.cl")`. Перед шагом 1:

```bash
P=docs/specs/fix-cleanup-3-probes
export CHASKIQ_FXD_CACHE=$HOME/.cache/chaskiq-fxc3-ci
```

**Шаг 1. Спека типа цели** `spec/models/lead_merge_type_spec.rb`, код = BASE (коммит без фикса — спека
на нём красная, так и задумано). Один пример, по порядку:
- СНАЧАЛА лид с email `"a@test.cl"` и `country` `"peru"`; ПОТОМ `user = app.add_user(email: "b@test.cl",
  country: "chile")` и `user.update_column(:email, "a@test.cl")` (у лида id меньше, чем у пользователя);
- `lead.verify!` → ПЕРВАЯ проверка `expect(user.reload.type).to eq("AppUser")`, затем `user.country ==
  "peru"`, `AppUser.find(lead.id).type == "Lead"`;
- повторный `Lead.find(lead.id).verify!` → `user.reload.type == "AppUser"`, `AppUser.find(lead.id).type ==
  "Lead"`, у лида ровно 2 события `lead.events.where(action: "leads.verified")`.

```bash
git add spec/models/lead_merge_type_spec.rb
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 1 files
git commit -m "Pin the lead merge target type"
```

**Шаг 2. Фикс типа.**

```bash
git apply $P/fxd_type.patch
git commit -qam "Keep the user type on lead merge"
```

**Шаг 3. Спека дублей** `spec/models/lead_verify_duplicate_spec.rb`, один пример, по порядку:
`older = app.add_user(email: "one@test.cl", country: "chile")`, `newer = app.add_user(email: "two@test.cl",
country: "chile")`; затем СНАЧАЛА `newer.update_column(:email, "a@test.cl")`, ПОТОМ
`older.update_column(:email, "a@test.cl")` (так без `ORDER BY` первой читается строка `newer`); лид с email
`"a@test.cl"` и `country` `"peru"`, его разговор `app.start_conversation(message: { text_content: "hi" },
from: lead)`; `lead.verify!` → ПЕРВАЯ проверка `expect(older.reload.country).to eq("peru")`, затем
`newer.reload.country == "chile"`, `main_participant_id` разговора (`reload`) — `older.id`.

```bash
git add spec/models/lead_verify_duplicate_spec.rb
git commit -m "Pin the duplicate user choice"
```

**Шаг 4. Фикс порядка.**

```bash
git apply $P/fxd_order.patch
git commit -qam "Merge a lead into the oldest user"
```

**Шаг 5. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/fxd_tests_gate.sh $B` (≈ 1–2 мин). Нужны три
строки: `FXD TREE PASS 2 examples` (или больше), `FXD BASE PASS 2 fix failing for the defect`,
`FXD MUTANTS PASS 7/7 killed`. Пример красный на дереве, спека зелёная на BASE или красная не по той причине
(«wrong reason»), мутант выжил — поправь спеку (код, патчи и мутантов не трогать; убийство — только
поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Pin the lead merge target type$')
mkdir -p tmp/fxd-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/fxd-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/fxd-specs (tmp/ игнорируется)
# поправь спеки в tmp/fxd-specs/spec/…, затем: cp -r tmp/fxd-specs/spec/. spec/
# затем — команды шагов 1–4 (каждый шаг добавляет только свою спеку), затем снова шаг 5
```

**Шаг 6. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fix-cleanup-3

- Fixed: `Lead#verify!` no longer turns the matching app user into a lead: the merge copied the lead's
  `type` attribute onto the user, and a repeated `verify!` then converted the lead itself.
- Fixed: `Lead#verify!` merges into the matching app user with the smallest id when several app users
  of the app share the email (`find_by` without an order picked an arbitrary row).
```

```bash
git commit -am "Note fix-cleanup-3 in changelog"
```

**Шаг 7.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 8.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`FXD … PASS`; AC-006 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `app/models/lead.rb` (только двумя патчами), двух новых спек и `CHANGELOG.md`.
- `.rubocop.yml`, `.rubocop_todo.yml`, гемы, `Gemfile*`, `package.json`, `yarn.lock`, `.ruby-version`,
  `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `vendor/`, существующие спеки (в том числе
  `lead_verify_spec.rb`, `lead_verify_unmatched_spec.rb`, `app_user_spec.rb`).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, чтения исходников в спеках.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_FXD_CACHE=$HOME/.cache/chaskiq-fxc3-ci bash docs/specs/fix-cleanup-3-probes/rspec_gate_fxd.sh'`

- **AC-002** — пути и код: изменены ровно lead.rb, 2 новых файла спек (новые обычные файлы) и CHANGELOG — каждый; todo и .rubocop.yml не тронуты; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; lead.rb побайтно равен BASE с двумя патчами по порядку; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-3-probes/fxd_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 2 спек зелёные на коде дерева; на коде BASE в каждой спеке есть пример, упавший на ожидании с текстом дефекта (base_reason из fxd_config.json), ошибок вне примеров нет; каждый из 7 мутантов fxd_config.json (текст найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_FXD_CACHE=$HOME/.cache/chaskiq-fxc3-ci bash docs/specs/fix-cleanup-3-probes/fxd_tests_gate.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, todo BASE, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-fxc3-ci bin/ci-local --only rubocop'`

- **AC-005** — каждый коммит отдельно, ровно в порядке раздела 5: коммит спеки добавляет ровно свою спеку при коде до своего фикса; коммит фикса применяет ровно свой патч и ничего не добавляет; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fix-cleanup-3 (не меньше двух строк «- Fixed: ») после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-3-probes/fxd_probe.py commits $B'`

- **AC-006** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-3-probes/source_scan.py $B'`

- **AC-007** — в lead.rb нет find_by, выбор пользователя — where по типу и email с order(:id).first, type исключён из копируемых атрибутов (сбой grep — FAIL).
  `bash -c 'L=app/models/lead.rb && n=$(grep -c "find_by" $L || [ $? -eq 1 ]) && test "$n" = 0 && grep -qF "app.app_users.where(type: \"AppUser\", email: email).order(:id).first" $L && grep -qF "\"session_id\", \"type\")" $L'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "08967ed541caec47751cb83070d75a3b4d946df5e615d70519c8a1ebd2b7a0ab  docs/specs/fix-cleanup-3-probes/fxd_probe.py" "1ed99d5a90499ea4023f0aa5bf715610755a040c8b3cc323b1455a3232abf5df  docs/specs/fix-cleanup-3-probes/fxd_config.json" "9197efe36d632893dceb53a905b9145a5676787b5e0a3555380c2494bb1a09f9  docs/specs/fix-cleanup-3-probes/fxd_tests.rb" "bdd27f8c9be4c6311130485b4ada559ea2207eb43a8df0a22903503252540784  docs/specs/fix-cleanup-3-probes/fxd_tests_gate.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fix-cleanup-3-probes/source_scan.py" "20a84abd058f5f16d36438720682e9e4cdd5350682972034cc2b836baec2b58b  docs/specs/fix-cleanup-3-probes/fxd_type.patch" "ab1f038101eabdcb3f55b82820a43b39c3c0601de3003bd9ede50585e8181b71  docs/specs/fix-cleanup-3-probes/fxd_order.patch" "dfa510a574dd1d79f99aa5793344a445d1f5c67388934337719e22968bb7ae9d  docs/specs/fix-cleanup-3-probes/rspec_gate_fxd.sh" "39164c92c878ca60193824285421edb6d5298c05022512ea05a954d59cbc4109  docs/specs/fix-cleanup-3-probes/fxd_sentinel.rb" "8e31edd84bb61503b519b157dacb96e47b4acc4ff55820e73497d209fb3f1b5f  docs/specs/fix-cleanup-3-probes/examples_base.txt" "926162de991d184e8db868d462b90c9b5c809c3d5d32d1893fdf7202ce421f7e  docs/specs/fix-cleanup-3-probes/pending_allowed.txt" "734b97928f3e3092e9c0c4436bbbc02efad4c647f8cefa8603c6aad6e339ee4f  docs/specs/fix-cleanup-3-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-004, AC-006, AC-008, AC-009 зелёные; AC-002 красный
(`fix-cleanup-3 paths without the change: …`); AC-003 красный (тексты мутантов не найдены, спек нет);
AC-005 красный (`missing commits`); AC-007 красный (`find_by` на BASE).

Пробный прогон автора (21.11.2026; свежий клон BASE a631554c со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия `chaskiq-fxb-ci`):
- чистый клон: AC-004, AC-006 (`SOURCE SCAN PASS 0 files`), AC-008, AC-009 — rc=0; AC-002, AC-003, AC-005,
  AC-007 красные с сообщениями выше (AC-001 = снимок `--write-base` на BASE: 1051 пример, 0 failures);
- после сборки: все 9 AC rc=0 — rspec 1053 примера (2 новых), 0 failures, 30 pending (≈ 7 мин); AC-003
  `FXD TREE PASS 2 examples`, `FXD BASE PASS 2 fix failing for the defect`, `FXD MUTANTS PASS 7/7 killed`
  (≈ 35 с); AC-006 `SOURCE SCAN PASS 2 files`;
- порченые правки (все ловятся): `File.read(Rails.root.join("app/models/lead.rb"))` в спеке → AC-006; ручная
  строка в `lead.rb` → AC-002, AC-005; без коммита CHANGELOG → AC-005; спека дублей с `update_column` в
  естественном порядке (сначала `older`) → AC-003 («no example fails on BASE», выжил D02).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если код после ревью менялся). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fix-cleanup-3.md --exclude "docs/specs/fix-cleanup-3-probes/**" --context "chaskiq fix-cleanup-3: два фикса Lead#verify! патчами постановщика — clone_records_and_discard больше не копирует type (найденный AppUser оставался лидом), выбор AppUser при дублях email — where(...).order(:id).first вместо find_by без порядка; две спеки, каждая закоммичена до фикса и красная на BASE по причине дефекта; 7 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fix-cleanup-3.md
REVIEW_EXCLUDE: docs/specs/fix-cleanup-3-probes/**

Контекст ревьюеру: найти вызывающего `verify!`/`clone_records_and_discard`, которому нужен был перенос `type`
или выбор не самого старого пользователя; спеку, которая проверяет текст, а не поведение, или красна на BASE
не по той причине. Код править нельзя — замечание по месту решает постановщик (раздел 9); спеки — можно,
одним заходом.

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
  "spec_sha256": "<sha256 файла docs/specs/fix-cleanup-3.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fix-cleanup-3.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004 красный — дефект спеки;
- пример не может быть красным на BASE по причине дефекта (ожидание из раздела 5), проверяя описанное
  поведение — приложи вывод (в том числе если PostgreSQL отдаёт дубли в порядке id и на BASE);
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл вызывающего или путь, который фикс ломает — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды
возврата.

## 10. Стыки

- **R3b-3 (`fork-updates-r3b3`, qw2) — может идти параллельно.** Её файлы кода —
  `api/v1/hooks/provider_controller.rb`, `application_controller.rb`, `concerns/package_iframe_behavior.rb`;
  здесь — только `lead.rb`. Общий файл — `CHANGELOG.md` (оба вставляют блок после `# Changelog`; второй влитой
  вехе — перенос BASE). Проверено на a631554c: два патча R3b-3 и два патча этой вехи применяются в любом
  порядке.
- **R2b (`fork-updates-r2b`, qw2) — может идти параллельно.** Общих файлов кода нет (там `app.rb`,
  `oauth_utils.rb`, `open_ai/api.rb`, `twilio/api.rb`, `Gemfile`, `.rubocop.yml`, todo); общий — `CHANGELOG.md`.
- Мутационный прогон по двум спекам этой вехи — у противоположного исполнителя (cx), после снятия запрета
  на Codex 2026-11-22 11:39Z.
