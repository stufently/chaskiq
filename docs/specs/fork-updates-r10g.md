# fork-updates-r10g — выбросы RuboCop, шаг 10g: `ui_catalog` `configure_hook` — таблица вместо цепочки `if`, вывод пиннится снимками

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10g.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10g: «Риск: вывод
  мессенджеру, тестов 2. Сначала характеризация: снимок полного возвращаемого хеша для КАЖДОГО id кнопки каталога и
  для `kind`≠submit (… золотые JSON-снимки в `spec/fixtures`, сгенерированные на BASE пробником, не спекой). Подход:
  `case` → таблица `{id => :метод}`; с К1 литералы остаются как есть»; решения К1/К2, раздел 2), план чистки —
  `docs/specs/fork-updates-rubocop-plan.md`. Шаблон — `fork-updates-r10c`/`fork-updates-r10b` (патч постановщика,
  спека характеризации, мутанты). Соседняя веха — `fork-updates-r10e` (раздел 10).
- BASE_SHA: `9c3146ba6bb5df1597b141b94a1ace21dc5e0d0e` — HEAD `main` «Add R10e spec» (от a813c6dd отличается только docs/specs; снимки a813c6dd годны) (R10cfg и R10c влиты;
  Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10e` или другая веха — раздел 10), постановщик переносит BASE (раздел 2), коммитит
  новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-009).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 115 КБ: ≈ 70 КБ — 32 файла снимков, ≈ 42 КБ — презентер (литералы сдвинуты на 4 пробела).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все десять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: у `MessageApis::UiCatalog::Presenter.configure_hook` уходят 4 выброса (`AbcSize`, `CyclomaticComplexity`,
  `MethodLength`, `PerceivedComplexity`; их 4 строки уходят из todo). Код задан патчем постановщика
  `r10g_rewrite.patch`, снимки — патчем `r10g_snapshots.patch` (оба руками не править). Работа исполнителя — одна
  НОВАЯ спека, которая сверяет вывод `configure_hook` с 32 снимками: зелёная на коде BASE и после; каждый из 22
  мутантов постановщика (`r10g_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)` по коду, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другой хеш ответа
(значение, ключ, порядок ключей). Чтение снимков `spec/fixtures/**` — данные, оно разрешено. AC-008
(`source_scan.py`) ищет запрещённые приёмы в новых и изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10g`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10g-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10g-ci` (уже сделан при написании спеки).
2. При переносе BASE (например, после влития `r10e`) перемерить, патч не перегенерировать, пока всё сходится:
   - `git apply --check` обоих патчей (`r10g_snapshots.patch`, затем `r10g_rewrite.patch`) на новом `main` чист
     (проверено: с `r10e_rewrite.patch` в обоих порядках);
   - в `.rubocop.yml` есть строка `  CountAsOne: [array, hash, heredoc]` (К1; без неё новые методы-литералы дают
     8 `MethodLength`, и AC-005 сам падает на `base_requires`); 4 строки `presenter.rb` в блоках `AbcSize`,
     `CyclomaticComplexity`, `MethodLength`, `PerceivedComplexity` todo на месте;
   - бэклог-пробник на копии нового `main` с обоими патчами и шагом 4: у презентера 4 → 0, роста нет, итог падает
     ровно на 4 — число `4` в команде AC-005 (сейчас: a813c6dd 120 → 116; с `r10e` 81 → 77);
   - снимочный пробник на той же копии: `R10G SNAPSHOTS PASS 32 fixtures = BASE output = tree output` (если
     `presenter.rb` на `main` менялся — пересобрать снимки `r10g_snapshot.rb` на новом BASE и патч);
   - тексты 22 мутантов — каждый ровно один раз в `presenter.rb` после патча; имя новой спеки не занято;
   - перегенерировать снимки сьюта на чистом checkout `main`:
     `CHASKIQ_R10G_CACHE=$HOME/.cache/chaskiq-r10g-ci bash docs/specs/fork-updates-r10g-probes/rspec_gate_r10g.sh --write-base`
     и пересчитать sha256 в AC-009. Сейчас в снимках — 1394 примера BASE a813c6dd.
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z. Если клон снимается позже — постановщик по желанию заменяет
   раздел 8 полной политикой `cross-review-v1` (codex + agy) до коммита спеки.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-009 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10g-ci`). `configure_hook` (`presenter.rb:72`): `AbcSize` 37.15/30,
`CyclomaticComplexity` 17/13, `PerceivedComplexity` 17/13, `MethodLength` 33/30 с К1 (814/30 без К1, на bba1d7ce).
Других офенсов у файла нет. Метод — каталог-демо всех UI-компонентов мессенджера: литерал кнопок каталога, затем
под `if action.type == "submit"` цепочка из 9 НЕЗАВИСИМЫХ `if` (не `case`): два ранних `return` по id
(`aaaaaaaa` — ответ `kind: "initialize"` с `results`, `content-url` — ответ с `url`), `name == "bubu"` → литерал
списка компонентов, шесть `type == "item" && id == "list-item-N"` → литерал своей страницы.

**`r10g_rewrite.patch`** (только `presenter.rb`, +733/−705: литералы сдвинуты на 4 пробела, текст тот же): ранние
`return` → таблица `SUBMIT_RESPONSES` (`aaaaaaaa` → `catalog_results_response`, `content-url` → `content_url_response`);
шесть `if` пунктов → таблица `ITEM_DEFINITIONS` (`list-item-1/4/2/6/7/8` → `text_`, `single_select_`, `textarea_`,
`dropdown_`, `checkbox_`, `input_definitions`); `bubu` → `components_list_definitions`; литерал каталога →
`catalog_definitions`; выбор после `submit` — `submitted_definitions(ctx)` (пункт списка, затем `bubu`, иначе каталог).
Новые методы — `private_class_method`. После патча: `configure_hook` Abc 6.78, Cyc 3, 4 строки;
`submitted_definitions` Abc 8.66, Cyc 4, 4 строки; методы-литералы — 2 строки (К1). У файла 0 офенсов.

**Почему поведение то же.** Порядок проверок сохранён: не `submit` → каталог с переданным `kind`; `submit` и id из
`SUBMIT_RESPONSES` → тот же ответ (`kind: "initialize"` при любом входном `kind`, `# ctx: ctx` — комментарий, как
был); иначе пункт списка (тип `item`, id из таблицы) побеждает `bubu` — на BASE это давало последнее присваивание
цепочки; неизвестный id пункта или пункт без `type: "item"` → `bubu` или каталог, как раньше. Поиск по хешу
вместо `id == "…"`: для строк и `nil` одно и то же (`eql?`/`hash` строки = `==`); id, у которого `==` со строкой
переопределён, мессенджер не шлёт. Первый `ctx.dig(:field, :action, :type)` тот же — `TypeError` на
не-хеше `field` тот же. Литералы перенесены дословно (новый объект на каждый вызов, как раньше).

**Доказательство.** `r10g_snapshot.rb` (чистый Ruby, без Rails) грузит файл презентера и для 32 случаев конфига
пишет `<имя>.json` = `{case, kind, ctx_keys, ctx, result}`. Случаи: без `field` (`kind` `configure` и `custom`),
`click` по `aaaaaaaa` и по пункту; каждый элемент с `action` из ЛЮБОГО ответа — кнопки каталога, `popis`, шесть
пунктов, option и четыре input с `action` (самопроверка COVERAGE: элемент с `action`, которого нет среди `field`
случаев, — дефект спеки); приоритеты (`aaaaaaaa`/`content-url` с именем `bubu`, пункт с именем `bubu`, неизвестный
пункт с именем `bubu`, пункт без `type`, неизвестный id, `submit` с `kind: "custom"`); `ctx` со строковыми ключами.
Каждый результат обязан пройти круг через JSON без потерь (только символьные ключи, JSON-значения). AC-003:
снимки дерева = вывод BASE побайтно, вывод дерева = вывод BASE побайтно. Спека исполнителя сверяет то же в rspec
(`eq` — значения и символьные ключи; `JSON.pretty_generate` — порядок ключей); AC-004 гоняет её на коде BASE и
дерева и под 22 мутантами. ISEQ-сверка (как в r10c) неприменима: структура кода меняется намеренно; её место
занимает полный снимок вывода — каждый литерал метода попадает хотя бы в один снимок целиком.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10g-ci`):

1. Замер на bba1d7ce (без К1), 1f32a872 (К1) и a813c6dd (К1 + r10c): 4 офенса `configure_hook` везде. С патчем:
   0 у файла; итог a813c6dd 120 → 116, 1f32a872 137 → 133. Без К1 (bba1d7ce + патч) — 8 `MethodLength` у новых
   методов-литералов, итог 211 → 215: веха возможна только после R10cfg.
2. Снимочный пробник: 32 случая, 17 элементов с `action` покрыты, снимки = вывод BASE = вывод дерева.
3. Образец спеки постановщика (форма — шаг 1): 33 примера зелёные на BASE и на дереве; 22/22 мутантов убиты
   (G17 — строковый ключ `"kind"` — убит только `eq`; G18 — порядок ключей — только сверкой `pretty_generate`).
4. Полный сьют на BASE a813c6dd: 1394 примера, 0 failures, 30 pending (снимки `--write-base`). Стыки — раздел 10;
   пробный прогон и порченые правки — раздел 7.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимки — **только** `git apply` патчей. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения
исходников (раздел 1); спека чиста под RuboCop (AC-005, AC-006). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10g-probes
export CHASKIQ_R10G_CACHE=$HOME/.cache/chaskiq-r10g-ci
```

**Шаг 1. Снимки и спека — на коде BASE (характеризация первой).** Создай
`spec/services/message_apis/ui_catalog/configure_hook_snapshots_spec.rb` ровно с этим содержимым:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::UiCatalog::Presenter do
  snapshots = Rails.root.glob("spec/fixtures/ui_catalog/configure_hook/*.json").sort

  it "has the 32 configure_hook snapshots" do
    expect(snapshots.size).to eq(32)
  end

  snapshots.each do |path|
    name = path.basename(".json").to_s

    it "configure_hook returns the snapshot #{name}" do
      snapshot = JSON.parse(path.read, symbolize_names: true)
      ctx = case snapshot[:ctx_keys]
            when "symbol" then snapshot[:ctx]
            when "string" then snapshot[:ctx].deep_stringify_keys
            else raise ArgumentError, "unknown ctx_keys #{snapshot[:ctx_keys]}"
            end

      result = described_class.configure_hook(kind: snapshot[:kind], ctx: ctx)

      expect(snapshot[:case]).to eq(name)
      expect(result).to eq(snapshot[:result])
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(snapshot[:result]))
    end
  end
end
```

```bash
git apply $P/r10g_snapshots.patch
git add spec
git status --short        # ожидается: 33 строки "A  spec/…" (32 снимка и спека), ничего больше
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 33 files
git commit -qm "Pin ui_catalog configure_hook output"
bash $P/r10g_snapshot_gate.sh $(git merge-base HEAD @{u})   # ожидается последней строкой: R10G SNAPSHOTS PASS 32 fixtures = BASE output = tree output
```

**Шаг 2. Код.**

```bash
git apply $P/r10g_rewrite.patch
git status --short        # ожидается: одна строка " M app/services/message_apis/ui_catalog/presenter.rb"
git commit -qam "Split ui_catalog configure_hook"
bash $P/r10g_snapshot_gate.sh $(git merge-base HEAD @{u})   # снова PASS
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10g_tests_gate.sh $B` (≈ 10 мин). Нужны строки
`R10G TREE PASS 33 examples, 32 snapshots`, `R10G BASE PASS 33 examples`, `R10G MUTANTS PASS 22/22 killed`. Красное —
сверь спеку с текстом шага 1 посимвольно и поправь её, не добавляя коммитов (код, патчи, снимки и мутантов не
трогать):

```bash
C1=$(git log --format=%H -1 --grep '^Pin ui_catalog configure_hook output$')
mkdir -p tmp/r10g-spec && cp spec/services/message_apis/ui_catalog/configure_hook_snapshots_spec.rb tmp/r10g-spec/
git reset --hard "$C1~1"    # коммитов вехи нет; копия спеки — в tmp/r10g-spec (tmp/ игнорируется)
# поправь tmp/r10g-spec/configure_hook_snapshots_spec.rb, затем:
# mkdir -p spec/services/message_apis/ui_catalog && cp tmp/r10g-spec/configure_hook_snapshots_spec.rb spec/services/message_apis/ui_catalog/
# затем — команды шагов 1 и 2 (без повторного создания файла), затем снова шаг 3
```

Мутант выживает при спеке ровно из шага 1 — раздел 9, не правка спеки.

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10g <<'PY'
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
git commit -am "Drop R10g entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10g

- Changed: `MessageApis::UiCatalog::Presenter.configure_hook` (the messenger UI catalog demo) picks its
  answer from two tables instead of a chain of nine `if`s: `SUBMIT_RESPONSES` (button id => response
  method) and `ITEM_DEFINITIONS` (list item id => definitions method); each literal moved unchanged
  into its own private method (decision K1 of the R10 programme counts it as one line). The order of
  the checks is kept: a known list item still wins over the "bubu" button.
  Its output is pinned by 32 JSON snapshots generated from the old code (spec/fixtures/ui_catalog/
  configure_hook/, one per catalog element with an action, plus non-submit, precedence and string-key
  cases) and a new spec that compares the full returned hash, key order included. The four Metrics
  outliers of the method leave the todo.
```

```bash
git commit -am "Note fork-updates-r10g in changelog"
```

**Шаг 6.** Все десять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строка `R10G SNAPSHOTS PASS …`; AC-004 — три строки `R10G … PASS`; AC-005 — строки `backlog without
todo: …` и `drop: …`; AC-008 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `presenter.rb` и 32 снимков (только патчами), новой спеки шага 1, `.rubocop_todo.yml` (только
  скриптом шага 4), `CHANGELOG.md`.
- `app/services/message_apis/ui_catalog/api.rb`, прочие презентеры, существующие спеки (в том числе
  `spec/services/message_apis/presenters_case_equality_spec.rb` с двумя старыми примерами `configure_hook`).
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`; файлы
  вехи `r10e` (раздел 10).
- Прочие блоки и строки todo.
- Никаких ручных правок кода и снимков, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников; странные тексты каталога (`fuckya`, `inputut pupx`, `/ppupu`) — данные BASE, не чинить.
- `docs/specs/**` — не править (AC-009, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10G_CACHE=$HOME/.cache/chaskiq-r10g-ci bash docs/specs/fork-updates-r10g-probes/rspec_gate_r10g.sh'`

- **AC-002** — пути и код: изменён ровно презентер патча, добавлены ровно 32 снимка и 1 спека (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; презентер и снимки побайтно равны BASE с обоими патчами; todo = BASE без 4 строк презентера; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10g-probes/r10g_probe.py tree $B'`

- **AC-003** — снимки: пробник на презентере BASE даёт 32 файла (каждый результат проходит круг через JSON, каждый элемент с action покрыт случаем), закоммиченный каталог снимков побайтно равен этому выводу, вывод пробника на презентере HEAD побайтно равен выводу BASE.
  `bash -c 'B=$(git merge-base HEAD @{u}) && bash docs/specs/fork-updates-r10g-probes/r10g_snapshot_gate.sh $B'`

- **AC-004** — тесты на копии HEAD: все примеры новой спеки зелёные на коде дерева и на коде BASE, у каждого из 32 снимков есть пройденный пример с его именем; ошибок вне примеров нет; каждый из 22 мутантов r10g_config.json (текст найден ровно один раз) роняет пример, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10G_CACHE=$HOME/.cache/chaskiq-r10g-ci bash docs/specs/fork-updates-r10g-probes/r10g_tests_gate.sh $B'`

- **AC-005** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у четырёх копов вехи 0 офенсов в презентере; ни у одного копа ни в одном файле (новая спека тоже) офенсов не больше, чем на BASE; BASE содержит настройку К1; итог упал ровно на измеренные 4.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10G_CACHE=$HOME/.cache/chaskiq-r10g-ci bash docs/specs/fork-updates-r10g-probes/r10g_backlog_probe.sh $B > tmp/r10g-backlog.txt; rc=$?; cat tmp/r10g-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 4)}" tmp/r10g-backlog.txt'`

- **AC-006** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10g-ci bin/ci-local --only rubocop'`

- **AC-007** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимков добавляет ровно 32 снимка = BASE + патч снимков и спеку, презентер = BASE; коммит кода меняет только презентер = BASE + оба патча; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10g после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10g-probes/r10g_probe.py commits $B'`

- **AC-008** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10g-probes/source_scan.py $B'`

- **AC-009** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "7bd9ef2ac1ca4266448de027694dcb19554b796109f88c49905eb0d95128340e  docs/specs/fork-updates-r10g-probes/examples_base.txt" "a0f0c1ae835336c23a27820b4ad4e2a71307602a2c56e221ac480b3da2c8ad40  docs/specs/fork-updates-r10g-probes/pending_allowed.txt" "4cadd7528645c60afb53fc208c03875e92146b3102685c435ffffd0904e31813  docs/specs/fork-updates-r10g-probes/r10g_backlog_probe.sh" "5fd3fede689e2af46bb00432d5a8c3fd6034bfee3e3123439616b34380a1430a  docs/specs/fork-updates-r10g-probes/r10g_config.json" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10g-probes/r10g_probe.py" "4d0aa42950fe33abf2b5df5a757f87e0e425cab1071838fc1768a6106e0eea23  docs/specs/fork-updates-r10g-probes/r10g_rewrite.patch" "3f4050846a88fcd510644156c63128e8db9ee6a934bd6a935e6414ce26d2196b  docs/specs/fork-updates-r10g-probes/r10g_sentinel.rb" "af00edafadd8fc4e7db698f1e7edede8729ebfddf7aac3d984c9d731f9ad2492  docs/specs/fork-updates-r10g-probes/r10g_snapshot.rb" "57ca989d73dc0759893b6af22c0f04811858357254bf7af38350b79b77f40826  docs/specs/fork-updates-r10g-probes/r10g_snapshot_gate.sh" "0afd051886258b33e67c251ebed2f1a63cb9aecc1fd3e484da0fadb4fe856980  docs/specs/fork-updates-r10g-probes/r10g_snapshots.patch" "1ab3acd3a18fcd3b89ca9a644e1f63b7b40082d5d501637a6aab903f308b16f0  docs/specs/fork-updates-r10g-probes/r10g_tests.rb" "e50a550169e90f1b9da306460153e7c05104288effc2fea2682062aa437e8ca7  docs/specs/fork-updates-r10g-probes/r10g_tests_gate.sh" "bff2bb8243824826c8743df31de8b1a0b8fdfdfa5869efe8b69f9b8d86bfa55f  docs/specs/fork-updates-r10g-probes/rspec_gate_r10g.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10g-probes/source_scan.py" "990f1da8cf3db4c78b3259bf0a02bcea07e034048902ac3d6c48c189316c3ffe  docs/specs/fork-updates-r10g-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-010** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-006, AC-008, AC-009, AC-010 зелёные; AC-002 красный (`R10G paths without the
change`, `is not BASE + r10g_snapshots.patch, r10g_rewrite.patch`); AC-003 красный (`… is not BASE's output`, `Only in
tmp/r10g-snapshots/out/base: …`); AC-004 красный (спеки нет — `no examples ran`); AC-005 красный (`… offenses left in the files of this
milestone`, `total did not go down`); AC-007 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10g-ci`).** Граница: клон от коммита спеки поверх
a813c6dd (upstream — коммит спеки) — AC-001 (1394 примера, 403 с), AC-006, AC-008, AC-009, AC-010 rc=0; AC-002,
AC-003, AC-004, AC-005 (`4 offenses left`, `BASE 120, tree 120`), AC-007 красные ровно с сообщениями выше. Сборка по
разделу 5 (спека — текст шага 1): все 10 критериев зелёные (AC-001 — 1427 примеров, 0 failures; AC-004 — 33
примера, 22/22 мутантов, 127 с; AC-005 — `BASE 120, tree 116`, `drop: 4`). Порченые правки поверх сборки лишним
коммитом: (а) в `submitted_definitions` `bubu` проверяется раньше пункта — AC-002 (`is not BASE + …`), AC-003
(`the tree's configure_hook output differs from BASE's`), AC-004 (пример `submit_list_item_1_named_bubu` красный на
дереве, текст G08 не найден), AC-007 (`extra commit`); (б) в снимке `submit_list_item_6.json` `"Option 2"` →
`"Option 3"` — AC-002, AC-003 (`is not BASE's output`), AC-004 (пример красный на дереве и на BASE), AC-007.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10g.md --exclude "docs/specs/fork-updates-r10g-probes/**" --exclude docs/specs/fork-updates-r10e.md --exclude "docs/specs/fork-updates-r10e-probes/**" --exclude "spec/fixtures/ui_catalog/**" --context "chaskiq fork-updates-r10g: RuboCop AbcSize/Cyclomatic/Perceived/MethodLength у MessageApis::UiCatalog::Presenter.configure_hook (каталог-демо UI мессенджера): цепочка из 9 независимых if после action.type == submit заменена таблицами SUBMIT_RESPONSES (id aaaaaaaa, content-url → метод ответа) и ITEM_DEFINITIONS (list-item-N → метод определений), выбор submitted_definitions: пункт списка (type item) раньше name bubu, иначе каталог; литералы перенесены дословно в private_class_method-методы (К1 считает литерал одной строкой). Вывод пиннят 32 JSON-снимка spec/fixtures/ui_catalog/configure_hook (сгенерированы пробником из кода BASE, проверены побайтно) и новая спека: eq полного хеша + JSON.pretty_generate (порядок ключей), зелёная на коде BASE, 22 мутанта; спека не читает исходники как текст; только чтение"`

Исключения (снимки — данные пробника, их побайтно проверяет AC-003):

REVIEW_EXCLUDE: docs/specs/fork-updates-r10g.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10g-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10e.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10e-probes/**
REVIEW_EXCLUDE: spec/fixtures/ui_catalog/**

Контекст ревьюеру: другой порядок проверок (`bubu` раньше пункта, ранний ответ после выбора определений),
`kind` ответа не тот (входной вместо `"initialize"` или наоборот), литерал, изменившийся при переносе, неизвестный
id пункта, дающий `nil` вместо каталога, спека, которая сверяет не весь хеш или читает исходник. Код и снимки
править нельзя — замечание по месту решает постановщик (раздел 9); спеку — можно, одним заходом.

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10g.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10g.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все десять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9`, снимочный пробник шага 1 или 2
  красный — дефект спеки;
- после шагов 1–4 AC-005 или AC-006 красные (офенс остался, вырос в другой паре, разница итогов не 4, нет
  `base_requires` К1) — дефект спеки (замер устарел); приложи вывод;
- спека ровно из шага 1 красная на BASE или на дереве, или мутант выживает при ней — приложи вывод (мутант
  эквивалентен или спека слаба — решает постановщик); читать исходник, чтобы «убить» мутанта, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл изменение поведения — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, снимков и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на bba1d7ce, 1f32a872 и a813c6dd (`r10c_rewrite.patch`, `r10cfg_rewrite.patch`, `r10e_rewrite.patch`,
`r10g_snapshots.patch` + `r10g_rewrite.patch`):

- **Код.** Общих файлов нет ни с одной вехой (`r10c` — 9 других файлов `app/`/`lib/` и 4 спеки, `r10cfg` — только
  `.rubocop.yml`, `r10e` — 10 спек и `spec/fixtures/requests/**`). На bba1d7ce все четыре патча применяются в любом
  из 24 порядков, итог один; на a813c6dd `r10e` и `r10g` — в обоих порядках.
- **Зависимость от R10cfg (К1) жёсткая:** без `CountAsOne` новые методы-литералы — 8 `MethodLength` (раздел 4).
  R10cfg влита (BASE); AC-005 проверяет строку настройки на BASE (`base_requires`).
- **`.rubocop_todo.yml`.** `r10g` убирает 4 строки презентера из блоков `AbcSize`, `CyclomaticComplexity`,
  `MethodLength`, `PerceivedComplexity`; `r10e` — строки спек блока `Layout/LineLength`. Блоки разные — git сливает
  чисто; скрипты todo в любом порядке дают один итог.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Вместе.** a813c6dd + `r10e` + `r10g`: без todo 120 → 81 (`r10e`) → 77 (`r10g`); строгий RuboCop — ноль офенсов.
- **Перенос BASE после `r10e` — раздел 2, п. 2** (`--write-base`, перемер 4, снимочный пробник, тексты мутантов,
  sha256 AC-009). Мутационный прогон противоположным исполнителем (cx) — после 2026-11-22 11:39Z.
