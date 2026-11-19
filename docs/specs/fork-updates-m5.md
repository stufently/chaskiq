# fork-updates-m5 — все вложения в исходящих сообщениях, безопасная загрузка медиа в Twitter

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`.
  Дата спеки: 2026-11-19.
- BASE_SHA: `9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef` «Update CHANGELOG for fork-updates-m4» — HEAD `main` после слияния вехи fork-updates-m4.
  Клон снимается с СЛЕДУЮЩЕГО коммита — коммита этой спеки и каталога
  `docs/specs/fork-updates-m5-probes/`; других коммитов между BASE_SHA и HEAD клона нет.
- Исполнитель: Codex (`cx`). Мутации по новым тестам потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`). Исправления внутри вехи — тому же Codex.
- Цель: закрыть две известные проблемы из CHANGELOG 2026-11-19, после чего координатор сам вливает
  ветку в main.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m5`.
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
| `node_modules/` | в клоне (gitignored), копия из клона m4 (тот же `yarn.lock`) | ts-node в спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `axllent/mailpit:v1.34.0` | гейт, пробники |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m5-probes
bash $P/rspec_gate_m5.sh                                  # полный строгий rspec, ~6 мин
bash $P/rspec_gate_m5.sh --only $P/m5_media_probe_spec.rb # один файл
python3 -I $P/m5_mutation_gate.py MB1 SD1                 # часть мутантов (полный набор ~10 мин)
```

## 3. Задача и почему

1. **Только первое вложение.** telegram, vonage и message_bird выбирают медиа
   `blocks.find { |block| %w[ImageBlock VideoBlock FileBlock AudioRecorderBlock].include?(...) }` и
   отправляют один запрос: сообщение агента с несколькими файлами (или пересланное из Slack с
   несколькими картинками) уходит получателю с одним вложением, остальные молча теряются.
   Ещё: если у первого медиа нет пригодного URL (`absolute_url` → nil), не уходит ничего — ни
   остальные медиа, ни текст.
2. **SSRF в Twitter.** `MessageApis::Twitter::Api#upload_media` скачивает картинку сервером через
   `URI.parse(media).open` (open-uri: http, https, ftp, без проверки адреса, без лимита размера,
   редиректы без проверки, прокси из ENV). URL приходит из блока сообщения: после m4 туда попадают
   и картинки из обёртки `blocks`, которые пишут входящие плагины. Сообщение с картинкой
   `http://169.254.169.254/latest/meta-data/...` или `http://redis:6379/` заставляет Rails сходить во
   внутреннюю сеть. Плюс `url.include?("http")` считает `/uploads/http-guide.png` абсолютным URL.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker на клоне от BASE_SHA и на черновике (черновик — только для проверки
достижимости критериев, в веху не идёт):

1. Гейт rspec на BASE: `479 examples, 0 failures, 30 pending`; pending совпадают с `pending_allowed.txt` m4 (скопирован
   сюда), список примеров BASE — `examples_base.txt`.
2. Ответ `send_message` используется только в `MessageApis::BasePackage#notify_message`
   (`base_package.rb:30`): из него берётся id сообщения провайдера (`get_message_id`) и пишется
   `conversation_part_channel_sources`, по нему же отсекаются дубли. Поэтому при нескольких
   запросах `send_message` возвращает ответ ПЕРВОГО запроса.
3. API провайдеров принимают одно медиа на сообщение: Telegram `sendPhoto/sendVideo/sendDocument/
   sendAudio` (одно поле медиа + `caption`), Vonage Messages v0.1 `message.content` одного типа,
   MessageBird conversations `send` с одним `type`/`content`. Альбом Telegram `sendMediaGroup`
   смешивает не все типы (аудио/документы только между собой) — не используем.
4. Telnyx шлёт только SMS-текст (`send_sms_message`), медиа не трогает; Slack `process_blocks`
   уже переводит КАЖДЫЙ блок — у обоих проблемы нет. У twilio и dialog360 то же «одно вложение»
   (`blocks.find`) — вне вехи, раздел 10.
