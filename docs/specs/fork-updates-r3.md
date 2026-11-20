# fork-updates-r3 — бэклог RuboCop, шаг 3: `# frozen_string_literal: true` в 127 файлах, ни один литерал не мутируется

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r3.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — R3 оттуда, только
  `Style/FrozenStringLiteralComment`; Rails-копы прежнего R3 вынесены в R3b плана, раздел 3).
  R2b плана идёт ПОСЛЕ: это ручной разбор каждого места, механически не проверяется.
- BASE_SHA: `4a749faad21988a144555a1eb3d23f92ef3d0459` — HEAD `main` с влитыми R1, R2 и решениями
  владельца по плану (Ruby 4.0.10, RuboCop 1.92.3, Prism 1.8.2).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-007).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: 127 файлов из секции `Style/FrozenStringLiteralComment` todo получают магический
  комментарий автокорректом, секция удалена из todo; каждый файл изменён ровно на комментарий и
  пустую строку (`.freeze`, ставший лишним, снят `Style/RedundantFreeze` в 2 местах), дерево Prism
  без изменений; ни один литерал этих файлов не может быть мутирован — ни по статическому разбору
  потоков (`r3_frozen.rb mutate`), ни во время полного сьюта и eager load с ЗАМОРОЖЕННЫМИ ВСЕМИ
  литералами (`--enable-frozen-string-literal`); полный rspec зелёный тем же списком примеров;
  строгий RuboCop CI зелёный.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r3`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.
- Всё на Ruby и гемах дерева через образ `bin/ci-local` (ubuntu-26.04, Ruby из `.ruby-version`
  = 4.0.10). Свой кэш: `$HOME/.cache/chaskiq-r3-ci` (не делить с pre-push хуком живого дерева).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r3-ci` — копия `chaskiq-r2-ci` (гемы Ruby 4) — уже создан при
   написании спеки; если его нет — `cp -a $HOME/.cache/chaskiq-r2-ci $HOME/.cache/chaskiq-r3-ci`.
2. Если `main` ушёл вперёд от BASE_SHA шапки: перемерить (секция копа в todo та же; `FREEZE_FILES`
   в `r3_equiv_probe.py` верен; раздел 5 на черновике) и перегенерировать список примеров:
   `CHASKIQ_R3_CACHE=$HOME/.cache/chaskiq-r3-ci bash docs/specs/fork-updates-r3-probes/rspec_gate_r3.sh --write-base`
   на чистом checkout `main`, затем `frozen_gate_r3.sh` на нём же должен быть зелёным. Сейчас в
   файлах — снимок `main` 4a749faa (раздел 4 п. 7).
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-007 и строку
   BASE_SHA ← HEAD `main`. Только после этого — `make_clone.sh`.
4. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` | собирает `bin/ci-local` | rubocop, rspec, Prism, пробники |
| гемы, yarn-кэш | `$HOME/.cache/chaskiq-r3-ci` | `bin/ci-local`, пробники; гемы в вехе не меняются |
| образы | `postgres:14-alpine`, `redis:8.10-alpine` | rspec через `bin/ci-local` и `frozen_gate_r3.sh` |

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r3-probes
export CHASKIQ_R3_CACHE=$HOME/.cache/chaskiq-r3-ci
bash $P/rspec_gate_r3.sh                      # полный rspec через bin/ci-local, ~10 мин
python3 -I $P/r3_equiv_probe.py $B            # форма правки, дерево, статический поиск мутаций, todo (~1 мин)
bash $P/frozen_gate_r3.sh                     # eager load + полный rspec, все литералы заморожены (~8 мин)
bash $P/r3_backlog_probe.sh $B                # rubocop без todo: R3-копы 0, остальные не выросли (~3 мин)
python3 -I $P/r3_commits_probe.py $B          # коммиты по порядку, каждый проверен отдельно (~1 мин)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r3-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

## 3. Задача и почему

Секция `Style/FrozenStringLiteralComment` todo BASE — 128 файлов: 40 `app/services`, 17
`app/models`, 12 `app/graphql`, 9 `app/controllers`, 4 `app/jobs`, по одному `app/channels`,
`app/helpers`, `app/policies`, 36 `spec/`, 6 `lib/` (два `.rake`), `bin/setup`. RuboCop
инспектирует 127: `bin/setup` в его список целей не входит (нет `.rb`, `bin/` не в Include;
`NOT_INSPECTED` в `r3_equiv_probe.py`), его не трогать.

Комментарий меняет одно: строковые литералы файла (`"…"`, `'…'`, heredoc и `"a" "b"` без
интерполяции, `__FILE__`) становятся замороженными, мутация такого литерала бросает `FrozenError`
вместо тихой правки (Ruby 4.0 пока лишь «chilled»: мутирует и предупреждает под `-W:deprecated`).
Строки с интерполяцией (`"#{x}"`) не замораживаются. Код, вычисляемый `eval`/ERB, комментария файла
не наследует (проверено: `eval('"x" << "y"', binding)` и `ERB#result(binding)` в файле с
комментарием отрабатывают, литералы там chilled). Значит, поведение меняется ровно там, где
литерал из этих файлов где-то мутируется — это и проверяет веха, тремя независимыми способами:

