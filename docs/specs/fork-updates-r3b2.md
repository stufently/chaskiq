# fork-updates-r3b2 — бэклог RuboCop, шаг 3b-2: Rails OrderArguments, Pluck, WhereRange, Delegate — тест на каждое место

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r3b2.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (R3b: «R3b-2 — `OrderArguments`, `Pluck`, `WhereRange`,
  `StrongParametersExpect`, `Delegate`»).
- BASE_SHA: `ff28cdb92caabb5d77c2329e6a3e39bf3953182e` — HEAD `main` после влития R5b-2, R6c, mut-r5b1 и mut-m9-m14b
  (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1).
- BASE плавающий: если `main` уйдёт дальше до запуска, постановщик переносит его (раздел 2),
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 30 КБ
  (22 файла четырьмя патчами, 13 новых спек, todo, CHANGELOG) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все десять критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.** «Сделал часть» — не конец работы.
- Цель: в дереве не остаётся `Rails/OrderArguments` (19), `Rails/Pluck` (9), `Rails/WhereRange` (1),
  `Rails/Delegate` (2) — 31 офенс, 22 файла (18 в `app/`, 4 существующие спеки). **Поведение не
  меняется** (раздел 3). Код правки задан патчами постановщика (автокоррекция RuboCop, руками не
  править), работа исполнителя — 13 характеризационных спек (зелёные на BASE и после правки), и каждый
  из 23 мутантов постановщика (`r3b2_config.json`, `mutants`) роняет пример.
- **`Rails/StrongParametersExpect` (3) в эту веху не входит** — его делает следующая веха
  `fork-updates-r3b3` (решение владельца, раздел 10); его блок в todo остаётся.
- **`spec/`: 13 НОВЫХ файлов** (раздел 5) и правка `Pluck` в четырёх существующих спеках — только
  патчем. Другие существующие спеки не трогать.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Сравнение `to_sql` с текстом тоже
