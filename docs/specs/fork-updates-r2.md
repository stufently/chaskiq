# fork-updates-r2 — бэклог RuboCop, шаг 2: автокоррект Style с меняющимся байткодом, каждое изменение объяснено

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-r2.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — R2 оттуда; что из прежнего списка R2 не
  прошло механическую проверку, перенесено в R2b плана).
- BASE_SHA: `d8c82e37d7f030f426bc252e60f0f906e3ac2c7a` — HEAD `main` с влитыми m11–m14 и R1 (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-006).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: 10 копов Style/Naming из `.rubocop_todo.yml` исправлены автокорректом, коп за копом
  (отдельный коммит на коп), их секции удалены из todo; каждое отличие синтаксического дерева в
  изменённых файлах объяснено переписыванием разрешённого для этого файла копа
  (`r2_canon.rb`), необъяснённое — FAIL; полный rspec зелёный тем же списком примеров без новых
  warning; строгий RuboCop CI зелёный.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.
- Всё на Ruby и гемах дерева через образ `bin/ci-local` (ubuntu-26.04, Ruby из `.ruby-version`
  = 4.0.10). Свой кэш: `$HOME/.cache/chaskiq-r2-ci` (не делить с pre-push хуком живого дерева).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r2-ci` — копия `chaskiq-r1-ci` (гемы Ruby 4) — уже создан при
   написании спеки; если его нет — `cp -a $HOME/.cache/chaskiq-r1-ci $HOME/.cache/chaskiq-r2-ci`.
2. Если `main` ушёл вперёд от BASE_SHA шапки: перемерить (все 10 копов раздела 3 ещё в todo;
   `TODO_ADDITIONS`/`CASCADES` в `r2_equiv_probe.py` всё ещё верны — прогнать раздел 5 на черновике)
   и перегенерировать список примеров:
   `CHASKIQ_R2_CACHE=$HOME/.cache/chaskiq-r2-ci bash docs/specs/fork-updates-r2-probes/rspec_gate_r2.sh --write-base`
   на чистом checkout `main`. Сейчас в файлах — снимок `main` d8c82e37 на Ruby 4.0.10 (раздел 4 п. 8).
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-006 и строку
   BASE_SHA ← HEAD `main`. Только после этого — `make_clone.sh`.
4. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` | собирает `bin/ci-local` | rubocop, rspec, проверка деревьев |
| гемы, yarn-кэш | `$HOME/.cache/chaskiq-r2-ci` | `bin/ci-local`, пробники; гемы в вехе не меняются |
| образы | `postgres:14-alpine`, `redis:8.10-alpine` | rspec через `bin/ci-local` |

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r2-probes
export CHASKIQ_R2_CACHE=$HOME/.cache/chaskiq-r2-ci
bash $P/rspec_gate_r2.sh                      # полный rspec через bin/ci-local, ~10 мин
python3 -I $P/r2_equiv_probe.py $B            # каждое отличие объяснено копом файла, границы, todo (~1 мин)
bash $P/r2_backlog_probe.sh $B                # rubocop без todo: R2-копы 0, остальные не выросли (~3 мин)
python3 -I $P/r2_commits_probe.py $B          # коммиты по порядку, каждый объяснён своим копом (~2 мин)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r2-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

## 3. Задача и почему

После R1 бэклог без todo — 2323 офенса (BASE d8c82e37, Ruby 4.0.10, 497 файлов). R2 берёт
автокорректируемые копы Style/Naming, у которых байткод МЕНЯЕТСЯ, но равенство поведения
доказуемо механически: для каждого копа есть переписывание синтаксического дерева, которое
переводит старую и новую форму в одну каноническую, и оно верно в семантике Ruby при условиях,
которые проверяет сам инструмент. 10 копов, 95 офенсов в 46 файлах:

| Коп | Офенсов | Файлов | Что меняет / почему это то же самое |
|---|---|---|---|
| `Style/IfUnlessModifier` | 15 | 13 | длинный модификатор → блочный `if`; дерево то же (переписывание не нужно) |
| `Style/GuardClause` | 36 | 26 | `if c … end` в хвосте метода → `return unless c; …`; `if c; return a; else; return b; end` → `return a if c; return b` |
| `Style/RedundantParentheses` | 14 | 9 | `(x)` → `x` (одно выражение, не под `defined?`), `a && (b && c)` → `a && b && c` (ассоциативность) |
| `Style/RedundantReturn` | 2 | 2 | `return x if c` последним выражением метода → `x if c` |
| `Style/HashAsLastArrayItem` | 17 | 11 | `[a, k: v]` → `[a, { k: v }]` (в литерале массива это один и тот же хеш; без `**`) |
| `Style/ArgumentsForwarding` | 4 | 2 | `*args`/`&block`, которые только пробрасываются → анонимные `*`/`&` |
| `Naming/BlockForwarding` | 2 | 1 | `&block` → `&` (то же условие; параметр не читается и в значениях по умолчанию) |
| `Style/SuperArguments` | 1 | 1 | `super(a)` в `def f(a)` без переприсваивания `a` → `super` |
| `Style/EmptyStringInsideInterpolation` | 1 | 1 | `"#{c ? x : ''}"` → `"#{x if c}"` (`nil` интерполируется в `""`; `NilClass` в `app/`, `lib/`, `config/` не переоткрыт — проверяет пробник, гемы вне досягаемости) |
| `Style/DirectiveScope` | 3 | 2 | пара `rubocop:disable`/`enable` → `rubocop:disable-next` (только комментарии) |

Каскад (замерено на черновике, объявлен — `CASCADES` в `r2_equiv_probe.py`): `IfUnlessModifier`
рождает `GuardClause` в 3 файлах своего списка (длинный модификатор в хвосте метода → блочный `if`
→ guard clause); его исправляет коммит `GuardClause`. Новые офенсы, которые чинить НЕ этой вехе,
вносятся в todo (`TODO_ADDITIONS`):
- `Rails/Blank` — 5 мест в 4 файлах: `GuardClause` пишет `return unless x.present?`, коп хочет
  `return if x.blank?`; это равенство только при `blank? == !present?` для типа получателя —
  проверка типа это R3, а не R2. Секции `Rails/Blank` в todo BASE нет — создаётся новая
  (`NEW_SECTION_HEADERS`), перед `Rails/Delegate` (порядок имён копов);
- `Metrics/BlockLength` в `app/models/app.rb` (модификатор внутри блока стал блочным `if`; R8);
- `Style/ReturnNilInPredicateMethodDefinition` в `app/services/message_apis/open_ai/api.rb`
  (`GuardClause` в методе `locked_for_channel?`; `return false` вместо `return` — изменение
  поведения, R2b).