1. **Форма правки** (`r3_frozen.rb shape`): текст файла = BASE + `# frozen_string_literal: true` +
   пустая строка наверху (после shebang и `encoding`-комментария, где их ставит RuboCop);
   магического комментария в начале BASE-файла не было (комментарий ниже первого токена Ruby не
   действует — `paddle.rb:96` такой); деревья Prism равны после отбрасывания позиций, флага NEWLINE и
   флагов заморозки (FROZEN/MUTABLE и производный STATIC_LITERAL); `__END__` тот же.
2. **Статический поиск мутаций** (`r3_frozen.rb mutate`, правила — в шапке файла): консервативный,
   не зависящий от порядка разбор «может ли значение быть литералом» — сам литерал; локальная,
   `@`/`@@`/`$`-переменная или константа, которой где-либо присвоено такое значение (`=`, `||=`,
   `&&=`, значение параметра по умолчанию, множественное присваивание из литерала массива);
   ветви `if`/`unless`/`?:`/`case`/`&&`/`||`; тождественные вызовы (`to_s`, `presence`, `freeze`,
   `then`, `tap` …); результат метода того же файла (хвост или `return`); элемент массива/хеша из
   литералов (`[]`, `first`, `fetch`, `dig`, параметр блока `each`/`map`/…); memo
   `each_with_object("")`/`inject("")`. Находка — если такое значение: получает мутирующий метод
   String (`<<`, `concat`, `prepend`, `insert`, `replace`, `clear`, `force_encoding`, `[]=`, все
   `…!` String, `setbyte`, `bytesplice`, …); отдаётся буфером (`StringIO.new/open`,
   `CSV.generate`, `target:` Builder, второй аргумент `read`/`readpartial`/`sysread`/`recv`…);
   передаётся в параметр, который мутирует метод с тем же именем где угодно в `app/`, `lib/`,
   `config/`, `spec/`; метод этих файлов, который может вернуть литерал, стоит получателем мутатора
   где угодно там же (`x.name << y`). `+""`, `"".dup`, `String.new` — не литералы. Находок — 0
   (`REVIEWED` пуст).
3. **Рантайм** (`frozen_gate_r3.sh`): eager load всего приложения и всех rake-файлов, затем полный
   сьют — с `RUBYOPT="--enable-frozen-string-literal --debug-frozen-string-literal -W:deprecated"`:
   заморожены ВСЕ литералы (приложение, гемы, eval/ERB), любая мутация на пройденном пути —
   `FrozenError` с местом создания литерала. На BASE это зелёно (675 примеров, 0 failures), а
   прогон без флага заморозки, с `-W:deprecated --debug-frozen-string-literal`, не печатает ни
   одного предупреждения о мутации chilled-литерала: на путях сьюта приложение и гемы не мутируют
   ни одного литерала. Полный rspec обычным `bin/ci-local` (AC-001) — отдельно.

| Коп | Офенсов | Файлов | Что меняет |
|---|---|---|---|
| `Style/FrozenStringLiteralComment` | 127 | 127 | + `# frozen_string_literal: true` (+ пустая строка от `Layout/EmptyLineAfterMagicComment`, в том же коммите) |
| `Style/RedundantFreeze` | 2 | 2 | каскад: `"literal".freeze` → `"literal"` в `digital_ocean/api.rb:4`, `twilio_phone/store.rb:5` (литерал уже заморожен; тот же дедуплицированный объект) |

Новых офенсов других копов нет (замерено: после двух автокоррекций `rubocop` по дереву — 0).

