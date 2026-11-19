# fork-updates-m7 — все вложения в Twilio и Dialog360, SafeDownload для серверных загрузок

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19.
- BASE_SHA: `bcfdbc9dd170f1c5e2595ef0953a23c02d83f860` «Update CHANGELOG for fork-updates-m6» (m4, m5 и m6 — Rails 8.1 — влиты). **BASE плавающий:** веха запускается ПОСЛЕ влития fork-updates-m6 (Rails 8.1). Поверх
  BASE_SHA в `main` могут лежать только коммиты постановщика, правящие эту строку; клон снят с
  последнего из них. Все команды вычисляют BASE сами: `B=$(git merge-base HEAD @{u})` — коммит
  `main`, от которого снят клон (`make_clone.sh --work-branch fork-updates-m7` ставит upstream
  `origin/main`). В `report.json` поле `base_sha` = значение этой строки. Коммиты исполнителя в
  `docs/specs` запрещены (AC-006).
- Исполнитель: Codex (`cx`). Мутации по новым тестам потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`). Исправления внутри вехи — тому же Codex.
- Цель: закрыть известные проблемы из CHANGELOG fork-updates-m5 (одно вложение в twilio и
  dialog360, серверные загрузки по URL вне SafeDownload), после чего координатор вливает ветку.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m7`.
  Живое дерево `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root (исключение —
  контейнеры redis/postgres/mailpit без bind mount, их пробники поднимают сами). На хост ничего
  не ставить (никаких gem/bundle/npm/yarn/pip/apt на хосте).

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker | ruby 3.3.5 + libpq + node + curl + jq |
| гемы | `$HOME/.cache/chaskiq-m6/bundle` (Rails 8 в lock) или `$HOME/.cache/chaskiq-m1/bundle` (Rails 7.2) — гейт и пробники выбирают сами по `Gemfile.lock`; `CHASKIQ_BUNDLE` переопределяет | гейт, пробники |
| `node_modules/` | в клоне (gitignored), копия из `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в спеках |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `axllent/mailpit:v1.34.0` | гейт, пробники |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m7-probes
bash $P/rspec_gate_m7.sh                                # полный строгий rspec, ~6 мин
bash $P/rspec_gate_m7.sh --only $P/m7_probe_spec.rb     # один файл
python3 -I $P/m7_mutation_gate.py MB1 CL1               # часть мутантов (полный набор ~6 мин)
```

## 3. Задача и почему

1. **Одно вложение в Twilio и Dialog360.** `MessageApis::Twilio::Api#process_message_params`
   берёт `blocks.find` по ImageBlock и FileBlock (второй перетирает первый в `MediaUrl`, видео и
   аудио не уходят вовсе); Dialog360 `send_message` выбирает первое из image/video/audio/file.
   Оба строят URL как `HOST + url` (абсолютный URL медиа ломается, пробел не кодируется).
2. **SSRF вне пересылки** (серверные загрузки по чужому URL через open-uri или http-гем):
   - `Api::V1::HooksController#send_subscription_confirmation` — `URI.parse(@request_body["SubscribeURL"]).open`.
     Эндпоинт `POST /api/v1/hooks` не аутентифицирован, тело — любой JSON: запрос с заголовком
     `x-amz-sns-message-type: SubscriptionConfirmation` и `SubscribeURL: http://169.254.169.254/...`
     заставляет Rails сходить во внутреннюю сеть.
   - `FetchLinkCardService#call` — HEAD и GET страницы http-гемом с `follow` и
     `VERIFY_NONE`, `download_image` — `URI.parse(url).open` для `og:image` и oEmbed-миниатюры;
     URL приходит из `OembedController` (`params[:url]`) и `ContentShowcase` presenter.
   - `Mutations::CreateUrlUpload#download_to_file` — `URI.parse(uri).open` по URL из GraphQL.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker на клоне от BASE_SHA и на черновике (черновик — только для проверки
достижимости, в веху не идёт):

1. Гейт на BASE (Rails 7.2, кэш m1): `503 examples, 0 failures, 30 pending`; список примеров —
   `examples_base.txt`, pending — `pending_allowed.txt` (тот же, что в m5). Гейт проверяет, что
   выполнены ВСЕ примеры BASE (подмножество) и их не меньше `MIN_EXAMPLES`; после m6 набор примеров
   не меньше (m6 только дополняет), поэтому замер на Rails 7.2 годится и после m6.
2. Черновик реализации (разделы 5.A–5.F) с примерными тестами: полный гейт зелёный
   (513 примеров, 0 падений), пробник `m7_probe_spec.rb` 19/19, мутационный гейт — 7/7
   мутантов убиты, пробник целостности и регрессий зелёные. На BASE пробник красный (раздел 7).
