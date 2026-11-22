# fork-updates-r10h1 — выбросы RuboCop, шаг 10h1: `content_showcase` `configure_hook` — ветки в методы, вывод пиннится золотым снимком

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10h1.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10h:
  «`content_showcase` + `inbox_sections` … Характеризация: каждая ветка `ctx[:field][:id]`/`ctx[:values][:type]` →
  снимок хеша; `AnnouncementRecord` — с фиксированными записями. Подход: ветка → метод, общий каркас ответа
  (`{kind:, definitions:, results:}`) → помощник. Можно резать на две вехи (по файлу), если > 400 строк»). Дифф кода
  обоих файлов — 631 строка, поэтому веха разрезана: **R10h1** — `content_showcase` (эта спека, патч 312 строк),
  **R10h2** — `inbox_sections` (`fork-updates-r10h2.md`). План чистки — `docs/specs/fork-updates-rubocop-plan.md`.
  Шаблон — `fork-updates-r10g` (патч постановщика, золотые снимки на BASE пробником, спека-сверка, мутанты).
- BASE_SHA: `fa3dcd142bd98f9fc7487d3c09cdde5fdaefc3ab` — HEAD `main` «Record R10g acceptance» (К1 `CountAsOne: [array, hash,
  heredoc]` и R10c влиты; Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влились `r10e`, `r10g`, `r10h2` — раздел 10), постановщик переносит BASE (раздел 2), коммитит
  новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 85 КБ: ≈ 70 КБ — золотой снимок (JSON), ≈ 12 КБ — презентер, ≈ 2 КБ — спека.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: у `MessageApis::ContentShowcase::Presenter.configure_hook` уходят 4 выброса (`AbcSize`,
  `CyclomaticComplexity`, `MethodLength`, `PerceivedComplexity`; их 4 строки уходят из todo). Код задан патчем
  постановщика `r10h1_rewrite.patch`, золотой снимок — патчем `r10h1_golden.patch` (оба руками не править). Работа
  исполнителя — одна НОВАЯ спека (текст дан в шаге 1), которая сверяет вывод хуков с 30 случаями снимка: зелёная на
  коде BASE и после; каждый из 27 мутантов постановщика (`r10h1_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)` по коду, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другой хеш ответа
(значение, ключ, тип ключа, порядок ключей) или другое исключение. Чтение снимка `spec/fixtures/**` — данные, оно
разрешено. AC-007 (`source_scan.py`) ищет запрещённые приёмы в новых и изменённых файлах `spec/` и валит критерий на
любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10h1`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов (общий с R10h2):
  `$HOME/.cache/chaskiq-r10h-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-r10e-ci $HOME/.cache/chaskiq-r10h-ci` (уже сделан при написании спеки).
   **Уже нужно:** пока спека писалась, в `main` влились `r10e` и `r10g` (HEAD `fa3dcd14` «Record R10g acceptance»).
   Перемерено на fa3dcd14 (Docker): оба патча применяются, сборка по разделу 5 — AC-002, AC-004, AC-006 зелёные,
   бэклог 77 → 73 (`drop: 4`); код вехи и её 4 строки todo не менялись, снимок годен. Осталось: BASE_SHA →
   новый HEAD, `--write-base` (примеры `r10e`/`r10g` добавятся к 1394) и sha256 в AC-008.
2. При переносе BASE (после влития `r10e`, `r10g` или `r10h2`) перемерить; патчи не перегенерировать, пока всё сходится:
   - `git apply --check` патчей `r10h1_golden.patch`, затем `r10h1_rewrite.patch` на новом `main` чист (проверено:
     с патчами `r10e`, `r10g`, `r10h2` в трёх разных порядках);
   - каталог `app/services/message_apis/content_showcase` на `main` не менялся
     (`git diff --quiet 9c3146ba main -- app/services/message_apis/content_showcase`) — иначе снимок мог устареть:
     пересобрать его генератором (`r10h1_golden_spec.rb`, команда — раздел 4, п. 2) и патч;
   - 4 строки `content_showcase/presenter.rb` в блоках `Metrics/AbcSize`, `CyclomaticComplexity`, `MethodLength`,
     `PerceivedComplexity` todo на месте (r10g и r10h2 убирают из тех же блоков СВОИ строки; блоки не пустеют);
   - бэклог-пробник на копии нового `main` со сборкой по разделу 5: у файла 4 → 0, роста нет, итог падает ровно на 4 —
     число `4` в команде AC-004 (сейчас 9c3146ba: 120 → 116; влитые `r10e`/`r10g`/`r10h2` снижают обе стороны на
     39/4/4);
   - тексты 27 мутантов — каждый ровно один раз в `presenter.rb` после патча; имя новой спеки не занято;
   - перегенерировать снимки сьюта на чистом checkout `main`:
     `CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h1-probes/rspec_gate_r10h1.sh --write-base`
     и пересчитать sha256 в AC-008. Сейчас в снимках — 1394 примера BASE 9c3146ba (влитая раньше веха добавит свои).
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z. Если клон снимается позже — постановщик по желанию заменяет
   раздел 8 полной политикой `cross-review-v1` (codex + agy) до коммита спеки.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10h-ci`) на 9c3146ba: `configure_hook` (`presenter.rb:88`) —