**Не в R3 (перенесены в R3b плана):** Rails-копы прежнего R3 — `Rails/OrderArguments` 19,
`Pluck` 9, `Blank` 5 (из R2), `Presence` 4, `StrongParametersExpect` 3, `Delegate` 2,
`WhereRange` 1, `Present` 1: равенство зависит от типа получателя (`present?`/`blank?`/`presence`
своих классов), меняет SQL (`order`, `pluck`, `where` с диапазоном) или ответ API (`params.expect`)
или сигнатуру метода (`delegate` определяет `def x(...)` и бросает `DelegationError` на `nil`) —
механическим канонизатором не доказывается, нужен тест на каждое место.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r3-ci`) на
клоне BASE 4a749faa и на черновике (только для проверки достижимости, в веху не идёт):

1. Поведение Ruby 4.0.10: литерал без комментария chilled — мутация проходит, под `-W:deprecated`
   печатает `literal string will be frozen in the future`, с `--debug-frozen-string-literal` ещё и
   `the string was created here` (место создания); с комментарием или
   `--enable-frozen-string-literal` — `FrozenError … created at <файл:строка>`; `eval`/ERB
   комментарий вызывающего файла не наследуют. Внутри `rails_helper`-спеки предупреждение видно
   (подсаженная спека).
2. `rubocop -A --only Style/FrozenStringLiteralComment` — 127 офенсов, 127 файлов (`bin/setup` не
   в целях), комментарий в строке 1 каждого; затем 127 `Layout/EmptyLineAfterMagicComment` и 2
   `Style/RedundantFreeze` — оба исправляются автокорректом, после чего 0 офенсов.
3. `r3_frozen.rb shape`: 125 файлов SAME; 2 файла `FREEZE_FILES` — `freeze` EXPLAINED. Первый
   прогон дал 100 DIFF — флаги заморозки у Prism это FROZEN (16) **и** STATIC_LITERAL (2) у
   строки, STATIC_LITERAL и у массивов/хешей из литералов; маска поправлена; `paddle.rb` с
   `# frozen_string_literal: true` в строке 96 — не магический (после первого токена), учтено.
4. `r3_frozen.rb mutate` по 127 файлам дерева (559 файлов `app/ lib/ config/ spec/` для параметров и
   возвращаемых значений): 0 находок. Самопроверка (вшита в пробник) находит все 13 подсаженных
   мутаций и ни одной в `+""`/`dup`/`String.new`/интерполяции. Ручной просмотр всех
   `<<`/`concat`/`gsub!`/`force_encoding`/`StringIO` в 127 файлах: мутируются массивы и буферы
   `+""` (`dante/utils.rb` уже `each_with_object(+"")`).
5. Рантайм на BASE: полный сьют с `-W:deprecated --debug-frozen-string-literal` — 675/0/30, ни
   одного chilled-предупреждения; с `--enable-frozen-string-literal --debug-frozen-string-literal`
   (все литералы заморожены) — 675/0/30, ни одного `FrozenError`; `frozen_gate_r3.sh` на BASE —
   PASS (eager load OK, 675/0/30, ни одной строки о мутации литерала).
6. Черновик ровно по разделу 5 на свежем клоне с закоммиченными спекой и пробниками (коммит todo,
   коммит комментария — 127 файлов, коммит RedundantFreeze — 2 файла, коммит CHANGELOG):
   AC-001…AC-008 все зелёные. rspec 675/0/30 без warning-строк; AC-002 — 125 SAME, 2 EXPLAINED,
   `MUTATE 0 findings`; AC-003 — eager load OK, 675/0/30 при замороженных всех литералах;
   AC-004 — без todo BASE 2225 → дерево 2098, других копов не прибавилось; `bin/ci-local --only
   rubocop` OK. Плохие правки — раздел 7.
7. Снимки: `examples_base.txt`/`pending_allowed.txt`/`warnings_base.txt` —
   `rspec_gate_r3.sh --write-base` на чистом `main` 4a749faa (675 примеров, 30 pending, warning-
   строк нет — тот же список, что у R2).

Предположения: гемы, которые сьют не вызывает, не мутируют строки, полученные из 127 файлов
(статический разбор видит только `app/ lib/ config/ spec/`; известные API-буферы перечислены);
тела rake-задач (не только их загрузка) и пути плагинов `app/services/message_apis/*`, не
покрытые сьютом, проверены только статически.

## 5. Что сделать

