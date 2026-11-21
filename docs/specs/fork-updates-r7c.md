# fork-updates-r7c — бэклог RuboCop, шаг 7c: предикаты переименованы, старые имена остаются алиасами

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-21. Спека — `docs/specs/fork-updates-r7c.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «Решения владельца 2026-11-20, вторая партия»:
  «`PredicateMethod` — … остальные 6 переименовать с alias старого имени; `PredicatePrefix` — переименовать,
  старое имя alias»).
- BASE_SHA: `8e2ddd3ddddf86b4fb6909ef4248950902d3fd04` — HEAD `main` «Record R3b-3 acceptance» (Ruby 4.0.10,
  RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1).
- BASE плавающий: если `main` уйдёт дальше до запуска (R2b, fix-cleanup-3, R7b, R7d — раздел 10), постановщик
  переносит его (раздел 2), коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 14 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно шаги раздела 5,
  ровно этими командами, по одному. **Не останавливайся, пока все девять критериев раздела 7 не зелёные —
  или пока не сработал пункт раздела 9.**
- Цель: в дереве не остаётся `Naming/PredicatePrefix` (7 офенсов, 6 файлов; блок уходит из todo) и
  `Naming/PredicateMethod` в `outgoing_webhook.rb` и `origin_validator.rb` (их строки уходят из блока).
  Восемь методов переименованы, каждое старое имя остаётся `alias` нового — вызывающие, стабы спек и
  интеграции не меняются. Код задан патчем постановщика (руками не править). Работа исполнителя — шесть
  НОВЫХ спек: примеры на старых именах (характеризация: зелёные на BASE и после) и вложенный
  `describe "renamed"` на новых именах (красные на BASE — имени ещё нет, зелёные после); каждый из 25 мутантов
  постановщика (`r7c_config.json`, `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `Rails.root.glob(...)`, `File.read`/`IO.read`/`readlines`/`Pathname(...)`
