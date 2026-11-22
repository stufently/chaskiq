# fork-updates-r10 — программа рефакторинга выбросов Metrics/LineLength (после R8a, до R9)

Дата: 2026-11-21. План всей чистки — `docs/specs/fork-updates-rubocop-plan.md` (R8: «выбросы — отдельные вехи
рефакторинга с тестами»; `ModuleLength` Max 123 = `user_handler.rb` со своей вехой). Список R8a —
`docs/specs/fork-updates-r8a-probes/outliers.tsv`. После всех вех этой программы R9 удаляет `.rubocop_todo.yml`.

## 1. Замер на BASE

BASE = `16682f02e62acae780f15f7027e0d258237d7d16` (HEAD `main` «Record R9b acceptance»: R9a и R9b влиты). RuboCop
1.92.3 c `.rubocop.yml` репозитория без строки `inherit_from: .rubocop_todo.yml`, только отслеживаемые файлы, Docker
`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` под 1002:1002, копия кэша `chaskiq-fxb-ci`:

- всего **254 офенса, все — выбросы Metrics/LineLength**: мультимножество (коп, файл) из `outliers.tsv` R8a без
  трёх, что убрала `r9b` (`AbcSize` `globalize_accessors.rb`, `BlockLength` `app.rb`, один `MethodLength`
  `twilio/api.rb`); Style в todo не осталось;
- по копам: LineLength 93, MethodLength 82, AbcSize 43, CyclomaticComplexity 14, PerceivedComplexity 9,
  BlockLength 7, ClassLength 5, ParameterLists 1;
- на db853da1 (до r9b) было 257 выбросов + 46 Style; файлы вех R10a/R10b r9b не трогала, их патчи одинаковы на
  обоих BASE.

## 2. Решения для координатора (настройки вместо рефакторинга)

Каждое — с измерением на BASE; программа ниже работает при любом ответе (вехи, которые решение снимает,
помечены).

**К1. `CountAsOne: [array, hash, heredoc]` для `Metrics/MethodLength`, `Metrics/ClassLength`,
`Metrics/BlockLength` (рекомендую принять).** Многострочный литерал хеша/массива/heredoc считается одной
строкой. Замер: MethodLength 82 → 16, ClassLength 5 → 1 (остаётся `app_type.rb`), BlockLength 7 → 3 — **74
выбросов уходят без правки кода**. Причина: это декларативные схемы — `definition_info` плагинов, схемы
презентеров мессенджера (`schema`, `base_schema`, `csat_buttons`, `sheet_view`), фикстуры провайдеров в спеках;
длина литерала — не сложность, дробление схемы на десяток методов-кусков ухудшает чтение и ничего не
упрощает. Логику по-прежнему держат `AbcSize`, `Cyclomatic`/`Perceived` (их числа не меняются). Цена: новый
длинный литерал не будет пойман. Вариант с `method_call` (на db853da1 83 → 10) не рекомендую: прячет многострочные вызовы с
логикой в аргументах. Если принято — вехи R10d, R10f, R10j снимаются целиком, в R10h, R10k–R10u уходит часть
офенсов (колонка «CA1» в таблице), исполняет одна маленькая веха R10cfg (строка `.rubocop.yml` с причиной +
строки todo; доказательство — бэклог-пробник: ни одного нового офенса, ни одного кода).

**К2. `ui_catalog/presenter.rb#configure_hook` (814 строк) — если К1 не принято: `Exclude` файла из
`Metrics/MethodLength` с причиной.** Это каталог-демо всех UI-компонентов мессенджера — один литерал на 780
строк под `case` по id кнопки; 30 методов-кусков дадут то же самое, только разнесённое. С К1 метод — 33
строки: остаётся маленькая выделка (`case` → таблица `{id => method}`), Cyclomatic 17 уходит той же правкой.

