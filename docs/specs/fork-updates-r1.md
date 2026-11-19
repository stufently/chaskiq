# fork-updates-r1 — бэклог RuboCop, шаг 1: безопасный автокоррект Layout/Style без изменения байткода

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-r1.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — R1 оттуда).
- BASE_SHA: `b8ce925cc3c68539eea0cf173be55298dffc9f58` — сейчас HEAD `main`; веха запускается ПОСЛЕ влития fork-updates-m11 (Telnyx) и fork-updates-m14 (Ruby 4.0.10).
- BASE плавающий: до запуска `main` уйдёт вперёд (вливаются m11 и m14), постановщик коммитит
  новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-005).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: 16 копов Layout/Style из `.rubocop_todo.yml` исправлены автокорректом RuboCop по всему
  дереву, их записи из `.rubocop_todo.yml` удалены; `docs/**` выведен из-под RuboCop с
  записанной причиной; каждый изменённый Ruby-файл компилируется в тот же байткод YARV, что на
  BASE (поведение не меняется по построению); полный rspec зелёный тем же списком примеров;
  строгий RuboCop CI (`bin/ci-local --only rubocop`) зелёный.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r1`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.
- Всё на Ruby и гемах дерева через `bin/ci-local` (образ раннеров ubuntu-26.04, Ruby из
  `.ruby-version`) — так же, как CI. Свой кэш гемов: `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r1-ci`
  (не делить с pre-push хуком живого дерева).

Что делает постановщик ДО запуска (после влития m11 и m14, на `main`; строго по порядку — клон
снимается ПОСЛЕДНИМ, когда всё ниже уже закоммичено в `main`):

1. Кэш: `cp -a $HOME/.cache/chaskiq-m14-ci $HOME/.cache/chaskiq-r1-ci` (гемы Ruby 4 из m14;
   если каталога m14 нет — `mkdir -p $HOME/.cache/chaskiq-r1-ci`, первый прогон соберёт гемы,
   ~5 мин). Образ `chaskiq-ci-local:ruby-<.ruby-version>-ubuntu-26.04` собирает сам `bin/ci-local`.
2. Перемерить: на чистом checkout `main` прогнать
   `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r1-ci bin/ci-local --only rubocop` (должен быть зелёным)
   и убедиться, что все 16 копов раздела 3 ещё есть в `.rubocop_todo.yml` (m11 мог убрать строку
   `telnyx_sms/api.rb` у `Layout/EmptyLinesAroundClassBody` — это нормально, пробник берёт список
   из `.rubocop_todo.yml` BASE; пропал коп целиком — убрать его из `R1_COPS` в
   `r1_equiv_probe.py` и из таблицы раздела 3).
3. Список примеров BASE на том же checkout:
   `CHASKIQ_R1_CACHE=$HOME/.cache/chaskiq-r1-ci bash docs/specs/fork-updates-r1-probes/rspec_gate_r1.sh --write-base`
   (сьют должен быть зелёным; пишет `examples_base.txt`, `pending_allowed.txt`,
   `warnings_base.txt`). Снят постановщиком на `main` b8ce925c (Ruby 4.0.10): 675 примеров,
   0 failures, 30 pending.
4. Закоммитить в `main` одним коммитом постановщика: три файла из п. 3, их sha256 (и sha256
   изменённого пробника, если был п. 2) в AC-005 и строку BASE_SHA ← HEAD `main`. Только после
   этого коммита — `make_clone.sh`: исполнитель получает спеку и пробники уже закоммиченными и сам
   в `docs/specs` не коммитит ничего (AC-005).
5. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-ci-local:ruby-<.ruby-version>-ubuntu-26.04` | собирает `bin/ci-local` | rubocop, rspec, байткод — Ruby дерева |
| гемы, yarn-кэш | `$HOME/.cache/chaskiq-r1-ci` (`bundle-ubuntu-26.04/`, `yarn/`) | `bin/ci-local`, пробники; гемы в вехе не меняются |
| образы | `postgres:14-alpine`, `redis:8.10-alpine` | rspec через `bin/ci-local` |

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r1-probes
export CHASKIQ_R1_CACHE=$HOME/.cache/chaskiq-r1-ci
bash $P/rspec_gate_r1.sh                      # полный rspec через bin/ci-local, ~10 мин
bash $P/rspec_gate_r1.sh --only <spec-файл>   # один файл
python3 -I $P/r1_equiv_probe.py $B            # байткод BASE == дерево, границы, todo, .rubocop.yml (~1 мин)
bash $P/r1_backlog_probe.sh $B                # rubocop без todo: R1-копы 0, остальные не выросли (~3 мин)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r1-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

