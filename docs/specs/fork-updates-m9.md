# fork-updates-m9 — видимые частичные сбои отправки и все id провайдера у части сообщения

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m9.md`.
- BASE_SHA: `94dbeebc4b15e06efbe86b14e5996e89c0663ccc` «Add fork-updates-m12 spec and probes» — `main` с влитыми m1–m8 (Rails 8.1.4.1, load_defaults 8.1, Ruby 3.3.14), ci-parity и спекой m12 (bin/ci-local, .githooks, документы, `docs/specs/fork-updates-m12*` и правка тела одного примера в `spec/mailers/campaign_spec.rb` без смены имён; app как в 7e5523d3, на котором сняты examples_base и черновик).
- BASE плавающий: поверх BASE_SHA в `main` могут лежать только коммиты постановщика (эта спека,
  её пробники, правка этой строки, спеки соседних вех); клон снят с последнего из них. Команды
  критериев считают BASE сами: `B=$(git merge-base HEAD @{u})` — коммит `main`, от которого снят
  клон (`make_clone.sh --work-branch fork-updates-m9` ставит upstream `origin/main`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в
  `docs/specs` запрещены (AC-008).
- Исполнитель: Codex (`cx`). Мутации по новым тестам потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`). Исправления внутри вехи — тому же Codex.
- Цель: закрыть два известных дефекта из CHANGELOG (разделы fork-updates-m5 и m7, «Known
  issues»): сбой второго и следующих запросов многовложенной отправки теряется молча; часть
  сообщения хранит один id провайдера, и квитанции о прочтении/статусы матчатся только с первым
  вложением.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m9`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind mount пробники поднимают сами. На хост ничего не ставить (никаких
  gem/bundle/npm/yarn/pip/apt на хосте).

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker | ruby 3.3.14 + libpq + libvips + node + jq |
| гемы Rails 8.1 | `$HOME/.cache/chaskiq-m6/bundle` (`CHASKIQ_BUNDLE` переопределяет) | гейт и пробники; гемы в этой вехе не меняются |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m9-probes
B=$(git merge-base HEAD @{u})
bash $P/rspec_gate_m9.sh                     # полный строгий rspec, ~6 мин
bash $P/rspec_gate_m9.sh --only <spec-файл>  # один файл
bash $P/m9_red_on_base.sh $B                 # новые тесты красные на BASE, ~1 мин
bash $P/m9_rubocop.sh $B                     # строгий RuboCop по своим .rb, как в CI
python3 -I $P/m9_mutation_gate.py OF1 IM1    # часть мутантов (полный набор ~20 мин)
```

## 3. Задача и почему

1. **Частичный сбой теряется.** `MessageApis::BlockManager.deliver_attachments` возвращает первый
   успешный ответ; неуспешные запросы после него (и до него, если потом что-то ушло) никуда не
   попадают. Единственный видимый сегодня сигнал об ошибке синхронной отправки — событие
   `errored: …` в разговоре, которое Twilio строит в `send_message`, когда итоговый ответ
   неуспешен. При многовложенной отправке итоговым становится первый успех, и событие не
   появляется. Новый UI не вводим — используем это же событие, но с безопасными данными (п. 3).
2. **Один id на часть, и сохраняется он в конце.** `MessageApis::BasePackage#notify_message`
   создаёт ровно одну `ConversationPartChannelSource` из итогового ответа и только после всей
   серии запросов. Квитанции Vonage (`status: "read"`, `message_uuid`), статусы Dialog360
   (`statuses[].id`, `read`/`failed`) и Twilio (`MessageSid`/`SmsSid`, `read`/`undelivered`)
   ищут строку по `message_source_id` и для второго и следующих вложений ничего не находят;
   квитанция, пришедшая во время следующего POST, теряется; таймаут посреди серии роняет джобу
   до записи id, и ретрай шлёт уже принятые вложения заново (а с одной лишь защитой «есть строка —
   ничего не слать» недошедшие вложения не дошли бы никогда). Тело без id (Dialog360
   `{"messages": []}`) роняет `get_message_id` с `NoMethodError`.
