# fork-updates-r4 — бэклог RuboCop, шаг 4: вложенные `module`/`class` вместо `A::B`, разрешение констант не меняется

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r4.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — R4 оттуда). R2b и R3b плана идут ПОСЛЕ:
  это ручной разбор каждого места (тип получателя, SQL, ответ API) с тестом, механически не
  проверяется; R4 — первая по порядку механически проверяемая.
- BASE_SHA: `1ea7453da7d9739341b728f304d7309a57ba5605` — HEAD `main` с влитыми R1, R2, R3, R7a
  (Ruby 4.0.10, RuboCop 1.92.3, Prism 1.8.2).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; `accept_run.py`
  ищет квитанции по `base_sha` из `report.json`).
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, `qw2`). **`spec/` веха не трогает** (параллельно идёт mut-m9-m14, он меняет только `spec/`).
- Цель: 65 файлов из секции `Style/ClassAndModuleChildren` todo переведены автокорректом из
  `class A::B` во вложенную форму; секция todo сокращена до пяти файлов `KEEP`
  (`twilio_phone/api.rb` — там вложение меняет разрешение константы `Twilio`; четыре презентера с
  `template.result(binding)` — константы в строках ERB проверка не видит); каждый файл отличается
  только вложением и раскладкой (дерево Prism то же после склейки `module A; class B` в `A::B`,
  комментарии те же); каждое неквалифицированное имя константы в этих файлах разрешается в
  booted-приложении в тот же объект, что и до правки (и после загрузки плагинов), суперклассы и
  предки определённых классов те же; полный rspec зелёный тем же списком примеров; строгий RuboCop
  зелёный.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r4`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid, без sudo/root; на хост ничего не ставить. Всё через образ
  `bin/ci-local` (Ruby 4.0.10). Свой кэш: `$HOME/.cache/chaskiq-r4-ci`.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r4-ci` — копия `chaskiq-r3-ci` (уже создан); если нет —
   `cp -a $HOME/.cache/chaskiq-r3-ci $HOME/.cache/chaskiq-r4-ci`.
2. Если `main` ушёл вперёд от BASE_SHA: перенести BASE, прогнать раздел 5 на черновике и
   `resolve_gate_r4.sh` (список `KEEP` в `r4_equiv_probe.py` может вырасти); если влит mut-m9-m14 или
   иначе изменились тесты — перегенерировать список примеров:
   `CHASKIQ_R4_CACHE=$HOME/.cache/chaskiq-r4-ci bash docs/specs/fork-updates-r4-probes/rspec_gate_r4.sh --write-base`
   на чистом checkout `main`. Сейчас в снимках — список примеров `main` 4a749faa (675 примеров,
   30 pending, без warning-строк); с тех пор `spec/` менял только R3 (магический комментарий в 36
   файлах), имена примеров те же.
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r4-probes
export CHASKIQ_R4_CACHE=$HOME/.cache/chaskiq-r4-ci
bash $P/rspec_gate_r4.sh                      # полный rspec через bin/ci-local, ~10 мин
python3 -I $P/r4_equiv_probe.py $B            # форма правки, todo, границы (~30 с)
bash $P/resolve_gate_r4.sh $B                 # разрешение констант, плагины, предки BASE/дерево (~4 мин)
bash $P/r4_backlog_probe.sh $B                # rubocop без todo: коп 0 вне KEEP, рост только из ALLOWED_GROWTH (~3 мин)
python3 -I $P/r4_commits_probe.py $B          # коммиты по порядку, каждый проверен (~30 с)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r4-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

## 3. Задача и почему

Секция `Style/ClassAndModuleChildren` todo BASE — 70 файлов (14 `app/controllers`, 4 `app/graphql`,
52 `app/services`; `spec/` нет), 70 офенсов (автокоррект делает 76 исправлений: в некоторых файлах
два класса). `rubocop -A --only Style/ClassAndModuleChildren`
переписывает `class A::B < C` в `module A` + `class B < C` (и глубже: `module Api; module V1; class X`),
затем `rubocop -a --only Layout` выравнивает отступы (252 `IndentationWidth`, 15
`AccessModifierIndentation`); после этого офенсов 0.

Чем это опасно: вложенная форма добавляет `A` (и `A::B` …) в лексическую область видимости
(`Module.nesting`). Неквалифицированное имя `X` внутри класса и в выражении суперкласса после правки
сначала ищется в `A`: если там есть свой `A::X`, имя молча начинает означать другое. И `module A`
падает `TypeError`, если `A` — класс. Две независимые проверки:

