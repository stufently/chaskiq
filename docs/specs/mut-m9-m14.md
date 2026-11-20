# mut-m9-m14 — мутационная проверка тестов вех m9–m14, недостающие тесты

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/mut-m9-m14.md`, пробники — `docs/specs/mut-m9-m14-probes/`.
- BASE_SHA: `7553575ce9ab1cc73ba9facc9a98ef1b8702cd47` — HEAD `main` (m9–m14, R1, R2, R3 влиты). Черновик проверен на
  6f377c93 (до слияния R3); R3 менял в `spec/` и в целях только первую строку (магический
  комментарий), список примеров тот же.
- BASE плавающий: если до запуска `main` уйдёт вперёд, постановщик коммитит новое значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению строки
  BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-005).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; `accept_run.py`
  ищет квитанции по `base_sha` из `report.json`).
- Исполнитель: **Qwen (`qw2`)** — решение владельца: вехи пишет Codex, отдельный мутационный проход
  по новым тестам каждой вехи — Qwen. Проверку потом смотрит Codex.
- Цель: по коду, который изменили вехи m9–m14, прогнать осмысленные мутанты по одному, записать
  для каждого killed/killed_new/equivalent, и на каждого выжившего написать тест, который его
  убивает (только файлы под `spec/`); ни одного изменения боевого кода; полный rspec зелёный с
  новыми тестами; каждый новый тест краснеет на своём мутанте (AC-003 переприкладывает патчи).

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `mut-m9-m14`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid, без sudo/root; на хост ничего не ставить. Всё через образ
  `bin/ci-local`. Кэш: `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mut-ci` (копия `chaskiq-r3-ci`, уже
  создан; если нет — `cp -a $HOME/.cache/chaskiq-r3-ci $HOME/.cache/chaskiq-mut-ci`).
- Мутанты НИКОГДА не коммитятся. Патч каждого мутанта и `manifest.json` — в `tmp/mutants/` клона
  (игнорируется git, не коммитится); `mut-report.md` и `report.json` — в корне клона, untracked.

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Если `main` ушёл вперёд (например, влит R3): перенести BASE_SHA; если изменились тесты —
   перегенерировать список примеров:
   `CHASKIQ_MUT_CACHE=$HOME/.cache/chaskiq-mut-ci bash docs/specs/mut-m9-m14-probes/rspec_gate_mut.sh --write-base`
   на чистом checkout `main`. Сейчас в снимках — список примеров `main` 4a749faa (675 примеров,
   30 pending, без warning-строк); 6f377c93 отличается от него только `docs/`.
2. Если код файлов `targets.json` на `main` поменялся (R3 добавляет только комментарий в строку 1
   своих файлов — среди целей это `app/services/dante/utils.rb`) — ничего делать не надо: мутанты
   снимаются с текущего BASE.
3. Закоммитить в `main` одним коммитом: спеку, пробники, снимки, их sha256 в AC-005 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

Команды (из корня клона; `B=$(git merge-base HEAD @{u})`):

```bash
P=docs/specs/mut-m9-m14-probes
export CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mut-ci CHASKIQ_MUT_CACHE=$HOME/.cache/chaskiq-mut-ci
bin/ci-local --only rspec --rspec-args "--options .rspec spec/a_spec.rb spec/b_spec.rb"   # прогон мутанта, ~1–2 мин
python3 -I $P/mut_probe.py scope $B           # только spec/ изменён, боевой код = BASE (~2 с)
python3 -I $P/mut_probe.py manifest $B        # манифест, патчи, переприложение выживших (~2 мин на мутанта)
bash $P/rspec_gate_mut.sh                     # полный rspec, ~10 мин
```

## 3. Задача и почему

Вехи m9–m14 добавили и поменяли защитный и поведенческий код вместе с тестами, но никто не
проверял, что эти тесты ловят поломку кода. Мутационный проход отвечает на это: мутант, на котором
все тесты зелёные, — дыра в тестах.

Цели — `targets.json` (47 записей; построен из `git diff <merge>^1 <merge>` по `app/ lib/ config/
vendor/nightfury vendor/php_serialize` для каждой вехи): `milestone`, `merge` (SHA слияния), `file`,
`changed_lines` (+/− строк вехи), `min_mutants` (≥100 строк — 10; ≥10 — 5; 3–9 — 2; 1–2 — 1;
исключённые — 0 с причиной в `excluded`), `specs_hint` (spec-файлы, которые изменила веха) и
`focus` (что мутировать в первую очередь). Итого минимум 159 неэквивалентных мутантов.

| Веха | Боевой код (мин. мутантов) | Приоритет |
|---|---|---|
| m9 | `conversation_part_channel_source.rb` (5), `base_package.rb` (10), `block_manager.rb` (5), `dialog360/api.rb` (5), `twilio/api.rb` (5), `helpers.rb`, `message_bird`, `telegram`, `vonage` `api.rb` (1–2) | delivery_index / advisory lock, уникальность доставки |
| m10 | `sns_message_verifier.rb` (10), `hooks_controller.rb` (5) | SNS: хост/схема/порт cert URL, версия подписи, строка для подписи, время, кэш, коды ответа |
| m11 | `safe_download.rb` (5), `telnyx_sms/api.rb` (10) | SafeDownload: хост/IP, повторная проверка редиректа, лимиты; allowlist медиа Telnyx |
| m12 | `offline_checker_job.rb` (5), `lib/rack/health_check.rb` (5), `vendor/nightfury/**` (5–10 на файл), мелкие (1–2) | присутствие/offline, коды health check, метрики nightfury |
| m13 | `rack_attack.rb` (5), `rack_forwarded_values.rb` (5), `lib/middleware/rack_bad_request.rb` (5), мелкие (1–2) | ключ и лимиты Rack::Attack, разбор forwarded, что становится 400 |
| m14 | `vendor/php_serialize/lib/php_serialize.rb` (10), мелкие (2) | байтовый вывод serialize/unserialize |

Исключены (0, причина в `targets.json`): LICENSE, `version.rb`, gemspec и `test.rb` php_serialize,
`config/redis/shared.yml`, `config/environments/{development,test}.rb`, `cypress_on_rails.rb`.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-mut-ci`):

1. `bin/ci-local --only rspec --rspec-args "--options .rspec <spec-файлы>"` гоняет только
   указанные файлы (~1–2 мин на прогон с поднятием сервисов): мутант «убрана проверка `.pem` у cert
   URL» в `sns_message_verifier.rb` — `24 examples, 1 failure`; «убрана проверка фрагмента» — тоже
   убит (`40 examples, 1 failure`); `b:1`↔`b:0` в `php_serialize.rb` — `5 examples, 2 failures`.
2. Черновик механики (две цели с `min_mutants` 1 в отдельном targets-файле, мутант killed и мутант
   killed_new с новым тестом под `spec/`) — все критерии зелёные, плохие правки — раздел 7.
3. Снимки примеров — `main` 4a749faa (тот же код и тесты, что у BASE).

Предположение: ~160+ прогонов по 1–2 мин — несколько часов; это нормально для вехи.

## 5. Что сделать

Коммиты — ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Для каждой цели `targets.json` с `min_mutants > 0`: прочитать дифф вехи
   (`git diff <merge>^1 <merge> -- <file>`) и тот же код в BASE (после вех его косметически
   переформатировали R1/R2). Мутировать КОД, который веха добавила или изменила, в первую очередь
   `focus`: перевернуть условие, убрать охранную проверку/`return`/`raise`, поменять константу или
   лимит (на 1 и на «бесконечность»), убрать вызов, поменять код ответа или класс ошибки, ослабить
   регулярку, поменять порядок полей. Мутант — одна правка, меняющая поведение; правка только
   комментария/пробелов — не мутант (AC-003 отбрасывает).
2. Каждый мутант строго по одному:
   - применить правку; `git diff > tmp/mutants/<ID>.patch` (ID `M001`, `M002`, …);
   - прогнать ТОЛЬКО релевантные spec-файлы (из `specs_hint` и те, что вызывают этот код):
     `bin/ci-local --only rspec --rspec-args "--options .rspec <файлы>"`;
   - вернуть файл: `git checkout -- <file>`, затем `git status --porcelain` — пусто (кроме
     untracked `report.json`/`mut-report.md`); иначе остановиться;
   - записать в `tmp/mutants/manifest.json` (формат — шапка `mut_probe.py`): `killed`, если
     красный; выживший — сначала проверить, что правка действительно применилась и меняет
     поведение (не эквивалент); эквивалентный — `equivalent` с причиной ≥ 20 символов (не больше
     20% мутантов цели).
3. На каждого выжившего неэквивалентного — тест, который его убивает: только новые или изменённые
   файлы под `spec/` (существующие примеры не удалять, не ослаблять, не skip-ать). Проверить: с
   мутантом новый тест красный, без мутанта — зелёный. Статус — `killed_new`, `test_added` — путь
   spec-файла, он же в `specs`. Коммит тестов — `Add tests for mutants in <веха>` (только `spec/`).
4. `mut-report.md` в корне клона: таблица «веха | файл:строка | мутант | killed / killed_new /
   equivalent | тест» по каждому ID манифеста, плюс итог по вехам.
5. Новые spec-файлы проходят строгий RuboCop (их нет в todo): `# frozen_string_literal: true`,
   двойные кавычки и т. д.

## 6. Не трогать

- Ничего вне `spec/`: `app/`, `lib/`, `config/`, `vendor/`, `db/`, `Gemfile*`, `.rubocop*`,
  `.rspec`, `bin/`, workflows. Мутанты — только в рабочем дереве, по одному, всегда откатываются.
- Существующие примеры под `spec/` не удалять, не skip-ать, не ослаблять (AC-001 требует все
  примеры BASE). Не добавлять `.rspec-local` и игнорируемые файлы под `spec/` (AC-002, AC-006).
- `docs/specs/**` — не править (AC-005, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec с новыми тестами строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE, pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_MUT_CACHE=$HOME/.cache/chaskiq-mut-ci bash docs/specs/mut-m9-m14-probes/rspec_gate_mut.sh'`

- **AC-002** — изменён только spec/: против BASE и в каждом коммите — только добавленные или изменённые файлы под spec/ с прежним git-режимом; HEAD и рабочее дерево вне spec/ равны BASE (ни один мутант не оставлен и не закоммичен); нет лишних неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec/vendor.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/mut-m9-m14-probes/mut_probe.py scope $B'`

- **AC-003** — манифест и переприложение: у каждой цели не меньше min_mutants неэквивалентных мутантов; у каждого мутанта патч трогает ровно свой файл, прикладывается и меняет синтаксическое дерево; статусов survived нет, equivalent с причиной и не больше 20%; mut-report.md называет каждый ID; каждый killed_new и выборка из 8 killed переприложены по одному — их spec-файлы красные (у killed_new — именно в добавленном тесте), после каждого дерево снова чистое.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mut-ci python3 -I docs/specs/mut-m9-m14-probes/mut_probe.py manifest $B'`

- **AC-004** — строгий RuboCop как в CI: все отслеживаемые файлы (с новыми spec-файлами), оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-mut-ci bin/ci-local --only rubocop'`

- **AC-005** — коммитов в docs/specs нет, пробники и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "2a1345d57ee18c06c3cdb58d62742b9606869c44208041a4982e5840d57cbf99  docs/specs/mut-m9-m14-probes/mut_probe.py" "8b9fec61052434caeab459072fb230183a2d72b23f50f27d76a4a49e7adca7c2  docs/specs/mut-m9-m14-probes/targets.json" "e118cfe0f62ce49335a1ac8e601e9753b30980a0225d4f8943c2efa8e6abdbca  docs/specs/mut-m9-m14-probes/rspec_gate_mut.sh" "c4e4d15330c1a174b2c39b96d12e4c69da786dac690bb6b8e852206a382dffe5  docs/specs/mut-m9-m14-probes/mut_sentinel.rb" "b6cff89254e380efdc46f5b196fc187958cdd1bf798bb1d8cb8b3d756dd84c32  docs/specs/mut-m9-m14-probes/examples_base.txt" "dab2103621c29999d87706eaff91708e1caa30375f5a5b8f849ee5595d426a6e  docs/specs/mut-m9-m14-probes/pending_allowed.txt" "ec396f65c66825d52c74e1d008fabd9dbcf7c88c79202f40eed5890792883476  docs/specs/mut-m9-m14-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-006** — дерево чистое (сбой git — тоже FAIL), кроме untracked report.json, report-blocked.md, mut-report.md; нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md" ":(exclude)mut-report.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-002, AC-004, AC-005, AC-006 зелёные; AC-003 красный
(`tmp/mutants/manifest.json: … No such file`).

Проверено на черновике (две цели с `min_mutants` 1 в отдельном targets-файле `--targets`: M001,
M003 killed в `sns_message_verifier.rb`, M002 killed_new в `php_serialize.rb` с новым
`spec/lib/php_serialize_bool_spec.rb`): AC-001 (675+1 примеров, сторож 648), AC-002, AC-003
(переприложены все три — красные), AC-004…AC-006 зелёные; с настоящим `targets.json` AC-003 красный
(37 целей ниже `min_mutants`). Плохие правки → FAIL:
- AC-002: мутант оставлен в дереве; мутант закоммичен; правка боевого файла и откат двумя
  коммитами (итог равен BASE — ловит проверка каждого коммита); удалён существующий spec-файл.
- AC-003: статус `survived`; мутант только из пробела (дерево Prism то же); патч трогает не тот
  файл, что в манифесте; `equivalent` без причины (и > 20%); ID нет в `mut-report.md`; killed_new,
  чей `test_added` не краснеет на мутанте (падает только старый spec — FAIL).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/mut-m9-m14.md --exclude "docs/specs/mut-m9-m14-probes/**" --context "chaskiq mut-m9-m14: мутационный проход по коду вех m9-m14, новые тесты только под spec/ на выживших мутантов; боевой код не меняется; только чтение"`

(то же для второго ревьюера). Исключения:

REVIEW_EXCLUDE: docs/specs/mut-m9-m14.md
REVIEW_EXCLUDE: docs/specs/mut-m9-m14-probes/**

Контекст ревьюерам: убивает ли каждый новый тест именно поведение мутанта (а не, например,
падает на опечатке); не ослаблены ли существующие тесты; нет ли тестов, зависящих от порядка или
сети.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 6: AC-001…AC-006. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-003 — строка `mutants: …` из вывода пробника; в `note` AC-001 — итог примеров.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/mut-m9-m14.md>",
  "base_sha": "<значение строки BASE_SHA шапки>",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "qwen", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция agy>", "<квитанция codex>"],
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/mut-m9-m14.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- выживший мутант, которого нельзя убить тестом без правки боевого кода (код недостижим из
  теста, нужна инъекция зависимости) — оставить в манифесте как `survived` нельзя: опиши мутант,
  патч и почему, решение примет постановщик;
- мутант выявил настоящий дефект боевого кода (тест на правильное поведение красный и без
  мутанта) — не чинить код; тест не коммитить; описать;
- `git checkout -- <file>` не вернул дерево к чистому состоянию;
- сьют BASE красный или флапает (приложи два прогона), образ/кэш/сервисы недоступны;
- пробник противоречит спеке или коду BASE (дефект спеки).
Запрещено: коммитить мутанты или любые файлы вне `spec/`, удалять/ослаблять/skip-ать тесты, править
пробники и `targets.json`, помечать выживших `equivalent` без доказательства, глушить вывод и
коды возврата.

## 10. Стыки

- Дальше — тот же проход после каждой вехи, добавившей тесты (R-вехи тестов не добавляют).
- Найденные дефекты боевого кода (раздел 9) — отдельными вехами Codex с тестом.
