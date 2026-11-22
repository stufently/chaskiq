# fork-updates-r10i — выбросы RuboCop, шаг 10i: `dialog360` `configure_hook` — шаги мастера шаблона по методам, вывод пиннится снимками

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10i.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10i: «`configure_hook`
  224 строки (Abc 104, Cyc 24), `search_participant`. Риск в: шаблоны WhatsApp идут во внешний API
  (`retrieve_templates`, Base64 JSON шаблона). Характеризация: снимок `definitions` для каждого шага мастера шаблона с
  застабленным `message_api_klass`; WebMock — ни одного неожиданного запроса»; решение К1, раздел 2), план чистки —
  `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10g` (снимки пробником, мутанты в конфиге,
  четыре коммита). Соседние вехи — `r10g`, `r10h`, `r10l` (раздел 10).
- BASE_SHA: `fa3dcd142bd98f9fc7487d3c09cdde5fdaefc3ab` — HEAD `main` «Record R10g acceptance» (R10cfg/К1, R10c, R10e,
  R10g влиты; от 7a8ace58, где сняты снимки, `dialog360` не менялся; Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails
  2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10h` или другая веха — раздел 10), постановщик переносит BASE (раздел 2), коммитит новое
  значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают `B=$(git merge-base HEAD @{u})`
  сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спеки — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 105 КБ: ≈ 80 КБ — 29 файлов снимков, ≈ 17 КБ — презентер, ≈ 3 КБ — новая спека.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все десять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: у `MessageApis::Dialog360::Presenter.configure_hook` уходят 3 выброса todo (`AbcSize`, `CyclomaticComplexity`,
  `MethodLength`; их 3 строки уходят из todo) и строка `# rubocop:disable-next Metrics/PerceivedComplexity` над
  методом (четвёртый, спрятанный выброс). Код задан патчем постановщика `r10i_rewrite.patch`, снимки — патчем
  `r10i_snapshots.patch`, новая спека — файлом `r10i_spec.rb` (всё руками не править). Спека сверяет вывод
  `configure_hook` и вызовы API с 29 снимками: зелёная на коде BASE и после; каждый из 31 мутанта постановщика
  (`r10i_config.json`, `mutants`) роняет пример. Работа исполнителя — собрать веху шагами раздела 5, прогнать
  критерии, ревью и отчёт.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)` по коду, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое возвращаемое
значение (значение, ключ, порядок ключей), другое исключение или другие вызовы API. Чтение снимков
`spec/fixtures/**` — данные, оно разрешено. AC-008 (`source_scan.py`) ищет запрещённые приёмы в новых и изменённых
файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10i`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10i-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-r10e-ci $HOME/.cache/chaskiq-r10i-ci` (уже сделан при написании спеки).
2. При переносе BASE (после влития `r10h` или другой вехи) перемерить, патч не перегенерировать, пока всё
   сходится:
   - `git apply --check` обоих патчей (`r10i_snapshots.patch`, затем `r10i_rewrite.patch`) на новом `main` чист
     (проверено на fa3dcd14 с черновиками `r10h1`/`r10h2` в обоих порядках);
   - `dialog360/presenter.rb` на новом `main` побайтно тот же, что на 7a8ace58/fa3dcd14 (иначе — снимки заново из
     `tmp/r10i-snapshots/out/base` снимочного пробника на новом BASE, патч, мутанты);
   - в `.rubocop.yml` есть строка `  CountAsOne: [array, hash, heredoc]` (К1); 3 строки `dialog360/presenter.rb` в
     блоках `AbcSize`, `CyclomaticComplexity`, `MethodLength` todo на месте;
   - бэклог-пробник на копии нового `main` с обоими патчами и шагом 4: у презентера 3 → 0, роста нет, итог падает
     ровно на 3 — число `3` в команде AC-005 (fa3dcd14: 77 → 74; 7a8ace58: 81 → 78);
   - снимочный пробник на той же копии: `R10I SNAPSHOTS PASS 29 fixtures = BASE output = tree output`;
   - тексты 31 мутанта — каждый ровно один раз в `presenter.rb` после патча; имя новой спеки не занято;
   - перегенерировать снимки сьюта на чистом checkout `main`:
     `CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci bash docs/specs/fork-updates-r10i-probes/rspec_gate_r10i.sh --write-base`
     и пересчитать sha256 в AC-009. Сейчас в снимках — 1427 примеров BASE fa3dcd14.
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z. Если клон снимается позже — постановщик по желанию заменяет
   раздел 8 полной политикой `cross-review-v1` (codex + agy) до коммита спеки.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-009 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10i-ci`), на 7a8ace58 и fa3dcd14 одинаково. `configure_hook`
(`presenter.rb:89`): `AbcSize` 103.5/30, `CyclomaticComplexity` 24/13, `MethodLength` 69/30 (с К1).
`PerceivedComplexity` 25/13 RuboCop не показывает: его глушит строка 88
`# rubocop:disable-next Metrics/PerceivedComplexity` (без неё — 4 офенса; в todo строки `PerceivedComplexity` у
файла нет). `search_participant` с К1 офенсов не имеет (Abc 20.64, Cyc 5) — его код
не меняется, но он ветка `configure_hook` и пиннится снимками. Других офенсов у файла нет.

Метод — мастер шаблона WhatsApp (`ctx` из `AppPackageIntegration#call_hook`): страница из `paginate-template-N`;
без `conversation_key`/`selected-user`/`values.selected_user` → `search_participant`; `retrieve_templates(offset:)`,
`meta.success == false` → текст ошибки с входным `kind`; список одобренных шаблонов (id — `Base64.encode64(to_json)`)
с кнопками `<- Prev`/`Next ->` и скрытым полем при `selected-user`; `submit-template` (`action.type` submit) → форма
параметров `{{N}}`; `pick-template` → `send_template_message`, «sent»/«NOT sent» (не хеш — список); оба шага —
`kind: "configure"` с `results`; иначе — список с входным `kind`.

**`r10i_rewrite.patch`** (только `presenter.rb`): строка директивы и закомментированные `Rails.logger` удалены;
`configure_hook` — 11 строк: `template_offset`, `participant_missing?`, `templates_error_response`,
`templates_definitions` (список, пагинация, пункты, скрытое поле), таблица `TEMPLATE_STEPS` (`submit-template` →
`submit_template_response`, `nil` при `action.type` ≠ submit — тогда ответ по умолчанию; `pick-template` →
`pick_template_response`); `per = 10` → `TEMPLATES_PER_PAGE`. Новые методы — `private_class_method`. После патча:
`configure_hook` Abc 15.17, Cyc 5, Perceived 5; максимум у новых — Abc 15.1, Cyc 5. У файла 0 офенсов.

**Почему поведение то же.** Порядок вычислений сохранён: страница считается ДО ворот поиска (`paginate-template`
без `id` — тот же `NoMethodError` до поиска); ворота — то же выражение; `retrieve_templates` с той же страницей;
список строится до шагов (тот же `Base64`/`to_json` ActiveSupport, тот же `Rails.logger.debug`); шаги — в прежнем
порядке проверок. Формы ключей `ctx` — те же, что в BASE, по месту (`ctx.dig("field", …)` строками, `ctx.dig(:field,
…)` символами, `ctx['package']`): на plain-хеше с символьными ключами BASE ведёт себя иначе, чем на indifferent, и это
пиннится снимками `*_symbol_keys*`. Поиск шага по хешу вместо `==` для строк и `nil` одно и то же. `template_inputs`
оставлен на `each` (тот же `NoMethodError` у шаблона без `components`). Ветки «sent»/«NOT sent» взаимно исключающие,
как в BASE.

**Доказательство.** `r10i_snapshot.rb` (`bundle exec ruby`, только ActiveSupport, без Rails, БД и сети) грузит файл
презентера под `Coverage` и для 29 случаев конфига вызывает `configure_hook` с фейковым `package`: фейковый API
отвечает только тем, что в случае задано (`templates_json`, `send_json`, `users`), каждый вызов фейков пишется по
порядку. Снимок `<имя>.json` = `{case, kind, ctx_keys, ctx, api, calls, outcome}`, `outcome` — `{result}` или
`{raised: {class, message}}`. Самопроверки на BASE: каждый результат проходит круг через JSON без потерь; вызов без
заглушки — дефект спеки; COVERAGE — каждая ветка файла (30) взята хотя бы одним случаем. AC-003: снимки дерева = вывод
BASE побайтно, вывод дерева = вывод BASE побайтно. Новая спека сверяет то же в rspec строгими doubles (`eq` и
`JSON.pretty_generate` исхода, `eq` списка вызовов); AC-004 гоняет её на коде BASE и дерева и под 31 мутантом.
WebMock: в сьюте не подключён (`spec/rails_helper.rb:39` закомментирован), включать его — правка `rails_helper`,
вне вехи; вместо него API — строгий `double`: любой незаявленный вызов роняет пример, своего HTTP у презентера нет.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10i-ci`):

1. Замер (раздел 3): 3 офенса `configure_hook`, 4 без строки директивы. С патчем: 0 у файла; итог 7a8ace58
   81 → 78, fa3dcd14 77 → 74; строгий RuboCop (`bin/ci-local --only rubocop`) после шага 4 чистый.
2. Снимочный пробник: 29 случаев, 30 веток покрыты, снимки = вывод BASE = вывод дерева; кодировка `to_json`
   ActiveSupport (`&` → `\u0026`) в пробнике и в rspec совпадает (снимок `list_conversation` зелёный в rspec на BASE).
3. Новая спека (`r10i_spec.rb`): 30 примеров зелёные на BASE и на дереве; 31/31 мутантов убиты (раздел 7, пробный прогон).
4. Полный сьют на BASE fa3dcd14: 1427 примеров, 0 failures, 30 pending (снимки `--write-base`).
5. Прочитаны тела: `AppPackageIntegration#call_hook` (`ctx[:package] = self`, `configure_hook(**params)`),
   `Dialog360::Api#retrieve_templates` (строка `response.body`), `#send_template_message` (хеш или `nil`),
   `#get_profile_for_participant_label` (строка или `nil`). Предположение: в проде `ctx` всегда indifferent
   (GraphQL); plain-хеш с символами пиннится только как поведение BASE.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимки — **только** `git apply` патчей. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения
исходников (раздел 1); спека чиста под RuboCop (AC-005, AC-006). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10i-probes
export CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci
```

**Шаг 1. Снимки и спека — на коде BASE (характеризация первой).** Спека — готовый файл постановщика
`$P/r10i_spec.rb` (sha256 в AC-009): строгие doubles API по полю `api` снимка, `ctx` по `ctx_keys`, сверка `outcome`
через `eq` и `JSON.pretty_generate` и списка вызовов через `eq`. Копируется без правок:

```bash
mkdir -p spec/services/message_apis/dialog360
cp $P/r10i_spec.rb spec/services/message_apis/dialog360/configure_hook_snapshots_spec.rb
git apply $P/r10i_snapshots.patch
git add spec
git status --short        # ожидается: 30 строк "A  spec/…" (29 снимков и спека), ничего больше
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 30 files
git commit -qm "Pin dialog360 configure_hook output"
bash $P/r10i_snapshot_gate.sh $(git merge-base HEAD @{u})   # ожидается последней строкой: R10I SNAPSHOTS PASS 29 fixtures = BASE output = tree output
```

**Шаг 2. Код.**

```bash
git apply $P/r10i_rewrite.patch
git status --short        # ожидается: одна строка " M app/services/message_apis/dialog360/presenter.rb"
git commit -qam "Split dialog360 configure_hook"
bash $P/r10i_snapshot_gate.sh $(git merge-base HEAD @{u})   # снова PASS
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10i_tests_gate.sh $B` (≈ 3 мин). Нужны строки
`R10I TREE PASS 30 examples, 29 snapshots`, `R10I BASE PASS 30 examples`, `R10I MUTANTS PASS 31/31 killed`. Красное —
сначала `cmp $P/r10i_spec.rb spec/services/message_apis/dialog360/configure_hook_snapshots_spec.rb` (файл обязан
совпасть); совпадает, а гейт красный (пример упал, мутант выжил) — раздел 9. Спеку, код, патчи, снимки и мутантов не
править.

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10i <<'PY'
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
git diff --stat            # ожидается: только .rubocop_todo.yml, 3 deletions
git commit -am "Drop R10i entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10i

- Changed: `MessageApis::Dialog360::Presenter.configure_hook` (the WhatsApp template wizard of the
  Dialog360 app) is split into one private method per step: contact search gate, template list
  with pagination buttons, parameters form (`submit-template`) and send (`pick-template`), picked
  from the `TEMPLATE_STEPS` table. The order of the checks, the key forms read from `ctx` and the
  calls to the Dialog360 API are kept; the stray in-file disable comment for PerceivedComplexity is gone.
  Its output is pinned by 29 JSON snapshots generated from the old code with a stubbed API
  (spec/fixtures/dialog360/configure_hook/, one per branch, including raised errors and the API
  calls made) and a new spec that compares the full returned value, key order included. The
  three Metrics outliers of the method leave the todo.
```

```bash
git commit -am "Note fork-updates-r10i in changelog"
```

**Шаг 6.** Все десять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строка `R10I SNAPSHOTS PASS …`; AC-004 — три строки `R10I … PASS`; AC-005 — строки `backlog without
todo: …` и `drop: …`; AC-008 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `presenter.rb` и 29 снимков (только патчами), новой спеки (только копией шага 1), `.rubocop_todo.yml` (только
  скриптом шага 4), `CHANGELOG.md`.
- `app/services/message_apis/dialog360/api.rb` (веха `r10l`), прочие презентеры (вехи `r10g`, `r10h`), существующие
  спеки (в том числе `spec/services/message_apis/presenters_case_equality_spec.rb`), `spec/rails_helper.rb`.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`.
- Прочие блоки и строки todo.
- Никаких ручных правок кода и снимков, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников; странности BASE (`Whatsapp templates` дважды, `{{10}}` не параметр, пустой `Phone:  | `) — данные, не
  чинить.
- `docs/specs/**` — не править (AC-009, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci bash docs/specs/fork-updates-r10i-probes/rspec_gate_r10i.sh'`

- **AC-002** — пути и код: изменён ровно презентер патча, добавлены ровно 29 снимков и 1 спека (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; презентер и снимки побайтно равны BASE с обоими патчами, спека — побайтная копия r10i_spec.rb; todo = BASE без 3 строк презентера; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10i-probes/r10i_probe.py tree $B'`

- **AC-003** — снимки: пробник на презентере BASE даёт 29 файлов (каждый результат проходит круг через JSON, нет вызова API без заглушки, каждая ветка файла взята), закоммиченный каталог снимков побайтно равен этому выводу, вывод пробника на презентере HEAD побайтно равен выводу BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci bash docs/specs/fork-updates-r10i-probes/r10i_snapshot_gate.sh $B'`

- **AC-004** — тесты на копии HEAD: все примеры новой спеки зелёные на коде дерева и на коде BASE, у каждого из 29 снимков есть пройденный пример с его именем; ошибок вне примеров нет; каждый из 31 мутанта r10i_config.json (текст найден ровно один раз) роняет пример, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci bash docs/specs/fork-updates-r10i-probes/r10i_tests_gate.sh $B'`

- **AC-005** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у трёх копов вехи 0 офенсов в презентере; ни у одного копа ни в одном файле (новая спека и PerceivedComplexity презентера тоже) офенсов не больше, чем на BASE; BASE содержит настройку К1; итог упал ровно на измеренные 3.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10I_CACHE=$HOME/.cache/chaskiq-r10i-ci bash docs/specs/fork-updates-r10i-probes/r10i_backlog_probe.sh $B > tmp/r10i-backlog.txt; rc=$?; cat tmp/r10i-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 3)}" tmp/r10i-backlog.txt'`

- **AC-006** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10i-ci bin/ci-local --only rubocop'`

- **AC-007** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимков добавляет ровно 29 снимков = BASE + патч снимков и спеку = копия r10i_spec.rb, презентер = BASE; коммит кода меняет только презентер = BASE + оба патча; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10i после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10i-probes/r10i_probe.py commits $B'`

- **AC-008** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10i-probes/source_scan.py $B'`

- **AC-009** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "cab259c26df9ebec9fa934b10283e4bcded5f8bcedf949da1712dea216ab76ba  docs/specs/fork-updates-r10i-probes/examples_base.txt" "1b5700f22b290c736aa3932946ecf4915a668fb1b3ba140f9dd54e661852a682  docs/specs/fork-updates-r10i-probes/pending_allowed.txt" "299361d547db736e815d5bc6467d781072fc5a99a66b9fac4aa65b6cd380cbe1  docs/specs/fork-updates-r10i-probes/r10i_backlog_probe.sh" "fc6748d745046a97975235fae50acb6ecb6be0e9605bfbaf6af7d9ae9baa72f8  docs/specs/fork-updates-r10i-probes/r10i_config.json" "66447c070a013be46ca5968eeca23e50fc213209e34afd14a5a4159cbe703f82  docs/specs/fork-updates-r10i-probes/r10i_probe.py" "c34ee0045bce4c3d127147764a6423877ddeed71f2665a8c2fcd18619e383d7c  docs/specs/fork-updates-r10i-probes/r10i_rewrite.patch" "04d6ddd1a7feda2647425c8f089e6d71d6841e90d8ba048c9f086cfbffddbfda  docs/specs/fork-updates-r10i-probes/r10i_sentinel.rb" "d0b6d20aeb69763522247b42e7f06be513e2e1cc52f7b4502a60a25760f25018  docs/specs/fork-updates-r10i-probes/r10i_snapshot.rb" "a756bda6eeb73b07e6c489250ee64dbd17d119a17e3edaeddbf1a629f28f5c27  docs/specs/fork-updates-r10i-probes/r10i_snapshot_gate.sh" "89d00a5ac93e62fb562364f292ea9578b921d190c0d90bfd7eace66e904a4ad1  docs/specs/fork-updates-r10i-probes/r10i_snapshots.patch" "a643fcb7ca273b8cc847b4bf08c23d2d068f6575410b4a6bab050da7b1a0cc09  docs/specs/fork-updates-r10i-probes/r10i_spec.rb" "49e638b0ad48afb87f92768b5b9f51c577bbd479c79094eadf54adf8bb539eca  docs/specs/fork-updates-r10i-probes/r10i_tests.rb" "a9c4918446ee7594365cdfd9bf4b7bfe6abd22522910d94acaeedcb480a4763d  docs/specs/fork-updates-r10i-probes/r10i_tests_gate.sh" "6f4d5045ce90c36d5624c127ced2b7a6901d152384c435cb54abf78b772c4bc6  docs/specs/fork-updates-r10i-probes/rspec_gate_r10i.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10i-probes/source_scan.py" "c7d8730ef5874903d20afdec1a972f45808cf97acc1024c40683c48e27cbdc7f  docs/specs/fork-updates-r10i-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-010** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-006, AC-008, AC-009, AC-010 зелёные; AC-002 красный (`R10I paths without the
change`, `is not BASE + r10i_snapshots.patch, r10i_rewrite.patch`, `is not a byte-for-byte copy of r10i_spec.rb`);
AC-003 красный (`… is not BASE's output`); AC-004 красный (спеки нет — `no examples ran`; на коде BASE текст I28
встречается дважды — это нормально, патча ещё нет); AC-005 красный (`… offenses left in the files of this milestone`,
`total did not go down`); AC-007 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10i-ci`).** Граница: клон от коммита спеки поверх
fa3dcd14 (upstream — коммит спеки) — AC-001 (1427 примеров, 409 с), AC-006, AC-008, AC-009, AC-010 rc=0; AC-002,
AC-003, AC-004, AC-005 (`BASE 77, tree 77`), AC-007 красные ровно с сообщениями выше. Сборка по разделу 5: все 10
критериев зелёные (AC-001 — 1457 примеров, 0 failures; AC-004 — 30 примеров, 31/31 мутантов, 167 с; AC-005 — `BASE 77,
tree 74`, `drop: 3`). Порченые правки поверх сборки лишним коммитом: (а) в `pagination_buttons` кнопки
переставлены (`[next_button, prev_button]`) — AC-002 (`is not BASE + …`), AC-003 (`the tree's configure_hook output
differs from BASE's`), AC-004 (пример `page_middle` красный на дереве, текст I14 не найден), AC-007 (`extra commit`);
(б) в снимке `pick_sent.json` `conv-9` → `conv-8` в ссылке — AC-002, AC-003 (`is not BASE's output`), AC-004 (пример
`pick_sent` красный на дереве и на BASE), AC-007.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10i.md --exclude "docs/specs/fork-updates-r10i-probes/**" --exclude "spec/fixtures/dialog360/**" --context "chaskiq fork-updates-r10i: RuboCop AbcSize/Cyclomatic/MethodLength (и спрятанный директивой PerceivedComplexity) у MessageApis::Dialog360::Presenter.configure_hook (мастер шаблона WhatsApp): метод разбит на шаги — template_offset, participant_missing? (поиск контакта search_participant без изменений), retrieve_templates и ошибка meta.success == false, список шаблонов с пагинацией, таблица TEMPLATE_STEPS (submit-template → форма параметров при action.type submit, pick-template → send_template_message); порядок вычислений и формы ключей ctx (строки/символы) как в BASE, строка rubocop:disable-next удалена. Вывод и вызовы API пиннят 29 JSON-снимков spec/fixtures/dialog360/configure_hook (сгенерированы пробником из кода BASE с фейковым API, каждая ветка покрыта, проверены побайтно) и новая спека: строгие doubles, eq полного исхода + JSON.pretty_generate (порядок ключей) + eq списка вызовов, зелёная на коде BASE, 31 мутант; спека не читает исходники как текст; только чтение"`

Исключения (снимки — данные пробника, их побайтно проверяет AC-003):

REVIEW_EXCLUDE: docs/specs/fork-updates-r10i.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10i-probes/**
REVIEW_EXCLUDE: spec/fixtures/dialog360/**

Контекст ревьюеру: другой порядок вычислений (страница после ворот поиска, шаг до списка), другая форма ключа
`ctx` (символ вместо строки или наоборот), `kind` ответа не тот (входной вместо `"configure"` или наоборот), граница
пагинации, `submit-template` без проверки `action.type`, «sent» при непустых `errors`, ответ не-хеш, дающий не список,
спека, которая сверяет не весь исход или вызовы, или читает исходник. Код, снимки и спеку править нельзя (AC-002,
AC-009) — замечание по месту решает постановщик (раздел 9); заход исправлений тогда пустой, FINAL_SHA = REVIEW_SHA.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 10 критериев зелёные. Если agy упал или не дал
вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010. `blocked` у критерия —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10i.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10i.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все десять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, снимочный пробник шага 1 или 2
  красный — дефект спеки;
- после шагов 1–4 AC-005 или AC-006 красные (офенс остался, вырос в другой паре, разница итогов не 3, нет
  `base_requires` К1) — дефект спеки (замер устарел); приложи вывод;
- спека шага 1 (копия `r10i_spec.rb`) красная на BASE или на дереве, или мутант выживает при ней — приложи вывод (мутант
  эквивалентен или спека слаба — решает постановщик); читать исходник, чтобы «убить» мутанта, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл изменение поведения — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, снимков и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на 7a8ace58 и fa3dcd14 (`r10g` до и после влития, черновики `r10h1`/`r10h2` (golden + rewrite) из рабочей
папки автора R10h на 2026-11-22 05:56Z, `r10i_snapshots.patch` + `r10i_rewrite.patch`):

- **Код.** Общих файлов нет (`r10g` — `ui_catalog`, `r10h` — `content_showcase`/`inbox_sections` и
  `spec/fixtures/presenters/**`). На 7a8ace58 восемь патчей применяются подряд в порядках `r10g, r10h, r10i` и
  `r10i, r10g, r10h`, на fa3dcd14 (`r10g` влита) — `r10h, r10i` и `r10i, r10h`. Финальный `r10h` не проверен
  (спеки в `main` нет) — при переносе BASE повторить (раздел 2).
- **Зависимость от R10cfg (К1)** — влита; AC-005 проверяет строку настройки на BASE (`base_requires`).
- **`.rubocop_todo.yml`.** `r10i` убирает 3 строки `dialog360/presenter.rb` (блоки `AbcSize`, `CyclomaticComplexity`,
  `MethodLength`); `r10g` — строки `ui_catalog`, `r10h` — `content_showcase`/`inbox_sections` в тех же блоках, а
  строка `inbox_sections` СОСЕДНЯЯ с `dialog360/presenter.rb`. Скрипт шага 4 текстовый — на любом BASE даёт верный
  итог; но веха, снятая с BASE до влития `r10h`, при слиянии после неё даст конфликт соседних строк todo
  (решение — обе строки удалить; AC-002/AC-007 считают todo от своего BASE). Поэтому вехи ставить
  последовательно, перенося BASE (раздел 2).
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **R10l (`dialog360/api.rb`, позже).** Файлов не делит. Общее — строка todo `dialog360/api.rb` прямо над
  `dialog360/presenter.rb` (`AbcSize`, `MethodLength`: конфликт соседних строк при параллельном влитии) и аргументы
  `send_template_message(template:, selected_user:, conversation_key:, parameters:)`, которые пиннят снимки `pick_*`.
- **Мутационный прогон противоположным исполнителем (cx)** — после 2026-11-22 11:39Z.
