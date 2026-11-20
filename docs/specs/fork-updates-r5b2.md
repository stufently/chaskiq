# fork-updates-r5b2 — бэклог RuboCop, шаг 5b-2: остальные Lint в app/ и lib/ — сначала тесты, потом правка

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r5b2.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — вторая часть R5b, раздел 10 спеки R5b-1).
- BASE_SHA: `b9e3c4ec5782cdebc0dfd3bf3c460ceb951b9a34` — HEAD `main` с влитой R5b-1 и обновлённым планом
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд (влиты R5b-1, mut-m9-m14b), постановщик
  коммитит новое значение в строку BASE_SHA и только потом снимает клон (раздел 2). Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 25 КБ
  (18 файлов кода четырьмя патчами, 12 новых спек, todo, CHANGELOG) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все десять критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: в `app/` и `lib/` не остаётся `Lint/AssignmentInCondition`, `BooleanSymbol`,
  `InterpolationCheck`, `MisplacedMagicComment`, `NonLocalExitFromIterator`, `RedundantSafeNavigation`,
  `RedundantTypeConversion`, `SafeNavigationChain`, `SymbolConversion`, `UnderscorePrefixedVariableName`,
  `UnreachableCode` (52 офенса, 18 файлов). **Поведение не меняется**: удаляемый код мёртв (решения
  владельца E1, E2 — раздел 3), остальное — равносильная запись. Код правки задан патчами постановщика
  (руками Ruby в `app/`/`lib/` не править), а работа исполнителя — 12 характеризационных спек (зелёные на
  BASE и после правки) и чтобы каждый из 20 мутантов постановщика (`r5b2_config.json`, `mutants` —
  «правка, сделанная неправильно») ронял пример.