5. Серверные загрузки по URL в `app/` и `lib/` (поиск `URI.open`, `URI.parse(...).open`, `open-uri`,
   `Net::HTTP.get`, `Faraday.get`): `twitter/api.rb:382` (пересылка — в вехе);
   `hooks_controller.rb:109` (SNS SubscribeURL), `fetch_link_card_service.rb:124` (карточки ссылок),
   `graphql/mutations/create_url_upload.rb:30` (загрузка по URL агентом), `campaign.rb:138` — не
   пересылка, раздел 10. `twitter#make_get_request` ходит OAuth-клиентом только на api.twitter.com.
   dialog360 `upload_media` — пустая заглушка.
6. Гемов для SSRF в lock нет (`ssrf_filter`, `private_address_check` отсутствуют; есть
   `addressable 2.8.5`, `net-http 0.10.0`, `webmock 3.19.1`). Новые гемы не нужны: в net-http 0.10.0
   есть `Net::HTTP#ipaddr=` (`net/http.rb:1365`) — соединение идёт на заданный IP, а `Host`/SNI и
   проверка сертификата — по имени. Проверено: с webmock `Net::HTTP.new(host, 443, nil)` +
   `ipaddr=` + запрос отдают тело стаба; третий аргумент `nil` отключает прокси из ENV.
7. `IPAddr` (ruby 3.3.5): `private?` (10/8, 172.16/12, 192.168/16, fc00::/7), `loopback?`,
   `link_local?` (169.254/16, fe80::/10) НЕ покрывают `100.64.0.0/10`, `0.0.0.0/8`, мультикаст и
   IPv4-mapped (`::ffff:127.0.0.1` → `loopback? == false`, нужен `native`). Поэтому список
   запрещённых диапазонов — явный (раздел 5 B).
8. Достижимость: черновик (раздел 5 целиком) проходит `m5_media_probe_spec.rb`, полный гейт,
   мутационный гейт (с примерными тестами), пробники целостности и регрессий — раздел 7.

Предположения (не проверены): что провайдеры принимают серию медиа подряд без ограничения частоты
для одного получателя в пределах обычного сообщения (2–5 файлов); живого Twitter API нет (DM API
v1.1 закрыт для бесплатных аккаунтов) — проверяем только код загрузки до upload.twitter.com.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Все вложения.**
1. `MessageApis::BlockManager.media_blocks(blocks)` — новый метод класса
   (`app/services/message_apis/block_manager.rb`): Hash-узлы верхнего уровня с типом `ImageBlock`,
   `VideoBlock`, `FileBlock`, `AudioRecorderBlock`, в порядке документа; не-массив → `[]`.
2. telegram, vonage, message_bird (`app/services/message_apis/<плагин>/api.rb`) берут медиа ТОЛЬКО
   через `MessageApis::BlockManager.media_blocks` (`blocks.find` по медиа-типам не остаётся) и:
   - на каждое медиа с пригодным URL (`MessageApis::BlockManager.absolute_url` не nil) — один
     запрос провайдеру тем же методом и в той же форме, что сейчас для одного медиа
     (telegram `sendPhoto`/`sendVideo`/`sendDocument`/`sendAudio`; vonage `message.content` с
     `type` и `{url:, caption:}`; message_bird `send` с `type` и `content`);
   - медиа без пригодного URL пропускается (остальные и текст уходят);
   - текст (`plain_text`) уходит ОДИН раз — подписью (`caption`) к первому ОТПРАВЛЕННОМУ медиа; у
     остальных медиа подписи нет (ключ отсутствует или пустая строка); пустой текст подписью не
     ставится;
   - если ни одно медиа не ушло, а текст есть — один текстовый запрос, как сейчас; нет ни медиа,
     ни текста — запросов нет, возврат `nil`;
   - `send_message` возвращает ответ ПЕРВОГО запроса (раздел 4 п.2).
   В vonage метод `build_message_params` можно заменить (его зовёт только `send_message`).
   Telegram отправляет через существующий `upload_telegram(channel_id, data, method:)` (имя и
   сигнатуру не менять — на нём мутант CP1).

**B. `MessageApis::SafeDownload`** — новый класс `app/services/message_apis/safe_download.rb`,
только stdlib (`net/http`, `ipaddr`, `socket`), без новых гемов:
1. `MessageApis::SafeDownload.blocked_ip?(ip)` → `true`/`false`: IPv4-mapped IPv6 сначала
   разворачивается в IPv4 (`native`); запрещены `0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
   169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
   ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8`; нераспознаваемая строка → `true`.