3. Twilio WhatsApp принимает одно медиа на сообщение: «Additional MediaUrl parameters will be
   ignored» (help.twilio.com, «Sending and Receiving Media with WhatsApp Messaging on Twilio»).
   Подпись к медиа — `Body` того же запроса. Dialog360 (WhatsApp Cloud API v1) — один медиа-объект
   на запрос, `caption` у image/video/document, у audio подписи нет (текущий код её и не шлёт).
4. `MessageApis::SafeDownload` (m5): `fetch(url, max_bytes:, max_redirects:, deadline:)` → `StringIO`
   или nil; `resolve` — единственная точка DNS (подменяется в тестах); webmock перехватывает его
   `Net::HTTP` (проверено пробником m5). `read_response` сейчас отдаёт голый `StringIO` — типа
   содержимого нет, а link card и upload его используют.
5. `OEmbed::Providers.get(url)` ходит только к эндпоинтам зарегистрированных провайдеров (URL
   должен совпасть со схемой провайдера, иначе `OEmbed::NotFound`) — в скоуп не входит, кроме
   загрузки `thumbnail_url` (через `download_image`).
6. `Campaign#clean_inline_css` (`campaign.rb:138`) открывает URL премейлера, который строит само
   приложение из `default_url_options[:host]` и `app.key`/`id` — пользовательского ввода в нём нет,
   поэтому это не SSRF; перевод на SafeDownload сломал бы self-hosted с приватным хостом. Вне вехи.
   `client_tester_controller.rb` только делает `require "open-uri"`; `lib/auth0_web_token.rb` ходит
   на домен из конфигурации — вне вехи.

Предположения (не проверены): что живой Twilio принимает `Body` без `MediaUrl` и наоборот в одной
серии без ограничения частоты; что SNS всегда присылает `SubscribeURL` на
`https://sns.<регион>.amazonaws.com` (документация AWS «Confirm the subscription»; для Китая —
`amazonaws.com.cn`).

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. `MessageApis::BlockManager.deliver_attachments`** — новый keyword `captionless: []` (массив
типов блоков). Для типа из `captionless` блок вызывается с `caption = nil`, и подпись НЕ считается
отправленной. После цикла: если есть успешный ответ, а подпись так и не ушла (`caption` не nil) —
`send_text.call(caption)` один раз, вернуть первый успешный ответ. Без `captionless:` поведение
m5 не меняется побайтно для всех вызывающих (Telegram, Vonage, MessageBird).

**B. Twilio** (`app/services/message_apis/twilio/api.rb`): каждое медиа (`media_blocks`, все
четыре типа) — отдельный POST с `MediaUrl` из `BlockManager.absolute_url`; текст — `Body` первого
успешно отправленного медиа (кроме аудио: `captionless: %w[AudioRecorderBlock]`, тогда текст
уходит отдельным POST только с `Body`); без медиа — один POST с `Body`. Через
`deliver_attachments`. `blocks.find` и `HOST +` не остаются. Обработка неуспешного ответа
(`add_message_event "errored: …"` и nil) — по итоговому ответу, как сейчас.

**C. Dialog360** (`app/services/message_apis/dialog360/api.rb`): то же — каждое медиа отдельным
`POST {url}/messages` с `type` image/video/document/audio и `{type => {link:, caption:}}` (у audio
только `link`, `captionless: %w[AudioRecorderBlock]`); текст — `{type: "text", text: {body:}}`;
URL — `absolute_url`; через `deliver_attachments`; `blocks.find` и `endpoint +` не остаются.

**D. `MessageApis::SafeDownload::Body < StringIO`** — `fetch` возвращает его вместо голого
`StringIO`: `content_type` — сырое значение заголовка `Content-Type` ответа (или nil), `mime_type` —
часть до `;`, обрезанная и в нижнем регистре, nil при пустой. Остальной контракт `fetch` не
меняется (Twitter работает без правок).

**E. SNS** (`app/controllers/api/v1/hooks_controller.rb`): `SubscribeURL` подтверждается только
если это `https` и хост целиком совпадает с `\Asns\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z`;
загрузка — только `MessageApis::SafeDownload.fetch`. Иначе — ничего не запрашивать (ответ
эндпоинта прежний, `ok`). `require "open-uri"` убрать.

**F. Карточки ссылок и загрузка по URL.**
1. `FetchLinkCardService#call`: HEAD + GET http-гемом заменить одним
   `MessageApis::SafeDownload.fetch(url, max_bytes: 2 МБ)`; нет ответа или `mime_type` не
   `text/html` — nil; дальше oEmbed как сейчас, иначе opengraph из уже полученного HTML (второго
   запроса нет). `download_image` — только через `SafeDownload.fetch`, тип файла — `mime_type`.