- **`spec/`: только 12 НОВЫХ файлов** (раздел 5); существующие спеки не трогать — параллельно идут
  R5b-1 и mut-m9-m14b (их новые файлы — `spec/models/audit_serialize_spec.rb`, `campaign_urls_spec.rb`,
  `spec/services/message_apis/{pipedrive_api,slack_api_helpers,safe_download_location,calendly_presenter,
  slack_event_data}_spec.rb`, `spec/jobs/app_user_event_job_spec.rb` и файлы mut-m9-m14b — имена этой
  вехи с ними не пересекаются).

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Мутант убит, только если код с
мутантом **ведёт себя** иначе: другой результат, другое сообщение, другое состояние базы, исключение.
AC-007 (`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на
любом совпадении; ревьюеры смотрят и остальное.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r5b2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r5b2-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (иначе Docker создаст точку монтирования от root; пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r5b2-ci` — копия `chaskiq-r5b1-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5b1-ci $HOME/.cache/chaskiq-r5b2-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; проверить `git apply --check` четырёх патчей на
   новом BASE по порядку и тексты мутантов (R5b-1 уже влита: её правки `safe_download.rb:148`,
   `paddle.rb:25`, `action_trigger_factory.rb:7` с патчами не конфликтуют — проверено на b9e3c4ec). Если менялся `spec/` —
   перегенерировать список примеров
   `CHASKIQ_R5B2_CACHE=$HOME/.cache/chaskiq-r5b2-ci bash docs/specs/fork-updates-r5b2-probes/rspec_gate_r5b2.sh --write-base`
   на чистом checkout `main`, проверить, что имена 12 новых спек не заняты, и пересчитать sha256 в
   AC-009. Сейчас в снимках — список примеров BASE b9e3c4ec (с 32 примерами R5b-1).
3. Решения владельца E1, E2 получены 2026-11-20 (раздел 3) и уже учтены в патчах.
4. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-009 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE. Где вывод держится на факте о коде или геме, факт назван.

**Решения владельца (2026-11-20):**
- **E1 `lib/subdomain_routes.rb` — УДАЛИТЬ `PersonalizedDomain`, `NoSubdomain` и константу `DOMAIN`**
  (`r5b2_routes.patch`). Остаётся `SubdomainOrDomain` — единственный используемый
  (`config/routes.rb:57`, `constraints(SubdomainOrDomain)`). `git grep -nwE
  "PersonalizedDomain|NoSubdomain|DOMAIN" -- app config lib spec ":(exclude)app/javascript"` на BASE
  находит только `lib/subdomain_routes.rb` (в `app/javascript` — строка лога `'No DOMAIN ON AUTH0'`,
  не константа). `InterpolationCheck` (4) были ровно в удаляемых классах. Поведение `SubdomainOrDomain`
  фиксирует спека шага 1 (M01, M02).
- **E2 `app/controllers/api_controller.rb` — УДАЛИТЬ `eu_location?` (строки 197-200) и закомментированный
  `# raise EULocationError…` (строка 138)** (`r5b2_eu.patch`). Вызовов `eu_location?` нет нигде
  (`git grep`). `EULocationError` и `EuCountries` **остаются**: `EULocationError` по-прежнему назван в
  `rescue` `app/controllers/api/graphql_controller.rb:49`, `EuCountries` — в
  `app/graphql/types/messenger_type.rb:37`; доказуемо неиспользуемыми они не стали (раздел 10).

**`r5b2_autocorrect.patch` — автокоррекция RuboCop 1.92.3, 12 файлов**
(`rubocop -A --only Lint/AssignmentInCondition,Lint/BooleanSymbol,Lint/SymbolConversion,
Lint/RedundantSafeNavigation,Lint/RedundantTypeConversion` + `-a --only Layout/ArgumentAlignment`):
- `AssignmentInCondition` 6 — присваивание в условии в скобках (`create_app.rb:16`, `insert_comment.rb:23`,
  `start_conversation.rb:24`, `list_importer.rb:36`, `lead.rb:6`, `action_trigger_factory.rb:313`): тот же
  AST, скобки — только знак намерения; запись `todo` про `conversation_part.rb` устарела (офенса нет).
- `BooleanSymbol` 26 — `presence: :true` → `presence: true` (`plugin_schema_validator.rb` 25, `message.rb:17`).
  Равносильно: `ActiveModel::Validations::ClassMethods#_parse_validates_options` превращает не-Hash/не-true
  значение в `{with: :true}`, а `PresenceValidator` `:with` не читает — проверка та же.
- `SymbolConversion` 4 (+1 в `sns_receiver_job.rb` — в ручном патче) — `"…".to_sym` → `:"…"`.
- `RedundantSafeNavigation` `app_package_integration.rb:187` — `"…"&.constantize` → `.constantize`
  (строковый литерал не `nil`); `RedundantTypeConversion` `message.rb:119` — `.to_json.to_s` → `.to_json`
  (`to_json` уже String).

**`r5b2_manual.patch` — руками, 4 файла:**
- `MisplacedMagicComment` `paddle.rb:97` — вторая `# frozen_string_literal: true` в конце файла удалена
  (первая строка файла — та же; автокоррекция дублировала бы её наверху).
- `NonLocalExitFromIterator` 5 `safe_download.rb:79,80,83,87,157` — `return` → `return nil` (то же значение).
- `UnderscorePrefixedVariableName` `sns_receiver_job.rb:7` — `_referrer` используется → `referrer`
  (позиционный аргумент: вызывающий код не меняется); там же `SymbolConversion:42`.
- `SafeNavigationChain` `app_user_trigger_job.rb:48` — `trigger.paths.first&.with_indifferent_access["steps"].find …`
  → `first_path = trigger.paths.first` и `step = first_path.with_indifferent_access["steps"].find { … } if first_path`.
  Равносильно: в Ruby `&.` обрывает всю цепочку, так что при `nil` и раньше получался `step = nil`.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r5b2-ci`) на
клоне BASE 4bd1b924 (снимки примеров, патчи и тексты мутантов перепроверены на b9e3c4ec):

1. Rubocop без todo на BASE: у 11 копов вехи 52 офенса, все в 18 файлах раздела 3. Четыре патча
   применяются по порядку; после них полный rubocop по изменённым файлам (todo без блоков вехи) — 0 офенсов.
2. Мутанты против существующих спек: M07, M11 и M18 (по нумерации конфига) убиты существующими файлами
   поведенческими проверками (в конфиге их спеки — эти файлы). M03–M05 существующие
   `spec/controllers/graphql/{app,conversations}_spec.rb` «убивали» не всегда: они ходят через
   `graphql_post`, текст запроса берётся из `npx ts-node`, и в одном прогоне все примеры падали с
   `unexpected end of input` при любом коде — убийство от среды, не от мутанта. Поэтому для M03–M05 —
   своя спека с прямым `resolve`. Остальные выживали; отсюда 12 новых спек.
   Два кандидата постановщик выбросил как эквивалентные: удаление `return nil if hop == limits.max_redirects`
   (после цикла метод и так возвращает `nil`) и `return nil unless addresses` (`download` с `nil`
   бросает, `within_deadline` ловит `StandardError` и возвращает `nil`, запроса нет).
3. Образцы 12 спек постановщика (раздел 5 описывает их содержание): 25 примеров зелёные на дереве и на
   BASE; 20/20 мутантов убиты. Черновик ровно по разделу 5: итоги — раздел 7.
4. `EuCountries.include?("DE")` в Ruby 4.0.10 — `TypeError` (`Module#include?`), `EuCountries.includes?` —
   `NoMethodError` (метод экземпляра модуля): раздел 10.

Предположение: равносильность синтаксических замен — по чтению кода и исходника ActiveModel (раздел 3);
подкреплено полным rspec (AC-001) и мутантами.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код `app/`/`lib/` — **только** `git apply` патчей, руками не править. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r5b2-probes
export CHASKIQ_R5B2_CACHE=$HOME/.cache/chaskiq-r5b2-ci
```

**Шаг 1. Характеризационные спеки** — 12 НОВЫХ файлов, код = BASE. В каждом
`# frozen_string_literal: true`, `require "rails_helper"`; HTTP — только WebMock (как
`spec/services/message_apis/safe_download_spec.rb`: `include WebMock::API`, `WebMock.enable!`/`reset!`/
`disable!` в `around`). `FactoryBot.create(:app)`, `app.add_agent({ email:, first_name: }).agent`,
`app.add_user(email:, first_name:)`. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив и чтения
исходников (раздел 1, правило). Что проверить (значения — точные):
- `spec/lib/subdomain_or_domain_spec.rb` — `SubdomainOrDomain.matches?(ActionDispatch::Request.new(
  Rack::MockRequest.env_for("http://<host>/")))`: `help.example.com` → `true`; каждый из `APP_SUBDOMAINS`
  как поддомен → `false`; `example.com` → `nil`; `www.help.example.com` → `true`, а со
  `stub_const("APP_SUBDOMAINS", ["www.help"])` → `false` (поддомены склеиваются через `.`).
