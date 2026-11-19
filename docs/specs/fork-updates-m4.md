# fork-updates-m4 — хвосты приёмки m3: старые блоки, абзацы, URL, Slack, SMTP, redis

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`.
  Дата спеки: 2026-11-19.
- BASE_SHA: `0b296f3466d81286d034a64604f552c515cf2618` «Add CHANGELOG for fork updates» — HEAD
  `main` после слияния вех fork-updates m1–m3. Клон снимается с СЛЕДУЮЩЕГО коммита — коммита этой
  спеки и каталога `docs/specs/fork-updates-m4-probes/`; других коммитов между BASE_SHA и HEAD
  клона нет.
- Исполнитель: Codex (`cx`), назначен координатором (m2 и m3 делал Codex, контекст тот же).
  Мутации по новым тестам потом гоняет противоположный исполнитель (Qwen, панель `qw2`).
  Исправления внутри вехи — тому же Codex.
- Цель: закрыть известные проблемы из CHANGELOG и приёмки m3, после чего координатор сам вливает
  ветку в main.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m4`.
  Живое дерево `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root (исключение —
  контейнеры redis/postgres/mailpit без bind mount, их пробники поднимают сами). На хост ничего
  не ставить (никаких gem/bundle/npm/yarn/pip/apt на хосте).

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (из `docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.5 + libpq + node + curl + jq |
| гемы | `$HOME/.cache/chaskiq-m1/bundle` (BUNDLE_PATH, общий кэш) | гейт, пробники |
| `node_modules/` | в клоне (gitignored), копия из клона m3 (тот же `yarn.lock`) | ts-node в спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine`, `axllent/mailpit:v1.34.0` | гейт, пробники |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m4-probes
bash $P/rspec_gate_m4.sh                                   # полный строгий rspec, ~5 мин
bash $P/rspec_gate_m4.sh --only $P/m4_blocks_probe_spec.rb # один файл
python3 -I $P/m4_mutation_gate.py LB1 SE1                  # часть мутантов (полный набор ~20 мин)
bash $P/m4_boot_probe.sh --smtp-only                       # только SMTP (или --ra-only)
```

## 3. Задача и почему

Известные проблемы (каждая подтверждена командой, раздел 4):

1. **Старый формат содержимого не пересылается.** Входящие плагины пишут `serialized_content` как
   `{"blocks": [...], "entityMap": {}}` (slack `process_blocks`/`attachment_block`, медиа telegram,
   vonage, message_bird, dialog360), в старых данных лежат блоки Draft.js
   (`key`/`text`/`type: "unstyled"`/`data`). `MessageApis::BlockManager.get_blocks` читает только
   `["content"]` и отдаёт `nil` — telegram, vonage, message_bird, telnyx_sms молча не отправляют,
   slack шлёт пустой список блоков. Пример: сообщение из Slack не уходит в Telegram.
2. **Абзацы склеиваются.** `BlockManager.plain_text` = `Dante::Utils.extract_plain_text`: два абзаца
   «заказ» и «123» дают `"заказ123"`; жирный фрагмент внутри абзаца даёт лишний пробел
   (`"foo"` + жирный `"bar"` → `"foo bar"`). Затрагивает все плагины на `plain_text`
   (twilio, dialog360, messenger, twitter и пять из m3).
3. **URL медиа с пробелом.** `URI.join(HOST, url)` в telegram, vonage, message_bird, slack падает
   `URI::InvalidURIError` на пробеле или не-ASCII в пути (имя загруженного файла).
4. **Slack mrkdwn не экранируется.** Текст `a <b> & c` уходит в section как есть; Slack трактует
   `<...>` как ссылку/упоминание, `&` — как начало сущности.
5. **SMTP без логина — 500.** `smtp_settings` всегда содержит `authentication: :login`; при пустом
   `SMTP_USERNAME` (открытый релей внутри сети) `deliver_now` падает `ArgumentError: SMTP-AUTH
   requested but missing user name` — запрос, отправляющий письмо синхронно, получает 500.