2. `MessageApis::SafeDownload.resolve(host)` → массив строк-адресов (`Addrinfo.getaddrinfo` или
   `Resolv`); ошибка разрешения → `[]`. Это единственная точка DNS — тесты и пробник подменяют её.
3. `MessageApis::SafeDownload.fetch(url, max_bytes: 15 * 1024 * 1024, max_redirects: 3)` →
   объект с `read` (StringIO, бинарный) или `nil`; исключений наружу не бросает:
   - только `http`/`https` с непустым хостом (`ftp:`, `file:`, `javascript:`, относительный путь,
     `nil` → `nil`); хост берётся как `URI#hostname` (IPv6-литерал без скобок);
   - адреса — `resolve(hostname)`; пусто или ЛЮБОЙ адрес `blocked_ip?` → `nil` без запроса;
     исключение — origin из `Chaskiq::Config.get("HOST")` (совпадают схема, хост без учёта
     регистра и порт): свой сервер можно и на приватном адресе (относительные `/uploads/...`
     self-hosted инсталляций), другой порт того же хоста — нет;
   - соединение: `Net::HTTP.new(hostname, port, nil)` (без прокси из ENV), `ipaddr =` проверенный
     адрес (защита от DNS rebinding), `use_ssl` для https, таймауты открытия ≤ 5 с и чтения ≤ 10 с,
     один `GET`;
   - 3xx с `Location` — следующий хоп (относительный `Location` — от текущего URL), каждый хоп
     проходит ВСЕ проверки заново; больше `max_redirects` редиректов → `nil`;
   - не 2xx (кроме обработанных 3xx) → `nil`; `Content-Length` больше `max_bytes` или тело,
     выросшее больше `max_bytes` при чтении, → `nil` (читать потоком, не держать больше лимита).
**C. Twitter** (`app/services/message_apis/twitter/api.rb`): `upload_media` получает файл только
через `MessageApis::SafeDownload.fetch(media)`; `nil` → `upload_media` возвращает `nil` (DM уходит
без вложения, как при неудачной загрузке сейчас). В `send_message` URL картинки —
`MessageApis::BlockManager.absolute_url(...)` (вместо `url.include?("http")` и склейки с HOST);
`nil` → без вложения. Остальное в плагине не трогать.

**D. Тесты** (новые `*_spec.rb` вне `spec/support/`; в существующие файлы — только ДОБАВЛЕНИЕ строк).
HTTP — webmock, включённый локально, как в describe «outgoing messages» (`include WebMock::API`,
`WebMock.enable!`/`disable!` в `around`); DNS — подмена `MessageApis::SafeDownload.resolve`.
1. Новый `spec/services/message_apis/safe_download_spec.rb`: примеры, в описании которых есть слово
   `private` (хост резолвится в приватный адрес → `nil`, стаб URL не запрошен), `mapped`
   (`blocked_ip?("::ffff:127.0.0.1")` и `::ffff:10.0.0.1` → `true`), `redirect` (публичный URL
   отвечает 302 на хост с приватным адресом → `nil`, внутренний стаб не запрошен); плюс размер,
   лимит редиректов, схемы, свой HOST.
2. `spec/controllers/api/v1/hooks/{telegram,vonage,message_bird}_spec.rb`, в describe «outgoing
   messages»: пример со словом `attachments` в описании — два и больше медиа уходят отдельными
   запросами в порядке документа; telegram — ещё пример со словом `caption`: текст уходит
   подписью первого медиа и только его.
3. `spec/controllers/api/v1/hooks/twitter_spec.rb`: пример со словом `private` — `upload_media` с
   URL на приватный адрес (например `http://169.254.169.254/...`) возвращает `nil`, стаб этого URL и
   `upload.twitter.com` не запрошены; пример с публичным URL — загрузка через SafeDownload и
   INIT/APPEND/FINALIZE на `https://upload.twitter.com/1.1/media/upload.json` (стабы webmock).
