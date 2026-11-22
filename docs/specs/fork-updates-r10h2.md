# fork-updates-r10h2 — выбросы RuboCop, шаг 10h2: `inbox_sections` `content_hook` — блоки в методы, вывод пиннится золотым снимком

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-22. Спека —
  `docs/specs/fork-updates-r10h2.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10h:
  «`content_showcase` + `inbox_sections` … Характеризация: каждая ветка `ctx[:field][:id]`/`ctx[:values][:type]` →
  снимок хеша; `AnnouncementRecord` — с фиксированными записями. Подход: ветка → метод, общий каркас ответа
  (`{kind:, definitions:, results:}`) → помощник. Можно резать на две вехи (по файлу), если > 400 строк»). Дифф кода
  обоих файлов — 631 строка, поэтому веха разрезана: **R10h1** — `content_showcase` (`fork-updates-r10h1.md`),
  **R10h2** — `inbox_sections` (эта спека, патч 319 строк). План чистки — `docs/specs/fork-updates-rubocop-plan.md`.
  Шаблон — `fork-updates-r10g` (патч постановщика, золотые снимки на BASE пробником, спека-сверка, мутанты).
- BASE_SHA: `9b7d5cdf782c6f7d620dbc697af4d7d48e639fa5` — HEAD `main` «Record R10h1 acceptance» (К1 `CountAsOne: [array, hash,
  heredoc]` и R10c влиты; Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влились `r10e`, `r10g`, `r10h1` — раздел 10), постановщик переносит BASE (раздел 2), коммитит
  новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 85 КБ: ≈ 70 КБ — золотой снимок (JSON), ≈ 13 КБ — презентер, ≈ 2,5 КБ — спека.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные — или
  пока не сработал пункт раздела 9.**
- Цель: у `MessageApis::InboxSections::Presenter.content_hook` уходят 4 выброса (`AbcSize`,
  `CyclomaticComplexity`, `MethodLength`, `PerceivedComplexity`; их 4 строки уходят из todo). Код задан патчем
  постановщика `r10h2_rewrite.patch`, золотой снимок — патчем `r10h2_golden.patch` (оба руками не править). Работа
  исполнителя — одна НОВАЯ спека (текст дан в шаге 1), которая сверяет вывод хуков с 43 случаями снимка: зелёная на
  коде BASE и после; каждый из 31 мутанта постановщика (`r10h2_config.json`, `mutants`) роняет пример.

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

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10h2`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов (общий с R10h1):
  `$HOME/.cache/chaskiq-r10h-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-r10e-ci $HOME/.cache/chaskiq-r10h-ci` (уже сделан при написании спеки).
   **Уже нужно:** пока спека писалась, в `main` влились `r10e` и `r10g` (HEAD `fa3dcd14` «Record R10g acceptance»).
   Перемерено на fa3dcd14 (Docker): оба патча применяются, сборка по разделу 5 — AC-002, AC-004, AC-006 зелёные,
   бэклог 77 → 73 (`drop: 4`); код вехи и её 4 строки todo не менялись, снимок годен. Осталось: BASE_SHA →
   новый HEAD, `--write-base` (примеры `r10e`/`r10g` добавятся к 1394) и sha256 в AC-008.