6. **redis 5 в compose.** `docker-compose.yml` держит `redis:5-alpine`; sidekiq 7.3 (redis-client
   0.31) требует Redis 6+ (`HELLO`) — в compose не работает ни один фоновый job.
7. **RA9.** Выживший мутант m3: в staging выбор отдельного redis-хранилища Rack::Attack не покрыт
   ничем. Закрывается пробником постановщика (AC-004), кода не требует.

Что сломается и чинится в этой же вехе: экранирование Slack меняет ожидание существующего теста
`slack_spec.rb` «sends HTML-only content as plain text» (`Hello & goodbye` → `Hello &amp; goodbye`)
— это единственная разрешённая правка существующей строки теста (раздел 6). Новый `plain_text`
не должен менять `Dante::Utils` — его зовут правила назначения (`ConversationPart#check_rules`) и
`ConversationPartContent#text_from_serialized`.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker на клоне от BASE_SHA и на черновом клоне (черновик — только для
проверки достижимости критериев, в веху не идёт):

1. Гейт rspec на BASE с `redis:8.10-alpine`: `457 examples, 0 failures, 30 pending`; pending
   совпадают с `pending_allowed.txt` (копия из m3), список примеров — `examples_base.txt`.
2. `Dante::Utils.extract_plain_text` (app/services/dante/utils.rb): text-узел дописывает
   `"#{text} "`, рекурсия делает `.strip` — проверено: два абзаца → `"заказ123"`,
   `"foo"`+жирный`"bar"` → `"foo bar"`. `Dante::Utils.get_blocks` = `JSON.parse(s)["content"]`.
   Вызывающие `extract_plain_text`: `BlockManager.plain_text`, `conversation_part.rb:214`,
   `conversation_part_content.rb:18`. `BlockManager.get_blocks` зовут dialog360, telegram,
   messenger, twilio, twitter, vonage, telnyx_sms, message_bird, slack.
3. Форматы: `MessageApis::Helpers#serialized_block` → `{type: "text", text:}`, `photo_block` →
   `{type: "ImageBlock", attrs: {url:,…}}`, `file_block` → `FileBlock`, `gif_block` — блок Draft.js
   (`key`, `type: "recorded-video"`, `data: {url:}`); slack `process_blocks` (slack/api.rb:1056)
   всегда пишет `{blocks: [serialized_block(text), images…]}`; telegram/vonage/message_bird/dialog360
   `attachment_block` — `{blocks: [media_block(...)], entityMap: {}}`. Текстовые входящие telegram
   (`text_block`) уже пишут документ Dante. `BlockManager.block_mapping` знает file,
   recorded-audio, image, unstyled, divider, header-one…four. `Dante::Converter.draftjs_to_prosemirror`
   есть, но требует `inlineStyleRanges`/`entityRanges` у каждого блока.
4. Дефект 1 воспроизведён `m4_blocks_probe_spec.rb` на BASE: 18 примеров, 17 падений (зелёный
   только разбор обычного документа Dante). Черновик (фолбэк в `BlockManager`) — 18/18.
5. Дефект 3: `URI.join("http://localhost:5002", "/a b.png")` → `URI::InvalidURIError: bad URI(is
   not URI?)` (в спеке пробника и мутанте UJ1). HOST в test env — `http://localhost:5002`
   (config/environments/test.rb:11), `Chaskiq::Config.get("HOST")` = credentials или ENV.
6. Дефект 4: существующий `slack_spec.rb:657` ожидает неэкранированный `"Hello & goodbye"`.
   Slack API: в `mrkdwn` `&`, `<`, `>` экранируются как `&amp;`, `&lt;`, `&gt;`
   (api.slack.com «Formatting text for app surfaces», «Escaping text») — по документации, не
   проверено на живом Slack.