4. Мутанты AC-004 (дописываются в конец файла, перекрывая метод): MB1 — `media_blocks` отдаёт
   только первое медиа (цели: три спеки плагинов, слово `attachment`); CP1 — `upload_telegram`
   выкидывает `caption` (`caption`); SD1 — `blocked_ip?` всегда `false` (`private`); SD2 —
   `blocked_ip?` без разворота IPv4-mapped (`mapped`); SD3 — `fetch` проверяет только первый хоп
   и идёт по редиректам без проверки (`redirect`); TW1 — `upload_media` снова через open-uri
   (twitter_spec, `private`). Убит = упал пример целевого файла с этим словом в описании.

## 6. Не трогать

- Всё вне списка AC-007. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`
  (никаких новых гемов и бампов), `config/**`, `docker-compose.yml`, `app/services/dante/**`,
  плагины вне telegram/vonage/message_bird/twitter (twilio, dialog360, slack, telnyx_sms — тоже
  нет), `hooks_controller.rb`, `fetch_link_card_service.rb`, `create_url_upload.rb`, `campaign.rb`,
  `lib/`, `db/`, workflows, `Dockerfile*`, `CHANGELOG.md`.
- Всё, что принесли m1–m4, не откатывать: версии гемов, письма Devise, Rack::Attack, SES, puma.rb,
  CI, восстановленные плагины, faraday-2-авторизация, пути ассетов, разбор старого формата
  блоков, `absolute_url`, экранирование Slack, SMTP без логина, redis 8.10.
- Существующие спеки: удалять, переименовывать, skip-ать (`xit`, `skip`, `pending`, `:skip`),
  ослаблять или менять существующие строки запрещено — только добавлять. Новые файлы в
  `spec/support/`, правки `spec/rails_helper.rb`, `spec/spec_helper.rb`, `.rspec`, глобальный
  `require "webmock/rspec"` запрещены.
- `docs/specs/fork-updates-m1*` … `fork-updates-m4*`, `docs/specs/fork-updates-m5.md`,
  `docs/specs/fork-updates-m5-probes/**` — закоммичены постановщиком; не править (AC-007, sha256).
  `docs/specs/fork-updates-m6*` (параллельная веха) не трогать.
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq
  (вредоносный код). Запрещены: `.vscode/`, self-hosted runner, `.env*` (кроме `.env.example`),
  `eval`/`new Function` в JS, невидимые Unicode-символы, git- и path-источники в Gemfile.
- Не апгрейдить Rails, не трогать формат, который ПИШУТ входящие плагины.

## 7. Критерии приёмки

Команды — из корня клона. BASE — `9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef`.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме, пробник зависимостей m1 зелёный.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m1-probes/m1_deps_probe.rb"'`

- **AC-002** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 479 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m5-probes/rspec_gate_m5.sh`

- **AC-003** — три плагина шлют все вложения с одной подписью и ответом первого запроса, SafeDownload режет приватные адреса, схемы, редиректы и размер и держит соединение на проверенном адресе, Twitter качает только через него.
  `bash docs/specs/fork-updates-m5-probes/rspec_gate_m5.sh --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb`

- **AC-004** — новые тесты убивают мутанты одного вложения, подписи, фильтра адресов, IPv4-mapped, редиректа и open-uri в Twitter.
  `python3 -I docs/specs/fork-updates-m5-probes/m5_mutation_gate.py`

- **AC-005** — целостность: зависимости и конфиги не тронуты, спеки только дополнены, инварианты m1–m4 на месте, одного вложения и open-uri нет.
  `python3 -I docs/specs/fork-updates-m5-probes/m5_integrity_probe.py 9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef`

- **AC-006** — нет регрессий m1–m4: пробники рантайма m1 и m2, Rack::Attack m3, блоки m4, загрузка m3, m4 и production m2, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'P=docs/specs/fork-updates-m5-probes; bash $P/rspec_gate_m5.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $P/rspec_gate_m5.sh --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $P/rspec_gate_m5.sh --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $P/rspec_gate_m5.sh --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb" && python3 -I $P/m5_tree_probe.py 9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef'`

- **AC-007** — вне разрешённых путей ничего не изменено, спеки и пробники постановщика не тронуты (sha256).
  `bash -c 'B=9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef; test "$(git log --format=%H $B..HEAD -- docs/specs | wc -l)" = 1 && git diff --quiet $B HEAD -- docs/specs/fork-updates-m1.md docs/specs/fork-updates-m1-probes docs/specs/fork-updates-m2.md docs/specs/fork-updates-m2-probes docs/specs/fork-updates-m3.md docs/specs/fork-updates-m3-probes docs/specs/fork-updates-m4.md docs/specs/fork-updates-m4-probes && printf "%s\n" "cd71b2873de1895437fa99ea056c9b3a4418da69a523b41858e32ee9a33bb4a6  docs/specs/fork-updates-m5-probes/examples_base.txt" "77b6082022df5e4a82fa6671b4d57e1cdf0d163b7b0439a713b44eafc7e88ce8  docs/specs/fork-updates-m5-probes/m5_integrity_probe.py" "1fa925059d61fe712852ec51b1bbda361003a04a2a1ebdfcdd7ef4d39960d649  docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb" "0c5e1121fee95c7c9a78d4824d2245a2973ca14d9aa9ae731f617153b3e3b2e6  docs/specs/fork-updates-m5-probes/m5_mutation_gate.py" "57f9e85d77d0598cfa4329832fb62943311177dfe2ed8512b8067e19a4d67a2a  docs/specs/fork-updates-m5-probes/m5_tree_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m5-probes/pending_allowed.txt" "7600bf0d129cae344e6ef196dd46ef8c14d461f89815ab8de99b3e7509223d2a  docs/specs/fork-updates-m5-probes/rspec_gate_m5.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/block_manager[.]rb|app/services/message_apis/safe_download[.]rb|app/services/message_apis/(telegram|vonage|message_bird|twitter)/.+|spec/.+|docs/specs/fork-updates-m5[.]md|docs/specs/fork-updates-m5-probes/.+")"'`

- **AC-008** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-002, AC-006, AC-007, AC-008 зелёные; AC-003 красный (нет `MessageApis::SafeDownload`, одно вложение в трёх плагинах); AC-004 красный (нет `spec/services/message_apis/safe_download_spec.rb`, затем — `def self.media_blocks`); AC-005 красный (нет `media_blocks` и `safe_download.rb`, `blocks.find` в трёх плагинах, `URI.parse(media).open` и `url.include?("http")` в twitter).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила, раздел «Автономное
перекрёстное ревью»). Коротко: коммит → REVIEW_SHA; исполнитель Codex → ревьюеры `agy` +
`qwen`, оба параллельно на `9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка, путь абсолютный:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base 9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef --range 9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef..<REVIEW_SHA> --exclude docs/specs/fork-updates-m5.md --exclude "docs/specs/fork-updates-m5-probes/**" --context "chaskiq fork-updates-m5: все вложения в telegram/vonage/message_bird (подпись один раз, ответ первого запроса), MessageApis::SafeDownload (приватные адреса, IPv4-mapped, редиректы, размер, ipaddr-пиннинг, без прокси), Twitter upload_media через SafeDownload; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m5.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m5-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; обходы SSRF (DNS
rebinding, IPv6, mapped, десятичные/восьмеричные IP-литералы, редирект, прокси из ENV, `Location`
со схемой `file:`); не теряются ли медиа и текст; id сообщения провайдера сохраняется.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-002 — итоговые числа
examples/failures/pending; в `note` AC-004 — строка `killed`/`SURVIVED` по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m5.md>",
  "base_sha": "9fa8d4e11d4819fd35f36284d6a0dfeb49ba80ef",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m5.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-007 (другие плагины, `config/**`, Gemfile) или изменения
  существующей строки теста;
- нужен новый гем, или зелёный rspec недостижим без отката чего-то из m1–m4;
- мутант набора AC-004 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- образ, кэш или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах.

## 10. Стыки

После приёмки координатор вливает ветку в main и дописывает CHANGELOG. Следующим вехам остаются:
одно вложение в twilio и dialog360 (`blocks.find`); серверные загрузки по URL вне пересылки —
`hooks_controller.rb:109` (SNS SubscribeURL), `fetch_link_card_service.rb:124` (карточки ссылок),
`create_url_upload.rb:30` (загрузка по URL агентом), `campaign.rb:138` — перевести на
`MessageApis::SafeDownload`; MMS-вложения в telnyx_sms; апгрейд Rails (веха m6).
