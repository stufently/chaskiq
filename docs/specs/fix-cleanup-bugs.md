# fix-cleanup-bugs — пять дефектов, найденные чисткой RuboCop и мутациями: тест «красный на BASE» на каждый

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fix-cleanup-bugs.md`; решения — план
  `docs/specs/fork-updates-rubocop-plan.md`, раздел «Решения владельца 2026-11-20, вторая партия»
  (веха фиксов) и «Вне бэклога: дефект `TwilioPhone::Store.delete_key`».
- BASE_SHA: `ff28cdb92caabb5d77c2329e6a3e39bf3953182e` — HEAD `main` после влития R5b-2, R6c, mut-r5b1 и mut-m9-m14b
  (Ruby 4.0.10, Rails 8.1.4.1, RuboCop 1.92.3, rubocop-rails 2.38.0, kredis из `Gemfile.lock`).
- BASE плавающий: если `main` уйдёт дальше до запуска, постановщик переносит его (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 8 КБ.
- Исполнитель: **Codex (`cx`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не
  зелёные — или пока не сработал пункт раздела 9.**
- Цель: **пять правок поведения** (раздел 3), код каждой задан патчем постановщика (руками не
  править). Работа исполнителя — шесть НОВЫХ спек: одна характеризационная (зелёная на BASE и после) и
  пять спек фиксов — в каждой хотя бы один пример **красный на BASE** и все зелёные после патча; и
  каждый из 21 мутанта постановщика (`fxb_config.json`, `mutants`) роняет пример. Запись `Fixed` в
  CHANGELOG на каждый фикс.
- RuboCop-копов эта веха не касается: `.rubocop_todo.yml` и `.rubocop.yml` не меняются.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Мутант убит, только если код с
мутантом **ведёт себя** иначе: другое значение, другой ответ, исключение при вызове. AC-006
(`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на любом
совпадении; ревьюеры смотрят и остальное.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fix-cleanup-bugs`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-fxb-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-fxb-ci` (уже создан, копия `chaskiq-r3b2-ci`); если нет —
   `cp -a $HOME/.cache/chaskiq-r3b2-ci $HOME/.cache/chaskiq-fxb-ci`.
2. BASE уже перенесён на ff28cdb9: пять патчей применяются, `fxb_eulocation.patch` пересобран на нём
   (R5b-2 удалил комментарий `# raise EULocationError…` — строку контекста старого патча), тексты 21
   мутанта — по одному разу, снимки сняты `--write-base` на ff28cdb9. При следующем переносе:
   `git apply --check` пяти патчей по порядку; не применяется — пересобрать (для `fxb_eulocation`
   — теми же двумя правками: удалить строку `class EULocationError < StandardError; end` с пустой строкой
   после неё в `api_controller.rb`; в `api/graphql_controller.rb` заменить двухстрочный
   `rescue EULocationError,` / `OriginValidator::NonAcceptedOrigin => e` на
   `rescue OriginValidator::NonAcceptedOrigin => e`) — `git diff` после правки на новом BASE). Проверить
   тексты 21 мутанта (каждый ровно один раз в своём файле дерева после патчей), имена шести новых спек
   не заняты (mut-m9-m14b добавил `spec/lib/nightfury_time_series_spec.rb` — здесь другое имя; с фиксом (д)
   он совместим, проверено полным rspec на ff28cdb9). Перегенерировать снимки:
   `CHASKIQ_FXB_CACHE=$HOME/.cache/chaskiq-fxb-ci bash docs/specs/fix-cleanup-bugs-probes/rspec_gate_fxb.sh --write-base`
   на чистом checkout `main`; пересчитать sha256 в AC-008 (`acblock`). Сейчас в снимках — список
   примеров ff28cdb9. Параллельно идёт R3b-2 (`messenger_type.rb`: здесь строка 37, там 50; патчи
   применяются в любом порядке — проверено на ff28cdb9).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE ff28cdb9 (номера совпадают с e0b470d0).