Все команды RuboCop — в образе `bin/ci-local` (`-v $PWD:/app`,
`-v $CHASKIQ_R3_CACHE/bundle-ubuntu-26.04:/app/vendor/bundle`, `BUNDLE_PATH=/app/vendor/bundle`).
Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Коммит `Drop R3 cops from RuboCop todo`: `.rubocop_todo.yml` = BASE без блока
   `Style/FrozenStringLiteralComment` (блоки разделены пустой строкой; блок удалён целиком с
   комментариями), больше ничего (`expected_todo()` в `r3_equiv_probe.py`). Перегенерация
   `--auto-gen-config` запрещена. `.rubocop.yml` не меняется.
2. Коммит `Autocorrect Style/FrozenStringLiteralComment`:
   `bundle exec rubocop -A --only Style/FrozenStringLiteralComment`, затем
   `bundle exec rubocop -a --only Layout/EmptyLineAfterMagicComment`. Ровно 127 файлов
   (`FSL_FILES`), `bin/setup` не трогать.
3. Коммит `Autocorrect Style/RedundantFreeze`: `bundle exec rubocop -A --only Style/RedundantFreeze`.
   Ровно 2 файла `FREEZE_FILES`.
4. После каждого коммита — `python3 -I docs/specs/fork-updates-r3-probes/r3_commits_probe.py $B`
   (на промежуточных коммитах ожидаемо только `missing commits`); любая другая FAIL-строка —
   остановиться (раздел 9). Ручные правки Ruby-файлов запрещены.
5. В конце `bundle exec rubocop` по дереву — 0 офенсов; `CHANGELOG.md` — одна строка в новом
   разделе «## <дата> — fork-updates-r3» → «Changed» сразу после строки `# Changelog` (текст BASE
   ниже не меняется): `# frozen_string_literal: true` в 127 файлах
   (RuboCop), ни один литерал не мутируется (статический разбор + сьют с заморозкой всех
   литералов). Коммит ровно `Note fork-updates-r3 in changelog`, только `CHANGELOG.md`. После него
   допустимы только коммиты, меняющие один `CHANGELOG.md` (правка формулировки по ревью);
   замечание ревью, требующее правки Ruby-файла, — раздел 9.
6. В `report.json`, `note` AC-002 — строки `files:` и `MUTATE …` из вывода пробника дословно;
   `note` AC-003 — итоговая строка примеров.

## 6. Не трогать

- Всё, кроме `.rubocop_todo.yml`, `CHANGELOG.md` и 127 файлов `FSL_FILES` (обычные файлы, тот же
  git-режим, не симлинки). Новых файлов нет, файлы не удаляются (AC-002).
- `bin/setup`, `.rubocop.yml`, версии гемов, `Gemfile`, `Gemfile.lock`, RuboCop и плагины,
  `.ruby-version`, `Dockerfile*`, `docker-compose.yml`, workflows, `bin/*`, `.githooks/`, `db/`,
  `config/`, `package.json`, `yarn.lock`.
- Копы вне раздела 3 (в том числе Rails-копы R3b): не исправлять «заодно». Никаких
  `# rubocop:disable`/`todo`/`enable`, никаких `.dup`/`+""` «на всякий случай» — правка только
  автокорректом.
- Существующие спеки: удалять, skip-ать, ослаблять запрещено; меняет их только автокоррект.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-007, sha256). Всё, что принесли
  m1–m14, R1 и R2, не откатывать.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только закоммиченный .rspec; тела примеров действительно выполнены (сторож r3_sentinel.rb: не меньше, чем примеров минус pending); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R3_CACHE=$HOME/.cache/chaskiq-r3-ci bash docs/specs/fork-updates-r3-probes/rspec_gate_r3.sh'`

- **AC-002** — форма и равенство: самопроверка r3_frozen.rb проходит; каждый изменённый путь — обычный файл с тем же git-режимом, todo, CHANGELOG или файл из списка копа; нет игнорируемых, но существующих .rspec*/файлов под app/lib/config/spec; каждый из 127 файлов изменён ровно на комментарий и пустую строку наверху (2 файла FREEZE_FILES — плюс снятый .freeze), дерево Prism то же (SAME/EXPLAINED); статический поиск мутаций литералов — 0 находок; todo = BASE без блока копа; .rubocop.yml не тронут.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3-probes/r3_equiv_probe.py $B'`

