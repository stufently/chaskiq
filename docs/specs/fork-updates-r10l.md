# fork-updates-r10l — выбросы RuboCop, шаг 10l: WhatsApp-адаптеры (twilio, vonage, message_bird, dialog360) — отправка по методам, запросы пиннятся золотым снимком

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10l.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10l «SMS/WhatsApp:
  twilio, vonage, message_bird, telnyx, dialog360 api»; группа R10l/R10m: «`send_message`, `send_template_message` …
  Риск в: тела запросов к провайдерам и создаваемые записи. Характеризация: WebMock — точный метод/URL/тело/заголовки
  … Подход: „разбор входящего“ и „сборка исходящего“ — отдельные методы»; решение К1), план чистки —
  `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10k` (золотой снимок генератором-rspec на BASE,
  WebMock, готовая спека файлом, четыре шага сборки). Соседние вехи — `r10k`, позже `r10m`/`r10o` (раздел 10).
- BASE_SHA: `e05ceccfda38511b8c33b95e5395c460793221bd` — HEAD `main` «Record R10h2 acceptance» (R10cfg/К1, R10h1,
  R10i, R10h2 влиты; Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1, webmock из
  `Gemfile.lock`).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10k` — раздел 10), постановщик переносит BASE (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают `B=$(git merge-base HEAD @{u})`
  сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; спеки и снимок — в REVIEW_EXCLUDE).
  Дифф ≈ 345 КБ: ≈ 325 КБ — снимок (JSON), ≈ 14 КБ — четыре `api.rb` (+150/−112), ≈ 6 КБ — новая спека.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: уходят все 8 выбросов четырёх адаптеров (`Twilio::Api#send_message` — `AbcSize`; `Vonage::Api#send_message`
  и `MessageBird::Api#send_message` — `AbcSize`, `MethodLength`; `Dialog360::Api#send_message` — `AbcSize`,
  `#send_template_message` — `AbcSize`, `MethodLength`), с ними 7 строк todo. Код задан патчем постановщика
  `r10l_rewrite.patch`, золотой снимок — патчем `r10l_golden.patch`, новая спека — файлом `r10l_spec.rb` (всё руками
  не править). Спека прогоняет 110 случаев снимка через адаптеры с HTTP, застабленным WebMock, и сверяет
  возвращаемое значение, КАЖДЫЙ запрос (метод, URI, заголовки `Authorization`, `Content-Type`, `Accept`, `X-Token`,
  `D360-Api-Key`, сырое тело — порядок ключей и параметров тоже) и строки таблиц разговора после вызова: зелёная на
  коде BASE и после; каждый из 68 мутантов постановщика (`r10l_config.json`, `mutants`) роняет пример. Работа
  исполнителя — собрать веху шагами раздела 5, прогнать критерии, ревью и отчёт.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)` по коду, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое возвращаемое
значение, другое исключение, другой HTTP-запрос (URI, заголовок, тело) или другие строки в БД. Чтение снимка
`spec/fixtures/**` — данные, оно разрешено. AC-007 (`source_scan.py`) ищет запрещённые приёмы в новых и изменённых
файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10l`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10l-ci` (переменная `CHASKIQ_R10L_CACHE`). Перед любым `docker run` с
  `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-r10k-ci $HOME/.cache/chaskiq-r10l-ci` (уже сделан).
2. При переносе BASE (после влития `r10k` или другой вехи) перемерить; патчи не перегенерировать, пока
   всё сходится:
   - `git apply --check` патчей `r10l_golden.patch`, затем `r10l_rewrite.patch` на новом `main` чист (проверено на
     e05ceccf с патчами `r10k` в обоих порядках — раздел 10);
   - четыре адаптера и то, что они зовут, на новом `main` не менялись:
     `git diff --quiet e05ceccf main -- app/services/message_apis/twilio app/services/message_apis/vonage app/services/message_apis/message_bird app/services/message_apis/dialog360/api.rb app/services/message_apis/base_package.rb app/services/message_apis/block_manager.rb app/services/message_apis/helpers.rb`
     — иначе пересобрать снимок генератором (раздел 4, п. 2) на новом BASE, патч и мутанты (правки моделей
     `Conversation*`, `AppUser`, `ExternalProfile` видны по красному AC-003 на чистой сборке);
   - в `.rubocop.yml` есть строка `  CountAsOne: [array, hash, heredoc]` (К1); 7 строк адаптеров в блоках `AbcSize`
     (`dialog360/api.rb`, `message_bird/api.rb`, `twilio/api.rb`, `vonage/api.rb`) и `MethodLength`
     (`dialog360/api.rb`, `message_bird/api.rb`, `vonage/api.rb`) todo на месте;
   - бэклог-пробник на копии нового `main` со сборкой по разделу 5: у четырёх файлов 8 → 0, роста нет, итог падает
     ровно на 8 — число `8` в команде AC-004 (e05ceccf: 66 → 58; `r10k` снижает обе стороны на 6);
   - тексты 68 мутантов — каждый ровно один раз в своём файле после патча; имя новой спеки и снимка не заняты;
   - перегенерировать снимки сьюта на чистом checkout `main` с закоммиченными пробниками:
     `CHASKIQ_R10L_CACHE=$HOME/.cache/chaskiq-r10l-ci bash docs/specs/fork-updates-r10l-probes/rspec_gate_r10l.sh --write-base`
     и пересчитать sha256 в AC-008. Сейчас в снимках — 1530 примеров BASE e05ceccf (сняты на коммите
     черновика спеки поверх e05ceccf — шапки файлов называют его) (влитая раньше веха добавит свои).
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z; позже — по желанию полная политика `cross-review-v1` до коммита.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10l-ci`), 0ade8cfd, 8dd44a6b, e05ceccf (адаптеры между ними не менялись):
`Twilio::Api#send_message` (`twilio/api.rb:144`) — `AbcSize` 32.34/30; `Vonage::Api#send_message` (`vonage/api.rb:100`)
— `AbcSize` 40.63/30, `MethodLength` 31/30; `MessageBird::Api#send_message` (`message_bird/api.rb:114`) — `AbcSize`
41.45/30, `MethodLength` 31/30; `Dialog360::Api#send_message` (`dialog360/api.rb:153`) — `AbcSize` 30.1/30;
`#send_template_message` (`dialog360/api.rb:265`) — `AbcSize` 56.01/30, `MethodLength` 32/30. Итого 8; программа
считала 12 до К1. `telnyx_sms/api.rb` из названия вехи офенсов не имеет (замер: 0, в todo его нет) — не трогается.
`twilio_phone/api.rb` (3 `AbcSize`) — веха `r10m`. `ClassLength` для `app/services/message_apis/**` исключён в
`.rubocop.yml`.

**`r10l_rewrite.patch`** (только четыре `api.rb`, +150/−112): у каждого `send_message` ворота (`private_note?`,
пустой контент, профиль) остаются на месте, отправка уходит в приватный `deliver_blocks` (лямбды отправки, `plain_text`
у Twilio, `media_blocks`, `deliver_attachments` с теми же `captionless` и `delivery_hooks`); у Vonage и MessageBird
разбор контента — приватные `outgoing_blocks` (`html_content` → `serialized_text`, как было) и `parse_blocks` (тот же
`rescue JSON::ParserError, TypeError, NoMethodError` ровно вокруг `get_blocks`/`plain_text`), локальный хеш типов
медиа → константа `MEDIA_TYPES` (`private_constant`, как у Dialog360). `send_template_message` — `template_conversation`
(поиск по ключу, ветка `selected_user`: профиль, разговор по каналу, `start_conversation`), `template_profile_id`
(профиль участника, затем `add_participant_to_existing_user`), `template_payload` (тот же хеш тела) и
`add_template_message` (тот же `add_message`); `return if json_message.blank?` остаётся в методе. Закомментированные
`puts` удалены. После патча у четырёх файлов 0 офенсов (строгий RuboCop без todo).

**Почему поведение то же.** Вычисления идут в прежнем порядке: `part.message.as_json` и разбор — до поиска профиля,
`message_params`/`addressing` строятся из тех же значений, `plain_text` у Twilio считается после проверки профиля (у
документа-массива — тот же `NoMethodError` на `nil`). `rescue` у Vonage/MessageBird охватывает ровно `get_blocks` и
`plain_text` (не `Loofah`/`serialized_text`), сбой → `nil`, как старое `return`. Возвращаемое значение
`send_message` — то, что вернул `deliver_blocks` (ответ Faraday или `nil`); у Twilio проверка `response.success?` и
`report_delivery_failure` остались в `send_message`. В `send_template_message` профиль из ветки `selected_user`
передаётся дальше и не перезаписывается (`if profile_id.blank?`), `start_conversation` — только когда разговор по
каналу не найден; ключ не найден, но задан — тот же `NoMethodError` на `nil.main_participant`; `parameters.compact`
— тот же список; ответ не JSON → тот же `JSON::ParserError`; `messages: []` → `nil`; нет ключа `messages` →
`NoMethodError`.

**Доказательство.** Генератор `r10l_golden_spec.rb` (rspec-файл пробника, не часть сьюта; помощники — посимвольно
помощники спеки `r10l_spec.rb`) строит для каждого из 110 случаев `r10l_cases.json` мир в БД (приложение с ключом
`app-key`, агент, пользователи с внешними профилями и телефоном в `properties`, разговоры с ключами и каналами, часть
с контентом — сохранённая или нет, приватная или нет, с уже доставленными вложениями `delivery_index`), застабливает
`Chaskiq::Config.get("HOST")` и ВЕСЬ HTTP (`stub_request(:any, /.*/)`: ответ — из `replies` случая по номеру запроса,
иначе `reply`; каждый запрос пишется по порядку), для Dialog360 передаёт пакет-дубль с `app`, зовёт `send_message` /
`send_template_message` и пишет снимок `spec/fixtures/whatsapp/provider_payloads.json`: случай + `outcome` =
`{result, requests, db}`; `result` — каноническая форма (ответ Faraday — `{"@response" => {status, body}}`, символы —
`":имя"`, случайный ключ `Tokenable` — `"@random-key"`) или `{"@raise" => класс}`; `db` — строки `conversations`,
`conversation_parts`, `conversation_part_contents`, `conversation_part_events`, `conversation_part_channel_sources`,
`conversation_channels`, `external_profiles` (без колонок `datetime` и `nil`) и `id, type, email, properties`
`app_users`. Id детерминированы: `DatabaseCleaner` усекает таблицы перед каждым примером. AC-003: снимок дерева =
вывод генератора на коде BASE побайтно; спека сверяет каждый случай на коде дерева и BASE и под 68 мутантами (у
каждого мутанта `example` — прогоняются только случаи его метода, `rspec --example`).

Случаи (110, имена — в `r10l_cases.json`): по 21 на `send_message` каждого адаптера (приватная заметка, нет профиля,
текст, отказ 400, четыре вложения с подписью, вложения без текста, отказ второго вложения, первое уже доставлено,
несохранённая часть, вложение без URL, gif + аудио, аудио перед картинкой, jpeg, только `html_content`, пустой
`serialized_content` с html, пустой html, документ-массив, битый JSON, пустые и обычные draft-блоки, «битый» узел),
3 sandbox (Vonage, MessageBird, Dialog360), 23 `send_template_message` (каждая ветка поиска разговора и профиля,
отказ, ответ без `messages`/без id/не JSON, шаблон без языка, sandbox, параметры-строка/список с `nil`/хеш).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10l-ci`) на клонах
0ade8cfd/8dd44a6b/e05ceccf:

1. Замер без todo: 8 офенсов (раздел 3); с патчем — 0 у четырёх файлов, строгий RuboCop с урезанным todo чист; итог
   на e05ceccf 66 → 58 (на 8dd44a6b 70 → 62), роста ни у одной пары (коп, файл), новая спека без офенсов.
2. Генератор на коде BASE: `R10L_CASES=<путь>/r10l_cases.json R10L_GOLDEN_OUT=<файл> bundle exec rspec --options .rspec
   docs/specs/fork-updates-r10l-probes/r10l_golden_spec.rb` (окружение — как в `r10l_tests_gate.sh`: БД, redis,
   `RAILS_ENV=test`) → снимок патча побайтно; два прогона на BASE и прогон на коде с патчем — тот же вывод побайтно.
3. Спека `r10l_spec.rb`: 110 примеров зелёные на BASE и на дереве; 68/68 мутантов убиты (раздел 7, пробный прогон).
4. Полный сьют на BASE e05ceccf: 1530 примеров, 0 failures, 30 pending (снимки `--write-base`).
5. Утверждения о существующем коде (прочитаны тела): `BasePackage#delivery_hooks` — только `on_failure` у
   несохранённой части или части без медиа, иначе `already_sent`/`on_success` (`store_message_id` с
   `delivery_index`)/`on_failure`; `report_delivery_failure` → `add_error_event` (событие с источником
   `bypass-internal-<id>`); `BlockManager.deliver_attachments` (порядок вложений, подпись на первом подходящем,
   `captionless` — массив типов или лямбда, текст отдельно, результат — первый успех) и `get_blocks` (`nil` у
   не-хеша, `JSON::ParserError` у битого JSON), `plain_text` на «битых» узлах не падает (проверено пробой: ни один
   контент из строки не даёт `TypeError`/`NoMethodError`, поэтому эти два класса в `rescue` из случаев не
   достижимы — мутанты их не трогают); `serialized_text` — документ из одного текстового узла;
   `Helpers#find_conversation_by_channel(provider, channel)` — по `conversation_channels`; `App#start_conversation`
   ищет пакет по имени `initiator_channel` (`"dialog_360"` не находит пакета `Dialog360` — канал не создаётся,
   снимок это пиннит); `AppUser#phone` — ключ `properties`; ключи `Conversation`/`ConversationPart` — `Tokenable`
   (`SecureRandom.base58(24)`); WebMock — как в `message_bird_media_spec.rb` (`include WebMock::API`,
   `enable!`/`reset!`/`disable!` в `around`, `rails_helper` не трогаем). Предположение: порядок строк по `id` и
   нумерация с 1 после усечения стабильны — вывод совпал в трёх прогонах.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимок — **только** `git apply` патчей, спека — только копией. Никаких `pending`/`skip`/`xit`,
