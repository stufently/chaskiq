# fork-updates-r7a — бэклог RuboCop: три копа выключены решением владельца, с причиной

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r7a.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (эта веха — конфигурационная часть R7 оттуда,
  блок «Решения владельца (2026-11-20)»).
- BASE_SHA: `e3ba32a68501f04e9fa1f55e89727daff56938d1` — HEAD `main` с влитым R3 и закоммиченной
  спекой mut-m9-m14 (Ruby 4.0.10, RuboCop 1.92.3).
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-005).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA; `accept_run.py` ищет квитанции по `base_sha` из
  `report.json`.
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`).
- Цель: `Style/Documentation`, `Naming/AccessorMethodName`, `Naming/MethodParameterName` выключены в
  `.rubocop.yml` блоком с письменной причиной каждого (текст — `BLOCK` в `r7a_probe.py`), их секции
  удалены из `.rubocop_todo.yml`; ни одного изменения кода; строгий RuboCop CI зелёный; бэклог без
  todo теряет ровно офенсы этих трёх копов, у остальных копов ничего не меняется ни в одном файле.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r7a`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root. На хост ничего не
  ставить. Всё — через образ `bin/ci-local` (Ruby 4.0.10). Свой кэш: `$HOME/.cache/chaskiq-r7a-ci`.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. R3 влит (BASE уже после него). Если `main` ещё уйдёт вперёд — перенести BASE_SHA на новый HEAD
   и перемерить: у трёх копов всё ещё есть секции в todo и
   нет настроек в `.rubocop.yml` (пробник сам падает со «spec defect», если нет); в `.rubocop.yml`
   ровно одна строка `AllCops:`; числа раздела 3 — по выводу `r7a_backlog_probe.sh` на черновике.
   Снимков rspec у вехи нет (раздел 3), перегенерировать нечего.
2. Кэш: `$HOME/.cache/chaskiq-r7a-ci` — копия `chaskiq-r3-ci` (уже создан); если его нет —
   `cp -a $HOME/.cache/chaskiq-r3-ci $HOME/.cache/chaskiq-r7a-ci`.
3. Закоммитить в `main` одним коммитом: спеку, пробники, их sha256 в AC-005 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.
4. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/fork-updates-r7a-probes
export CHASKIQ_R7A_CACHE=$HOME/.cache/chaskiq-r7a-ci
python3 -I $P/r7a_probe.py tree $B            # побайтовые .rubocop.yml/todo/CHANGELOG, разрешённый конфиг (~20 с)
bash $P/r7a_backlog_probe.sh $B               # rubocop без todo: три копа 0, остальные без изменений (~3 мин)
python3 -I $P/r7a_probe.py commits $B         # коммиты по порядку, каждый проверен (~2 с)
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r7a-ci bin/ci-local --only rubocop   # строгий RuboCop как CI
```

## 3. Задача и почему

Владелец решил (план, R7, 2026-11-20): `Style/Documentation` — заглушки «# Class for X» пользы не
несут; `Naming/AccessorMethodName` и `Naming/MethodParameterName` — переименование публичных
методов и их параметров ломает плагины и интеграции. Выключить с причиной в `.rubocop.yml`, а не
держать вечными исключениями в todo.

Замер на черновике (BASE e3ba32a6, бэклог без todo): 2098 офенсов, из них `Style/Documentation`
402, `Naming/AccessorMethodName` 32, `Naming/MethodParameterName` 18 — итого 452; после вехи 1646,
у всех остальных копов — те же офенсы в тех же файлах.

Меняются ровно три файла: `.rubocop.yml` (вставлен `BLOCK` — 3 комментария-причины и 3 настройки
`Enabled: false` — прямо перед строкой `AllCops:`), `.rubocop_todo.yml` (удалены три блока копов,
блоки разделены пустой строкой, с их комментариями), `CHANGELOG.md`. Ruby-код не меняется, поэтому
rspec вехе не нужен: конфигурация RuboCop приложением не загружается, а то, что изменились только
эти три файла, проверяет AC-001.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r7a-ci`):

1. Черновик ровно по разделу 5 на клоне с закоммиченными пробниками: AC-001…AC-006 зелёные
   (`rubocop --show-cops` даёт `Enabled: false` у всех трёх; бэклог 2098 → 1646; `bin/ci-local
   --only rubocop` OK).
2. `rubocop --show-cops` принимает список копов только через запятую (с пробелами печатает лишь
   первый) — пробник передаёт через запятую.
3. Плохие правки — раздел 7.

Перемерено после слияния R3 (BASE e3ba32a6): секции трёх копов в todo те же, что до R3; изменилось
только общее число бэклога (2225 → 2098 на BASE).

## 5. Что сделать

Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Коммит `Disable three cops by owner decision` — ровно два файла, одним коммитом (строгий CI
   должен быть зелёным на каждом коммите):
   - `.rubocop.yml` = `expected_config()` из `r7a_probe.py` над файлом BASE: текст `BLOCK`
     (посимвольно, с комментариями) вставлен прямо перед строкой `AllCops:`, больше ничего;
   - `.rubocop_todo.yml` = `expected_todo()`: блоки `Style/Documentation`,
     `Naming/AccessorMethodName`, `Naming/MethodParameterName` удалены целиком с комментариями,
     больше ничего. Перегенерация `--auto-gen-config` запрещена.