## 3. Задача и почему

RuboCop в CI строгий (любой офенс валит сборку), старый бэклог лежит в `.rubocop_todo.yml`
пофайловыми `Exclude` (`--auto-gen-only-exclude`, `inherit_mode: merge: Exclude` в
`.rubocop.yml`). Цель владельца — бэклог в ноль и `.rubocop_todo.yml` удалён, поведение
приложения не меняется. Замер на BASE a6ec4ad4 (RuboCop 1.92.3, rubocop-rails 2.38.0, Ruby
3.3.14, `.rubocop_todo.yml` не подключён): **2565 офенсов в 507 файлах, 103 копа**; из них 129 —
в `docs/specs/*-probes` (10 файлов). Без `docs/`: 2436 офенсов — 1299 ручных (27 копов), 829 с
безопасным автокорректом (41 коп), 308 с небезопасным (26 копов). Полный разбор и вехи R1–R9 — в
`docs/specs/fork-updates-rubocop-plan.md`.

R1 берёт только то, что можно доказать механически. Отбор (раздел 4 п. 2–4): коп из
`.rubocop_todo.yml` с **безопасным** автокорректом (по RuboCop), департамент Layout или Style,
`rubocop -a --only <коп>` исправляет ВСЕ его офенсы, и каждый изменённый файл компилируется в
тот же байткод YARV на Ruby 3.3.14 и на Ruby 4.0.10. Таких копов 16, 126 офенсов в 49 файлах
(вне `docs/`):

| Коп | Офенсов | Файлов |
|---|---|---|
| `Layout/EmptyLineAfterGuardClause` | 1 | 1 |
| `Layout/EmptyLinesAfterModuleInclusion` | 39 | 22 |
| `Layout/EmptyLinesAroundBlockBody` | 1 | 1 |
| `Layout/EmptyLinesAroundClassBody` | 15 | 15 |
| `Layout/EmptyLinesAroundMethodBody` | 1 | 1 |
| `Layout/ExtraSpacing` | 4 | 2 |
| `Layout/FirstArrayElementIndentation` | 24 | 5 |
| `Layout/HashAlignment` | 4 | 2 |
| `Layout/MultilineMethodCallIndentation` | 22 | 4 |
| `Layout/SpaceAroundOperators` | 2 | 2 |
| `Layout/SpaceBeforeBlockBraces` | 2 | 2 |
| `Layout/SpaceInsideBlockBraces` | 4 | 2 |
| `Style/RegexpLiteral` | 1 | 1 |
| `Style/Semicolon` | 4 | 1 |
| `Style/TrailingCommaInArguments` | 1 | 1 |
| `Style/WordArray` | 1 | 1 |

Сознательно НЕ в R1 (безопасный автокоррект есть, но байткод меняется или исправляется не всё —
это R2, R5, R6 и R8 плана): `Style/RedundantParentheses` (`a && (b && c)` → другая структура
переходов), `Style/RedundantReturn` (на Ruby 4.0.10 другой байткод), `Style/IfUnlessModifier`
(переводит длинные модификаторы в блочный `if` и рождает `Style/GuardClause`),
`Style/GuardClause`, `Style/HashAsLastArrayItem`, `Layout/LineLength` (автокоррект закрывает
85 из 228), все `Lint/*` (каждый — возможный баг, разбирается руками), `Bundler/OrderedGems`
(порядок `gem` = порядок `Bundler.require`).

