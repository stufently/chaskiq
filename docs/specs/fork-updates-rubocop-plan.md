# План: бэклог RuboCop в ноль (вехи R1–R9, плюс R2b)

Дата: 2026-11-19. Цель владельца: `.rubocop_todo.yml` пуст и удалён, поведение приложения не
меняется (найденные баги чинятся отдельно, с тестом и строкой в `CHANGELOG.md`). Настройка в
`.rubocop.yml` вместо правки кода допустима только с записанной причиной рядом с ней; глобальное
`Enabled: false` без причины — нет.

## Замер (BASE `main` a6ec4ad4)

RuboCop 1.92.3, rubocop-rails 2.38.0, Ruby 3.3.14, образ `bin/ci-local`, `.rubocop.yml` без
строки `inherit_from: .rubocop_todo.yml`: **2565 офенсов, 507 файлов, 103 копа**; 129 из них — в
`docs/specs/*-probes` (уходят из-под RuboCop в R1). Без `docs/` — **2436**:

| Категория | Копов | Офенсов |
|---|---|---|
| ручные (автокорректа нет) | 27 | 1299 |
| безопасный автокоррект (`-a`) | 41 | 829 |
| небезопасный автокоррект (`-A`) | 26 | 308 |

По каталогам (с `docs/`): `app/services` 1105, `spec` 353, `app/models` 333, `app/graphql` 325,
`app/controllers` 160, `docs` 129, `app/jobs` 54, `lib` 41, прочее 65.

Топ-25 копов (без `docs/`; s — безопасный, u — небезопасный автокоррект, m — ручной):

| Коп | Офенсов | Файлов | | Веха |
|---|---|---|---|---|
| Metrics/MethodLength | 418 | 152 | m | R8 |
| Style/Documentation | 401 | 359 | m | R7 |
| Lint/UselessAssignment | 188 | 87 | s | R6 |
| Layout/LineLength | 179 | 65 | s (частично) | R8 |
| Metrics/AbcSize | 173 | 93 | m | R8 |
| Lint/UnusedMethodArgument | 165 | 56 | s (48 из 165) | R6 |
| Style/FrozenStringLiteralComment | 127 | 127 | u | R3 |
| Style/ClassAndModuleChildren | 70 | 70 | u | R4 |
| Metrics/CyclomaticComplexity | 53 | 37 | m | R8 |
| Metrics/ClassLength | 46 | 45 | m | R8 |
| Metrics/PerceivedComplexity | 39 | 30 | m | R8 |
| Layout/EmptyLinesAfterModuleInclusion | 39 | 22 | s | R1 |
| Style/GuardClause | 36 | 26 | s | R2 |
| Style/CaseEquality | 34 | 21 | m (s, но не корректирует) | R7 |
| Naming/AccessorMethodName | 32 | 19 | m | R7 |
| Style/OneClassPerFile | 27 | 5 | m | R7 |
| Lint/BooleanSymbol | 26 | 2 | u | R5 |
| Layout/FirstArrayElementIndentation | 24 | 5 | s | R1 |
| Layout/MultilineMethodCallIndentation | 22 | 4 | s | R1 |
| Rails/OrderArguments | 19 | 14 | u | R3 |
| Naming/MethodParameterName | 18 | 8 | m | R7 |
| Lint/Void | 17 | 16 | s | R5 |
| Style/HashAsLastArrayItem | 17 | 11 | s | R2 |
| Layout/EmptyLinesAroundClassBody | 15 | 15 | s | R1 |
| Style/IfUnlessModifier | 15 | 13 | s | R2 |

Ключевой инструмент: `docs/specs/fork-updates-r1-probes/r1_iseq.rb` — сравнение байткода YARV
файла на BASE и в дереве без номеров строк. Замер по 76 автокорректируемым копам (каждый
отдельно, `-A --only`): байткод не меняется у Layout-копов, `Style/RegexpLiteral`, `Semicolon`,
`TrailingCommaInArguments`, `WordArray`, `LambdaCall`, `NestedTernaryOperator`, `DirectiveScope`,
`IfUnlessModifier`, `RedundantReturn` (только на 3.3), `Lint/AmbiguousOperatorPrecedence`,
`AssignmentInCondition`, `AmbiguousBlockAssociation`; у остальных меняется.