- **AC-003** — рантайм с заморозкой всех литералов: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); eager load приложения и rake-файлов прошёл; полный сьют с --enable-frozen-string-literal --debug-frozen-string-literal -W:deprecated завершился 0, 0 failures, примеров не меньше, чем на BASE; в выводе нет FrozenError, can't modify frozen String и предупреждений о мутации литерала.
  `bash -c 'CHASKIQ_R3_CACHE=$HOME/.cache/chaskiq-r3-ci bash docs/specs/fork-updates-r3-probes/frozen_gate_r3.sh'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Style/FrozenStringLiteralComment и Style/RedundantFreeze 0 офенсов; ни у одного другого копа ни в одном файле офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3_CACHE=$HOME/.cache/chaskiq-r3-ci bash docs/specs/fork-updates-r3-probes/r3_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r3-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно: коммиты идут ровно в порядке раздела 5; ни один коммит не меняет git-режим и тип пути; коммит todo меняет только todo, коммит CHANGELOG только CHANGELOG, и CHANGELOG в каждом коммите — это CHANGELOG BASE с одним непустым блоком про fork-updates-r3 сразу после строки «# Changelog»; коммит комментария меняет ровно 127 файлов списка и каждый — SAME (родитель + комментарий, дерево то же); коммит RedundantFreeze меняет ровно 2 файла и каждый EXPLAINED.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3-probes/r3_commits_probe.py $B'`

- **AC-007** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "b6cff89254e380efdc46f5b196fc187958cdd1bf798bb1d8cb8b3d756dd84c32  docs/specs/fork-updates-r3-probes/examples_base.txt" "dab2103621c29999d87706eaff91708e1caa30375f5a5b8f849ee5595d426a6e  docs/specs/fork-updates-r3-probes/pending_allowed.txt" "ec396f65c66825d52c74e1d008fabd9dbcf7c88c79202f40eed5890792883476  docs/specs/fork-updates-r3-probes/warnings_base.txt" "b7a474a06d0b98164c1972340e377afbb03c29c852204cf71e2002c4df7134ba  docs/specs/fork-updates-r3-probes/rspec_gate_r3.sh" "5ddae8ddd24242c2e1e7bd8ca315eee01c930eab379e6f67b545e66178e6b04a  docs/specs/fork-updates-r3-probes/r3_equiv_probe.py" "89c98f0fb14a695da99a086c2bfdd1f54f0df502bd8fa285bccb73cf76b4dd01  docs/specs/fork-updates-r3-probes/r3_frozen.rb" "777a49f8df6c2fd7eb698b6471453b574665ee7ad42fac8211ffe8d03a18c8cb  docs/specs/fork-updates-r3-probes/frozen_gate_r3.sh" "76a7f49263d3afb8459823645f7d9bc9c53fa007fa19875a6474e526c07d37a0  docs/specs/fork-updates-r3-probes/r3_backlog_probe.sh" "454e950c622b9a53f55bd75191d9f4d64329eff99297488e5540be10a0b1d70e  docs/specs/fork-updates-r3-probes/r3_commits_probe.py" "e0a8b5cd6c33f26670d7586ce1b7852495aa0270122671834811142787276c6f  docs/specs/fork-updates-r3-probes/r3_sentinel.rb" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-008** — дерево чистое (сбой git — тоже FAIL: первый вызов проверяет код возврата), и нет игнорируемых, но существующих файлов, меняющих прогон тестов (.rspec-local, .rspec-parallel, что-либо под app/, lib/, config/, spec/).
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-003, AC-005, AC-007, AC-008
зелёные; AC-002 красный (`files of the Style/FrozenStringLiteralComment list without the change`,
`.rubocop_todo.yml is not BASE minus …`); AC-004 красный (`Style/FrozenStringLiteralComment: 127
offenses left`); AC-006 красный (`missing commits: [...]`).

Проверено на черновике (каждая правка → FAIL названного критерия):
- AC-002: мутация литерала в файле списка (`s = "x"; s << "y"` — и форма, и `literal may be
  mutated … mutator`); вызывающий в другом файле мутирует литерал, который возвращает метод файла
  списка (`err.update_record << "x"` — `… return update_record …`); `chmod +x`; лишняя строка
  комментария; `frozen_string_literal: false`; правка `bin/setup`; лишняя строка в todo; правка
  `.rubocop.yml`; `.dup` вместо снятого `.freeze` в файле FREEZE_FILES; `.rspec-local` с
  `--dry-run`, спрятанный через `.git/info/exclude`; игнорируемый `spec/support/zz_local.rb`.
