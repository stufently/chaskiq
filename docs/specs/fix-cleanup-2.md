# fix-cleanup-2 — четыре дефекта с приёмки fix-cleanup-bugs: тест «красный на BASE» на каждый

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fix-cleanup-2.md`; решения — план `docs/specs/fork-updates-rubocop-plan.md`,
  разделы «Вне бэклога: дефект Lead#verify!» и «Вне бэклога: находки Codex на приёмке fix-cleanup-bugs».
- BASE_SHA: `9032bd307a25e257717fbe7b269d216055b61b49` — HEAD `main` «Record mut-r5b2 acceptance» (после
  влития fix-cleanup-bugs и mut-r5b2; Ruby 4.0.10, Rails 8.1.4.1).
- BASE плавающий: если `main` уйдёт дальше до запуска, постановщик переносит его (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 7 КБ.
- Исполнитель: **Codex (`cx`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не
  зелёные — или пока не сработал пункт раздела 9.**
- Цель: **четыре правки поведения** (раздел 3), код каждой задан патчем постановщика (руками не
  править). Работа исполнителя — четыре НОВЫЕ спеки: одна характеризационная (зелёная на BASE и после) и
  три спеки фиксов — в каждой хотя бы один пример **красный на BASE** и все зелёные после патча; каждый
  из 11 мутантов постановщика (`fxc_config.json`, `mutants`) роняет пример. Четвёртый фикс (радиокнопка
  во фронтенде) — без спеки, AC-007. Каждый фикс — свой коммит; запись `Fixed` в CHANGELOG на каждый.
- RuboCop-копов эта веха не касается: `.rubocop_todo.yml` и `.rubocop.yml` не меняются.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Мутант убит, только если код с
мутантом **ведёт себя** иначе. AC-006 (`source_scan.py`) ищет эти приёмы в новых файлах `spec/`.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fix-cleanup-2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу
  заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-fxc2-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-fxc2-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` четырёх патчей по порядку (`fxc_lead`, `fxc_consent`,
   `fxc_dashboard`, `fxc_radio`); не применяется — пересобрать той же правкой (раздел 3) и `git diff`.
   Проверить тексты 11 мутантов (каждый ровно один раз в своём файле дерева после патчей) и что имена
   четырёх новых спек не заняты. Если менялся `spec/` — перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_FXC_CACHE=$HOME/.cache/chaskiq-fxc2-ci bash docs/specs/fix-cleanup-2-probes/rspec_gate_fxc.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 993 примера BASE 9032bd30.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE 9032bd30.

**(а) `fxc_lead.patch` — `app/models/lead.rb:4-14`, `Lead#verify!`.** Было
`if email.present? && (app_users = app.app_users.where(type: "AppUser", email: email))`, затем голая строка
`app_users.any?` (результат выброшен) и `clone_records_and_discard(app_users.first)`. Relation в условии
всегда истинна, поэтому лид с email, у которого в приложении нет AppUser с тем же email, уходит в
`clone_records_and_discard(nil)` и падает `NoMethodError: undefined method 'update' for nil` (`lead.rb:19`,
проверено на BASE). Стало `if email.present? && (app_user = app.app_users.find_by(type: "AppUser", email:
email))` и `clone_records_and_discard(app_user)`: такой лид идёт в ветку `else` — `becomes!(AppUser)`,
`type = "AppUser"`, `save` (как лид без email). Ветка совпадения не меняется: `clone_records_and_discard`
копирует атрибуты лида (кроме `id`, `created_at`, `updated_at`, `session_id`) в найденного AppUser,
пишет лиду событие `leads.verified` (`events.log` свойства не сохраняет — `concerns/eventable.rb:10`),
шлёт `user:refresh` и переносит разговоры лида на AppUser (`main_participant`); сам лид остаётся
записью типа `Lead`. Вызывающих `verify!` в `app/`, `lib/` нет (`git grep`), только `spec/models/app_user_spec.rb`.

**(б) `fxc_consent.patch` — `app/graphql/types/messenger_type.rb:37`, `needs_privacy_consent`.** Настройку
`privacy_consent_required` (`store_accessor` приложения, `app.rb:45`, без умолчания) UI сохраняет как
`"ue"` (`MessengerSettings.tsx:127`), а резолвер проверял только `"eu"`: для `"ue"` метод возвращал `nil`
(согласие не спрашивалось никогда). Стало `… if %w[eu ue].include?(privacy_consent_required)`: оба
значения дают `EuCountries.includes?(код страны)`. Сохранённые данные и фронтенд не трогаем — в базах уже
лежит `"ue"`.