## Порядок и правила для всех вех

- Строго последовательно: каждая веха правит `.rubocop_todo.yml` (удаляет секции своих копов
  целиком), параллельные ветки конфликтуют. Перегенерация `--auto-gen-config` запрещена во всех
  вехах.
- Порядок выбран так, чтобы поздние вехи не переделывали ранние: автокоррект стиля (R1–R4)
  раньше Lint (R5–R6), а те раньше ручных Naming/Style (R7) и Metrics/LineLength (R8) —
  автокоррект и вложенные модули меняют длины строк и методов, R8 меряется в самом конце.
- Каждая веха: полный rspec тем же списком примеров (гейт R1 переиспользуется,
  `--write-base` перед запуском), строгий `bin/ci-local --only rubocop`, пробник бэклога «свои копы
  0, чужие не выросли» (`r1_backlog_probe.sh` с другим списком), граница — только файлы из todo
  BASE под копами вехи. Конфиги (`.rubocop.yml`, `.rubocop_todo.yml`) сравниваются побайтово с
  ожидаемым текстом (RuboCop пропускает их через ERB), `<%` в их диффе запрещён.
- Исключения из «чужие не выросли» и из границы, заранее и списком в спеке вехи:
  - **Рост `Layout/LineLength` до R8.** R2 (`IfUnlessModifier`/`GuardClause`), R3 (строка
    `frozen_string_literal`) и особенно R4 (вложенные `module`/`class` сдвигают тело на 2–6
    пробелов) удлиняют строки. Разрешено: новые офенсы `Layout/LineLength` только в файлах, которые
    веха меняет, с добавлением этих файлов в секцию `Layout/LineLength` todo; пробник бэклога
    проверяет «вырос только LineLength и только в списке». Альтернатива на выбор владельца —
    вынести решение по лимиту `LineLength` (часть R8) перед R2; тогда исключение не нужно.
  - **Новые файлы в R7.** `Style/OneClassPerFile` (27 офенсов в 5 файлах) и `Style/MixinUsage`
    требуют разнести классы по файлам под Zeitwerk: спека R7 перечисляет новые пути явно
    (`app/…/<class>.rb` для каждого выносимого класса), граница разрешает ровно их, и они сразу
    чистые (в todo не попадают).
  - Новые офенсы Metrics от R2–R7 (например, развёрнутый `GuardClause` удлиняет метод) — так же,
    как LineLength: только в файлах вехи, с записью в секцию todo, разбираются в R8.
- После влития m11 (Telnyx) и m14 (Ruby 4.0.10) числа сдвинутся немного; каждая спека
  перемеряет перед запуском.

## R1 — Layout/Style без изменения байткода (влита, main 96509378)

- Копы: 16 (12 Layout + `Style/RegexpLiteral`, `Semicolon`, `TrailingCommaInArguments`,
  `WordArray`), 126 офенсов, 49 файлов; плюс `docs/**` в `AllCops: Exclude` с причиной (пробники
  заморожены sha256) и удаление всех строк `docs/` из todo (7 секций исчезают целиком).
- Подход: `rubocop -a --only <16>` + каскадный `-a --only Layout,Style/BlockDelimiters`;
  доказательство — байткод каждого файла равен BASE (Ruby 3.3.14 и 4.0.10).
- Риски: нет по построению; остаточный — каскады (закрыты вторым проходом, проверено).
- Спека: `docs/specs/fork-updates-r1.md`.

## R2 — автокоррект Style/Naming с меняющимся байткодом, каждое отличие объяснено (спека готова)

- Копы: 10, 95 офенсов, 46 файлов (замер на `main` d8c82e37, Ruby 4.0.10): `Style/GuardClause` 36,
  `HashAsLastArrayItem` 17, `IfUnlessModifier` 15, `RedundantParentheses` 14, `ArgumentsForwarding`
  4, `DirectiveScope` 3, `RedundantReturn` 2, `Naming/BlockForwarding` 2, `SuperArguments` 1,
  `EmptyStringInsideInterpolation` 1. `GuardClause` рождает 5 офенсов `Rails/Blank` (4 файла,
  `return unless x.present?`) — их НЕ исправляет R2: они вносятся в todo новой секцией (R3).