`AbcSize` 90.64/30, `CyclomaticComplexity` 16/13, `MethodLength` 87/30 (уже с К1), `PerceivedComplexity` 17/13.
Других офенсов у файла нет (схемы `schema`/`article_fields`/`presentation_schema`/`base_schema` с К1 в лимите).
Метод: `record = AnnouncementRecord.new`, `base_schema`; при `field.action.type == "submit"` цепочка из 12 `if` по
`field.id`, каждая ветка с `return`; иначе — `{kind:, definitions: base_schema}`.

**`r10h1_rewrite.patch`** (только `presenter.rb`, +95/−177): константы `ANNOUNCEMENT_TITLE`, `TOP_ARTICLES_TITLE`
(аргументы `base_title`) и таблица `CONFIGURE_ACTIONS` (9 точных id → метод); `configure_hook` — 6 строк:
`submit` → `configure_action` (точный id из таблицы, иначе id, содержащий `autofill-`, → `configure_autofill_article`,
иначе `nil`), `nil` → `configure_response(kind, record.base_schema)`. Каркас ответа — два помощника:
`configure_response(kind, definitions)` = `{kind:, definitions:}`, `initialize_response(definitions, results)` =
`{kind: "initialize", definitions:, results:}`. Ветки → 9 методов `configure_*`, общая сборка формы «Top Articles» →
`top_articles_response`, запись из `values` с автозаполнением → `autofilled_record`, проверка статей →
`articles_valid?`. Все новые методы — `private_class_method`. После патча у файла 0 офенсов; самый сложный метод —
`configure_action` (Cyc 3).

**Почему поведение то же.** Порядок проверок сохранён: точные id сравнивались раньше `include?("autofill-")`, ни
один из 9 точных id не содержит `autofill-`, поэтому «сначала таблица, потом `include?`» — тот же выбор; поиск по
хешу вместо `==`: для строк и `nil` одно и то же; `nil` id при `submit` → `nil.include?` → `NoMethodError`, как
раньше. `base_schema` — чистый литерал: строить его в конце, а не в начале, — то же значение. Выброшенный вызов
`aa.schema` после `autofill` (результат не использовался) убран: `schema` читает только атрибуты и `errors[]`, побочных
эффектов нет. В `add-to-messenger` порядок `autofill` → `valid?` → `schema` сохранён (ошибки `valid?` попадают в
схему). Проверка статей: `map { … valid? }.all?` ≡ старое `map.uniq.any?(&:!)` наоборот; `map` целиком, как раньше
(без короткого замыкания). Аргументы `generate_collection_definitions` в трёх ветках те же; `base_title`
считается раньше `generate_collection_definitions`, как раньше; `.flatten` — где был. `results: ctx[:values]` — тот же
объект `ActionController::Parameters`. `pick-another` по выводу совпадает с ответом по умолчанию (оба —
`base_schema`); строка таблицы оставлена, как была ветка.

