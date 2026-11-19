# fork-updates-m10 — проверка подписи SNS-сообщений до любых действий

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m10.md`.
- BASE_SHA: `c51c75735267fa24a347e2a8dcb1449908f983df` — `main` с влитыми m6 (Rails 8.1.4.1), m7 (SafeDownload, SubscribeURL только sns.*), m8 (`load_defaults 8.1`) ci-parity (только `bin/ci-local`, хуки, документация), фиксом флейка `campaign_spec` и фиксом входа агента (`Agents::SessionsController`, новый `spec/requests/agents_sessions_spec.rb`, 3 примера).
- BASE плавающий: если до запуска `main` уйдёт вперёд (например, влита веха m9 или m11), постановщик
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев
  считают `B=$(git merge-base HEAD @{u})` сами (`make_clone.sh --work-branch fork-updates-m10`
  ставит upstream `origin/main`). В `report.json` поле `base_sha` равно значению строки BASE_SHA.
  **Авторевью (раздел 8) — от фиксированного BASE_SHA из этой строки, не от `B`:**
  `review_run.sh --base <BASE_SHA>` и диапазон `<BASE_SHA>..<REVIEW_SHA>` — `accept_run.py` ищет
  квитанции по `base_sha` из `report.json`. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- Исполнитель назначается при запуске (Codex `cx` или Qwen `qw`/`qw2`); мутации по новым тестам
  потом гоняет противоположный исполнитель. Исправления внутри вехи — тому же исполнителю.
- Параллельно идёт fork-updates-m11 (Telnyx MMS) в своём клоне; пути двух вех не пересекаются
  (раздел 10).
- Цель: каждое сообщение на `POST /api/v1/hooks` (Notification, SubscriptionConfirmation,
  UnsubscribeConfirmation) проверяется по подписи SNS раньше любого действия; неподписанное или
  поддельное отвергается с понятным статусом.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m10`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push запрещён,
  постановщик заберёт работу `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить (никаких
  gem/bundle/npm/yarn/pip/apt на хосте). Сеть в тестах не нужна и не используется.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (`docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.14, OpenSSL 3.0, libpq, libvips, node, jq |