- Подход: коп за копом (коммит на коп); `r2_canon.rb` переводит старую и новую форму каждого
  преобразования в одну каноническую (Prism-деревья без позиций, литералы точно) при проверяемых
  условиях; необъяснённое отличие — FAIL; каждый коммит проверяется отдельно (родитель → коммит
  объяснён одним своим копом). Объявленные добавления в todo: `Metrics/BlockLength`
  `app/models/app.rb`, `ReturnNilInPredicateMethodDefinition` `open_ai/api.rb`, новая секция
  `Rails/Blank` (4 файла).
- Риски: guard clause не в хвосте метода (ловит правило «только хвост»), `return` в блоке.
- Спека: `docs/specs/fork-updates-r2.md`.

## R2b — Style-автокоррект, равенство которого механически не доказывается (ручной разбор)

- Копы: 16, 41 офенс (по `main` d8c82e37): `Style/StringConcatenation` 15, `SymbolProc` 3,
  `SingleArgumentDig` 3, `Naming/MemoizedInstanceVariableName` 3, `MapIntoArray` 2,
  `InverseMethods` 2, `MultipleComparison` 2, `ReturnNilInPredicateMethodDefinition` 2 (+1 из R2),
  `Bundler/OrderedGems` 2, `SafeNavigation`, `HashEachMethods`, `FloatDivision`, `CaseLikeIf`,
  `ModuleMemberExistenceCheck`, `MutableConstant`, `RedundantRegexpEscape` по 1.
- Почему не R2: равенство зависит от типа получателя (`+` против интерполяции, `&:m` и арность
  блока, `dig` против `[]`, `each`+`<<` против `map`, `!=` против `!(==)`, `x == a` против
  `[a].include?(x)` и `===` в `case`, `false&.m`, `keys.each` против `each_key`) или меняет
  поведение (`return` → `return false`, `.freeze`, переименование ivar, порядок `Bundler.require`).
- Подход: по месту — тип получателя установлен чтением кода (и тестом, если не очевиден);
  `r2_canon.rb` отчётом показывает, что других отличий нет; поведенческие (`nil`→`false`,
  `.freeze`, ivar, порядок гемов) — с тестом или отказ от автокорректа в пользу ручной правки.
- Риски: тип, который не виден из кода (динамические значения из JSON/параметров).

## R3 — `frozen_string_literal` (спека готова: `docs/specs/fork-updates-r3.md`)

Идёт раньше R2b: R2b — ручной разбор каждого места, R3 проверяется механически.

- Коп: `Style/FrozenStringLiteralComment`, 127 файлов (секция todo — 128, `bin/setup` RuboCop не
  инспектирует), +1 комментарий и пустая строка в каждом; каскад `Style/RedundantFreeze` 2
  (`"x".freeze` → `"x"`).
- Подход: коммит на коп, каждый коммит проверяется отдельно. Доказательство: (1) текст = BASE +
  комментарий наверху, дерево Prism то же без флагов заморозки; (2) статический разбор потоков
  (`r3_frozen.rb mutate`): ни один литерал этих файлов не доходит до мутатора String, буфера
  (`StringIO`, `read(n, buf)`, `CSV.generate`), мутирующего параметра или вызывающего, мутирующего
  возвращённый литерал — 0 находок; (3) eager load и полный сьют с
  `--enable-frozen-string-literal --debug-frozen-string-literal` (заморожены все литералы, включая
  гемы) — зелёные, без `FrozenError`; на BASE так же, и chilled-предупреждений нет.
- Риски: мутация на пути вне сьюта в гемах (статический разбор видит только `app/ lib/ config/
  spec/`); тела rake-задач проверены только статически.

## R3b — Rails-автокоррект (по тесту на каждое место)