**Доказательство.** Генератор `r10h1_golden_spec.rb` (rspec-файл пробника, не часть сьюта) прогоняет 30 случаев
`r10h1_cases.json` через хуки презентера и пишет снимок `spec/fixtures/presenters/content_showcase_hooks.json`:
случаи с полем `outcome` — каноническая форма ответа (символьные ключи и значения — `":имя"`, параметры —
`{"@parameters" => to_unsafe_h}`, порядок ключей сохранён) или `{"@raise" => класс}`. Случаи: все 9 точных id и
`autofill-N`, id «с `autofill-` внутри», неизвестный id, `submit` без id, `click` вместо `submit`, без `field`;
автозаполнение с карточкой ссылки, без неё, с битым URL, без картинок; `add-to-messenger` валидный, без заголовка, с
битым и «рыхлым» URL; `add-articles-to-messenger` все валидны / одна / первая невалидна / пусто / без статей;
`add-new-article`; разные `kind` (ловят подмену `kind` литералом); плюс три случая `initialize_hook` (код не
меняется, пиннится заодно). `FetchLinkCardService.new.call(url)` застаблен картой `link_cards` случая (сеть не
трогается). AC-003: снимок дерева = вывод генератора на коде BASE побайтно; спека исполнителя сверяет каждый случай
на коде дерева и BASE и под 27 мутантами. ISEQ-сверка (как в r10c) неприменима: структура кода меняется намеренно.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10h-ci`) на клонах 9c3146ba:

1. Замер без todo: 4 офенса `configure_hook` (раздел 3), у файла других нет; с патчем — 0; итог 120 → 116, роста ни
   у одной пары (коп, файл), строгий RuboCop с урезанным todo чист.
2. Генератор на коде BASE: `R10H_CASES=<путь>/r10h1_cases.json R10H_GOLDEN_OUT=<файл> bundle exec rspec
   docs/specs/fork-updates-r10h1-probes/r10h1_golden_spec.rb` (окружение — как в `r10h1_tests_gate.sh`) → снимок
   патча побайтно; на коде с патчем — тот же вывод.
3. Образец спеки (текст шага 1): 30 примеров зелёные на BASE и на дереве; 27/27 мутантов убиты (эквивалентный
   кандидат «`pick-another` → `pick_another`» исключён: ответ `pick-another` = ответ по умолчанию).
4. Полный сьют на BASE 9c3146ba: 1394 примера, 0 failures, 30 pending (снимки `--write-base`).
5. Утверждения о существующем коде (прочитаны тела): `AnnouncementRecord#autofill` зовёт `valid?` и
   `FetchLinkCardService.new.call(page_url)` только при валидном непустом URL; `schema`/`article_fields` читают
   `errors[:page_url]` (Rails 8.1 `errors[]` — `messages_for`, без записи); `generate_collection_definitions` делает
   `items.map!` (меняет массив `ctx`), затем `article_fields(i)` — массив массивов, отсюда `.flatten`; хуки зовёт только
   `AppPackageIntegration#presenter_hook_response` (`case` по имени хука), новые приватные методы снаружи не видны.
   Предположение: `ActionController::Parameters` от мессенджера несёт строковые id (JSON) — для не-строк `==` и поиск
   в хеше тоже совпадают (`nil` → `NoMethodError` в обоих).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимок — **только** `git apply` патчей. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения
исходников (раздел 1); спека чиста под RuboCop (AC-004, AC-005). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10h1-probes
export CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci
```

**Шаг 1. Снимок и спека — на коде BASE (характеризация первой).** Создай
`spec/services/message_apis/content_showcase/presenter_hooks_spec.rb` ровно с этим содержимым:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::ContentShowcase::Presenter, "hooks" do
  golden = JSON.parse(Rails.root.join("spec/fixtures/presenters/content_showcase_hooks.json").read)

  around do |example|
    I18n.with_locale(:en) { Time.use_zone("UTC") { example.run } }
  end

  def canon(obj)
    case obj
    when ActionController::Parameters then { "@parameters" => canon(obj.to_unsafe_h) }
    when Hash then obj.to_h { |k, v| [k.is_a?(Symbol) ? ":#{k}" : k.to_str, canon(v)] }
    when Array then obj.map { |v| canon(v) }
    when Symbol then ":#{obj}"
    when String, Integer, true, false, nil then obj
    else raise ArgumentError, "canon: #{obj.class}"
    end
  end

  def outcome
    result = yield
  rescue StandardError => e
    { "@raise" => e.class.name }
  else
    canon(result)
  end

  def stub_link_cards(cards)
    cards = cards.to_h do |url, card|
      [url, double("link card", title: card["title"], description: card["description"],
                                images: card["images"].map { |u| { url: u } })]
    end
    service = double("FetchLinkCardService")
    allow(service).to receive(:call) { |url| cards[url] }
    allow(FetchLinkCardService).to receive(:new).and_return(service)
  end

  golden.each do |c|
    it c["name"] do
      stub_link_cards(c["link_cards"])
      ctx = ActionController::Parameters.new(c["ctx"])
      result = outcome { described_class.public_send("#{c['hook']}_hook", kind: c["kind"], ctx: ctx) }
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(c["outcome"]))
    end
  end
end
```

