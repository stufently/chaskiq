# mut-fxb — отдельный мутационный прогон по новым тестам fix-cleanup-bugs

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/mut-fxb.md`, пробники — `docs/specs/mut-fxb-probes/`.
  Проверяемая веха — `docs/specs/fix-cleanup-bugs.md` (влита коммитом «Merge fix-cleanup-bugs», код —
  `8186b5e8..4a570bbf`).
- BASE_SHA: `9032bd307a25e257717fbe7b269d216055b61b49` — HEAD `main` «Record mut-r5b2 acceptance» (после
  влития fix-cleanup-bugs и mut-r5b2).
- BASE плавающий: постановщик переносит строку BASE_SHA на коммит, которым кладёт эту спеку в `main`,
  и только потом снимает клон (раздел 2). Команды критериев считают `B=$(git merge-base HEAD @{u})`
  сами. В `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в
  `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`).
- Исполнитель: **Qwen Code (`qw2`)** (fix-cleanup-bugs писал Codex — мутации у противоположного
  исполнителя). **Не останавливайся, пока все восемь критериев раздела 7 не зелёные — или пока не
  сработал пункт раздела 9.**
- Цель: каждый из 37 мутантов таблицы `kill_table.json` убит **поведенческим** тестом (только новые
  файлы под `spec/`, боевой код равен BASE). Мутанты — новые, не повторяют 21 мутант гейта
  fix-cleanup-bugs (`fix-cleanup-bugs-probes/fxb_config.json`, `M01`–`M21`). Эквивалентные постановщик
  уже исключил (раздел 3); **исполнитель эквивалентность не объявляет.** Убийство проверяет пробник сам:
  прикладывает патч из `docs/specs/mut-fxb-probes/patches/` (не из файлов исполнителя) к копии HEAD и
  гоняет спеки, которые исполнитель записал в манифест.

### Правило: тест проверяет поведение, а не текст кода (обязательно, без исключений)

**Чтение исходников как текста запрещено и убийством мутанта не считается.** Нельзя:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines`/`Pathname` любых путей,
`Dir.glob`, `method(...).source_location`, `.source`, `RubyVM`, `Ripper`, `Prism`, `__FILE__`,
`__dir__`, `ObjectSpace`, `Rails.application.root`, `$LOADED_FEATURES`, любой вызов `.read`/`.readlines`/
`.each_line`, `load`/`require_relative`/`require` чего-либо кроме `rails_helper`, шелл (`system`, `` ` ``, `%x`,
`Open3`) — и затем `expect(source).to match(...)`.
Такой тест «убивает» любую правку текста и не доказывает ничего о поведении. Мутант убит, только если
код с мутантом **ведёт себя** иначе: другое возвращённое значение, другой ответ контроллера, другая
запись в Redis/БД, поднятое исключение, сработавший шпион (`have_received`). AC-003 (`mfxb_probe.py scan`)
ищет эти приёмы во **всех** добавленных строках `spec/` (включая строки-описания) и валит критерий на
любом совпадении; ревьюеры смотрят и остальное. Найденная попытка обойти — провал вехи целиком.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `mut-fxb`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу
  заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-mutfxb-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).