7. Дефект 5: production, `SMTP_DELIVERY_METHOD=smtp`, `SMTP_ADDRESS` = mailpit, без
   `SMTP_USERNAME` → `smtp_settings` `{… user_name: nil, password: nil, authentication: :login …}`,
   `deliver_now` → `ArgumentError: SMTP-AUTH requested but missing user name`, в mailpit 0 писем.
   staging.rb и development.rb — тот же литерал без `port`/`domain` (порт 25 по умолчанию).
   Черновик (`authentication:` только при непустом `SMTP_USERNAME`, port/domain как в production)
   — письмо доходит во всех трёх средах, с логином — `:login` из ENV.
8. `docs/specs/fork-updates-m1-probes/m1_config_probe.rb` (AC-008) регуляркой
   `config\.action_mailer\.smtp_settings\s*=\s*(\{.*?^\s*\})` вырезает ЛИТЕРАЛ хеша из
   production.rb и делает ему `eval` в голом ruby (без ActiveSupport), затем требует при
   заданном `SMTP_USERNAME` user_name/password из ENV и `authentication == :login`, а без
   `SMTP_PORT` — порт 25. Значит: присваивание остаётся одним литералом `{ … }` с закрывающей
   скобкой на отдельной строке, условие внутри литерала — без ActiveSupport (`.to_s.empty?`, а не
   `.present?`). Черновик в такой форме прошёл m1_config_probe.
9. Дефект 6: `curl https://endoflife.date/api/v1/products/redis/` 2026-11-19 — живые ветки 8.10
   (8.10.3, 2026-07-29), 8.8, 8.6, 8.4, 8.2, 8.0, 7.4, 7.2, 6.2; новейшая — 8.10, тег
   `redis:8.10-alpine` (redis-server v=8.10.3). sidekiq 7.3.10 + redis-client 0.31.0 на
   `redis:5-alpine`: `RedisClient::UnsupportedServer: redis-client requires Redis 6+ with HELLO
   command available`; на 8.10 job выполняется. RDB, записанный redis 5 в именованный том,
   читается redis 8.10 (строка, список, хеш, zset). Полный rspec на 8.10 зелёный (п.1).
10. RA9: `m4_boot_probe.sh --ra-only` на BASE зелёный; с мутантом
    (`if Rails.env.production?` без staging) — красный (`SAME_AS_RAILS_CACHE=true`): в staging
    `Rails.cache` тоже redis, отличие видно только по отдельному объекту хранилища.
11. Мутационный гейт проверен на черновике с примерными тестами: все 9 мутантов убиты; на BASE
    гейт останавливается на отсутствии цели `spec/services/message_apis/block_manager_spec.rb`.

Предположения (не проверены): поведение Slack на экранированном тексте (по документации);
что в продовых данных нет иных форматов `serialized_content`, кроме Dante, обёртки `blocks` и
Draft.js.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. `MessageApis::BlockManager.get_blocks`** (`app/services/message_apis/block_manager.rb`).
JSON — Hash с `content`-массивом → этот массив (как сейчас). Hash с `blocks`-массивом → массив
узлов Dante: элемент, уже похожий на узел Dante (нет `key`/`inlineStyleRanges`/`entityRanges`),
остаётся как есть; блок Draft.js переводится: текстовые типы (`unstyled`, `header-*`, `blockquote`,
`code-block`, `*-list-item`, неизвестные) → узел `paragraph` (или `heading`) с одним text-узлом
`block["text"]` (пустой текст — без детей); `image` → `ImageBlock`, `file` → `FileBlock`,
`recorded-audio` → `AudioRecorderBlock`, `recorded-video`/`video` → `VideoBlock`, `divider` →
`DividerBlock`, у медиа `attrs` = `block["data"]`. Не-Hash элементы пропускаются. Прочий JSON
(`{}`, `[]`, `null`, число, `blocks`/`content` не массив) → `nil`. Битый JSON — как сейчас
(`JSON::ParserError`, плагины его ловят). `BlockManager.block_data` не менять.

**B. `MessageApis::BlockManager.plain_text(blocks)`**: текст каждого узла верхнего уровня; узлы
с пустым текстом пропускаются; между узлами — `"\n"`. Внутри узла text-узлы склеиваются как есть,
без вставленных символов; `hardBreak`/`hard_break` → `"\n"`; вложенные блочные узлы (элементы
списка и т. п.) — через `"\n"`. Края каждого узла обрезаются (`strip`). `Dante::Utils` не трогать.