| гемы Rails 8.1 | `$HOME/.cache/chaskiq-m6/bundle` | гейт, пробники, rubocop; гемы в вехе не меняются |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m10-probes
bash $P/rspec_gate_m10.sh                               # полный строгий rspec, ~6 мин
bash $P/rspec_gate_m10.sh --only $P/m10_probe_spec.rb   # один файл
python3 -I $P/m10_mutation_gate.py SV1 CS1              # часть мутантов (полный набор ~12 мин)
```

## 3. Задача и почему

`Api::V1::HooksController` (`POST /api/v1/hooks`, без аутентификации) принимает любой JSON и
действует по нему: `x-amz-sns-message-type: SubscriptionConfirmation` (или тело с
`notificationType: AmazonSnsSubscriptionSucceeded`) — запрос на `SubscribeURL` (m7 ограничил хост
`sns.<регион>.amazonaws.com(.cn)`, но подписи нет); `Type: Notification` — разбор события SES и
`SnsReceiverJob` (метрики кампаний, прочтение сообщений, **отписка пользователей** при bounce и
complaint), а письмо SES Receipt — чтение объекта из S3 и создание сообщений в разговорах. Любой,
кто знает адрес, подделывает отписки, прочтения и входящие письма. AWS требует проверять подпись
до обработки любого сообщения («Verifying the signatures of Amazon SNS messages»,
https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 (Docker, клон от BASE_SHA и черновик; черновик — только для проверки
достижимости, в веху не идёт):
Замеры сняты на `7e5523d3`; до BASE_SHA добавились только коммиты ci-parity (`bin/ci-local`,
`.githooks/`, `.gitignore`, документация) фикс флейка `campaign_spec.rb` (описания примеров те же) и фикс входа агента
(`app/controllers/agents/sessions_controller.rb`, +3 примера в `examples_base.txt`) — путей вехи это
не касается; `config/`, `Gemfile.lock` те же.

1. **SDK-верификатора в бандле нет.** `Aws::SNS::MessageVerifier` живёт в геме `aws-sdk-sns`;
   в `Gemfile.lock` только `aws-sdk-core 3.254.1`, `-s3`, `-ses`, `-sesv2`, `-kms`, `-rails 5.2.0`,
   `aws-actionmailer-ses`; в `$HOME/.cache/chaskiq-m6/bundle` `aws-sdk-sns` нет ни в одной версии
   (свежая на rubygems — 1.133.0). Новый гем запрещён (раздел 6). Кроме того, исходник SDK
   (`gems/aws-sdk-sns/lib/aws-sdk-sns/message_verifier.rb`, ветка version-3) качает сертификат
   приватным `https_get` через голый `Net::HTTP` с тремя повторами, без лимита размера и без
   SSRF-фильтра — подключить `MessageApis::SafeDownload` можно только манкипатчем приватного
   метода. **Решение: свой маленький верификатор**, повторяющий логику SDK (поля по типу,
   обязательные поля, запрет переводов строк, https + хост + `.pem`) и добавляющий то, чего в SDK
   нет (срок сертификата, allowlist TopicArn, 503 на временный сбой); загрузка — только
   `SafeDownload.fetch`.
2. Алгоритм (AWS, «Verifying the signature of an Amazon SNS message when using HTTP query-based
   requests», https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message-verify-message-signature.html):
   строка подписи — пары `Ключ\nЗначение\n` в байтовом порядке ключей, ровно поля типа:
   Notification — `Message MessageId Subject(если есть) Timestamp TopicArn Type`;
   SubscriptionConfirmation и UnsubscribeConfirmation — `Message MessageId SubscribeURL Timestamp
   Token TopicArn Type`; один завершающий `\n`. `Signature` — Base64; `SignatureVersion` 1 → SHA1,
   2 → SHA256 (RSA). Сертификат — X.509 по `SigningCertURL`, только https с домена AWS.
   Обязательные поля (AWS «HTTP/HTTPS notification JSON format» и «subscription confirmation JSON
   format»): у всех трёх типов `Message`, `MessageId`, `Timestamp`, `TopicArn`, `Type`, `Signature`,
   `SignatureVersion`, `SigningCertURL`; у SubscriptionConfirmation/UnsubscribeConfirmation ещё
   `SubscribeURL` и `Token`; `Subject` необязателен и подписывается только у Notification.
3. В образе (ruby 3.3.14, OpenSSL 3.0.22) RSA-SHA1 и RSA-SHA256 `PKey#verify` работают.
   `SafeDownload.fetch` уже принимает `deadline:` (по умолчанию 30 с) и возвращает `nil` на любой
   сбой сети/DNS/TLS/таймаут/не-2xx/редирект при `max_redirects: 0`/превышение `max_bytes`;
   различить эти причины снаружи нельзя, а `safe_download.rb` правит m11 — поэтому `nil` от `fetch`
   трактуется как временный сбой (503, SNS повторит доставку: на 4xx SNS не ретраит).
4. Черновик (разделы 5.A–5.C) с примерными тестами: пробник `m10_probe_spec.rb` 26/26, мутационный
   гейт 17/17 убиты, пробник целостности и «красный на BASE» (по каждому примеру) зелёные,
   rubocop — ноль нарушений. На BASE пробник красный: 26 из 26 (раздел 7). Пробник — ноль
   нарушений rubocop.
5. Существующий `spec/controllers/api/v1/hooks_controller_spec.rb`: блок m7 «SNS subscription
   confirmation» (строки 13–51 на BASE, 2 примера) шлёт неподписанные тела и ждёт `ok` — это
   ровно отменяемый вехой контракт; остальные 19 примеров шлют фикстуры с настоящими подписями AWS
   2020 года, сертификат которых офлайн не достать. В черновике блок удалён, а в начало
   `describe` добавлено `allow(MessageApis::SnsMessageVerifier).to receive(:verify!).and_return(true)`
   — все 19 зелёные.