3. **Утечка в событие.** Нынешнее событие Twilio кладёт в `data` ВСЁ тело ответа провайдера
   (`data: { status: body }`; у Twilio там `more_info` с URL, текст ошибки с URL медиа и т. п.), а
   `data` события уходит клиенту мессенджера через GraphQL (`Types::ConversationPartContentType#data`
   → `object.data`). Асинхронные `process_error` Twilio (статус `undelivered`) и Dialog360 (статус
   `failed`) так же кладут в событие весь вебхук (`data: { status: params }`: номера, URL медиа,
   `href`). Все три источника события приводятся к одному безопасному формату.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 чтением кода BASE и в Docker на клоне от BASE_SHA и на черновике (черновик —
только для проверки достижимости, в веху не идёт):

1. Гейт на BASE: `528 examples, 0 failures, 30 pending`; список примеров — `examples_base.txt`,
   pending — `pending_allowed.txt` (те же 30, что в m8).
2. **Схема — без миграции.** `conversation_part_channel_sources` (`db/schema.rb`):
   `conversation_part_id` (not null, FK), `provider`, `message_source_id`, таймстемпы; индексы
   только неуникальные по каждому из трёх столбцов — уникальности на (часть, провайдер) или на
   `message_source_id` нет. Модель — голый `belongs_to :conversation_part`, валидаций нет.
   Все поиски по входящим событиям — `find_by(provider:, message_source_id:)`
   (`MessageApis::Helpers#find_channel`/`#process_read`, `Dialog360::Api#find_channel`,
   `Twilio::Api#find_channel_from_part_source`) или `conversation_part_channel_sources
   .find_by(message_source_id:)` (дедупликация входящих в каждом плагине) — то есть они уже
   матчат ЛЮБУЮ строку. Значит, «все id части» = по строке на id: существующие строки (по одной
   на часть) продолжают работать без изменений, поиски менять не нужно. Массивный столбец
   потребовал бы миграции данных и переписывания каждого поиска.
3. **Ретрай продолжает серию без схемы.** Строки `ConversationPartChannelSource` части пишутся в
   порядке запросов (по одной на каждый УСПЕШНЫЙ запрос серии — медиа по порядку документа, затем
   отдельный текст), поэтому N = число строк части у провайдера = сколько запросов серии уже
   прошло. Ретрай `notify_message` передаёт N в `deliver_attachments` (`already_sent: N`), тот
   «проигрывает» первые N запросов как успешные (подпись, ушедшая с проигранным медиа, считается
   отправленной; отдельный текст — последний запрос серии) и шлёт только остаток; если остатка нет —
   не шлёт ничего и возвращает `nil`. Старая защита `find_by(provider:)` остаётся для всего, что
   НЕ продолжает серию: плагины вне пяти, текст без медиа (Twilio и Dialog360 шлют его мимо
   `deliver_attachments`), — там поведение не меняется. Для одиночного сообщения: текст без медиа —
   старая защита; одно медиа с подписью — N = 1, повтора нет; одно медиа + отдельный текст — N = 2,
   повтора нет, а при сбое на тексте ретрай шлёт только текст.
   Ограничение (раздел 10): N считает только успехи. Если в той же попытке до исключения был
   НЕуспешный ответ (4xx, событие `errored`), точка продолжения сдвигается на число таких ответов:
   ретрай повторит неуспешное вложение и столько же следующих за ним успешных. Точный счёт требует
   строки на каждый запрос или схемы «вложение → id» — вне вехи.
   Других чтений `conversation_part_channel_sources` (`.first`, подсчёт) в `app/`, `lib/` нет.
   В джобе транзакции вокруг `notify_message` нет — `create` коммитится сразу.