**`docs/**` вне RuboCop.** Файлы `docs/specs/*-probes/*.rb` — замороженные пробники вех; их
sha256 зашиты в критерии их спек (например последний критерий спеки m12), правка «под стиль» ломает перезапуск
этих критериев. Поэтому в `.rubocop.yml` в `AllCops: Exclude` добавляется `'docs/**/*'` с
комментарием-причиной, а все строки `docs/...` уходят из `.rubocop_todo.yml` (7 секций состояли
только из них и исчезают целиком: `Layout/EmptyLineAfterMagicComment`,
`Rails/RootPathnameMethods`, `Style/ExplicitBlockArgument`, `Style/LambdaCall`,
`Style/NestedTernaryOperator`, `Style/NumericPredicate`, `Style/SelectByKind`).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker (`chaskiq-ci-local:ruby-3.3.14-ubuntu-26.04`, гемы из кэша
`bin/ci-local`) на клоне BASE a6ec4ad4 и на черновике (только для проверки достижимости, в веху
не идёт):

1. Замер раздела 3: `rubocop -c <.rubocop.yml без строки inherit_from>` — 2565 офенсов,
   `--format json`, классификация копов по `Safe`/`SafeAutoCorrect` конфигурации RuboCop.
2. По каждому из 76 автокорректируемых копов отдельно: `rubocop -A --only <коп>` на файлах с его
   офенсами + сравнение нормализованного байткода (`r1_iseq.rb`) до и после. Байткод НЕ меняется
   у 16 копов раздела 3 и ещё у `Layout/LineLength`, `Style/IfUnlessModifier`,
   `Style/RedundantReturn` (на 3.3), `Lint/AmbiguousOperatorPrecedence`,
   `Lint/AssignmentInCondition`, `Lint/AmbiguousBlockAssociation`, `Style/DirectiveScope`,
   `Style/LambdaCall`, `Style/NestedTernaryOperator`; у остальных меняется.
3. Каскады: после `-a --only <16 копов>` появляются офенсы копов, которых нет в todo этих файлов:
   `Layout/ArrayAlignment` (26), `Layout/FirstHashElementIndentation`,
   `Layout/IndentationConsistency`, `Layout/BlockEndNewline`, `Layout/MultilineBlockLayout`
   (спеки hooks), `Style/BlockDelimiters` (4, `spec/models/segment_spec.rb`: `Style/Semicolon`
   превращает однострочный `{ |o| a; b }` в многострочный). Второй проход
   `rubocop -a --only Layout,Style/BlockDelimiters` их закрывает (77 исправлений), после него
   `bundle exec rubocop` по всему дереву — 0 офенсов, 495 файлов.
4. Черновик (раздел 5 целиком): 49 Ruby-файлов + `.rubocop.yml` + `.rubocop_todo.yml`, +150/−333
   строк (из них −228 — `.rubocop_todo.yml`); `r1_equiv_probe.py` — 49/49 файлов с тем же
   байткодом, PASS; тот же `r1_iseq.rb` на `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` — 49/49
   SAME; `r1_backlog_probe.sh` — PASS (без todo: BASE 2565, дерево 2321; RuboCop проверил ровно 508/495 целевых файлов, stderr пуст); `rubocop` — 0 офенсов;
   `rspec_gate_r1.sh` — см. п. 7.
5. Ловушки пробника, проверенные на черновике (каждая → FAIL): семантическая правка в изменённом
   файле (`DIFF`); `# encoding: us-ascii` в изменённом файле — строки «равны» по `==`, но `DIFF` по
   кодировке; `0.0` → `-0.0` в изменённом файле (`DIFF`); пробел в файле вне списка R1; правка
   `.erb`-шаблона и `bin/ci-local` (не Ruby-исходник R1); возврат секции R1 в todo; лишний
   комментарий и ERB-комментарий (`# <%= … %>`) в todo; лишний комментарий и ERB-комментарий в
   `.rubocop.yml`; добавленный `# rubocop:disable`. Самопроверка компаратора (вшита в пробник) на
   3.3.14 и 4.0.10: layout-правка, сдвиг строк в обычном файле и `:a` под us-ascii — `SAME`;
   удалённое присваивание, другой литерал, другой вызов, `frozen_string_literal`, кодировка
   строкового литерала, `-0.0` — `DIFF`; сдвиг строк в файле с `caller` и с `class_eval <<~RUBY` —
   `LINES`. Среди 49 файлов черновика line-sensitive нет (`binding` в `app/models/plan.rb` отдаётся
   в ERB, номера строк файла он не раскрывает, поэтому в список признаков не входит).