**(а) `fxb_store.patch` — `app/services/message_apis/twilio_phone/store.rb:36-37`, `delete_key`.**
Было `hash(namespace(conversation_key)).del(key)`. `hash(k)` сам добавляет namespace
(`Kredis.hash(namespace(k))`), так что ключ получался `/twilio_phone//twilio_phone/<k>` — не тот, куда
пишет `set` (`hash(k).update(key => value)`), и записанное не удалялось никогда. Кроме того, `del` у
`Kredis::Types::Hash` — проксированный Redis `DEL` всего ключа хеша, а не поля. Стало
`hash(conversation_key).delete(key)` — Redis `HDEL` одного поля того же хеша, что пишет `set`; другие поля
остаются (имя метода — «удалить ключ»). Вызывающих в `app/`/`lib/` сейчас нет — метод публичный API
хранилища. После фикса мутанты **M259/M267** вехи mut-m9-m14b (`hash(conversation_key).del(key)`,
классифицированы как «дефект») становятся обычными: их форма — мутант **M04** этой вехи, и он убит
(сносит соседнее поле). Старые тексты M259/M267 (`hash(namespace(…)).del(key)`) в дереве больше не
встречаются — при следующем прогоне мутаций store.rb их надо заменить мутантами M01–M04 отсюда.

**(б) `fxb_slack.patch` — `app/services/message_apis/slack/api.rb:894`, `notify_message`.** Было
`if part&.message&.action == "assigned" && data["email"].present?` — событие `assigned` с `data` `nil`
падает `NoMethodError`, с массивом — `TypeError` (строкой выше `data_fmt` уже безопасен с R5b-1). Стало
`… && data.is_a?(Hash) && data["email"].present?`: упоминание Slack-пользователя ищется только для
хеша с email; для `nil`/массива сообщение уходит без упоминания (текст `*event*: assigned \n `).

**(в) `fxb_eu.patch` — `app/services/eu_countries.rb` и `app/graphql/types/messenger_type.rb:37`.**
`EuCountries#includes?` был методом экземпляра модуля (модуль никто не подмешивает), а
`needs_privacy_consent` звал `EuCountries.include?(code)` — это `Module#include?`, который на строке и
`nil` бросает `TypeError` (проверено: Ruby 4.0.10) — поле `needsPrivacyConsent` при настройке
`privacy_consent_required == "eu"` всегда падало. Стало: `module_function` в `EuCountries` (метод
доступен как `EuCountries.includes?`) и вызов `EuCountries.includes?(…)`. Ответ: `true` для кода страны
из списка, `false` вне списка и для неизвестного места (`nil`).

**(г) `fxb_eulocation.patch` — `app/controllers/api_controller.rb:134` и
`app/controllers/api/graphql_controller.rb:49-50`.** `class EULocationError < StandardError; end` нигде не
поднимается (единственное упоминание кроме `rescue` — закомментированный `raise` в `get_app_user:138`,
его удаляет R5b-2; `git grep EULocationError` больше ничего не находит — AC-007). Класс удалён, `rescue`
в `Api::GraphqlController#execute` сужен до `rescue OriginValidator::NonAcceptedOrigin => e` — ответ на
чужой origin тот же: 422 с `errors[0].message` валидатора. Характеризационная спека фиксирует этот ответ
до и после.

**(д) `fxb_nightfury.patch` — `vendor/nightfury/lib/nightfury/metric/time_series.rb:21,29,34,53,63,71`.**
Все шесть мест — `redis.exists(redis_key)`. В `Gemfile.lock` redis 4.8.1, а
`config/initializers/redis.rb:14` ставит `Redis.exists_returns_integer = true`: `exists` возвращает
`Integer`, `0` в Ruby истинен — оба вида проверок не срабатывают никогда (проверено в Docker на BASE:
`Redis::VERSION` 4.8.1, `exists_returns_integer=true`, `exists(нет ключа) = 0`):
- `init_time_series unless redis.exists(…)` (строки 21 — `initialize`, 29 — `set` после `delete`) не
  создаёт мету: у нового ряда в Redis ничего нет (`zcard` 0), `meta` бросает `TypeError`
  (`JSON.parse(nil)`), после `delete` + `set` меты тоже нет;