**C. `MessageApis::BlockManager.absolute_url(url)`** — новый метод класса: пустой/`nil` → `nil`;
относительный путь → `HOST` без хвостового `/` + `/` + путь без ведущего `/`; `http(s)://` —
как есть; затем символы, недопустимые в URI (пробел, не-ASCII и т. п.), процент-кодируются, уже
закодированные `%XX` не трогаются; исключений не бросает (неисправимое → `nil`). telegram, vonage,
message_bird, slack строят URL медиа только им (`URI.join` в этих плагинах не остаётся); `nil` —
как пустой URL сейчас.

**D. Slack** (`app/services/message_apis/slack/api.rb`): приватный метод экземпляра
`escape_mrkdwn(text)` — `&` → `&amp;` (первым), `<` → `&lt;`, `>` → `&gt;`; применяется к тексту
section-блоков, которые `process_block` строит из содержимого сообщения. Ссылку
`<url|View attachment>` не экранировать (URL уже из `absolute_url`). `replied_block` не трогать.

**E. SMTP** (`config/environments/{production,staging,development}.rb`): `authentication: :login`
только при непустом `SMTP_USERNAME`; без него — без аутентификации (`authentication` nil или
нет ключа). user_name/password по-прежнему из ENV. staging и development получают
`port: ENV.fetch('SMTP_PORT', 25).to_i` и `domain: ENV.fetch('SMTP_DOMAIN', 'localhost.localdomain')`,
как production. Форма — раздел 4 п.8 (литерал хеша, условие без ActiveSupport). Ветку SES не трогать.

**F. compose** (`docker-compose.yml`): `services.redis.image: redis:8.10-alpine` — одна строка,
больше в файле ничего не менять (в том числе устаревший ключ `version`).

**G. Тесты** (новые `*_spec.rb` вне `spec/support/`; в существующие файлы — только ДОБАВЛЕНИЕ строк,
кроме одной строки slack из раздела 6). HTTP — webmock, включённый локально, как в describe
«outgoing messages» m3 (`include WebMock::API`, `WebMock.enable!`/`disable!` в `around`).
1. Новый `spec/services/message_apis/block_manager_spec.rb`: примеры, в описании которых есть
   слово `legacy` (обёртка `blocks` с узлами Dante → текст), `Draft` (блоки Draft.js → текст и
   ImageBlock с url), `paragraph` (два абзаца → `"a\nb"`), `space` (`absolute_url` с пробелом →
   `%20`).
2. В describe «outgoing messages» существующих файлов `spec/controllers/api/v1/hooks/`:
   telegram — примеры с `legacy`, `paragraph` (два абзаца уходят с `\n`), `space` (ImageBlock
   с пробелом в относительном пути → `sendPhoto` с закодированным URL); vonage, message_bird,
   telnyx_sms — пример с `legacy` (обёртка `blocks` уходит провайдеру с текстом); slack — пример
   с `escape` (`a < b` → section `a &lt; b`).
3. Slack: строку `      stub = expect_delivery("Hello & goodbye")` в `slack_spec.rb` заменить на
   `      stub = expect_delivery("Hello &amp; goodbye")`.
4. RA9 и SMTP покрыты пробником постановщика (`m4_boot_probe.sh`), своих тестов не нужно.

## 6. Не трогать