4. Кто зовёт `deliver_attachments`: `telegram`, `vonage`, `message_bird` (блок `do |type, url,
   caption|`, без `captionless:`), `twilio` (`captionless: method(:captionless_attachment?)`),
   `dialog360` (`captionless: %w[AudioRecorderBlock]`). Все пятеро — подклассы
   `MessageApis::BasePackage` с `include MessageApis::Helpers` и `send_message(conversation, part)`.
   Twilio и Dialog360 для сообщения без медиа шлют текст напрямую, мимо `deliver_attachments`.
   Существующие спеки зовут `api.send_message(thread, part)` с НЕсохранённой частью
   (`thread.messages.build`) — на ней `create` по связи упал бы, поэтому запись id только для
   `part.persisted?`.
5. `notify_message` зовут `ConversationChannel#notify_part` (из `ApiChannelNotificatorJob`) и
   slack; `BasePackage#notify_message` — общий для всех плагинов (telnyx, messenger, twitter и
   др. тоже), их `send_message` может вернуть не Faraday-ответ (`respond_to?(:body)` в коде BASE).
6. Существующие спеки фиксируют контракт, который нельзя ломать: `block_manager_spec.rb`
   ожидает `expect(result).to equal(success)` (возврат — тот же объект первого успеха), спеки
   twilio и dialog360 — `JSON.parse(result.body)` первого успеха от `send_message`. Поэтому
   возвращаемое значение `deliver_attachments`/`send_message` не меняется, а все ответы уходят
   колбэками.
7. `Conversation#add_message_event` создаёт часть с `ConversationPartEvent(action:, data:)`
   (`data` — jsonb) и строкой `ConversationPartChannelSource(provider:, message_source_id:)`;
   эта строка и не даёт событию уйти обратно провайдеру (защита из п. 3). `data` и `action`
   отдаются GraphQL-типом `ConversationPartContentType` (`field :data`) — и агентам, и мессенджеру.
   Потребителей ключа `data.status` у событий `errored` во фронтенде нет (grep `errored` по `app/`
   находит только twilio и dialog360).
8. Формы ответов, на которых держатся тесты, — из существующих спеков и кода: Telegram
   `result.message_id` / ошибка `{ok: false, error_code, description}`; Vonage `message_uuid`,
   квитанция `{message_uuid, status: "read"}`, ошибка `{title}`; MessageBird `id`, ошибка
   `{errors: [{code, description}]}`; Twilio `sid`, ошибка `{code, message, more_info, status}`,
   колбэки `SmsStatus` + `MessageSid`/`SmsSid`; Dialog360 `messages[0].id`, ошибка
   `{errors: [{code, title}]}`, статусы `statuses[{id, status, errors[{code, title}]}]`.
9. **RuboCop на `main` строгий** (любой offense валит CI; `.rubocop.yml` + `.rubocop_todo.yml`,
   `inherit_mode: merge: Exclude`; CI и `bin/ci-local` зовут `rubocop --force-exclusion`).
   `Metrics/ParameterLists` (max 5, keyword-аргументы считаются) не пускает сигнатуру с
   отдельными `on_success:` и `on_failure:` (6 параметров) — отсюда `**hooks` (раздел 5.A).
   `Metrics/BlockLength` на `spec/**` выключен, на `docs/specs/**` — нет (в пробнике —
   `rubocop:disable-next`).
10. Черновик (раздел 5) с примерными тестами: полный гейт зелёный, пробник `m9_probe_spec.rb`
    19/19, мутационный гейт — все 22 мутанта убиты, `m9_red_on_base.sh`, `m9_rubocop.sh`,
    пробник целостности и регрессий зелёные. На BASE пробник красный (раздел 7).

Предположения (не проверены): что Vonage шлёт квитанцию `read` по `message_uuid` каждого
отдельного сообщения (документация Vonage Messages API, вживую не проверялось); поля ошибок
провайдеров, кроме Twilio (`message`/`code` — по коду BASE), — по документации и существующим
спекам, вживую не проверялись; если поля нет, в событии будет пустой текст и `code: null`, само
событие появляется всегда. Поле `ErrorCode` в статус-колбэке Twilio (`undelivered`) — по
документации Twilio, в существующих спеках его нет.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. `MessageApis::BlockManager.deliver_attachments`** — сигнатура
`deliver_attachments(attachments, plain_text, send_text:, captionless: [], **hooks)`; `hooks`
принимает только `:on_success`, `:on_failure` и `:already_sent` (иное — `ArgumentError`, например
`assert_valid_keys`); `on_success`/`on_failure` — вызываемые объекты с одним аргументом (ответом):
- `on_success` — СРАЗУ после каждого успешного запроса внутри метода: каждое медиа, хвостовой
  текст-подпись после успеха, текст-замена, когда ни одно медиа не ушло; до следующего запроса.