**(в) `fxc_dashboard.patch` — `app/services/dashboard.rb:31`, `Dashboard#visits`.** После фикса Nightfury
(fix-cleanup-bugs) `get_all` удалённого ряда — `nil`, а `visits` зовёт на нём `.map`. Конструктор ряда сам
создаёт мету (`time_series.rb:21`), поэтому `nil` бывает, только когда ряд удалён после создания объекта
(`Identity#delete` между созданием и чтением). Стало `(… .get_all || {}).map`: удалённый ряд — `[]`.
В спеке это моделируется подменой `AppIdentity.new(app.key)` объектом, чей ряд `visits` удалён.

**(г) `fxc_radio.patch` — `app/javascript/src/pages/MessengerSettings.tsx:153`.** Радиокнопка «none»
сохраняет `'none'`, а `defaultChecked` сравнивал `privacyConsentRequired === ''` — после сохранения «none»
не была отмечена ни одна кнопка; не была отмечена и при незаданной настройке (`null`). Бэкенд считает «нет
согласия» и пустое значение, и `"none"` (`messenger_type.rb:33`). Стало: отмечена, когда значение пустое
или `'none'`. JS-юнит-тестов, запускаемых в Docker, в проекте нет (в `package.json` ни jest, ни vitest;
`spec/cypress` — e2e на полном стенде), поэтому проверка — AC-007 (grep) и побайтное равенство патчу (AC-002).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 9032bd30:

1. Образцы четырёх спек постановщика (содержание — раздел 5): на BASE характеризационная зелёная, в каждой
   из трёх спек фиксов есть красный пример по нужной причине — `NoMethodError: undefined method 'update'
   for nil` (verify!), `expected true got nil` / `expected false got nil` (`ue`), `undefined method 'map'
   for nil` (Dashboard); на дереве — все 8 примеров зелёные.
2. 11/11 мутантов убито поведением (неверный тип записи после `verify!`, чужой AppUser изменён, `nil` вместо
   `true`, исключение, пустой список вместо визитов).
3. Патчи применяются к BASE, поверх четырёх патчей R3b-2 и наоборот (общий файл `messenger_type.rb`: тут
   строка 37, там ~50); мутанты mut-fxb (37 патчей) применяются поверх собранного дерева этой вехи.
4. `Event` лида с `leads.verified` создаётся без свойств (`Eventable#log` пишет `properties: {}`) — в
   спеке проверяй событие по `lead.events.where(action: "leads.verified")`, не по свойствам.
5. Черновик ровно по разделу 5: итоги — раздел 7.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код — **только** `git apply` патчей. В каждой спеке
`# frozen_string_literal: true`, `require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:`
директив, чтения исходников (раздел 1). Лид в спеках: `visitor = app.add_anonymous_user({})`,
`visitor.update!(attrs)`, `visitor.become_lead!`, затем `Lead.find(visitor.id)`. Перед шагом 1:

```bash
P=docs/specs/fix-cleanup-2-probes
export CHASKIQ_FXC_CACHE=$HOME/.cache/chaskiq-fxc2-ci
```

**Шаг 1. Характеризационная спека** `spec/models/lead_verify_spec.rb` (`RSpec.describe Lead`), код = BASE:
- в приложении сначала AppUser `app.add_user(email: "other@test.cl")`, затем `user = app.add_user(email:
  "a@test.cl")` с `country` `"chile"`; лид с email `"a@test.cl"` и `country` `"peru"` и его разговор
  (`app.start_conversation(message: { text_content: "hi" }, from: lead)`); `lead.verify!` →
  `user.reload.country == "peru"`, `main_participant_id` разговора — `user.id`, у лида ровно одно событие
  `leads.verified`;
- в приложении AppUser без email (`app.add_anonymous_user({})` и `update_column(:type, "AppUser")`); лид без
  email, `verify!` → `AppUser.find(lead.id).type == "AppUser"`, событий `leads.verified` у лида нет.

```bash
git add spec/models/lead_verify_spec.rb
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 1 files
git commit -m "Pin Lead#verify! branches"
```