Предположения (не проверены): что живой SNS не присылает пустых строк в подписываемых полях (SDK
пропускает пустые, документация AWS — только отсутствующий `Subject`; веха пропускает только
отсутствующие, `nil`); что сертификаты SNS не меняют URL, сохраняя содержимое (кеш по URL; срок
`not_after` проверяется при каждой проверке подписи). **Цепочку доверия сертификата веха НЕ
проверяет (решение координатора):** PEM по `SigningCertURL` обычно содержит только лист, а
промежуточного «Amazon RSA 2048 M0x» нет в системных хранилищах — проверка отвергла бы все
настоящие сообщения, а проверить это без живого сертификата нельзя (известные URL из документации
отдают 404 — сертификаты ротированы). Как в документации AWS и `Aws::SNS::MessageVerifier`, доверие
даёт загрузка только по https с хоста `sns.<регион>.amazonaws.com(.cn)` с проверкой TLS-пира:
`SafeDownload.request` ставит `use_ssl` и не трогает `verify_mode` — у Net::HTTP по умолчанию
`VERIFY_PEER` с проверкой имени хоста (AC-004 проверяет, что `VERIFY_NONE`/`verify_mode =` нигде нет).

Флейк `spec/mailers/campaign_spec.rb:47` (Faker-имя с апострофом) на BASE_SHA исправлен (`352f8c09`);
любой провал AC-001 теперь — настоящий.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. `app/services/message_apis/sns_message_verifier.rb`** — `MessageApis::SnsMessageVerifier`
(вложенно: `module MessageApis` / `class SnsMessageVerifier` с комментарием-документацией — новый
файл не в `.rubocop_todo.yml`, поэтому компактный `class MessageApis::…`, класс длиннее 100 строк,
методы длиннее 10 строк и т. п. ломают AC-006; допустимы однострочные `def self.x(...) = …`).
**Путь попадает под `.gitignore` (`app/services/message_apis/**/*`): коммитить `git add -f`;
незакоммиченный файл проваливает AC-004.** Внутри:
`class VerificationError < StandardError` (неверное сообщение → 403) и `class CertificateUnavailable <
StandardError` (временный сбой загрузки сертификата → 503; НЕ подкласс `VerificationError`). Все
методы — методы класса, объявленные буквально как `def self.<имя>` (мутанты AC-003 перекрывают их по
имени; `private_class_method` для служебных разрешён).

| Метод | Контракт |
|---|---|
| `verify!(message)` | `message` — Hash из JSON-тела. `true` или исключение. Порядок — **все дешёвые проверки до любого сетевого вызова**: Hash → `Type` из трёх → `validate_fields!` → `digest_for` → `decode_signature` → `topic_allowed?` → `certificate_url?` → `signing_certificate` → `certificate_current?` → `PKey#verify(digest, подпись, canonical_string)`. Ошибка OpenSSL → `VerificationError` |
| `clear_cache!` | очищает кеш сертификатов и флаг «предупреждение уже было» (для тестов) |
| `validate_fields!(message)` | обязательные поля из п. 4.2 (по `Type`) — непустые строки, иначе `VerificationError` до любой криптографии и сети; каждое подписываемое поле, если есть, — строка; `\r`/`\n` запрещены во всех подписываемых полях, кроме `Message` |
| `digest_for(version)` | `"1"` → `"SHA1"`, `"2"` → `"SHA256"`, иначе `nil` (→ `VerificationError`) |
| `decode_signature(value)` | `Base64.strict_decode64`; ошибка → `VerificationError`; длина подписи вне 128..1024 байт → `VerificationError` |
| `topic_allowed?(arn)` | `ENV["SNS_ALLOWED_TOPIC_ARNS"]` — список через запятую (пробелы вокруг обрезаются, пустые элементы отбрасываются). Задан → только точное совпадение `TopicArn`, иначе `VerificationError`. Не задан/пуст → `true` и один раз на процесс `Rails.logger.warn` с именем переменной |
| `certificate_url?(url)` | `URI::HTTPS`, порт 443, без userinfo, query и fragment, хост целиком `\Asns\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z` (без учёта регистра), путь оканчивается на `.pem`; иначе `VerificationError` до сети |
| `canonical_string(message)` | строка подписи по списку полей типа из п. 4.2 (`Subject` — только у Notification), поля с `nil` пропускаются |
| `signing_certificate(url)` | сертификат из кеша процесса или `download_certificate`; кешируются только успешные; кеш потокобезопасный (Mutex), не больше 32 записей (старейшая вытесняется) |
| `download_certificate(url)` | только `MessageApis::SafeDownload.fetch(url, max_bytes: 64 * 1024, max_redirects: 0, deadline: 5)` (значения — литералом или константой класса); `nil` → `CertificateUnavailable`; первый блок `BEGIN CERTIFICATE` из тела → `X509::Certificate`; нет блока или ошибка разбора → `VerificationError`; цепочка доверия не проверяется (п. 4, доверие — TLS к хосту sns.*) |
| `certificate_current?(cert)` | `not_before <= Time.now <= not_after`; ложно → `VerificationError` (проверяется при КАЖДОЙ проверке, в том числе для сертификата из кеша) |