**Не в R2 (перенесены в R2b плана):** равенство зависит от типов или меняет поведение, механически
не доказывается — `Style/StringConcatenation` 15 (`+` против `to_s` интерполяции),
`SymbolProc` 3 (арность блока), `SingleArgumentDig` 3, `MapIntoArray` 2, `InverseMethods` 2,
`MultipleComparison` 2, `SafeNavigation` 1 (`false&.m`), `HashEachMethods` 1, `FloatDivision` 1,
`CaseLikeIf` 1 (`===` с обратным порядком), `ModuleMemberExistenceCheck` 1 — зависят от типа
получателя; `ReturnNilInPredicateMethodDefinition` 2 (`nil` → `false`), `MutableConstant` 1
(`.freeze`), `Naming/MemoizedInstanceVariableName` 3 (переименование ivar), `RedundantRegexpEscape` 1
(эквивалентность регулярок не проверяется инструментом), `Bundler/OrderedGems` 2 (порядок
`Bundler.require`) — 41 офенс.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r2-ci`) на
клоне BASE d8c82e37 и на черновике (только для проверки достижимости, в веху не идёт):

1. Замер: `rubocop` без `.rubocop_todo.yml` — 2323 офенса, 497 файлов; числа раздела 3 — из него.
2. По каждому из 26 копов прежнего списка R2 отдельно (`-A --only <коп>`) байткод
   (`r1_iseq.rb`): без изменений только у `IfUnlessModifier` (13/13 файлов) и `DirectiveScope`
   (2/2); `RedundantParentheses` — 8 из 9 без изменений; у остальных меняется. Диффы всех 26
   прочитаны; отбор раздела 3 — по ним.
3. `r2_canon.rb` (Prism 1.8.2 из Ruby 4.0.10): деревья без позиций и флага NEWLINE, литералы точно
   (кодировка + байты строк, IEEE-байты Float), магические комментарии и `__END__`; переписывания
   по копам — в шапке файла, условия проверяются (хвост метода; `begin` без `else`; не внутри
   блока; параметр только пробрасывается и нет `binding`/`local_variables`/`eval`; `super` без
   переприсваивания и только с обязательными позиционными параметрами; хеш без `**`; скобки не
   под `defined?`).
4. Черновик ровно по разделу 5 на свежем клоне с закоммиченными спекой и пробниками (коммит todo,
   10 коммитов `Autocorrect <коп>` в порядке раздела 5 — все непустые: 13, 29, 9, 2, 11, 1, 1, 1,
   1, 2 файлов; `Naming/BlockForwarding` идёт ДО `ArgumentsForwarding`, иначе его коммит пуст;
   коммит CHANGELOG): AC-001…AC-007 все зелёные. rspec 675/0/30 без warning-строк; AC-002 — 46
   файлов, 4 SAME, 42 EXPLAINED; AC-003 — без todo BASE 2323 → дерево 2225 (5 офенсов
   `Rails/Blank` остаются и закрыты новой секцией todo; рост `Metrics/MethodLength` в
   `twilio_phone/api.rb` 10 → 11 — файл уже в todo этого копа, R8); AC-005 — каждый коммит копа
   объяснён одним своим копом; `bin/ci-local --only rubocop` OK.
5. Найдено на черновике и учтено: `GuardClause` переписывает не только хвостовой `if`, но и
   `if c; return a; else; return b; end` в середине метода (`zapier/api.rb`) — отсюда второе правило
   копа; `Redis#eval(<<~LUA)` в `hooks_controller.rb` — не Ruby `eval` (признак line-sensitive
   уточнён: `x.eval` с чужим получателем не считается).
6. Самопроверка (вшита в пробник, 38 случаев): каждое правило объясняет свой случай и только своим
   копом; отказ на похожих, но неравных: guard не в хвосте, в блоке, в `begin … else`, без разрешения
   копа; `a && (b || c)` → `a && b || c`; `defined?((a))`; литерал рядом с разрешённым
   переписыванием; `return` внутри блока; `**h` в массиве; хеш в аргументах вызова (kwargs);
   использованный `*args`; `binding` в методе; `&block` без `ArgumentsForwarding`; переприсвоенный
   параметр и необязательный параметр у `super`; непустая строка в интерполяции; `unless x.present?` →
   `if x.blank?` (теперь всегда DIFF); проброшенный параметр, прочитанный в значении по умолчанию
   (`k: args`), и `binding` в значении по умолчанию; смена кодировки; сдвиг строк в файле с `caller` (`LINES`).
7. Плохие правки на черновике (каждая → FAIL): см. раздел 7, «Проверено на черновике».
8. rspec BASE через `bin/ci-local --only rspec` (Ruby 4.0.10, чистый checkout `main` d8c82e37):
   675 примеров, 0 failures, 30 pending, ни одной warning-строки (`warnings_base.txt` — только
   заголовок; гейт считает это пустым множеством).

