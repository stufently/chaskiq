# fork-updates-m11 — Telnyx MMS: отправка и приём медиа, статусы доставки

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m11.md`.
- BASE_SHA: `a6ec4ad4964c2eecf2302abe2c073bf5f2859384` — `main` с влитыми m4 (telnyx_sms шлёт текст из блоков), m5/m7 (SafeDownload, все вложения), m8, ci-parity, **m9** (возобновляемая доставка вложений: `deliver_attachments(..., **hooks)`, `delivery_index`, `RESUMABLE_DELIVERY`, `BasePackage#delivery_hooks`/`#notify_message`/`#add_error_event`), **m10** (подпись SNS), m12 и **m13** (rack 3.2.8).
- **`examples_base.txt` снят на этом BASE** (`rspec_gate_m11.sh --write-base` на чистом клоне
  `main`, полный rspec зелёный). Если `main` уйдёт вперёд до запуска, постановщик повторяет
  `--write-base` на чистом клоне нового BASE, коммитит файл и заменяет его sha256 в AC-007. AC-001
  сравнивает именно с этим файлом; порог «не меньше N примеров» — число строк в нём (в гейте не
  захардкожен).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (`make_clone.sh --work-branch fork-updates-m11` ставит
  upstream `origin/main`). В `report.json` поле `base_sha` равно значению строки BASE_SHA.
  **Авторевью (раздел 8) — от фиксированного BASE_SHA из этой строки, не от `B`:**
  `review_run.sh --base <BASE_SHA>` и диапазон `<BASE_SHA>..<REVIEW_SHA>` — `accept_run.py` ищет
  квитанции по `base_sha` из `report.json`. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- Исполнитель назначается при запуске (Codex `cx` или Qwen `qw`/`qw2`); мутации по новым тестам
  потом гоняет противоположный исполнитель. Исправления внутри вехи — тому же исполнителю.