- Копы: 8, 44 офенса (замер BASE прежнего R3 + `Rails/Blank` из R2): `Rails/OrderArguments` 19
  (u), `Pluck` 9 (u), `Blank` 5 (u, из R2: `return unless x.present?` в `connection.rb`,
  `types/app_type.rb`, `email_chat_notifier_job.rb`, `action_trigger.rb` ×2), `Presence` 4,
  `StrongParametersExpect` 3 (u), `Delegate` 2, `WhereRange` 1 (u), `Present` 1.
- Подход: по одному копу с тестом на каждое место, где меняется SQL или ответ:
  `order("x desc")` → `order(x: :desc)` (сравнить `to_sql`), `pluck` вместо `map` (только для
  отношений без загруженных ассоциаций), `params.expect` вместо `require.permit` (меняет ответ на
  кривые параметры: 400 вместо 500/игнора — сверить контракт API, при сомнении оставить
  `require.permit` и настроить коп с причиной). `Rails/Blank`/`Present`/`Presence` — только после
  проверки типа получателя в каждом месте: `blank? == !present?` и `presence` верны для
  ActiveSupport `Object`, но не для класса со своим `present?`/`blank?`; тип установить чтением
  кода, в пробнике — грепом `def present?`/`def blank?`/`def presence` в `app/`, `lib/`, `config/` и
  гемах по `Gemfile.lock`. `Delegate`: `delegate` определяет `def x(...)` и бросает
  `Module::DelegationError` на `nil` — проверить арность и `nil`-получателя.
- Риски: SQL-эквивалентность `OrderArguments`/`WhereRange`; контракт API для `expect`.

## R4 — `Style/ClassAndModuleChildren` (70 файлов; спека готова: `docs/specs/fork-updates-r4.md`)

Идёт раньше R2b/R3b (ручной разбор с тестами): проверяется механически. На черновике пробник
разрешения констант нашёл `Twilio` в `message_apis/twilio_phone/api.rb` — вложение дало бы
`MessageApis::Twilio`; файл оставлен компактным в todo (`::Twilio` + тест — в R7). Ещё четыре
презентера (`article_search`, `calendly`, `twilio_phone`, `ui_catalog`) вычисляют ERB с
`result(binding)` — константы в шаблонах пробник не видит, они тоже компактны до R7. Итого 65 файлов
вложены, 5 в `KEEP`. Проверка (после ревью Codex): комментарии неизменны, разрешение — до и после
загрузки плагинов `before_start.rb` и статически по определениям в `app/`/`lib/`, предки классов
BASE vs дерево в двух процессах; рост `Layout/LineLength` — ровно в двух файлах.

- Копы: 1, 70 офенсов/файлов (`app/controllers/agents/*`, `api/v1/*`, `app/services/dante/*`,
  `message_apis/*/{api,presenter}.rb`, `app/graphql/types/*`). Автокоррект `-A` переводит
  `class A::B` во вложенный `module A; class B`.
- Подход: автокоррект + пробник разрешения констант: для каждого неквалифицированного имени
  константы внутри перенесённых классов сравнить, во что оно разрешается до и после
  (вложенная форма добавляет `A` в `Module.nesting`, и `Foo` может стать `A::Foo`); eager load
  Zeitwerk в production/test. Альтернатива на выбор владельца — оставить compact там, где это
  принято (`EnforcedStyle` по каталогам с причиной), но смешанный стиль не исчезнет.
- Риски: смена разрешения константы (молчаливая смена поведения); рост отступов → новые
  `Layout/LineLength` (идёт до R8 намеренно).

## R5 — Lint: кандидаты в баги + `Security/Open` (ручной разбор)