```bash
git apply $P/r10h1_golden.patch
git add spec
git status --short        # ожидается ровно: "A  spec/fixtures/presenters/content_showcase_hooks.json" и "A  spec/services/message_apis/content_showcase/presenter_hooks_spec.rb"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 2 files
git commit -qm "Pin content showcase hooks"
```

**Шаг 2. Код.**

```bash
git apply $P/r10h1_rewrite.patch
git status --short        # ожидается ровно: " M app/services/message_apis/content_showcase/presenter.rb"
git commit -qam "Split content showcase configure hook"
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10h1_tests_gate.sh $B` (≈ 3 мин). Нужны строки
`R10H1 TREE PASS 30 examples`, `R10H1 BASE PASS 30 char / 0 renamed failing / 0 fix failing`, `R10H1 GOLDEN PASS 30
cases`, `R10H1 MUTANTS PASS 27/27 killed`, `R10H1 TESTS GATE PASS`. Красное — сверь спеку с текстом шага 1 посимвольно
и поправь её, не добавляя коммитов (код, патчи, снимок и мутантов не трогать):

```bash
C1=$(git log --format=%H -1 --grep '^Pin content showcase hooks$')
mkdir -p tmp/r10h1-spec && cp spec/services/message_apis/content_showcase/presenter_hooks_spec.rb tmp/r10h1-spec/
git reset --hard "$C1~1"    # коммитов вехи нет; копия спеки — в tmp/r10h1-spec (tmp/ игнорируется)
# поправь tmp/r10h1-spec/presenter_hooks_spec.rb, затем:
# cp tmp/r10h1-spec/presenter_hooks_spec.rb spec/services/message_apis/content_showcase/
# затем — команды шагов 1 и 2 (без повторного создания файла), затем снова шаг 3
```

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10h1 <<'PY'
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
git diff --stat            # ожидается: только .rubocop_todo.yml, 4 строки удалены
git commit -am "Drop R10h1 entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10h1

- Changed: `MessageApis::ContentShowcase::Presenter.configure_hook` is split without a change in
  behaviour (Metrics outliers of R8a, milestone R10h of the R10 programme): the chain of twelve
  field-id branches is a table of actions with one method per branch, and the response skeletons
  `{kind:, definitions:}` / `{kind: "initialize", definitions:, results:}` are two helpers. A golden
  fixture (spec/fixtures/presenters/content_showcase_hooks.json, 30 cases generated on the old code)
  pins the full output of every branch, and a new spec checks it. Its four todo lines are gone.
```

```bash
git commit -am "Note fork-updates-r10h1 in changelog"
```

**Шаг 6.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строки `R10H1 … PASS`; AC-004 — строки `backlog without todo: …` и `drop: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `content_showcase/presenter.rb` (только патчем), снимка (только патчем), новой спеки шага 1,
  `.rubocop_todo.yml` (только скриптом шага 4), `CHANGELOG.md`.
- Существующие спеки (`spec/services/message_apis/content_showcase/presenter_spec.rb` и др.) — не править и не
  переименовывать; `content_showcase/api.rb`, `inbox_sections/*` (веха R10h2), `ui_catalog/*` (веха R10g).
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`.
- Прочие строки и блоки todo.
- Никаких ручных правок кода и снимка, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h1-probes/rspec_gate_r10h1.sh'`

