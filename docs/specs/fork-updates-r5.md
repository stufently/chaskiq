# fork-updates-r5 — бэклог RuboCop, шаг 5: дубли методов, `x op x` и `URI.open` — поведение зафиксировано тестами

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r5.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — первая часть R5 оттуда; остальные копы R5 —
  R5b, раздел 10).
- BASE_SHA: `8fce795c87fb27da7a3bd9a9ab4e9a9397b492ef` — HEAD `main` с влитыми R1–R4, R7a
  (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон (патчи раздела 5 обязаны применяться к новому BASE —
  это проверяет AC-002; если влит mut-m9-m14 — перегенерировать снимки rspec, раздел 2). Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; `accept_run.py`
  ищет квитанции по `base_sha` из `report.json`). Дифф вехи мал (≈ 10 КБ: 5 файлов кода, 7 новых
  спек, todo, CHANGELOG) — лимит `review_run.sh` в 100 КБ не задет.
- Исполнитель: Codex (`cx`). Независимую мутационную проверку потом гоняет Qwen (`qw2`).
- Цель: копы `Lint/DuplicateMethods`, `Lint/BinaryOperatorWithIdenticalOperands`, `Security/Open`
  — 0 офенсов, их блоки удалены из todo. Это **меняет поведение намеренно** в трёх местах (раздел 3);
  поведение каждого места решено в спеке, код правки задан патчем, а работа исполнителя — тесты:
  сначала характеризационные (зелёные на BASE, фиксируют сегодняшнее поведение), затем тест на
  каждую правку (красный на BASE, зелёный после), и все 14 мутантов постановщика убиты.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r5`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid, без sudo/root; на хост ничего не ставить. Всё через образ
  `bin/ci-local` (Ruby 4.0.10). Свой кэш: `$HOME/.cache/chaskiq-r5-ci`.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r5-ci` — копия `chaskiq-r4-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r4-ci $HOME/.cache/chaskiq-r5-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE; если менялся `spec/` (влит mut-m9-m14) —
   перегенерировать список примеров
   `CHASKIQ_R5_CACHE=$HOME/.cache/chaskiq-r5-ci bash docs/specs/fork-updates-r5-probes/rspec_gate_r5.sh --write-base`
   на чистом checkout `main`; проверить, что имена семи новых файлов спек (раздел 5) не заняты.
   Сейчас в снимках — список примеров `main` 4a749faa (675 примеров, 30 pending); с тех пор `spec/`
   менял только R3 (магический комментарий), имена примеров те же.
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r5-probes
export CHASKIQ_R5_CACHE=$HOME/.cache/chaskiq-r5-ci
bash $P/rspec_gate_r5.sh                      # полный rspec через bin/ci-local, ~10 мин
python3 -I $P/r5_probe.py tree $B             # пути, код = BASE + патчи, todo (~5 с)
bash $P/r5_tests_gate.sh $B                   # характеризация/правки на BASE и дереве + 14 мутантов (~8 мин)
bash $P/r5_backlog_probe.sh $B                # rubocop без todo: три копа 0, остальные не выросли (~3 мин)
python3 -I $P/r5_probe.py commits $B          # коммиты по порядку, каждый проверен (~5 с)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r5-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

Отдельный прогон одного файла спек (в образе, с postgres/redis) проще всего делать через
`r5_tests_gate.sh` — он гоняет ровно семь файлов на копии `git archive HEAD`, поэтому сначала
закоммитить; либо `bin/ci-local --only rspec --rspec-args "<файл>"`.

## 3. Места, поведение и почему

Строки — по BASE. «Живое» определение — последнее (Ruby переопределяет метод молча).

1. **`app/models/plan.rb` — `Plan#features=`** (`Lint/DuplicateMethods`): `attr_accessor ... :features`
   (стр. 6) и `def features=(f)` (стр. 27). Живое — `def`: оборачивает каждый хеш в `Plan::Feature`.
   **Поведение не меняется**: из `attr_accessor` убран `:features`, добавлен `attr_reader :features`.