- `spec/importers/list_importer_leads_spec.rb` — подготовка как `spec/importers/list_spec.rb`
  (`Roo::Spreadsheet.open` → `Spreadsheet.new(rows)`, сброс `@fetch_model_block`/`@sheet_index`,
  `transactional(false)`): `ListImporter.import("/dummy/file", params: {app_id:, agent_id:, type: "leads"})`
  двух строк → `Lead.count` +2, контакт — `Lead`; без `type` → контакт `AppUser`, первый тег начинается с
  `"import "`.
- `spec/services/action_trigger_factory_segment_spec.rb` — `ActionTriggerFactory.find_by_segment(app:, user:,
  rules: [{"trigger" => bot.id, "predicates" => [{"attribute" => "email", "comparison" => "eq", "type" => "string",
  "value" => <email>}]}])` (`bot = app.bot_tasks.create(title: "bot", bot_type: "new_conversations")`):
  email пользователя → `bot`; чужой email → `nil`.
- `spec/models/bot_task_infix_spec.rb` — `BotTask` без `name` невалиден, ошибка на `:name`;
  `BotTask.where(BotTask.infix(["AppUser"]))` находит задачу, чьи `segments` (через `update_column`) — это
  `BotTask.type_predicate_for(["AppUser"])` (строковые ключи) плюс ещё один предикат, и не находит задачу с
  предикатом `["Lead"]`.
- `spec/models/app_package_integration_presenter_spec.rb` — `AppPackageIntegration.new(app_package:
  AppPackage.new(name: <имя>)).get_presenter_manager`: `"Calendly"` → `MessageApis::Calendly::Presenter`;
  `"NoSuchPackage"` → `ExternalPresenterManager`.
- `spec/controllers/application_controller_cookie_spec.rb` — у `ApplicationController.new` с
  `@app = App.new(key: "ab-cd-ef")` `cookie_namespace` (через `send`) → `:chaskiq_session_id_abcdef`.
- `spec/graphql/mutations/update_conversation_state_spec.rb` — `described_class.new(object: nil, field: nil,
  context: {current_user: agent, request: ActionDispatch::TestRequest.create})`, агент — владелец
  приложения (`app.update!(owner_id: agent.id)`), разговор `app.conversations.create(main_participant: user)`:
  `resolve(app_key:, conversation_id:, state: "close")` → после `reload` `state == "closed"`, затем `"reopen"`
  → `"opened"`; `state: "destroy"` → остаётся `"opened"`.