- Мутанты НИКОГДА не применяются к дереву клона и не коммитятся: пробник гоняет их на копии
  (`git archive HEAD` → `tmp/mfxb-kill/`). Поэтому тесты надо **закоммитить** до прогона гейта.
  Манифест исполнителя — `tmp/mutants-fxb/manifest.json` (игнорируется git, не коммитится).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-mutfxb-ci` (если его ещё нет).
2. Если `main` ушёл вперёд от BASE_SHA: `git apply --check` всех `patches/*.patch` на новом HEAD
   (не прикладываются — пересобрать по `old`/`new` строки `kill_table.json`: замена встречается ровно
   один раз, патч — `git diff -U1`); если менялся `spec/` — на чистом checkout `main`
   `CHASKIQ_MFXB_CACHE=$HOME/.cache/chaskiq-mutfxb-ci bash docs/specs/mut-fxb-probes/rspec_gate_mfxb.sh --write-base`
   и пересчитать sha256 снимков в AC-007. **Пересечения** — раздел 10: все 37 патчей проверены на BASE,
   BASE + четыре патча R3b-2, BASE + фикс-веха fix-cleanup-2 и BASE + обе.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-007 и строку
   BASE_SHA (= этот коммит или его родитель — `B` вычисляется по `@{u}`). Только после этого — `make_clone.sh`.

## 3. Мутанты и почему

Новые спеки fix-cleanup-bugs: `store_delete_key_spec.rb`, `slack_assigned_event_spec.rb`,
`messenger_privacy_consent_spec.rb`, `graphql_origin_error_spec.rb`, `eu_location_error_spec.rb`,
`nightfury_time_series_exists_spec.rb` (15 примеров). Мутантов по файлам: `store.rb` (`delete_key`) 4,
`slack/api.rb` (ветка `assigned` в `notify_message`) 8, `eu_countries.rb` 5, `messenger_type.rb`
(`needs_privacy_consent`) 4, `api/graphql_controller.rb` (`rescue` чужого origin) 3,
`vendor/nightfury/lib/nightfury/metric/time_series.rb` (охрана `exists?`, `get`/`get_exact` с `get_meta`,
`get_range`, `get_all`, `initialize`, `set`) 13.

**Слабые места спек fix-cleanup-bugs, которые вскрывают выжившие:**
- `nightfury_time_series_exists_spec.rb` зовёт `get`/`get_exact` только без `get_meta` (замечание Codex на
  приёмке) и не читает существующий ряд: X25–X33 выживают. Правильные ответы на BASE (проверено):
  удалённый ряд — `nil` и с `get_meta`; новый ряд `get(nil, true) == [nil, {}]`; точка `t` —
  `get(nil, true) == [{t => "5"}, {}]`, `get_exact(t, true)` так же; `get_exact` отсутствующего шага — `nil`.
- `slack_assigned_event_spec.rb` проверяет упоминание через `include("<@U1>")` — нужен точный текст
  (X09, X10); нет примеров «пользователь Slack не найден» (X08), «email пустой» (X11), «событие не
  `assigned`» (X05).
- `messenger_privacy_consent_spec.rb` — только настройка `eu` и пользователь без согласия: X18–X21; список
  стран проверен одним `DE` (X13–X15: таблица всех 28 кодов и пара соседей вне списка).
- `graphql_origin_error_spec.rb` — `start_with("not accepted origin")`: X22, X23.
- `store_delete_key_spec.rb` не смотрит возвращаемое значение и поле с пустым значением: X01, X04.

**Эквивалентные (4), исключены из таблицы** (`classified.json`, довод по коду):
- `E1` `eu_countries.rb` `module_function` → `extend self` — EuCountries никто не подмешивает (единственный
  вызов — `EuCountries.includes?` в `messenger_type.rb`), обе формы дают один и тот же `EuCountries.includes?`.
- `E2` `time_series.rb` `result = get_meta ? …` → `get_meta ? …` — мёртвая локальная: присваивание и есть
  последнее выражение `get_exact`.
- `E3` `time_series.rb` удалить `data_point = ''` в `get` — мёртвая запись: обе ветки `if` присваивают
  `data_point` до чтения.
- `E4` `store.rb` `hash(conversation_key)` → `Kredis.hash(namespace(conversation_key))` — это тело `self.hash`.

**Остальные 37 — убить.** «уже убит» — мутант падает на спеках fix-cleanup-bugs его файла (раздел 4):
такие можно записать `killed` со спеками BASE; остальным нужен новый тест (`killed_new`). Предлагаемые
файлы (новые, существующие спеки не трогать): `spec/services/message_apis/twilio_phone/store_delete_key_mutants_spec.rb`,
`spec/services/message_apis/slack_assigned_event_mutants_spec.rb`, `spec/graphql/types/messenger_privacy_consent_mutants_spec.rb`
(и X13–X17, и X18–X21), `spec/controllers/api/graphql_origin_error_mutants_spec.rb`,
`spec/lib/nightfury_time_series_exists_mutants_spec.rb` (поле `suggested_spec` таблицы).

`ma/` = `app/services/message_apis/`, `s/` = `app/services/`, `gt/` = `app/graphql/types/`,
`ca/` = `app/controllers/api/`, `nf/` = `vendor/nightfury/lib/nightfury/metric/`; точный текст мутанта —
поля `old`/`new` в `kill_table.json` и патч `patches/<id>.patch`:

| id | файл | мутант | как убить | уже убит |
|---|---|---|---|---|
| X01 | `ma/twilio_phone/store.rb` | delete_key returns nil instead of the HDEL count | delete_key of a set field returns 1; of an absent field returns 0 |  |
| X02 | `ma/twilio_phone/store.rb` | every field of the hash deleted | set a and b, delete_key a: b stays | да |
| X03 | `ma/twilio_phone/store.rb` | deletes from the key without the namespace | set a, delete_key a: get a is nil | да |
| X04 | `ma/twilio_phone/store.rb` | a field with a blank value is not deleted | set a to "", delete_key a: get_values has no a |  |
| X05 | `ma/slack/api.rb` | user looked up for any event, not only assigned | event action other than assigned with data {"email" => ...}: get_slack_user_by_email not received, no mention |  |
| X06 | `ma/slack/api.rb` | assigned enters the lookup without the hash check | assigned with data nil: no exception | да |
| X07 | `ma/slack/api.rb` | user looked up by the name, not the email | get_slack_user_by_email received with the email | да |
| X08 | `ma/slack/api.rb` | mention added when no Slack user is found | get_slack_user_by_email returns nil: no exception, text without <@ |  |
| X09 | `ma/slack/api.rb` | mention replaces the event data instead of appending | exact text: "*event*: assigned \n *EMAIL*: agent@test.cl\n <@U1>" |  |
| X10 | `ma/slack/api.rb` | mention without the line break | exact text with "\n <@U1>" |  |
| X11 | `ma/slack/api.rb` | blank email still looked up | data {"email" => "", "name" => "Agent"}: get_slack_user_by_email not received |  |
| X12 | `ma/slack/api.rb` | mention uses the user name, not the id | lookup returns {"id" => "U1", "name" => "agent"}: text has <@U1> | да |
| X13 | `s/eu_countries.rb` | GB dropped from the list (kept on purpose: UK GDPR) | EuCountries.includes?("GB") true (or consent for GB) |  |
| X14 | `s/eu_countries.rb` | FR dropped from the list | includes? true for every listed code, e.g. FR |  |
| X15 | `s/eu_countries.rb` | NO (not in the list) added | includes?("NO") false, includes?("CH") false |  |
| X16 | `s/eu_countries.rb` | US added | US: consent false | да |
| X17 | `s/eu_countries.rb` | unknown location treated as an EU country | location nil: consent false | да |
| X18 | `gt/messenger_type.rb` | consent asked again after the user consented | user with privacy_consent true, setting eu, DE: false |  |
| X19 | `gt/messenger_type.rb` | setting none answers nil instead of false | setting none, DE: be(false) |  |
| X20 | `gt/messenger_type.rb` | setting all no longer asks for consent | setting all, US: true |  |
| X21 | `gt/messenger_type.rb` | empty setting answers nil instead of false | setting "", DE: be(false) |  |
| X22 | `ca/graphql_controller.rb` | origin error message replaced by a constant prefix | errors[0].message == OriginValidator::NonAcceptedOrigin.new.message |  |
| X23 | `ca/graphql_controller.rb` | origin error data nil | errors[0].data == {} |  |
| X24 | `ca/graphql_controller.rb` | origin error falls through to the generic 500 handler | status 422 and errors[0].message | да |
| X25 | `nf/time_series.rb` | deleted series: get with get_meta answers [nil, {}] | set, delete: get(nil, true) is nil |  |
| X26 | `nf/time_series.rb` | deleted series: get_exact with get_meta answers [nil, {}] | set, delete: get_exact(time, true) is nil |  |
| X27 | `nf/time_series.rb` | new series: get with get_meta answers nil | new series: get(nil, true) == [nil, {}] |  |
| X28 | `nf/time_series.rb` | get with get_meta drops the meta | set(5, time): get(nil, true) == [{ts => "5"}, {}] |  |
| X29 | `nf/time_series.rb` | get_exact with get_meta drops the meta | set(5, time): get_exact(time, true) == [{ts => "5"}, {}] |  |
| X30 | `nf/time_series.rb` | get_exact of a missing timestamp answers {} instead of nil | set(5, time): get_exact(time + 60) is nil |  |
| X31 | `nf/time_series.rb` | get returns the oldest member (the meta) instead of the latest point | set(5, time - 60), set(7, time): get == {time => "7"} |  |
| X32 | `nf/time_series.rb` | get(timestamp) finds only an exact point | set(5, time): get(time + 120) == {time => "5"} |  |
| X33 | `nf/time_series.rb` | get_range returns only the last step | set(5, time - 60), set(7, time): get_range(time - 60, time) has both |  |
| X34 | `nf/time_series.rb` | get_all keeps the meta member | new series: get_all == {} | да |
| X35 | `nf/time_series.rb` | new series not initialised | new series: meta == {} | да |
| X36 | `nf/time_series.rb` | set after delete does not restore the meta | set, delete, set: a new instance has meta {} | да |
| X37 | `nf/time_series.rb` | get_range guard inverted | set, delete: get_range is nil | да |

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 9032bd30:

1. Все 37 патчей применяются к BASE, меняют свой файл, у выживших 0 ошибок вне примеров; ни один не
   совпадает с `M01`–`M21` fix-cleanup-bugs. Тексты `old` — ровно по одному разу в файле.
2. Предпроверка (`mfxb_kill_gate.sh --jobs`, у каждого мутанта — спека fix-cleanup-bugs его файла): без
   мутантов 15 примеров в 6 файлах зелёные; спеки BASE уже убивают 12 (колонка «уже убит», все —
   проваленной проверкой); остальные 25 выживают.
3. Факты кода, на которые опирается таблица: `Kredis::Types::Hash#delete(*keys)` — `hdel keys if
   keys.flatten.any?` (kredis 1.5.0), то есть `delete_key` возвращает число удалённых полей (1/0);
   `OriginValidator::NonAcceptedOrigin#message` — постоянная строка (`app/services/origin_validator.rb:12`);
   `needs_privacy_consent` для `none`/пустой настройки и согласившегося пользователя возвращает ровно
   `false`, для `all` — `true`; `privacy_consent` пользователя — `store_accessor :properties`
   (`app_user.rb:115,124`), `user.update!(privacy_consent: true)` работает; `AppIdentity`-ряд `get_meta`
   в `app/` никто не зовёт (поведение закрепляется как публичный API вендорного гема).
4. Снимки AC-001 сняты `--write-base` на BASE: 993 примера, 0 failures, 30 pending.
5. Пробный прогон конструктора (свежий клон BASE, спека и пробники закоммичены поверх, как сделает
   постановщик) — раздел 7, абзац после критериев.

Предположение: каждый мутант таблицы убиваем поведенческим тестом без правки боевого кода (подходы — в
таблице; на пробном прогоне так убиты все 37); если нет — раздел 9.

## 5. Что сделать — по шагам

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей.
Перед шагом 1:

```bash
P=docs/specs/mut-fxb-probes
export CHASKIQ_MFXB_CACHE=$HOME/.cache/chaskiq-mutfxb-ci CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutfxb-ci
mkdir -p tmp/mutants-fxb vendor/bundle
```

**Шаг 1. Манифест.** `jq '{mutants: map({id, status: "killed_new", specs: [], test_added: null})}'
$P/kill_table.json > tmp/mutants-fxb/manifest.json` и заполняй: `killed_new` — убит новым тестом
(`test_added` — spec-файл с ним, он же в `specs`); `killed` — убит уже существующими спеками (`specs` их
перечисляет, `test_added` — `null`). Других статусов нет: не убил — раздел 9 (`blocked` в `report.json`
с конкретной причиной; AC-004 и AC-005 тогда красные — так и задумано).

**Шаг 2. Тесты — по строке таблицы.** Прочитай патч `$P/patches/<id>.patch` и код вокруг; напиши пример,
который проверяет **поведение**, сломанное мутантом: вызов кода и его результат, ответ контроллера,
содержимое Redis через публичные методы, поднятую ошибку, двойник или шпион на соседе
(`have_received(...).with(...)`). Чтение исходников — запрещено (раздел 1). Образцы построения — спеки
fix-cleanup-bugs того же файла (Slack: заглушка `post_message`, собирающая `blocks.first["text"]["text"]`;
согласие: `described_class.send(:new, app, { set_locale: -> {}, get_app_user: -> { user }, request:
double(location: loc) })`; Nightfury: уникальное имя ряда, `Time.zone.at(1_700_000_040)`, `series.delete`
в `after`; Store: уникальный ключ, `described_class.hash(key).remove` в `after`). Настройку согласия
проверяй значениями `eu`, `all`, `none`, `""` — **не `ue`**: параллельная веха fix-cleanup-2 меняет её
ответ. Проверь:

```bash
git add spec && git commit -qm "Add tests for Nightfury mutants"
bash $P/mfxb_kill_gate.sh --only X25,X26        # список id через запятую
```

Нужно `MFXB BASELINE …` (без мутанта всё зелёное) и `KILLED <id>`. `SURVIVED` — усиль пример.
Новые spec-файлы — `# frozen_string_literal: true`, `require "rails_helper"`, двойные кавычки, строки
≤ 120; глобальное состояние (ключи Redis, заглушки) — вернуть в `after`/`ensure`.

**Шаг 3.** Коммиты — только новые файлы `spec/`. **Шаг 4.** Все восемь критериев раздела 7; AC-005
(все 37, ≈ 2–8 мин) — последним. **Шаг 5.** Ревью и `report.json` — раздел 8. В `note`: AC-004 — строка
`mutants: …`; AC-005 — `MFXB KILL PASS 37/37 killed`; AC-001 — итог примеров.

## 6. Не трогать

- Ничего вне `spec/`: `app/`, `lib/`, `config/`, `vendor/`, `db/`, `Gemfile*`, `.rubocop*`, `.rspec`,
  `bin/`, workflows. Мутанты не применять к дереву клона. Боевой код равен BASE.
- Существующие файлы под `spec/` не менять, не удалять, не skip-ать (AC-001 требует все примеры BASE).
  Не добавлять `.rspec-local` и игнорируемые файлы под `spec/`.
- `docs/specs/**` — не править (AC-007, sha256): ни таблицу, ни классификацию, ни патчи.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec с новыми тестами строго зелёный: SPEC_OPTS не задан, .rspec-local нет, тела примеров выполнены (сторож); 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет новых warning-строк.
  `bash -c 'CHASKIQ_MFXB_CACHE=$HOME/.cache/chaskiq-mutfxb-ci bash docs/specs/mut-fxb-probes/rspec_gate_mfxb.sh'`

- **AC-002** — только новые файлы spec/: против BASE и в каждом коммите — только обычные файлы под spec/, которых нет в BASE (существующие спеки не меняются); вне spec/ HEAD и рабочее дерево равны BASE; нет лишних неотслеживаемых и игнорируемых файлов.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-fxb-probes/mfxb_probe.py scope $B'`

- **AC-003** — нет чтения исходников как текста: ни одна добавленная строка под spec/ не содержит Rails.root, File/IO/Dir/Pathname/FileUtils/Tempfile, путь к .rb под app/lib/config/vendor/db, source_location, .source, RubyVM, Ripper, Prism, __FILE__, __dir__, ObjectSpace, open/system/spawn/exec, %x, обратные кавычки, Rails.application.root, $LOADED_FEATURES, вызовы .read/.readlines/.each_line, load/require_relative и require чего-либо кроме rails_helper.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-fxb-probes/mfxb_probe.py scan $B'`

- **AC-004** — классификация: в tmp/mutants-fxb/manifest.json ровно id kill_table.json, каждый killed или killed_new (blocked, survived, equivalent — провал) со своими spec-файлами; у killed_new test_added изменён с BASE и есть в specs.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-fxb-probes/mfxb_probe.py check $B'`

- **AC-005** — убийство переприложением: на копии HEAD без мутантов спеки всех мутантов без failed-примеров; каждый из 37 патчей пробника приложен по одному и меняет файл; с ним спеки из манифеста дают упавший пример (killed_new — в своём test_added) и ни одной ошибки вне примеров; статусы исполнителя не учитываются.
  `bash -c 'CHASKIQ_MFXB_CACHE=$HOME/.cache/chaskiq-mutfxb-ci bash docs/specs/mut-fxb-probes/mfxb_kill_gate.sh'`

- **AC-006** — строгий RuboCop как в CI: все отслеживаемые файлы (с новыми spec-файлами), ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mutfxb-ci bin/ci-local --only rubocop'`

- **AC-007** — коммитов в docs/specs нет, пробники, патчи, таблицы и снимки не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "cdcc03e1656fc7a3db611e41bae4427ef4b8de9a8c234c7e610d0b39e42f45d9  docs/specs/mut-fxb-probes/mfxb_probe.py" "be49d154ce92db877496e4f45b257f05c9b7ff7390e3e6275f532ea3d16eedd8  docs/specs/mut-fxb-probes/mfxb_kill.rb" "ea42fd93031a7df734b5de6ad253f3ff5f0cbec37bbd4511f1bd137039978a44  docs/specs/mut-fxb-probes/mfxb_kill_gate.sh" "e2b885a1bf23bb30dc6bddf3154c27101dd48f856d79dce7ebfedd48c665ae19  docs/specs/mut-fxb-probes/kill_table.json" "b99660e996134735a8e720a1a167ca1bb7ebb7f97e999da06b682ac070e9c8b3  docs/specs/mut-fxb-probes/classified.json" "95a8d0f53e7c23b4bd5edd0c9b90bcef9066a167e330272bff7b30f0529e2309  docs/specs/mut-fxb-probes/patches.sha256" "8ff5e3c5c1208259e125dbad5a25c70b6b6f7f50d5036dd4f2e2750a8b1031c1  docs/specs/mut-fxb-probes/rspec_gate_mfxb.sh" "3f48c5fdcf6eebacbbcefd5d7792a0a930e80358fd66a96fa23e0337e6417d0d  docs/specs/mut-fxb-probes/mfxb_sentinel.rb" "5d2ff9eda9a6a9e75a221d943fdd47dbbc3d20c766b512f1aac2411d2f093f45  docs/specs/mut-fxb-probes/examples_base.txt" "f72a78123496f11047fe0f5ce5e016ef6ffb3b05e0ec3355d6eee18de97a93a2  docs/specs/mut-fxb-probes/pending_allowed.txt" "9d2c258e2aad7ccd3fe4ffd9f550839644307dbd03f054374f5a58f52df3813a  docs/specs/mut-fxb-probes/warnings_base.txt" | sha256sum -c --quiet - && sha256sum -c --quiet docs/specs/mut-fxb-probes/patches.sha256 && test "$(ls docs/specs/mut-fxb-probes/patches | wc -l)" = 37 && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), кроме untracked report.json и report-blocked.md; нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-002, AC-003, AC-006, AC-007, AC-008 зелёные; AC-004 и AC-005
красные (`tmp/mutants-fxb/manifest.json: … No such file`).

Пробный прогон автора (21.11.2026; свежий клон `main` 9032bd30, спека и пробники одним коммитом поверх, как
сделает постановщик; кэш — копия `chaskiq-fxb-ci`):
- чистый клон: AC-001 (993 примера, 0 failures, 30 pending), AC-002, AC-003, AC-006, AC-007, AC-008 — rc=0;
  AC-004 и AC-005 — rc=1 (манифеста нет), так и задумано;
- образцовые спеки постановщика (5 новых файлов, 17 примеров) и манифест (12 `killed` со спеками
  fix-cleanup-bugs, 25 `killed_new`): все 8 AC rc=0 — AC-001 1010 примеров, 0 failures, сторож 982;
  AC-005 `MFXB KILL PASS 37/37 killed` (≈ 2 мин без параллельной нагрузки); файлов от root нет;
- порченые правки (все ловятся): спека с `File.read(Rails.root.join("app/services/eu_countries.rb"))` →
  AC-003; правка существующей `slack_assigned_event_spec.rb` → AC-002; правка `app/models/lead.rb` → AC-002;
  `equivalent` у X09 в манифесте → AC-004; без примера с точным текстом упоминания → `SURVIVED X09`,
  `SURVIVED X10` (AC-005).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/mut-fxb.md --exclude "docs/specs/mut-fxb-probes/**" --context "chaskiq mut-fxb: новые тесты только под spec/ на 37 мутантов кода, который покрывают спеки fix-cleanup-bugs (TwilioPhone::Store.delete_key, Slack assigned, EuCountries, needs_privacy_consent, rescue чужого origin, Nightfury TimeSeries exists?/get_meta); убийство только поведенческое (чтение исходников запрещено), проверяет пробник переприложением патчей; боевой код не меняется; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/mut-fxb.md
REVIEW_EXCLUDE: docs/specs/mut-fxb-probes/**

Контекст ревьюерам: убивает ли каждый тест именно поведение мутанта (а не падает на загрузке, опечатке
или на чтении кода); нет ли проверки текста исходников в любом виде; не тронуты ли существующие тесты;
нет ли зависимости от порядка, времени без фиксированного `Time.zone.at`, общих ключей Redis; возвращено
ли глобальное состояние.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда критерий выполнить нельзя: `"rc": null` и дословная ошибка или причина в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/mut-fxb.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/mut-fxb.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все восемь критериев зелёные, ревью и `report.json`
готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md` (id, патч, что
пробовал, дословный вывод `mfxb_kill_gate.sh --only <id>`), в `report.json` у AC-004/AC-005 — `blocked`
с этими id и конкретной причиной, и доложи, НЕ обходя:
- мутант нельзя убить поведенческим тестом без правки боевого кода — id и почему (довод по коду);
- мутант кажется эквивалентным — id и довод по коду (не «тесты этого не проверяют»); объявлять
  эквивалентность сам не вправе, в манифест `equivalent` не писать;
- тест на правильное поведение красный и без мутанта (настоящий дефект кода) — не чинить код, тест не
  коммитить, описать;
- сьют BASE красный или флапает (приложи два прогона), образ/кэш/сервисы недоступны;
- пробник противоречит спеке или коду BASE (дефект спеки).
Запрещено: файлы вне `spec/`, правка существующих спек, пробников, таблиц, патчей; удалять/ослаблять/
skip-ать тесты; чтение исходников в тестах (раздел 1); глушить вывод и коды возврата.

## 10. Стыки

- 21 мутант гейта fix-cleanup-bugs (`M01`–`M21`) этот прогон не повторяет и не перепроверяет.
- **fix-cleanup-2** (фикс-веха, cx, может идти параллельно): меняет последнюю строку
  `needs_privacy_consent` (`%w[eu ue]`) — её мутанты здесь не трогают (патчи `-U1`, контекст её не
  включает), и ещё `lead.rb`, `dashboard.rb`, `MessengerSettings.tsx` — вне этой вехи. Проверено: все 37
  патчей применяются поверх собранного дерева fix-cleanup-2; тесты с настройкой `eu` верны до и после.
  Вливание её первой требует только переноса BASE и `--write-base`.
- **R3b-2** (идёт, qw2): общий файл `messenger_type.rb` (там `order` в строке ~50). Проверено: все 37
  патчей применяются поверх четырёх патчей R3b-2 и поверх R3b-2 + fix-cleanup-2.
- Найденный дефект кода (раздел 9) — отдельная веха с тестом «красный на BASE».