2. **`app/models/role.rb` — `Role#avatar_url`**: `delegate :avatar_url, to: :agent` дважды (стр. 14 и
   25), оба одинаковые. **Не меняется**: второй удалён.
3. **`app/services/app_user_dashboard.rb` — `AppUserDashboard#conversations`**: два одинаковых
   определения (стр. 16 и 28). **Не меняется**: первое удалено. (Класс сейчас нигде не вызывается.)
4. **`app/models/plan.rb:42` — `count >= count`** (`Lint/BinaryOperatorWithIdenticalOperands`).
   Сегодня `limit_reached?` для числового `count` всегда `true` (кроме `"unlimited"`), для фичи,
   которой нет в плане, — тоже `true`. Явный баг (переменная лимита `c` вычислена и не использована).
   **Правка**: лимит достигнут, когда `count >= limit`; `"unlimited"` и фича вне плана — без лимита
   (`false`, как `enabled?`, который считает отсутствующую фичу разрешённой). Вызывающих в коде нет —
   риск для работающих путей нулевой.
5. **`app/services/fetch_link_card_service.rb:124` — `x.value || x.value`**. Сегодня ищется только
   `<meta property=…>`; `meta_property(page, "description")` поэтому никогда не находит стандартный
   `<meta name="description">`, а `<meta property="og:title">` без `content` роняет весь вызов
   `NoMethodError` (`nil.value`). Второй операнд явно должен был быть поиском по `name`.
   **Правка**: значение `content` у `<meta property=P>`, иначе у `<meta name=P>`; узел без `content`
   пропускается. Что изменится наблюдаемо: описание карточки берётся из `<meta name="description">`,
   если нет `og:description`; страница с пустым `og:title` даёт карточку (заголовок из `<title>` или
   `<meta name="og:title">`) вместо исключения. Если оба есть — побеждает `property` (как сейчас).
6. **`app/models/campaign.rb:138` — `URI.open(url)`** (`Security/Open`). URL строится из собственного
   `HOST` приложения (`/apps/<key>/premailer/<id>`), не из ввода пользователя, и это объект
   `URI`, не строка, поэтому `|команда` невозможна; реальные дыры — без таймаута/лимита размера и с
   переходом по редиректу куда угодно (в т.ч. на `169.254.169.254`). **Правка**: `MessageApis::SafeDownload.fetch`
   (лимиты 15 МБ / 30 с / 3 редиректа, запрет приватных адресов) с `allow_own_host: true` (свой
   HOST в docker-сети бывает приватным — как сегодня, он работает) и `url_allowed` — только тот же
   origin (схема, хост, порт), редиректы тоже; нет страницы (HTTP-ошибка, блок, чужой origin,
   таймаут) — `Campaign::PremailerFetchError` (джоб падает и ретраится, как сегодня с
   `OpenURI::HTTPError`). Дальше без изменений: Roadie инлайнит CSS, относительные
   `rails/active_storage` картинки становятся абсолютными по HOST. `require "open-uri"` остаётся
   (его побочный эффект глобален — не трогаем). Кодировка: тело — двоичная строка; проверено, что
   Roadie/Nokogiri отдают UTF-8 и кириллица проходит (мутант с `force_encoding` выжил — значит,
   он ненаблюдаем, и в патче его нет).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r5-ci`) на
клоне BASE 8fce795c:

1. Патчи раздела 5 применяются к BASE по порядку; `rubocop` по пяти файлам — 0 офенсов трёх копов.
2. Черновик ровно по разделу 5 (спеки — образец постановщика, не обязательный текст): AC-001…AC-008
   зелёные; итоги — раздел 7.
3. `r5_tests_gate.sh` на черновике: 19 примеров зелёные на дереве; на BASE 8 характеризационных
   зелёные, каждый из 3 файлов правок красный; 14/14 мутантов убиты (мутант `force_encoding` выжил и
   из патча убран, раздел 3 п. 6).

Предположение: WebMock перехватывает и `open-uri` (BASE), и `Net::HTTP` из `SafeDownload` — так
работает существующий `spec/services/fetch_link_service_spec.rb`; характеризационная спека Campaign
зелёная на BASE (проверено), значит, перехват есть.

## 5. Что сделать

Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей, ровно в этом порядке. Код
приложения — **только** патчами из `docs/specs/fork-updates-r5-probes/` (`git apply <патч>`), руками
не править. Все спеки — НОВЫЕ файлы с этими именами (существующие спеки не трогать); в каждом
`# frozen_string_literal: true`, `require "rails_helper"`, HTTP — только WebMock (как
`spec/services/fetch_link_service_spec.rb`: `WebMock.enable!`/`disable!` в `around`, адреса через
`allow(MessageApis::SafeDownload).to receive(:resolve)`), HOST — `allow(Chaskiq::Config).to
receive(:get).with("HOST")`. Никаких `pending`/`skip`/`xit`.