- `spec/jobs/sns_receiver_job_campaign_spec.rb` — `Campaign.find_by(id: "7")` и `AppUser.find_by(id: "9")`
  заглушены (`Campaign.new`, `AppUser.new`); `SnsReceiverJob.new.perform("click", message, "https://ref.example")`,
  где в `mail.headers` — `X-CHASKIQ-CAMPAIGN-ID` `"7"` и `X-CHASKIQ-CAMPAIGN-TO` `"9"`, `"click" =>
  {"ipAddress" => "1.2.3.4"}` → пользователь получает `track_click(host: "1.2.3.4", trackable: campaign,
  data: {"ipAddress" => "1.2.3.4"})`.
- `spec/models/concerns/subscribable_payment_attribute_spec.rb` — `App.new(...).payment_attribute("subscription_status")`:
  без `paddle_subscription_plan_id` → значение `stripe_subscription_status`; с ним → `paddle_subscription_status`
  (оба атрибута заданы разными значениями).
- `spec/services/message_apis/safe_download_limits_spec.rb` (`resolve` заглушен публичным IP):
  цепочка двух 302 при `max_redirects: 1` → `nil`; `url_allowed: ->(_uri) { false }` → `nil` и запроса не было
  (`assert_not_requested`).
- `spec/jobs/app_user_trigger_job_spec.rb` — `add_message(trigger, conversation)` у
  `described_class.new` с `@app` — дублёром `agent_bots: [bot]`; `trigger` — дублёр `id: 5, paths:
  [{"steps" => [{"step_uid" => "s1", "messages" => []}, {"step_uid" => "s2", "messages" => [<message>]}]}]`:
  `conversation.add_message` получает `step_id: "s2", trigger_id: 5, from: bot, message: {html_content:,
  serialized_content:, text_content: <html_content>}, controls: <controls>`; `paths: []` → `NoMethodError`.
- `spec/graphql/mutations/conversation_authors_spec.rb` — мутации прямым `resolve` (`klass.new(object: nil,
  field: nil, context:)`, без `graphql_post`): `InsertComment` с контекстом `{current_user: nil,
  get_app_user: -> { app_user }}` в разговор этого пользователя → `result[:message].authorable == app_user`;
  `StartConversation` с тем же контекстом → `result[:conversation].main_participant == app_user`;
  `CreateApp` агентом (`app_params: ActionController::Parameters.new(name:, domain_url:)`, `operation: "create"`)
  → приложение сохранено, `owner` — агент, `agent.apps.reload` его включает.

```bash
git add spec/lib/subdomain_or_domain_spec.rb spec/importers/list_importer_leads_spec.rb spec/services/action_trigger_factory_segment_spec.rb spec/models/bot_task_infix_spec.rb spec/models/app_package_integration_presenter_spec.rb spec/controllers/application_controller_cookie_spec.rb spec/graphql/mutations/update_conversation_state_spec.rb spec/jobs/sns_receiver_job_campaign_spec.rb spec/models/concerns/subscribable_payment_attribute_spec.rb spec/services/message_apis/safe_download_limits_spec.rb spec/jobs/app_user_trigger_job_spec.rb spec/graphql/mutations/conversation_authors_spec.rb
git status --short        # ожидается: ровно 12 строк "A  spec/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 12 files
git commit -m "Add R5b-2 characterization specs"
```

**Шаги 2–5. Патчи** (после каждого — ровно эта команда и коммит):