Служебные `def self.` сверх таблицы разрешены (например, `precheck!`, `reject!`); методы таблицы
перекрываются мутантами, поэтому их логика не должна дублироваться в обход них. Другие HTTP-клиенты
(Net::HTTP, Faraday, http-гем, open-uri) в верификаторе запрещены.
Ровно 64 КиБ (65 536 байт) сертификата проходят, 65 537 — нет (лимит SafeDownload; `nil` → 503).

**B. `app/controllers/api/v1/hooks_controller.rb`.**
1. Первый `before_action` — `:verify_sns_message`: тело `JSON.parse(request.body.read)` в
   `@request_body`; не JSON или не объект → `400`, текст `bad request`; затем
   `MessageApis::SnsMessageVerifier.verify!(@request_body)`; `VerificationError` → `403`, текст
   `invalid SNS message signature`; `CertificateUnavailable` → `503` (`:service_unavailable`), текст
   `SNS signing certificate unavailable` (SNS повторит доставку). Ни одного действия (запроса,
   джоба, записи в БД) до проверки.
2. Решения — только по подписанному `@request_body["Type"]`, заголовок `x-amz-sns-message-type`
   не учитывается: `SubscriptionConfirmation` → `send_subscription_confirmation` (проверка хоста
   `SubscribeURL` из m7 остаётся) и `ok`; `UnsubscribeConfirmation` → `ok` без действий;
   `Notification` → `handle_notification` как сейчас (`is_notification_message?` = `Type ==
   "Notification"`). Ветку `notificationType == "AmazonSnsSubscriptionSucceeded"` убрать.
3. Имена `verify_sns_message`, `check_aws_confirmation`, `is_notification_message?`,
   `send_subscription_confirmation`, `handle_notification`, `process_email_notification`,
   `read_mail_file`, `find_resources_in_recipient_parts`, `find_remitent`, `serialize_content`
   остаются (их используют существующие спеки и мутанты). `SnsReceiverJob` не меняется.

**C. Тесты.** HTTP — webmock, включённый локально (`include WebMock::API`, `WebMock.enable!`/
`disable!` в `around`), DNS — `allow(MessageApis::SafeDownload).to receive(:resolve)`; ключи и
сертификаты — генерируются в тесте (`OpenSSL::PKey::RSA.new(2048)`, X.509);
`SNS_ALLOWED_TOPIC_ARNS` — настоящим `ENV[...] =` с удалением в `before`/`after` (не заглушкой
`ENV.[]`: реализация вправе читать `ENV.fetch`); сети нет.
Новые файлы не должны падать при загрузке на BASE (не ссылаться на `MessageApis::SnsMessageVerifier`
вне примеров/хуков: `RSpec.describe "MessageApis::SnsMessageVerifier"` строкой). Слова-маркеры в
описаниях примеров обязательны — по ним мутационный гейт ищет упавший пример:
1. Новый `spec/services/message_apis/sns_message_verifier_spec.rb` (настоящий верификатор, без
   заглушек его методов): `Subject` входит в подпись (`Subject`); перевод строки в поле кроме
   `Message` отвергается (`newline`); `SignatureVersion` 1 = SHA1, 2 = SHA256, 3 и несовпадение
   digest — отказ (`SignatureVersion`); чужие `SigningCertURL` — отказ без запроса (`SigningCertURL`);
   редирект сертификата не исполняется (`redirect`); ровно 64 КиБ проходит, на байт больше — нет
   (`64 KiB`); дедлайн загрузки не больше 5 с — проверять по фактическому `Timeout.timeout` внутри
   SafeDownload (`allow(Timeout).to receive(:timeout).and_call_original`, затем
   `have_received(:timeout).with(be <= 5)` и `not_to have_received(:timeout).with(be > 5)`) (`5 seconds`);
   один URL качается один раз (`cache`); временный сбой (500) → `CertificateUnavailable`, не
   кешируется, следующая попытка проходит (`temporary`); allowlist `SNS_ALLOWED_TOPIC_ARNS` в обоих
   режимах (`TopicArn`); битый Base64 — отказ без запроса (`Base64`); нет обязательного поля
   (`Token` у Confirmation, `MessageId` у Notification) — отказ без запроса (`required`); сертификат
   из кеша после `not_after` (через `travel_to`) отвергается (`not_after`).