1. `Add R5 characterization specs` — только четыре новых файла; код = BASE, все примеры зелёные на BASE:
   - `spec/models/plan_features_spec.rb` — `Plan.new(features: [хеши])`: `features` — массив
     `Plan::Feature` с теми же `name`/`count`; `enabled?` — по `active`, отсутствующая фича → `true`;
   - `spec/models/role_delegation_spec.rb` — `role.avatar_url` равен `role.agent.avatar_url`;
   - `spec/services/app_user_dashboard_spec.rb` — `conversations` пользователя: по одной строке на
     состояние, `id`/`label` = состояние (`nil` → `"unknown"`), `value` = число (разные числа у
     разных состояний), `color` вида `hsl(<n>, 70%, 50%)`;
   - `spec/models/campaign_premailer_spec.rb` — `clean_inline_css(URI)` при собственном HOST, который
     резолвится в ПРИВАТНЫЙ адрес: CSS из `<style>` проинлайнен в `style=` элемента, кириллица цела,
     `/rails/active_storage/...` → `<HOST>/rails/...`, внешняя картинка не тронута; редирект в
     пределах своего origin выполняется; HTTP 500 → исключение (`StandardError`).
2. `Remove duplicate method definitions` — `git apply r5_dedupe.patch`; спек не добавлять.
3. `Fix Plan#limit_reached? comparison` — `git apply r5_limit.patch` + `spec/models/plan_limit_spec.rb`:
   ниже лимита → `false`, ровно на лимите → `true`, выше → `true`, `"unlimited"` → `false`, фича вне
   плана → `false`.
4. `Fall back to meta name in link cards` — `git apply r5_meta.patch` +
   `spec/services/fetch_link_card_meta_spec.rb` (через `FetchLinkCardService#call`, OEmbed →
   `NotFound`): при `property` и `name` с разными значениями берётся `property`; без `property` —
   `name` (`description`); `<meta property="og:title">` без `content` → заголовок из `<title>`, вызов
   не падает.
5. `Fetch premailer HTML via SafeDownload` — `git apply r5_premailer.patch` +
   `spec/models/campaign_premailer_fetch_spec.rb`: редирект на другой origin (публичный адрес) →
   `Campaign::PremailerFetchError`, запроса туда нет; приватный адрес не своего HOST →
   `PremailerFetchError`, запроса нет; HTTP 500 → именно `PremailerFetchError`.
6. `Drop R5 cops from RuboCop todo` — из `.rubocop_todo.yml` удалить ровно три блока этих копов
   (с их строками-комментариями и пустой строкой-разделителем), больше ничего.
7. `Note fork-updates-r5 in changelog` — новый раздел «## <дата> — fork-updates-r5» сразу после
   строки `# Changelog` (текст BASE ниже не меняется): Fixed — `limit_reached?`, meta name в
   карточках, premailer через SafeDownload; Removed — дубли трёх методов. Только `CHANGELOG.md`;
   после него — только коммиты, меняющие один `CHANGELOG.md` по тому же правилу.
8. В `report.json`: `note` AC-003 — строки `R5 TREE PASS …`, `R5 BASE PASS …`, `R5 MUTANTS PASS …`;
   AC-004 — строка `backlog without todo: …`.