- **AC-002** — пути и байты: изменены ровно презентер и снимок (новый обычный файл), новая спека, todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; презентер и снимок побайтно равны BASE с двумя патчами; todo = BASE без четырёх строк content_showcase/presenter.rb блоков AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h1-probes/r10h1_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: снимок дерева побайтно равен выводу генератора постановщика на коде BASE (30 случаев); у каждого случая есть пример новой спеки, зелёный на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 27 мутантов r10h1_config.json (текст найден ровно один раз) роняет пример, не загрузку.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h1-probes/r10h1_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; у AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity 0 офенсов в презентере; ни у одного копа ни в одном файле (новая спека тоже) офенсов не больше, чем на BASE; итог упал ровно на измеренные 4.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h1-probes/r10h1_backlog_probe.sh $B > tmp/r10h1-backlog.txt; rc=$?; cat tmp/r10h1-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 4)}" tmp/r10h1-backlog.txt'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10h-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимка добавляет ровно снимок (= патч) и спеку, презентер = BASE; коммит кода меняет ровно презентер = BASE + патч; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10h1 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h1-probes/r10h1_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h1-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "cab259c26df9ebec9fa934b10283e4bcded5f8bcedf949da1712dea216ab76ba  docs/specs/fork-updates-r10h1-probes/examples_base.txt" "1b5700f22b290c736aa3932946ecf4915a668fb1b3ba140f9dd54e661852a682  docs/specs/fork-updates-r10h1-probes/pending_allowed.txt" "0d29d40b922ffce240481de5b50ab52db067e4ced9ea1734d0407450d9d0ee4d  docs/specs/fork-updates-r10h1-probes/r10h1_backlog_probe.sh" "89b18de104f3333d9a184d6c7ef5734920b4af7a6c48e813d4b6fca8cfdef52c  docs/specs/fork-updates-r10h1-probes/r10h1_cases.json" "801b313c2338c048ff8a5355f6d200dac5af17d7ec81a71fb0e1e1358bcd919a  docs/specs/fork-updates-r10h1-probes/r10h1_config.json" "67783a3e4cd760eb6649ce2a5825c9818ff5cf58677ee2a6e4788ec897f10a77  docs/specs/fork-updates-r10h1-probes/r10h1_golden.patch" "5261b84862d64fb647a2cea82b90449d159ce797f723e9a2cb9d8ac388139b79  docs/specs/fork-updates-r10h1-probes/r10h1_golden_spec.rb" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10h1-probes/r10h1_probe.py" "1c9fa7c1ca463ccb28d1a271086aeffdffe860a10728b90795a6926094905d03  docs/specs/fork-updates-r10h1-probes/r10h1_rewrite.patch" "fb7d29097c70fa049f26e3118b3cc9a3758d1abcf4269cc1be162ab476fe7059  docs/specs/fork-updates-r10h1-probes/r10h1_sentinel.rb" "560b4395497cfb117d228b8d4b57c771b577c75d7bfbed4d23f8df383b624b48  docs/specs/fork-updates-r10h1-probes/r10h1_tests.rb" "23a999e1ba67144f8ace1692185343ce842b8e653ca26eef4813731224742b8b  docs/specs/fork-updates-r10h1-probes/r10h1_tests_gate.sh" "05c0c9aa00acdf7179f6e01fc275154f171e865186e2af8e7be42c96ed59187a  docs/specs/fork-updates-r10h1-probes/rspec_gate_r10h1.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10h1-probes/source_scan.py" "c7d8730ef5874903d20afdec1a972f45808cf97acc1024c40683c48e27cbdc7f  docs/specs/fork-updates-r10h1-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10H1 paths without
the change`, `is not BASE + r10h1_golden.patch, r10h1_rewrite.patch`); AC-003 красный (`no examples ran`, `golden: …
missing in the tree`); AC-004 красный (`Metrics/AbcSize: 1 offenses left in the files of this milestone`, `total did
not go down`); AC-006 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10h-ci`).** Граница: клон от коммита спеки
поверх 9c3146ba (upstream — коммит спеки) — AC-001 (1394 примера, тот же набор), AC-005, AC-007, AC-008, AC-009 rc=0;
AC-002, AC-003 (`no examples ran`), AC-004 (`1 offenses left` у каждого из 4 копов, `total did not go down`), AC-006
красные ровно с сообщениями выше. Сборка по разделу 5 (спека — текст шага 1 из этого файла): все 9 критериев
зелёные (AC-001 — 1424 примеров, 0 failures, 30 pending; AC-003 — `R10H1 GOLDEN PASS 30 cases`, `R10H1 MUTANTS PASS
27/27 killed`; AC-004 — `backlog without todo: BASE 120, tree 116`, `drop: 4`; AC-007 — 2 файла). Порченая правка
поверх сборки (лишним коммитом): в снимке `"Card one"` → `"Card 0ne"` в одном `outcome` — AC-002 (`is not BASE +
r10h1_golden.patch, …`), AC-003 (пример `configure submit autofill with a link card` красный на дереве и на BASE,
`golden: … is not the generator's output on BASE (first difference at byte 8964)`), AC-006 (`extra commit after the
changelog commit`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10h1.md --exclude "docs/specs/fork-updates-r10h1-probes/**" --exclude docs/specs/fork-updates-r10h2.md --exclude "docs/specs/fork-updates-r10h2-probes/**" --exclude spec/fixtures/presenters/content_showcase_hooks.json --context "chaskiq fork-updates-r10h1: MessageApis::ContentShowcase::Presenter.configure_hook (Abc 90, Cyc 16, 87 строк) разбит без изменения поведения — цепочка 12 if по field.id → таблица CONFIGURE_ACTIONS (9 точных id) + include?(autofill-) → configure_autofill_article; каркасы {kind:, definitions:} и {kind: initialize, definitions:, results:} → configure_response/initialize_response; общая форма Top Articles → top_articles_response; новые методы private_class_method. Снимок spec/fixtures/presenters/content_showcase_hooks.json (30 случаев, вывод старого кода, исключён из ревью как данные) и спека, сверяющая каждый случай (зелёная на BASE и после, 27 мутантов); спека не читает исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10h1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h1-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h2-probes/**
REVIEW_EXCLUDE: spec/fixtures/presenters/content_showcase_hooks.json

Контекст ревьюеру: ветка, потерянная или переставленная при переходе к таблице (точный id против `include?`),
другой `kind` в ответе, `results` не тем объектом, порядок `autofill`/`valid?`/`schema`, короткое замыкание в
проверке статей, потерянный `.flatten`, другие аргументы `generate_collection_definitions`; спека, которая проверяет
не всё значение или читает исходник. Код и снимок править нельзя — замечание по месту решает постановщик (раздел 9);
спеку — можно, одним заходом (только если она расходится с текстом шага 1).

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10h1.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10h1.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после шагов 1–4 AC-004/AC-005
  красные — дефект спеки;
- `R10H1 GOLDEN` красный (снимок ≠ вывод генератора на BASE) или пример красный на BASE при спеке, посимвольно
  равной тексту шага 1, — дефект спеки, приложи вывод;
- пример зелёный на BASE и красный на дереве (патч меняет поведение) — пример и вывод: это дефект патча, не спеки;
- мутант выжил при спеке, посимвольно равной тексту шага 1, — id и вывод (эквивалентный мутант — дефект спеки);
  читать исходник, чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл расхождение поведения патча с BASE — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода, снимка и существующих спек, правка пробников, патчей и мутантов, `pending`/`skip`,
чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и коды возврата.

## 10. Стыки

Проверено на 9c3146ba (`git apply` патчей `r10e_rewrite`, `r10g_snapshots` + `r10g_rewrite`, обоих патчей
`r10h1` и `r10h2` в трёх порядках — e,g,h1,h2 / h1,h2,e,g / h2,g,h1,e: все чисты):

- **Код.** `r10e` меняет 10 спек и добавляет `spec/fixtures/requests/**`; `r10g` — `ui_catalog/presenter.rb` и
  `spec/fixtures/ui_catalog/**`; `r10h2` — `inbox_sections/presenter.rb` и `spec/fixtures/presenters/inbox_sections_hooks.json`.
  Ни одна не трогает файлы этой вехи (снимки — разные файлы, каталог `spec/fixtures/presenters/` общий с `r10h2`).
- **`.rubocop_todo.yml`.** `r10g`, `r10h1`, `r10h2` убирают каждая по строке из блоков `AbcSize`, `CyclomaticComplexity`,
  `MethodLength`, `PerceivedComplexity`; ни один блок не пустеет. В `PerceivedComplexity` строки `content_showcase` и
  `inbox_sections` соседние: при ПАРАЛЛЕЛЬНОМ прогоне `r10h1` и `r10h2` слияние второй ветки даёт текстовый конфликт в
  todo (и в CHANGELOG). Рекомендую ставить последовательно: вторая — после влития первой, с переносом BASE.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Что перемерить при переносе BASE** (раздел 2, п. 2): `git apply --check` обоих патчей; `git diff` каталога
  `content_showcase` (снимок годен, пока код BASE не менялся); 4 строки todo; итог бэклога (число `4` в AC-004 не
  меняется, меняются только итоги в выводе: на 9c3146ba 120 → 116; каждая влитая раньше веха снижает обе стороны —
  `r10e` на 39, `r10g` на 4, `r10h2` на 4); тексты мутантов; `--write-base` (примеры влитых вех) и sha256 AC-008.
- Мутационный прогон противоположным исполнителем (cx) — после 2026-11-22 11:39Z, по спеке
  `presenter_hooks_spec.rb` этой вехи.