2. Новый `spec/controllers/api/v1/hooks_sns_signature_spec.rb` (контроллер с настоящим
   верификатором): неподписанное подтверждение — 403 и нет запроса к `SubscribeURL`
   (`unsigned`); подделанный `Message` — 403 и нет джоба (`tampered`); подписанный Notification с
   заголовком `SubscriptionConfirmation` не подтверждает подписку (`header`); временный сбой
   сертификата — `503`, и следующая попытка — 200 (`503`); подписанные SubscriptionConfirmation,
   Notification, UnsubscribeConfirmation — 200 и ожидаемое действие.
3. `spec/controllers/api/v1/hooks_controller_spec.rb`: блок m7 «SNS subscription confirmation»
   (строки 13–51 на BASE) можно удалить или переписать на подписанные сообщения; в остальном файле
   — только ДОБАВЛЕНИЕ строк; заглушка `allow(MessageApis::SnsMessageVerifier).to receive(:verify!)`
   разрешена только в этом файле.
4. **Красные на BASE — по каждому примеру** (AC-008): каждый новый пример файлов пп. 1–2 падает на
   BASE (как пример, не ошибкой загрузки файла); пример, который законно зелёный на BASE, обязан
   содержать в описании `base-green` и на BASE проходить.

Новые и изменённые Ruby-файлы — ноль нарушений rubocop проекта (`.rubocop.yml` +
`.rubocop_todo.yml`, CI падает на любом; AC-006); правки `.rubocop*.yml` запрещены.

Мутанты AC-003 (дописываются в конец файла, перекрывая метод): SV1 — `verify_sns_message` без
проверки; HT1 — `check_aws_confirmation` по заголовку; TU1 — временный сбой отдаётся как
`VerificationError` (403); CS1 — `canonical_string` без `Subject`; NL1 — `validate_fields!` без запрета
переводов строк; RQ1 — `validate_fields!` без обязательных полей; DG1 — `digest_for` всегда SHA256 и
для «3»; B64 — `decode_signature` нестрогим `Base64.decode64` без длины; TA1 — `topic_allowed?` всегда
`true`; CU1 — `certificate_url?` = хост оканчивается на amazonaws.com; RD1 — три редиректа; SZ1 —
`max_bytes: 70 * 1024`; TO1 — `deadline: 30`; CA1 — без кеша; CA2 — кеширует неудачу; EX1 —
`certificate_current?` всегда `true`.

## 6. Не трогать

- Всё вне списка AC-007. В частности: `Gemfile`, `Gemfile.lock` (никакого `aws-sdk-sns`),
  `package.json`, `yarn.lock`, `config/**`, `bin/**`, `db/**`, `lib/**`, `app/models/**`,
  `app/jobs/**` (`SnsReceiverJob` как есть), `.rubocop*.yml`, `app/services/message_apis/safe_download.rb` и
  `block_manager.rb` (их правят m11 и m9), плагины `app/services/message_apis/*/`, `CHANGELOG.md`.
- Всё, что принесли m1–m8, не откатывать: версии гемов и Rails, `load_defaults 8.1`, Rack::Attack,
  Devise, SES, SafeDownload и его фильтры, все вложения в провайдерах, проверка хоста SubscribeURL.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — кроме блока из 5.C.3. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec`, глобальный `require "webmock/rspec"` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-007, sha256).
- Запрещено брать что-либо из форков (VooDooNoir/chaskiq, kreasialamteknologi/chaskiq и др.),
  `.vscode/`, `.env*` (кроме `.env.example`), невидимые Unicode-символы, git- и path-источники
  в Gemfile, новые гемы.
- Вне вехи: подпись вебхуков других провайдеров, `SnsReceiverJob`, правка `safe_download.rb` (m11).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 529 примеров, выполнены все примеры BASE (кроме двух примеров блока m7), pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m10-probes/rspec_gate_m10.sh`