- `return nil unless redis.exists(…)` (34 `get`, 53 `get_exact`, 63 `get_range`, 71 `get_all`) не
  возвращает `nil` для удалённого ряда: `get`/`get_exact` всё равно дают `nil` (пустая выборка), а
  `get_range` и `get_all` — `{}` (проверено).
Стало `redis.exists?(redis_key)` во всех шести (`Redis::Namespace` 1.11.0 его проксирует; проверено:
спека зелёная на дереве). Других `.exists(` в `vendor/nightfury`, `app/`, `lib/`, `config/` нет
(`git grep -n "\.exists("`). Поведение для приложения: `AppIdentity.new(key).<метрика>` при первом
обращении пишет мету `{}` со score 0 (так задумано — комментарий в `set`); чтение существующих рядов
не меняется (`get_all` мету отбрасывает, `get` пропускает score 0). `nil` из `get_range`/`get_all`
теперь бывает только у объекта, на котором вызван `delete` (в `app/` — `Identity#delete`, вне
дашборда); `get_padded_range` на таком объекте упал бы — на BASE давал `{}`; вызывающих с такой
последовательностью нет. После фикса мутанты **M100** и **M103** вехи mut-m9-m14b становятся
убиваемыми (их формы — M17/M18 и M21 здесь, убиты). **M101** (`zremrangebyscore` на ±1) с `exists`
не связан и остаётся эквивалентным: все score — кратные шагу (≥ 60 с) или 0 у меты, в окне
`[t-1, t+1]` при `t`, кратном шагу, нет других точек.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-fxb-ci`) на
клоне BASE e0b470d0, повторено на ff28cdb9:

1. Образцы шести спек постановщика (содержание — раздел 5): на BASE характеризационная зелёная, в каждой
   из пяти спек фиксов есть красный пример, причём по нужной причине — `expected: nil got: "1"`
   (delete_key), `NoMethodError '[]' for nil` и `TypeError` (Slack), `TypeError wrong argument type
   String (expected Module)` (consent), `expected false got true` (EULocationError), `expected nil got {}`
   и `TypeError` у `meta` (Nightfury); на дереве — все примеры зелёные.
2. 21/21 мутант убит поведением: неверное значение/статус (`expected: 422 got: 400`), сработавшая
   проверка `not_to have_received`, `NameError` при `rescue` с удалённым классом, `NoMethodError` вызова
   `EuCountries.includes?` без `module_function`.
3. RuboCop на файлах кода `app/` и шести спеках — 0 офенсов (`vendor/` RuboCop не проверяет).
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: `MessengerType` в спеке создаётся напрямую с контекстом-хешем
(`set_locale`, `get_app_user`, `request`), как его собирает `Api::GraphqlController`; путь через
`graphql_post` не используется (тот берёт текст запроса из `npx ts-node` и падает от среды).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код — **только** `git apply` патчей. В каждой спеке
`# frozen_string_literal: true`, `require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:`
директив, чтения исходников (раздел 1), `graphql_post`. Перед шагом 1:

```bash
P=docs/specs/fix-cleanup-bugs-probes
export CHASKIQ_FXB_CACHE=$HOME/.cache/chaskiq-fxb-ci
```

**Шаг 1. Характеризационная спека** `spec/controllers/api/graphql_origin_error_spec.rb`
(`RSpec.describe Api::GraphqlController, type: :controller`), код = BASE: приложение
`FactoryBot.create(:app)` (его `domain_url` — `http://localhost:3000`), заголовки `HTTP_APP` = ключ
приложения и `HTTP_ORIGIN` = `http://evil.example`, `post :execute, params: { query: "{ __typename }" }` →
статус ровно 422 и `errors[0].message` начинается с `not accepted origin`.

```bash
git add spec/controllers/api/graphql_origin_error_spec.rb
git status --short        # ожидается: "A  spec/controllers/api/graphql_origin_error_spec.rb" (после отката шага 6 — плюс "??" остальных спек)
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 1 files
git commit -m "Pin the widget origin error response"
```