- Копы: 19, 87 офенсов, 45 файлов. Каждое место — разбор «баг или намерение»; баг чинится с
  тестом и строкой в CHANGELOG, намерение — переписать явно (без `rubocop:disable`).
  - `Lint/DuplicateMethods` 3: `Plan#features=` (plan.rb:3 и :24), `Role#avatar_url`
    (role.rb:14 и :25), `AppUserDashboard#conversations` — работает только второе определение.
  - `Lint/BinaryOperatorWithIdenticalOperands` 2: `app/models/plan.rb:39` (`x >= x`),
    `app/services/fetch_link_card_service.rb:124` (`a || a`) — почти наверняка баги.
  - `Lint/UnreachableCode` `app/controllers/api_controller.rb:199`; `Lint/UselessOr`
    `app/models/audit.rb:23` (`"--"` никогда не подставится — `to_s` всегда строка);
    `Lint/MisplacedMagicComment` `app/services/payment_services/paddle.rb:95` (комментарий не
    действует).
  - `Lint/BooleanSymbol` 26: `app/services/plugin_schema_validator.rb` (25), `message.rb:17` —
    `:true` в схемах; автокоррект меняет ЗНАЧЕНИЯ — только руками, сверив с потребителем схемы.
  - `Lint/Void` 17: `self` в теле `initialize` плагинов (13) — безвредно, удалить; литералы
    `"photo"` (telegram/api.rb:257) и `1` в спеках — проверить, не потерян ли `return`/ассерт.
  - `Lint/AssignmentInCondition` 7, `NonLocalExitFromIterator` 5 (`safe_download.rb`),
    `InterpolationCheck` 4 (`lib/subdomain_routes.rb` — шаблон или ошибка),
    `SymbolConversion` 5, `AmbiguousOperatorPrecedence` 5, `AmbiguousBlockAssociation` 4 (спеки:
    `change { }` — проверить, что матчер реально что-то проверяет), `SafeNavigationChain`,
    `RedundantSafeNavigation`, `RedundantTypeConversion`, `UnderscorePrefixedVariableName`,
    `EmptyFile` (`spec/controllers/graphql/agent_spec.rb`).
  - `Security/Open` `app/models/campaign.rb:138` (`URI.open` с внешним URL — SSRF/командная
    инъекция через `|`): заменить на `SafeDownload` из m11.
- Риски: здесь реальные изменения поведения — каждое с тестом «красный на BASE».

## R6 — `Lint/UselessAssignment` и `Lint/UnusedMethodArgument`

- Копы: 2, 353 офенса, 115 файлов. `UselessAssignment` 188 (автокоррект убирает присваивание,
  правая часть остаётся), `UnusedMethodArgument` 165 (48 позиционных — `_arg`; 117 keyword-
  аргументов автокоррект не трогает).
- Подход: `UselessAssignment` — автокоррект, затем список всех 188 мест в отчёте с отметкой
  «значение действительно не нужно» / «баг: должно было использоваться» (баги — в R5-стиле, с
  тестом). `UnusedMethodArgument`: большинство — сигнатуры API плагинов
  (`message_apis/*/api.rb`, `presenter.rb`: `def initialize(config:)`, `def process_event(params,
  package)`), их менять нельзя (вызывающий код передаёт имена). Решение на выбор владельца:
  `Lint/UnusedMethodArgument: AllowUnusedKeywordArguments: true` с причиной «фиксированный
  интерфейс плагинов» + `_`-префикс для позиционных, либо `**` в сигнатурах.
- Риски: удаление присваивания с побочным эффектом в правой части сохраняет эффект (RuboCop
  оставляет выражение); ложное «не нужно» прячет баг — поэтому список в отчёт.

## R7 — ручные Style и Naming (нужны решения владельца)

**Решения владельца (2026-11-20):** конфигурационная часть — веха R7a (спека
`docs/specs/fork-updates-r7a.md`, после R3: обе правят todo).
- `Style/Documentation` — отключить в `.rubocop.yml` (`Enabled: false`) с причиной: заглушки
  «# Class for X» пользы не несут.
- `Naming/AccessorMethodName` и `Naming/MethodParameterName` — отключить в `.rubocop.yml` с
  причиной (переименование публичных методов ломает плагины и интеграции).
- Metrics (R8) — реальные лимиты с письменной причиной (ориентир: MethodLength ~25,
  LineLength ~140, spec/ вне BlockLength), методы сверх лимита — отдельными вехами
  рефакторинга с тестами.