Предположения: ни один гем не переопределяет `NilClass#to_s` (пробник проверяет только `app/`,
`lib/`, `config/`); RuboCop 1.92.3 на ревизии клона
исправляет копы так же, как на черновике.

## 5. Что сделать

Все команды RuboCop — в образе `bin/ci-local` (`-v $PWD:/app`,
`-v $CHASKIQ_R2_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle`, `BUNDLE_PATH=/app/vendor/bundle`).
Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Коммит `Drop R2 cops from RuboCop todo`: `.rubocop_todo.yml` побайтово равен
   `expected_todo()` из `r2_equiv_probe.py` над файлом BASE: блоки (через пустую строку) 10 копов
   раздела 3 удалены целиком с комментариями; в секцию `Metrics/BlockLength` добавлена строка
   `    - 'app/models/app.rb'`, в секцию `Style/ReturnNilInPredicateMethodDefinition` — строка
   `    - 'app/services/message_apis/open_ai/api.rb'`, обе на место по сортировке; перед блоком
   `Rails/Delegate` вставлен новый блок — две строки комментария из `NEW_SECTION_HEADERS`,
   `Rails/Blank:`, `  Exclude:` и четыре файла `TODO_ADDITIONS["Rails/Blank"]` по сортировке;
   больше ничего.
   Перегенерация `--auto-gen-config` запрещена. `.rubocop.yml` не меняется.
2. По одному коммиту на коп, строго в этом порядке, каждый — `bundle exec rubocop -A --only <коп>`
   и затем `bundle exec rubocop -a --only Layout` (отступы после переписывания), сообщение коммита
   ровно `Autocorrect <коп>`: `Style/IfUnlessModifier`, `Style/GuardClause`,
   `Style/RedundantParentheses`, `Style/RedundantReturn`, `Style/HashAsLastArrayItem`,
   `Naming/BlockForwarding`, `Style/ArgumentsForwarding`, `Style/SuperArguments`,
   `Style/EmptyStringInsideInterpolation`, `Style/DirectiveScope`. Каждый коммит непустой и меняет
   только файлы своего копа (AC-005 проверяет каждый коммит отдельно: родитель → коммит объяснён
   этим одним копом). `Rails/Blank` НЕ исправлять. Ручные правки Ruby-файлов запрещены.
3. После каждого коммита — `python3 -I docs/specs/fork-updates-r2-probes/r2_equiv_probe.py $B`:
   `DIFF`/`LINES`/`NEWWARN` у файла — откатить коммит этого копа и остановиться (раздел 9).
4. В конце `bundle exec rubocop` по дереву — 0 офенсов; `CHANGELOG.md` — одна строка в новом
   разделе «## <дата> — fork-updates-r2» → «Changed»: автокоррект 10 копов Style/Naming, каждое
   изменение дерева объяснено правилом копа, поведение не меняется. Коммит ровно
   `Note fork-updates-r2 in changelog`, только `CHANGELOG.md`. После него допустимы только коммиты,
   меняющие один `CHANGELOG.md` (правка формулировки по ревью); замечание ревью, требующее правки
   Ruby-файла, — контракт на невыполнимое (раздел 9): весь код вехи пишет автокоррект.
5. В `report.json`, `note` AC-002 — строки `files:` и `per cop:` из вывода пробника дословно.

## 6. Не трогать

- Всё, кроме `.rubocop_todo.yml`, `CHANGELOG.md` и Ruby-файлов (обычные файлы, тот же git-режим, не симлинки), которые BASE todo перечисляет под
  копом раздела 3 (с каскадами `CASCADES`). Новых файлов нет, файлы не удаляются (AC-002).
- `.rubocop.yml`, версии гемов, `Gemfile`, `Gemfile.lock`, RuboCop и плагины, `.ruby-version`,
  `Dockerfile*`, `docker-compose.yml`, workflows, `bin/*`, `.githooks/`, `db/`, `config/`,
  `package.json`, `yarn.lock`.