2. `CHANGELOG.md` — новый раздел «## <дата> — fork-updates-r7a» → «Changed» сразу после строки
   `# Changelog` (текст BASE ниже не меняется): три копа выключены в `.rubocop.yml` по решению
   владельца с причиной, их записи удалены из todo, код не менялся. Коммит ровно
   `Note fork-updates-r7a in changelog`, только `CHANGELOG.md`. После него допустимы только коммиты,
   меняющие один `CHANGELOG.md` по тому же правилу.
3. В `report.json`, `note` AC-002 — строка `backlog without todo: …` дословно.

## 6. Не трогать

- Всё, кроме `.rubocop.yml`, `.rubocop_todo.yml`, `CHANGELOG.md`. Никаких правок Ruby-файлов,
  `# rubocop:` директив, других настроек `.rubocop.yml` (в том числе `AllCops`, `inherit_mode`,
  `plugins`), других секций todo.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `.githooks/`.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-005, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — конфиг и границы: самопроверка помощников проходит; изменены только .rubocop.yml, .rubocop_todo.yml, CHANGELOG.md с тем же git-режимом, нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; .rubocop.yml побайтово равен BASE с BLOCK перед AllCops:, todo побайтово равен BASE без трёх блоков; разрешённый конфиг RuboCop даёт Enabled: false у всех трёх копов; CHANGELOG — BASE с одним блоком про fork-updates-r7a после «# Changelog».
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7A_CACHE=$HOME/.cache/chaskiq-r7a-ci python3 -I docs/specs/fork-updates-r7a-probes/r7a_probe.py tree $B'`

- **AC-002** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок, на BASE и в дереве один и тот же список целей; у трёх копов 0 офенсов; у каждого другого копа в каждом файле ровно столько же офенсов, сколько на BASE; общий счёт уменьшился ровно на офенсы трёх копов на BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7A_CACHE=$HOME/.cache/chaskiq-r7a-ci bash docs/specs/fork-updates-r7a-probes/r7a_backlog_probe.sh $B'`

- **AC-003** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r7a-ci bin/ci-local --only rubocop'`

- **AC-004** — каждый коммит отдельно: ровно в порядке раздела 5; первый меняет ровно .rubocop.yml и .rubocop_todo.yml и оба равны ожидаемому тексту; следующие меняют только CHANGELOG по правилу AC-001; ни один коммит не меняет git-режим или тип пути, слияний нет.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7a-probes/r7a_probe.py commits $B'`

- **AC-005** — коммитов в docs/specs нет, пробники постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "ec7b9ecb4ca3ae589bb81db5546ef898ec74c300e46d31fdd7bb8522f0c12cab  docs/specs/fork-updates-r7a-probes/r7a_probe.py" "f3e119679194a856e3f046d36713aee092ff01d9af521c9bc281ad89810b7cfe  docs/specs/fork-updates-r7a-probes/r7a_backlog_probe.sh" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-006** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих файлов, меняющих прогон (.rspec-local, .rspec-parallel, что-либо под app/, lib/, config/, spec/).
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-003, AC-005, AC-006 зелёные; AC-001 красный (`.rubocop.yml is not
BASE with BLOCK …`, `resolved config is not 'Enabled: false'`); AC-002 красный
(`Style/Documentation: 402 offenses in the tree`); AC-004 красный (`missing commits`).

Проверено на черновике (каждая правка → FAIL названного критерия):
- AC-001: перефразированный комментарий-причина; лишний выключенный коп (`Style/CaseEquality`, ещё и
  AC-002: офенсы другого копа изменились, итог не сходится); удалена чужая секция todo; выключение
  через `Exclude: ["**/*"]` вместо `Enabled: false` (и разрешённый конфиг не `Enabled: false`);
  `# rubocop:disable` в Ruby-файле (и AC-002); `chmod +x .rubocop.yml`; игнорируемый `.rspec-local`;
  правка старой записи CHANGELOG.
- AC-004: конфиг и todo разными коммитами; `chmod +x` и обратно двумя коммитами CHANGELOG;
  опустошённый CHANGELOG.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r7a.md --exclude "docs/specs/fork-updates-r7a-probes/**" --context "chaskiq fork-updates-r7a: три копа (Style/Documentation, Naming/AccessorMethodName, Naming/MethodParameterName) выключены в .rubocop.yml с причиной по решению владельца, их секции удалены из todo; кода нет; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r7a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r7a-probes/**

Контекст ревьюерам: не выключено ли что-то сверх трёх копов; причины записаны; нет ли правок кода.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 6: AC-001…AC-006. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-002 — строка `backlog without todo: …`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r7a.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r7a.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- пробник говорит «spec defect» (секций нет, настройка уже есть, не одна строка `AllCops:`);
- AC-002 показывает изменение офенсов другого копа или другой список целей;
- зелёный AC-003 недостижим без других правок;
- замечание ревью требует правки, не предусмотренной разделом 5;
- образ, кэш `chaskiq-r7a-ci` недоступны.
Запрещено: менять текст `BLOCK`, другие настройки или секции, Ruby-файлы, пробники; глушить вывод
и коды возврата.

## 10. Стыки

- Остаток R7 (Style: `CaseEquality`, `OneClassPerFile`, `MixinUsage`, …; Naming: `PredicateMethod`,
  `PredicatePrefix`, `VariableName`, `VariableNumber`) — отдельными вехами по плану.
- R8 (Metrics с реальными лимитами и причинами) правит `.rubocop.yml` по тому же образцу: блок с
  причиной, побайтовая проверка.