- Копы: 14, 569 офенсов, 375 файлов.
  - `Style/Documentation` 401 (359 файлов): писать 359 комментариев-заглушек бессмысленно.
    Вариант с причиной: `Exclude` для `spec/**`, `app/graphql/types/**`, `app/graphql/mutations/**`,
    `app/controllers/**`, миграционных/плагинных шаблонов (там класс = DSL, документация в
    схеме GraphQL), остальное (модели, сервисы, lib) — дописать по существу. Решение владельца.
  - `Style/CaseEquality` 34 (`Class === x` → `is_a?`, `/re/ === s` → `match?`; по месту),
    `Style/OneClassPerFile` 27 (5 файлов — разнести по файлам с учётом Zeitwerk), `Style/MixinUsage`
    13 (`include` на верхнем уровне засоряет `Object` — реальная проблема), `SafeNavigationChainLength`
    10, `MultilineBlockChain` 2, `HashLikeCase` 1, `FormatStringToken` (секция `EnforcedStyle:
    unannotated` — выбрать стиль проекта).
  - Naming: `AccessorMethodName` 32 (`get_x`/`set_x` — часть публичны: резолверы GraphQL, API
    плагинов; переименование только с алиасом или настройкой с причиной), `MethodParameterName`
    18, `PredicateMethod` 15, `PredicatePrefix` 7, `VariableName` 7 (camelCase из внешних API —
    `AllowedIdentifiers` с причиной), `VariableNumber` 2.
- Подход: сначала решения владельца по Documentation и публичным именам, затем 2 вехи (Style /
  Naming), если не влезет в ~400 строк.
- Риски: переименование публичного метода ломает плагины/фронт (GraphQL поля) — только с
  сохранением старого имени.

## R8 — Metrics и `Layout/LineLength` (настройки с причиной + рефакторинг выбросов)

- Копы: 9, 929 офенсов, 180 файлов. Распределение значений (без `docs/`):

| Коп | Лимит | Офенсов | p50 | p75 | p90 | p95 | max |
|---|---|---|---|---|---|---|---|
| Metrics/MethodLength | 10 | 418 | 18 | 27 | 43 | 56 | 814 |
| Metrics/AbcSize | 17 | 173 | 23 | 30 | 41 | 59 | 111 |
| Metrics/CyclomaticComplexity | 7 | 53 | 10 | 13 | 18 | 22 | 27 |
| Metrics/PerceivedComplexity | 8 | 39 | 11 | 13 | 20 | 24 | 30 |
| Metrics/ClassLength | 100 | 46 | 199 | 305 | 396 | 421 | 965 |
| Metrics/BlockLength | 25 | 11 | 40 | 56 | 62 | 122 | 164 |
| Metrics/ParameterLists | 5 | 9 | 6 | 7 | 7 | 7 | 8 |
| Layout/LineLength | 120 | 179 | 148 | 176 | 449 | 1319 | 5768 |

- Подход: два шага. (1) Настройки с записанной причиной: `Max` на уровне, который принят в
  Rails-проектах и покрывает большинство (например MethodLength 25–30, AbcSize 30, ClassLength
  для `app/services/message_apis/**` — 26 из 46 классов это API плагинов, один класс на внешний
  API), `Metrics/BlockLength` — `Exclude` для `lib/tasks/**` (DSL rake), `LineLength` —
  `AllowedPatterns` для URL/base64/фикстур в `spec/`. (2) Рефакторинг выбросов выше нового `Max`
  (метод на 814 строк, классы 400–965 строк) — отдельными вехами по файлу, с тестами, вне
  «чистки». Конкретные числа — решение владельца по распределению выше.
- Риски: рефакторинг крупных методов меняет поведение — только с характеризационными тестами;
  поэтому выбросы — отдельные вехи, а не часть R8.

## R9 — удалить `.rubocop_todo.yml`

- Проверка, что todo пуст (или содержит только то, что R8 сознательно перенёс в `.rubocop.yml` с
  причиной); удалить файл, строку `inherit_from` и `inherit_mode: merge: Exclude` из
  `.rubocop.yml`; строгий `bin/ci-local --only rubocop` и workflow `rubocop-analysis.yml`
  зелёные; pre-push хук живого дерева зелёный.
- Риски: нет; если что-то осталось — веха останавливается и называет секции.
