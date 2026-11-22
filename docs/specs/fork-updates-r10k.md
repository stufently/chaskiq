# fork-updates-r10k — выбросы RuboCop, шаг 10k: `slack/api.rb` — сборка Block Kit по методам, тела запросов пиннятся золотым снимком

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10k.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10k: «`thread_head`
  96, `conversation_status_blocks` 54, `notify_new_lead` 38, `notify_message` 67 (Cyc 23), `attachment_block` 31. Риск
  в: Block Kit-нагрузка во внешний API. Характеризация — WebMock: точное тело каждого запроса
  `chat.postMessage`/`chat.update` (JSON) по каждой ветке события … Подход: блоки → методы-строители»; решение К1,
  раздел 2), план чистки — `docs/specs/fork-updates-rubocop-plan.md`. Шаблоны — `fork-updates-r10h1` (золотой снимок
  генератором-rspec на BASE, сверка по случаю) и `fork-updates-r10i` (готовая спека файлом, `spec_sources`,
  `base_requires`). Соседние вехи — `r10h1`, `r10h2`, `r10i`, позже `r10l`/`r10m` (раздел 10).
- BASE_SHA: `e05ceccfda38511b8c33b95e5395c460793221bd` — HEAD `main` «Record R10h2 acceptance» (R10cfg/К1, R10c, R10e, R10g
  влиты; от 5fdb3a33 «Add R10h1 spec», где снимались замеры, отличается только `docs/specs`; Ruby 4.0.10, RuboCop
  1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1, webmock из `Gemfile.lock`).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влились `r10h1`, `r10h2`, `r10i` — раздел 10), постановщик переносит BASE (раздел 2), коммитит
  новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 155 КБ: ≈ 136 КБ — золотой снимок (JSON), ≈ 12 КБ — `slack/api.rb`, ≈ 5 КБ — новая спека.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: у `MessageApis::Slack::Api` уходят все 6 выбросов (`thread_head` — `AbcSize`; `notify_message` — `AbcSize`,
  `CyclomaticComplexity`, `MethodLength`, `PerceivedComplexity`; `attachment_block` — `AbcSize`), с ними 4 строки
  `slack/api.rb` из todo. Код задан патчем постановщика `r10k_rewrite.patch`, золотой снимок — патчем
  `r10k_golden.patch`, новая спека — файлом `r10k_spec.rb` (всё руками не править). Спека прогоняет 50 случаев снимка
  через API Slack с HTTP, застабленным WebMock, и сверяет возвращаемое значение, КАЖДЫЙ запрос (метод, URI,
  `Authorization`, `Content-Type`, сырое тело JSON — порядок ключей тоже) и аргументы `direct_upload`: зелёная на коде
  BASE и после; каждый из 42 мутантов постановщика (`r10k_config.json`, `mutants`) роняет пример. Работа
  исполнителя — собрать веху шагами раздела 5, прогнать критерии, ревью и отчёт.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)` по коду, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое возвращаемое
значение, другое исключение, другой HTTP-запрос (URI, заголовок, тело) или другие аргументы загрузки. Чтение снимка
`spec/fixtures/**` — данные, оно разрешено. AC-007 (`source_scan.py`) ищет запрещённые приёмы в новых и изменённых
файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10k`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10k-ci` (переменная `CHASKIQ_R10K_CACHE`). Перед любым `docker run` с
  `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-r10h-ci $HOME/.cache/chaskiq-r10k-ci` (уже сделан). **Уже нужно:** влилась `r10h1`
   (HEAD 0ade8cfd): оба патча применяются, `slack`/`helpers`/`block_manager` не менялись, 4 строки todo на месте (проверено);
   не перемерено — бэклог (ожидаемо 73 → 67), `--write-base` (+30 примеров `r10h1`) и sha256; перенести BASE по п. 2.
2. При переносе BASE (после влития `r10h1`, `r10h2`, `r10i` или другой вехи) перемерить; патчи не перегенерировать,
   пока всё сходится:
   - `git apply --check` патчей `r10k_golden.patch`, затем `r10k_rewrite.patch` на новом `main` чист (проверено на
     46aa8d16 с патчами `r10h1`, `r10h2`, `r10i` в трёх порядках — раздел 10);
   - `slack/api.rb` и то, что он зовёт из соседей, на новом `main` не менялись:
     `git diff --quiet 46aa8d16 main -- app/services/message_apis/slack app/services/message_apis/helpers.rb app/services/message_apis/block_manager.rb`
     — иначе пересобрать снимок генератором (раздел 4, п. 2) на новом BASE, патч и мутанты (правки моделей
     `Conversation*`, `AppUser`, `Agent` видны по красному AC-003 на чистой сборке);
   - в `.rubocop.yml` есть строка `  CountAsOne: [array, hash, heredoc]` (К1); 4 строки `slack/api.rb` в блоках
     `AbcSize`, `CyclomaticComplexity`, `MethodLength`, `PerceivedComplexity` todo на месте;
   - бэклог-пробник на копии нового `main` со сборкой по разделу 5: у файла 6 → 0, роста нет, итог падает ровно на
     6 — число `6` в команде AC-004 (46aa8d16: 77 → 71; влитые раньше `r10h1`/`r10h2`/`r10i` снижают обе стороны на
     4/4/3);
   - тексты 42 мутантов — каждый ровно один раз в `slack/api.rb` после патча; имя новой спеки не занято;
   - перегенерировать снимки сьюта на чистом checkout `main`:
     `CHASKIQ_R10K_CACHE=$HOME/.cache/chaskiq-r10k-ci bash docs/specs/fork-updates-r10k-probes/rspec_gate_r10k.sh --write-base`
     и пересчитать sha256 в AC-008. Сейчас в снимках — 1427 примеров BASE 46aa8d16 (сняты на коммите черновика спеки поверх 46aa8d16 — шапки файлов называют его) (влитая раньше веха добавит свои).
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z; позже — по желанию полная политика `cross-review-v1` до коммита.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10k-ci`) на 5fdb3a33 (= 46aa8d16 по коду), только `slack/api.rb`:
`thread_head` (`api.rb:366`) — `AbcSize` 36.4/30; `notify_message` (`api.rb:839`) — `AbcSize` 64.82/30,
`CyclomaticComplexity` 23/13, `MethodLength` 45/30, `PerceivedComplexity` 25/13; `attachment_block` (`api.rb:1100`) —
`AbcSize` 31.05/30. Итого 6; программа считала 10 до К1 — `MethodLength` у `thread_head`,
`conversation_status_blocks`, `notify_new_lead`, `attachment_block` сняла К1 (литералы Block Kit — одна строка), эти
методы не трогаются. `ClassLength` для `app/services/message_apis/**` исключён в `.rubocop.yml`.

**`r10k_rewrite.patch`** (только `slack/api.rb`, +122/−171): `thread_head` собирает те же блоки в том же порядке из
`thread_intro_block`, `participant_fields_block` (семь строк полей → `{type: "mrkdwn", text:}`) и `pick_agent_block`;
тело `replied_block` → `replied_section(data)` (общий с `notify_message`, `return nil if data.blank?` остаётся в
`replied_block`); `notify_message` — ворота, `blocks_transform`, имя автора, ветка блока (`replied_section(data || {})`,
имя участника), ветка события → `event_section` + `assignee_mention` (тот же `get_slack_user_by_email`), отправка →
`post_thread_message`; `attachment_block` — файлы через `attachment_file` и `fetch_attachment` (`get_file_data` +
`handle_direct_upload` под тем же `rescue StandardError` с логами → `[file_data, file]` или `nil`), первый `nil` →
`return nil` из `attachment_block`. После патча у файла 0 офенсов (строгий RuboCop без todo).

**Почему поведение то же.** `thread_head`: блоки и их порядок — те же литералы; поля участника — те же строки в том же
порядке (`seen` считается раньше `Info` — чистые `I18n.l`/атрибуты, без побочных эффектов); `text_blocks` считается
первым, как раньше; `flatten!` всегда что-то разворачивает (`conversation_status_blocks` — массив), поэтому
возвращает массив, `nil` от пустого `replied_block` остаётся внутри (снимок `thread_head with only a blank block`).
`notify_message`: `blocks_transform(part)` и `format_user_name(part.authorable)` вычисляются для КАЖДОЙ части и в
прежнем порядке (у части без автора — тот же `NoMethodError`); замена `username` у ответа блока —
`user_options[:username] =` вместо `merge!` (ключ есть — позиция в хеше та же); `messageable.data || {}` и порядок
`data["label"]` → `data_fmt` сохранены (массив → тот же `TypeError`, строка → `String#[]`); у события `data_fmt`
считается до запроса `users.lookupByEmail`, запрос — до поиска треда (снимок `assignment without a slack thread`:
запрос есть, поста нет); `"#{data_fmt}#{mention}"` ≡ старое `data_fmt << mention` (у `""`-литерала мутации не было: она
шла только для хеша). `post_message` получает те же `"new message"`, `blocks.as_json` и `{username:, channel:,
thread_ts:}` → то же тело (порядок ключей тела пиннится сырой строкой). `attachment_block`: `rescue` охватывает ровно
то же (`get_file_data` и `handle_direct_upload`), ошибка → `nil` из метода, как старое `err`/`return nil` (файлы
до сбойного уже загружены — снимок `second file without a download url`); `file[:url]` при `nil` от загрузки падает
ВНЕ `rescue`, как раньше (`NoMethodError` — снимок `upload returns nothing`); `data["text"].split` — после файлов.

**Доказательство.** Генератор `r10k_golden_spec.rb` (rspec-файл пробника, не часть сьюта; помощники — посимвольно
помощники спеки `r10k_spec.rb`) строит для каждого из 50 случаев `r10k_cases.json` мир в БД (приложение с ключом
`app-key`, агенты, участник AppUser/Lead с колонками, разговор с ключом `conversation-key`, состоянием,
приоритетом, исполнителем, временем создания 2026-01-02 03:04:05 UTC, тредами Slack, частями Content/Block/Event),
застабливает `Chaskiq::Config.get("HOST")`, `direct_upload` (аргументы пишутся, ответ — из `uploads` случая) и ВЕСЬ HTTP
(`stub_request(:any, /.*/)`: ответ — из `replies` случая по «МЕТОД URI-без-query», иначе `200 {}`; каждый запрос
пишется по порядку), зовёт `thread_head` / `notify_added` / `update_thread_head` / `notify_message` /
`serialize_content` и пишет снимок `spec/fixtures/slack/block_kit_payloads.json`: случай + `outcome` =
`{result, requests, uploads}`; `result` — каноническая форма (символьные ключи и значения — `":имя"`, запись AR —
`{"@record" => класс, "attributes" => …}` без меток времени) или `{"@raise" => класс}`. Id детерминированы:
`DatabaseCleaner` усекает таблицы перед каждым примером с `RESTART IDENTITY`. AC-003: снимок дерева = вывод генератора
на коде BASE побайтно; спека сверяет каждый случай на коде дерева и BASE и под 42 мутантами.

Случаи (50, имена — в `r10k_cases.json`): 8 `thread_head` (состояние, приоритет, исполнитель с именем/без, Lead и
аноним, все виды частей, пустой блок → `nil`, ответ-массив → `TypeError`), 2 `notify_added`, 3 `update_thread_head`,
26 `notify_message` (каждая ветка контента/блока/события, без треда, `ok: false`, пользователь Slack найден/нет, пустой
email — ловит `present?` → `nil?`), 11 `serialize_content` (каждая ветка `attachment_block` и одна `process_blocks`).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10k-ci`) на клонах
5fdb3a33/46aa8d16:

1. Замер без todo: 6 офенсов (раздел 3); с патчем — 0 у файла, строгий RuboCop с урезанным todo чист; итог
   77 → 71, роста ни у одной пары (коп, файл), новая спека без офенсов.
2. Генератор на коде BASE: `R10K_CASES=<путь>/r10k_cases.json R10K_GOLDEN_OUT=<файл> bundle exec rspec --options .rspec
   docs/specs/fork-updates-r10k-probes/r10k_golden_spec.rb` (окружение — как в `r10k_tests_gate.sh`: БД, redis,
   `RAILS_ENV=test`) → снимок патча побайтно; два прогона на BASE и прогон на коде с патчем — тот же вывод побайтно.
3. Спека `r10k_spec.rb`: 50 примеров зелёные на BASE и на дереве; 42/42 мутантов убиты (раздел 7, пробный прогон).
4. Полный сьют на BASE 46aa8d16: 1427 примеров, 0 failures, 30 pending (снимки `--write-base`).
5. Утверждения о существующем коде (прочитаны тела): `api_post` строит `{channel:, text:, blocks:}` и `merge!(options)`
   (порядок ключей тела); `blocks_transform` возвращает `[]`, если `messageable` не отвечает на `serialized_content`
   (у `ConversationPartBlock`/`ConversationPartEvent` такого атрибута нет — схема), и глотает `JSON::ParserError`,
   `NoMethodError`, `TypeError`; `get_slack_user_by_email` — GET `users.lookupByEmail`, `nil` при любой ошибке;
   `get_file_data` — `files.info` только при `mode == "file_access"` и `file_access == "check_file_info"`;
   `handle_direct_upload` — `authorize_bot!`, GET файла, `direct_upload(file:, filename: File.basename(url), content_type:)`;
   `Helpers#photo_block`/`file_block`/`serialized_block` без случайных ключей (`keygen` зовёт только `gif_block`);
   `Agent#avatar_url` без вложения → gravatar от email; `DatabaseCleaner` — `Truncation` перед каждым примером (id в
   снимке — 1); WebMock — как в `slack_api_helpers_spec.rb` (`include WebMock::API`, `enable!`/`reset!`/`disable!` в
   `around`, `rails_helper` не трогаем). Предположение: порядок `conversation.messages` (без `order`) — порядок
   вставки; запрос не менялся, вывод стабилен в трёх прогонах.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимок — **только** `git apply` патчей, спека — только копией. Никаких `pending`/`skip`/`xit`,