- **AC-002** — каждое SNS-сообщение проверяется до действия: подписанные v1 и v2 принимаются; без обязательных полей, с битым Base64, чужим TopicArn (при allowlist) или чужим SigningCertURL — 403 без сетевого запроса; поддельные, с просроченным сертификатом (и из кеша), переводом строки, неизвестной версией — 403; временный сбой, редирект и сертификат больше 64 КиБ — 503; решение по подписанному Type, кеш, дедлайн 5 с.
  `bash docs/specs/fork-updates-m10-probes/rspec_gate_m10.sh --only docs/specs/fork-updates-m10-probes/m10_probe_spec.rb`

- **AC-003** — новые тесты убивают все 17 мутантов: проверка в контроллере, решение по заголовку, 503, строка подписи, переводы строк, обязательные поля, версия, Base64, TopicArn, хост сертификата, редирект, размер 70 КиБ, дедлайн, кеш, срок сертификата.
  `python3 -I docs/specs/fork-updates-m10-probes/m10_mutation_gate.py`

- **AC-004** — целостность: зависимости, конфиги и джобы не тронуты, спеки только дополнены (кроме блока m7), верификатор качает только через SafeDownload с max_redirects 0, max_bytes ровно 64 КиБ и deadline ≤ 5 (по значению), есть CertificateUnavailable/SNS_ALLOWED_TOPIC_ARNS, проверка TLS-пира не выключена (нет VERIFY_NONE/verify_mode в SafeDownload, верификаторе и коде app/lib/config), контроллер проверяет первым и отвечает 503, инварианты m1–m7 на месте.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m10-probes/m10_integrity_probe.py $B'`

- **AC-005** — нет регрессий m1–m8: загрузка четырёх сред (m8), пробники рантайма m1–m5, загрузка m2–m4, redis из compose, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m10-probes/m10_regress.sh $B'`

- **AC-006** — изменённые и новые Ruby-файлы вне docs — ноль нарушений rubocop проекта (CI падает на любом нарушении).
  `bash -c 'B=$(git merge-base HEAD @{u}); F=$(git diff --name-only --diff-filter=AM $B...HEAD -- "*.rb" ":(exclude)docs/**"); test -z "$F" || docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m6/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bundle exec rubocop --force-exclusion $F'`

- **AC-007** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "f4412e3f84e3684a9d9364649333476456257a871b57ab105bfaa7e702ee165e  docs/specs/fork-updates-m10-probes/examples_base.txt" "cb91a041923f2537500e108164d903d134fd96f29c7523e18dfc4f5079e5313d  docs/specs/fork-updates-m10-probes/m10_integrity_probe.py" "adca3c4c3d4b44e1deb0f21492f2023ea82e0c81f77b7307e088726958e7bfbb  docs/specs/fork-updates-m10-probes/m10_mutation_gate.py" "76f42b1e1a30f6a623a83b9e3c6867fedf7a0df6319f507f587321247653eef7  docs/specs/fork-updates-m10-probes/m10_probe_spec.rb" "6d5c9d87b5a5d7d63385830ec6e4c4d7ab7c9448b221f845953f68e434053b87  docs/specs/fork-updates-m10-probes/m10_red_on_base.sh" "e16408144cfd8d8355741ff41aa8b107ec9acd77da8351127c9f75f36f97156c  docs/specs/fork-updates-m10-probes/m10_regress.sh" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m10-probes/pending_allowed.txt" "f68d5c73170b66b0ad848729cafef46ec6397d18ff27366705af34f5823bd8f9  docs/specs/fork-updates-m10-probes/rspec_gate_m10.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/sns_message_verifier[.]rb|app/controllers/api/v1/hooks_controller[.]rb|spec/services/message_apis/sns_message_verifier_spec[.]rb|spec/controllers/api/v1/hooks_sns_signature_spec[.]rb|spec/controllers/api/v1/hooks_controller_spec[.]rb")"'`

- **AC-008** — новые тесты верификатора и контроллера красные на BASE по каждому примеру: файлы грузятся, каждый новый пример падает (кроме помеченных base-green, которые проходят), примеры BASE не падают, по каждому маркеру 5.C есть красный пример.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m10-probes/m10_red_on_base.sh $B'`