путей кода, `Dir.glob` по ним, `method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`,
`RubyVM::AbstractSyntaxTree`/`InstructionSequence`, `.disasm`), `` `cat`/`grep` `` в шелле — и затем
`expect(source).to match(...)`. Мутант убит, только если код с мутантом **ведёт себя** иначе: другое
возвращаемое значение, исключение, видимость метода. AC-007 (`source_scan.py`) ищет эти приёмы в новых и
изменённых файлах `spec/` и валит критерий на любом совпадении.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r7c`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r7c-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `cp -a $HOME/.cache/chaskiq-fxb-ci $HOME/.cache/chaskiq-r7c-ci` (если его ещё нет).
2. При переносе BASE: `git apply --check` патча `r7c_rename`; блок `Naming/PredicatePrefix` и строки
   `outgoing_webhook.rb`/`origin_validator.rb` блока `Naming/PredicateMethod` в todo на месте (пробник сам
   падает со «spec defect»); тексты 25 мутантов — каждый ровно один раз в своём файле после патча; имена
   шести новых спек не заняты; `git grep` вызывающих (раздел 3) не нашёл новых. Если менялся `spec/` —
   перегенерировать снимки на чистом checkout `main`:
   `CHASKIQ_R7C_CACHE=$HOME/.cache/chaskiq-r7c-ci bash docs/specs/fork-updates-r7c-probes/rspec_gate_r7c.sh --write-base`
   и пересчитать sha256 в AC-008. Сейчас в снимках — 1059 примеров BASE 8e2ddd3d.
3. Закоммитить в `main` одним коммитом: спеку, пробники, патч, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Замер — RuboCop без todo на BASE 8e2ddd3d: `Naming/PredicatePrefix` 7 (план — 7), `Naming/PredicateMethod`
15 (план — 15: 9 в `app/graphql/types` — Exclude в R7b; 2 — здесь; 4 — раздел 10). Всего 1090, после вехи 1081.

**`r7c_rename.patch` — восемь переименований.** Правило одно для всех: `def <старое>` → `def <новое>`, сразу
после `end` метода — строка `alias <старое> <новое>` с тем же отступом; тело метода и все вызывающие не
меняются (вызывающие идут через алиас, стабы `allow_any_instance_of(…).to receive(:<старое>)` продолжают
перехватывать вызов). Новое имя — то, что предлагает RuboCop (`PredicatePrefix` — без `is_`/`has_`;
`PredicateMethod` — с `?`). Алиасы RuboCop не проверяет (проверено: после патча у обоих копов 0 офенсов в шести
файлах, других новых офенсов нет).

| Файл:строка BASE | Было → стало | Вызывающие (`git grep` по `app lib config spec`, JS, вьюхи) |
|---|---|---|
| `api/v1/hooks_controller.rb:77` (private) | `is_notification_message?` → `notification_message?` | `before_action :handle_notification, if: :is_notification_message?` (:13); стаб в `hooks_controller_spec.rb:1013` |
| `app_package.rb:48` | `is_external?` → `external?` | 4 валидации `if: -> { is_external? }`, `:113`; `app_package_integration.rb` ×6; `create_integration.rb:24`; `be_is_external` в 3 спеках |
| `conversation_part.rb:48` | `is_event_message?` → `event_message?` | `:181`, `:227` того же файла |
| `conversation_part.rb:190` | `is_from_auto_message_campaign?` → `from_auto_message_campaign?` | `:181` |
| `conversation.rb:220` | `has_user_visible_comment?` → `user_visible_comment?` | `:216` |
| `outgoing_webhook.rb:17` | `is_enabled` → `enabled?` (оба копа) | `as_json`: `hash["enabled"] = is_enabled` (:23) |
| `origin_validator.rb:17` | `is_valid?` → `valid?` | `api_controller.rb:191`, `application_cable/connection.rb:46`; стабы в `api/graphql_controller_spec.rb`; `be_is_valid` в `origin_validator_spec.rb` |
| `origin_validator.rb:30` | `validate_domain` → `validate_domain?` (`PredicateMethod`) | `:22` того же файла |

Ни одно имя не поле GraphQL, не ключ JSON для фронтенда (в `app/javascript` нет ни одного), не метод
`as_json(methods:)` и не аргумент job (Sidekiq сериализует аргументы, не имена методов). Коллизий нет:
`OutgoingWebhook#state` — строка без `enum`, `enabled?` не определён; у `AppPackage`, `ConversationPart`,
`Conversation` нет столбцов `external`, `event_message`, `user_visible_comment` (`db/schema.rb`). Видимость:
`notification_message?` в секции `private` контроллера, алиас — тоже private (у контроллера публичный метод был
бы экшеном); остальные публичные, как были.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-21 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, копия кэша `chaskiq-fxb-ci`) на
клонах BASE 8e2ddd3d:

1. Замер RuboCop без todo до и после патча (раздел 3).
2. Образцы шести спек постановщика (содержание — раздел 5): 9 примеров на старых именах зелёные на BASE и
   дереве, 9 примеров `renamed` красные на BASE (`NoMethodError`), зелёные на дереве; 25/25 мутантов убиты.