**Шаг 2. delete_key.** Спека `spec/services/message_apis/twilio_phone/store_delete_key_spec.rb`
(`RSpec.describe MessageApis::TwilioPhone::Store`), ключ разговора уникальный на пример
(`"fxb-#{SecureRandom.hex(4)}"`), после примера `described_class.hash(conv_key).remove`; только
публичные `set`, `get`, `get_values`, `delete_key`:
- `set` полей `a`=`"1"` и `b`=`"2"`, `delete_key(conv_key, "a")` → `get(conv_key, "a")` равен `nil`,
  `get(conv_key, "b")` равен `"2"`;
- `delete_key` отсутствующего поля → `get_values(conv_key) == { "b" => "2" }`.

```bash
git apply $P/fxb_store.patch
git add spec/services/message_apis/twilio_phone/store_delete_key_spec.rb
git commit -qam "Delete the set field in Twilio delete_key"
```

**Шаг 3. Slack `assigned`.** Спека `spec/services/message_apis/slack_assigned_event_spec.rb`
(`RSpec.describe MessageApis::Slack::Api`; образец построения — `spec/services/message_apis/slack_event_data_spec.rb`):
`described_class.new(config: { "access_token" => "x", "channel_id" => "C1" })`, разговор пользователя с
каналом `conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")`, `post_message`
заглушен и запоминает `blocks.first["text"]["text"]`; часть —
`conversation.messages.create!(authorable: user, event: { action: "assigned", data: data })`, затем
`notify_message(conversation:, part:, channel: nil)`. Примеры:
- `data` `nil` — без исключения, текст ровно `"*event*: assigned \n "`;
- `data` `%w[a b]` — без исключения, тот же текст;
- `data` `{ "name" => "Agent" }` (без email) — `get_slack_user_by_email` не вызван
  (`allow` + `not_to have_received`), текст ровно `"*event*: assigned \n *NAME*: Agent"`;
- `data` `{ "email" => "agent@test.cl" }`, `get_slack_user_by_email` с этим email возвращает
  `{ "id" => "U1" }` — текст содержит `<@U1>`.

```bash
git apply $P/fxb_slack.patch
git add spec/services/message_apis/slack_assigned_event_spec.rb
git commit -qam "Skip Slack mention without hash data"
```

**Шаг 4. Согласие EU.** Спека `spec/graphql/types/messenger_privacy_consent_spec.rb`
(`RSpec.describe Types::MessengerType`): `app.update!(privacy_consent_required: "eu")`, пользователь
`app.add_user(email:)` без согласия; тип —
`described_class.send(:new, app, { set_locale: -> {}, get_app_user: -> { user }, request: double(location: loc) })`,
где `loc` — `double(country_code: code)` или `nil`; вызов `needs_privacy_consent`:
- `"DE"` → ровно `true`; `"US"` → ровно `false`; место неизвестно (`location` `nil`) → ровно `false`.

```bash
git apply $P/fxb_eu.patch
git add spec/graphql/types/messenger_privacy_consent_spec.rb
git commit -qam "Call EuCountries.includes? for consent"
```

**Шаг 5. EULocationError.** Спека `spec/controllers/api/eu_location_error_spec.rb`
(`RSpec.describe ApiController`): `described_class.const_defined?(:EULocationError, false)` ровно `false`
(константа — поведение загрузки класса, не текст файла). Ответ 422 после сужения `rescue` уже
закреплён шагом 1.

```bash
git apply $P/fxb_eulocation.patch
git add spec/controllers/api/eu_location_error_spec.rb
git commit -qam "Remove unused EULocationError"
```

**Шаг 5а. Nightfury `exists?`.** Спека `spec/lib/nightfury_time_series_exists_spec.rb`
(`RSpec.describe Nightfury::Metric::TimeSeries`), имя ряда уникальное на пример
(`:"fxb_series_#{SecureRandom.hex(4)}"`), время `Time.zone.at(1_700_000_040)` (кратно минуте; `Time.at` без зоны — офенс `Rails/TimeZone`), после примера
`series.delete`:
- `set(5, time)`, `delete` → `get`, `get_exact(time)`, `get_range(time - 3600, time)`, `get_all` — все ровно `nil`;
- новый ряд: `meta == {}`, `get` — `nil`, `get_all == {}`;
- `set(5, time)`, `delete`, `set(7, time)` → `get_all == { time.to_i.to_s => "7" }` и у нового экземпляра
  с тем же именем `meta == {}`;