6. На Ruby 4.0.10 `Style/RedundantReturn` (`return x if c` в хвосте метода → `x if c`) даёт
   другой байткод (другая раскладка меток) — поэтому он не в R1, хотя на 3.3 байткод совпадал.
7. rspec BASE через `bin/ci-local --only rspec` (Ruby 3.3.14): 635 примеров, 0 failures,
   30 pending; единственная warning-строка — `WARNING:  you don't own a lock of type
   ExclusiveLock` (вывод postgres в спеках m9). Черновик: тот же гейт зелёный, 635/0/30.

Предположения: что m11 и m14 не добавят в файлы R1 новых офенсов этих копов, которые автокоррект
не берёт (m14 по своей спеке не меняет `.rubocop*.yml`, m11 — тоже); что RuboCop 1.92.3 на
Ruby 4.0 исправляет эти копы так же (m14: «новых офенсов от Ruby 4 нет»). Если не так —
постановщик правит раздел 3 до запуска (раздел 2 п. 2).

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей. Все команды
RuboCop — в образе `bin/ci-local` (как `in_ruby` в `bin/ci-local`: `-v $PWD:/app`,
`-v $CHASKIQ_R1_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle`, `BUNDLE_PATH=/app/vendor/bundle`).

1. `.rubocop.yml`: сразу после строки `    - 'vendor/**/*'` блока `AllCops: Exclude` вставить
   ровно эти три строки (байт в байт, отступ 4 пробела):
   ```yaml
       # Frozen milestone specs and probes: their files are pinned by sha256 in the
       # acceptance criteria of each spec, so they are never rewritten for style.
       - 'docs/**/*'
   ```
   Больше в `.rubocop.yml` ничего не меняется: пробник сравнивает файл с «BASE + эти три строки»
   побайтово (RuboCop пропускает конфиги через ERB, поэтому даже комментарий может отключить коп;
   любые `<%` в диффе конфигов — FAIL; AC-002).
2. `.rubocop_todo.yml` — побайтово равен результату этого алгоритма над файлом BASE (он же
   `expected_todo()` в `r1_equiv_probe.py`): файл режется на блоки по пустой строке; первый блок
   (шапка) остаётся; блок, чья строка копа (`^<Dept>/<Cop>:$`) — коп из раздела 3, удаляется
   целиком вместе с комментариями; в остальных блоках удаляются все строки, начинающиеся с
   `    - 'docs/`; если после этого последняя строка блока — `  Exclude:`, она удаляется; если в
   блоке после строки копа ничего не осталось — блок удаляется; блоки склеиваются через одну
   пустую строку, файл кончается одним переводом строки. Так остаются, например, `EnforcedStyle:
   …` у `Style/FormatStringToken` и `Style/SpecialGlobalVars`. Перегенерировать файл
   `--auto-gen-config` ЗАПРЕЩЕНО (AC-002).