3. Патч применяется поверх патчей R2b, fix-cleanup-3, R7b и R7d и наоборот (раздел 10).
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: внешние плагины (каталог `MessageApis`, загружаемый `Plugins::TarDownloader`) зовут только
старые имена — они и остаются.

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей, ровно в
этом порядке. Код — **только** `git apply` патча. В каждой спеке `# frozen_string_literal: true`,
`require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:` директив, чтения исходников
(раздел 1); спеки чисты под RuboCop (AC-004, AC-005). Значения проверяй точно: `eq(true)` / `eq(false)`, не
`be_truthy`. Модели — `Model.new(...)` без сохранения. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r7c-probes
export CHASKIQ_R7C_CACHE=$HOME/.cache/chaskiq-r7c-ci
```

**Шаг 1. Шесть спек.** В каждой — примеры на СТАРЫХ именах на верхнем уровне `describe` и вложенный
`describe "renamed"` с теми же входами и теми же ожиданиями на НОВЫХ именах. Гейт тестов узнаёт пример
«renamed» по подстроке ` renamed ` в полном описании — в описаниях остальных примеров слова `renamed` нет.

- `spec/controllers/api/v1/hooks_notification_alias_spec.rb` (`RSpec.describe Api::V1::HooksController`):
  экземпляр `Api::V1::HooksController.new` с `instance_variable_set(:@request_body, …)`, вызов через `send`:
  `{ "Type" => "Notification" }` → `true`, `{ "Type" => "SubscriptionConfirmation" }` → `false`, `{}` → `false`;
  `described_class.private_method_defined?(<имя>)` → `true` и `public_method_defined?(<имя>)` → `false` (для
  старого имени — на верхнем уровне, для нового — в `renamed`).
- `spec/models/app_package_external_alias_spec.rb` (`RSpec.describe AppPackage`): `AppPackage.new(name: "Slack")`
  → `false`; `name: "NoSuchPluginR7c"` → `true`; `name: "Slack", author: Agent.new` → `true`;
  `name: "NoSuchPluginR7c", plugin: Plugin.new` → `false`.
- `spec/models/conversation_part_predicates_alias_spec.rb` (`RSpec.describe ConversationPart`): `is_event_message?`
  — `messageable: ConversationPartEvent.new` → `true`, `ConversationPartContent.new` → `false`, без
  `messageable` → `false`; `is_from_auto_message_campaign?` — `message_source: UserAutoMessage.new` → `true`,
  `Campaign.new` → `false`, без источника → `false`.
- `spec/models/conversation_visible_comment_alias_spec.rb` (`RSpec.describe Conversation`):
  `latest_user_visible_comment_at: Time.zone.now` → `true`, `nil` → `false`.
- `spec/models/outgoing_webhook_enabled_alias_spec.rb` (`RSpec.describe OutgoingWebhook`): `state: "enabled"` →
  `true`, `"disabled"` → `false`, `nil` → `false`; плюс на старом имени `as_json["enabled"]` — `true` /
  `false` для первых двух.
- `spec/services/origin_validator_alias_spec.rb` (`RSpec.describe OriginValidator`): `host: "http://loc.cl:3002"`;
  `is_valid?` — `app: nil` → `true`, `"*"` → `true`, `"http://other.io, http://loc.cl:3002"` → `true`,
  `"http://loc.cl"` → `raise_error(OriginValidator::NonAcceptedOrigin)`; `validate_domain` —
  `"http://loc.cl:3002"` → `true`, `"http://loc.cl"` → `false`, `"https://loc.cl:3002"` → `false`.

```bash
git apply $P/r7c_rename.patch
git add spec/controllers/api/v1/hooks_notification_alias_spec.rb spec/models/app_package_external_alias_spec.rb spec/models/conversation_part_predicates_alias_spec.rb spec/models/conversation_visible_comment_alias_spec.rb spec/models/outgoing_webhook_enabled_alias_spec.rb spec/services/origin_validator_alias_spec.rb
git status --short        # ожидается: 6 строк "A  spec/…" и 6 строк " M app/…"/"M  app/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 6 files
git commit -qam "Rename is_/has_ predicates, keep old names"
```

**Шаг 2. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r7c_tests_gate.sh $B` (≈ 6 мин). Нужны три
строки: `R7C TREE PASS … examples`, `R7C BASE PASS … char / … renamed failing / 0 fix failing`,
`R7C MUTANTS PASS 25/25 killed`. Пример красный на дереве, пример на старом имени красный на BASE, пример
`renamed` зелёный на BASE или мутант выжил — поправь спеку (код, патч и мутантов не трогать; убийство — только
поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Rename is_/has_ predicates, keep old names$')
mkdir -p tmp/r7c-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r7c-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r7c-specs (tmp/ игнорируется)
# поправь спеки в tmp/r7c-specs/spec/…, затем: cp -r tmp/r7c-specs/spec/. spec/
# затем — команды шага 1, затем снова шаг 2
```

**Шаг 3. todo** — убрать блок `cops_whole` и строки `cops_partial` конфига:

```bash
python3 -I - r7c <<'PY'
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
git commit -am "Drop R7c entries from RuboCop todo"
```

**Шаг 4. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r7c

- Changed: predicate methods renamed for Naming/PredicatePrefix and Naming/PredicateMethod, each old
  name kept as an `alias` (callers, stubs and integrations keep working):
  `HooksController#is_notification_message?` -> `notification_message?` (private),
  `AppPackage#is_external?` -> `external?`, `ConversationPart#is_event_message?` -> `event_message?`,
  `ConversationPart#is_from_auto_message_campaign?` -> `from_auto_message_campaign?`,
  `Conversation#has_user_visible_comment?` -> `user_visible_comment?`, `OutgoingWebhook#is_enabled` ->
  `enabled?`, `OriginValidator#is_valid?` -> `valid?`, `OriginValidator#validate_domain` ->
  `validate_domain?`. Specs pin both names.
```

```bash
git commit -am "Note fork-updates-r7c in changelog"
```

**Шаг 5.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 6.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R7C … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме шести файлов кода (только патчем), шести новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- Вызывающих старых имён (в том числе `api_controller.rb`, `connection.rb`, `app_package_integration.rb`,
  `create_integration.rb`) и существующие спеки — не переводить на новые имена.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`.
- Прочие строки `Naming/PredicateMethod` (`app/graphql/types` — R7b; четыре файла — раздел 10) и блоки
  других копов.
- Никаких ручных правок кода, `# rubocop:` директив, `pending`/`skip`, `--auto-gen-config`, чтения исходников.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R7C_CACHE=$HOME/.cache/chaskiq-r7c-ci bash docs/specs/fork-updates-r7c-probes/rspec_gate_r7c.sh'`

- **AC-002** — пути и код: изменены ровно 6 файлов кода, 6 новых файлов спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с патчем; todo = BASE без блока PredicatePrefix и без двух строк PredicateMethod; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7c-probes/r7c_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 6 спек зелёные на коде дерева; на коде BASE примеры на старых именах зелёные, каждый пример renamed упал, в каждой спеке есть оба вида; ошибок вне примеров нет; каждый из 25 мутантов r7c_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7C_CACHE=$HOME/.cache/chaskiq-r7c-ci bash docs/specs/fork-updates-r7c-probes/r7c_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у PredicatePrefix 0 офенсов во всём дереве, у PredicateMethod 0 в двух файлах вехи; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R7C_CACHE=$HOME/.cache/chaskiq-r7c-ci bash docs/specs/fork-updates-r7c-probes/r7c_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r7c-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: коммит переименования меняет ровно 6 файлов кода = BASE + патч и добавляет ровно 6 спек; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r7c после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7c-probes/r7c_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root/Rails.application.root в app/lib/config/vendor/db (join, glob, слеш), File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода и disasm, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r7c-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патч и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "be11737287bc84bbb4bae187247be51982bdcef9b0c54caf09149754d995adb6  docs/specs/fork-updates-r7c-probes/examples_base.txt" "6c66945c162827cd0b7c97ee9199b1dc6debd5f0a15f196e8887f5ff4c4b8487  docs/specs/fork-updates-r7c-probes/pending_allowed.txt" "3daa05bb21af5cef476cc042ceb3f6fc5e0bdc8f9a5b4264c564b5141028d4dd  docs/specs/fork-updates-r7c-probes/r7c_backlog_probe.sh" "03168d7faba1000226ac2aefd8a2bb8be6ffda74f0d903f37a2922ccad215b41  docs/specs/fork-updates-r7c-probes/r7c_config.json" "532180fc427855aefeac6d0e6c916e8a09b64752220482b78757b925dfc374bf  docs/specs/fork-updates-r7c-probes/r7c_probe.py" "81796dddc38097e1108c0d36fc6a4e0dd96ebeef1a1b7a0f02b6794a1fa470cc  docs/specs/fork-updates-r7c-probes/r7c_rename.patch" "36eeacc5a15392b94afd3a9c4a9299dfa4e36e5c6af5bbf62f62248dde5e7b08  docs/specs/fork-updates-r7c-probes/r7c_sentinel.rb" "03fa791f397817a25de65f98ab42b669b43485e8f5c8f8a7d517045430521f9f  docs/specs/fork-updates-r7c-probes/r7c_tests.rb" "175cb063cd9a2b5951bc240ddc3a12b92283cf91ed43050017e43e34e195906b  docs/specs/fork-updates-r7c-probes/r7c_tests_gate.sh" "713ded4e1acefe7f3609bfab9dfd52cb726d8d7c9ff1c45db774ba966f6a496f  docs/specs/fork-updates-r7c-probes/rspec_gate_r7c.sh" "1d6ada2d3673c3967a5c5e29abf552bc1f39bad983fcca7fb886dee5768f4c08  docs/specs/fork-updates-r7c-probes/source_scan.py" "a88700524901c3390aaf1445c07ba0a8df09b17d7de0cd47900cf2a8e32cdb2f  docs/specs/fork-updates-r7c-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный
(`R7C paths without the change` / `is not BASE + r7c_rename.patch`); AC-003 красный (спек нет — `no examples
ran`, тексты мутантов не найдены); AC-004 красный (`… offenses left`); AC-006 красный (`missing commits`).

Пробный прогон автора (21.11.2026; свежий клон BASE 8e2ddd3d со спекой и пробниками одним коммитом поверх,
сборка по разделу 5 буквально, спеки — образцы постановщика; кэш — копия `chaskiq-fxb-ci`, путь кэша в
командах подменён на копию):
- чистый клон: AC-001 (1059 примеров, 0 failures, 30 pending), AC-005, AC-007, AC-008, AC-009 — rc=0; AC-002,
  AC-003, AC-004 (`Naming/PredicatePrefix: 7 offenses left`), AC-006 красные с сообщениями выше;
- после сборки: все 9 AC rc=0 — rspec 1077 примеров (18 новых), 0 failures, 30 pending; AC-003
  `R7C BASE PASS 9 char / 9 renamed failing / 0 fix failing`, `R7C MUTANTS PASS 25/25 killed` (≈ 1,5 мин);
  AC-004 бэклог без todo 1090 → 1081; AC-007 `SOURCE SCAN PASS 6 files`;
- порченые правки (все ловятся): из спеки `OriginValidator` убраны примеры с `"*"` → AC-003 (выжил C22);
  `Rails.root.join("app/models/conversation.rb").read` в спеке → AC-007; вызывающий `api_controller.rb`
  переведён на `valid?` → AC-002, AC-006.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила) **в усечённом виде: ревьюер один —