- `Nightfury::Metric::CountTimeSeries`: `incr(1, time)` дважды → `get_exact(time) == { time.to_i.to_s => "2" }`
  (ряд удалить в `ensure`).

```bash
git apply $P/fxb_nightfury.patch
git add spec/lib/nightfury_time_series_exists_spec.rb
git commit -qam "Use exists? in Nightfury time series"
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/fxb_tests_gate.sh $B` (≈ 3 мин). Нужны три
строки: `FXB TREE PASS … examples`, `FXB BASE PASS 1 char / 5 fix failing` (число char-примеров — твоё),
`FXB MUTANTS PASS 21/21 killed`. Пример красный на дереве, спека фикса зелёная на BASE или мутант
выжил — поправь спеку (код, патчи и мутантов не трогать; убийство — только поведением), не добавляя
новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Pin the widget origin error response$')
mkdir -p tmp/fxb-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/fxb-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/fxb-specs (tmp/ игнорируется)
# поправь спеки в tmp/fxb-specs/spec/…, затем: cp -r tmp/fxb-specs/spec/. spec/
# затем — команды шагов 1–5 (каждый шаг добавляет только свою спеку), шага 5а, затем снова шаг 6
```

**Шаг 7. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-20 — fix-cleanup-bugs

- Fixed: `MessageApis::TwilioPhone::Store.delete_key` deletes the field that `set` wrote (it deleted
  from a double-namespaced key, so nothing was ever removed).
- Fixed: Slack notification of an `assigned` event no longer raises when the event data is nil or an
  array (the assignee mention is looked up only for hash data with an email).
- Fixed: `needs_privacy_consent` with the "eu" setting no longer raises `TypeError`: it calls
  `EuCountries.includes?`, now a module function, and answers true only for an EU country code.
- Fixed: unused `ApiController::EULocationError` and its `rescue` in `Api::GraphqlController` removed
  (never raised); the origin error still answers 422.
- Fixed: Nightfury time series use `redis.exists?`: with redis 4.8 `exists` returns an Integer and 0
  is truthy, so a new series was never initialised (its `meta` raised) and `get_range`/`get_all` of a
  deleted series returned `{}` instead of nil.
```

```bash
git commit -am "Note fix-cleanup-bugs in changelog"
```

**Шаг 8.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 9.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`FXB … PASS`; AC-006 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме семи файлов кода (шесть в `app/` и `vendor/nightfury/lib/nightfury/metric/time_series.rb`, только
  патчами), шести новых спек и `CHANGELOG.md`; остальной `vendor/` не трогать.
