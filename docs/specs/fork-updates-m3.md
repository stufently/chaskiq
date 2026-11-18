# fork-updates-m3 — дефекты приёмки m2: Rack::Attack, SES staging, плагины, ассеты

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `fork-updates-m2`.
  Дата спеки: 2026-11-18.
- BASE_SHA: `2835be9b17f811cbabdb4ee52fb646fd7b5b6558` «Adapt upstream plugins to the current
  runtime» — HEAD ветки `fork-updates-m2` (итог вехи fork-updates-m2). Клон снимается с
  СЛЕДУЮЩЕГО коммита — коммита этой спеки и каталога `docs/specs/fork-updates-m3-probes/`;
  других коммитов между BASE_SHA и HEAD клона нет.
- Исполнитель: Codex (`cx`), назначен владельцем. Мутации по новым тестам потом гоняет
  противоположный исполнитель (Qwen, панель `qw2`). Исправления внутри вехи — тому же Codex.
- Цель: починить дефекты, найденные на приёмке m2 (стенд, ревью, мутации), после чего
  координатор сам вливает ветку в main.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m3`.
  Живое дерево `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root. На хост ничего
  не ставить (никаких gem/bundle/npm/yarn/pip/apt на хосте).

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (из `docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.5 + libpq + node + curl |
| гемы | `$HOME/.cache/chaskiq-m1/bundle` (BUNDLE_PATH, общий кэш) | гейт, пробники |
| кэш yarn | `$HOME/.cache/chaskiq-m1/yarn` | `yarn install` в Docker |
| `node_modules/` | в клоне (gitignored), копия из пробного клона (тот же `yarn.lock`) | ts-node в спеках, сборка фронта |
| образы | `postgres:14-alpine`, `redis:5-alpine`, `node:16.20.2-bullseye-slim` | гейт, стенд |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m3-probes
bash $P/rspec_gate_m3.sh                                   # полный строгий rspec, ~5 мин
bash $P/rspec_gate_m3.sh --only spec/requests/rack_attack_spec.rb   # один файл
python3 -I $P/m3_mutation_gate.py RA6 PL1                  # часть мутантов (полный набор ~15 мин)
```

## 3. Задача и почему

Приёмка m2 нашла дефекты (каждый подтверждён командой, раздел 4):

1. Rack::Attack считает только пути `/oauth/token` и `/oauth/token.json`; маршрут doorkeeper —
   `/oauth/token(.:format)`, поэтому `POST /oauth/token.xml` (любой суффикс формата) обходит лимит
   подбора паролей.
2. Rack::Attack берёт grant_type из `req.params` (Rack: тело перекрывает query), а Rails —
   `request_parameters.merge(query_parameters)` (query перекрывает тело). `?grant_type=password`
   плюс тело `grant_type=refresh_token` — Rails видит password, троттлинг видит refresh и не считает.
3. Счётчики Rack::Attack в production живут в `Rails.cache` — файловом кэше реплики; при
   нескольких репликах лимит умножается на их число.
4. `config/environments/staging.rb` всё ещё вызывает `Aws::Rails.add_action_mailer_delivery_method`
   (нет в aws-sdk-rails 5) — staging не загружается в ветке SES.
5. Исходящие сообщения telegram, message_bird, telnyx_sms, vonage разбирают `serialized_content`
   старым форматом (`JSON.parse(...)["blocks"]`) и падают на nil; slack `blocks_transform` молча
   возвращает `[]`.
6. telnyx_sms вызывает `@conn.authorization` — метода нет в faraday 2.15.1.
7. Выжившие мутанты m2: PL1 (ключ и токен basic auth twilio переставлены), PL2 (`chat:write` в
   slack user_scope), RA6 (период троттлинга проверял только пробник), RA2 (битый JSON не
   тестировался); DV3, DV4, SE4 в m2 rspec'ом не прогонялись.
8. propshaft 1.3 копирует весь `node_modules` в `public/assets` (на BASE: 848 МБ, 78483 файла).

Что сломается и чинится в этой же вехе: переписанный выбор grant_type не должен начать считать
refresh_token (фронт обновляет токен через `/oauth/token`); новое хранилище не должно падать без
redis; фронт после сужения путей ассетов обязан отдаваться (стенд AC-006).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-18 в Docker на клоне от BASE_SHA и на пробном клоне с черновыми правками
(черновик — только для проверки достижимости критериев, в веху не идёт):

1. Гейт rspec на BASE: `433 examples, 0 failures, 30 pending`; pending совпадают с
   `fork-updates-m2-probes/pending_allowed.txt` (скопирован в `pending_allowed.txt` этого каталога),
   список примеров — `examples_base.txt`.
2. Маршрутизация (`Rails.application.routes.recognize_path(p, method: :post)`, production):
   `/oauth/token`, `.json`, `.xml`, `.html`, `.foo`, `/oauth/token/`, `//oauth/token`,
   `/oauth//token`, `/oauth/token.json/` → `agents/tokens#create`; `/OAUTH/TOKEN`, `/oauth/Token`,
   `/oauth/%74oken`, `/oauth/token%2Ejson`, `/oauth/token;x` → RoutingError. Контроллер
   `Agents::TokensController < Doorkeeper::TokensController` (config/routes.rb `use_doorkeeper`,
   `controllers tokens: 'agents/tokens'`), doorkeeper 5.6.9 берёт `params[:grant_type]`
   (`tokens_controller.rb:130`).
3. Приоритет параметров: actionpack 7.2.1.1 `parameters` = `request_parameters.merge(query_parameters)`
   (query побеждает); rack 2.2.25 `Request#params` = `GET.merge(POST)` (тело побеждает).
4. Дефекты 1 и 2 воспроизведены: `m3_attack_probe_spec.rb` на BASE — 14 примеров, 5 падений
   (`.xml`, `.html`, `.anything`, query password + тело refresh_token, общий счётчик на IP по всем
   вариантам пути). Живой стенд на BASE:
   `POST /oauth/token?grant_type=password` с телом `grant_type=refresh_token` — 21-й запрос 401, а не
   429. Варианты `/oauth/token/`, `//oauth/token`, `/oauth/token.json/` на BASE уже считаются (и в
   request spec, и на стенде) — они в пробниках как защита от регрессии.
5. Дефект 3: production-загрузка офлайн → `RA_STORE=ActiveSupport::Cache::FileStore`. В staging
   `config.cache_store = :redis_cache_store, { url: Chaskiq::Config.get('REDIS_URL') }`
   (staging.rb:67). `Chaskiq::Config.get(name)` = credentials или `ENV[name.upcase]`
   (config/application.rb:18). Test env: `config.cache_store = :null_store`, существующие спеки
   подменяют `Rack::Attack.cache.store` на MemoryStore в `around`. Черновик (RedisCacheStore по
   REDIS_URL в production/staging, иначе `Rails.logger.warn`) прошёл `m3_boot_probe.sh`.
6. Дефект 4: staging-загрузка офлайн → `staging.rb:126 undefined method
   'add_action_mailer_delivery_method' for module Aws::Rails (NoMethodError)`; с
   `SMTP_DELIVERY_METHOD=smtp` грузится. Production и development уже на
   `config.action_mailer.ses_settings = { credentials: creds, region: zone }` (production.rb:129,
   development.rb:120), гем aws-actionmailer-ses 1.2.0 в lock.
7. Дефект 5: `telegram/api.rb:94`, `message_bird/api.rb:121`, `telnyx_sms/api.rb:107`,
   `vonage/api.rb:104` — `JSON.parse(message["serialized_content"])["blocks"]`; `slack/api.rb:946`
   `blocks_transform` с `rescue StandardError; []`. Новый формат — документ Dante
   (`{"type":"doc","content":[...]}`); `MessageApis::BlockManager.get_blocks` → `content`,
   `plain_text` → `Dante::Utils.extract_plain_text`, `block_data(block)` → `block["attrs"]`;
   типы медиа-блоков — `ImageBlock`, `FileBlock`, `VideoBlock`, `AudioRecorderBlock`
   (`app/services/dante/renderer.rb`). Образец перевода — twilio, dialog360 в коммите 2835be9b.
8. Дефект 6: поиск по `app/` и `lib/` (`basic_auth`, `.authorization`, `token_auth`,
   `:basic_auth`, `UploadIO`, `:multipart`) — единственный живой вызов `telnyx_sms/api.rb:80`
   `@conn.authorization :Bearer, @api_key`; остальное — комментарии (`dialog360/api.rb:238,243`,
   `data_enrichment_service/base.rb:6,10`). Telnyx API v2: `Authorization: Bearer <API key>`
   (developers.telnyx.com, «API authentication»). `authorize!` зовётся на каждую отправку
   (`send_sms_message`), а middleware в собранный и уже использованный стек faraday 2 добавлять
   нельзя — авторизацию ставить один раз.
9. webmock 3.19.1 есть в Gemfile (группа test) и грузится `Bundler.require`, но НЕ включён:
   `require "webmock"` без `webmock/rspec` реальную сеть не перехватывает (проверено), а
   `spec/rails_helper.rb:39` держит `# require 'webmock/rspec'` закомментированным.
10. Мутации: `m3_mutation_gate.py` на BASE — все 9 целей зелёные на чистом дереве; DV3 и DV4
    УЖЕ убиты существующим `spec/models/agent_notifications_spec.rb` («enqueues password_change and
    email_changed…»), SE4 убит загрузкой development в `m3_boot_probe.sh --dev-only` (development.rb
    rspec не грузит — это и есть его тест); выжили PL1, PL2, RA6, TG1, MB1, TX1, TX2, VO1, SL1 и TXT
    на всех пяти файлах — тестов исходящей отправки нет. Попутно: существующий пример
    `message_bird_spec.rb` «receive conversation media» ходит в реальную сеть
    (`whatsapp-sandbox.messagebird.com`) — не трогать, это вне вехи. Механика гейта проверена на
    черновике: добавленный пример «one hour» убивает RA6 на своей строке (`expected 429, got 401`).
11. Ассеты: `config/initializers/assets.rb:6` `Rails.application.config.assets.paths <<
    Rails.root.join('node_modules')`. `rails assets:precompile` (production, после `yarn build`) на
    BASE: `public/assets` 848 МБ, 78483 файла, 1198 записей верхнего уровня. Та же сборка без этой
    строки: 14 МБ, 92 файла; в манифесте есть application.js/.css, tailwind.css, inter-font.css
    (из гема tailwindcss-rails), embed.js, article.js, logo.png, favicon.png; ссылок `/assets/...` на
    файлы из node_modules в `app/assets/builds/*` и шаблонах нет (esbuild кладёт свои картинки в
    builds). Стенд на черновике: главная `/` 200, все её css/js 200. Порог AC-006 — 64 МБ и 500
    файлов (запас ×4 над замером, на порядок ниже BASE).
12. devise 5 и secret_key (пункт 9 владельца) — правок НЕ требует. CHANGELOG 5.0.0.rc: убран
    `SecretKeyFinder`, теперь `Devise.secret_key ||= app.secret_key_base`; раньше порядок был
    credentials → secrets → config.secret_key_base → app.secret_key_base. Здесь
    `config/credentials/` содержит только README (нет `credentials.yml.enc`), `config.secret_key`
    в devise.rb закомментирован, `Rails.application.respond_to?(:secrets)` в 7.2 → false.
    Проверено загрузкой production: старый порядок выбирает `config.secret_key_base`, он равен
    новому `Devise.secret_key` и равен `ENV["SECRET_KEY_BASE"]`. `Devise::TokenGenerator` в 4.9.3
    и 5.0.4 побайтно одинаков; devise_invitable 2.0.14 берёт тот же `Devise.token_generator`.
    Токены сброса пароля, разблокировки и приглашения, выданные до апгрейда, остаются валидными.
    Известное поведение: если оператор когда-либо добавит `credentials.yml.enc` с ДРУГИМ
    `secret_key_base`, чем в ENV, devise 4 взял бы credentials, а devise 5 берёт ENV (Rails 7.2
    читает ENV первым) — выданные токены станут невалидны.
13. Известное ограничение (вне вехи): ключ троттлинга — `req.ip` (Rack). Rack доверяет
    `X-Forwarded-For`, когда REMOTE_ADDR — приватный адрес; если приложение доступно не только
    через доверенный прокси, клиент подменяет XFF и получает новую корзину на каждый запрос (так
    стенд AC-006 и разводит клиентов). Рекомендация владельцу: держать puma доступной только с
    прокси и задать `config.action_dispatch.trusted_proxies` / ключ по `remote_ip` отдельной вехой.

Предположения (не проверены): что slack принимает section-блоки из текста абзацев без доп. полей;
что сторонние плагины вне пяти папок не используют faraday-1-API вне найденного поиском.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Rack::Attack** (`config/initializers/rack_attack.rb`).
1. Считать каждый POST, который Rails маршрутизирует на token endpoint: `/oauth/token` с любым
   суффиксом формата `.xxx`, хвостовыми и повторными слэшами (раздел 4 п.2). Например
   `%r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}` или `recognize_path`. `/oauth/revoke` и прочие — нет.
   Счётчик один на IP для всех вариантов пути и форматов тела (дискриминатор — только IP).
2. grant_type — как его увидит Rails: query (`req.GET`) перекрывает тело; тело — JSON (только
   Hash, `media_type` JSON) или форма (`req.POST`). Любая ошибка разбора — запрос считается, из
   middleware ничего не вылетает, `req.body` после чтения перематывается. Исключать из подсчёта
   только refresh_token в этом смысле.
3. В production и staging — отдельное хранилище:
   `Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: Chaskiq::Config.get("REDIS_URL"))`.
   REDIS_URL пуст — остаётся прежнее (сам `Rails.cache`, счётчик растёт) и `Rails.logger.warn` с текстом, где есть
   `Rack::Attack` и `REDIS_URL`. `Rails.cache`/`cache_store` не менять; test/development не трогать.
4. Литерал `Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour)` сохранить как есть.

**B. staging SES** (`config/environments/staging.rb`): вызов `Aws::Rails.add_action_mailer_delivery_method`
заменить на `config.action_mailer.ses_settings = { credentials: creds, region: zone }` — так же, как в
production.rb; `delivery_method = :ses`, ветку SMTP и источники creds/zone не менять.

**C. Исходящие сообщения плагинов** (`app/services/message_apis/{telegram,message_bird,telnyx_sms,vonage,slack}/`).
1. Разбор `serialized_content` — только `MessageApis::BlockManager.get_blocks`, текст — только
   `MessageApis::BlockManager.plain_text`, данные медиа — `MessageApis::BlockManager.block_data`,
   типы `ImageBlock`/`FileBlock`/`VideoBlock`/`AudioRecorderBlock` (как twilio/dialog360 в 2835be9b).
   Пустой или битый `serialized_content` — не исключение, а отказ от отправки, как сейчас.
2. slack `blocks_transform`: документ Dante → блоки slack; абзац и заголовок → `section` с `mrkdwn`
   из `BlockManager.plain_text` узла (пустые пропускать), `DividerBlock` → `divider`,
   `ImageBlock` → `image` (url из `block_data`, относительный — с префиксом HOST). Для
   корректного документа результат не пустой.
3. telnyx_sms: заголовок `Authorization: Bearer <api_key>` средствами faraday 2
   (`request :authorization, "Bearer", key` при сборке соединения или заголовок), ровно один раз
   на соединение; повторная отправка тем же экземпляром работает.
4. Пройти все плагины `app/services/message_apis/*/` на faraday-1-only вызовы. Найдено вне пяти
   папок — контракт на невыполнимое (раздел 9), не правка.

**D. Ассеты** (`config/initializers/assets.rb`): убрать `node_modules` из `config.assets.paths`
(или исключить его целиком через `config.assets.excluded_paths` — AC-007 бракует только
`node_modules` в `config.assets.paths`), остальное в файле не трогать.

**E. Тесты** (только ДОБАВЛЕНИЕ строк в существующие файлы; новые `*_spec.rb` — вне `spec/support/`).
1. `spec/requests/rack_attack_spec.rb`: суффиксы `.xml` и ещё один формат; конфликт query
   password + тело refresh_token (форма и JSON); битый JSON `{bad` с `Content-Type: application/json`
   — считается и `JSON::ParserError` из middleware не вылетает (убивает RA2, ошибку разбора самого
   Rails `ActionDispatch::Http::Parameters::ParseError` допускается ловить в тесте); пример с
   описанием, содержащим `one hour`: время выровнено на начало окна
   (`travel_to Time.zone.at((Time.now.to_i / 3600 + 1) * 3600 + 1)`), 20 запросов, через 3590 с —
   429, через 3610 с — не 429 (`include ActiveSupport::Testing::TimeHelpers`).
2. Исходящие сообщения — в существующих `spec/controllers/api/v1/hooks/{telegram,message_bird,telnyx_sms,vonage,slack,twilio}_spec.rb`:
   на каждый плагин минимум один пример, в описании которого есть слово `outgoing`; отправка
   агентским сообщением в формате Dante (текст `foobar`), HTTP — через webmock, включённый
   ЛОКАЛЬНО в этом describe (`include WebMock::API`, `around { WebMock.enable!; ...; WebMock.reset!;
   WebMock.disable! }`), без `require "webmock/rspec"` и глобальной конфигурации. Пример
   проверяет запрос к настоящему URL провайдера (как его строит плагин, включая sandbox-вариант)
   с текстом `foobar` в теле; telnyx — ещё `Authorization: Bearer <api_key>` и две отправки подряд
   одним экземпляром; twilio — `Authorization: Basic base64("<Account SID>:<Auth Token>")` (PL1);
   slack — тело `chat.postMessage` содержит section с `foobar`.
3. slack: пример с `user_scope` в описании — `oauth_authorize` даёт ровно
   `user_scope=channels:history,channels:write,channels:read` (PL2).
4. DV3, DV4, SE4 уже убиты (раздел 4 п.10) — новых тестов не нужно; гейт держит их от регрессии.

## 6. Не трогать

- Всё вне списка AC-009. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock` (никаких
  бампов гемов и npm), `config/environments/production.rb`, `development.rb`, `test.rb`,
  `config/initializers/devise.rb`, `app/` вне пяти папок плагинов, `MessageApis::BlockManager`,
  `Dante::Utils`, `lib/`, `db/`, workflows, `Dockerfile*`, `docker-compose.yml`, `config.ru`.
- Всё, что принесли m1 и m2, не откатывать: версии гемов, письма Devise, SMTP-умолчания, puma.rb,
  CI, восстановленные плагины, Slack #917, SES через aws-actionmailer-ses.
- Существующие спеки: удалять, переименовывать, skip-ать (`xit`, `skip`, `pending`, `:skip`),
  ослаблять или менять существующие строки запрещено — только добавлять. Новые файлы в
  `spec/support/`, правки `spec/rails_helper.rb`, `spec/spec_helper.rb`, `.rspec` и фильтрация
  примеров через конфигурацию RSpec запрещены.
- `docs/specs/fork-updates-m1*`, `docs/specs/fork-updates-m2*`, `docs/specs/fork-updates-m3.md`,
  `docs/specs/fork-updates-m3-probes/**` — закоммичены постановщиком; не править (AC-009, sha256).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq
  (вредоносный код: eval в `esbuild.config.mjs`, стилер через `.vscode/tasks.json`). Запрещены:
  `.vscode/`, self-hosted runner, `skip_client_authentication_for_password_grant`, `.env*` (кроме
  `.env.example`), чужой брендинг, `eval`/`new Function` в JS, невидимые Unicode-символы,
  git- и path-источники в Gemfile. Не ходить в `appstore.chaskiq.io`.
- Не апгрейдить Rails, redis в compose, не делать SMTP без логина, синхронное письмо
  разблокировки, SES через IAM-роль, ключ троттлинга по `remote_ip` (всё — вне вехи).

## 7. Критерии приёмки

Команды — из корня клона. BASE — `2835be9b17f811cbabdb4ee52fb646fd7b5b6558`.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме, пробник зависимостей m1 зелёный.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m1-probes/m1_deps_probe.rb"'`

- **AC-002** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 433 примеров, выполнены все 433 примера BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m3-probes/rspec_gate_m3.sh`

- **AC-003** — Rack::Attack считает пароли на всех вариантах token-пути и при конфликте query и тела, битый JSON считается без исключения, refresh_token не считается, окно один час.
  `bash docs/specs/fork-updates-m3-probes/rspec_gate_m3.sh --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb`

- **AC-004** — staging грузится в ветке SES и SMTP, development в ветке SES с region из ENV, счётчики Rack::Attack в production общие через redis из REDIS_URL, без REDIS_URL загрузка с предупреждением.
  `bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh`

- **AC-005** — новые тесты убивают мутанты PL1 PL2 RA6 DV3 DV4 SE4 и мутанты исходящей отправки пяти плагинов.
  `python3 -I docs/specs/fork-updates-m3-probes/m3_mutation_gate.py`

- **AC-006** — живой стенд: фронт собирается из lock, public/assets не больше 64 МБ и 500 файлов без пакетов node_modules, главная и её css и js отдаются 200, лимит 20 срабатывает на вариантах пути и при конфликте grant_type, счётчики в redis.
  `bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh`

- **AC-007** — целостность: зависимости не тронуты, спеки только дополнены, инварианты m1 и m2 на месте, старого разбора блоков и faraday-1-вызовов нет, node_modules не в путях ассетов.
  `python3 -I docs/specs/fork-updates-m3-probes/m3_integrity_probe.py 2835be9b17f811cbabdb4ee52fb646fd7b5b6558`

- **AC-008** — нет регрессий m1 и m2: пробники рантайма m1 и m2, загрузка production m2, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'P=docs/specs/fork-updates-m3-probes; bash $P/rspec_gate_m3.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $P/rspec_gate_m3.sh --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb" && python3 -I $P/m3_tree_probe.py 2835be9b17f811cbabdb4ee52fb646fd7b5b6558'`

- **AC-009** — вне разрешённых путей ничего не изменено, спеки и пробники постановщика не тронуты (sha256).
  `bash -c 'B=2835be9b17f811cbabdb4ee52fb646fd7b5b6558; test "$(git log --format=%H $B..HEAD -- docs/specs | wc -l)" = 1 && git diff --quiet $B HEAD -- docs/specs/fork-updates-m1.md docs/specs/fork-updates-m1-probes docs/specs/fork-updates-m2.md docs/specs/fork-updates-m2-probes && printf "%s\n" "feb790130ca4cdb283c13fc3dc994f11324c94541e8e5d082430d01b4fd5956b  docs/specs/fork-updates-m3-probes/examples_base.txt" "39acb1b64d74833595d658fa63d0185ea07053117a4db7d4d425aee5581cb808  docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb" "bd4fb4da6ae16241c5d1c1e46abd3efb2d208fdb58411dac8ccd7ef712d0cdd4  docs/specs/fork-updates-m3-probes/m3_boot_probe.sh" "eb26adc847f63384fca8d5ade0502d530559455869242afcda6ee083e7917fc9  docs/specs/fork-updates-m3-probes/m3_integrity_probe.py" "e847a03494d0208085401e421e368dbd55b0b34cee9ae62b2692b7e4a96de320  docs/specs/fork-updates-m3-probes/m3_mutation_gate.py" "22b32fd17edcfb3a581cd55abdd7b1674b9c9ee0de9ac2bb9005a3b3c6b3a2bb  docs/specs/fork-updates-m3-probes/m3_stand_probe.sh" "d82a9027bbc2083195cca8c91bbca7cf288a18a7baeabefa1992b05eee75bb8d  docs/specs/fork-updates-m3-probes/m3_tree_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m3-probes/pending_allowed.txt" "c998cb1d35b3c4c27623377b491fb7bf4abe0d1f7cb884f5617d63df1f814323  docs/specs/fork-updates-m3-probes/rspec_gate_m3.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "config/initializers/rack_attack[.]rb|config/initializers/assets[.]rb|config/environments/staging[.]rb|app/services/message_apis/(telegram|message_bird|telnyx_sms|vonage|slack)/.+|spec/.+|docs/specs/fork-updates-m3[.]md|docs/specs/fork-updates-m3-probes/.+")"'`

- **AC-010** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-002, AC-008, AC-009, AC-010
зелёные; AC-003 красный (5 падений: `.xml`, `.html`, `.anything`, конфликт grant_type, общий счётчик); AC-004
красный (staging.rb:126 NoMethodError); AC-005 красный (выжили PL1, PL2, RA6 и мутанты исходящей отправки, раздел 4 п.10); AC-006 красный
(848 МБ); AC-007 красный (staging add_action_mailer_delivery_method, `["blocks"]` в пяти плагинах,
`@conn.authorization`, node_modules в путях ассетов).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила, раздел «Автономное
перекрёстное ревью»). Коротко: коммит → REVIEW_SHA; исполнитель Codex → ревьюеры `agy` +
`qwen`, оба параллельно на `2835be9b17f811cbabdb4ee52fb646fd7b5b6558..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только
обёртка, путь абсолютный:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base 2835be9b17f811cbabdb4ee52fb646fd7b5b6558 --range 2835be9b17f811cbabdb4ee52fb646fd7b5b6558..<REVIEW_SHA> --exclude docs/specs/fork-updates-m3.md --exclude "docs/specs/fork-updates-m3-probes/**" --context "chaskiq fork-updates-m3: Rack::Attack (все варианты token-пути, grant_type как у Rails, redis-хранилище счётчиков), SES в staging, исходящие сообщения пяти плагинов на BlockManager, telnyx Bearer на faraday 2, node_modules вне путей ассетов, тесты на выживших мутантов; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m3.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m3-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; Rack::Attack не
выпускает исключений и не начал считать refresh_token; хранилище не падает без redis;
исходящие сообщения не теряют текст и медиа; нет сети в тестах кроме webmock-стабов.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-002 — итоговые числа
examples/failures/pending; в `note` AC-005 — строка `killed`/`SURVIVED` по каждому мутанту;
в `note` AC-006 — размер public/assets.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m3.md>",
  "base_sha": "2835be9b17f811cbabdb4ee52fb646fd7b5b6558",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m3.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-009 (в том числе faraday-1-вызов в другом плагине,
  правка `BlockManager`/`Dante::Utils`, production.rb, devise.rb) или изменения существующей
  строки теста;
- зелёный rspec недостижим без отката чего-то из m1/m2 или без бампа гема/npm;
- мутант набора AC-005 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах.

## 10. Стыки

После приёмки координатор вливает ветку в main. Следующим вехам остаются: ключ троттлинга за
прокси (раздел 4 п.13), redis 6+ в compose (sidekiq 7 требует HELLO), Rails 8, продовый
`Dockerfile` (`rails assets:precompile` теперь не тащит node_modules в образ).