- `on_failure` — для каждого неуспешного запроса внутри метода, КРОМЕ того объекта, который метод
  возвращает (его, как сегодня, обрабатывает вызывающий). Вызывается после всех отправок.
- Ответ `send_text`, у которого нет `success?`, ни в один колбэк не идёт.
- `already_sent` (целое, по умолчанию 0) — сколько запросов этой серии уже прошло в прошлой
  попытке. Первые `already_sent` медиа с годным URL не отправляются и считаются успешными
  (`yield` и колбэки для них не зовутся; подпись, которая ушла бы с таким медиа, считается
  отправленной); если `already_sent` больше числа таких медиа — отдельный текст (подпись после
  медиа или текст-замена при отсутствии медиа) тоже считается отправленным. Возврат: первый
  НОВЫЙ успешный ответ, иначе успешный ответ текста, иначе `nil`, если ничего не отправлено.
- Возвращаемое значение, порядок запросов, подписи и `captionless:` — побайтно как сейчас при
  `already_sent: 0` и без `hooks`.

**B. `MessageApis::BasePackage`** (`app/services/message_apis/base_package.rb`):
1. `message_id_for(response)` — id провайдера из ЛЮБОГО ответа (успешного, неуспешного,
   итогового, не-Faraday): тело `response.body` или сам `response`, `JSON.parse`,
   `get_message_id`, `to_s`, пустое → `nil`; любые `JSON::ParserError`, `TypeError`,
   `NoMethodError`, `KeyError` → `nil` без исключения (Dialog360 `{"messages": []}` → `nil`).
2. `store_message_id(part, response)` — `message_id_for`; если id есть и такой строки
   (`provider: self.class::PROVIDER`, `message_source_id: id`) у части ещё нет — создать.
3. `delivery_hooks(conversation, part)` → `{ already_sent: N, on_success: …, on_failure: … }`:
   N — число строк части с `provider: self.class::PROVIDER` (0 для несохранённой части);
   `on_success` СРАЗУ зовёт `store_message_id(part, response)`, если `part.persisted?` (иначе
   ничего); `on_failure` зовёт `report_delivery_failure`. Никакого накопления ответов в экземпляре
   (объект API кэшируется на интеграции и живёт между вызовами).
4. `resumable_delivery?(part)` — истина, только если у класса плагина объявлено
   `RESUMABLE_DELIVERY = true` (собственная константа, `const_defined?(…, false)`) И в
   `part.message.as_json["serialized_content"]` есть медиа (`BlockManager.get_blocks` +
   `media_blocks`); любая ошибка разбора → ложь.
5. `notify_message`: вместо `return if …find_by(provider:).present?` —
   `return if N.positive? && !resumable_delivery?(part)` (N — как в п. 3; раздел 4, п. 3); затем
   `send_message`; `nil` → выход; иначе `store_message_id(part, response)` для итогового ответа
   (повтор id не создаёт второй строки). Прямой `get_message_id(JSON.parse(…))` не остаётся.
6. `add_error_event(conversation, source_id, status:, code:, text:)` — единственное место, где
   строится событие ошибки: `conversation.add_message_event(action: "errored: #{text}",
   provider: self.class::PROVIDER, message_source_id: source_id, data: { status:, code:, message: text })`
   с очищенными `code` и `text` (правила ниже); `data` — РОВНО три ключа.