1. **Форма** (`r4_nest.rb shape`): на обеих сторонах `module P`, чьё тело — ровно одно определение
   класса/модуля с простым именем `N`, склеивается в определение `P::N`; деревья Prism без позиций
   равны (литералы точно; heredoc `<<-`, чьё содержимое сдвинул Layout, — отличие); магические
   комментарии, `__END__` и список ВСЕХ комментариев (текст, по порядку) те же — так что добавленный
   `# rubocop:disable` при оставленной компактной форме — DIFF; каждый файл `R4_FILES` обязан
   измениться. Плюс в изменённых файлах нет `Module.nesting`, `const_missing`, `@@`, `__LINE__`,
   `caller`, `eval(` по строке, `binding`, `ERB`/`Erubi`, `*_eval` по строке (проверено: нет;
   `redis.eval` — не Ruby `eval`).
2. **Разрешение констант** (`resolve_gate_r4.sh`): `r4_nest.rb refs` выписывает каждое
   неквалифицированное имя (`X`, голову `X::Y`; не `::X`, не имя определяемого класса), включая
   суперклассы, с цепочкой определений вокруг него на BASE (`class Agents::Auth0Controller`) и в
   дереве (`module Agents` > `class Auth0Controller`); `r4_resolve.rb` под `bin/rails runner`
   (test, после `eager_load!`) вычисляет имя внутри каждой цепочки на верхнем уровне и требует тот
   же объект (или тот же класс исключения). Самопроверка: затенённая в новом пространстве
   константа и `module` над классом — должны ловиться, обычное имя — нет. Дальше:
   - статически: для каждого пространства, которое цепочка дерева добавила (`MessageApis`, затем
     `MessageApis::Slack` …), константа `<пространство>::<Имя>`, определённая где-либо в исходниках
     `app/` и `lib/` (`r4_nest.rb defs`, загружена она или нет), должна существовать и быть тем же
     объектом, в который имя разрешается на BASE;
   - плагины: `config/initializers/before_start.rb` в server/console/sidekiq после `eager_load!`
     зовёт `ChaskiqBoot.plugin_autoloader` → `Plugin.save_all_plugins`: файлы плагина из БД
     пишутся в `app/services/message_apis/<plugin>/` и грузятся `require_dependency`. В test-среде
     таблица пуста, поэтому загрузка воспроизведена без записи: каждый `*.rb` из
     `app/services/message_apis/*/` грузится `load` (надмножество `require_dependency`), затем все
     ссылки проверяются второй раз. Плагины из appstore, которых нет в репо, не видны никак — это
     граница проверки (раздел 4);
   - предки: `r4_resolve.rb ancestry` в двух отдельных процессах — в дереве и в полном checkout BASE
     (`git archive`) — выписывает для каждого класса/модуля, определённого в изменённых файлах,
     суперкласс, `ancestors` и `singleton_class.ancestors` по полным именам; дампы должны совпасть
     (суперкласс и миксины выбираются в момент определения).

На черновике (все 70 файлов) проверка 2 нашла настоящее изменение: в
`app/services/message_apis/twilio_phone/api.rb` имя `Twilio` (гем twilio-ruby) внутри
`module MessageApis` стало бы `MessageApis::Twilio` (пакет соседнего мессенджера). Этот файл —
`KEEP`: остаётся компактным и в todo; исправлять его (`::Twilio` + тест) — отдельная правка вне
автокорректа (R7 плана).