- AC-001: тот же `.rspec-local` — FAIL до запуска; `SPEC_OPTS=--dry-run` — FAIL. Сторож проверен
  отдельно: `spec/models/segment_spec.rb` с `--dry-run` — rspec «15 examples, 0 failures», сторож 0
  строк (без `--dry-run` — 15), то есть гейт упал бы и при dry-run, пришедшем другим путём.
- AC-003: тот же `.rspec-local` — FAIL до запуска. `R3_PLANT = "seg".public_send(:concat, "x")` в теле класса файла списка (статический
  разбор `public_send` не видит) — eager load падает `FrozenError`; тот же вызов в
  `SegmentComparator#initialize` — 28 failures `can't modify frozen String: "seg"`, FAIL.
- AC-006: переставленные коммиты копов; комментарий и `.freeze` одним коммитом; Ruby-файл в
  коммите todo; `bin/setup` в коммите комментария; смена литерала в коммите RedundantFreeze;
  Ruby-правка в коммите CHANGELOG; `chmod +x` и обратно двумя коммитами (итоговое дерево равно
  чистому — AC-002 не видит, AC-006 FAIL на обоих коммитах); `chmod +x` в коммите комментария,
  снятый в коммите CHANGELOG; CHANGELOG опустошён; правка старой записи CHANGELOG; запись без
  `fork-updates-r3`; запись в конце файла, а не после `# Changelog`.
- AC-008: тот же `.rspec-local` и игнорируемый файл под `spec/support/`; дерево вне
  git-репозитория (как в R2).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r3.md --exclude "docs/specs/fork-updates-r3-probes/**" --context "chaskiq fork-updates-r3: RuboCop -A Style/FrozenStringLiteralComment в 127 файлах (комментарий + пустая строка) и каскад Style/RedundantFreeze в 2 файлах, секция удалена из todo; риск — мутация замороженного литерала (FrozenError); только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r3.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r3-probes/**

Контекст ревьюерам: главный риск — литерал из этих файлов, который где-то мутируется (`<<`,
`force_encoding`, `gsub!`, буфер `StringIO`/`read`) на пути, которого нет в сьюте; нет ли правок
кроме комментария; не ослаблены ли спеки.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 8: AC-001…AC-008. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-002 — строки `files:` и
`MUTATE …`; в `note` AC-003 — итоговая строка примеров; в `note` AC-004 — строка
`backlog without todo: …`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r3.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r3.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- `r3_equiv_probe.py` даёт находку `literal may be mutated` или `shape`/`freeze` говорит `DIFF` —
  укажи файл, строку, вывод; решение (исключить файл из вехи, вернуть его в todo, или правка кода
  отдельной вехой с тестом) принимает постановщик;
- `frozen_gate_r3.sh` (AC-003) красный: `FrozenError`/`can't modify frozen String` — приложи
  строку с местом создания литерала (`created at …`); красный по причине вне дерева (флап,
  среда) — приложи два прогона;
- `r3_commits_probe.py` (AC-006) не проходит при коммитах ровно по разделу 5;
- автокоррект меняет не 127/2 файла или рождает офенсы других копов;
- зелёный AC-004/AC-005 недостижим без правки чужих секций todo, `rubocop:disable` или
  настройки в `.rubocop.yml`;
- замечание ревью требует правки Ruby-файла (весь код вехи пишет автокоррект);
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-r3-ci` или сервисы недоступны.
Запрещено: ручные правки Ruby-файлов (в том числе `.dup`/`+""`), перегенерация
`.rubocop_todo.yml`, правка пробников, удалять и skip-ать тесты, ослаблять ассерты, глушить вывод
и коды возврата.

## 10. Стыки

- Следующие вехи — R3b плана (Rails-копы с тестом на каждое место) и R2b (ручной разбор). Все
  вехи правят `.rubocop_todo.yml` и идут строго последовательно.
- `r3_frozen.rb mutate` переиспользуется, если `frozen_string_literal` понадобится файлам вне
  нынешнего списка (новые файлы R7 обязаны иметь комментарий — их проверяет сам коп).
- `frozen_gate_r3.sh` можно держать как разовую проверку перед переходом на Ruby, где литералы
  заморожены по умолчанию: на BASE весь сьют с `--enable-frozen-string-literal` уже зелёный.