2. При переносе BASE (после влития `r10e`, `r10g` или `r10h1`) перемерить; патчи не перегенерировать, пока всё сходится:
   - `git apply --check` патчей `r10h2_golden.patch`, затем `r10h2_rewrite.patch` на новом `main` чист (проверено:
     с патчами `r10e`, `r10g`, `r10h1` в трёх разных порядках);
   - каталог `app/services/message_apis/inbox_sections` на `main` не менялся
     (`git diff --quiet 9c3146ba main -- app/services/message_apis/inbox_sections`), как и `config/locales/*`
     (`common.visit`, формат `time.formats.short` `en`) — иначе снимок мог устареть: пересобрать его генератором
     (`r10h2_golden_spec.rb`, команда — раздел 4, п. 2) и патч;
   - 4 строки `inbox_sections/presenter.rb` в блоках `Metrics/AbcSize`, `CyclomaticComplexity`, `MethodLength`,
     `PerceivedComplexity` todo на месте (r10g и r10h1 убирают из тех же блоков СВОИ строки; блоки не пустеют);
   - бэклог-пробник на копии нового `main` со сборкой по разделу 5: у файла 4 → 0, роста нет, итог падает ровно на 4 —
     число `4` в команде AC-004 (сейчас 9c3146ba: 120 → 116; влитые `r10e`/`r10g`/`r10h1` снижают обе стороны на
     39/4/4);
   - тексты 31 мутанта — каждый ровно один раз в `presenter.rb` после патча; имя новой спеки не занято;
   - перегенерировать снимки сьюта на чистом checkout `main`:
     `CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h2-probes/rspec_gate_r10h2.sh --write-base`
     и пересчитать sha256 в AC-008. Сейчас в снимках — 1394 примера BASE 9c3146ba (влитая раньше веха добавит свои).
3. Раздел 8: Codex запрещён до 2026-11-22 11:39Z. Если клон снимается позже — постановщик по желанию заменяет
   раздел 8 полной политикой `cross-review-v1` (codex + agy) до коммита спеки.
4. Закоммитить в `main` одним коммитом: спеку, пробники, оба патча, снимки сьюта, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Место, поведение и почему

Замер — RuboCop без todo (Docker, кэш `chaskiq-r10h-ci`) на 9c3146ba: `content_hook` (`presenter.rb:185`) —
`AbcSize` 93.5/30, `CyclomaticComplexity` 22/13, `MethodLength` 55/30 (уже с К1), `PerceivedComplexity` 24/13.
Других офенсов у файла нет. Метод: `conversation = Conversation.find_by(key: ctx[:conversation_key])`,
`user = conversation.main_participant`, затем цепочка НЕЗАВИСИМЫХ `if` по `values[:block_type]`, каждая присваивает
`definitions` (без `return`): `user-blocks`, `conversation-events`, `user-properties-block`, `external-profiles`, затем
`if values[:c]` → `[{text: "foo", type: "text"}]`, затем `assignee-block`, `tag-blocks`; ответ — `{definitions:}`
(`nil`, если ничего не совпало).

**`r10h2_rewrite.patch`** (только `presenter.rb`, +80/−211): таблицы `EARLY_BLOCKS` (четыре блока до флага `c`) и
`LATE_BLOCKS` (`assignee-block`, `tag-blocks` — после него), лямбды свойств пользователя — константа
`USER_PROPERTIES` (метка → лямбда, тот же порядок); `content_hook` — 8 строк: ранний блок из таблицы, затем флаг `c`,
затем поздний блок, ответ `{definitions:}`. Блоки → методы `user_block`, `events_block`, `user_properties_block`,
`external_profiles_block`, `assignee_block`, `tags_block`; кнопка «Visit» (общая для пользователя и агента) —
помощник `visit_button(id, url)`. Все новые методы — `private_class_method`. Хуки `initialize_hook`,
`configure_hook`, `submit_hook`, `base_schema`, `user_data` не тронуты. После патча у файла 0 офенсов.

**Почему поведение то же.** Порядок присваиваний сохранён: ранний блок строится ВСЕГДА, даже если потом его заменит
`c` (на BASE ветка исполнялась целиком — её исключения и вызовы те же: «`user-blocks` с `c` без участника» по-прежнему
`NoMethodError`); поздний блок строится после `c` и побеждает его; блок вне таблиц — `definitions` остаётся `nil`.
`block_type` один, поэтому совпасть может не больше одной строки таблиц — как одна ветка цепочки. Поиск по хешу
вместо `==`: для строк и `nil` одно и то же. Литералы перенесены с тем же порядком ключей; `display_name.presence ||
"---"`, `email.present?`, `assignee.blank?`, `assignee&.display_name&.empty? ? email : display_name` (на BASE —
`assignee&.…` в обеих ветках; `assignee` здесь не `nil`), `compact.join(", ")`/`join(", ")`, `rescue StandardError → nil`
у «Last Seen», `.flatten` у профилей — дословно. Пустые профили → новый хеш на каждый вызов, как раньше (не
константа). `I18n.t("common.visit")` вычисляется после URL кнопки — чистые вызовы, значение то же.