- **AC-009** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-005, AC-006, AC-007, AC-009
зелёные; AC-002 красный (26 из 26: хук `before` пробника вызывает
`MessageApis::SnsMessageVerifier.clear_cache!`, которого на BASE нет);
AC-003 красный (`sns_message_verifier.rb does not define ...` — гейт останавливается до прогонов);
AC-004 красный (нет верификатора, первый before_action не `verify_sns_message`, ветка
`AmazonSnsSubscriptionSucceeded`); AC-008 красный (`… is not committed at HEAD`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки из шапки, не плавающий `B`: по нему `accept_run.py` ищет квитанции); один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m10.md --exclude "docs/specs/fork-updates-m10-probes/**" --context "chaskiq fork-updates-m10: проверка подписи SNS (SignatureVersion 1/2) в MessageApis::SnsMessageVerifier до любых действий HooksController; дешёвые проверки (поля по типу, Base64, TopicArn allowlist SNS_ALLOWED_TOPIC_ARNS, URL) до сети; сертификат только https sns.<регион>.amazonaws.com(.cn)/*.pem через SafeDownload без редиректов, 64 КиБ, 5 с, TLS verify_peer, кеш, срок сертификата (цепочку не проверяем — как SDK); временный сбой 503, неверное 403; решения по подписанному Type; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m10.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m10-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; обходы `certificate_url?` (регистр, userinfo,
порт, `sns.x.amazonaws.com.evil`, query, путь без `.pem`); можно ли подсунуть подпись одного типа
под другой (поля Notification против Confirmation); склейка полей через перевод строки; действует
ли контроллер хоть в одном пути до `verify!`; заглушки верификатора вне `hooks_controller_spec.rb`;
есть ли сетевой запрос до дешёвых проверок; не превращается ли временный сбой в 403 (SNS не
повторит) или неверное сообщение в 503; доверяет ли кеш сертификату после `not_after`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-001 — итоговые числа
examples/failures/pending; в `note` AC-003 — строка `killed`/`SURVIVED` по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m10.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m10.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-007 (модели, джобы, `config/**`, Gemfile, SafeDownload,
  другие плагины) или изменения существующей строки теста вне блока 5.C.3;
- нужен новый гем (включая `aws-sdk-sns`), или зелёный rspec недостижим без отката m1–m8;
- мутант набора AC-003 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш гемов или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, заглушать верификатор вне
`hooks_controller_spec.rb`, менять пробники, подменять окружение и глушить коды возврата.

## 10. Стыки

- **fork-updates-m11** (Telnyx MMS) правит `safe_download.rb` (keywords `headers:`,
  `allow_own_host:`, контракт `fetch` для остальных не меняется) и `telnyx_sms/`; m10 их не трогает и
  только вызывает `SafeDownload.fetch(url, max_bytes:, max_redirects: 0, deadline: 5)`. m10 убирает
  из `hooks_controller_spec.rb` два примера m7, поэтому если m11 запускается после m10, постановщик
  перед запуском m11 перегенерирует её `examples_base.txt` (`rspec_gate_m11.sh --write-base`).
- **fork-updates-m9** (вложения, id частей) правит `block_manager.rb`, `base_package.rb` и плагины
  Vonage/Dialog360 — путей m10 не касается. После влития m10 пробник `m7_probe_spec.rb` в части
  неподписанного `SubscribeURL` (4 примера) красный, поэтому его нет в `m10_regress.sh` и
  `m11_regress.sh`. **`m9_regress.sh` его запускает**: если m10 вольют раньше m9, постановщик до
  перезапуска m9 убирает m7-пробник из регресса m9 (или переносит BASE m9 на коммит до m10).
- После приёмки координатор вливает ветку в main и дописывает CHANGELOG, **с рекомендацией**:
  задать `SNS_ALLOWED_TOPIC_ARNS` (через запятую, точные ARN топиков SES/SNS этой инсталляции);
  без неё сообщения принимаются от любого топика, а в лог один раз на процесс пишется
  предупреждение; **рекомендация оператору** после выкладки — убедиться по логу, что настоящее
подтверждение подписки SNS прошло `verify!` (стенд этого не проверяет). Новые коды ответа `/api/v1/hooks`: 403 — неверное сообщение, 503 — временно
  недоступен сертификат (SNS повторит).
- Остаётся вне вехи: проверка ed25519-подписи вебхуков Telnyx.