`agy`.** Codex запрещён до 2026-11-22 11:39Z (решение владельца), Qwen — та же модель, что исполнитель.
**`codex` и `qwen` не запускать ни в какой форме** (ни `review_run.sh … codex|qwen`, ни `ask-codex`, ни
`ask-qwen`). Порядок: коммит → REVIEW_SHA; `agy` на `<BASE_SHA>..REVIEW_SHA`; один заход исправлений →
FINAL_SHA; одна проверка `agy` на `REVIEW_SHA..FINAL_SHA` (если код после ревью менялся). Квитанции пишет
только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r7c.md --exclude "docs/specs/fork-updates-r7c-probes/**" --context "chaskiq fork-updates-r7c: RuboCop Naming/PredicatePrefix 7 и PredicateMethod 2 — восемь методов переименованы (is_notification_message? private, is_external?, is_event_message?, is_from_auto_message_campaign?, has_user_visible_comment?, is_enabled, is_valid?, validate_domain), старое имя — alias сразу после метода, вызывающие и стабы не меняются; 6 спек: старые имена зелёные на BASE, describe renamed красный на BASE; 25 мутантов; спеки не читают исходники как текст; только чтение"`

Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r7c.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r7c-probes/**

Контекст ревьюеру: вызывающий по новому имени, которого нет (JS, GraphQL, `send`/`public_send` со строкой,
`respond_to?`), подкласс, переопределяющий старое имя (алиас указывает на тело родителя), смена видимости,
спека, которая проверяет текст, а не поведение. Код править нельзя — замечание по месту решает постановщик
(раздел 9); спеки — можно, одним заходом.

**Второй квитанции не будет — это штатный блок ревью, не повод искать другого ревьюера.** В `report.json`:
`initial_receipts` — только квитанция agy, `handoff_status` — `"blocked"`; в `report-blocked.md` (untracked, в
корне клона) — строка `review: second reviewer unavailable (codex banned until 2026-11-22 11:39Z, qwen is the
executor model)`, итог ревью agy (находки и решения) и что все 9 критериев зелёные. Если agy упал или не
дал вердикта — один технический повтор, затем то же самое с пометкой `agy: <дословная ошибка>`.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` у
критерия — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r7c.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r7c.md --dry-run`; отказ только из-за одной квитанции ревью — ожидаем, запиши его
вывод в `report-blocked.md`; любой другой отказ формы — исправь `report.json`.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью agy и
`report.json` готовы, блок второго ревьюера записан в `report-blocked.md` (раздел 8); (б) сработал пункт
ниже — тогда остановись, запиши `report-blocked.md` (что сделал, какая команда, дословный вывод) и доложи,
НЕ обходя:
- патч не применяется (`git apply` отказал), скрипт todo упал на `stop: section 9` или после патча
  AC-004/AC-005 красные — дефект спеки;
- пример на старом имени не может быть зелёным на BASE, проверяя описанное в разделе 5 поведение, — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл вызывающего по новому имени, подкласс со своим старым именем или смену видимости — файл,
  строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, перевод вызывающих на новые имена, правка пробников, патча
и мутантов, `pending`/`skip`, чтение исходников в спеках, запуск Codex или Qwen как ревьюеров, глушить вывод и
коды возврата.

## 10. Стыки

- **R2b (qw2) и fix-cleanup-3 (qw2) — идут сейчас.** Общих файлов кода нет (R2b: `Gemfile`, `app.rb`,
  `oauth_utils.rb`, `open_ai/api.rb`, `twilio/api.rb`, `.rubocop.yml`; fix-cleanup-3: `lead.rb`). Общие —
  `.rubocop_todo.yml` (разные блоки, удаление скриптом) и `CHANGELOG.md`. Проверено на 8e2ddd3d: патчи
  применяются в любом порядке.
- **R7b** — общий только todo: обе вехи вынимают разные строки блока `Naming/PredicateMethod`; **R7d** — общий
  только todo (разные блоки). Блок, оставшийся без строк файлов, удаляет та веха, что вливается последней.
- **Кто вливается вторым, тому — перенос BASE и `--write-base`** (раздел 2, п. 2).
- Оставшиеся `Naming/PredicateMethod` — `segment_comparator.rb` (`compare`), `slack/api.rb`
  (`receive_oauth_code`), `zapier/api.rb` (`event_identifier_available?`), `plugins/tar_downloader.rb`
  (`download_plugin`) — отдельной вехой: у `receive_oauth_code` (интерфейс плагина, зовётся из
  `AppPackageIntegration`) и `download_plugin` есть побочные эффекты, имя с `?` вводит в заблуждение; нужно
  решение координатора (переименование по букве решения или `AllowedMethods` с причиной).
- Мутационный прогон по шести спекам этой вехи — у противоположного исполнителя (cx), после снятия запрета на
  Codex 2026-11-22 11:39Z.