- Цель: `MessageApis::TelnyxSms` отправляет вложения как MMS, сохраняет входящие медиа MMS в
  Active Storage через SafeDownload, сохраняет id исходящего сообщения и правильно разбирает
  статусы доставки.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m11`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push запрещён,
  постановщик заберёт работу `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить. Сеть в тестах не
  нужна и не используется (живой Telnyx не вызывать).

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (`docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.14, libpq, libvips, node, jq |
| гемы Rails 8.1 | `$HOME/.cache/chaskiq-m6/bundle` | гейт, пробники, rubocop; гемы в вехе не меняются |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m11-probes
bash $P/rspec_gate_m11.sh                               # полный строгий rspec, ~6 мин
bash $P/rspec_gate_m11.sh --only $P/m11_probe_spec.rb   # один файл
python3 -I $P/m11_mutation_gate.py MU1 IM1              # часть мутантов (полный набор ~10 мин)
```

## 3. Задача и почему

`app/services/message_apis/telnyx_sms/api.rb` на BASE:
1. `send_message` шлёт только `plain_text(blocks)`; вложения (ImageBlock/FileBlock/VideoBlock/
   AudioRecorderBlock) молча теряются, сообщение только из вложения не уходит вовсе.
2. `send_message` возвращает `data = JSON.parse(response.body)` — Hash, а
   `BasePackage#notify_message` делает `JSON.parse(response.body или response)` → `TypeError`
   (проверено: `JSON.parse(Hash)` в образе — `TypeError`). id исходящего (`data.id`) не
   сохраняется, джоб уведомления падает после успешной отправки, а `message.finalized` по этому
   id никогда не находит часть.
3. `process_incoming_message` берёт только `payload.text`: медиа MMS (`payload.media[]`) теряются,
   MMS только с картинкой (`text: null`) превращается в пустое сообщение; ссылки Telnyx живут
   30 дней, поэтому медиа надо скачать и сохранить у себя.
4. `message.finalized` помечает часть прочитанной при ЛЮБОМ итоге, в том числе
   `delivery_failed`/`sending_failed`; ошибки доставки агент не видит.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 по официальной документации Telnyx и в Docker (клон от BASE_SHA и
черновик; черновик — только для проверки достижимости, в веху не идёт):
Замеры сняты на `7e5523d3`; до BASE_SHA добавились только коммиты ci-parity (`bin/ci-local`,
`.githooks/`, `.gitignore`, документация) фикс флейка `campaign_spec.rb` (описания примеров те же) и фикс входа агента
(`app/controllers/agents/sessions_controller.rb`, +3 примера в `examples_base.txt`) — путей вехи это
не касается; `config/`, `Gemfile.lock` те же.

1. Отправка, «Send a message», https://developers.telnyx.com/api-reference/messages/send-a-message:
   `POST https://api.telnyx.com/v2/messages`, `Authorization: Bearer`, тело JSON: `to` (E.164),
   `from` или `messaging_profile_id`, `text` («Required for SMS»), `media_urls` — массив URL
   («Required for MMS», «The total media size must be less than 1 MB»), `subject`, `type`
   (`SMS`/`MMS`, необязателен). Ответ 200: `data.id` (UUID), `data.type`, `data.media[].url`,
   `data.to[].status` (`queued`); ошибки 4XX: `{"errors": [{"code", "title", "detail", "source"}]}`.
   FAQ (https://support.telnyx.com/en/articles/4450150-faqs-about-mms-at-telnyx): `media_urls`
   включать только для MMS, иначе SMS считается MMS. Пример v2 с `text` + `media_urls` в одном
   запросе: https://support.telnyx.com/en/articles/3102823-mms-sending-and-receiving (там же —
   лимит по умолчанию 1 MMS/с, размеры 1 МБ / 600 КБ / 300 КБ по уровню оператора).
2. Приём, «Receive SMS and MMS Messages», https://developers.telnyx.com/docs/messaging/messages/receive-message:
   `data.event_type = "message.received"`, `data.payload.id` (для дедупликации),
   `payload.from.phone_number`, `payload.text` («may be null for media-only MMS»), `payload.type`
   (`SMS`/`MMS`), `payload.media[]` — `url` («Authenticated download URL (expires in 30 days)»),
   `content_type`, `sha256`, `size`; пример URL — `https://media.telnyx.com/example-image.png`;
   скачивание в примерах — `GET` с `Authorization: Bearer <API key>`. Ответить 2xx за 2 с.
3. Статусы, «Receiving Webhooks for Messaging», https://developers.telnyx.com/docs/messaging/messages/receiving-webhooks:
   события `message.received`, `message.sent`, `message.finalized`; у `message.finalized`
   `payload.id` — id исходящего, итог в `payload.to[].status`: `delivered`, `sending_failed`,
   `delivery_failed`, `delivery_unconfirmed` (плюс промежуточные `queued`/`sending`/`sent`);
   `payload.errors[]` с `code`/`title`/`detail`. Там же — подпись вебхуков ed25519
   (`telnyx-signature-ed25519`, `telnyx-timestamp`) — вне вехи (раздел 10).
4. Код BASE: `BlockManager.media_blocks`, `.block_data`, `.absolute_url`, `.plain_text`,
   `.deliver_attachments(attachments, plain_text, send_text:, captionless: [], **hooks)` (hooks —
   только `on_success(response, index)`, `on_failure(response)`, `already_sent` — Set индексов;
   индекс текста = `attachments.size`; итоговый неуспех `on_failure` НЕ получает — его сообщает
   вызывающий) — публичные. `BasePackage` (приватные, вызываются из плагина): `notify_message` →
   `with_delivery_lock`, для плагина с `RESUMABLE_DELIVERY = true` и сообщения с любыми
   `media_blocks` id частей пишут только хуки `delivery_hooks(conversation, part)` (по
   `delivery_index`), иначе `store_message_id` первого ответа; `report_delivery_failure(conversation,
   part, response)` берёт текст из `errors[0].title` и т. п. и пишет событие через
   `add_error_event(conversation, source_id, status:, code:, text:)` (URL вырезаются, ≤ 200 символов,
   код — только безопасный; `status: nil` → не больше одного события на `source_id`). Так же устроены
   twilio, vonage, telegram, message_bird, dialog360. `Helpers#direct_upload`, `#photo_block`,
   `#file_block`, `#serialized_block`, `#main_doc`, `#find_channel` (пустой id → nil),
   `#process_read` есть; `SafeDownload.fetch` не умеет заголовки; `api.rb` Telnyx и
   `safe_download.rb` после m4/m5 не менялись. Вебхук приходит
   в `Api::V1::Hooks::ProviderController#process_event` → `HookMessageReceiverJob` →
   `process_event(params, package)` с `HashWithIndifferentAccess`.
5. Черновик (разделы 5.A–5.D) с примерными тестами на этом BASE (`main` с влитым m9): пробник
   `m11_probe_spec.rb` 27/27, мутационный гейт 20/20 убиты, пробник целостности и «красный на BASE» по
   каждому примеру зелёные, полный гейт зелёный, rubocop изменённых файлов — ноль нарушений (с
   одним inline-исключением `Metrics/ParameterLists`, п. 5.A.4). На BASE пробник красный: 20 из 27
   (зелёные — 7 примеров `base-green`). Пробник — ноль нарушений rubocop.
6. Поддерживаемые типы исходящих MMS (https://support.telnyx.com/en/articles/3102823-mms-sending-and-receiving,
   раздел «Supported MMS File Types and Sizes», дословно): «Telnyx supports a wide range of file
   types for MMS, including: text/plain, text/vcard, image/jpeg, image/png, image/gif, video/3gpp,
   video/mp4». PDF в списке нет. Блоки вложений редактора несут только `attrs.url` (типа нет),
   поэтому тип определяется по расширению пути URL.

Предположения (не проверены): что `media.telnyx.com` (или другой хост под `telnyx.com`) — реальный
хост медиа и он принимает Bearer API key; медиа с других хостов веха НЕ качает вовсе (вебхук не
подписан, раздел 5.C) — если живой Telnyx отдаёт медиа с другого домена, это всплывёт на живом
стенде и решается правкой спеки; что живой Telnyx принимает
`media_urls` с URL Active Storage (`/rails/active_storage/blobs/redirect/...` отвечает редиректом на
сервис хранения); ограничение числа элементов `media_urls` в документации не найдено — веха
шлёт все вложения одним запросом; что `message.finalized` приходит и для входящих id не бывает.

Флейк `spec/mailers/campaign_spec.rb:47` (Faker-имя с апострофом) исправлен до BASE_SHA (`352f8c09`);
любой провал AC-001 теперь — настоящий.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.
Имена методов ниже обязательны (их перекрывают мутанты AC-003); методы экземпляра — `def <имя>`.

**A. `MessageApis::SafeDownload`** (`app/services/message_apis/safe_download.rb`): новые keywords
`fetch(url, ..., headers: {}, allow_own_host: true)`.
1. `headers:` уходят ТОЛЬКО в первый запрос; после ЛЮБОГО редиректа (в том числе на тот же хост)
   — без них. Служебный метод запроса принимает их третьим позиционным аргументом:
   `def self.request(uri, address, headers, &block)`. `Accept-Encoding: identity` не перекрывается.
2. `allow_own_host: false` отключает исключение «свой `HOST` на приватном адресе» (`own_origin?`)
   на всех шагах; по умолчанию `true` — как сейчас.
3. Без новых keywords поведение и контракт `fetch` для всех вызывающих (Twitter, карточки ссылок,
   CreateUrlUpload, SNS) не меняются; фильтры адресов, лимиты и `ipaddr=` — как были.
4. Rubocop: `safe_download.rb` уже в `.rubocop_todo.yml` по метрикам, кроме `Metrics/ParameterLists`
   — шестой keyword его нарушает. Единственное разрешённое inline-исключение вехи:
   `# rubocop:disable Metrics/ParameterLists` на строке `def self.fetch(` с комментарием «почему»;
   остальные нарушения — рефакторингом (например, вынести проверку адресов в служебный метод).

**B. Отправка** (`app/services/message_apis/telnyx_sms/api.rb`) — на финальном API m9, как в
twilio/vonage, ничего в `block_manager.rb`/`base_package.rb` не меняя:
1. В классе `RESUMABLE_DELIVERY = true` (как у пяти плагинов m9): повтор джоба не шлёт уже
   доставленные медиа, id каждой части хранится с её `delivery_index`.
2. `send_message(conversation, part)`: блоки и текст — как сейчас (Dante, legacy, HTML).
   `media = media_blocks(blocks)` делятся `supported_media?(block)`: тип по расширению пути
   `attachment_url(block)` (`absolute_url(block_data(block)["url"])`), без учёта регистра, ровно
   список из п. 4.6: `.jpg`/`.jpeg` image/jpeg, `.png`, `.gif`, `.mp4`, `.3gp` video/3gpp, `.txt`
   text/plain, `.vcf`/`.vcard` text/vcard (MIME-строки списка — в коде, константой).
   **Неподдерживаемое (PDF и всё прочее) не уходит как медиа, а добавляется ссылкой отдельной
   строкой в конец текста** (`текст\nURL`; без текста — только URL). Почему ссылка, а не
   `report_delivery_failure`: агент отправил сообщение, и клиент должен его получить; Telnyx/оператор
   такое медиа отвергнет или обрежет, а ссылка Active Storage — тот же URL, что ушёл бы в
   `media_urls`. Нет ни текста, ни поддерживаемых вложений — ничего не слать.
3. `media` пуст — один `send_sms_message(channel_id, plain_message)`. Иначе (**даже если все
   вложения ушли ссылками** — для `notify_message` сообщение с медиа возобновляемое, и id пишут
   только хуки) — `MessageApis::BlockManager.deliver_attachments(attachments, plain_message,
   send_text: ->(text) { send_sms_message(channel_id, text) }, **delivery_hooks(conversation, part))
   { |_type, url, caption| send_sms_message(channel_id, caption, [url]) }`: каждое медиа — отдельный
   запрос с ОДНИМ URL в `media_urls`, текст — подпись первого успешного медиа (`captionless:` не
   нужен). Возвращает ответ Faraday (НЕ разобранный Hash).
4. `send_sms_message(channel_id, message, media_urls = [])`: тело `to`, `text` — только если текст
   не пустой, `media_urls` — только если список не пустой, плюс `from`/`messaging_profile_id`
   из `resolve_outbound_phone` как сейчас.
5. Итоговый ответ неуспешен — `report_delivery_failure(conversation, part, response)` и `nil` (как
   twilio; частичные сбои сообщает хук `on_failure`). `delivery_hooks`, `report_delivery_failure`,
   `notify_message`, `store_message_id`, `add_error_event` и прочие методы `BasePackage` в telnyx не
   переопределять: `report_delivery_failure` уже читает `errors[0].title` Telnyx.
6. **В событие и его `data` не класть тело ответа провайдера** — это обеспечивает
   `add_error_event` m9 (статус, безопасный код, ≤ 200 символов).

**C. Приём** (`process_incoming_message`):
1. Текст — `payload.text.to_s` (null допустим); блоки: строки текста (`serialized_block`) + по
   одному блоку на каждый элемент `payload.media`; `serialized_content = main_doc(blocks).to_json`,
   `html_content` — текст. Нет ни текста, ни медиа — сообщение не создавать. Дедупликация по
   `payload.id` и `STOP` — как сейчас.
2. `media_block(media, message_id, index)` → блок: `download_media(media["url"])`; `nil` → текстовый
   блок `[attachment unavailable: <content_type>]`; иначе `direct_upload(file:, filename:
   "#{message_id}-#{index}<расширение по типу>", content_type: media["content_type"] или
   body.mime_type)`; `image/*` → `photo_block(url: upload[:url], text: "")`, прочее →
   `file_block(url: upload[:url], text: content_type)`. Ссылка Telnyx в сообщение не попадает.
3. `media_url?(url)` — `URI::HTTPS`, без userinfo, хост (без учёта регистра) ровно `telnyx.com` или
   оканчивается на `.telnyx.com`. Вебхук не подписан: всё остальное (`http://`, `eviltelnyx.com`,
   `telnyx.com.evil.com`, `telnyx.co`, CDN, S3) **не качается вовсе** — `Rails.logger.warn` (без
   полного URL и ключа) и `nil` (→ блок `[attachment unavailable: …]`).
4. `download_media(url)` — `media_url?` ложно → лог и `nil`; иначе только
   `MessageApis::SafeDownload.fetch(url, max_bytes: 5 * 1024 * 1024, allow_own_host: false,
   headers: {"Authorization" => "Bearer #{@api_key}"})` (ключ — только в первый запрос, п. 5.A.1;
   исключение своего `HOST` выключено — медиа никогда не качается с приватного адреса).

**D. Статусы** (`process_message` → `message.finalized` → `process_status(payload)`). Часть ищется
ТОЛЬКО в приложении интеграции: `app_channel(id)` — `ConversationPartChannelSource` с `provider:
PROVIDER`, `message_source_id: id` и разговором `app_id == @package.app_id` (join через
`conversation_part` → `conversation`); глобальные `find_channel`/`process_read` в telnyx не
вызывать (id чужого приложения не трогается). Нет части → ничего.
`payload.to[].status` содержит `delivered` → `part.read!`; содержит
`sending_failed` или `delivery_failed` → `add_error_event(part.conversation,
"telnyx-failed-#{payload.id}", status: nil, code: errors[0].code, text: errors[0].title || detail ||
статусы через запятую)` (m9: `status: nil` даёт одно событие на повтор вебхука, сырой
`payload`/`errors` в `data` не попадает); прочие статусы и `message.sent` — ничего.

**E. Тесты** (в существующий `spec/controllers/api/v1/hooks/telnyx_sms_spec.rb` — только
ДОБАВЛЕНИЕ строк; новый `spec/services/message_apis/safe_download_headers_spec.rb`). HTTP — webmock,
включённый локально (`include WebMock::API`, `WebMock.enable!`/`disable!` в `around`), DNS —
`allow(MessageApis::SafeDownload).to receive(:resolve)`, свой `HOST` — заглушкой
`Chaskiq::Config.get("HOST")`. Слова-маркеры в описаниях примеров обязательны — по ним мутационный
гейт ищет упавший пример:
1. `telnyx_sms_spec.rb`, отправка: поддерживаемые вложения и текст — по запросу на медиа, один URL
   в `media_urls`, текст на первом (`media_urls`); PDF уходит ссылкой в тексте, не в `media_urls`, и
   PDF без текста — SMS с одной ссылкой (`unsupported`); `notify_message` сохраняет id каждой
   отправленной части, текстового сообщения и сообщения, где вложение ушло только ссылкой (`message id`);
   повтор `notify_message` с уже сохранённым `delivery_index` 0 шлёт только второе медиа (`retry`); ошибка провайдера — событие errored
   без тела ответа и nil (`errored`); сбой второго вложения при успехе первого (`partly sent`).
2. `telnyx_sms_spec.rb`, приём: MMS с картинкой и файлом с `media.telnyx.com` — два блоба и блоки с
   их URL (`inbound MMS`); ключ уходит на `https` `media.telnyx.com`, `telnyx.com`, хост в другом
   регистре (`API key`); `http://media.telnyx.com` не качается (`plain http`); `eviltelnyx.com`,
   `telnyx.com.evil.com`, `telnyx.co` не качаются (`lookalike`); чужой хост не качается и пишется в
   лог (`foreign host`); после редиректа на тот же хост ключа нет (`redirect`); `media.telnyx.com` на
   приватном адресе не качается (`private`); то же, когда `HOST` = этот хост (`own host`); медиа
   больше 5 МБ (`oversized`).
3. `telnyx_sms_spec.rb`, статусы: `delivered` читает часть, `message.sent` и `delivery_unconfirmed` —
   нет (`delivered`); `delivery_failed` — одно событие без сырого payload при повторе (`failed
   delivery`); `delivered`/`delivery_failed` с id части ДРУГОГО приложения ничего не меняют (`another
   app`).
4. `safe_download_headers_spec.rb`: заголовки уходят в первый запрос и не уходят после редиректа на
   другой хост и на тот же хост (`redirect`); по умолчанию свой `HOST` на приватном адресе качается,
   с `allow_own_host: false` — нет (`own host`); без `headers:` лишних заголовков нет.
5. **Красные на BASE — по каждому примеру** (AC-008): каждый новый пример обоих файлов падает на
   BASE (как пример, не ошибкой загрузки); пример, который законно зелёный на BASE (охранный тест,
   который проходит и код, ничего не качающий: текст без `media_urls`, `plain http`, `lookalike`,
   `private`, `own host` в telnyx, `oversized`, «нет лишних заголовков»), обязан содержать в описании
   `base-green` и на BASE проходить. Примеры BASE не должны падать.

Мутанты AC-003 (дописываются в конец файла): MU1 — `send_sms_message` без `media_urls`; MT1 —
`supported_media?` пропускает любой тип; HK1 — `delivery_hooks` пустой; RS1 — `send_message` возвращает
разобранный Hash; ER1 — ошибка не пишется событием; IM1 — `media_block` теряет медиа; IM2 —
`download_media` голым `Net::HTTP`; IM3 — без `max_bytes`; AU1 — `media_url?` пускает `http`; AU3 —
суффикс без точки (`eviltelnyx.com`); AU4 — без якоря конца (`telnyx.com.evil.com`); AU5 — `telnyx.co`;
AU6 — любой хост; AU2 — SafeDownload шлёт заголовки после любого редиректа; AU7 — после редиректа на
тот же хост; OH1 — `allow_own_host` игнорируется; SC1 — `app_channel` = глобальный `find_channel`;
RV1 — без `RESUMABLE_DELIVERY`; ST1 — `finalized` читает при любом статусе; ST2 — ошибка доставки не пишется.

Новые и изменённые Ruby-файлы — ноль нарушений rubocop проекта (`.rubocop.yml` +
`.rubocop_todo.yml`, CI падает на любом; AC-006); правки `.rubocop*.yml` запрещены.

## 6. Не трогать

- Всё вне списка AC-007. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`,
  `config/**`, `bin/**`, `db/**`, `lib/**`, `app/models/**`, `app/jobs/**`, `app/controllers/**`,
  `app/services/message_apis/block_manager.rb`, `helpers.rb`, `base_package.rb` (финальный API m9;
  m11 только ВЫЗЫВАЕТ `media_blocks`/`deliver_attachments`/`absolute_url`/`plain_text`,
  `delivery_hooks`/`report_delivery_failure`, `direct_upload`/`photo_block`/`file_block`), другие
  плагины, `.rubocop*.yml`, `CHANGELOG.md`, фронтенд.
- Всё, что принесли m1–m8, не откатывать: версии гемов и Rails, `load_defaults 8.1`, Rack::Attack,
  SafeDownload и его фильтры, все вложения в других провайдерах, тексты telnyx из m4.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — только добавлять. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec`, глобальный `require "webmock/rspec"` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-007, sha256).
- Запрещено брать что-либо из форков (VooDooNoir/chaskiq, kreasialamteknologi/chaskiq и др.),
  `.vscode/`, `.env*` (кроме `.env.example`), невидимые Unicode-символы, git- и path-источники
  в Gemfile, новые гемы (в том числе гем `telnyx`).
- Вне вехи: проверка ed25519-подписи вебхуков Telnyx, групповые MMS (`/v2/messages/group_mms`),
  `subject`, настройки пакета (`definition_info`).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE из examples_base.txt (перегенерирован постановщиком перед запуском, их число — порог), pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m11-probes/rspec_gate_m11.sh`

- **AC-002** — поддерживаемые вложения уходят MMS через deliver_attachments (один URL в media_urls), PDF — ссылкой в тексте, id частей сохраняются, ошибки — событием без тела ответа; входящие медиа качаются только с https *.telnyx.com через SafeDownload (с ключом только в первый запрос, без своего HOST, приватных адресов и сверх лимита) в Active Storage; статусы — только для частей своего приложения.
  `bash docs/specs/fork-updates-m11-probes/rspec_gate_m11.sh --only docs/specs/fork-updates-m11-probes/m11_probe_spec.rb`

- **AC-003** — новые тесты убивают все 20 мутантов: media_urls, типы MMS, хуки m9, RESUMABLE_DELIVERY, ответ, событие ошибки, входящие медиа, загрузка мимо SafeDownload, лимит, http/похожие/чужие хосты, заголовки после редиректа (любого и на тот же хост), allow_own_host, поиск части в своём приложении, статусы.
  `python3 -I docs/specs/fork-updates-m11-probes/m11_mutation_gate.py`

- **AC-004** — целостность: зависимости, конфиги, контроллеры, BlockManager, Helpers и BasePackage не тронуты, спеки только дополнены, SafeDownload с headers: и allow_own_host: true по умолчанию, telnyx на deliver_attachments/delivery_hooks/SafeDownload(allow_own_host: false) с app_channel и списком типов MMS, без сырого тела в событиях, инварианты m1–m7 на месте.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m11-probes/m11_integrity_probe.py $B'`

- **AC-005** — нет регрессий m1–m10: загрузка четырёх сред (m8), пробники рантайма m1–m5, загрузка m2–m4, redis из compose, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m11-probes/m11_regress.sh $B'`

- **AC-006** — изменённые и новые Ruby-файлы вне docs — ноль нарушений rubocop проекта (CI падает на любом нарушении).
  `bash -c 'B=$(git merge-base HEAD @{u}); F=$(git diff --name-only --diff-filter=AM $B...HEAD -- "*.rb" ":(exclude)docs/**"); test -z "$F" || docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m6/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bundle exec rubocop --force-exclusion $F'`

- **AC-007** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "a721bd78ba5324bfa799ea72204267d8d6eec4fc48502979f0357974448ee635  docs/specs/fork-updates-m11-probes/examples_base.txt" "d42ec162c39e4831c562d8c5eb8c5bbef9b8d880213e32bdbc0ec861548428fe  docs/specs/fork-updates-m11-probes/m11_integrity_probe.py" "a5cd4522777e9cc3c09dedc41c02ba55af6d353e21620114387368ae8f493302  docs/specs/fork-updates-m11-probes/m11_mutation_gate.py" "024a985c0626c880e00223aca796c4332edc79615dfb542567f96fe008783467  docs/specs/fork-updates-m11-probes/m11_probe_spec.rb" "d8bd550cdde48b9af603e29a1e44d7981907d03944de745cf89d4158b0b77d62  docs/specs/fork-updates-m11-probes/m11_red_on_base.sh" "30644b11015fba3d9c349ef7cd51d4ddc63447db51aa1e5003d65a222da32e32  docs/specs/fork-updates-m11-probes/m11_regress.sh" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m11-probes/pending_allowed.txt" "a643f84e33064da0de5de0d4822bb93c9eb581165332065d929968784cfe61a0  docs/specs/fork-updates-m11-probes/rspec_gate_m11.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/safe_download[.]rb|app/services/message_apis/telnyx_sms/api[.]rb|spec/controllers/api/v1/hooks/telnyx_sms_spec[.]rb|spec/services/message_apis/safe_download_headers_spec[.]rb")"'`

- **AC-008** — новые тесты Telnyx и SafeDownload красные на BASE по каждому примеру: файлы грузятся, каждый новый пример падает (кроме помеченных base-green, которые проходят), примеры BASE не падают, по каждому маркеру 5.E есть красный пример.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m11-probes/m11_red_on_base.sh $B'`

- **AC-009** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком на BASE_SHA): AC-001, AC-005, AC-006, AC-007, AC-009
зелёные; AC-002 красный (20 из 27; зелёные на BASE только 7 примеров `base-green` — их проходит и
код, который ничего не качает); AC-003 красный (`telnyx_sms/api.rb does not define def
send_sms_message` — гейт останавливается до прогонов); AC-004 красный (нет `headers:`/`allow_own_host:`,
`RESUMABLE_DELIVERY`, методов 5.B–5.D, `deliver_attachments`/`delivery_hooks`, `send_message`
кончается разобранным телом); AC-008 красный (второго файла нет: `… is not committed at HEAD`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки из шапки, не плавающий `B`: по нему `accept_run.py` ищет квитанции); один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m11.md --exclude "docs/specs/fork-updates-m11-probes/**" --context "chaskiq fork-updates-m11: Telnyx MMS — RESUMABLE_DELIVERY и deliver_attachments финального m9 с одним URL в media_urls на запрос, delivery_hooks, ответ Faraday для data.id, ошибки через report_delivery_failure без тела ответа; PDF и прочие типы вне списка MMS Telnyx — ссылкой в тексте; входящие payload.media только с https *.telnyx.com через SafeDownload (5 МБ, allow_own_host: false, Bearer только в первый запрос) в Active Storage, прочие хосты не качаются; message.finalized ищет часть только в приложении интеграции: delivered читает, failed — событие; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m11.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m11-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6 (BlockManager, Helpers, BasePackage — m9); не
попадает ли тело ответа или сырой payload Telnyx в событие/`data`; утечка
API-ключа (хост `telnyx.com.evil`, `eviltelnyx.com`, `telnyx.co`, `http://`, userinfo, редирект на
тот же хост, регистр); загрузка с не-telnyx хоста или со своего `HOST`; поиск части по id вне
приложения интеграции; уходит ли неподдерживаемый тип в `media_urls`; загрузка мимо SafeDownload;
теряются ли текст или медиа (media-only, `text: null`, недоступное медиа); не изменился ли
контракт `SafeDownload.fetch` для Twitter, карточек ссылок, CreateUrlUpload и SNS.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-001 — итоговые числа
examples/failures/pending; в `note` AC-003 — строка `killed`/`SURVIVED` по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m11.md>",
  "base_sha": "<значение строки BASE_SHA из шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "codex|qwen", "model": "<точная модель>"},
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m11.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-007 (`block_manager.rb`, `helpers.rb`, `base_package.rb`,
  контроллеры, модели, `config/**`, `.rubocop*.yml`, Gemfile, другие плагины) или изменения
  существующей строки теста;
- API m9 на BASE отличается от п. 4.4/5.B (хуки `deliver_attachments`, `delivery_hooks`,
  `RESUMABLE_DELIVERY`, `add_error_event`), или `report_delivery_failure` кладёт в событие тело ответа;
- нужен новый гем, или зелёный rspec недостижим без отката m1–m8;
- мутант набора AC-003 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш гемов или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах, ходить в живой Telnyx.

## 10. Стыки

- **fork-updates-m9, m10, m12, m13 влиты в BASE.** m11 строится на финальном API m9 (п. 4.4) и не
  правит его файлы. Пробники m7, m9 и m10 в регресс m11 НЕ входят: m7 противоречит m10, а пробники
  m9/m10 писались против черновиков и на влитом коде красные (m9 — тело Dialog360 без id, 1 из 19;
  m10 — хост сертификата, 2 из 26); влитое поведение m9/m10 проверяют их спеки в полном rspec (AC-001). m10 вызывает `SafeDownload.fetch(url, max_bytes:,
  max_redirects: 0, deadline: 5)` без новых keywords — совместимо. m13 (Rack 3) вебхук Telnyx не
  затрагивает: `ProviderController` читает параметры как раньше.
- Остаётся вне вехи: проверка ed25519-подписи вебхуков Telnyx (без неё любой может прислать
  поддельный `message.received`/`message.finalized`; m11 лишь не отдаёт такому вебхуку ключ API);
  ограничение суммарного размера исходящих медиа 1 МБ (решает Telnyx, ошибка вернётся событием);
  после приёмки координатор вливает ветку в main и дописывает CHANGELOG.