`# rubocop:` директив, чтения исходников (раздел 1). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10l-probes
export CHASKIQ_R10L_CACHE=$HOME/.cache/chaskiq-r10l-ci
```

**Шаг 1. Снимок и спека — на коде BASE (характеризация первой).** Спека — готовый файл постановщика
`$P/r10l_spec.rb` (sha256 в AC-008): строит мир случая, стабит HTTP и `HOST`, сверяет `JSON.pretty_generate` исхода
с `outcome` снимка. Копируется без правок:

```bash
cp $P/r10l_spec.rb spec/services/message_apis/whatsapp_provider_payloads_spec.rb
git apply $P/r10l_golden.patch
git add spec
git status --short        # ожидается ровно: "A  spec/fixtures/whatsapp/provider_payloads.json" и "A  spec/services/message_apis/whatsapp_provider_payloads_spec.rb"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 2 files
git commit -qm "Pin WhatsApp adapter payloads"
```

**Шаг 2. Код.**

```bash
git apply $P/r10l_rewrite.patch
git status --short        # ожидается ровно четыре строки " M app/services/message_apis/{dialog360,message_bird,twilio,vonage}/api.rb"
git commit -qam "Split WhatsApp send_message builders"
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10l_tests_gate.sh $B` (≈ 10 мин). Нужны строки
`R10L TREE PASS 110 examples`, `R10L BASE PASS 110 char / 0 renamed failing / 0 fix failing`, `R10L GOLDEN PASS 110
cases`, `R10L MUTANTS PASS 68/68 killed`, `R10L TESTS GATE PASS`. Красное — сначала
`cmp $P/r10l_spec.rb spec/services/message_apis/whatsapp_provider_payloads_spec.rb` (файл обязан совпасть); совпадает,
а гейт красный — раздел 9. Спеку, код, патчи, снимок и мутантов не править.

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10l <<'PY'
import json, re, sys
n = sys.argv[1]
cfg = json.load(open(f"docs/specs/fork-updates-{n}-probes/{n}_config.json"))
has = lambda b, c: re.search(rf"(?m)^{re.escape(c)}:$", b)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not any(has(b, c) for c in cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
for cop, paths in cfg.get("cops_partial", {}).items():
    i = next(i for i, b in enumerate(out) if has(b, cop))
    gone = {f"    - '{p}'" for p in paths}
    assert gone <= set(out[i].split("\n")), "stop: section 9"
    out[i] = "\n".join(l for l in out[i].split("\n") if l not in gone)
out = [b for b in out if re.search(r"(?m)^    - '", b) or not re.search(r"(?m)^  Exclude:$", b)]
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
PY
git diff --stat            # ожидается: только .rubocop_todo.yml, 7 deletions
git commit -am "Drop R10l entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10l

- Changed: the WhatsApp adapters (Twilio, Vonage, MessageBird, Dialog360) build their outgoing
  requests in smaller methods without a change in behaviour (Metrics outliers of R8a, milestone
  R10l of the R10 programme): each `send_message` hands the delivery to a `deliver_blocks` helper,
  Vonage and MessageBird parse the message content in `outgoing_blocks`/`parse_blocks`, and
  Dialog360 `send_template_message` finds the conversation, the profile, the payload and the sent
  message record in their own methods. A golden fixture (spec/fixtures/whatsapp/provider_payloads.json,
  110 cases generated on the old code with WebMock) pins the returned values, every request (URI,
  headers, raw body) and the conversation rows afterwards, and a new spec checks it. Their seven
  todo lines are gone.
```