`# rubocop:` директив, чтения исходников (раздел 1). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10k-probes
export CHASKIQ_R10K_CACHE=$HOME/.cache/chaskiq-r10k-ci
```

**Шаг 1. Снимок и спека — на коде BASE (характеризация первой).** Спека — готовый файл постановщика
`$P/r10k_spec.rb` (sha256 в AC-008): строит мир случая, стабит HTTP/`direct_upload`/`HOST`, сверяет
`JSON.pretty_generate` исхода с `outcome` снимка. Копируется без правок:

```bash
cp $P/r10k_spec.rb spec/services/message_apis/slack_block_kit_payloads_spec.rb
git apply $P/r10k_golden.patch
git add spec
git status --short        # ожидается ровно: "A  spec/fixtures/slack/block_kit_payloads.json" и "A  spec/services/message_apis/slack_block_kit_payloads_spec.rb"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 2 files
git commit -qm "Pin Slack Block Kit payloads"
```

**Шаг 2. Код.**

```bash
git apply $P/r10k_rewrite.patch
git status --short        # ожидается ровно: " M app/services/message_apis/slack/api.rb"
git commit -qam "Split Slack thread and message builders"
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10k_tests_gate.sh $B` (≈ 9 мин). Нужны строки
`R10K TREE PASS 50 examples`, `R10K BASE PASS 50 char / 0 renamed failing / 0 fix failing`, `R10K GOLDEN PASS 50
cases`, `R10K MUTANTS PASS 42/42 killed`, `R10K TESTS GATE PASS`. Красное — сначала
`cmp $P/r10k_spec.rb spec/services/message_apis/slack_block_kit_payloads_spec.rb` (файл обязан совпасть); совпадает, а
гейт красный — раздел 9. Спеку, код, патчи, снимок и мутантов не править.

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10k <<'PY'
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
git diff --stat            # ожидается: только .rubocop_todo.yml, 4 deletions
git commit -am "Drop R10k entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10k

- Changed: `MessageApis::Slack::Api` builds its Block Kit payloads in smaller methods without a
  change in behaviour (Metrics outliers of R8a, milestone R10k of the R10 programme): the thread
  head is assembled from intro, participant fields and agent picker blocks, `notify_message` picks
  the replied/event section and posts through one helper, and `attachment_block` fetches each file
  in its own method under the same rescue. A golden fixture (spec/fixtures/slack/block_kit_payloads.json,
  50 cases generated on the old code with WebMock) pins the returned values and every request
  (URI, headers, raw JSON body) and upload, and a new spec checks it. Its four todo lines are gone.
```