**Доказательство.** Генератор `r10h2_golden_spec.rb` (rspec-файл пробника, не часть сьюта) прогоняет 43 случая
`r10h2_cases.json` через хуки презентера и пишет снимок `spec/fixtures/presenters/inbox_sections_hooks.json`:
случаи с полем `outcome` — каноническая форма ответа (символьные ключи и значения — `":имя"`, параметры —
`{"@parameters" => to_unsafe_h}`, порядок ключей сохранён) или `{"@raise" => класс}`. `Conversation.find_by(key:)`
застаблен беседой случая — фиксированные записи на дублях RSpec (`double`): участник (все поля, пустой, частичный, нет),
события с фиксированными id/временем, теги, агент (с именем, `""`, `nil`, нет), ключ приложения. Дубли строгие:
сообщение, которого BASE не посылал, роняет пример (это `Exception`, не `StandardError`, `outcome` его не ловит).
Случаи: каждый `block_type` во всех вариантах данных, каждый блок с `c` (ранние — заменяются, поздние — нет),
только `c`, `c: false`, неизвестный блок, без `values`, беседа не найдена, нет участника; плюс 12 случаев
`configure_hook`/`initialize_hook` (код не меняется, пиннится заодно: id списка, `values[:type]`). Время — UTC,
локаль `en` (хук `around`). AC-003: снимок дерева = вывод генератора на коде BASE побайтно; спека исполнителя
сверяет каждый случай на коде дерева и BASE и под 31 мутантом. ISEQ-сверка неприменима: структура кода меняется
намеренно.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-22 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r10h-ci`) на клонах 9c3146ba:

1. Замер без todo: 4 офенса `content_hook` (раздел 3), у файла других нет; с патчем — 0; итог 120 → 116, роста ни у
   одной пары (коп, файл), строгий RuboCop с урезанным todo чист.
2. Генератор на коде BASE: `R10H_CASES=<путь>/r10h2_cases.json R10H_GOLDEN_OUT=<файл> bundle exec rspec
   docs/specs/fork-updates-r10h2-probes/r10h2_golden_spec.rb` (окружение — как в `r10h2_tests_gate.sh`) → снимок
   патча побайтно; на коде с патчем — тот же вывод.
3. Образец спеки (текст шага 1): 43 примера зелёные на BASE и на дереве; 31/31 мутант убит (кандидат «метка `Visit`
   литералом вместо `I18n.t`» исключён как эквивалентный при локали `en`).
4. Полный сьют на BASE 9c3146ba: 1394 примера, 0 failures, 30 pending (снимки `--write-base`).
5. Утверждения о существующем коде (прочитаны тела): `Conversation` — `belongs_to :main_participant` (`AppUser`),
   `:assignee` (`Agent`), `acts_as_taggable_on :tags`, `events` из `Eventable`; хуки зовёт только
   `AppPackageIntegration#presenter_hook_response` (`case` по имени хука), новые приватные методы снаружи не видны;
   `I18n.t("common.visit")` в `en` — `Visit`; формат `I18n.l(…, format: :short)` в `en` — `%d %b %H:%M`;
   `I18n.l(nil)` бросает `I18n::ArgumentError` (`StandardError`) — «Last Seen» `nil`. Предположение: настоящие
   записи (`AppUser`, `Agent`, `ExternalProfile`) отвечают на те же сообщения, что дубли (`external_profiles` —
   записи с `[]`), — код вызывает у них ровно то же, что на BASE, дубли это и проверяют.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код и снимок — **только** `git apply` патчей. Никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения
исходников (раздел 1); спека чиста под RuboCop (AC-004, AC-005). Перед шагом 1:

```bash
P=docs/specs/fork-updates-r10h2-probes
export CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci
```

**Шаг 1. Снимок и спека — на коде BASE (характеризация первой).** Создай
`spec/services/message_apis/inbox_sections/presenter_hooks_spec.rb` ровно с этим содержимым (каталог создай:
`mkdir -p spec/services/message_apis/inbox_sections`):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::InboxSections::Presenter, "hooks" do
  golden = JSON.parse(Rails.root.join("spec/fixtures/presenters/inbox_sections_hooks.json").read)

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

  def time(value)
    value && Time.zone.parse(value)
  end

  def build_conversation(conv)
    return if conv.nil?

    user = conv["user"]&.to_h { |k, v| [k.to_sym, k.end_with?("_at") ? time(v) : v] }
    events = double("events")
    allow(events).to receive(:order).with("events.id asc").and_return(
      conv["events"].map { |e| double("event", id: e["id"], action: e["action"], created_at: time(e["created_at"])) }
    )
    double("conversation", main_participant: user && double("user", user), events: events, tag_list: conv["tags"],
                           assignee: conv["assignee"] && double("assignee", conv["assignee"].transform_keys(&:to_sym)),
                           app: double("app", key: conv["app_key"]))
  end

  golden.each do |c|
    it c["name"] do
      allow(Conversation).to receive(:find_by).with(key: c["ctx"]["conversation_key"])
                                              .and_return(build_conversation(c["conversation"]))
      ctx = ActionController::Parameters.new(c["ctx"])
      result = outcome { described_class.public_send("#{c['hook']}_hook", kind: c["kind"], ctx: ctx) }
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(c["outcome"]))
    end
  end
end
```

```bash
git apply $P/r10h2_golden.patch
git add spec
git status --short        # ожидается ровно: "A  spec/fixtures/presenters/inbox_sections_hooks.json" и "A  spec/services/message_apis/inbox_sections/presenter_hooks_spec.rb"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 2 files
git commit -qm "Pin inbox sections hooks"
```

**Шаг 2. Код.**

```bash
git apply $P/r10h2_rewrite.patch
git status --short        # ожидается ровно: " M app/services/message_apis/inbox_sections/presenter.rb"
git commit -qam "Split inbox sections content hook"
```

**Шаг 3. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10h2_tests_gate.sh $B` (≈ 4 мин). Нужны строки
`R10H2 TREE PASS 43 examples`, `R10H2 BASE PASS 43 char / 0 renamed failing / 0 fix failing`, `R10H2 GOLDEN PASS 43
cases`, `R10H2 MUTANTS PASS 31/31 killed`, `R10H2 TESTS GATE PASS`. Красное — сверь спеку с текстом шага 1 посимвольно
и поправь её, не добавляя коммитов (код, патчи, снимок и мутантов не трогать):

```bash
C1=$(git log --format=%H -1 --grep '^Pin inbox sections hooks$')
mkdir -p tmp/r10h2-spec && cp spec/services/message_apis/inbox_sections/presenter_hooks_spec.rb tmp/r10h2-spec/
git reset --hard "$C1~1"    # коммитов вехи нет; копия спеки — в tmp/r10h2-spec (tmp/ игнорируется)
# поправь tmp/r10h2-spec/presenter_hooks_spec.rb, затем:
# mkdir -p spec/services/message_apis/inbox_sections && cp tmp/r10h2-spec/presenter_hooks_spec.rb spec/services/message_apis/inbox_sections/
# затем — команды шагов 1 и 2 (без повторного создания файла), затем снова шаг 3
```