**Шаг 2. verify! без совпадения.** Спека `spec/models/lead_verify_unmatched_spec.rb` (`RSpec.describe Lead`):
другое приложение с AppUser `"a@test.cl"` (`foreign`); в своём приложении — лид с email `"a@test.cl"` и
ни одного AppUser с ним → `expect { lead.verify! }.not_to raise_error`, `AppUser.find(lead.id).type ==
"AppUser"`, `foreign.reload.app_id` — id другого приложения.

```bash
git apply $P/fxc_lead.patch
git add spec/models/lead_verify_unmatched_spec.rb
git commit -qam "Verify a lead with no matching user"
```

**Шаг 3. Настройка `ue`.** Спека `spec/graphql/types/messenger_consent_ue_spec.rb`
(`RSpec.describe Types::MessengerType`): `app.update!(privacy_consent_required: setting)`, пользователь
`app.add_user(email:)` без согласия; тип —
`described_class.send(:new, app, { set_locale: -> {}, get_app_user: -> { user }, request: double(location: loc) })`,
где `loc` — `double(country_code: code)` или `nil`; вызов `needs_privacy_consent`:
- `"ue"`: `"DE"` → ровно `true`; `"US"` → ровно `false`; место неизвестно → ровно `false`;
- `"eu"`: `"FR"` → ровно `true`.

```bash
git apply $P/fxc_consent.patch
git add spec/graphql/types/messenger_consent_ue_spec.rb
git commit -qam "Accept the ue privacy consent setting"
```

**Шаг 4. Dashboard.** Спека `spec/services/dashboard_visits_spec.rb` (`RSpec.describe Dashboard`),
`range = { from: "2023-11-01", to: "2023-11-30" }`, в `after` — `AppIdentity.new(app.key).delete`:
- `AppIdentity.new(app.key).visits.incr(1, Time.zone.at(1_700_000_040))` →
  `described_class.new(app: app, range: range).visits == [{ day: "2023-11-14", value: 1 }]`;
- `identity = AppIdentity.new(app.key)`, `identity.visits.delete`,
  `allow(AppIdentity).to receive(:new).with(app.key).and_return(identity)` → `visits == []`.

```bash
git apply $P/fxc_dashboard.patch
git add spec/services/dashboard_visits_spec.rb
git commit -qam "Guard Dashboard#visits for a deleted series"
```

**Шаг 5. Радиокнопка «none».** Только патч, без спеки:

```bash
git apply $P/fxc_radio.patch
git commit -qam "Check the none consent radio when saved"
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/fxc_tests_gate.sh $B` (≈ 1–3 мин). Нужны три
строки: `FXC TREE PASS … examples`, `FXC BASE PASS 2 char / 3 fix failing` (число char-примеров — твоё),
`FXC MUTANTS PASS 11/11 killed`. Пример красный на дереве, спека фикса зелёная на BASE или мутант
выжил — поправь спеку (код, патчи и мутантов не трогать; убийство — только поведением), не добавляя
новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Pin Lead#verify! branches$')
mkdir -p tmp/fxc-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/fxc-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/fxc-specs (tmp/ игнорируется)
# поправь спеки в tmp/fxc-specs/spec/…, затем: cp -r tmp/fxc-specs/spec/. spec/
# затем — команды шагов 1–5 (каждый шаг добавляет только свою спеку), затем снова шаг 6
```

**Шаг 7. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fix-cleanup-2

- Fixed: `Lead#verify!` of a lead whose email no app user of the app has turns the lead into an app
  user (it called `clone_records_and_discard(nil)` and raised `NoMethodError`).
- Fixed: `needs_privacy_consent` honours the "ue" setting that the messenger settings UI saves (only
  "eu" was checked, so EU consent was never asked); both values are accepted.
- Fixed: `Dashboard#visits` returns no visits instead of raising when the visits series was deleted.
- Fixed: the "none" privacy consent radio in the messenger settings is checked when the saved value
  is "none" or unset (it compared with an empty string).
```

```bash
git commit -am "Note fix-cleanup-2 in changelog"
```

**Шаг 8.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 9.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`FXC … PASS`; AC-006 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме четырёх файлов кода (`lead.rb`, `messenger_type.rb`, `dashboard.rb`, `MessengerSettings.tsx`,
  только патчами), четырёх новых спек и `CHANGELOG.md`.
- `.rubocop.yml`, `.rubocop_todo.yml`, гемы, `Gemfile*`, `package.json`, `yarn.lock`, `.ruby-version`,
  `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `vendor/`, существующие спеки (в том числе
  `app_user_spec.rb`, `messenger_privacy_consent_spec.rb`).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, чтения исходников в спеках, JS-тестовых
  обвязок.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_FXC_CACHE=$HOME/.cache/chaskiq-fxc2-ci bash docs/specs/fix-cleanup-2-probes/rspec_gate_fxc.sh'`