```bash
git commit -am "Note fork-updates-r10k in changelog"
```

**Шаг 6.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строки `R10K … PASS`; AC-004 — строки `backlog without todo: …` и `drop: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `slack/api.rb` (только патчем), снимка (только патчем), новой спеки (только копией шага 1),
  `.rubocop_todo.yml` (только скриптом шага 4), `CHANGELOG.md`.
- Существующие спеки Slack (`spec/services/message_apis/slack_*_spec.rb`, `spec/controllers/api/v1/hooks/slack_spec.rb`)
  — не править и не переименовывать; `spec/rails_helper.rb`; `message_apis/helpers.rb`, `block_manager.rb` (веха
  `r10o`), презентеры (вехи `r10h1`, `r10h2`, `r10i`), прочие адаптеры (`r10l`, `r10m`).
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`.
- Прочие строки и блоки todo.
- Никаких ручных правок кода и снимка, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников; странности BASE (`*From:*` дважды, пробел в конце `*From:* city, region `, `TypeError` на ответе-массиве,
  `<@>` при пользователе Slack без `id`) — данные, не чинить.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10K_CACHE=$HOME/.cache/chaskiq-r10k-ci bash docs/specs/fork-updates-r10k-probes/rspec_gate_r10k.sh'`

- **AC-002** — пути и байты: изменены ровно slack/api.rb и снимок (новый обычный файл), новая спека, todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; api.rb и снимок побайтно равны BASE с двумя патчами, спека — побайтная копия r10k_spec.rb; todo = BASE без четырёх строк slack/api.rb блоков AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10k-probes/r10k_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: снимок дерева побайтно равен выводу генератора постановщика на коде BASE (50 случаев); у каждого случая есть пример новой спеки, зелёный на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 42 мутантов r10k_config.json (текст найден ровно один раз) роняет пример, не загрузку.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10K_CACHE=$HOME/.cache/chaskiq-r10k-ci bash docs/specs/fork-updates-r10k-probes/r10k_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; у AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity 0 офенсов в slack/api.rb; ни у одного копа ни в одном файле (новая спека тоже) офенсов не больше, чем на BASE; BASE содержит настройку К1; итог упал ровно на измеренные 6.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10K_CACHE=$HOME/.cache/chaskiq-r10k-ci bash docs/specs/fork-updates-r10k-probes/r10k_backlog_probe.sh $B > tmp/r10k-backlog.txt; rc=$?; cat tmp/r10k-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 6)}" tmp/r10k-backlog.txt'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10k-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимка добавляет ровно снимок (= патч) и спеку (= копия r10k_spec.rb), api.rb = BASE; коммит кода меняет ровно api.rb = BASE + патч; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10k после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10k-probes/r10k_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10k-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "93f5a3da4ee25bfd74983448cd060e72ebaacc7df2fc9ce3ca65c2be3375dd90  docs/specs/fork-updates-r10k-probes/examples_base.txt" "3d63bc2c7bfd3862b3fa5be1d0462e579de9dbe5efa983c44205d6c405ba1444  docs/specs/fork-updates-r10k-probes/pending_allowed.txt" "9d3dd510e338ce69ba4815909183c0367fcc91d0178d9cea421d4b991690e5c9  docs/specs/fork-updates-r10k-probes/r10k_backlog_probe.sh" "cec1b34891f2092ce729b80bca82d4562697be751fe6e902ae4868443d87828e  docs/specs/fork-updates-r10k-probes/r10k_cases.json" "50675fd1026a498a81b9bf76320d1cfd84a038be482ad56154a07aec5a9725d8  docs/specs/fork-updates-r10k-probes/r10k_config.json" "18ece54d4a92276e29bdad0cfe7068ec5b4721368ea56b3dfa2909a9131452b4  docs/specs/fork-updates-r10k-probes/r10k_golden.patch" "301681f2e3740658c25cb715028f8bc9a040ca8ba7f1efb7a9f088784b20094e  docs/specs/fork-updates-r10k-probes/r10k_golden_spec.rb" "66447c070a013be46ca5968eeca23e50fc213209e34afd14a5a4159cbe703f82  docs/specs/fork-updates-r10k-probes/r10k_probe.py" "48f79cf7f60fa2bf858d33883987eb571396f082dbd8558431802fe5062c40c6  docs/specs/fork-updates-r10k-probes/r10k_rewrite.patch" "7f4a6b456b7621e5be91fb4a77ce79e1e28ab8b7ef9e3089321330051dfed86d  docs/specs/fork-updates-r10k-probes/r10k_sentinel.rb" "40ff6d7a6239012b3e15170d7d81e74e4572882725171cdfba16a7b6ae8de934  docs/specs/fork-updates-r10k-probes/r10k_spec.rb" "c747da7dfc6beb86b0885e11584020cdee5dbfa492fb113007cf51305c30ee7b  docs/specs/fork-updates-r10k-probes/r10k_tests.rb" "e173158e384b48d5153e497b315c7c0a71efc1adee7f9676483ac207f2750e5d  docs/specs/fork-updates-r10k-probes/r10k_tests_gate.sh" "a26a2c23eb72e94ad58d314d116b0a8ce0c83d45864912ee29e2c551061c46b9  docs/specs/fork-updates-r10k-probes/rspec_gate_r10k.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10k-probes/source_scan.py" "b9c7d8875e8b7dfc1ad014e90bc936f7208a9c4a384eaa93175c0b1348e3e0fe  docs/specs/fork-updates-r10k-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10K paths without
the change`, `is not BASE + r10k_golden.patch, r10k_rewrite.patch`, `is not a byte-for-byte copy of r10k_spec.rb`);
AC-003 красный (`no examples ran`, мутанты «survived» — спеки ещё нет, текст K42 на коде BASE не найден);
AC-004 красный (`1 offenses left in the files of this milestone` у трёх копов, `total did not go down: BASE 77, tree
77`); AC-006 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10k-ci`).** Граница: клон от коммита спеки поверх
46aa8d16 (upstream — коммит спеки) — AC-001 (1427 примеров, 0 failures), AC-005, AC-007, AC-008, AC-009 rc=0; AC-002,
AC-003, AC-004, AC-006 красные ровно с сообщениями выше. Сборка по разделу 5: все 9 критериев зелёные за 16 мин
(AC-001 — 1477 примеров, 0 failures, 30 pending; AC-003 — `R10K GOLDEN PASS 50 cases`, `R10K MUTANTS PASS 42/42
killed`, ≈ 9 мин; AC-004 — `backlog without todo: BASE 77, tree 71`, `drop: 6`; AC-007 — 2 файла). Порченая правка
поверх сборки (лишним коммитом): в снимке `thread_ts` `171.1` → `171.2` в одном теле запроса — AC-002 (`is not BASE +
r10k_golden.patch, …`), AC-003 (пример `notify_message agent content` красный на дереве и на BASE, `golden: … is not the generator's output on BASE
(first difference at byte 66549)`), AC-006 (`extra commit after the changelog commit`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10k.md --exclude "docs/specs/fork-updates-r10k-probes/**" --exclude spec/fixtures/slack/block_kit_payloads.json --context "chaskiq fork-updates-r10k: RuboCop-выбросы MessageApis::Slack::Api (thread_head Abc 36; notify_message Abc 65, Cyc 23, 45 строк, Perceived 25; attachment_block Abc 31) разбиты без изменения поведения — thread_head: thread_intro_block, participant_fields_block, pick_agent_block; notify_message: replied_section (общий с replied_block), event_section + assignee_mention (users.lookupByEmail), post_thread_message (chat.postMessage с теми же опциями и порядком ключей тела); attachment_block: attachment_file + fetch_attachment под тем же rescue, первый сбой → nil. Снимок spec/fixtures/slack/block_kit_payloads.json (50 случаев, вывод старого кода: результат, каждый HTTP-запрос с сырым телом, аргументы direct_upload; исключён из ревью как данные) и спека, сверяющая каждый случай с WebMock (зелёная на BASE и после, 42 мутанта); спека не читает исходники как текст; только чтение"`

Исключения (снимок — данные генератора, его побайтно проверяет AC-003):

REVIEW_EXCLUDE: docs/specs/fork-updates-r10k.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10k-probes/**
REVIEW_EXCLUDE: spec/fixtures/slack/block_kit_payloads.json

Контекст ревьюеру: другой порядок вычислений с побочными эффектами (`format_user_name` автора пропущен для блоков и
событий, запрос `users.lookupByEmail` после поиска треда), `username` не того, другой порядок ключей тела
`chat.postMessage`, потерянный `nil` в `thread_head`, `rescue` в `attachment_block`, охватывающий больше или меньше
(`file[:url]` при `nil`), `next` вместо `return nil` при сбойном файле, иной `replied_section` для пустых данных
(`replied_block` → `nil`, `notify_message` → `"*replied*: "`); спека, которая сверяет не всё значение или запросы, или
читает исходник. Код, снимок и спеку править нельзя (AC-002, AC-008) — замечание по месту решает постановщик
(раздел 9); заход исправлений тогда пустой, FINAL_SHA = REVIEW_SHA.

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10k.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10k.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после шагов 1–4 AC-004/AC-005
  красные (офенс остался, вырос в другой паре, разница итогов не 6, нет `base_requires` К1) — дефект спеки;
- `R10K GOLDEN` красный (снимок ≠ вывод генератора на BASE) или пример красный на BASE при спеке, побайтно равной
  `r10k_spec.rb`, — дефект спеки, приложи вывод;
- пример зелёный на BASE и красный на дереве (патч меняет поведение) — пример и вывод: это дефект патча, не спеки;
- мутант выжил при спеке, побайтно равной `r10k_spec.rb`, — id и вывод (эквивалентный мутант — дефект спеки);
  читать исходник, чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл расхождение поведения патча с BASE — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, снимка и существующих спек, правка пробников, патчей и мутантов, `pending`/`skip`,
чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на 46aa8d16 (`git apply` патчей `r10h1_golden` + `r10h1_rewrite`, `r10h2_golden` + `r10h2_rewrite` (спека
`r10h2` в `main` ещё не закоммичена — взяты файлы рабочего дерева), `r10i_snapshots` + `r10i_rewrite` и обоих патчей
`r10k` в порядках h1,h2,i,k / k,h1,h2,i / i,k,h2,h1: все чисты):

- **Код.** `r10h1` — `content_showcase/presenter.rb`, `r10h2` — `inbox_sections/presenter.rb`, `r10i` —
  `dialog360/presenter.rb`, их снимки — `spec/fixtures/presenters/**`, `spec/fixtures/dialog360/**`. Файлов этой вехи
  ни одна не трогает. Позже `r10o` (`block_manager.rb`, `dante`) меняет то, что зовёт `blocks_transform`, — снимок
  `r10k` (случаи с контентом) станет её характеризацией; `r10l`/`r10m` — другие адаптеры.
- **`.rubocop_todo.yml`.** `r10k` убирает 4 строки `slack/api.rb`. Соседи по блокам: `CyclomaticComplexity` —
  строка прямо над `slack/api.rb` — `inbox_sections` (`r10h2`), над ней — `dialog360/presenter.rb` (`r10i`);
  `PerceivedComplexity` — над `slack/api.rb` `inbox_sections` (`r10h2`), над ней `content_showcase` (`r10h1`);
  `AbcSize` и `MethodLength` — без соседей из очереди (К1 влита, AC-004 проверяет её на BASE). Скрипт шага 4
  текстовый — на любом BASE даёт верный итог; но ветка, снятая с BASE до
  влития `r10h2` (или `r10h1`/`r10i` после неё), при слиянии даст конфликт соседних строк todo (решение — обе строки
  удалить; AC-002/AC-006 считают todo от своего BASE). Ставить последовательно, перенося BASE; блоки не пустеют.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Что перемерить при переносе BASE** — раздел 2, п. 2 (число `6` в AC-004 не меняется, меняются только итоги).
- Мутационный прогон противоположным исполнителем (cx) — после 2026-11-22 11:39Z, по новой спеке вехи.