2. `Mutations::CreateUrlUpload#download_to_file`: только `SafeDownload.fetch`; nil →
   `raise GraphQL::ExecutionError` (текст на выбор). `require "open-uri"`/`URI.open` не остаются.

**G. Тесты** (новые `*_spec.rb` вне `spec/support/`; в существующие файлы — только ДОБАВЛЕНИЕ
строк). HTTP — webmock, включённый локально (`include WebMock::API`, `WebMock.enable!`/`disable!`
в `around`), DNS — `allow(MessageApis::SafeDownload).to receive(:resolve)`. Слова-маркеры в
описаниях примеров обязательны — по ним мутационный гейт ищет упавший пример:
1. `spec/controllers/api/v1/hooks/twilio_spec.rb` и `spec/controllers/api/v1/hooks/dialog_360_spec.rb`:
   несколько вложений уходят все, подпись на первом (`attachment`); аудио без подписи и текст
   отдельным сообщением (`audio`).
2. `spec/services/message_apis/block_manager_spec.rb`: `deliver_attachments` с `captionless:` (`captionless`).
3. `spec/services/message_apis/safe_download_spec.rb`: `content_type`/`mime_type` тела (`content type`).
4. `spec/services/fetch_link_service_spec.rb`: страница на приватном адресе — ни одного запроса
   (`private`); публичная HTML-страница даёт карточку opengraph, приватная `og:image` не
   запрашивается (`opengraph` и `image` в одном или разных примерах).
5. `spec/controllers/api/v1/hooks_controller_spec.rb`: `SubscribeURL` вне SNS не запрашивается (`SubscribeURL`).
6. Новый `spec/graphql/mutations/create_url_upload_spec.rb`: приватный URL — ошибка без запроса (`private`).

Мутанты AC-003 (дописываются в конец файла, перекрывая метод): MB1 — `media_blocks` отдаёт одно
медиа; CL1 — `deliver_attachments` игнорирует `captionless:`; CT1 — `Body#mime_type` → nil; SN1 —
старое `send_subscription_confirmation` через open-uri; LC1 — старый `call` (HEAD/GET http-гемом);
LC2 — старый `download_image` через open-uri; UP1 — старый `download_to_file` через open-uri.
Поэтому имена `media_blocks`, `deliver_attachments(…, captionless:)`, `Body#mime_type`,
`send_subscription_confirmation`, `FetchLinkCardService#call`, `#download_image`,
`Mutations::CreateUrlUpload#download_to_file` обязаны остаться.

## 6. Не трогать

- Всё вне списка AC-006. В частности: `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`,
  `config/**`, `bin/**`, `db/**`, `lib/**`, `app/models/**` (в том числе `campaign.rb`,
  `preview_card.rb`), `app/services/dante/**`, плагины вне twilio/dialog360, `CHANGELOG.md`.
- Всё, что принесли m1–m6, не откатывать: версии гемов и Rails, письма Devise, Rack::Attack, SES,
  SMTP, puma.rb, CI, восстановленные плагины, absolute_url, экранирование Slack, все вложения в
  telegram/vonage/message_bird, SafeDownload и его фильтры.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — только добавлять. Новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `spec/spec_helper.rb`, `.rspec`, глобальный `require "webmock/rspec"` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-006, sha256).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq.
  Запрещены: `.vscode/`, self-hosted runner, `.env*` (кроме `.env.example`), `eval`/`new Function`
  в JS, невидимые Unicode-символы, git- и path-источники в Gemfile, новые гемы.
- Не проверять подпись SNS-сообщений, не менять `Campaign`, oEmbed-провайдеров и ключ троттлинга.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 503 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m7-probes/rspec_gate_m7.sh`

- **AC-002** — Twilio и Dialog360 шлют все вложения с одной подписью и без подписи у аудио, SafeDownload отдаёт тип содержимого, SNS, карточки ссылок и загрузка по URL ходят только через SafeDownload.
  `bash docs/specs/fork-updates-m7-probes/rspec_gate_m7.sh --only docs/specs/fork-updates-m7-probes/m7_probe_spec.rb`

- **AC-003** — новые тесты убивают мутанты одного вложения, подписи у аудио, типа содержимого, SNS, карточек ссылок и загрузки по URL.
  `python3 -I docs/specs/fork-updates-m7-probes/m7_mutation_gate.py`

- **AC-004** — целостность: зависимости и конфиги не тронуты, спеки только дополнены, инварианты m1–m5 на месте, одного вложения, HOST-конкатенации и open-uri нет.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m7-probes/m7_integrity_probe.py $B'`