7. `report_delivery_failure(conversation, part, response)` →
   `add_error_event(conversation, "bypass-internal-#{part.id}", …)`, где:
   - `status` — HTTP-статус ответа (`response.status`, если есть, иначе `nil`);
   - `code` — код ошибки провайдера: первое из `body["code"]`, `body["error_code"]`,
     `body["errors"][0]["code"]`; только Integer или строка `\A[\w.-]{1,32}\z`, иначе `nil`;
   - `message` = `text` — первая непустая строка из `body["message"]`, `body["description"]`,
     `body["title"]`, `body["errors"][0]["title"]`, `body["errors"][0]["description"]`; каждый
     URL (`схема://…` до пробела) заменён на `[url]`, пробелы схлопнуты, не длиннее 200 символов
     (`truncate(200)`); нет текста — `""`.
   Тело, которое не разбирается или не Hash, — `code: nil`, `message: ""`. Ничего больше из тела
   (URL, `more_info`, номера, данные интеграции) в событие не попадает. Для Twilio `action` с
   обычным коротким текстом без URL совпадает с нынешним `errored: #{body["message"]}`.

**C. Пять плагинов** (`telegram`, `vonage`, `message_bird`, `twilio`, `dialog360` — только
`api.rb`): объявить `RESUMABLE_DELIVERY = true`; передать `**delivery_hooks(conversation, part)`
в вызов `deliver_attachments`. `process_error` Twilio и Dialog360 — через `add_error_event` с тем
же `message_source_id` (`bypass-internal-#{params['id']}`), `status: nil` и тем же текстом, что
сейчас в `action` (Twilio — `params["SmsStatus"]`, Dialog360 — склейка `"#{code} #{title}"` по
`errors`); `code` — Twilio `params["ErrorCode"]`, Dialog360 `errors[0]["code"]`; поиск строки
по id не меняется. Twilio:
блок обработки неуспешного итогового ответа заменить вызовом
`report_delivery_failure(conversation, part, response)` (затем `return nil`, как сейчас) — так
синхронное событие Twilio тоже приходит к безопасному формату. Методы `delivery_hooks`,
`report_delivery_failure`, `notify_message`, `store_message_id`, `message_id_for`,
`resumable_delivery?`, `add_error_event` в плагинах не переопределять. Поиски по
квитанциям/статусам не трогать (раздел 4, п. 2).

**D. Тесты** (в существующие файлы — только ДОБАВЛЕНИЕ строк; новые `*_spec.rb` вне
`spec/support/` можно). HTTP — webmock, включённый локально (`include WebMock::API`,
`WebMock.enable!`/`disable!` в `around`). Все новые и изменённые `.rb` проходят строгий RuboCop
(AC-005). Слова-маркеры в описаниях примеров обязательны — по ним мутационный гейт и AC-004 ищут
упавший пример:
1. `spec/services/message_apis/block_manager_spec.rb`: `on_success` получает каждый успешный
   запрос (`on_success`); `on_failure` получает сбой после успеха (`on_failure`) и не получает
   возвращаемый неуспешный ответ (`returned`); `already_sent` пропускает первые медиа с учётом
   подписи и считает отдельный текст (`already_sent`).
2. Каждый из `spec/controllers/api/v1/hooks/{telegram,vonage,message_bird,twilio,dialog_360}_spec.rb`:
   через `notify_message` с сохранённой частью — сбой одного из нескольких вложений даёт одно
   событие `errored:` (`partial failure`).
3. `vonage_spec.rb`: квитанция `read` по `message_uuid` последующего вложения помечает часть
   прочитанной (`provider id`); во время второго и третьего POST id предыдущих уже лежат в базе
   (`immediately`); таймаут (`Faraday::TimeoutError`) на третьем из четырёх вложений, затем
   повторный `notify_message` той же части шлёт только третье и четвёртое, без подписи (`resume`);
   повтор после полностью доставленной серии не шлёт ничего (`retry`, `base-green`).
4. `dialog_360_spec.rb`: статус `failed` по id последующего вложения даёт событие `errored:`
   (`provider id`); первый успешный ответ `{"messages": []}` — без исключения, id остальных
   вложений сохранены (`empty`); событие статуса `failed` — ровно `status: nil`, `code`, текст без
   URL (`failed status event`).