Убивать мутантов (`r5_config.json`, `mutants`) — задача спек: если мутант выжил, усиливай спеку его
места (не код, не мутанта). Тест на отказ проверяй по причине: в спеках правок `raise_error` — с
классом `Campaign::PremailerFetchError`, а «запроса не было» — `assert_not_requested`.

## 6. Не трогать

- Всё, кроме пяти файлов кода (только патчами), семи новых файлов спек, `.rubocop_todo.yml`,
  `CHANGELOG.md`. Существующие файлы `spec/` не менять (параллельно идёт mut-m9-m14, он добавляет
  свои файлы в `spec/`).
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`,
  `config/`, `MessageApis::SafeDownload`.
- Никаких `# rubocop:` директив, `pending`/`skip`.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R5_CACHE=$HOME/.cache/chaskiq-r5-ci bash docs/specs/fork-updates-r5-probes/rspec_gate_r5.sh'`

- **AC-002** — пути и код: изменены ровно пять файлов кода, семь новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с четырьмя патчами по порядку; todo = BASE без блоков трёх копов; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5-probes/r5_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры семи файлов зелёные на коде дерева; на коде BASE характеризационные зелёные, а в каждом из трёх файлов правок есть упавший пример, ошибок вне примеров нет; каждый из 14 мутантов r5_config.json (текст мутанта найден ровно один раз) роняет пример своих спек, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5_CACHE=$HOME/.cache/chaskiq-r5-ci bash docs/specs/fork-updates-r5-probes/r5_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Lint/DuplicateMethods, Lint/BinaryOperatorWithIdenticalOperands и Security/Open 0 офенсов; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R5_CACHE=$HOME/.cache/chaskiq-r5-ci bash docs/specs/fork-updates-r5-probes/r5_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r5-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно четыре спеки при коде BASE; каждый коммит правки оставляет код = BASE + патчи до своего включительно и добавляет ровно свою спеку; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r5 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r5-probes/r5_probe.py commits $B'`

- **AC-007** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "833cf086cef98f6ab2ab4579e0490ba96c96e681e7ad07e6ad924b5e189bd461  docs/specs/fork-updates-r5-probes/r5_probe.py" "c717565cb4861244380f8a4d20e79511e4d226e0487cdcef29dcfaef22b50025  docs/specs/fork-updates-r5-probes/r5_config.json" "50ea4dd3a12f5a82481b4e0d444d24f6a3fdb7c3950a9a62738cc7c9aabfec94  docs/specs/fork-updates-r5-probes/r5_tests.rb" "10db87d1dadb43404e2644450bc957ebd9809314cc713b5f5a3570664d12222d  docs/specs/fork-updates-r5-probes/r5_tests_gate.sh" "496d59d4c147430ed8ad3adec752b4fbe7710dd15292eeb91f139a547f4563f8  docs/specs/fork-updates-r5-probes/r5_backlog_probe.sh" "6a70d6f475a1b73711187e3f82ac7f9d8a69f898ee0e170bd7a274a0b2447276  docs/specs/fork-updates-r5-probes/r5_dedupe.patch" "8de6079009ef4a794e3325446ede2278fb06744df97f468421ea25494fc58ef2  docs/specs/fork-updates-r5-probes/r5_limit.patch" "ef67b505c8bfc484878bf1547862190e50d0952c349fdb37d6af232831a39402  docs/specs/fork-updates-r5-probes/r5_meta.patch" "6661a5a6f72e14668dc8322ceba6cb1b7daef48f5df2d0304fb4c40fb4584479  docs/specs/fork-updates-r5-probes/r5_premailer.patch" "02120d94f34048f530c3051bd4f625d697a90db7fb34fcccb043011187518f7c  docs/specs/fork-updates-r5-probes/rspec_gate_r5.sh" "23226ecbe2228a86b8984133f866fa52a33e0d01ea8a4601c1b578b63c9a8b57  docs/specs/fork-updates-r5-probes/r5_sentinel.rb" "b6cff89254e380efdc46f5b196fc187958cdd1bf798bb1d8cb8b3d756dd84c32  docs/specs/fork-updates-r5-probes/examples_base.txt" "dab2103621c29999d87706eaff91708e1caa30375f5a5b8f849ee5595d426a6e  docs/specs/fork-updates-r5-probes/pending_allowed.txt" "ec396f65c66825d52c74e1d008fabd9dbcf7c88c79202f40eed5890792883476  docs/specs/fork-updates-r5-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008 зелёные; AC-002 красный (`R5 paths
without the change`); AC-003 красный (спек нет — `no examples ran`, тексты мутантов `campaign.rb` не найдены); AC-004 красный (`… offenses left`);
AC-006 красный (`missing commits`).

Проверено на черновике ровно по разделу 5 (свежий клон с закоммиченными спекой и пробниками):
AC-001…AC-008 зелёные — rspec 694/0/30 (19 новых примеров), сторож 666; AC-003 — `R5 TREE PASS 19
examples`, `R5 BASE PASS 8 char / 3 fix failing`, `R5 MUTANTS PASS 14/14 killed`; AC-004 — без todo
BASE 1583 → дерево 1576. Плохие правки (каждая → FAIL названного критерия):
- AC-002 и AC-006: ручная правка кода (`limit <= count` вместо патча) — «is not BASE + …»;
  `# rubocop:disable` в новой спеке — «rubocop directive added».