- **AC-005** — нет регрессий m1–m6: загрузка на Rails 8 (после m6), пробники рантайма m1–m5, загрузка m2–m4, redis из compose, puma и конфиг m1, дерево и supply-chain.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-m7-probes/m7_regress.sh $B'`

- **AC-006** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "8d1934273de6d13564c11a005a15426808704dfb554708d669a3e404f0d61922  docs/specs/fork-updates-m7-probes/examples_base.txt" "656978ab88791c100f536f3c9df6e4bdf38aa25d1cfa76289d2635999b5aab37  docs/specs/fork-updates-m7-probes/m7_integrity_probe.py" "2b87e570b280510e0ff439cdae6b66561073eb1af4a6f3774d6092fabcd4a0ef  docs/specs/fork-updates-m7-probes/m7_mutation_gate.py" "ace18792b43f1275d8fc4ac4c250114dd397d9a10d71a45771fee495130cb212  docs/specs/fork-updates-m7-probes/m7_probe_spec.rb" "bf67ebbe6c963d51b97517425ad872e6519447edb937d059a097293c8fa41594  docs/specs/fork-updates-m7-probes/m7_regress.sh" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m7-probes/pending_allowed.txt" "56c8e160c7cbb2d39eae9f26ad05081941e24fec3f39ef39dab76fde19295e30  docs/specs/fork-updates-m7-probes/rspec_gate_m7.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "app/services/message_apis/(block_manager|safe_download)[.]rb|app/services/message_apis/(twilio|dialog360)/.+|app/controllers/api/v1/hooks_controller[.]rb|app/services/fetch_link_card_service[.]rb|app/graphql/mutations/create_url_upload[.]rb|spec/.+")"'`

- **AC-007** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-005, AC-006, AC-007 зелёные;
AC-002 красный (14 из 19 примеров: все вложения и аудио в Twilio и Dialog360, `Body#content_type`/`mime_type`, четыре чужих `SubscribeURL`, три примера карточек ссылок, приватный URL в CreateUrlUpload; зелёные на BASE только текст без медиа, поведение m5 `deliver_attachments`, публичная загрузка и подтверждение настоящего SNS); AC-003 красный (`block_manager.rb does not define captionless:` — гейт останавливается до прогонов); AC-004 красный (`blocks.find`, HOST-конкатенация, нет `media_blocks`/`deliver_attachments` в twilio и dialog360, нет `captionless:` и `SafeDownload::Body`, open-uri в трёх местах, хост SubscribeURL не ограничен, карточки — http-гемом).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<B>..REVIEW_SHA` (B — из
`git merge-base HEAD @{u}`, подставить значение); один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <B> --range <B>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m7.md --exclude "docs/specs/fork-updates-m7-probes/**" --context "chaskiq fork-updates-m7: все вложения в twilio и dialog360 (подпись один раз, аудио без подписи, deliver_attachments captionless:), SafeDownload::Body с content_type, SNS SubscribeURL только sns.*.amazonaws.com через SafeDownload, FetchLinkCardService и CreateUrlUpload через SafeDownload; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m7.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m7-probes/**

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; обходы проверки хоста SNS
(`sns.x.amazonaws.com.evil`, userinfo, порт, регистр, http); остались ли пути загрузки мимо
SafeDownload; не теряются ли медиа и текст; поведение Telegram/Vonage/MessageBird не изменилось.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 7: AC-001…AC-007.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-001 — итоговые числа
examples/failures/pending; в `note` AC-003 — строка `killed`/`SURVIVED` по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m7.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m7.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- починка требует правки вне путей AC-006 (модели, `config/**`, Gemfile, другие плагины) или
  изменения существующей строки теста;
- нужен новый гем, или зелёный rspec недостижим без отката чего-то из m1–m6;
- мутант набора AC-003 эквивалентен (поведение неотличимо) — опиши почему, не меняя гейт;
- пробник постановщика противоречит этой спеке или коду BASE (дефект спеки);
- веха запущена до влития m6 (в `Gemfile.lock` Rails 7.2, а BASE_SHA в шапке уже после m6) или
  образ, кэш или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, подменять окружение и
глушить коды возврата в командах.

## 10. Стыки

- Веха m6 меняет `app/models/preview_card.rb` (`enum :type`), рядом с которым работает
  `FetchLinkCardService` (`card.type = response.type` / `:link`); m7 модель не трогает — после
  влития m6 гейт m7 это проверяет (AC-001, AC-002).
- После приёмки координатор вливает ветку в main и дописывает CHANGELOG. Остаются вне вехи:
  проверка подписи SNS-сообщений (`SigningCertURL`), запросы oEmbed к провайдерам,
  `Campaign#clean_inline_css` (URL строит приложение), MMS в telnyx_sms, связь read-receipt
  Vonage только с первым вложением, `config.load_defaults 8.1` (план m6).