- **AC-002** — пути и код: изменены ровно 4 файла кода, 4 новых файла спек (новые обычные файлы) и CHANGELOG — каждый; todo и .rubocop.yml не тронуты; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с четырьмя патчами по порядку; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-2-probes/fxc_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 4 файлов зелёные на коде дерева; на коде BASE характеризационная спека зелёная, в каждой из 3 спек фиксов есть упавший пример; ошибок вне примеров нет; каждый из 11 мутантов fxc_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_FXC_CACHE=$HOME/.cache/chaskiq-fxc2-ci bash docs/specs/fix-cleanup-2-probes/fxc_tests_gate.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, todo BASE, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-fxc2-ci bin/ci-local --only rubocop'`

- **AC-005** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно свою спеку при коде BASE; каждый коммит фикса оставляет файлы кода = BASE + патчи до своего включительно и добавляет ровно свою спеку (радиокнопка — без спеки); коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fix-cleanup-2 (не меньше четырёх строк «- Fixed: ») после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-2-probes/fxc_probe.py commits $B'`

- **AC-006** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-2-probes/source_scan.py $B'`

- **AC-007** — фронтенд и значения настройки: в MessengerSettings.tsx нет сравнения privacyConsentRequired с пустой строкой, радиокнопка none отмечается по значению none; в lead.rb нет голой строки app_users.any?; резолвер согласия принимает eu и ue (сбой grep — FAIL).
  `bash -c 'T=app/javascript/src/pages/MessengerSettings.tsx && n=$(grep -cP "privacyConsentRequired === \x27\x27" $T || [ $? -eq 1 ]) && test "$n" = 0 && grep -qP "privacyConsentRequired === \x27none\x27" $T && a=$(grep -cE "^[[:space:]]*app_users\.any\?[[:space:]]*$" app/models/lead.rb || [ $? -eq 1 ]) && test "$a" = 0 && grep -qF "%w[eu ue].include?(privacy_consent_required)" app/graphql/types/messenger_type.rb'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "ed216a0a6c334f0c1b49b5270205ef50738acd74387e3b401886a7ccef0d35a7  docs/specs/fix-cleanup-2-probes/fxc_probe.py" "8ca6126f1896e9daea9872e9f075748f778dd73b5e107bcfe055b056fd685621  docs/specs/fix-cleanup-2-probes/fxc_config.json" "8bc45b656951bbc71feebd0f7364ce5fbff0becca48e0c05583d4e45ff9dcebb  docs/specs/fix-cleanup-2-probes/fxc_tests.rb" "f85c0c6daff93cfac0756a1243a526798b1a2b112f02e6f2a90eaa09730a1ba1  docs/specs/fix-cleanup-2-probes/fxc_tests_gate.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fix-cleanup-2-probes/source_scan.py" "ed4c7fb6c7ea075b1f0429cd2f12daac3d4b9a5b0db771da7d3db416a86df8c5  docs/specs/fix-cleanup-2-probes/fxc_lead.patch" "211793c3140f8f161e13e1e4194864f8b8b6f95b8edf36c25cc732b242bf5933  docs/specs/fix-cleanup-2-probes/fxc_consent.patch" "84520b2e92a09ddaf4a68bbc46e6b65e9011c640204d40f1f1e37e37f7cc5395  docs/specs/fix-cleanup-2-probes/fxc_dashboard.patch" "8efeb5eec0889ed1e006852d73707f1e0dfb60044a53c3a232dcbbde43da02de  docs/specs/fix-cleanup-2-probes/fxc_radio.patch" "d5ab4b772bd006aa3695bf15c7461002e78a54aae314104247d3624e11ff5b66  docs/specs/fix-cleanup-2-probes/rspec_gate_fxc.sh" "692f347c2d4f96493ff00e9c9858947c1b145713b254dc7f38afec4d281baa88  docs/specs/fix-cleanup-2-probes/fxc_sentinel.rb" "5d2ff9eda9a6a9e75a221d943fdd47dbbc3d20c766b512f1aac2411d2f093f45  docs/specs/fix-cleanup-2-probes/examples_base.txt" "f72a78123496f11047fe0f5ce5e016ef6ffb3b05e0ec3355d6eee18de97a93a2  docs/specs/fix-cleanup-2-probes/pending_allowed.txt" "9d2c258e2aad7ccd3fe4ffd9f550839644307dbd03f054374f5a58f52df3813a  docs/specs/fix-cleanup-2-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-004, AC-006, AC-008, AC-009 зелёные; AC-002 красный
(`fix-cleanup-2 paths without the change: …`); AC-003 красный (спек нет — `no examples ran`); AC-005
красный (`missing commits`); AC-007 красный (`=== ''` и `app_users.any?` на BASE).

Пробный прогон автора (21.11.2026; свежий клон `main` 9032bd30 со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия `chaskiq-fxb-ci`):
- чистый клон: AC-001 (993 примера, 0 failures, 30 pending), AC-004, AC-006, AC-008, AC-009 — rc=0; AC-002,
  AC-005, AC-007 красные с сообщениями выше; AC-003 красный (тексты мутантов на BASE не найдены, спек нет);
- после сборки: все 9 AC rc=0 — rspec 1001 пример (8 новых), 0 failures, 30 pending; AC-003
  `FXC TREE PASS 8 examples`, `FXC BASE PASS 2 char / 3 fix failing`, `FXC MUTANTS PASS 11/11 killed` (≈ 1 мин);
  AC-006 `SOURCE SCAN PASS 4 files`; файлов от root нет;
- порченые правки (все ловятся): ручная строка в `lead.rb` → AC-002; спека с
  `File.read(Rails.root.join("app/models/lead.rb"))` → AC-006; без коммита радиокнопки → AC-002, AC-005,
  AC-007; характеризационная спека без AppUser, созданного раньше совпадающего → AC-003 (`F07 survived`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Codex,
поэтому пара — agy и Qwen); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fix-cleanup-2.md --exclude "docs/specs/fix-cleanup-2-probes/**" --context "chaskiq fix-cleanup-2: четыре фикса поведения патчами постановщика — Lead#verify! без подходящего AppUser становится AppUser (было clone_records_and_discard(nil)), needs_privacy_consent принимает eu и ue (UI сохраняет ue), Dashboard#visits для удалённого ряда даёт [], радиокнопка none в MessengerSettings.tsx отмечается по значению none или пустому; 1 характеризационная спека и 3 спеки фиксов, красные на BASE; 11 мутантов; спеки не читают исходники как текст; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fix-cleanup-2.md
REVIEW_EXCLUDE: docs/specs/fix-cleanup-2-probes/**

Контекст ревьюерам: найти вызывающего `verify!`, которому нужен был клон в первого AppUser без совпадения
email; место, где `ue`/`eu` или пустая настройка читаются иначе (мессенджер, GraphQL `privacyConsentRequired`);
вызывающего `Dashboard#visits`, которому мешает `[]`; поломку формы настроек от новой проверки `defaultChecked`;
спеку, которая проверяет текст, а не поведение, или красна на BASE не по той причине. Код править нельзя —
замечание по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fix-cleanup-2.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "codex", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>", "<квитанция qwen>"],
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fix-cleanup-2.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004 красный — дефект спеки;
- характеризационный пример не может быть зелёным на BASE или пример фикса не может быть красным на
  BASE, проверяя описанное в разделе 5 поведение — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл вызывающего или путь, который фикс ломает — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, JS-тестовые обвязки, глушить вывод и коды возврата.

## 10. Стыки

- **R3b-2 — идёт параллельно (qw2).** Общий файл — `app/graphql/types/messenger_type.rb`: там строка ~50
  (`order`), здесь 37. Проверено на 9032bd30: `fxc_consent.patch` применяется поверх четырёх патчей R3b-2 и
  наоборот; мутант R3b-2 в этом файле (`.order(updated_at: :desc)`) этой вехой не задет. Вторая влитая из
  двух вех получает перенос BASE и `--write-base`, если перезапуск нужен.
- **mut-fxb — может идти параллельно (qw2).** Его мутанты `needs_privacy_consent` не трогают строку 37
  (патчи `-U1`); все 37 его патчей применяются поверх дерева этой вехи; его тесты используют только
  настройку `eu`.
- **Решения плана, которые веха НЕ трогает:** `GB` в `EuCountries` остаётся; мета Nightfury со score 0 и
  `get_padded_range` после `delete` — не чиним.