Ещё четыре `KEEP` — файлы, которые вычисляют ERB-шаблон с `template.result(binding)`:
`article_search/presenter.rb`, `calendly/presenter.rb`, `twilio_phone/presenter.rb`,
`ui_catalog/presenter.rb`. Константы внутри строк шаблона разрешаются в лексической области метода,
а `r4_nest.rb refs` их не видит (строка, не код) — эти файлы остаются компактными, пока шаблоны не
разобраны отдельно (R7 плана).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r4-ci`) на
клоне BASE 1ea7453d:

1. Автокоррект: 76 исправлений в 70 файлах; после `-a --only Layout` — 0 офенсов под todo; без todo
   `Layout/LineLength` +1 в трёх файлах, уже исключённых в todo этого копа (`hooks_controller.rb`,
   `slack/api.rb`, `ui_catalog/presenter.rb`). `ui_catalog/presenter.rb` теперь в `KEEP`, поэтому
   разрешённый рост — ровно `ALLOWED_GROWTH` в `r4_equiv_probe.py`: `Layout/LineLength`
   `app/controllers/api/v1/hooks_controller.rb` 2 → 3 и `app/services/message_apis/slack/api.rb`
   4 → 5 (оба остаются исключёнными в todo до R8); ничего больше.
2. `r4_nest.rb shape` — 70 из 70 SAME; `refs` — 354 уникальных ссылки (по файлу).
3. `resolve_gate_r4.sh` на всех 70: eager load OK, одна разница — `Twilio` в `twilio_phone/api.rb`
   (п. 3 раздела 3). С `KEEP` — см. п. 4.
4. Черновик ровно по разделу 5 на свежем клоне с закоммиченными спекой и пробниками (коммит todo,
   коммит автокорректа — 65 файлов, коммит CHANGELOG): AC-001…AC-008 все зелёные. rspec 675/0/30,
   сторож 647; AC-002 — 65 SAME (с проверкой комментариев); AC-003 — `R4 STATIC SHADOW CHECK 0
   candidates` (540 определений в `app/`+`lib/`), `R4 PLUGIN LOAD OK 38 files`,
   `R4 RESOLVE PASS 325 references, 2 passes`, два дампа `R4 ANCESTRY DUMP 136 constants`
   совпали; AC-004 — без todo BASE 1646 → дерево 1583, рост ровно `ALLOWED_GROWTH`;
   `bin/ci-local --only rubocop` OK. Плохие правки — раздел 7.

Предположение: выражения, которые разрешаются только во время выполнения пути, которого нет при
загрузке (константа внутри `def`, вызываемого позже), разрешаются так же, как при вычислении имени в
той же лексической цепочке, — это и делает `r4_resolve.rb` (лексический поиск не зависит от
момента). Константы, определённые динамически ПОСЛЕ загрузки (в рантайме запроса), проверкой не
видны; в 65 файлах таких определений нет (`const_set` — не в этих файлах). Плагины appstore, которых
нет в репо (их код приходит из БД), могут добавить `MessageApis::<Имя>` и затенить имя в любом файле
под `module MessageApis` — так же, как они уже сейчас могут затенить имя в файлах, которые вложены с
BASE; проверка покрывает все плагины репо (статически и повторной загрузкой).

## 5. Что сделать

Все команды RuboCop — в образе `bin/ci-local` (`-v $PWD:/app`,
`-v $CHASKIQ_R4_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle`, `BUNDLE_PATH=/app/vendor/bundle`).
Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Коммит `Drop R4 cop from RuboCop todo`: `.rubocop_todo.yml` = `expected_todo()` из
   `r4_equiv_probe.py`: в блоке `Style/ClassAndModuleChildren` остаются только пять строк `KEEP`,
   больше ничего. `--auto-gen-config` запрещён. `.rubocop.yml` не меняется.
2. Коммит `Autocorrect Style/ClassAndModuleChildren`:
   `bundle exec rubocop -A --only Style/ClassAndModuleChildren`, затем
   `bundle exec rubocop -a --only Layout`. Ровно 65 файлов (`R4_FILES`), `KEEP` не тронут.
3. После коммита — `bash docs/specs/fork-updates-r4-probes/resolve_gate_r4.sh $B`; FAIL с новой
   константой — остановиться (раздел 9), не править код руками.
4. `bundle exec rubocop` по дереву — 0 офенсов; `CHANGELOG.md` — новый раздел
   «## <дата> — fork-updates-r4» → «Changed» сразу после строки `# Changelog` (текст BASE ниже не
   меняется): 65 файлов во вложенную форму (RuboCop), разрешение каждой константы и предки классов
   проверены, пять файлов `KEEP` оставлены компактными. Коммит ровно `Note fork-updates-r4 in changelog`,
   только `CHANGELOG.md`; после него — только коммиты, меняющие один `CHANGELOG.md` по тому же правилу.
5. В `report.json`: `note` AC-002 — строка `files:`; AC-003 — строка `R4 RESOLVE PASS …`; AC-004 —
   строка `backlog without todo: …`.

## 6. Не трогать