```bash
git apply $P/r5b2_routes.patch && git commit -qam "Remove unused subdomain constraints"
git apply $P/r5b2_eu.patch && git commit -qam "Remove eu_location? stub"
git apply $P/r5b2_autocorrect.patch && git commit -qam "Apply safe Lint autocorrections"
git apply $P/r5b2_manual.patch && git commit -qam "Fix remaining Lint offenses by hand"
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r5b2_tests_gate.sh $B` (≈ 10 мин). Нужны три
строки: `R5B2 TREE PASS …`, `R5B2 BASE PASS … char` (числа примеров — твои),
`R5B2 MUTANTS PASS 20/20 killed`. Пример красный или мутант выжил — поправь спеку его места (код и
мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Add R5b-2 characterization specs$')
git reset --hard "$C1" && git reset --soft HEAD~1   # 12 спек остаются, патчи сняты
# поправь спеки, затем — команды шагов 1–5, затем снова шаг 6
```

**Шаг 7. todo** — убрать блоки 11 копов вехи (`cops_whole` конфига):

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r5b2-probes/r5b2_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R5b-2 entries from RuboCop todo"
```

**Шаг 8. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r5b2

- Removed: unused routing constraints `PersonalizedDomain` and `NoSubdomain` and the `DOMAIN` constant
  (lib/subdomain_routes.rb), and the unused `ApiController#eu_location?` stub.
- Changed: remaining Lint offenses in app/ and lib/ cleaned up in 18 files without behaviour changes
  (AssignmentInCondition, BooleanSymbol, SymbolConversion, NonLocalExitFromIterator and others);
  characterization specs added.
```

```bash
git commit -am "Note fork-updates-r5b2 in changelog"
```

**Шаг 9.** Все десять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 10.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R5B2 … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 18 файлов кода (только патчами), 12 новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
  Существующие файлы `spec/` не менять.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`.
- Никаких ручных правок `app/`/`lib/`, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`,
  чтения исходников в спеках.
- `docs/specs/**` — не править (AC-009, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R5B2_CACHE=$HOME/.cache/chaskiq-r5b2-ci bash docs/specs/fork-updates-r5b2-probes/rspec_gate_r5b2.sh'`

- **AC-002** — пути и код: изменены ровно 18 файлов кода, 12 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с четырьмя патчами по порядку; todo = BASE без блоков 11 копов вехи; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5b2-probes/r5b2_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 12 файлов зелёные на коде дерева и на коде BASE, ошибок вне примеров нет; каждый из 20 мутантов r5b2_config.json (текст мутанта найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5B2_CACHE=$HOME/.cache/chaskiq-r5b2-ci bash docs/specs/fork-updates-r5b2-probes/r5b2_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у 11 копов вехи 0 офенсов во всём дереве; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5B2_CACHE=$HOME/.cache/chaskiq-r5b2-ci bash docs/specs/fork-updates-r5b2-probes/r5b2_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r5b2-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно 12 спек при коде BASE; каждый коммит патча оставляет код = BASE + патчи до своего включительно и ничего не добавляет; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r5b2 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5b2-probes/r5b2_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5b2-probes/source_scan.py $B'`

- **AC-008** — удалённых имён E1/E2 нигде нет: git grep PersonalizedDomain, NoSubdomain, DOMAIN (целым словом) в app, config, lib, spec кроме app/javascript и eu_location? там же ничего не находит (код 1; сбой git — FAIL).
  `bash -c 'git grep -nwE "PersonalizedDomain|NoSubdomain|DOMAIN" -- app config lib spec ":(exclude)app/javascript"; r1=$?; git grep -nF "eu_location?" -- app config lib spec; r2=$?; test $r1 -eq 1 && test $r2 -eq 1'`

- **AC-009** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "77feef4101941f02d05b20e6062a5b748a5e099ed94d23cccd1d16f6a7713e5c  docs/specs/fork-updates-r5b2-probes/r5b2_probe.py" "c7e476fe33952db529c40b2cbd463dfc9e448c8ddd2d08bbe562c48f01a17415  docs/specs/fork-updates-r5b2-probes/r5b2_config.json" "db5d8275f6e4c4ffc398ddebf82bbf754b50aca29d6ba52fdef5be7ef037ba2b  docs/specs/fork-updates-r5b2-probes/r5b2_tests.rb" "17206a756983fa94552cb0fc49ef3ae71db194e6a2e64bb242d309c1ce965f76  docs/specs/fork-updates-r5b2-probes/r5b2_tests_gate.sh" "51b3e5026782bb290e1cbddbccf397a960d27401495df8ef3a82b631f90942e3  docs/specs/fork-updates-r5b2-probes/r5b2_backlog_probe.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fork-updates-r5b2-probes/source_scan.py" "80af6985ecfaf14a14338428bd9aab297ad6e5e0b388e69c257b66c13e4bb5a1  docs/specs/fork-updates-r5b2-probes/r5b2_routes.patch" "030107a638f4b821323f230c0ad136bf0a6ab4fcfabf3ecf0872d8894aa31476  docs/specs/fork-updates-r5b2-probes/r5b2_eu.patch" "d815c57f919eff814d611348248c443640fe58d30ea9c3973312231fd74942f2  docs/specs/fork-updates-r5b2-probes/r5b2_autocorrect.patch" "2479cdcc7f06b34939830108d4f46d24ddc95060ba3a671592c556cdfb7a0fc1  docs/specs/fork-updates-r5b2-probes/r5b2_manual.patch" "9ebd14392ab8f3882cb08444eb8b7d253aadb92b859e7328a18ca36c903fc801  docs/specs/fork-updates-r5b2-probes/rspec_gate_r5b2.sh" "31762114463dc698d9056334daa94b32378f03c5aafdcafec534cbb95e72b9b1  docs/specs/fork-updates-r5b2-probes/r5b2_sentinel.rb" "6bafd8110e4f6b29b55ca38bae691c5058400b4668fe6da9d1c9efb49a782b9f  docs/specs/fork-updates-r5b2-probes/examples_base.txt" "1b0af0b341480b51ac3f41b11b932beda947078c0e71fc32bb0ecf00b1be8081  docs/specs/fork-updates-r5b2-probes/pending_allowed.txt" "1d9ee377b84570373fac45f2d0cebe803db89e35f2c48c7e25e21fcd6c3621a5  docs/specs/fork-updates-r5b2-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-010** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-009, AC-010 зелёные; AC-002 красный (`… is not BASE +
r5b2_routes.patch, …`); AC-003 красный (спек нет — `no examples ran`); AC-004 красный (`… offenses left`);
AC-006 красный (`missing commits`); AC-008 красный (имена E1/E2 ещё на месте).

Пробный прогон автора (20.11.2026, свежий клон от BASE 4bd1b924, сборка по разделу 5 буквально, спеки
шага 1 — образцы постановщика):
- чистый клон: AC-005, AC-007 (`SOURCE SCAN PASS 0 files`), AC-009, AC-010 зелёные; AC-002, AC-004, AC-006,
  AC-008 красные с сообщениями выше (AC-001 и AC-003 на чистом клоне не гонялись);
- после сборки: все 10 AC зелёные — rspec 788 examples (25 новых), 0 failures, 30 pending, сторож 760;
  AC-003 `R5B2 TREE PASS 25 examples`, `R5B2 BASE PASS 25 char`, `R5B2 MUTANTS PASS 20/20 killed`;
  AC-004 backlog без todo BASE 1282 → 1228; AC-007 `SOURCE SCAN PASS 12 files`; файлов от root нет;
- порченые правки (все ловятся; прогнаны на сборке с 11 спеками, пробники кроме конфига те же): строка
  `File.read(Rails.root.join("lib/subdomain_routes.rb"))` в спеке → AC-007; ручная правка `app/models/lead.rb`
  → AC-002; правка существующей `spec/models/app_user_spec.rb` → AC-002 «not an R5b-2 path»; слабая спека
  `SubdomainOrDomain` (только «не бросает») → AC-003, выжили M01, M02.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r5b2.md --exclude "docs/specs/fork-updates-r5b2-probes/**" --context "chaskiq fork-updates-r5b2: остальные Lint в 18 файлах app/ и lib/ патчами постановщика без смены поведения (AssignmentInCondition, BooleanSymbol, SymbolConversion, NonLocalExitFromIterator и др.); удалены мёртвые PersonalizedDomain/NoSubdomain/DOMAIN и eu_location? (решения владельца E1/E2); 12 характеризационных спек (зелёные на BASE), 20 мутантов; спеки не читают исходники как текст; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r5b2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r5b2-probes/**

Контекст ревьюерам: найти замену, которая меняет поведение (раздел 3), удалённое имя, которое где-то
используется, и спеку, которая проверяет текст кода, а не поведение. Код править нельзя — замечание
по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r5b2.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r5b2.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все десять критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004/AC-005 красные — дефект спеки;
- характеризационный пример не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение
  (BASE ведёт себя иначе) — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл замену с наблюдаемым эффектом или живое использование удалённого имени — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки `app/`/`lib/`, правка существующих спек, пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, глушить вывод и коды возврата.

## 10. Стыки

- `EULocationError` (класс в `api_controller.rb:134`) после E2 нигде не бросается, но назван в
  `rescue EULocationError, OriginValidator::NonAcceptedOrigin` (`api/graphql_controller.rb:49`): удалить
  его можно только вместе с этим упоминанием — вопрос владельцу, не в этой вехе.
- `EuCountries` используется в `messenger_type.rb:37` (`needs_privacy_consent` при
  `privacy_consent_required == "eu"`), но вызов сломан: `EuCountries.include?(code)` — это
  `Module#include?`, он бросает `TypeError` на строке и на `nil`; метод модуля называется `includes?` и
  объявлен методом экземпляра. Кандидат в баг-фикс (отдельная веха с тестом, красным на BASE).
- `Lint/*` в `spec/` — R6c (`docs/specs/fork-updates-r6c.md`).
