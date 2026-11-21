# fork-updates-r9b — бэклог RuboCop, шаг 9b: оставшиеся одиночные Style, поведение сохранено

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r9b.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «Решения 2026-11-21 по оставшимся не-Metrics копам»:
  «`SafeNavigationChainLength`, `MultilineBlockChain`: переписать (локальная переменная / промежуточный
  результат), с тестами; без поднятия Max», «`StringConcatenation`: интерполяция только там, где операнды
  гарантированно не nil … сомнительные места — тест на nil до правки», «`IfUnlessModifier`: безопасная
  автокоррекция», «Прочие одиночные Style — исправить по копу с тестами»). Парная веха — `fork-updates-r9a`
  (`CaseEquality`, `PredicateMethod`), файлы кода не пересекаются.
- BASE_SHA: `51ffdcadcc5c122fb41a818bb2d74511d65d4e88` — HEAD `main` «Record decisions for remaining Style cops»
  (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r9a` или другая веха — раздел 10), постановщик переносит BASE (раздел 2),
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 45 КБ (больше половины — новые спеки).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в дереве не остаётся 46 офенсов 16 копов (раздел 3; 14 блоков todo уходят целиком, у четырёх
  общих с r9a и у двух укоротившихся Metrics-выбросов — строки этих файлов). Код и `.rubocop.yml` заданы
  двумя патчами постановщика (руками не править): `r9b_modifier.patch` — автокоррекция
  `IfUnlessModifier`, байткод файлов тот же, что на BASE (AC-003 сравнивает); `r9b_rewrite.patch` — остальное.
  Работа исполнителя — семь НОВЫХ спек, зелёных на BASE и после (характеризация); каждый из 46 мутантов
  постановщика (`r9b_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе. AC-007
(`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на любом совпадении
(исключение одно: `app/javascript/` — JS-входы тестового клиента GraphQL, Ruby-кода там нет).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r9b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r9b-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r9b-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` обоих патчей по порядку; блоки `cops_whole` и строки `cops_partial`
   конфига в todo на месте (иначе пробник падает со «spec defect»); тексты 46 мутантов — каждый ровно один раз в
   своём файле после патчей; имена семи новых спек не заняты. Перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R9B_CACHE=$HOME/.cache/chaskiq-r9b-ci bash docs/specs/fork-updates-r9b-probes/rspec_gate_r9b.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1155 примеров BASE 51ffdcad.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 51ffdcad: всего 345, не-Metrics 88, у копов вехи 46. После патчей — 296
(−49: 46 вехи и три Metrics-выброса, ставшие короче); новых офенсов нет. Блоки `IdenticalConditionalBranches` и
`SpecialGlobalVars` (`EnforcedStyle: use_perl_names`) в todo пустые: без todo у них 0 офенсов — уходят.

| Коп (офенсов) | Где | Правка и почему поведение то же |
|---|---|---|
| `IfUnlessModifier` (4) | `app_type.rb:164`, `app.rb:228`, `globalize_accessors.rb:62`, `twilio_phone/api.rb:169` | автокоррект; байткод файла = BASE (AC-003, `R9B ISEQ PASS 4 files`) |
| `SafeNavigationChainLength` (10) | `hooks_controller.rb:99`, `app_type.rb:63`, `action_trigger.rb:90`, `dialog360/api.rb` ×2, `message_bird`, `telegram`, `twilio` ×2, `vonage` | цепочка `a&.b&.c&.d` делится на две через локальную: `x = a&.b&.c; x&.d` — `nil` на любом шаге даёт `nil` и там, и там; в `action_trigger` локальные внутри блока `find` (то же число и порядок вычислений) |
| `MultilineBlockChain` (2) | `origin_validator.rb:21`, `paddle.rb:33` | промежуточный результат в локальную (`results`, `available`); `map`/`filter` и так жадные |
| `StringConcatenation` (15) | `event.rb:46`; спеки `hooks_controller_spec` ×9, `graphql_controller_spec`, `spec/support/graphql_queries.rb` | `"Events::#{…classify}"` (`classify` всегда String, `nil`-action падает на `gsub` до `+`); `Rails.root.to_s + "/spec/…"` → `Rails.root.join("spec/…").read`; `Rails.root + "app/javascript/…"` (это `Pathname#+`, автокоррект дал бы путь без `/`) → `Rails.root.join(…)` |
| `StringConcatenation` — **настройка** | `api/graphql_controller.rb:17`, `graphql_controller.rb:16`, `campaign.rb:82` | **Exclude с причиной в `.rubocop.yml`**: `"X" + operationName` бросает `TypeError` на Array/Hash/числе от клиента (оба контроллера отвечают ошибкой), `name + "-copy"` бросает `NoMethodError` у кампании без имени; интерполяция приняла бы оба. Поведение остаётся, спеки его пиннят |
| `CaseLikeIf` (1) | `app_type.rb:468` | `if mode == …` → `case mode when …`: `mode` — String-аргумент GraphQL, `String#===` = `==`; без `else`, как было |
| `HashLikeCase` (1) | `app_user.rb:321` | `STYLE_CLASSES[state]` (frozen-константа): `state` — String/nil, промах — `nil`, как у `case` без `else` |
| `FloatDivision` (1) | `campaign.rb:65` | `.to_f` с одной стороны: Float / Integer = Float / Float (размеры < 2^53) |
| `HashEachMethods` (1) | `globalize_accessors.rb:45` | `keys.each` → `each_key`: `translated_attributes` строит новый хэш на каждый вызов, в цикле его никто не меняет |
| `InverseMethods`+`SymbolProc` (3) | `plugin_schema_validator.rb:11` | `!map { valid? }.any? { !o }` → `map(&:valid?).all?` (`map` оставлен: `valid?` вызывается у каждого узла) |
| `SymbolProc` (1) | `lib/tasks/utils.rake:21` | `find_each(&:attach_default_packages)` (публичный метод) |
| `MapIntoArray` (1) | `segment.rb:250` | `each` + `<<` → `map` |
| `ModuleMemberExistenceCheck` (1) | `conversation_part_block.rb:22` | `instance_methods.include?` → `method_defined?` (оба — public+protected с наследованием) |
| `MultipleComparison` (2) | `subscribable.rb:7,11` | `%w[active trialing].include?(status)`: статус — String/nil |
| `RedundantRegexpEscape` (1) | `block_manager.rb:156` | `\-` последним в классе → `-` (тот же набор символов) |
| `SafeNavigation` (1) | `app_package_integration.rb:115` | `register_hook if message_api_klass.respond_to?(:register_webhook)` — `nil.respond_to?` даёт `false`, та же ветка (`&.` счёл бы лишним `Lint/RedundantSafeNavigation`) |
| `SingleArgumentDig` (1) | `paddle.rb:40` | `p.dig("features")` → `p["features"]` (`HashWithIndifferentAccess`) |

`.rubocop.yml` — один новый блок `Style/StringConcatenation` (Exclude трёх файлов) после
`Rails/EnvironmentVariableAccess`, с причиной в комментарии.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 51ffdcad:

1. Замер RuboCop без todo до и после патчей (раздел 3); тела всех методов разделов 3 и 5 прочитаны
   (`translated_attributes` — в globalize 7.1.3, `Plan.get_by_id` — `HashWithIndifferentAccess`).
2. Образцы семи спек постановщика (раздел 5): 65 примеров зелёные на BASE и дереве; 46/46 мутантов убиты;
   байткод четырёх файлов после `r9b_modifier.patch` = BASE.
3. Полный сьют на BASE (`--write-base`): 1155 примеров, 0 failures, 30 pending.
4. Патчи применяются до и после патча `r9a`; todo обеих вех в любом порядке даёт один результат (раздел 10).
5. Пробный прогон по разделу 5 и порченые правки: итоги — раздел 7.

Предположение: ни один клиент не шлёт `operationName` не строкой намеренно (поведение всё равно сохранено).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. Код — **только** `git apply` патчей. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников
(раздел 1); спеки чисты под RuboCop (AC-004, AC-005). Значения проверяй точно. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r9b-probes
export CHASKIQ_R9B_CACHE=$HOME/.cache/chaskiq-r9b-ci
```

**Шаг 1. Модификаторы:**

```bash
git apply $P/r9b_modifier.patch && git commit -qam "Use modifier if/unless for one-line bodies"
```

**Шаг 2. Семь спек** (для каждого места — значение/вызов при обоих исходах и при `nil`, где он возможен):

- `spec/graphql/types/app_type_style_spec.rb` (`described_class.send(:new, app, {})`, `authorize!` застаблен):
  `app_packages_capabilities(kind: "nope")` → `raise_error(RuntimeError, "not in type")`, `kind: "inbox"` → `[]`;
  `articles(page: 1, per: 6, lang: "en", mode:, search: nil)` при застабленных `app.plan` и `app.articles`
  (`published`/`draft`/`page` → разные `double(per: …)`) — `"all"`, `"published"`, `"draft"` дают свой результат,
  другой mode → `NoMethodError`; `plans` — без `payment_service` → `nil`, сервис с `get_plans` →
  отсортировано по `:pricing`, `get_plans` → `nil` → `nil`.
- `spec/controllers/api/v1/hooks_email_text_part_spec.rb`: `Api::V1::HooksController.new`, застаблены
  `read_mail_file` и `handle_conversation_part` (→ `[nil, nil, nil]`), вызов `send(:process_email_notification,
  {"receipt"=>{"action"=>{…}},"mail"=>{"headers"=>[]}}.to_json)`: письмо `text/plain` → `handle_conversation_part`
  вызван; `multipart/mixed` только с `text/html` → не вызван.
- `spec/services/message_apis/profile_lookup_style_spec.rb`: участник —
  `double(external_profiles: profiles, phone:)`, `profiles.find_by(provider: <PROVIDER>)` → `double(profile_id:)` или
  `nil`; `@conn` подменён (`instance_variable_set`) двойником, чей `post` запоминает аргументы и бросает свою
  ошибку; часть — `double(private_note?: false, message: double(as_json: {"serialized_content" =>
  MessageApis::BlockManager.serialized_text("hi")}))`; у MessageBird и Vonage застаблен `delivery_hooks` → `{}`.
  Twilio (`"twilio"`): `send_message` шлёт `To:` профиля / без профиля → `nil`, `post` не вызван;
  `prepare_initiator_channel_for` — `update(conversation_channels_attributes: [{provider: "twilio",
  provider_channel_id: …}])` / без профиля (`add_participant_to_existing_user` → `nil`) →
  `ActiveRecord::Rollback`. MessageBird (`"message_bird"`): JSON `"to"` без `+` / без профиля → `nil`. Vonage
  (`"vonage"`): `"to" => {"type"=>"whatsapp","number"=>…}` / без профиля → `nil`. Dialog360 (`"dialog_360"`):
  `get_profile_for_participant` — id / `nil` для участника без профиля и для `nil`; `prepare_initiator_channel_for`
  как у Twilio (`find_conversation_by_channel("dialog_360", id)`). Telegram: `get_profile_for_participant(conversation)`
  — id / `nil`. TwilioPhone: `process_message(ActionController::Parameters.new(StatusCallbackEvent: …, Caller:
  "+300"), double)` возвращает результат застабленного `process_incoming_event`; `Caller: "client:support_agent"` —
  `process_incoming_event` не вызван (`package` — `double(app: nil)`). BlockManager:
  `absolute_url("https://cdn.test/a-b/%41%zz?q=1-2#x-y")` → `"https://cdn.test/a-b/%41%25zz?q=1-2#x-y"`.
- `spec/services/services_style_spec.rb`: `ActionTrigger.process_next_step(app, message, nil)` при
  `ActionTriggerFactory.find_task` → `[trigger, nil]`, `trigger.paths` — два пути с шагами `step_uid` 3 и 9 (у
  каждого `controls`), `message.message.blocks` → `{"next_step_uuid"=>"9"}`: `conversation.add_message` с
  `step_id: 9`; `message.message` → `nil` → `NoMethodError`. `OriginValidator#valid?` (host `http://loc.cl:3002`):
  список с host → `true`, без → `NonAcceptedOrigin`, `validate_domain` вызван у каждого из трёх доменов.
  `PaymentServices::Paddle#get_plans` (`Plan.all` и `get_data` застаблены): удалённые планы, известные
  локально, по порядку, с `features` и `name` локального плана, чужой id отброшен. `PluginSchemaValidator#valid?`
  (`schema` — двойники `valid?`): все `true` → `true`, один `false` → `false`, `nil` → `false`, `valid?` вызван и у
  узла после невалидного.
- `spec/models/models_style_spec.rb`: `Campaign#delivery_progress` (цепочки застаблены) 1 из 3 →
  `33.33333333333333`, без доставок → `0`; `Campaign#clone_newsletter` — имя `"Promo"` → `"Promo-copy"`, без имени →
  `NoMethodError` (пин Exclude); `App.new(…).plan.name` (`Plan.all` застаблен: id 11 `"pro"`, `"free"`) — stripe
  active/trialing и paddle active/trialing (`"11"`) → `"pro"`, `"canceled"` → `"free"`; `AppUser#style_class` —
  passive/subscribed/unsusbscribed/прочее/`nil`; `ConversationPartBlock#create_fase` — пакет `"Zoom"` (есть
  `create_fase`) заполняет `blocks["schema"]`, `"Csat"` → `nil` без `get_package_integration`;
  `AppPackageIntegration#handle_registration` (`send`) — API с `register_webhook` → `register_hook` вызван,
  `Object.new` и `nil` — нет; `Event#trigger_webhooks` — `"email_changed"` → `Events::EmailChanged.perform(event)`,
  `"conversations.started"` → `Events::ConversationsStarted`, неизвестное → `nil`, без action → `NoMethodError`;
  `QuickReply#delete_translation_if_all_blank(:es)` — перевод с текстом остаётся, пустой удаляется;
  `Segment#tagged_result(nil)` с предикатами tags `not_eq` — одна метка исключает своих, две — обоих.
- `spec/lib/tasks/packages_attach_spec.rb`: `require "thor"`, `Rails.application.load_tasks` (если задач нет),
  `Rails.logger` восстанавливается после примера; `packages:attach` вызывает `attach_default_packages` у каждого
  из двух приложений.
- `spec/controllers/graphql_operation_name_spec.rb` (пин Exclude): `post :execute, params: {query: "{ __typename }",
  operationName: ["x"]}` у `GraphqlController` и `Api::GraphqlController` → тело ответа содержит
  `"no implicit conversion of Array into String"`.

```bash
git apply $P/r9b_rewrite.patch
git add spec/graphql/types/app_type_style_spec.rb spec/controllers/api/v1/hooks_email_text_part_spec.rb spec/services/message_apis/profile_lookup_style_spec.rb spec/services/services_style_spec.rb spec/models/models_style_spec.rb spec/lib/tasks/packages_attach_spec.rb spec/controllers/graphql_operation_name_spec.rb
git status --short        # ожидается: 7 строк "A  spec/…" и 25 строк " M …"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 10 files
git commit -qam "Rewrite the remaining one-off Style offenses"
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r9b_tests_gate.sh $B` (≈ 6 мин). Нужны строки
`R9B TREE PASS … examples`, `R9B BASE PASS … char / 0 renamed failing / 0 fix failing`,
`R9B MUTANTS PASS 46/46 killed`, `R9B ISEQ PASS 4 files`. Пример красный на дереве или на BASE, мутант выжил —
поправь спеку (код, патчи и мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C2=$(git log --format=%H -1 --grep '^Rewrite the remaining one-off Style offenses$')
mkdir -p tmp/r9b-specs && git diff --name-only --diff-filter=A "$C2~1" HEAD -- spec | xargs cp --parents -t tmp/r9b-specs
git reset --hard "$C2~1"    # остаётся коммит шага 1; копии спек — в tmp/r9b-specs (tmp/ игнорируется)
# поправь спеки в tmp/r9b-specs/spec/…, затем: cp -r tmp/r9b-specs/spec/. spec/
# затем — команды шага 2, затем снова шаг 3
```

**Шаг 4. todo** — убрать блоки `cops_whole` и строки `cops_partial` конфига:

```bash
python3 -I - r9b <<'PY'
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
git commit -am "Drop R9b entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r9b

- Changed: the last one-off RuboCop Style offenses outside Metrics, behaviour kept: modifier if/unless
  (same bytecode), safe navigation chains split through a local, block chains through a local,
  interpolation instead of `+` where the operand is always a String, `case` and a frozen hash instead
  of if-chains and a hash-like `case`, `map`, `each_key`, `method_defined?`, `include?` on a word list.
- Changed: `Style/StringConcatenation` excludes the two GraphQL controllers and `campaign.rb`: there
  `+` raises on a non-String operand (client operationName, a nameless campaign) and that stays.
- Removed: empty todo blocks IdenticalConditionalBranches and SpecialGlobalVars. Seven specs pin the
  changed behaviour; the modifier rewrite is checked by bytecode.
```

```bash
git commit -am "Note fork-updates-r9b in changelog"
```

**Шаг 6.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка
`paths: …`; AC-003 — четыре строки `R9B … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 27 файлов патчей (только патчами), семи новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`; файлы вехи `r9a`
  (раздел 10); прочие блоки todo и строки Metrics/LineLength-выбросов, кроме двух строк `cops_partial`.
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R9B_CACHE=$HOME/.cache/chaskiq-r9b-ci bash docs/specs/fork-updates-r9b-probes/rspec_gate_r9b.sh'`

- **AC-002** — пути и код: изменены ровно 27 файлов патчей, 7 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патчей побайтно равен BASE с обоими патчами; todo = BASE без 14 блоков cops_whole и без строк cops_partial; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9b-probes/r9b_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 7 спек зелёные на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 46 мутантов r9b_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки; четыре файла iseq_same после одного r9b_modifier.patch компилируются в байткод BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R9B_CACHE=$HOME/.cache/chaskiq-r9b-ci bash docs/specs/fork-updates-r9b-probes/r9b_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у 14 копов cops_whole 0 офенсов во всём дереве, у копов cops_partial 0 в файлах вехи; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R9B_CACHE=$HOME/.cache/chaskiq-r9b-ci bash docs/specs/fork-updates-r9b-probes/r9b_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r9b-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит модификаторов — ровно 4 файла = BASE + r9b_modifier.patch; коммит правки — файлы r9b_rewrite.patch = BASE + оба патча и ровно 7 новых спек; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r9b после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9b-probes/r9b_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app (кроме app/javascript)/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r9b-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "443be9f456abeb22b532b68cba12f2704974292ad6beed694fab28daf40313a5  docs/specs/fork-updates-r9b-probes/examples_base.txt" "453f9ebd073a5cc110cd7b42d566af4a6c23ee0bbb8ece0751e2182c18b2cae5  docs/specs/fork-updates-r9b-probes/pending_allowed.txt" "d239605e0c9c72f6251b5c2f6f1951b495c030b4a0f8287b86ab612b96a88ed5  docs/specs/fork-updates-r9b-probes/r9b_backlog_probe.sh" "3619a8e9b5470818b15bfad07cd6a754b75b4712bbba3a470bb09802e7d56cfd  docs/specs/fork-updates-r9b-probes/r9b_config.json" "533305a069e4ad5c8466c35fff53a7186f7b5da132709680a7f09fb818794ee4  docs/specs/fork-updates-r9b-probes/r9b_iseq.rb" "a92c1af1bd6885b90fc66495d87e5ab618f0e768205e23f16a969eaa97c2b101  docs/specs/fork-updates-r9b-probes/r9b_modifier.patch" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r9b-probes/r9b_probe.py" "975fae2e45b8d202200740f1a9172871e775cc69a7bdee62586c347735f7e282  docs/specs/fork-updates-r9b-probes/r9b_rewrite.patch" "35181e4de2c3e17bf9cb3bead927d0aef7a87e22c448976a4548b3390c6679d8  docs/specs/fork-updates-r9b-probes/r9b_sentinel.rb" "b23e63448d6a69bb86147d5550174d85a4902af917f26c81cd340421470d8cf9  docs/specs/fork-updates-r9b-probes/r9b_tests.rb" "2a8ea442f1b1bbad04fde6c04cfe978543384883e738b452ee9bd3493c90f555  docs/specs/fork-updates-r9b-probes/r9b_tests_gate.sh" "f64d942c8d2566fb396cde3f340c1718b373d608af20740774a8deff624904ce  docs/specs/fork-updates-r9b-probes/rspec_gate_r9b.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r9b-probes/source_scan.py" "54db6575dc30d0d729e0881922a03a2a594b27f632e8f871f321fd27eb8de0f4  docs/specs/fork-updates-r9b-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный
(`R9B paths without the change`); AC-003 красный (спек нет — `no examples ran`, тексты мутантов не найдены);
AC-004 красный (`… offenses left`); AC-006 красный (`missing commits`).

Пробный прогон автора (21.11.2026; свежий клон BASE 51ffdcad со спекой и пробниками одним коммитом поверх,
ветка с upstream `origin/main`, сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия
`chaskiq-fxb-ci`, путь кэша в командах подменён на копию):
- чистый клон: AC-001 (1155 примеров, 0 failures, 30 pending, ≈ 7 мин), AC-005, AC-007 (`0 files`), AC-008, AC-009 —
  rc=0; AC-002, AC-003, AC-004 (`Style/CaseLikeIf: 1 offenses left` и т. д.), AC-006 красные с сообщениями выше;
- после сборки: все 9 AC rc=0 — rspec 1220 примеров (65 новых), 0 failures, 30 pending; AC-003
  `R9B BASE PASS 65 char / 0 renamed failing / 0 fix failing`, `R9B MUTANTS PASS 46/46 killed`, `R9B ISEQ PASS 4
  files` (≈ 3,5 мин); AC-004 бэклог без todo 345 → 296 (у копов вехи и двух строк Metrics на BASE — 48);
  AC-007 `SOURCE SCAN PASS 10 files`;
- порченые правки (все ловятся): из спеки валидатора убран пример «valid? у каждого узла» → AC-003 (выжил B34);
  `Rails.root.join("app/models/app_user.rb").read` в спеке → AC-007 (исключение `app/javascript` его не
  пропускает); `if` → `unless` в `r9b_modifier.patch` и `app.rb` → AC-003 (`iseq_same: 3 of 4 files`), AC-002, AC-008.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r9a.md --exclude "docs/specs/fork-updates-r9a-probes/**" --exclude docs/specs/fork-updates-r9b.md --exclude "docs/specs/fork-updates-r9b-probes/**" --context "chaskiq fork-updates-r9b: последние одиночные RuboCop Style вне Metrics, поведение сохранено — IfUnlessModifier (байткод = BASE), SafeNavigationChainLength 10 и MultilineBlockChain 2 через локальную, StringConcatenation интерполяцией только где операнд всегда String (graphql-контроллеры и campaign.rb — Exclude с причиной: + бросает на не-String), CaseLikeIf, HashLikeCase, FloatDivision, HashEachMethods, InverseMethods/SymbolProc, MapIntoArray, ModuleMemberExistenceCheck, MultipleComparison, RedundantRegexpEscape, SafeNavigation, SingleArgumentDig; 7 спек характеризации зелёные на BASE; 46 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r9a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r9a-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r9b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r9b-probes/**

Контекст ревьюеру: место, где правка меняет поведение (`nil`, порядок или число вычислений, тип операнда),
Exclude, причина которого не совпадает с фактом, спека, проверяющая текст, а не поведение. Код править нельзя
— замечание по месту решает постановщик (раздел 9); спеки — можно, одним заходом.

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r9b.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r9b.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, `R9B ISEQ PASS` не пришёл
  или после патчей AC-004/AC-005 красные — дефект спеки;
- пример не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл место, где правка меняет поведение, или неверную причину Exclude — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патчей и мутантов, новые Exclude,
`pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

- **`fork-updates-r9a` (qw2) — парная веха, может идти параллельно.** Общих файлов кода нет. Общие:
  `.rubocop.yml` (r9b — новый блок после `Rails/EnvironmentVariableAccess`; r9a — блоки `Naming/PredicateMethod` и
  `Style/CaseEquality` ниже по файлу), `.rubocop_todo.yml` (r9b убирает свои строки из блоков `IfUnlessModifier`,
  `InverseMethods`, `MapIntoArray`, `SingleArgumentDig`, r9a — строки `messenger/api.rb`, `segment_comparator.rb`,
  `sns_receiver_job.rb`; опустевший блок удаляет та веха, что вливается второй — её ожидаемый todo считается от
  нового BASE сам) и `CHANGELOG.md`. Проверено на 51ffdcad: патчи и скрипты todo применяются в любом порядке,
  итог один, строгий RuboCop чист.
- **Кто вливается вторым, тому — перенос BASE, `--write-base` (новые примеры первой вехи) и sha256 AC-008**
  (раздел 2, п. 2).
- Три Metrics-выброса укоротились: строки `Metrics/AbcSize` `globalize_accessors.rb` и `Metrics/BlockLength`
  `app.rb` уходят из todo здесь (`cops_partial`); `Metrics/MethodLength` `twilio/api.rb` (2 → 1) остаётся выбросом.
- Мутационный прогон по семи спекам — у противоположного исполнителя (cx), после снятия запрета на Codex
  2026-11-22 11:39Z.