- Всё, кроме `.rubocop_todo.yml`, `CHANGELOG.md` и 65 файлов `R4_FILES`. **`spec/` не трогать.**
  `KEEP` (`twilio_phone/api.rb` и четыре ERB-презентера) не трогать.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`,
  `config/`.
- Никаких ручных правок Ruby, `::`-префиксов «на всякий случай», `# rubocop:` директив.
- `docs/specs/**` — не править (AC-007, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R4_CACHE=$HOME/.cache/chaskiq-r4-ci bash docs/specs/fork-updates-r4-probes/rspec_gate_r4.sh'`

- **AC-002** — форма и границы: самопроверка r4_nest.rb проходит; изменены только todo, CHANGELOG и файлы R4_FILES (все 65, каждый изменён), обычные файлы с прежним git-режимом; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл SAME (дерево Prism то же после склейки вложенных module, комментарии те же — никаких добавленных rubocop-директив); todo = BASE со списком копа, сокращённым до KEEP; .rubocop.yml не тронут; в файлах нет Module.nesting, const_missing, @@, __LINE__, caller, eval по строке, binding, ERB/Erubi, *_eval по строке.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r4-probes/r4_equiv_probe.py $B'`

- **AC-003** — разрешение констант: eager load приложения прошёл (трижды: дерево, дерево, checkout BASE); самопроверка резолвера проходит; каждое неквалифицированное имя константы изменённых файлов в лексической цепочке дерева даёт тот же объект (или то же исключение), что в цепочке BASE, — до и после повторной загрузки всех файлов плагинов app/services/message_apis/*/; ни одна константа <новое пространство>::<Имя>, определённая в исходниках app/ и lib/, не затеняет имя; суперкласс, ancestors и singleton ancestors каждого класса/модуля изменённых файлов по полным именам совпадают в двух отдельных процессах (checkout BASE и дерево).
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R4_CACHE=$HOME/.cache/chaskiq-r4-ci bash docs/specs/fork-updates-r4-probes/resolve_gate_r4.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Style/ClassAndModuleChildren 0 офенсов вне KEEP; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE, кроме ровно ALLOWED_GROWTH из r4_equiv_probe.py — Layout/LineLength app/controllers/api/v1/hooks_controller.rb 2→3 и app/services/message_apis/slack/api.rb 4→5 (оба изменены и исключены из этого копа в todo; рост обязан совпасть точно, иначе FAIL), больше ничего; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R4_CACHE=$HOME/.cache/chaskiq-r4-ci bash docs/specs/fork-updates-r4-probes/r4_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r4-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно: ровно в порядке раздела 5; коммит todo меняет только todo и равен ожидаемому тексту; коммит автокорректа меняет ровно 65 файлов R4_FILES и каждый SAME (с теми же комментариями) (родитель → коммит); коммит CHANGELOG и последующие — только CHANGELOG, который равен BASE с одним блоком про fork-updates-r4 после «# Changelog»; ни один коммит не меняет git-режим или тип пути.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r4-probes/r4_commits_probe.py $B'`

- **AC-007** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "1715ec05b57249dc7e764a59634f8f9a3371e0d6189f992180265ec93e82219e  docs/specs/fork-updates-r4-probes/r4_nest.rb" "b02665ca95839805dc950da1784bd26c9782c934272a7d313ac5653003382810  docs/specs/fork-updates-r4-probes/r4_resolve.rb" "f600b86451e17e03da81340c02c92ff28e777ffacb07deb234dd15a0b9372f98  docs/specs/fork-updates-r4-probes/resolve_gate_r4.sh" "01302640eb32bf1cacca603f68383fe0f62893b784f2a7d4ba79e4421f484b82  docs/specs/fork-updates-r4-probes/r4_equiv_probe.py" "9be649992959f8f4573f8f202969685d8d100938a1e4a863fec575f9c77d5d95  docs/specs/fork-updates-r4-probes/r4_backlog_probe.sh" "a0ae61c0020d53f9e840091b34c0651c4f578e96d3f2fbcce28fc9c1878c4621  docs/specs/fork-updates-r4-probes/r4_commits_probe.py" "6fbe9020060f258b7bde1d5a5628b4ecc2a6e9282855ec80502ab3aabf9b1211  docs/specs/fork-updates-r4-probes/rspec_gate_r4.sh" "42526f77ad2762f56dcc92a8240653515171cf975afd094d8a2cbbe4714a321d  docs/specs/fork-updates-r4-probes/r4_sentinel.rb" "b6cff89254e380efdc46f5b196fc187958cdd1bf798bb1d8cb8b3d756dd84c32  docs/specs/fork-updates-r4-probes/examples_base.txt" "dab2103621c29999d87706eaff91708e1caa30375f5a5b8f849ee5595d426a6e  docs/specs/fork-updates-r4-probes/pending_allowed.txt" "ec396f65c66825d52c74e1d008fabd9dbcf7c88c79202f40eed5890792883476  docs/specs/fork-updates-r4-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008 зелёные; AC-002 красный (`files of the …
list without the change`); AC-003 красный (`no Ruby file changed since BASE`); AC-004 красный
(`ALLOWED_GROWTH … not observed`, `total did not go down`); AC-006 красный (`missing commits`).

Проверено на черновике (каждая правка → FAIL названного критерия):
- AC-002 и AC-003: автокоррект и `KEEP`-файла (`twilio_phone/api.rb`) — AC-002 «not a file of the
  list», AC-003 «`Twilio` … BASE Twilio, tree MessageApis::Twilio».
- AC-002: изменённый литерал; лишняя константа в новом `module Agents`; `chmod +x`; правка
  `spec/spec_helper.rb`; из todo выпала строка `KEEP`; `Module.nesting` в методе.
- AC-002 и AC-006: файл оставлен компактным, но получил `# rubocop:disable Style/ClassAndModuleChildren`
  — «DIFF … comments»; автокоррект ERB-презентера (`article_search/presenter.rb`) — AC-002 «not a
  file of the list» (и `binding`/`ERB` в списке запретов).
- AC-003: `lib/r4_shadow.rb` с `module MessageApis; I18n = :shadow; end` (не грузится Zeitwerk) —
  «I18n could resolve to MessageApis::I18n (defined in the source)» в четырёх файлах; суперкласс
  `ActionController::API` → `ActionController::Base` в `hooks_controller.rb` (голова та же, ссылки и
  разрешение те же) — «superclass/ancestors differ between BASE and the tree».
- AC-004: лишняя длинная строка в `dante/converter.rb` (исключён из LineLength в todo, но не в
  `ALLOWED_GROWTH`) — «Layout/LineLength … 4 offenses, BASE 3»; `slack/api.rb` вернули к BASE —
  «ALLOWED_GROWTH … 4 -> 5 not observed».
- AC-006: коммиты в обратном порядке; в коммите автокорректа не хватает файла; Ruby-правка в
  коммите CHANGELOG; `chmod +x` в коммите автокорректа, снятый в коммите CHANGELOG; опустошённый
  CHANGELOG; `.rubocop.yml` в коммите todo.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r4.md --exclude "docs/specs/fork-updates-r4-probes/**" --context "chaskiq fork-updates-r4: RuboCop -A Style/ClassAndModuleChildren в 65 файлах (class A::B -> module A; class B) + Layout, секция todo сокращена до пяти KEEP; риск — константа, которая после вложения разрешается в A::X; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r4.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r4-probes/**

Контекст ревьюерам: главный риск — смена разрешения константы (суперкласс, `include`, `rescue X`,
вызовы `X.new`), которую eager load не ловит; правки вне вложения и отступов.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r4.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r4.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- AC-003 FAIL: имя разрешается иначе (файл, имя, BASE → дерево) — файл может уйти в `KEEP`, решает
  постановщик; не добавлять `::` руками;
- AC-002 DIFF у файла (автокоррект изменил не только вложение) — файл, вывод `r4_nest.rb`;
- автокоррект меняет не 65 файлов или рождает офенсы других копов сверх `ALLOWED_GROWTH`;
- зелёный AC-004/AC-005 недостижим без правки чужих секций todo, `rubocop:disable` или
  `.rubocop.yml`;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов, перегенерация `.rubocop_todo.yml`, правка пробников,
удалять/skip-ать тесты, глушить вывод и коды возврата.

## 10. Стыки

- `twilio_phone/api.rb` (`KEEP`) — в R7 плана: `::Twilio` в нужных местах, тест, затем вложение.
- Четыре ERB-презентера (`KEEP`) — в R7 плана: вынести шаблоны или проверить константы в них, затем
  вложение.
- `r4_nest.rb refs` + `r4_resolve.rb` переиспользуются для любой будущей правки, меняющей
  лексическую вложенность.
- Следующие вехи — R3b/R2b (ручной разбор с тестами), R5 и далее по плану.