3. Автокоррект, два прохода:
   `bundle exec rubocop -a --only Layout/EmptyLineAfterGuardClause,Layout/EmptyLinesAfterModuleInclusion,Layout/EmptyLinesAroundBlockBody,Layout/EmptyLinesAroundClassBody,Layout/EmptyLinesAroundMethodBody,Layout/ExtraSpacing,Layout/FirstArrayElementIndentation,Layout/HashAlignment,Layout/MultilineMethodCallIndentation,Layout/SpaceAroundOperators,Layout/SpaceBeforeBlockBraces,Layout/SpaceInsideBlockBraces,Style/RegexpLiteral,Style/Semicolon,Style/TrailingCommaInArguments,Style/WordArray`,
   затем `bundle exec rubocop -a --only Layout,Style/BlockDelimiters` (каскады раздела 4 п. 3).
   Только `-a` (безопасный), НЕ `-A`. Ручные правки Ruby-файлов не нужны; если без них не
   обойтись — только пробелы/переводы строк, и байткод обязан совпасть (AC-002).
4. Проверить `bundle exec rubocop` по всему дереву — 0 офенсов; `r1_equiv_probe.py` — PASS.
   Файл с `DIFF` — откатить его правки и разобраться, какой коп дал изменение байткода; если это
   коп из списка R1 — контракт на невыполнимое (раздел 9), не обходить.
5. `CHANGELOG.md`: одна строка в новом разделе «## <дата> — fork-updates-r1» → «Changed»:
   RuboCop-бэклог, автокоррект 16 копов Layout/Style без изменения поведения, `docs/` вне RuboCop.
6. Тесты не добавляются и не меняются, кроме строк, которые меняет сам автокоррект (11 файлов
   `spec/` на черновике: отступы, `%w[]`, `do…end` вместо `{…}` в `segment_spec.rb`).

## 6. Не трогать

- Всё, кроме `.rubocop.yml`, `.rubocop_todo.yml`, `CHANGELOG.md` и Ruby-файлов, которые
  `.rubocop_todo.yml` BASE перечисляет под копом из раздела 3 (вне `docs/`). Новых файлов нет,
  файлы не удаляются и не переименовываются (AC-002).
- Версии гемов, `Gemfile`, `Gemfile.lock` (в том числе порядок гемов — `Bundler/OrderedGems` не в
  R1), RuboCop и его плагины, `.ruby-version`, `Dockerfile*`, `docker-compose.yml`, workflows,
  `bin/*` (включая `bin/ci-local`), `.githooks/`, `db/`, `config/`, `package.json`, `yarn.lock`.
- Копы вне раздела 3: их офенсы не исправлять даже «заодно» (каскады раздела 4 п. 3 — только в
  файлах из списка выше и только Layout + `Style/BlockDelimiters`). Ни одного
  `# rubocop:disable`/`rubocop:todo`, ни новых `Exclude`/`Max`/`Enabled` в конфигах.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять запрещено; меняет их только
  автокоррект (раздел 5 п. 6).
- `docs/specs/**` — закоммичены постановщиком; не править (AC-005, sha256). Чужие спеки и клоны не
  трогать. Всё, что принесли m1–m14, не откатывать.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R1_CACHE=$HOME/.cache/chaskiq-r1-ci bash docs/specs/fork-updates-r1-probes/rspec_gate_r1.sh'`

- **AC-002** — семантическая эквивалентность и границы: самопроверка компаратора проходит (в том числе кодировка литерала, 0.0 против -0.0, сдвиг строк в line-sensitive файле); каждый изменённый файл — Ruby-исходник, даёт тот же байткод YARV, что на BASE (литералы сравниваются точно, у line-sensitive файлов и номера строк), без новых warning от ruby -wc; изменены только файлы из todo BASE под R1-копами и три разрешённых файла; todo побайтово равен BASE минус секции R1 и строки docs; .rubocop.yml побайтово равен BASE плюс три строки docs-исключения; нет ERB в конфигах и rubocop:disable.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r1-probes/r1_equiv_probe.py $B'`

- **AC-003** — бэклог без todo: RuboCop проверил ровно свои целевые файлы на обеих сторонах без внутренних ошибок; у каждого R1-копа 0 офенсов по всему дереву, ни у одного другого копа офенсов не больше, чем на BASE, общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R1_CACHE=$HOME/.cache/chaskiq-r1-ci bash docs/specs/fork-updates-r1-probes/r1_backlog_probe.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r1-ci bin/ci-local --only rubocop'`