- AC-002: правка существующей `spec/models/role_spec.rb` — «not an R5 path».
- AC-006: дедуп кода внутри характеризационного коммита — «changes … expected …», «is not BASE +
  nothing», нет коммита `Remove duplicate method definitions`.
- AC-003: характеризационная спека, которая фиксирует ПРАВКУ (`limit_reached?` → `false`), — «is failed
  on BASE»; спека правки без примеров ниже лимита/`unlimited`/вне плана — «no example fails on BASE»
  и выжили M03, M04, M05.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r5.md --exclude "docs/specs/fork-updates-r5-probes/**" --context "chaskiq fork-updates-r5: дубли методов (Plan#features=, Role#avatar_url, AppUserDashboard#conversations) удалены без смены поведения; Plan#limit_reached? сравнивал count с собой; meta name в link cards; premailer через SafeDownload вместо URI.open; характеризационные спеки + спеки правок; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r5.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r5-probes/**

Контекст ревьюерам: проверить, что спеки проверяют поведение (а не реализацию), что характеризация
действительно фиксирует BASE, и что правка `clean_inline_css` не ломает рассылку (свой HOST в
приватной сети, редирект в пределах origin).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r5.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r5.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патча строгий RuboCop не зелёный — дефект
  спеки;
- характеризационная спека не может быть зелёной на BASE, не проверяя поведение неверно (поведение
  BASE не то, что описано в разделе 3), — приложи вывод;
- мутант не убивается спекой, проверяющей описанное в разделе 3 поведение (мутант эквивалентен) —
  id мутанта и почему; не менять мутанта и код;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода приложения, правка существующих спек, правка пробников/патчей,
`pending`/`skip`, глушить вывод и коды возврата.

## 10. Стыки

- R5b (следующая веха плана): остальные копы R5 — `Lint/UnreachableCode` (api_controller.rb),
  `Lint/UselessOr` (audit.rb), `Lint/MisplacedMagicComment` (paddle.rb), `Lint/BooleanSymbol`
  (схемы плагинов — значения, руками), `Lint/Void`, `AssignmentInCondition`,
  `NonLocalExitFromIterator`, `InterpolationCheck` и мелочь; тот же формат: решение по каждому месту,
  характеризация, тест правки, мутанты.
- `require "open-uri"` в `campaign.rb` и `client_tester_controller.rb` — убрать отдельно, после
  проверки, что никто не полагается на его глобальный эффект.
- `AppUserDashboard` нигде не вызывается — кандидат на удаление (решение владельца).