**К3. Длинные строки-фикстуры в `spec/` (39 офенсов, до 5768 символов).** Рекомендую вынести JSON/HTML
полезной нагрузки провайдеров в `spec/fixtures/requests/<provider>/*.json` (каталог уже есть) и читать
`file_fixture`-подобным хелпером; доказательство — пробник сравнивает байты фикстуры со значением литерала BASE
(литерал извлекается из BASE-версии спеки Ripper-ом в пробнике; в самих спеках чтение исходников запрещено как
всегда). Альтернатива дешевле, но хуже: `Layout/LineLength: Exclude: spec/controllers/api/v1/hooks/**/*` (записанные
ответы API не переносятся по смыслу). Третья — heredoc (`AllowHeredoc: true` уже действует) — не рекомендую:
меняет значение (перевод строки) и лишь прячет длину.

**К4. Билдеры фикстур в спеках (`data_for_*`, 11 MethodLength) — если К1 не принято:**
`Metrics/MethodLength: Exclude: spec/**/*` с причиной (как уже сделано для `BlockLength`): это хеши провайдеров,
а не логика. С К1 вопроса нет.

**К5 (информационно, не рекомендую).** `Metrics/BlockLength: AllowedMethods: [config]` убрал бы три DSL-блока
`subject.config do |c|` в `action_trigger_factory.rb`, но `infer_for` (129 строк) всё равно выброс по
MethodLength/AbcSize — экономии нет.

**Решения координатора (2026-11-22, владелец делегировал решения чистки):** К1 принято — `CountAsOne:
[array, hash, heredoc]` ставит веха R10cfg, R10d/R10f/R10j снимаются; К2 и К4 отпадают вместе с К1
(`configure_hook` остаётся в R10g как выделка `case` → таблица); К3 — фикстуры в
`spec/fixtures/requests/<provider>/` с пробником побайтного равенства литералу BASE; К5 не принято.

## 3. Вехи

Порядок — от безопасного к рискованному. «Риск»: **н** — поведение доказуемо (байткод/данные), **с** — чистая
функция или узкий метод с характеризацией, **в** — внешний API, вывод мессенджеру, БД, мало тестов. CA1 —
сколько офенсов группы снимает К1. Число строк — оценка дифа кода (без спек).

| Веха | Область | Офенсов | CA1 | Риск | Зависит от |
|---|---|---|---|---|---|
| **R10a** | LineLength в `app/` вне файлов r9b (20 файлов) | 37 | 0 | н | — (спека готова) |
| **R10b** | шесть одиночных сложных методов (чистые функции) | 6 | 0 | с | — (спека готова) |
| R10c | LineLength в файлах, которые меняла r9b (9 файлов) | 17 | 0 | н | — |
| R10cfg | настройка К1 (+ К2/К4 по решению) | до 74 | — | н | решение К1 |
| R10d | `definition_info` плагинов, `packages_old`, `default_new_conversation_path` | 10 | 10 | н | только без К1 |
| R10e | LineLength в спеках (10 файлов) | 39 | 0 | н | решение К3 |
| R10f | билдеры фикстур в спеках | 11 | 11 | н | только без К1/К4 |
| R10g | `ui_catalog` `configure_hook` | 4 | 0 | в | решение К1/К2 |
| R10h | `content_showcase` + `inbox_sections` презентеры | 14 | 6 | в | — |
| R10i | `dialog360` презентер | 4 | 1 | в | — |
| R10j | мелкие методы шести презентеров | 12 | 12 | с | только без К1 |
| R10k | `slack/api.rb` (Block Kit) | 10 | 4 | в | — |
| R10l | SMS/WhatsApp: twilio, vonage, message_bird, telnyx, dialog360 api | 12 | 4 | в | — |
| R10m | telegram, twitter, twilio_phone api | 12 | 5 | в | — |
| R10n | отчёты/уведомления: open_ai, csat, audits_reports api | 5 | 3 | с | — |
| R10o | конвертация контента: `block_manager`, `dante/renderer`, `dante/migrator` | 8 | 0 | в | R10a (dante) |
| R10p | `segment.rb` (`tagged_result`, `nested_preds_group`, `es_search`, класс) | 12 | 2 | в | — |
| R10q | `action_trigger.rb` + `action_trigger_factory.rb` | 14 | 7 | в | R10a (factory) |
| R10r | контроллеры: два `execute`, `package_iframe_behavior`, `hooks_controller` | 9 | 4 | в | R10c (hooks_controller) |
| R10s | `start_conversation#resolve` + `ChatNotifierMailer#notify` | 6 | 0 | в | — |
| R10t | `app_type.rb`: класс 563 строки, `conversations` (8 параметров), `dashboard` | 4 | 1 | в | R10c |
| R10u | модели: `app.rb`, `app_user.rb`, `globalize_accessors`, `app_package_integration`, `plugin`, `plugin_schema_validator` | 8 | 4 | в | R10c |
| R10v | `user_handler.rb` — разбить модуль, `ModuleLength` Max 123 → умолчание | (настройка) | — | в | — |