не убийство: проверяется **порядок и состав записей**, которые вернул код. Мутант убит, только если код
с мутантом **ведёт себя** иначе. AC-007 (`source_scan.py`) ищет эти приёмы в новых и изменённых файлах
`spec/` и валит критерий на любом совпадении; ревьюеры смотрят и остальное.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r3b2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r3b2-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (иначе Docker создаст точку монтирования от root; пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r3b2-ci` — копия `chaskiq-r5b2-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r5b2-ci $HOME/.cache/chaskiq-r3b2-ci`.
2. BASE уже перенесён на ff28cdb9 (R5b-2, R6c, mut-r5b1, mut-m9-m14b влиты): четыре патча применяются
   (`git apply --check`), тексты 23 мутантов — по одному разу, имена 13 спек свободны, снимки сняты
   `--write-base` на ff28cdb9. При следующем переносе: `git apply --check` четырёх патчей по порядку; если
   не применяются — пересобрать теми же командами RuboCop (раздел 3) и перепроверить тексты мутантов
   (каждый ровно один раз в своём файле). Перегенерировать список примеров
   `CHASKIQ_R3B2_CACHE=$HOME/.cache/chaskiq-r3b2-ci bash docs/specs/fork-updates-r3b2-probes/rspec_gate_r3b2.sh --write-base`
   на чистом checkout `main`, проверить, что имена 13 новых спек не заняты, пересчитать sha256 в AC-009.
   Сейчас в снимках — список примеров ff28cdb9. Параллельно идёт fix-cleanup-bugs (`messenger_type.rb`:
   там строка 37, здесь 50; патчи применяются в любом порядке — проверено на ff28cdb9).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-009 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE. Патчи — вывод `rubocop -A --only <коп>` по файлам офенсов, по копу на патч, в порядке
`OrderArguments` → `Pluck` → `WhereRange` → `Delegate`.

**`r3b2_order.patch` — `Rails/OrderArguments`, 19 мест, 14 файлов.** `order("x asc")` → `order(:x)`,
`order("x desc")` → `order(x: :desc)`, `order("id")` → `order(:id)`. SQL меняется с `ORDER BY x desc` на
`ORDER BY "table"."x" DESC`. Равносильно: в PostgreSQL голое имя в `ORDER BY` сначала ищется среди
выходных столбцов `SELECT`; во всех 19 запросах список — `table.*` (или `DISTINCT table.*`), так что
голое имя — тот же столбец этой таблицы, и при `JOIN` тоже (проверено вживую: `messenger_type.rb:50`,
`conversations JOIN app_users`, оба SQL выполняются и дают одно и то же). Места:
`types/app_type.rb:201` (`app_packages`), `:401` (`segments`, `union_scope` — `WHERE id IN (…)`, не `UNION`
во `FROM`), `:423` (`assignment_rules`; поверх `default_scope` того же порядка — без изменения),
`:563` (`collections`); `types/app_user_type.rb:74` (`visits`), `:88` (`conversations`);
`types/article_settings_type.rb:109`; `types/bot_task_type.rb:38`, `types/campaign_type.rb:45` (`metrics`);
`types/conversation_type.rb:55`, `types/public_conversation_type.rb:18` (`messages`);
`types/messenger_type.rb:50` (`conversations`); `chat_notifier_mailer.rb:52` (заголовок `References`);
`assignment_rule.rb:8` (`default_scope`); `conversation.rb:20,23` (`latest_message`,
`public_latest_message`); `message.rb:22` (`scope :ordered`); `audits_reports/api.rb:44`;
`open_ai/api.rb:158` (`previous_messages`).

**`r3b2_pluck.patch` — `Rails/Pluck`, 9 мест.** `map { |o| o[k] }` → `pluck(k)`. Равносильно:
получатели — массивы, не отношения ActiveRecord, а `Enumerable#pluck` ActiveSupport 8.1.4.1 с одним
ключом — ровно `map { |element| element[key] }` (`core_ext/enumerable.rb:145-151`). Места:
`segment.rb:337` (`predicates&.filter {…}` — Array), `open_ai/api.rb:117` (`parsed_content["blocks"]` —
Array из JSON), спеки `hooks/dialog_360_spec.rb:283,290`, `hooks/telegram_spec.rb:631`,
`hooks/twilio_spec.rb:603,604,641`, `hooks/twitter_spec.rb:49` (массивы тел запросов WebMock).

**`r3b2_where_range.patch` — `Rails/WhereRange`, `types/article_type.rb:32`** (`prev_article_url`):
`where("position < ?", p)` → `where(position: ...p)` — тот же `"articles"."position" < p`; `p` не `nil`
(две строки выше `return nil if object.position.blank?`); `published` уже сортирует по `position`.

**`r3b2_delegate.patch` — `Rails/Delegate`, 2 места.**
- `globalize_accessors.rb:78` — `def localized_attr_name_for(a, l) = self.class.localized_attr_name_for(a, l)`
  → `delegate :localized_attr_name_for, to: :class`: тот же вызов, класс не бывает `nil`.
- `messenger_events_channel.rb:105` — `def data_submit(data, message)` → `delegate :data_submit,
  to: :ActionTrigger`. Внутри приложения метод канала никто не вызывает (`ActionTrigger` зовёт свой
  `self.data_submit`); единственный вызывающий — клиент через ActionCable (`messenger.tsx:1247`,
  `pushEvent('data_submit', …)`). `ActionCable::Channel::Base#dispatch_action` (actioncable 8.1.4.1,
  `channel/base.rb:295-305`) передаёт данные, только если `arity == 1`; было 2, стало -1 — в обоих
  случаях `public_send(action)` без аргументов и `ArgumentError` (раньше в методе канала, теперь в
  `ActionTrigger.data_submit`). Исход тот же.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r3b2-ci`) на
клоне BASE 38a132da (повторено на ff28cdb9 — раздел 7):

1. Rubocop без todo на BASE: у четырёх копов вехи 31 офенс, все в 22 файлах раздела 3. Патчи —
   вывод автокоррекции по порядку.
2. `to_sql` и выполнение запросов `messenger_type`, `app_packages`, `segments`, `assignment_rules`,
   `visits`, `audits` до и после: отличие только в квалификации столбца, результаты те же.
3. Образцы 13 спек постановщика (раздел 5 описывает их содержание): 23 примера зелёные на дереве и
   на BASE; 23/23 мутантов убиты проверками порядка и значений (`expected … got …`), не ошибками.
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: порядок при равных ключах сортировки (например, одинаковый `updated_at`) не определён и
до, и после — спеки задают различающиеся значения.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код и существующие спеки — **только** `git apply` патчей. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r3b2-probes
export CHASKIQ_R3B2_CACHE=$HOME/.cache/chaskiq-r3b2-ci
```

**Шаг 1. Характеризационные спеки** — 13 НОВЫХ файлов, код = BASE. В каждом
`# frozen_string_literal: true`, `require "rails_helper"`. Типы GraphQL — экземпляром
`Types::XType.send(:new, object, context_hash)` и вызовом метода поля (без `graphql_post`: тот берёт текст
запроса из `npx ts-node` и падает от среды); `FactoryBot.create(:app)`, `app.add_agent({ email:, first_name: }).agent`,
`app.add_user(email:, first_name:)`, части разговора — `conversation.add_message(from:, message: {html_content:},
private_note:, email_message_id:)`. Порядок проверяй на данных, где правильный порядок отличается от
порядка вставки или обратного. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив и чтения исходников
(раздел 1). Что проверить:
- `spec/graphql/types/app_type_order_spec.rb` (агент — владелец: `app.update!(owner_id: agent.id)`,
  контекст `{current_user: agent}`): `app_packages` — два включённых опубликованных пакета
  (`AppPackage.new(name:, state: "enabled", published: true).save!(validate: false)`) идут по id по
  возрастанию; `segments` — id по возрастанию (их больше одного); `assignment_rules` — правила с
  `priority` 2, затем 1 → `[1, 2]`; `collections(lang: "en")` — коллекции «second» (`position: 2`), затем
  «first» (`position: 1`) → заголовки `["first", "second"]` (`acts_as_list` сдвигает номера, сравнивай заголовки).
- `spec/graphql/types/app_user_type_order_spec.rb` — `visits(page: 1, per: 10)`: новый id первым;
  `conversations(page: 1, per: 10)`: разговор с бо́льшим `updated_at` (`update_column`) первым.
- `spec/graphql/types/article_types_order_spec.rb` — `ArticleSettingsType#collections` (объект с `app`) —
  заголовки по `position`; `ArticleType#prev_article_url`: у единственной опубликованной статьи — `nil`;
  у статьи с `position: 3` при статье `position: 1` — та статья.
- `spec/graphql/types/metrics_order_spec.rb` — `BotTaskType#metrics` и `CampaignType#metrics`
  (`Metric.create!(trackable:, app_user:, action: "open")` дважды): новый id первым.
- `spec/graphql/types/conversation_order_spec.rb` — `ConversationType#messages(per: 10, page: 1)` и
  `PublicConversationType#messages`: новый id первым; `MessengerType#conversations` (контекст
  `{get_app_user: -> { user }}`): разговор с бо́льшим `updated_at` первым.
- `spec/models/conversation_latest_message_spec.rb` — `latest_message` — последняя часть;
  `public_latest_message` — последняя часть без `private_note` (после неё — приватная).
- `spec/models/message_ordered_spec.rb` — `BotTask.where(id:).ordered` по `position` (через `update_column`)
  по возрастанию, порядок вставки — обратный.
- `spec/mailers/chat_notifier_references_spec.rb` — `app.update!(outgoing_email_domain: "mail.example.com")`,
  разговор пользователя с назначенным агентом, три части с `email_message_id` `m1`, `m2`, `m3`, затем часть
  без него: `ChatNotifierMailer.notify(part).header["References"].to_s == "<m3> <m2>"`.
- `spec/services/message_apis/audits_reports_order_spec.rb` — `report("events_table", <объект с app>,
  { page: 1 })[:collection]` (экземпляр через `allocate`): `"id"` двух аудитов — новый первым.
- `spec/services/message_apis/open_ai_prompt_spec.rb` — канал `open_ai` с `data: {prompt:}`; части
  «first», «second», затем часть с `serialized_content`, где `blocks` — `[{text: "hello"}, {text: "world"}]`
  (и `content` для правил назначения); `get_gpt_response` заглушен и запоминает сообщения;
  `notify_message(conversation:, part:, channel: nil)` → содержимое сообщений `["first", "second", "hello world"]`.
- `spec/models/segment_clause_group_spec.rb` — `clause_group` (через `send`) собирает и сплющивает
  `fragment` предикатов одного `clause`: `[1, 2, 4]`; для `nil` — `[]`.
- `spec/channels/messenger_events_data_submit_spec.rb` — `MessengerEventsChannel.allocate.data_submit(data, :message)`
  вызывает `ActionTrigger.data_submit(data, :message)` с теми же аргументами и возвращает его результат.
- `spec/models/globalize_attr_name_spec.rb` — `Article.new.localized_attr_name_for(:title, :"pt-BR") == "title_pt_br"`.

```bash
git add spec/channels/messenger_events_data_submit_spec.rb spec/graphql/types/app_type_order_spec.rb spec/graphql/types/app_user_type_order_spec.rb spec/graphql/types/article_types_order_spec.rb spec/graphql/types/conversation_order_spec.rb spec/graphql/types/metrics_order_spec.rb spec/mailers/chat_notifier_references_spec.rb spec/models/conversation_latest_message_spec.rb spec/models/globalize_attr_name_spec.rb spec/models/message_ordered_spec.rb spec/models/segment_clause_group_spec.rb spec/services/message_apis/audits_reports_order_spec.rb spec/services/message_apis/open_ai_prompt_spec.rb
git status --short        # ожидается: ровно 13 строк "A  spec/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 13 files
git commit -m "Add R3b-2 characterization specs"
```

**Шаги 2–5. Патчи** (после каждого — ровно эта команда и коммит):

```bash
git apply $P/r3b2_order.patch && git commit -qam "Use hash arguments in order"
git apply $P/r3b2_pluck.patch && git commit -qam "Use pluck for key maps"
git apply $P/r3b2_where_range.patch && git commit -qam "Use a range in prev_article_url"
git apply $P/r3b2_delegate.patch && git commit -qam "Use delegate for forwarders"
```

**Шаг 6. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r3b2_tests_gate.sh $B` (≈ 8 мин). Нужны три
строки: `R3B2 TREE PASS …`, `R3B2 BASE PASS … char` (числа примеров — твои),
`R3B2 MUTANTS PASS 23/23 killed`. Пример красный или мутант выжил — поправь спеку его места (код и
мутантов не трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Add R3b-2 characterization specs$')
git reset --hard "$C1" && git reset --soft HEAD~1   # 13 спек остаются, патчи сняты
# поправь спеки, затем — команды шагов 1–5, затем снова шаг 6
```

**Шаг 7. todo** — убрать блоки четырёх копов вехи (`cops_whole` конфига; `Rails/StrongParametersExpect` остаётся):

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r3b2-probes/r3b2_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R3b-2 entries from RuboCop todo"
```

**Шаг 8. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-20 — fork-updates-r3b2

- Changed: Rails/OrderArguments, Rails/Pluck, Rails/WhereRange and Rails/Delegate cleaned up in 22 files
  (hash arguments in `order`, `pluck` on arrays, a range in `prev_article_url`, `delegate` for two
  forwarders) without behaviour changes; characterization specs added for every site.
```

```bash
git commit -am "Note fork-updates-r3b2 in changelog"
```

**Шаг 9.** Все десять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 10.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R3B2 … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 22 файлов (только патчами), 13 новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`.
- Три места `Rails/StrongParametersExpect` и их блок todo.
- Никаких ручных правок кода и существующих спек, `# rubocop:` директив, `pending`/`skip`,
  `--auto-gen-config`, чтения исходников в спеках.
- `docs/specs/**` — не править (AC-009, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R3B2_CACHE=$HOME/.cache/chaskiq-r3b2-ci bash docs/specs/fork-updates-r3b2-probes/rspec_gate_r3b2.sh'`

- **AC-002** — пути и код: изменены ровно 22 файла патчей (18 в app/ и 4 существующие спеки), 13 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патчей побайтно равен BASE с четырьмя патчами по порядку; todo = BASE без блоков четырёх копов вехи; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b2-probes/r3b2_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 13 файлов зелёные на коде дерева и на коде BASE, ошибок вне примеров нет; каждый из 23 мутантов r3b2_config.json (текст мутанта найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B2_CACHE=$HOME/.cache/chaskiq-r3b2-ci bash docs/specs/fork-updates-r3b2-probes/r3b2_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Rails/OrderArguments, Rails/Pluck, Rails/WhereRange, Rails/Delegate 0 офенсов во всём дереве; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B2_CACHE=$HOME/.cache/chaskiq-r3b2-ci bash docs/specs/fork-updates-r3b2-probes/r3b2_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r3b2-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно 13 спек при коде BASE; каждый коммит патча оставляет файлы патчей = BASE + патчи до своего включительно и ничего не добавляет; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r3b2 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b2-probes/r3b2_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b2-probes/source_scan.py $B'`

- **AC-008** — Rails/StrongParametersExpect не тронут (решение владельца ещё нет): три его файла побайтно равны BASE, его блок в todo на месте.
  `bash -c 'B=$(git merge-base HEAD @{u}) && git diff --quiet $B HEAD -- app/controllers/api/v1/hooks/provider_controller.rb app/controllers/application_controller.rb app/controllers/concerns/package_iframe_behavior.rb && grep -qx "Rails/StrongParametersExpect:" .rubocop_todo.yml'`

- **AC-009** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "4e50a7778012886cc71651323684754d19a3c34f4140489278067502e3b5ae69  docs/specs/fork-updates-r3b2-probes/r3b2_probe.py" "87f06bc0d9ea66854051c58f616475a8078a5872bbd3c4be0e896b346cf5f318  docs/specs/fork-updates-r3b2-probes/r3b2_config.json" "b7591fc5fa8bb08f153b96650a52ae539a4ba0ea5fe71650c8dcf1af5858eb69  docs/specs/fork-updates-r3b2-probes/r3b2_tests.rb" "f9986296f8f2c2023817f39bfdd1d46695e02e5b838225e0a1a664153c2d08ad  docs/specs/fork-updates-r3b2-probes/r3b2_tests_gate.sh" "6f8762ce25c186f780afd575980e985637c0006500db612ea673212e645efe16  docs/specs/fork-updates-r3b2-probes/r3b2_backlog_probe.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fork-updates-r3b2-probes/source_scan.py" "97888dc178529f40cef7b7cd511fd8dc370017383a1b6edb68c63b82fc12671b  docs/specs/fork-updates-r3b2-probes/r3b2_order.patch" "fbae316119c749a102b94edad449e817ede6755f35930ed4778bdd450a2ece38  docs/specs/fork-updates-r3b2-probes/r3b2_pluck.patch" "e5a4a6cdf8223d94364186d248e3c93f622981d21a8a2f310be992bdfdee502f  docs/specs/fork-updates-r3b2-probes/r3b2_where_range.patch" "76f5797c0464a73d198cb2f83a215289e74e7c3345ee455b84a84a5554defc96  docs/specs/fork-updates-r3b2-probes/r3b2_delegate.patch" "9707a2fdfafaa4ef672bec4044c0902e3ffe573ccd0201f193b1d1851f26b349  docs/specs/fork-updates-r3b2-probes/rspec_gate_r3b2.sh" "04169e42025538f515c49652d99237b2bd538208165c95ed971c19215a11c020  docs/specs/fork-updates-r3b2-probes/r3b2_sentinel.rb" "a0a9778af2766c14c28c330b1ad90e9d437a981c4c613fea580a56cfa0063f28  docs/specs/fork-updates-r3b2-probes/examples_base.txt" "8481b827024aa1f161b519d586a46805aca4f976f0e157c228ce85d28ea97fe5  docs/specs/fork-updates-r3b2-probes/pending_allowed.txt" "20fab06f2294ae690784481c9314ea7c4c67d1be288b8a98bed48cb9971c921a  docs/specs/fork-updates-r3b2-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-010** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009, AC-010 зелёные; AC-002 красный (`… is not
BASE + r3b2_order.patch, …`); AC-003 красный (спек нет — `no examples ran`); AC-004 красный (`… offenses
left`); AC-006 красный (`missing commits`).

Пробный прогон автора (21.11.2026, свежий клон от BASE ff28cdb9 со спекой поверх, сборка по разделу 5 буквально, спеки
шага 1 — образцы постановщика):
- чистый клон: AC-005, AC-007 (`SOURCE SCAN PASS 0 files`), AC-008, AC-009, AC-010 зелёные; AC-002, AC-004,
  AC-006 красные с сообщениями выше (AC-001 и AC-003 на чистом клоне не гонялись);
- после сборки: все 10 AC зелёные — rspec 968 examples (23 новых), 0 failures, 30 pending, сторож 932;
  AC-003 `R3B2 TREE PASS 23 examples`, `R3B2 BASE PASS 23 char`, `R3B2 MUTANTS PASS 23/23 killed`;
  AC-004 backlog без todo BASE 1124 → 1093; AC-007 `SOURCE SCAN PASS 17 files` (13 новых + 4 спеки патча);
  файлов от root нет;
- порченые правки (все ловятся): `Rails.root.join("app/graphql/types/app_type.rb").read` в спеке → AC-007;
  ручная правка `app/models/lead.rb` → AC-002 «not an R3b-2 path»; `params.expect(:id)` в
  `application_controller.rb` → AC-008; спека `visits`/`conversations` без проверки порядка → AC-003,
  выжили M04, M05.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r3b2.md --exclude "docs/specs/fork-updates-r3b2-probes/**" --context "chaskiq fork-updates-r3b2: Rails/OrderArguments 19, Pluck 9, WhereRange 1, Delegate 2 автокоррекцией RuboCop (патчи постановщика) без смены поведения; 13 характеризационных спек (порядок и состав записей, зелёные на BASE), 23 мутанта; StrongParametersExpect не тронут (веха R3b-3); спеки не читают исходники как текст; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r3b2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r3b2-probes/**

Контекст ревьюерам: найти место, где квалифицированный столбец `ORDER BY` даёт другой порядок, `pluck`
вызван на отношении или объекте со своим `pluck`, диапазон меняет границу, `delegate` меняет вызов; и
спеку, которая проверяет текст или SQL, а не результат. Код править нельзя — замечание по месту решает
постановщик (раздел 9); спеки — можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r3b2.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r3b2.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все десять критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004/AC-005 красные — дефект спеки;
- характеризационный пример не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение
  (BASE ведёт себя иначе) — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник или
  сравнивать SQL-текст, чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл замену с наблюдаемым эффектом — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, глушить вывод и коды возврата.

## 10. Стыки

- **`Rails/StrongParametersExpect` → `fork-updates-r3b3`** (решение владельца 2026-11-20, G1): два
  параметра пути — `params.expect` нейтрально, `package_iframe_behavior.rb:71` — руками
  `params.expect(user: [:id])[:id]` (400 вместо 500/404). R3b-3 идёт после этой вехи: AC-008 здесь
  требует, чтобы её три файла и блок todo были нетронуты.
- После этой вехи из Rails-копов в todo остаётся только `Rails/StrongParametersExpect`.