5. `twilio_spec.rb`: событие частичного сбоя — ровно ключи `status`/`code`/`message`, без URL,
   текст ≤ 200 (`safe`); событие колбэка `undelivered` — ровно `status: nil`, `code` из
   `ErrorCode`, текст статуса (`status callback`); единичный неуспешный запрос отправки только
   медиа без текста даёт ровно одно событие (`once`); повтор после аудио и отдельного текста не
   шлёт текст снова (`separate text`); повтор текста без медиа не шлёт его снова (`single text`).
   Примеры `once`, `separate text`, `single text` (и `retry` в vonage) на BASE ЗЕЛЁНЫЕ по праву —
   старый код ведёт себя так же; в их описании обязателен маркер `base-green`.
6. Регрессия обязательна: каждый маркер из п. 1–5, кроме примеров `base-green`, представлен
   примером, падающим на коде BASE; примеры `base-green` на BASE зелёные; существующие примеры на
   BASE не падают — это проверяет AC-004.

Мутанты AC-003 (дописываются в конец файла, перекрывая метод): OF1 — `deliver_attachments` не
зовёт `on_failure`; OS1 — не зовёт `on_success`; OF2 — отдаёт в `on_failure` и возвращаемый
ответ; RP1 — проигранное медиа не забирает подпись; RP2 — отдельный текст не входит в
`already_sent`; NM1 — `notify_message` BASE (`get_message_id` без защиты); GD1 — `notify_message`
без защиты вовсе; GD2 — старая защита `find_by(provider:)` (серия не продолжается); RN1/RN2/RN3 —
`already_sent` = 0 / N−1 / N+1; IM1 — id пишутся после всей серии; SG1 — `message_id_for` падает
на теле без id; RF1 — `report_delivery_failure` ничего не делает; LK1 — событие с сырым телом
(старый формат Twilio); LT2/LD2 — `process_error` twilio/dialog360 снова с сырым вебхуком;
DT1/DV1/DM1/DW1/DD1 — `delivery_hooks` в telegram/vonage/message_bird/twilio/dialog360 возвращает
`{}`. Поэтому `deliver_attachments` с обработкой `on_success`/`on_failure`/`already_sent`,
`BasePackage#notify_message`, `#store_message_id`, `#message_id_for`, `#resumable_delivery?`,
`#report_delivery_failure`, `#delivery_hooks`, `process_error` в twilio и dialog360 и строка
`delivery_hooks(conversation, part)` в каждом из пяти плагинов обязаны остаться.

## 6. Не трогать