- Копы вне раздела 3 (в том числе `Rails/Blank`): не исправлять «заодно». Новые офенсы других копов — только
  объявленные (`TODO_ADDITIONS`, рост Metrics/LineLength в файлах, уже исключённых в todo). Никаких
  новых `# rubocop:disable`/`todo`/`enable`; директивы меняет только `Style/DirectiveScope` в своих
  2 файлах.
- Существующие спеки: удалять, skip-ать, ослаблять запрещено; меняет их только автокоррект.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-006, sha256). Всё, что принесли
  m1–m14 и R1, не откатывать.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R2_CACHE=$HOME/.cache/chaskiq-r2-ci bash docs/specs/fork-updates-r2-probes/rspec_gate_r2.sh'`

- **AC-002** — каждое отличие объяснено: самопроверка r2_canon.rb проходит; каждый изменённый путь — обычный файл с тем же git-режимом, Ruby-исходник из todo BASE под R2-копом; его дерево SAME или EXPLAINED правилами разрешённых для файла копов (каждый названный коп нужен), нет DIFF, LINES, ERROR, новых warning от ruby -wc; NilClass не переоткрыт в app/lib/config; todo побайтово равен BASE минус секции R2 плюс TODO_ADDITIONS (с новой секцией Rails/Blank); .rubocop.yml не тронут; директивы меняются только у DirectiveScope; нет ERB в конфигах.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r2-probes/r2_equiv_probe.py $B'`

- **AC-003** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у каждого R2-копа 0 офенсов; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE, кроме TODO_ADDITIONS и роста Metrics/LineLength в изменённых файлах, уже исключённых в todo; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R2_CACHE=$HOME/.cache/chaskiq-r2-ci bash docs/specs/fork-updates-r2-probes/r2_backlog_probe.sh $B'`

- **AC-004** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r2-ci bin/ci-local --only rubocop'`

- **AC-005** — коп за копом, каждый коммит отдельно: коммиты идут ровно в порядке раздела 5; коммит todo меняет только todo, коммит CHANGELOG только CHANGELOG; каждый коммит Autocorrect непустой, меняет только файлы своего копа из todo BASE (с каскадами), и его дифф родитель → коммит объяснён этим одним копом (SAME или EXPLAINED, без DIFF, LINES, NEWWARN, ERROR).
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r2-probes/r2_commits_probe.py $B'`

- **AC-006** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "f4a30a005ecc1e8986af58db827be5440c26df5ea1fcdc472718f96f97ec2661  docs/specs/fork-updates-r2-probes/examples_base.txt" "7d13aeefc5130a4e3fb584e902da4c730ad61549fb3d3d8c2caefc97fb5b1f5d  docs/specs/fork-updates-r2-probes/pending_allowed.txt" "bc177cad3e868f380b043343549af7bc47a875b351d111399eb61851e0b4a464  docs/specs/fork-updates-r2-probes/warnings_base.txt" "3d69748c2520028b5c4acc2050a444572f1cb5ebf60873a3a6177aa26f2d7543  docs/specs/fork-updates-r2-probes/rspec_gate_r2.sh" "826ba537b3cee45db4d4b210c56042ae1507b44d0161d46feec1ab14e3e15281  docs/specs/fork-updates-r2-probes/r2_equiv_probe.py" "c3b15dbdb053bb07e6e5f3a6a8f65bf0e766357d12d4a6ef815a426fa13ccb88  docs/specs/fork-updates-r2-probes/r2_canon.rb" "5ea74b6f020e8533b925d8c7efd6246278460619826fcc44770dab2fb61f84c7  docs/specs/fork-updates-r2-probes/r2_backlog_probe.sh" "df976ff876fe3ce457f312a527af48d065293f13c00001cd60b5a54fd77f401e  docs/specs/fork-updates-r2-probes/r2_commits_probe.py" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-007** — дерево чистое (сбой git — тоже FAIL: первый вызов проверяет код возврата).
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-004, AC-006, AC-007 зелёные;
AC-002 красный (`.rubocop_todo.yml differs from BASE minus R2 sections plus TODO_ADDITIONS`);
AC-003 красный (`Style/IfUnlessModifier: 15 offenses left`, `Style/GuardClause: 36 …` и т. д.); AC-005 красный
(`missing commits: [...]`).