- `.rubocop.yml`, `.rubocop_todo.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows,
  `bin/*`, `db/`, `config/`, существующие спеки (в том числе `slack_event_data_spec.rb`,
  `store_spec.rb`, `graphql_controller_spec.rb`, `spec/lib/nightfury*_spec.rb`).
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, чтения исходников в спеках.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_FXB_CACHE=$HOME/.cache/chaskiq-fxb-ci bash docs/specs/fix-cleanup-bugs-probes/rspec_gate_fxb.sh'`

- **AC-002** — пути и код: изменены ровно 7 файлов кода (6 в app/ и vendor/nightfury/lib/nightfury/metric/time_series.rb), 6 новых файлов спек (новые обычные файлы) и CHANGELOG — каждый; todo и .rubocop.yml не тронуты; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с пятью патчами по порядку; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-bugs-probes/fxb_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 6 файлов зелёные на коде дерева; на коде BASE характеризационная спека зелёная, в каждой из 5 спек фиксов есть упавший пример; ошибок вне примеров нет; каждый из 21 мутанта fxb_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_FXB_CACHE=$HOME/.cache/chaskiq-fxb-ci bash docs/specs/fix-cleanup-bugs-probes/fxb_tests_gate.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, todo BASE, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-fxb-ci bin/ci-local --only rubocop'`

- **AC-005** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно свою спеку при коде BASE; каждый коммит фикса оставляет файлы кода = BASE + патчи до своего включительно и добавляет ровно свою спеку; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fix-cleanup-bugs (не меньше пяти строк «- Fixed: ») после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-bugs-probes/fxb_probe.py commits $B'`

- **AC-006** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fix-cleanup-bugs-probes/source_scan.py $B'`

- **AC-007** — EULocationError не упоминается в app/, lib/, config/ ничем, кроме строк-комментариев; вызова `.exists(` нет в vendor/nightfury, app/, lib/, config/ (сбой git grep — FAIL).
  `bash -c 'out=$(git grep -n EULocationError -- app lib config || [ $? -eq 1 ]) && test -z "$(printf "%s" "$out" | grep -vE "^[^:]+:[0-9]+:[[:space:]]*#")" && ex=$(git grep -n "\.exists(" -- vendor/nightfury app lib config || [ $? -eq 1 ]) && test -z "$ex"'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "41ca24a4bb13dba42055b0ca6208c4d8858be7f3921979bbf1459209f19032d4  docs/specs/fix-cleanup-bugs-probes/fxb_probe.py" "32cae04fe6ec170333bc00cddd9390bd894d1ffe7a116c2f08b2f6cc60dcba32  docs/specs/fix-cleanup-bugs-probes/fxb_config.json" "cc20ba764bc562c88a71136a351087264e0f888c8adc1e69d29d3f275960dcf4  docs/specs/fix-cleanup-bugs-probes/fxb_tests.rb" "a1646d4fd9c24576b5b1807185d9937ee874f4f7a7593a3cd183641a7bf52fb2  docs/specs/fix-cleanup-bugs-probes/fxb_tests_gate.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fix-cleanup-bugs-probes/source_scan.py" "891e2a29a6063408210ec979e14c20bbe2bc10e14e5118163b155752360a43ee  docs/specs/fix-cleanup-bugs-probes/fxb_store.patch" "f40a13f4938fda6bfeedd7087671da69767a10c80deef1e23348153692427198  docs/specs/fix-cleanup-bugs-probes/fxb_slack.patch" "20ff9d5423fb2bb6e8d03943a7a360de1174132e955e20eced12b59c36f6313f  docs/specs/fix-cleanup-bugs-probes/fxb_eu.patch" "961084d699a6c72211b8b37b04e2f554222440ef2e2b3959851aa03cfb9d5a3d  docs/specs/fix-cleanup-bugs-probes/fxb_eulocation.patch" "aa348689f772328c6b39a1b25fa13074ba1c3875257532cfc804b0ad3991a711  docs/specs/fix-cleanup-bugs-probes/fxb_nightfury.patch" "3a4d6d3f117e3e8776a19a529963ab326c178fed5b1952d9d3db76315d365c44  docs/specs/fix-cleanup-bugs-probes/rspec_gate_fxb.sh" "108831edf93775e5e0bc26208da43f63e38e6d6c72d385846f0c96146759a621  docs/specs/fix-cleanup-bugs-probes/fxb_sentinel.rb" "a0a9778af2766c14c28c330b1ad90e9d437a981c4c613fea580a56cfa0063f28  docs/specs/fix-cleanup-bugs-probes/examples_base.txt" "8481b827024aa1f161b519d586a46805aca4f976f0e157c228ce85d28ea97fe5  docs/specs/fix-cleanup-bugs-probes/pending_allowed.txt" "20fab06f2294ae690784481c9314ea7c4c67d1be288b8a98bed48cb9971c921a  docs/specs/fix-cleanup-bugs-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-004, AC-006, AC-008, AC-009 зелёные; AC-002 красный
(`fix-cleanup-bugs paths without the change: …`); AC-003 красный (спек нет — `no examples ran`); AC-005
красный (`missing commits`); AC-007 красный (`class EULocationError` и `.exists(` на BASE).

Пробный прогон автора (21.11.2026, свежий клон от BASE ff28cdb9 со спекой поверх, сборка по разделу 5 буквально, спеки —
образцы постановщика):
- чистый клон: AC-004, AC-006 (`SOURCE SCAN PASS 0 files`), AC-008, AC-009 зелёные; AC-002, AC-005,
  AC-007 красные с сообщениями выше (AC-001 и AC-003 на чистом клоне не гонялись);
- после сборки: все 9 AC зелёные — rspec 960 examples (15 новых), 0 failures, 30 pending, сторож 940
  (в том числе `spec/lib/nightfury_time_series_spec.rb` mut-m9-m14b — зелёная с фиксом (д));
  AC-003 `FXB TREE PASS 15 examples`, `FXB BASE PASS 1 char / 5 fix failing`, `FXB MUTANTS PASS 21/21 killed`;
  AC-006 `SOURCE SCAN PASS 6 files`; файлов от root нет (после замены `Time.at` → `Time.zone.at` в образце
  спеки Nightfury — офенс `Rails/TimeZone` в AC-004 — всё повторено на ff28cdb9);
- порченые правки (все ловятся): `File.read(Rails.root.join("app/…/store.rb"))` в спеке → AC-006; ручная
  правка `app/models/lead.rb` → AC-002 «not a fix-cleanup-bugs path»; `EULocationError = Class.new(StandardError)`
  в `ApiController` → AC-007; спека `delete_key` без примера «удалил поле, соседнее осталось» → AC-003
  (`no example fails on BASE`, выжили M01, M03).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Codex,
поэтому пара — agy и Qwen); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fix-cleanup-bugs.md --exclude "docs/specs/fix-cleanup-bugs-probes/**" --context "chaskiq fix-cleanup-bugs: пять фиксов поведения патчами постановщика — TwilioPhone::Store.delete_key (HDEL поля того же хеша, что пишет set), Slack assigned с data nil/массивом, EuCountries.includes? как module_function в needs_privacy_consent, удаление неиспользуемого EULocationError и его rescue, redis.exists? вместо exists (Integer, 0 истинен) в Nightfury::Metric::TimeSeries; 1 характеризационная спека (422 на чужой origin) и 5 спек фиксов, красные на BASE; 21 мутант; спеки не читают исходники как текст; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fix-cleanup-bugs.md
REVIEW_EXCLUDE: docs/specs/fix-cleanup-bugs-probes/**

Контекст ревьюерам: найти вызывающего, которому нужен был старый `delete_key` или `EuCountries#includes?`
как метод экземпляра; путь, где `assigned` с хешем без email теперь ведёт себя иначе; исключение, которое
раньше ловил `rescue EULocationError`; вызывающего Nightfury, которому мешает мета `{}` в новом ряду или `nil` из `get_range`/`get_all` удалённого ряда; спеку, которая проверяет текст, а не поведение, или красна на BASE
не по той причине. Код править нельзя — замечание по месту решает постановщик (раздел 9); спеки —
можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fix-cleanup-bugs.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fix-cleanup-bugs.md --dry-run`, добиться кода 2.

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
`pending`/`skip`, чтение исходников в спеках, глушить вывод и коды возврата.

## 10. Стыки

- **R5b-2** — влит. Он удалил комментарий `# raise EULocationError…` и `eu_location?` в
  `api_controller.rb`; `fxb_eulocation.patch` пересобран на ff28cdb9. Других общих файлов нет.
- **mut-r5b1** — влит. Его мутанты `R42`–`R44` правили строку `slack/api.rb:894`, которую меняет
  `fxb_slack.patch`; их прогон закончен, после этой вехи их тексты не применяются.
- **R3b-2 — идёт параллельно (qw2).** Общий файл — `app/graphql/types/messenger_type.rb`: там строка 50
  (`order`), здесь 37. На ff28cdb9 проверено: `fxb_eu.patch` применяется поверх `r3b2_order.patch` и
  наоборот. Вторая влитая из двух вех получает конфликт-свободный rebase, но её BASE и sha256 после
  влития первой постановщик переносит, если перезапуск нужен.
- **R6c** — общих файлов нет.
- **mut-m9-m14b** — влит (частичная приёмка). M259/M267 (`delete_key`) становятся обычными мутантами —
  раздел 3 (а); M100 и M103 (Nightfury) — убиваемыми, M101 остаётся эквивалентным — раздел 3 (д). Его
  `spec/lib/nightfury_time_series_spec.rb` с фиксом (д) совместим (полный rspec на ff28cdb9 зелёный);
  если он покраснеет — раздел 9, чужую спеку не править.