**Шаг 4. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10h2 <<'PY'
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
git commit -am "Drop R10h2 entries from RuboCop todo"
```

**Шаг 5. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-22 — fork-updates-r10h2

- Changed: `MessageApis::InboxSections::Presenter.content_hook` is split without a change in
  behaviour (Metrics outliers of R8a, milestone R10h of the R10 programme): each block type is a
  method, picked from two tables (blocks before and after the `c` flag, in the order of the old
  chain), and the "Visit" button is one helper. A golden fixture
  (spec/fixtures/presenters/inbox_sections_hooks.json, 43 cases generated on the old code, records
  as fixed doubles) pins the full output of every block and hook, and a new spec checks it. Its four
  todo lines are gone.
```

```bash
git commit -am "Note fork-updates-r10h2 in changelog"
```

**Шаг 6.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 7.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — строки `R10H2 … PASS`; AC-004 — строки `backlog without todo: …` и `drop: …`; AC-007 — строка
`SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме `inbox_sections/presenter.rb` (только патчем), снимка (только патчем), новой спеки шага 1,
  `.rubocop_todo.yml` (только скриптом шага 4), `CHANGELOG.md`.
- Существующие спеки (`spec/services/message_apis/inbox_sections_user_data_spec.rb` и др.) — не править и не
  переименовывать; `inbox_sections/api.rb`, `content_showcase/*` (веха R10h1), `ui_catalog/*` (веха R10g).
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`.
- Прочие строки и блоки todo.
- Никаких ручных правок кода и снимка, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения
  исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h2-probes/rspec_gate_r10h2.sh'`

- **AC-002** — пути и байты: изменены ровно презентер и снимок (новый обычный файл), новая спека, todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; презентер и снимок побайтно равны BASE с двумя патчами; todo = BASE без четырёх строк inbox_sections/presenter.rb блоков AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h2-probes/r10h2_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: снимок дерева побайтно равен выводу генератора постановщика на коде BASE (43 случая); у каждого случая есть пример новой спеки, зелёный на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 31 мутанта r10h2_config.json (текст найден ровно один раз) роняет пример, не загрузку.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h2-probes/r10h2_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок с обеих сторон; у AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity 0 офенсов в презентере; ни у одного копа ни в одном файле (новая спека тоже) офенсов не больше, чем на BASE; итог упал ровно на измеренные 4.
  `bash -c 'B=$(git merge-base HEAD @{u}) && mkdir -p tmp && CHASKIQ_R10H_CACHE=$HOME/.cache/chaskiq-r10h-ci bash docs/specs/fork-updates-r10h2-probes/r10h2_backlog_probe.sh $B > tmp/r10h2-backlog.txt; rc=$?; cat tmp/r10h2-backlog.txt; test $rc = 0 && awk "/^backlog without todo: BASE [0-9]+, tree [0-9]+;/ {gsub(/[,;]/, \"\"); d = \$5 - \$7; n++} END {print \"drop: \" d; exit !(n == 1 && d == 4)}" tmp/r10h2-backlog.txt'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10h-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит снимка добавляет ровно снимок (= патч) и спеку, презентер = BASE; коммит кода меняет ровно презентер = BASE + патч; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10h2 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h2-probes/r10h2_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10h2-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "fbc9b41ae6829b6461344a9be5cab40764574241e64f00e6aa3acdcf8d74a7b4  docs/specs/fork-updates-r10h2-probes/examples_base.txt" "2d9cea960a155fb702b8f15e2ede84261a882e29caec376b8f9ac38d2ffc9ba2  docs/specs/fork-updates-r10h2-probes/pending_allowed.txt" "1f1278f479405e7200d45d8acd8af016bedc404b5f606abeeadd7d27c7b3eccc  docs/specs/fork-updates-r10h2-probes/r10h2_backlog_probe.sh" "cd6d7b3e233d63d26e3eb3329f596c3792f92fe23e7b0611d4d4941a95acf8ad  docs/specs/fork-updates-r10h2-probes/r10h2_cases.json" "415b580c537887d97fa8f9b5c2b3d0317c5f1416c42c5332868612f634a12aab  docs/specs/fork-updates-r10h2-probes/r10h2_config.json" "6a8d82255011417054cc2cdec5a88e2f32a20b62c9d5117098e6c56a81095c02  docs/specs/fork-updates-r10h2-probes/r10h2_golden.patch" "fc7766a0cc81a37090eecf08ae0b4dbc07ae7233c8d96e5d23bdcb2074110065  docs/specs/fork-updates-r10h2-probes/r10h2_golden_spec.rb" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10h2-probes/r10h2_probe.py" "ab2a22988d5bede5e180915c6aeacd019887e7c3f72515421135517b5aa9d61c  docs/specs/fork-updates-r10h2-probes/r10h2_rewrite.patch" "19f381cdadef5e2d0f32955bce4228dfc42b1ddaab1782d71f1120b079740267  docs/specs/fork-updates-r10h2-probes/r10h2_sentinel.rb" "2d6748f607968b6efd1a77f3319f88a1d8884f62450c21e95a4c05d49cf80bdb  docs/specs/fork-updates-r10h2-probes/r10h2_tests.rb" "59adaa4f2c46c04d57c8f7156253883a3272b906a8d0cc99de3d6a2d2ce98c60  docs/specs/fork-updates-r10h2-probes/r10h2_tests_gate.sh" "a45ba1f966f18b70300341b9d566a608e927f255f274ea4e17b2bd91c8aaa5e6  docs/specs/fork-updates-r10h2-probes/rspec_gate_r10h2.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10h2-probes/source_scan.py" "d5943a4cb109293281f0b2252b748eab3f3b67796068dba17fef2590d7f43082  docs/specs/fork-updates-r10h2-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10H2 paths without
the change`, `is not BASE + r10h2_golden.patch, r10h2_rewrite.patch`); AC-003 красный (`no examples ran`, `golden: …
missing in the tree`); AC-004 красный (`Metrics/AbcSize: 1 offenses left in the files of this milestone`, `total did
not go down`); AC-006 красный (`missing commits`).

**Пробный прогон постановщика (2026-11-22, Docker, кэш `chaskiq-r10h-ci`).** Граница: клон от коммита спеки
поверх 9c3146ba (upstream — коммит спеки) — AC-001 (1394 примера, тот же набор), AC-005, AC-007, AC-008, AC-009 rc=0;
AC-002, AC-003 (`no examples ran`), AC-004 (`1 offenses left` у каждого из 4 копов, `total did not go down`), AC-006
красные ровно с сообщениями выше. Сборка по разделу 5 (спека — текст шага 1 из этого файла): все 9 критериев
зелёные (AC-001 — 1437 примеров, 0 failures, 30 pending; AC-003 — `R10H2 GOLDEN PASS 43 cases`, `R10H2 MUTANTS PASS
31/31 killed`; AC-004 — `backlog without todo: BASE 120, tree 116`, `drop: 4`; AC-007 — 2 файла). Порченая правка
поверх сборки (лишним коммитом): в «Location» `[u.region, u.city, …]` → `[u.city, u.region, …]` — AC-002 (`is not BASE
+ r10h2_golden.patch, …`), AC-003 (пример `content user-properties-block` красный на дереве, `golden: tree: case …
has no passed example`), AC-006 (`extra commit after the changelog commit`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10h2.md --exclude "docs/specs/fork-updates-r10h2-probes/**" --exclude docs/specs/fork-updates-r10h1.md --exclude "docs/specs/fork-updates-r10h1-probes/**" --exclude spec/fixtures/presenters/inbox_sections_hooks.json --context "chaskiq fork-updates-r10h2: MessageApis::InboxSections::Presenter.content_hook (Abc 93, Cyc 22, 55 строк) разбит без изменения поведения — цепочка независимых if по values[:block_type] → таблицы EARLY_BLOCKS (user-blocks, conversation-events, user-properties-block, external-profiles: строятся до флага c и заменяются им) и LATE_BLOCKS (assignee-block, tag-blocks: строятся после c и побеждают), блоки → user_block/events_block/user_properties_block/external_profiles_block/assignee_block/tags_block, лямбды свойств → USER_PROPERTIES, кнопка Visit → visit_button; новые методы private_class_method. Снимок spec/fixtures/presenters/inbox_sections_hooks.json (43 случая, вывод старого кода на дублях записей, исключён из ревью как данные) и спека, сверяющая каждый случай (зелёная на BASE и после, 31 мутант); спека не читает исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10h2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h2-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10h1-probes/**
REVIEW_EXCLUDE: spec/fixtures/presenters/inbox_sections_hooks.json

Контекст ревьюеру: ранний блок, который перестал строиться при `c` (исключения и вызовы BASE), поздний блок,
попавший под `c`, блок не в той таблице, переставленные метки или лямбды свойств, другой порядок ключей литерала,
`present?`/`blank?`/`presence` заменены на проверку `nil`, потерянный `.flatten`, разделяемый (замороженный) хеш
вместо нового; спека, которая проверяет не всё значение или читает исходник. Код и снимок править нельзя —
замечание по месту решает постановщик (раздел 9); спеку — можно, одним заходом (только если она расходится с
текстом шага 1).

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10h2.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10h2.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после шагов 1–4 AC-004/AC-005
  красные — дефект спеки;
- `R10H2 GOLDEN` красный (снимок ≠ вывод генератора на BASE) или пример красный на BASE при спеке, посимвольно
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
`r10h2` и `r10h1` в трёх порядках — e,g,h1,h2 / h1,h2,e,g / h2,g,h1,e: все чисты):

- **Код.** `r10e` меняет 10 спек и добавляет `spec/fixtures/requests/**`; `r10g` — `ui_catalog/presenter.rb` и
  `spec/fixtures/ui_catalog/**`; `r10h1` — `content_showcase/presenter.rb` и `spec/fixtures/presenters/content_showcase_hooks.json`.
  Ни одна не трогает файлы этой вехи (снимки — разные файлы, каталог `spec/fixtures/presenters/` общий с `r10h1`).
- **`.rubocop_todo.yml`.** `r10g`, `r10h2`, `r10h1` убирают каждая по строке из блоков `AbcSize`, `CyclomaticComplexity`,
  `MethodLength`, `PerceivedComplexity`; ни один блок не пустеет. В `PerceivedComplexity` строки `content_showcase` и
  `inbox_sections` соседние: при ПАРАЛЛЕЛЬНОМ прогоне `r10h2` и `r10h1` слияние второй ветки даёт текстовый конфликт в
  todo (и в CHANGELOG). Рекомендую ставить последовательно: вторая — после влития первой, с переносом BASE.
- **`CHANGELOG.md`.** Все вехи вставляют блок сразу после `# Changelog`; при последовательном влитии конфликта нет.
- **Что перемерить при переносе BASE** (раздел 2, п. 2): `git apply --check` обоих патчей; `git diff` каталога
  `inbox_sections` и локалей `en` (снимок годен, пока они не менялись); 4 строки todo; итог бэклога (число `4` в AC-004 не
  меняется, меняются только итоги в выводе: на 9c3146ba 120 → 116; каждая влитая раньше веха снижает обе стороны —
  `r10e` на 39, `r10g` на 4, `r10h1` на 4); тексты мутантов; `--write-base` (примеры влитых вех) и sha256 AC-008.
- Мутационный прогон противоположным исполнителем (cx) — после 2026-11-22 11:39Z, по спеке
  `presenter_hooks_spec.rb` этой вехи.