```bash
git commit -am "Note fork-updates-r10l in changelog"
```

**Шаг 6.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строки `R10L … PASS`; AC-004 — строки `backlog without todo: …` и `drop: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме четырёх `api.rb` (только патчем), снимка (только патчем), новой спеки (только копией шага 1),
  `.rubocop_todo.yml` (только скриптом шага 4), `CHANGELOG.md`.
- Существующие спеки (адаптеров, хуков `spec/controllers/api/v1/hooks/*`, `spec/rails_helper.rb`) — не править и не
  переименовывать; `base_package.rb`, `helpers.rb`, `block_manager.rb` (`r10o`), `dialog360/presenter.rb`,
  `telnyx_sms/api.rb` (офенсов нет), `twilio_phone/api.rb` и прочие адаптеры (`r10m`), `slack/api.rb` (`r10k`).
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`.
- Прочие строки и блоки todo.
- Никаких ручных правок кода и снимка, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников; странности BASE (Vonage/MessageBird/Dialog360 не сообщают об отказе текстового сообщения и возвращают
  ответ 400; `NoMethodError` у Twilio/Dialog360 на документе-массиве; `"@random-key"` нового разговора; канал
  `dialog_360` не создаётся при `start_conversation`; пустой профиль `""` у пользователя без телефона) — данные, не
  чинить.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10L_CACHE=$HOME/.cache/chaskiq-r10l-ci bash docs/specs/fork-updates-r10l-probes/rspec_gate_r10l.sh'`

- **AC-002** — пути и байты: изменены ровно четыре api.rb адаптеров и снимок (новый обычный файл), новая спека, todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; api.rb и снимок побайтно равны BASE с двумя патчами, спека — побайтная копия r10l_spec.rb; todo = BASE без семи строк адаптеров в блоках AbcSize и MethodLength; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/r10l_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: снимок дерева побайтно равен выводу генератора постановщика на коде BASE (110 случаев); у каждого случая есть пример новой спеки, зелёный на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 68 мутантов r10l_config.json (текст найден ровно один раз) роняет пример, не загрузку.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10L_CACHE=$HOME/.cache/chaskiq-r10l-ci bash docs/specs/fork-updates-r10l-probes/r10l_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; у AbcSize в четырёх api.rb и у MethodLength в трёх (dialog360, message_bird, vonage) 0 офенсов; ни у одного копа ни в одном файле (новая спека тоже) офенсов не больше, чем на BASE; BASE содержит настройку К1; итог упал ровно на измеренные 8.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10L_CACHE=$HOME/.cache/chaskiq-r10l-ci bash docs/specs/fork-updates-r10l-probes/r10l_backlog_probe.sh $B > tmp/r10l-backlog.txt; rc=$?; cat tmp/r10l-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 8)}" tmp/r10l-backlog.txt'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10l-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимка добавляет ровно снимок (= патч) и спеку (= копия r10l_spec.rb), api.rb = BASE; коммит кода меняет ровно четыре api.rb = BASE + патч; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10l после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/r10l_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "d8b4b1105dc305284be499e73212144e065668adb68174f9cd4219f6bea4f44b  docs/specs/fork-updates-r10l-probes/examples_base.txt" "aa61f2d8cbad04fce8466ab77efd34004128b8ff00776a52901b6951a057acd6  docs/specs/fork-updates-r10l-probes/pending_allowed.txt" "9bbd05fab0b46455987d7b0c0c5a0bab7038909154b29d0ce90285072575ea9b  docs/specs/fork-updates-r10l-probes/r10l_backlog_probe.sh" "2d2b2f9466d4c85165d429429c2fd971f59ddcdee4e48c58104e9a7db53654e8  docs/specs/fork-updates-r10l-probes/r10l_cases.json" "e0facc8414cf3122017b554cd56e5fd90e1c55f5752b837fe54fcd86b0dcc839  docs/specs/fork-updates-r10l-probes/r10l_config.json" "6d05454c2c87239001e8a61686bcd70d1d543d412a0f3a1aad46499a171c7167  docs/specs/fork-updates-r10l-probes/r10l_golden.patch" "99ff8f71f492ffd069c964c88a054abeed4d2e55a981fd8e08ac1342725b8ebb  docs/specs/fork-updates-r10l-probes/r10l_golden_spec.rb" "66447c070a013be46ca5968eeca23e50fc213209e34afd14a5a4159cbe703f82  docs/specs/fork-updates-r10l-probes/r10l_probe.py" "326e5137b593509b5ffcab4e6f32846b8dd5930431b48096ce9ca49d90ded35d  docs/specs/fork-updates-r10l-probes/r10l_rewrite.patch" "b2e7009e88b76a9f77c23f661e0d732d4cc330d787cfd557da2542f85b321f8e  docs/specs/fork-updates-r10l-probes/r10l_sentinel.rb" "d6baaaeef5b750771fa942aa49eec057fa9ddc6c2bb3e0320beac43100284d96  docs/specs/fork-updates-r10l-probes/r10l_spec.rb" "220ea4bc180a77cfc943ab8e4e868005338b11cd7c52ad7284360541517e2f93  docs/specs/fork-updates-r10l-probes/r10l_tests.rb" "6c249b92fdfd18d6c2f43c1aa8a4705c881e5a50c955587f513ee23e4eeb9263  docs/specs/fork-updates-r10l-probes/r10l_tests_gate.sh" "02aba90e7e625426a071b3fe4e5786ad11810452f20bfbefbd0210274782432c  docs/specs/fork-updates-r10l-probes/rspec_gate_r10l.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10l-probes/source_scan.py" "5ac207be726f8b106b7a912c8fb4bd606a520545a241be48bb006879ac792f9e  docs/specs/fork-updates-r10l-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10L paths without
the change`, `is not BASE + r10l_golden.patch, r10l_rewrite.patch`, `is not a byte-for-byte copy of r10l_spec.rb`);
AC-003 красный (`no examples ran`, мутанты «survived» — спеки ещё нет, `mutant text occurs 0 times` у L67/L68 — их
текстов на коде BASE нет); AC-004 красный (`offenses left in the files of this milestone` у двух копов, `total did not go down:
BASE 66, tree 66`); AC-006 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10l-ci`).** Граница: клон от коммита спеки поверх
e05ceccf (upstream — коммит спеки) — AC-001 (1530 примеров, 0 failures), AC-005, AC-007, AC-008, AC-009 rc=0; AC-002,
AC-003, AC-004, AC-006 красные ровно с сообщениями выше. Сборка по разделу 5: все 9 критериев зелёные за 16 мин
(AC-001 — 1640 примеров, 0 failures, 30 pending; AC-003 — `R10L GOLDEN PASS 110 cases`, `R10L MUTANTS PASS 68/68
killed`, ≈ 10 мин; AC-004 — `backlog without todo: BASE 66, tree 58`, `drop: 8`; AC-007 — 2 файла). Порченая правка
поверх сборки (лишним коммитом, `"to":"5511999990000"` → `…001` в одном теле снимка) — AC-002 (`is not BASE +
r10l_golden.patch, …`), AC-006 (`extra commit after the changelog commit`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10l.md --exclude "docs/specs/fork-updates-r10l-probes/**" --exclude spec/fixtures/whatsapp/provider_payloads.json --context "chaskiq fork-updates-r10l: RuboCop-выбросы WhatsApp-адаптеров (Twilio send_message Abc 32; Vonage и MessageBird send_message Abc 41, 31 строка; Dialog360 send_message Abc 30.1, send_template_message Abc 56, 32 строки) разбиты без изменения поведения — send_message: ворота на месте, отправка в приватный deliver_blocks (те же лямбды, captionless, delivery_hooks); Vonage/MessageBird: outgoing_blocks + parse_blocks (rescue ровно вокруг get_blocks/plain_text), MEDIA_TYPES константой; Dialog360 send_template_message: template_conversation, template_profile_id, template_payload, add_template_message. Снимок spec/fixtures/whatsapp/provider_payloads.json (110 случаев, вывод старого кода: результат, каждый HTTP-запрос с заголовками и сырым телом, строки таблиц разговора; исключён из ревью как данные) и спека, сверяющая каждый случай с WebMock (зелёная на BASE и после, 68 мутантов); спека не читает исходники как текст; только чтение"`

Исключения (снимок — данные генератора, его побайтно проверяет AC-003):

REVIEW_EXCLUDE: docs/specs/fork-updates-r10l.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10l-probes/**
REVIEW_EXCLUDE: spec/fixtures/whatsapp/provider_payloads.json

Контекст ревьюеру: другой порядок вычислений (`plain_text` у Twilio до проверки профиля, `as_json` после неё),
`rescue` у Vonage/MessageBird, охватывающий больше (`Loofah`, `serialized_text`) или меньше, `next`/`nil` вместо
прежнего `return`, у Twilio потерянная проверка `response.success?`/`report_delivery_failure`, иной состав
`captionless`/`delivery_hooks`, у `send_template_message` профиль из ветки `selected_user`, перезаписанный профилем
главного участника, лишний `start_conversation`, потерянный `return` при пустом `messages`, иной порядок ключей тела
(пиннится сырой строкой); спека, которая сверяет не всё значение, запросы или строки, или читает исходник. Код,
снимок и спеку править нельзя (AC-002, AC-008) — замечание по месту решает постановщик (раздел 9); заход
исправлений тогда пустой, FINAL_SHA = REVIEW_SHA.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 9 критериев зелёные. Если agy упал или не дал
вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` у критерия —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10l.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "qwen", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>"],
    "verification_receipts": [],
    "resolutions": []
  },
  "handoff_status": "blocked",
  "criteria": [
    {"id": "AC-001", "status": "pass|fail|blocked",
     "command": "<команда ИЗ ЭТОЙ СПЕКИ, посимвольно>", "rc": 0, "note": "…"}
  ]
}
```

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10l.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после шагов 1–4 AC-004/AC-005
  красные (офенс остался, вырос в другой паре, разница итогов не 8, нет `base_requires` К1) — дефект спеки;
- `R10L GOLDEN` красный (снимок ≠ вывод генератора на BASE) или пример красный на BASE при спеке, побайтно равной
  `r10l_spec.rb`, — дефект спеки, приложи вывод;
- пример зелёный на BASE и красный на дереве (патч меняет поведение) — пример и вывод: это дефект патча, не спеки;
- мутант выжил при спеке, побайтно равной `r10l_spec.rb`, — id и вывод (эквивалентный мутант — дефект спеки);
  читать исходник, чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл расхождение поведения патча с BASE — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, снимка и существующих спек, правка пробников, патчей и мутантов, `pending`/`skip`,
чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено: на 8dd44a6b — `git apply` патчей `r10h2` и `r10k` (спека `r10k` в `main` ещё не закоммичена — взяты файлы
рабочего дерева) и `r10l` в порядках h2,k,l / l,h2,k / k,l,h2 / l,k,h2; на e05ceccf (`r10i`, `r10h2` влиты) — `r10k` и
`r10l` в порядках k,l / l,k: все чисты.

- **Код.** `r10k` — `slack/api.rb` (+ снимок); влитые `r10h2`/`r10i` меняли презентеры: файлов этой вехи никто
  не трогает. Позже `r10o` (`block_manager.rb`: `deliver_attachments`) меняет то, что зовёт `deliver_blocks`, — снимок
  `r10l` (случаи с вложениями) станет её характеризацией; `r10m` — `twilio_phone`, `telegram`, `twitter` (другие
  файлы).
- **`.rubocop_todo.yml`.** `r10l` убирает 7 строк. Соседи по блокам (e05ceccf): `AbcSize` — `slack` (`r10k`)
  не соседствует (между ним и `message_bird/api.rb` — `open_ai`); `MethodLength` — `slack` (`r10k`) сразу под
  `message_bird/api.rb`. Скрипт шага 4 текстовый — на любом BASE даёт верный итог; но ветка, снятая с BASE до
  влития `r10k` (или `r10k`, снятая до `r10l`), при слиянии даст конфликт соседних строк todo
  (решение — удалить обе строки; AC-002/AC-006 считают todo от своего BASE). Ставить последовательно, перенося BASE;
  блоки не пустеют.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Что перемерить при переносе BASE** — раздел 2, п. 2 (число `8` в AC-004 не меняется, меняются только итоги:
  после `r10k` ожидаемо 60 → 52).
- Мутационный прогон противоположным исполнителем (cx) — после 2026-11-22 11:39Z, отдельной спекой.