- Всё вне списка AC-009. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`,
  `app/services/dante/**` (включая `Dante::Utils`, `Dante::Converter` — использовать можно, менять
  нельзя), `config/initializers/**` (в том числе rack_attack.rb), `config/environments/test.rb`,
  `app/models/**`, плагины вне telegram/vonage/message_bird/telnyx_sms/slack, `lib/`, `db/`,
  workflows, `Dockerfile*`, `config.ru`, `CHANGELOG.md`.
- Всё, что принесли m1–m3, не откатывать: версии гемов, письма Devise, Rack::Attack, SES через
  aws-actionmailer-ses, puma.rb, CI, восстановленные плагины, faraday-2-авторизация, пути ассетов.
- Существующие спеки: удалять, переименовывать, skip-ать (`xit`, `skip`, `pending`, `:skip`),
  ослаблять или менять существующие строки запрещено — только добавлять; единственное исключение —
  строка slack из раздела 5 G.3. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec`, глобальный `require "webmock/rspec"` запрещены.
- `docs/specs/fork-updates-m1*` … `fork-updates-m3*`, `docs/specs/fork-updates-m4.md`,
  `docs/specs/fork-updates-m4-probes/**` — закоммичены постановщиком; не править (AC-009, sha256).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq
  (вредоносный код). Запрещены: `.vscode/`, self-hosted runner, `.env*` (кроме `.env.example`),
  `eval`/`new Function` в JS, невидимые Unicode-символы, git- и path-источники в Gemfile.
- Не апгрейдить Rails, не трогать ключ троттлинга, не менять формат, который ПИШУТ входящие плагины
  (только чтение старого формата).

## 7. Критерии приёмки

Команды — из корня клона. BASE — `0b296f3466d81286d034a64604f552c515cf2618`.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме, пробник зависимостей m1 зелёный.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m1-probes/m1_deps_probe.rb"'`

- **AC-002** — полный rspec строго зелёный на redis 8.10: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 457 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m4-probes/rspec_gate_m4.sh`

- **AC-003** — старый формат читается и пересылается четырьмя плагинами, абзацы разделены, URL медиа с пробелом и не-ASCII валиден, slack экранирует mrkdwn.
  `bash docs/specs/fork-updates-m4-probes/rspec_gate_m4.sh --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb`

- **AC-004** — SMTP без логина доставляет письмо в production, staging и development, с логином остаётся login из ENV; в staging у Rack::Attack своё redis-хранилище.
  `bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh`

- **AC-005** — redis из compose запинен на 8.10, читает RDB redis 5 и обслуживает sidekiq 7.
  `bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh`

- **AC-006** — новые тесты убивают мутанты старого разбора, склейки абзацев, URI.join, экранирования; пробник убивает RA9 и SMTP-мутанты.
  `python3 -I docs/specs/fork-updates-m4-probes/m4_mutation_gate.py`

- **AC-007** — целостность: зависимости и Dante не тронуты, спеки только дополнены, инварианты m1–m3 на месте, URI.join и безусловного SMTP-логина нет, compose изменён одной строкой.
  `python3 -I docs/specs/fork-updates-m4-probes/m4_integrity_probe.py 0b296f3466d81286d034a64604f552c515cf2618`

- **AC-008** — нет регрессий m1–m3: пробники рантайма m1 и m2, пробник Rack::Attack и загрузки m3, загрузка production m2, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'P=docs/specs/fork-updates-m4-probes; bash $P/rspec_gate_m4.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $P/rspec_gate_m4.sh --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $P/rspec_gate_m4.sh --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb" && python3 -I $P/m4_tree_probe.py 0b296f3466d81286d034a64604f552c515cf2618'`

- **AC-009** — вне разрешённых путей ничего не изменено, спеки и пробники постановщика не тронуты (sha256).
  `bash -c 'B=0b296f3466d81286d034a64604f552c515cf2618; test "$(git log --format=%H $B..HEAD -- docs/specs | wc -l)" = 1 && git diff --quiet $B HEAD -- docs/specs/fork-updates-m1.md docs/specs/fork-updates-m1-probes docs/specs/fork-updates-m2.md docs/specs/fork-updates-m2-probes docs/specs/fork-updates-m3.md docs/specs/fork-updates-m3-probes && printf "%s\n" "1d2bb684fdd2ab18ce58ba3fb4ca6d346bc3bb1510a690c8089c0daf777ac9bd  docs/specs/fork-updates-m4-probes/examples_base.txt" "f7b7fa029b8cbaf0d861a9f9715abc795d8d402d8c0da96578d211e5dafa0f4a  docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb" "6c0aa9b1fc2a4dda341dd5d6ad01742773dbfc963c3eb41f7a3d0099bdb70d11  docs/specs/fork-updates-m4-probes/m4_boot_probe.sh" "2534e35e3360cd07efd014a9b301cae3f4f72c360ffdbc44dd41cce51e8b890f  docs/specs/fork-updates-m4-probes/m4_compose_probe.sh" "00f8155230864cb3ea7c8a67aa70bc0700958f69c5b0d2974de33e812990a843  docs/specs/fork-updates-m4-probes/m4_integrity_probe.py" "ed188f4f48bdac5d1dc4c49c618d54990ff5716e7654f00d4738987e091f6432  docs/specs/fork-updates-m4-probes/m4_mutation_gate.py" "e72870a509332ffebc9fec8be770fa94d4d73c68b721cd082cf706d0871a3f3f  docs/specs/fork-updates-m4-probes/m4_tree_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m4-probes/pending_allowed.txt" "63877f770393923170408a4c6450863778503e059c5c9914959eae421d28f51d  docs/specs/fork-updates-m4-probes/rspec_gate_m4.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/block_manager[.]rb|app/services/message_apis/(telegram|message_bird|telnyx_sms|vonage|slack)/.+|config/environments/(production|staging|development)[.]rb|docker-compose[.]yml|spec/.+|docs/specs/fork-updates-m4[.]md|docs/specs/fork-updates-m4-probes/.+")"'`

- **AC-010** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-002, AC-008, AC-009, AC-010
зелёные; AC-003 красный (17 из 18 примеров); AC-004 красный (production: `SMTP-AUTH requested but
missing user name`); AC-005 красный (`services.redis.image is redis:5-alpine`); AC-006 красный (нет
`spec/services/message_apis/block_manager_spec.rb`, затем — `def self.absolute_url`); AC-007 красный (нет `absolute_url`/`escape_mrkdwn`, `URI.join` в четырёх
плагинах, безусловный `authentication: :login` в трёх средах, redis 5 в compose).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила, раздел «Автономное
перекрёстное ревью»). Коротко: коммит → REVIEW_SHA; исполнитель Codex → ревьюеры `agy` +
`qwen`, оба параллельно на `0b296f3466d81286d034a64604f552c515cf2618..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только
обёртка, путь абсолютный:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base 0b296f3466d81286d034a64604f552c515cf2618 --range 0b296f3466d81286d034a64604f552c515cf2618..<REVIEW_SHA> --exclude docs/specs/fork-updates-m4.md --exclude "docs/specs/fork-updates-m4-probes/**" --context "chaskiq fork-updates-m4: BlockManager читает обёртку blocks и Draft.js, plain_text с переводом строки между блоками, absolute_url вместо URI.join, экранирование Slack mrkdwn, SMTP без логина, redis 8.10 в compose; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m4.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m4-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; не теряется ли текст и
медиа при разборе старого формата; `absolute_url` не кодирует дважды и не бросает; SMTP с логином
работает как раньше; правила назначения и поиск (Dante::Utils) не задеты.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-002 — итоговые числа
examples/failures/pending; в `note` AC-006 — строка `killed`/`SURVIVED` по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m4.md>",
  "base_sha": "0b296f3466d81286d034a64604f552c515cf2618",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m4.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-009 (в том числе `Dante::Utils`, другие плагины,
  initializers, test.rb) или изменения существующей строки теста, кроме строки slack G.3;
- зелёный rspec недостижим без отката чего-то из m1–m3 или без бампа гема/npm;
- мутант набора AC-006 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах.

## 10. Стыки

После приёмки координатор вливает ветку в main и дописывает CHANGELOG. Следующим вехам остаются:
апгрейд Rails (ветка 7.2 в EOL), ключ троттлинга за прокси, `replied_block` slack без
экранирования, нормализация формата, который пишут входящие плагины (сейчас обёртка `blocks`).