Проверено на черновике (каждая правка → FAIL AC-002): см. отчёт постановщика и раздел 4 п. 7 —
семантическая правка в файле с объяснённой разницей (литерал рядом с guard), `0.0` → `-0.0`,
`# encoding: us-ascii`, правка файла вне списков, правка `.erb` и `bin/`, лишняя строка и
ERB-комментарий в todo, правка `.rubocop.yml`, добавленный `# rubocop:disable`, `disable-next` вне
файлов DirectiveScope, `chmod +x` у изменённого файла, файл заменён симлинком, `class NilClass` с
`to_s` в `lib/`. FAIL AC-005: переставленные коммиты копов, лишний файл в коммите todo, ручная
правка Ruby в коммите CHANGELOG, правка файла другого копа внутри коммита копа, пустой коммит копа.
FAIL AC-007: дерево вне git-репозитория (сбой `git status`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r2.md --exclude "docs/specs/fork-updates-r2-probes/**" --context "chaskiq fork-updates-r2: RuboCop -A по 10 копам Style/Naming коп за копом (GuardClause, IfUnlessModifier, RedundantParentheses, RedundantReturn, HashAsLastArrayItem, ArgumentsForwarding, BlockForwarding, SuperArguments, EmptyStringInsideInterpolation, DirectiveScope) секции удалены из todo, объявленные добавления в todo (новая секция Rails/Blank); каждое отличие дерева объяснено правилом копа; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r2-probes/**

Контекст ревьюерам: главный риск — guard clause, вставленный не в хвост метода (там `return`
меняет поток), и `return` внутри блока; нет ли правок вне списков копов; не ослаблены ли спеки.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 7: AC-001…AC-007. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-002 — строки `files:` и
`per cop:`; в `note` AC-003 — строка `backlog without todo: …`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r2.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r2.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- `r2_equiv_probe.py` говорит `DIFF`, `LINES` или `NEWWARN` после автокоррекции копа из раздела 3 —
  укажи коп, файл, вывод `r2_canon.rb` и дифф; правило или список копов поправит постановщик;
- `r2_commits_probe.py` (AC-005) не проходит при коммитах ровно по разделу 5: коммит копа пустой,
  трогает файл не своего копа или не объяснён одним своим копом — приложи вывод пробника;
- замечание ревью требует правки Ruby-файла (весь код вехи пишет автокоррект);
- автокоррект рождает офенсы, которых нет в `CASCADES`/`TODO_ADDITIONS`, или не закрывает все
  офенсы копа;
- зелёный AC-003/AC-004 недостижим без правки чужих секций todo, `rubocop:disable` или
  настройки в `.rubocop.yml`;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-r2-ci` или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов, перегенерация `.rubocop_todo.yml`, правка пробников,
удалять и skip-ать тесты, ослаблять ассерты, глушить вывод и коды возврата.

## 10. Стыки

- Следующая веха — R2b плана (копы, не прошедшие механическую проверку, — ручной разбор каждого
  места), затем R3. Все вехи правят `.rubocop_todo.yml` и идут строго последовательно.
- Две строки, добавленные в todo (`TODO_ADDITIONS`), снимаются в R2b
  (`ReturnNilInPredicateMethodDefinition`) и R8 (`Metrics/BlockLength`).
- `r2_canon.rb` переиспользуется в R2b как отчётный инструмент: там `DIFF` допустим, но каждый
  должен быть объяснён в отчёте.