- **AC-005** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "8ed9bbbc70698efba6f7598533884aa59bc65c568a9d9f2603a94f8525519086  docs/specs/fork-updates-r1-probes/examples_base.txt" "07a26708559b6bc44f07390acf03b74bec37a1395344d5f9ee5e01982533b01d  docs/specs/fork-updates-r1-probes/pending_allowed.txt" "3bdb9a9cfa0344613c7a57d6560d71009d7dca7f166e615d32eb58546447c8db  docs/specs/fork-updates-r1-probes/warnings_base.txt" "9deddcf75be22e5b72062afc58c942bba4c0c7fdb69cbe2695a9e3145239abf8  docs/specs/fork-updates-r1-probes/rspec_gate_r1.sh" "7696238f431a9af732f3847641c9b92adb1832065fad4a783faeadddcd04307f  docs/specs/fork-updates-r1-probes/r1_equiv_probe.py" "cfb55a920c24ff8516dff21df34d2b73886e35763f77ef89af71cb86ea82c792  docs/specs/fork-updates-r1-probes/r1_iseq.rb" "d9a9ad141d38213b6336f6470107b19dc83d896d8c80cd3e4793c947d46bccfe  docs/specs/fork-updates-r1-probes/r1_backlog_probe.sh" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-006** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком на a6ec4ad4): AC-001, AC-004, AC-005, AC-006
зелёные; AC-002 красный (`.rubocop_todo.yml differs from BASE minus R1 sections and docs/ lines`
и `.rubocop.yml is not BASE plus exactly the docs/** exclude`); AC-003 красный (`Layout/EmptyLinesAfterModuleInclusion:
39 offenses left` и т. д.).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r1.md --exclude "docs/specs/fork-updates-r1-probes/**" --context "chaskiq fork-updates-r1: RuboCop rubocop -a по 16 копам Layout/Style (список в spec), каскадные Layout/BlockDelimiters, секции этих копов и строки docs/ удалены из .rubocop_todo.yml, docs/** в AllCops Exclude с причиной; байткод изменённых файлов равен BASE; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r1-probes/**

Контекст ревьюерам: нет ли правок вне копов R1 и вне их файлов; не удалено ли из todo лишнее (чужие
секции, строки не из `docs/`); не изменился ли смысл кода там, где автокоррект трогал heredoc,
регулярки, `%w[]` и блоки (`{…}` → `do…end` с аргументами без скобок меняет привязку блока).

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 6: AC-001…AC-006. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-002 — строка `bytecode: N/M`;
в `note` AC-003 — строка `backlog without todo: …`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r1.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r1.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- автокоррект копа из раздела 3 меняет байткод хотя бы одного файла (`DIFF` в AC-002) или сдвигает
  строки в line-sensitive файле (`LINES`) — укажи коп, файл, строку и вывод `r1_iseq.rb`; коп или
  файл исключит постановщик, сам не исключай;
- `rubocop -a` не закрывает все офенсы копа из раздела 3 или каскад требует копа вне
  `Layout` + `Style/BlockDelimiters`;
- зелёный AC-003/AC-004 недостижим без правки чужих секций todo, `rubocop:disable` или новой
  настройки в `.rubocop.yml`;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-r1-ci` или сервисы из раздела 2 недоступны.
Запрещено: `-A`, перегенерация `.rubocop_todo.yml`, удалять и skip-ать тесты, ослаблять ассерты,
глушить вывод, менять пробники, глушить коды возврата.

## 10. Стыки

- Следующая веха — R2 плана (автокоррект Style/Rails с изменением байткода, коп за копом с
  обоснованием эквивалентности); запускается после влития этой. Все вехи плана правят
  `.rubocop_todo.yml`, поэтому идут строго последовательно.
- Пробники `docs/specs/*-probes/*.rb` после вехи RuboCop не проверяет; это осознанно (раздел 3).
- `r1_iseq.rb` (нормализованный байткод) переиспользуется в R2 как отчётный инструмент: там
  `DIFF` допустим, но каждый должен быть объяснён.