Итого 254 офенса, **22 вехи** (без R10cfg) + R9. С К1: R10d/R10f/R10j (33) и 41 офенс других групп уходят в
одну R10cfg — **20 вех**, из них 16 логических рефакторингов (R10b, R10g–R10v без R10j). «Зависит от» R10a/R10c —
общий файл (патчи не должны пересечься по хункам): ставить после их влития или проверить `git apply` в обоих порядках. Мелкие соседние вехи (R10n+R10s, R10c+R10e) можно ставить
парой на один прогон, если обе ≤ 12 AC.

### Группы — файлы, офенсы, подход, что характеризовать

Строки — BASE `16682f02`; при постановке каждой вехи пересчитать замером.

**R10a — LineLength в `app/`** (спека `fork-updates-r10a.md`). 37 строк: 29 — комментарии (один и тот же текст
«Sent when a sheet has been submitted…» в 15 презентерах; закомментированный код `options:` в twilio_phone),
8 — код: `%w[]` `Agent.ransackable_attributes`, строка-SQL `Dante::Migrator`, вызов с kwargs в
`Dante::Renderer#handle_mark`, строки `scope:` Slack OAuth, `options:` окна TwilioPhone (две строки), значение
`InboxSections.user_data`, сообщение `ChaskiqSchema.unauthorized_field`. Подход: перенос; строковые литералы —
смежными кусками `"…" \`. Доказательство сильнее характеризации: 19 из 20 файлов компилируются в байткод
BASE (номера строк не в счёт); `chaskiq_schema.rb` — нет (Prism не склеивает интерполированные куски) — его
пиннит точное сообщение. Плюс характеризация всех методов с перенесённым кодом и 13 мутантов.

**R10b — шесть одиночных выбросов** (спека `fork-updates-r10b.md`): `SegmentComparator#compare_with`
(Cyclomatic 14 → таблица лямбд), `AppPolicy#find_role_by_resource` (Perceived 14 → `resource_app`),
`Dante::Converter.convert_inline_styles` (Abc 47 → три помощника), `VisitCollector#add_web_sessions`,
`Types::MessengerType#browser_data`, `FetchLinkCardService#attempt_oembed` (Abc 32–41 → выделение). Все —
чистые функции или узкие методы без внешнего API; характеризация золотыми значениями, 37 мутантов.

