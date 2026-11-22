# fork-updates-r10b — выбросы RuboCop, шаг 10b: шесть одиночных сложных методов разбиты, поведение то же

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки: 2026-11-21. Спека —
  `docs/specs/fork-updates-r10b.md`, программа — `docs/specs/fork-updates-r10-programme.md` (веха R10b: «шесть
  одиночных выбросов … чистые функции или узкие методы без внешнего API; характеризация золотыми значениями»),
  план чистки — `docs/specs/fork-updates-rubocop-plan.md` (R8: выбросы — отдельные вехи рефакторинга с тестами).
  Парная веха — `fork-updates-r10a`, файлы кода не пересекаются. `fork-updates-r9b` уже влита (BASE).
- BASE_SHA: `16682f02e62acae780f15f7027e0d258237d7d16` — HEAD `main` «Record R9b acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1, rspec-rails 6.1.1).
- BASE плавающий: постановщик коммитит спеку (и пробники) поверх BASE_SHA — это нормально. Если `main` уйдёт
  дальше до запуска (влилась `r10a` или другая веха — раздел 10), постановщик переносит BASE (раздел 2),
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев считают
  `B=$(git merge-base HEAD @{u})` сами (коммит спеки; от BASE_SHA он отличается только `docs/specs`). В
  `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`; файлы спек — в REVIEW_EXCLUDE).
  Дифф вехи ≈ 30 КБ (больше половины — новые спеки).
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: шесть выбросов Metrics уходят (`AbcSize` у четырёх файлов, `CyclomaticComplexity` у
  `segment_comparator.rb`, `PerceivedComplexity` у `app_policy.rb`; шесть строк уходят из трёх блоков todo). Код
  задан патчем постановщика `r10b_rewrite.patch` (руками не править). Работа исполнителя — шесть НОВЫХ спек
  характеризации: каждый переписанный метод пиннится точными значениями по всем веткам, зелёными на BASE и
  после; каждый из 37 мутантов постановщика (`r10b_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, исключение, другой вызов. AC-007 (`source_scan.py`) ищет эти приёмы в новых и
изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r10b`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт
  постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не ставить. Образ
  `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r10b-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` — `mkdir -p vendor/bundle`
  (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r10b-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r10b_rewrite.patch`; строки шести файлов в блоках
   `Metrics/AbcSize`, `Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity` todo на месте (иначе пробник
   сам падает со «spec defect»); тексты 37 мутантов — каждый ровно один раз в своём файле после патча; имена
   шести новых спек не заняты. Перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R10B_CACHE=$HOME/.cache/chaskiq-r10b-ci bash docs/specs/fork-updates-r10b-probes/rspec_gate_r10b.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1285 примеров BASE 16682f02.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку BASE_SHA.
   Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 16682f02 (Docker, копия кэша `chaskiq-fxb-ci`): всего 254 офенса (только выбросы Metrics/LineLength); у вехи — 6
(значение / лимит): `Types::MessengerType#browser_data` AbcSize 40.7/30, `Dante::Converter.convert_inline_styles`
AbcSize 47/30, `FetchLinkCardService#attempt_oembed` AbcSize 40.5/30, `VisitCollector#add_web_sessions` AbcSize
32.3/30, `SegmentComparator#compare_with` Cyclomatic 14/13, `AppPolicy#find_role_by_resource` Perceived 14/13.
После патча — 248, новых офенсов нет (ни у одного копа ни в одном файле больше, чем на BASE).

| Метод | Правка | Почему поведение то же |
|---|---|---|
| `SegmentComparator#compare_with` | `case` из 13 веток → константа `COMPARISONS` (имя → лямбда), `COMPARISONS[comparison]&.call(user_input, predicate_value)` | `when "eq"` — это `"eq" === comparison` = `String#==`; поиск в хеше по строке — `eql?`, для строк то же; неизвестное/`nil`/символ → `nil`, как у `case` без `else`; тела лямбд — тела веток, аргументы в том же порядке, исключения те же (`nil < 1` → `NoMethodError`) |
| `AppPolicy#find_role_by_resource` | выбор app → `resource_app` (`@record` / `@record.app` / `@app`, иначе `yield`); `find_role_by_resource` — `resource_app { return }`, затем `if owner … @owner ||= true else @role ||= find_by` | ветки в том же порядке; нет app нигде → `return` из блока даёт `nil`, как раньше; запись с `app == nil` → `nil.owner_id` → `NoMethodError`, как раньше. Разница одна: `@record.app` читается один раз вместо двух (ассоциация AR — тот же объект) |
| `Dante::Converter.convert_inline_styles` | выбор покрывающих диапазонов → `ranges_at`, отметка ссылки → `link_marks`, ближайший конец → `next_range_end` | выражения перенесены как есть: стили покрывающих диапазонов, затем ссылка первого покрывающего entity (`marks << …` ≡ `concat` массива из 0/1 отметки), концы — покрывающих стилей и ВСЕХ entity, `min || text.length`; пропавший entity → `NoMethodError`, как раньше |
| `VisitCollector#add_web_sessions` | `merge!(k: v)` → `options[k] = v`; новая сессия → приватный `new_web_session` | ключи и порядок вставки те же; `Time.zone.now` зовётся в том же порядке и столько же раз; ранний `return` при пустом `last_visited_at` сохранён |
| `Types::MessengerType#browser_data` | хеш локации → приватный `location_params(request)` (выражения дословно), считается только при `request.location.present?` | раньше хеш строился всегда и отбрасывался без локации; выражения без побочных эффектов (безопасная навигация, `try`, чтение константы) |
| `FetchLinkCardService#attempt_oembed` | пять одинаковых `respond_to? ? … : ""` → цикл по `OEMBED_TEXT_FIELDS`; миниатюра → приватный `attach_oembed_thumbnail` | присваивания в том же порядке (`public_send("title=")` ≡ `card.title =`); `rescue OEmbed::NotFound` по-прежнему охватывает и миниатюру (помощник зовётся внутри метода) |

**Находки, которые спеки пиннят как есть (не чинить — программа, раздел 5):** `convert_inline_styles` не режет
текст там, где диапазон начинается после текущей позиции (стиль внутри абзаца теряется); `attempt_oembed`
пишет тип `"video"` в `enum :type` строкового столбца — сохраняется `nil`.

**`r10b_rewrite.patch`** — 6 файлов `app/`, +92/−79 строк; `.rubocop.yml` не меняется.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 16682f02:

1. Замер RuboCop без todo до и после патча (раздел 3): 254 → 248, у шести целевых пар (коп, файл) 0, других
   изменений нет; строгий RuboCop с урезанным todo чист.
2. Образцы шести спек постановщика: 63 примера зелёные на BASE и на дереве; 37/37 мутантов убиты.
3. Полный сьют на BASE (`--write-base`): 1285 примеров, 0 failures, 30 pending.
4. Патч применяется до и после патча `r10a` (оба порядка; раздел 10); пробный прогон и порченые правки
   — раздел 7. Предположение: `@record.app` у записей политик — ассоциация или чистый геттер (одно чтение вместо
   двух); других реализаций `app` с побочным эффектом `git grep` не находит.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в этом
порядке. Код — **только** `git apply` патча. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников (раздел 1);
спеки чисты под RuboCop (AC-004, AC-005). Значения проверяй точно (`eq(true)`, `eq([...])`, `be_nil`,
`raise_error(NoMethodError)`), не `be_truthy`. Приватные методы — через `send`, это не чтение исходника. Перед
шагом 1:

```bash
P=docs/specs/fork-updates-r10b-probes
export CHASKIQ_R10B_CACHE=$HOME/.cache/chaskiq-r10b-ci
```

**Шаг 1. Шесть спек** (каждая ветка метода — пример с точным значением; на BASE и после — зелёные):

- `spec/models/segment_comparator_compare_with_spec.rb`: `SegmentComparator.new(user: nil, predicates:
  []).compare_with(input, value, comparison)` — для каждого из 13 сравнений и истинный, и ложный случай
  (`contains_start`, `contains_ends`, `is_null` — `""`, `nil` → `true`, `"a"` → `false`; `is_not_null`, `contains`,
  `not_contains`, `not_eq`, `eq`, `lt`/`lteq`/`gt`/`gteq` — обязательно и равные значения `(2, 2)`, `in`); порядок
  аргументов (`("abc", "abcd", "contains")` → `false`, `("b", "a", "lt")` → `false`); `"between"`, `nil`, `:eq` →
  `nil`; `(nil, 1, "lt")` и `(nil, "x", "contains_start")` → `raise_error(NoMethodError)`; через `compare?` —
  предикат `email`/`contains_ends`/`example.com` пользователя `app.add_user` → `true`, `not_contains` → `false`.
- `spec/policies/app_policy_find_role_spec.rb`: app (`FactoryBot.create(:app)`), владелец (`add_agent`, затем
  `app.update!(owner_id:)`), участник с ролью `role = app.add_agent(...)`, чужой агент другого app, разговор
  `app.start_conversation`. `AppPolicy.new(record, user:, **params).find_role_by_resource`: app + владелец → `true`,
  `@owner` `true`, `@role` `nil`; app + участник → `role`, второй вызов не ищет роль снова (`allow(app).to
  receive(:roles).and_raise`); разговор + владелец/участник/чужой → `true`/`role`/`nil`; `nil`/`Object.new` с `app:`
  → владелец `true`, участник `role`, чужой `nil`; запись с app важнее параметра `app:` (два случая); ни записи,
  ни `app:` → `nil`, оба ivar `nil`; `double(app: nil)` с `app:` → `raise_error(NoMethodError)`.
- `spec/services/dante/converter_inline_styles_spec.rb`: `Dante::Converter.convert_inline_styles({text:,
  inlineStyleRanges:, entityRanges:}, entity_map)` `eq` полного массива узлов: без диапазонов → один узел без
  отметок, пустой текст → `[]`; BOLD [0,4) в `"bold text"` → два узла; BOLD [0,3) + ITALIC [0,6) в `"abcdefghi"` →
  `abc` bold+italic, `def` italic, `ghi` без; **как есть**: BOLD [0,6) + ITALIC [3,9) → `abcdef` bold, `ghi`
  italic, и BOLD [3,6) в `"abcdef"` → один узел без отметок; CODE и LINK-entity [0,4) в `"here now"` (ключ `0`,
  карта `{"0": …}`) → отметки `code`, затем `link` с `href`; не-LINK entity режет текст, но отметки не даёт; два
  перекрытых LINK-entity → у каждого куска ссылка первого покрывающего; entity без записи в карте →
  `NoMethodError`; `CUSTOM_COLOR_#a1b2c3` → `textStyle` с цветом.
- `spec/services/visit_collector_web_sessions_spec.rb`: `travel_to` фиксированного времени, пользователь
  `app.add_user`, поля через `update_columns`; `VisitCollector.new(user:).add_web_sessions` `eq` хеша и `keys`
  по порядку: новый (`first_seen`, `last_visited_at`, `web_sessions` nil) → все четыре ключа, `web_sessions: 1`;
  известный без визитов (`web_sessions: 4`) → `last_seen`, `5`, `last_visited_at`; 29 минут назад → только
  `last_seen`; 10 минут без `first_seen` → `first_seen`, `last_seen`; **ровно 30 минут** → новая сессия; 3 часа без
  `first_seen` и `web_sessions` → все четыре.
- `spec/graphql/types/messenger_browser_data_spec.rb`: `described_class.send(:new, app, {request:, get_app_user:
  -> { user }, set_locale: -> {}})`, затем `type.enabled_for_user` (ставит `@user`) и `type.send(:browser_data)`;
  `request` — `double(user_agent: <Chrome 120 на macOS 10.15.7>, accept_language: "es-CL,es;q=0.9", referrer:,
  remote_ip:, location:)`; `eq` всего хеша (строковые ключи): поля пользователя, браузер (`"Chrome"`, `"120"`,
  `:mac`, `"10.15.7"`, язык `"es"`), локация из `double(city:, region:, country:, country_code:, latitude:,
  longitude:, postal_code:, present?: true)`; без названия страны — `COUNTRY_NAMES[:CL]`; `location: nil` — без
  ключей локации.
- `spec/services/fetch_link_card_oembed_spec.rb`: `OEmbed::Providers.find(url)` → `instance_double(OEmbed::Provider)`,
  `get(url)` → `double` с нужными полями; `service.send(:attempt_oembed, PreviewCard.new(url:), url)`: все поля
  есть → возвращает карточку, `persisted?`, `attributes.slice(...)` `eq` (тип — `nil`, раздел 3; `height` nil → 0),
  без вложения; полей нет → `""` у пяти текстовых, `width` 0, `html` nil; `thumbnail_url` → `download_image`
  (застаблен, возвращает `Rack::Test::UploadedFile` любого файла из `spec/fixtures` с типом `image/png`) →
  `image.attached?`; исключение `download_image` → карточка сохранена без вложения; провайдера нет → `nil`;
  `OEmbed::NotFound` → `false`, карточка не сохранена.

```bash
git apply $P/r10b_rewrite.patch
git add spec/models/segment_comparator_compare_with_spec.rb spec/policies/app_policy_find_role_spec.rb spec/services/dante/converter_inline_styles_spec.rb spec/services/visit_collector_web_sessions_spec.rb spec/graphql/types/messenger_browser_data_spec.rb spec/services/fetch_link_card_oembed_spec.rb
git status --short        # ожидается: 6 строк "A  spec/…" и 6 строк " M app/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 6 files
git commit -qam "Split six complex methods"
```

**Шаг 2. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r10b_tests_gate.sh $B` (≈ 5 мин). Нужны три строки:
`R10B TREE PASS … examples`, `R10B BASE PASS … char / 0 renamed failing / 0 fix failing`, `R10B MUTANTS PASS
37/37 killed`. Пример красный на дереве или на BASE, мутант выжил — поправь спеку (код, патч и мутантов не
трогать; убийство — только поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Split six complex methods$')
mkdir -p tmp/r10b-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r10b-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r10b-specs (tmp/ игнорируется)
# поправь спеки в tmp/r10b-specs/spec/…, затем: cp -r tmp/r10b-specs/spec/. spec/
# затем — команды шага 1, затем снова шаг 2
```

**Шаг 3. todo** — убрать строки `cops_partial` конфига:

```bash
python3 -I - r10b <<'PY'
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
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R10b entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до и после),
текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r10b

- Changed: six Metrics outliers of R8a are split without a change in behaviour:
  `SegmentComparator#compare_with` (a table of comparisons), `AppPolicy#find_role_by_resource`
  (`resource_app`), `Dante::Converter.convert_inline_styles` (three helpers), `VisitCollector#add_web_sessions`,
  `Types::MessengerType#browser_data` and `FetchLinkCardService#attempt_oembed` (extracted helpers). Six specs
  pin every branch, including two defects kept as they are (styles that start mid-text are dropped by the
  draft converter; the oEmbed card type is never stored). Their six todo lines are gone.
```

```bash
git commit -am "Note fork-updates-r10b in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-001 — строка `examples=…`; AC-002 — строка `paths: …`;
AC-003 — три строки `R10B … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме 6 файлов патча (только патчем), шести новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Существующие спеки (`segment_comparator_compare_spec.rb`, `fetch_link_card_meta_spec.rb`, `fetch_link_service_spec.rb`,
  `spec/services/visit_collector.rb` и др.) — не править и не переименовывать.
- Найденные дефекты (раздел 3) — не чинить: веха сохраняет поведение.
- Гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`, `.rubocop.yml`; файлы вехи
  `r10a` (раздел 10).
- Прочие блоки todo и строки других файлов в блоках `AbcSize`/`CyclomaticComplexity`/`PerceivedComplexity`.
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R10B_CACHE=$HOME/.cache/chaskiq-r10b-ci bash docs/specs/fork-updates-r10b-probes/rspec_gate_r10b.sh'`

- **AC-002** — пути и код: изменены ровно 6 файлов патча, 6 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл патча побайтно равен BASE с патчем; todo = BASE без шести строк блоков AbcSize, CyclomaticComplexity, PerceivedComplexity; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10b-probes/r10b_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 6 спек зелёные на коде дерева и на коде BASE; ошибок вне примеров нет; каждый из 37 мутантов r10b_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10B_CACHE=$HOME/.cache/chaskiq-r10b-ci bash docs/specs/fork-updates-r10b-probes/r10b_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у AbcSize, CyclomaticComplexity, PerceivedComplexity 0 офенсов в файлах вехи (cops_partial); ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R10B_CACHE=$HOME/.cache/chaskiq-r10b-ci bash docs/specs/fork-updates-r10b-probes/r10b_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10b-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит правки меняет ровно 6 файлов = BASE + патч и добавляет ровно 6 спек; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r10b после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10b-probes/r10b_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10b-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "35649d1370a6d3171ccf5f23b7e3641fe3a3a4baf297e7a0a799e93701681781  docs/specs/fork-updates-r10b-probes/examples_base.txt" "48b58c4ac146e9a424754da1fcc1217da36739ee472edcb539d780c16cfc13ea  docs/specs/fork-updates-r10b-probes/pending_allowed.txt" "724d350082d64903cf8d178d5a74991a00244f9850863c64f0aaddcfe23ba440  docs/specs/fork-updates-r10b-probes/r10b_backlog_probe.sh" "48053691ab74f88652c946d7fe20ebaa86495c5a6325fffdfea4cf9e7bbdbec5  docs/specs/fork-updates-r10b-probes/r10b_config.json" "f42f4c8bcca1a0438898fa1e183f92a4b0a6d383f3ab230cdfebdfc953a9f2e9  docs/specs/fork-updates-r10b-probes/r10b_probe.py" "e3da8bfd8de1c0a729754a6cf5a30ecf787484384ce8897913cdd9db1507f518  docs/specs/fork-updates-r10b-probes/r10b_rewrite.patch" "997ef0d3885e2d3d5a10ef7004f0f5c13e1ec2f2343871a6b1604a591f55b9c0  docs/specs/fork-updates-r10b-probes/r10b_sentinel.rb" "ea45a6cf84d78aaf9ad02a8923c28dc98c1005d218007009085143d8b35ed511  docs/specs/fork-updates-r10b-probes/r10b_tests.rb" "991edf27fdbdb3c495b99ed2056c15e93b94998a22f6a9301606b33f7587d1b4  docs/specs/fork-updates-r10b-probes/r10b_tests_gate.sh" "8329d53f574ac0330abfad4729346c4eae261a6f04de1a1ff992e0445fa79a8a  docs/specs/fork-updates-r10b-probes/rspec_gate_r10b.sh" "07ef989866b11518877e4e6d1c4f4688d278d556647d994a9c6801784f303af8  docs/specs/fork-updates-r10b-probes/source_scan.py" "6b4db091732fa5c109d1ac0bbe4af6468713ff8291d6ff7d22dbbd01d1646645  docs/specs/fork-updates-r10b-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`R10B paths without
the change` / `is not BASE + r10b_rewrite.patch`); AC-003 красный (спек нет — `no examples ran`, тексты мутантов
не найдены); AC-004 красный (`Metrics/AbcSize: 4 offenses left in the files of this milestone`); AC-006 красный
(`missing commits`).

Пробный прогон постановщика на 16682f02: все 9 критериев зелёные, 37/37 мутантов убиты, бэклог 254 → 248. Приёмка 2026-11-22: исполнитель qw2, все 9 критериев зелёные на перезапуске постановщика (37/37), agy — без находок.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один — `agy`.**
Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель. **`codex` и
`qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни `ask-qwen`). Порядок:
коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений → FINAL_SHA; одна проверка `agy`
на `REVIEW_SHA..FINAL_SHA` (если что-то после ревью менялось). Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r10b.md --exclude "docs/specs/fork-updates-r10b-probes/**" --exclude docs/specs/fork-updates-r10a.md --exclude "docs/specs/fork-updates-r10a-probes/**" --context "chaskiq fork-updates-r10b: шесть выбросов Metrics без изменения поведения — SegmentComparator#compare_with case → таблица лямбд COMPARISONS (&.call, nil для неизвестного), AppPolicy#find_role_by_resource → resource_app с yield (nil без app, NoMethodError при app nil), Dante::Converter.convert_inline_styles → ranges_at/link_marks/next_range_end, VisitCollector#add_web_sessions → new_web_session, MessengerType#browser_data → location_params, FetchLinkCardService#attempt_oembed → OEMBED_TEXT_FIELDS + attach_oembed_thumbnail; 6 спек характеризации зелёные на BASE, 37 мутантов; два дефекта запиннены как есть; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r10b.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10b-probes/**
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r10a-probes/**

Контекст ревьюеру: отличие таблицы от `case` (ключ не-строка, порядок аргументов, `&.`), потерянная ветка или
изменённый порядок в `find_role_by_resource`, другое число/порядок вызовов `Time.zone.now`, отметки ссылки до
стилей, пропущенный диапазон в концах, присваивание, вышедшее из-под `rescue OEmbed::NotFound`; спека, которая
проверяет не всё значение или читает исходник. Код править нельзя — замечание по месту решает постановщик
(раздел 9); спеки — можно, одним заходом.

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
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r10b.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r10b.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши
его вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и `report.json`
готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт ниже — тогда
остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после патча AC-004/AC-005
  красные — дефект спеки;
- пример характеризации не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник, чтобы
  «убить» его, запрещено (раздел 1);
- пример зелёный на BASE и красный на дереве (патч меняет поведение) — пример и вывод: это дефект патча, не спеки;
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл расхождение поведения патча с BASE — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патча и мутантов, починка найденных
дефектов, `pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и
коды возврата.

## 10. Стыки

- **`fork-updates-r10a` (qw2) может идти параллельно.** Общих файлов кода нет (r10a — 20 файлов LineLength:
  `agent.rb`, `chaskiq_schema.rb`, `action_trigger_factory.rb`, `dante/migrator.rb`, `dante/renderer.rb`,
  `slack/api.rb`, 14 презентеров). Общие: `.rubocop_todo.yml` (r10b — строки блоков `Metrics/AbcSize`,
  `CyclomaticComplexity`, `PerceivedComplexity`; r10a — строки `Layout/LineLength`; ни один блок не пустеет) и
  `CHANGELOG.md` (блок после `# Changelog`). Проверено на 16682f02: оба патча применяются в любом порядке,
  скрипты todo — тоже, итог один.
- `fork-updates-r9b` влита в BASE 16682f02 (её файлы с этой вехой не пересекались; патч на db853da1 и на
  16682f02 одинаков).
- **Кто вливается вторым, тому — перенос BASE, `--write-base` (новые примеры первой вехи) и sha256 AC-008**
  (раздел 2, п. 2). Патч перегенерировать не нужно, пока `git apply --check` чист.
- Найденные дефекты (раздел 3 и программа, раздел 5) — кандидаты в веху фиксов; после неё примеры «как есть»
  в двух спеках этой вехи переписываются той вехой.
- Мутационный прогон по шести спекам — у противоположного исполнителя (cx), после снятия запрета на Codex
  2026-11-22 11:39Z.