- Всё вне списка AC-008. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`,
  `config/**`, `bin/**`, `db/**` (миграции нет — раздел 4, п. 2), `lib/**`, `app/models/**`,
  `app/jobs/**`, `app/graphql/**`, `app/services/message_apis/helpers.rb`, плагины кроме пяти
  названных, `CHANGELOG.md`, `.github/**`, `.githooks/**`, `.rubocop.yml`, `.rubocop_todo.yml`.
- Всё, что принесли m1–m8, не откатывать: версии гемов и Rails, load_defaults 8.1, все вложения и
  `captionless:`, absolute_url, SafeDownload, экранирование Slack, Rack::Attack, письма Devise.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — только добавлять. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec`, глобальный `require "webmock/rspec"` запрещены. RuboCop не
  глушить: `rubocop:disable` в коде `app/` и новые записи в `.rubocop_todo.yml` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-008, sha256). Чужие спеки
  (`fork-updates-m10*` и дальше) не трогать.
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq.
  Запрещены: `.vscode/`, self-hosted runner, `.env*` (кроме `.env.example`), невидимые
  Unicode-символы, новые гемы.
- Не превращать в событие единичный неуспешный ответ telegram/vonage/message_bird/dialog360 (его
  сегодня никто не показывает — раздел 10), не менять поиски по `message_source_id`, не
  добавлять индексы и столбцы, не писать строки для неуспешных запросов.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 528 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m9-probes/rspec_gate_m9.sh`

- **AC-002** — частичный сбой в пяти плагинах и статусы-ошибки дают безопасное событие errored, id сохраняются сразу и все, ретрай продолжает серию с места обрыва и ничего не повторяет, тело без id не роняет отправку, квитанции и статусы матчатся с любым вложением и со старыми строками.
  `bash docs/specs/fork-updates-m9-probes/rspec_gate_m9.sh --only docs/specs/fork-updates-m9-probes/m9_probe_spec.rb`

- **AC-003** — новые тесты убивают все 22 мутанта: колбэки, продолжение серии и его счёт, защита ретрая, запись id сразу, безопасный разбор id, пустой и сырой отчёт о сбое, сырые вебхуки, отключённые хуки в каждом из пяти плагинов.
  `python3 -I docs/specs/fork-updates-m9-probes/m9_mutation_gate.py`

- **AC-004** — новые тесты регрессионные: на коде BASE они падают по каждому маркеру, перечисленные примеры base-green там зелёные, старые примеры не падают.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m9-probes/m9_red_on_base.sh $B'`

- **AC-005** — строгий RuboCop без единого offense на всех добавленных и изменённых .rb вехи и на пробнике, как в CI.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m9-probes/m9_rubocop.sh $B'`

- **AC-006** — целостность: зависимости, конфиги, схема и модели не тронуты, спеки только дополнены, инварианты m1–m7 на месте, пять плагинов передают хуки доставки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m9-probes/m9_integrity_probe.py $B'`

- **AC-007** — нет регрессий m1–m8: загрузка четырёх сред с load_defaults 8.1, пробники рантайма m1–m5 и m7, загрузка m2–m4, redis из compose, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m9-probes/m9_regress.sh $B'`

- **AC-008** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "53307e110355e3228dabd6e650dab666e05863416c487ac7030512404f8e828d  docs/specs/fork-updates-m9-probes/examples_base.txt" "992a6a4e397a6196b8723a3df086ed901b80306ba81d2c210031ea29ef506626  docs/specs/fork-updates-m9-probes/m9_integrity_probe.py" "16b2fbd90cee17904bff69402b8dc3e1f231d8aea8013b7684e19c079791ce31  docs/specs/fork-updates-m9-probes/m9_mutation_gate.py" "792de35ea99621992604ecd783392ee97a409c743b16856c0e12c903bed58e8f  docs/specs/fork-updates-m9-probes/m9_probe_spec.rb" "4ba27eef617ad2779badb38ce4bdde1966da4c18e3091cbb2e636621508787be  docs/specs/fork-updates-m9-probes/m9_red_on_base.sh" "577101a7fb1fff842d4cf75fdd3860f5ba620521a63d96b073ab1d01a4b659dc  docs/specs/fork-updates-m9-probes/m9_regress.sh" "b069ecf4b3461b89a7308cfc353a9949c56f53490b457bae5866d7e1fb3e676f  docs/specs/fork-updates-m9-probes/m9_rubocop.sh" "95aa52a5791a7033ded211c9999a96c6c46a177670c3041f550602c684482bff  docs/specs/fork-updates-m9-probes/pending_allowed.txt" "ff64e93ecfd6b580f4fdc7c22f0476db91a5ec46fa68acb35699b92a87e4713e  docs/specs/fork-updates-m9-probes/rspec_gate_m9.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/(block_manager|base_package)[.]rb|app/services/message_apis/(telegram|vonage|message_bird|twilio|dialog360)/api[.]rb|spec/.+")"'`

- **AC-009** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-007, AC-008, AC-009 зелёные;
AC-002 красный (14 из 19 примеров: колбэки — `unknown keyword`, сохранён только первый id, нет
события, сырые вебхуки в событиях статусов, id пишутся в конце, ретрай не продолжает серию,
`NoMethodError` на `{"messages": []}`; зелёные на BASE поведение без новых keyword, старая строка
Vonage, единичный сбой Twilio, повтор после аудио с текстом и повтор после полной серии);
AC-003 красный (`block_manager.rb does not define on_failure` — гейт
останавливается до прогонов); AC-004 красный (`HEAD adds or changes no spec file over BASE`);
AC-005 на чистом клоне зелёный (новых .rb нет, пробник чист) — смысл появляется с работой;
AC-006 красный (нет `**hooks`/keyword, методов BasePackage, `RESUMABLE_DELIVERY` и хуков в пяти
плагинах, twilio со своим событием, `process_error` с сырым вебхуком).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно; один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка.

**`--base` и начало диапазона — ФИКСИРОВАННЫЙ BASE_SHA из шапки, а не плавающий `B`.**
`accept_run.py` ищет квитанции по `base_sha` отчёта (= строка BASE_SHA), а `run_id` журнала
берётся из `--base`; коммит постановщика со спекой лежит поверх BASE_SHA, и с `--base <B>`
квитанции уйдут в журнал другого прогона. Коммиты постановщика трогают только `docs/specs/**`,
которые исключены из ревью, поэтому диапазон от BASE_SHA показывает ровно работу исполнителя:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base 94dbeebc4b15e06efbe86b14e5996e89c0663ccc --range 94dbeebc4b15e06efbe86b14e5996e89c0663ccc..<REVIEW_SHA> --exclude docs/specs/fork-updates-m9.md --exclude "docs/specs/fork-updates-m9-probes/**" --context "chaskiq fork-updates-m9: deliver_attachments **hooks on_success/on_failure, BasePackage delivery_hooks/store_message_id/message_id_for/report_delivery_failure, id провайдера пишутся сразу строками ConversationPartChannelSource без миграции, ретрай не шлёт повторно, безопасное событие errored (status/code/message) при частичном сбое в telegram/vonage/message_bird/twilio/dialog360; только чтение"`

(то же для `qwen`; проверка — `review_run.sh verify … --base 94dbeebc4b15e06efbe86b14e5996e89c0663ccc --range <REVIEW_SHA>..<FINAL_SHA>`). Если постановщик сдвинет строку BASE_SHA до запуска — брать новое
значение из шапки. Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m9.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m9-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; не меняется ли
возвращаемое значение и порядок запросов; не дублируется ли событие при единичном сбое Twilio;
не утекает ли в событие что-то кроме status/code/message; пишутся ли id до следующего запроса;
не падает ли `notify_message` на любом теле; не остаётся ли состояния в объекте API между вызовами.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-001 — итоговые числа
examples/failures/pending; в `note` AC-003 — строка `killed`/`SURVIVED` по каждому мутанту; в
`note` AC-004 — строки `red on BASE: …`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m9.md>",
  "base_sha": "<значение строки BASE_SHA из шапки>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m9.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-008 (модели, `db/**`, `helpers.rb`, другие плагины,
  конфиг RuboCop) или изменения существующей строки теста;
- зелёный rspec недостижим без изменения возвращаемого значения `deliver_attachments` или
  `send_message` (раздел 4, п. 6), без нового гема или без отката чего-то из m1–m8;
- мутант набора AC-003 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах.

## 10. Стыки

- После приёмки координатор вливает ветку в main и дописывает CHANGELOG (снять оба пункта Known
  issues m5/m7).
- Остаются вне вехи: единичный неуспешный синхронный ответ telegram/vonage/message_bird/dialog360
  по-прежнему не превращается в событие (раньше dialog360 на нём падал `NoMethodError` в джобе,
  после вехи — тихо, без id); точка продолжения ретрая сдвигается, если до исключения в той же
  попытке был неуспешный ответ (раздел 4, п. 3); квитанции `delivered` Vonage не обрабатываются
  вовсе; MMS в telnyx_sms (веха m11).
- По `docs/spec-queue.md`: m11 (Telnyx MMS) почти наверняка пойдёт через `deliver_attachments` —
  её спека должна опираться на контракт m9 (`**hooks` с `on_success`/`on_failure`, `delivery_hooks`) и
  запускаться после влития m9. m12 (старый синтаксис `any_instance` в спеках) правит строки тех же
  hook-спеков, куда m9 только дописывает в конец — конфликт возможен лишь текстовый, при rebase.
  m10 (подпись SNS) с путями m9 не пересекается.