**R10c — LineLength в файлах, которые меняла r9b** (17): `hooks_controller.rb` 236 (условие с `find`/`dig`), 265 (HTML-строка с
интерполяцией), `app_type.rb` 271 (символ ransack на 232 символа — не переносится: `:"…" \` нельзя; выход —
`%i[]`-список полей и `.join("_or_").to_sym` с пином результата), `app_user.rb` 139 (`%w[]`), 363, `campaign.rb` 15–27
(хеши полей формы с `I18n.t`), `globalize_accessors.rb` 36, `block_manager.rb` 196 (комментарий), `twilio/api.rb` 40,
`twilio_phone/api.rb` 123/546/564, `lib/tasks/utils.rake` 300 (комментарий). Подход как в R10a: байткод там, где
только перенос; характеризация `Campaign.config_fields`, `AppUser.ransackable_attributes`, символа ransack.

**R10d — литералы-определения** (10; снимается К1). `definition_info` calendly/dialog360/slack/twilio/twilio_phone/
twitter/vonage/zoom, `AppPackagesCatalog.packages_old`, `BotTask#default_new_conversation_path`. Подход:
выделить подхеши (`definitions:`, `settings`) в методы; характеризация — `eq` полного хеша (новый объект на каждый
вызов — проверить, что вызывающие его мутируют: `merge!` на результате → методы, не константы).

**R10e — LineLength в спеках** (39): `dante_renderer_spec.rb` 11, `pipedrive_spec.rb` 10, `hooks_controller_spec.rb` 9, `dialog_360_spec.rb` 3, по одной — `message_bird`, `twilio`, `twitter`, `vonage`, `app_package_spec`,
`campaign_spec`. Подход по К3. Доказательство: пробник — байты фикстуры = значение литерала BASE; полный rspec
(примеры BASE те же); мутанты не нужны (кода нет), вместо них — порча байта фикстуры ловится пробником.

**R10f — билдеры фикстур в спеках** (11; снимается К1/К4): `telegram_spec` ×5, `twitter_spec` ×3, `calendly_spec`,
`telnyx_sms_spec`, `dialog_360_spec`. Без К1/К4 — JSON-фикстуры, проверка равенства хешей пробником.

**R10g — `ui_catalog` `configure_hook`** (4). Риск: вывод мессенджеру, тестов 2. Сначала характеризация:
снимок полного возвращаемого хеша для КАЖДОГО id кнопки каталога и для `kind`≠submit (список id —
перечислить из BASE; ожидания — золотые JSON-снимки в `spec/fixtures`, сгенерированные на BASE пробником, не
спекой). Подход: `case` → таблица `{id => :метод}`; с К1 литералы остаются как есть.

**R10h — `content_showcase` + `inbox_sections`** (14). `configure_hook` 162 строки (Abc 91, Cyc 16), `content_hook`
201 строка (Abc 94, Cyc 22), схемы `schema`/`article_fields`/`presentation_schema`/`base_schema`. Риск в:
`inbox_sections` покрыт одним спеком. Характеризация: каждая ветка `ctx[:field][:id]`/`ctx[:values][:type]` →
снимок хеша; `AnnouncementRecord`/`ArticleRecord` — с фиксированными записями. Подход: ветка → метод, общий
каркас ответа (`{kind:, definitions:, results:}`) → помощник. Можно резать на две вехи (по файлу), если > 400 строк.

**R10i — `dialog360` презентер** (4): `configure_hook` 224 строки (Abc 104, Cyc 24), `search_participant`. Риск в:
шаблоны WhatsApp идут во внешний API (`retrieve_templates`, Base64 JSON шаблона). Характеризация: снимок
`definitions` для каждого шага мастера шаблона с застабленным `message_api_klass`; WebMock — ни одного
неожиданного запроса.

**R10j — мелкие методы презентеров** (12; снимается К1): `article_search` ×3, `calendly` ×2, `contact_fields`,
`csat` ×2, `full_contact`, `twilio_phone` ×3. Подход: выделить литералы; снимки хешей/HTML `sheet_view`. Заметка:
`TwilioPhone::Presenter.content_definitions` с непустым списком конференций падает `NameError` (`agents_ids`
вместо `agent_ids`, строка 295) и нигде не вызывается — дефект вне бэклога, кандидат в веху фиксов (R10a
пиннит только пустой список: строка `options:` 311 недостижима, её доказывает байткод; раздел 5).

**R10k — `slack/api.rb`** (10): `thread_head` 96, `conversation_status_blocks` 54, `notify_new_lead` 38,
`notify_message` 67 (Cyc 23), `attachment_block` 31. Риск в: Block Kit-нагрузка во внешний API. Характеризация —
WebMock: точное тело каждого запроса `chat.postMessage`/`chat.update` (JSON) по каждой ветке события; тестов
много (10 файлов), но тела проверяют не все. Подход: блоки → методы-строители, таблица событий.

**R10l / R10m — адаптеры провайдеров** (13 / 12): `send_message`, `send_template_message`, `process_message`,
`process_incoming_call/event`, `process_event` (+ BlockLength `each`). Риск в: тела запросов к провайдерам и
создаваемые записи. Характеризация: WebMock — точный метод/URL/тело/заголовки; после входящего — снимок
созданных `ConversationPart` (тип, контент, `message_source`, внешние профили). Подход: «разбор входящего» и
«сборка исходящего» — отдельные методы; общие куски (вложения) — помощник.

**R10n — отчёты** (5): `audits_reports#report`, `csat#report` (Abc 39), `open_ai#notify_message` (Abc 51). Риск с:
`csat_report_label_spec` уже пиннит подписи; open_ai — WebMock на запрос к API.

**R10o — конвертация контента** (8): `BlockManager.deliver_attachments` (Cyc 27, Perceived 30), `Dante::Renderer
#convert_node_to_element` (Cyc 15), `Dante::Migrator.migrate_bot_tasks`. Риск в: HTML-вывод писем и мессенджера.
Характеризация: точный HTML для каждого типа узла (таблица узел → строка), для `deliver_attachments` — вызовы
провайдера по каждому типу вложения. Подход: `case` → таблица `{type => метод}`.

**R10p — `segment.rb`** (12): `tagged_result` 86 строк (Abc 111, Cyc 27), `nested_preds_group`, `es_search`, класс
401. Риск в: SQL/ES-запросы сегментов, тестов 3. Характеризация: `to_sql` отношения для набора предикатов
(каждый тип × сравнение) + результат на фикстурах; `es_search` — тело запроса к Elasticsearch (снимок хеша).
Подход: предикат → объект-строитель (`SegmentPredicate`), класс худеет выносом в concern. Вероятно две вехи.

**R10q — action triggers** (14): `ActionTriggerFactory.infer_for` 129 строк + три DSL-блока `subject.config`,
`request_for_email`, `route_support`, класс 366; `ActionTrigger.trigger_step`/`process_next_step`. Риск в: сценарии
бота. Характеризация: снимок `to_obj`/`as_json` полного дерева путей для каждой комбинации настроек
(`email_requirement` × `in_business_hours?` × тип пользователя) — уже частично есть
(`action_trigger_factory_kind_spec`, `_infer_spec`). Подход: шаги пути → методы-фабрики.

**R10r / R10s — контроллеры и мутация** (9 / 6): `Api::GraphqlController#execute`, `GraphqlController#execute`,
`PackageIframeBehavior#package_iframe`/`handle_user_data`, `HooksController#process_email_notification`,
`StartConversation#resolve` (65 строк), `ChatNotifierMailer#notify` (Cyc 19). Риск в: auth, контекст GraphQL,
письма. Характеризация: request-спеки на статусы/тела/контекст, письмо — тема/получатели/тело (снимок).

**R10t — `app_type.rb`** (4): класс 563 строки, `conversations` 8 параметров (`ParameterLists` — поля GraphQL!
аргументы — часть схемы: выход — `**args`/объект фильтра, схема не меняется), `dashboard`. Характеризация:
дамп схемы (`ChaskiqSchema.to_definition`) до/после — идентичен; резолверы — запросы GraphQL-спеками. Подход:
резолверы-группы в модули (`Types::AppType::Conversations` …).

**R10u — модели** (8): `App` (класс 340, `config_fields` — литерал, `start_conversation`), `AppUser` (класс 352),
`GlobalizeAccessors` `included` 54, `AppPackageIntegration#call_hook`, `Plugin.save_plugin_files_to_folder` (пишет
файлы в `app/services/message_apis/` и грузит их Zeitwerk — характеризовать на временном каталоге),
`PluginSchemaValidator#initialize` (Cyc 15). Классы — выносом в concerns; с К1 ClassLength `App`/`AppUser` уходят.

**R10v — `user_handler.rb`** (не в todo: `ModuleLength` Max 123 в `.rubocop.yml`): спеков 0 — сначала
характеризация `add_user`/`add_lead`/`add_anonymous_user` (атрибуты, свойства, события), затем разбить на два
concern-а, Max → удалить строку (умолчание 100).

## 4. Общий шаблон вехи (как R10a/R10b)

Код задаёт патч постановщика (как в R9a/R9b); исполнитель (qw2) пишет характеризующие спеки. Критерии: полный
rspec против снимка BASE (`--write-base` на чистом клоне); пути = патч + спеки + todo + CHANGELOG; тест-гейт
(спеки зелёные на дереве и на BASE-коде, каждый мутант убит примером, не ошибкой загрузки; для вех-переносов —
байткод = BASE); бэклог без todo (целевые офенсы 0, ни у одного копа ни в одном файле не больше, чем на BASE,
общий счёт ниже); строгий CI RuboCop; коммиты по порядку; source-scan (чтение исходников в спеках запрещено);
sha256 пробников; чистое дерево. Ревью — только agy (Codex запрещён до 2026-11-22 11:39Z), блок второго
ревьюера — в `report-blocked.md`. Для вех риска «в» с большими методами, где патч постановщика писать дольше
самой работы, допустим вариант «исполнитель пишет и характеризацию, и рефакторинг»: тогда характеризующие
спеки — отдельным первым коммитом (зелёные на BASE), мутанты постановщик составляет на приёмке по дифу, а
AC-002 сверяет не байты патча, а «изменены только файлы вехи».

## 5. Находки по ходу замера (вне бэклога, решения координатора)

- `TwilioPhone::Presenter.content_definitions`: при непустом `conferences_list` — `NameError` (`agents_ids`), метод
  не вызывается (вызов закомментирован). Удалить мёртвый код или починить — веха фиксов.
- `Dante::Converter.convert_inline_styles`: диапазон стиля/ссылки, который начинается после текущей позиции, не
  режет текст — стиль, начинающийся внутри абзаца, теряется, если перед ним не кончается другой диапазон
  (`"abcdef"` с BOLD [3,6) → один узел без отметок). R10b пиннит это как есть; починка — веха фиксов (меняет
  миграцию draft → prosemirror).
- `FetchLinkCardService#attempt_oembed`: `card.type = response.type` (строка `"video"`) в `enum :type` на строковом
  столбце даёт `nil` — тип oEmbed-карточки не сохраняется никогда. R10b пиннит как есть.
- `Types::MessengerType#update_data` зовёт `browser_data`, который читает `@user`, а `@user` ставят только другие
  резолверы (`enabled_for_user`, `conversations`…); сам по себе `update_data` падает `NoMethodError` на `nil`.
- `spec/services/visit_collector.rb` назван без `_spec` — rspec его не запускает.

## 6. Стыки и перенос BASE

- R10a/R10b: общих файлов кода нет; общие — `.rubocop_todo.yml` (разные блоки/строки: r10a — строки
  `Layout/LineLength`; r10b — строки `AbcSize`/`Cyclomatic`/`Perceived` шести файлов) и `CHANGELOG.md` (блок после
  `# Changelog`). Проверено на 16682f02: оба патча применяются в любом порядке, скрипты todo — тоже, итог один.
  Патчи R10a/R10b не пересекаются и с патчами r9b (на db853da1 все три — в любом порядке), поэтому влитие r9b
  во время подготовки потребовало только переноса BASE: патчи и мутанты не изменились.
- Правило переноса BASE: каждая веха, которая вливается после другой, — перенос строки BASE_SHA на новый HEAD,
  `git apply --check` патча, мутанты (текст — ровно раз), `--write-base` снимков на чистом checkout нового
  `main`, sha256 в AC-008 — и только потом клон. Патч перегенерировать не нужно, пока `git apply --check` чист.
