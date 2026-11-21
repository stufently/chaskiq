# fork-updates-r3b3 — бэклог RuboCop, шаг 3b-3: Rails/StrongParametersExpect — три места с тестами

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-20. Спека — `docs/specs/fork-updates-r3b3.md`, план всей чистки —
  `docs/specs/fork-updates-rubocop-plan.md` (раздел «Решения владельца 2026-11-20, вторая партия»:
  «G1 → R3b-3: `StrongParametersExpect` — перевести все три с тестами; в `package_iframe_behavior.rb:71`
  вручную `params.expect(user: [:id])[:id]` (400 вместо 500/404 — запись Changed в CHANGELOG)»).
- BASE_SHA: `2b291654941220eb7aae23e4351703df23e77dd2` — HEAD `main` после влития R3b-2, fix-cleanup-bugs,
  fix-cleanup-2 и mut-r5b2 (Ruby 4.0.10, RuboCop 1.92.3, rubocop-rails 2.38.0, Rails 8.1.4.1).
- BASE перенесён 2026-11-21 с e0b470d0 после влития R3b-2 (раздел 2): постановщик коммитит это значение в
  строку BASE_SHA и только потом снимает клон. Команды критериев считают `B=$(git merge-base HEAD @{u})`
  сами. В `report.json` поле `base_sha` равно значению строки BASE_SHA. Коммиты исполнителя в
  `docs/specs` запрещены (AC-008).
- **Ревью — от BASE_SHA шапки, не от `B`** (`review_run.sh --base`, `--range`). Дифф вехи ≈ 9 КБ.
- Исполнитель: **Qwen Code (`qw2`)**. Спека написана для буквального исполнения: делай ровно
  шаги раздела 5, ровно этими командами, по одному. **Не останавливайся, пока все девять критериев
  раздела 7 не зелёные — или пока не сработал пункт раздела 9.**
- Цель: в дереве не остаётся `Rails/StrongParametersExpect` (3 офенса, 3 файла), его блок уходит из
  todo. Два места — параметры пути, правка нейтральна; третье меняет ответ на кривой запрос (400) —
  это решение владельца, запись `Changed` в CHANGELOG. Код задан патчами постановщика (руками не
  править). Работа исполнителя — четыре НОВЫЕ спеки: три характеризационные (зелёные на BASE и после) и
  одна спека 400 (красная на BASE, зелёная после); каждый из 10 мутантов постановщика (`r3b3_config.json`,
  `mutants`) роняет пример.

### Правило: тест проверяет поведение, а не текст кода (обязательно)

**Чтение исходников `app/`, `lib/`, `config/` как текста запрещено и убийством мутанта не считается**:
`Rails.root.join("app/...").read`, `File.read`/`IO.read`/`readlines` путей кода, `Dir.glob` по ним,
`method(...).source_location`, `.source`, парсеры (`Ripper`, `Prism`, `RubyVM::AbstractSyntaxTree`),
`` `cat`/`grep` `` в шелле — и затем `expect(source).to match(...)`. Мутант убит, только если код с
мутантом **ведёт себя** иначе: другой статус ответа, другое тело, другая запись, исключение. AC-007
(`source_scan.py`) ищет эти приёмы в новых и изменённых файлах `spec/` и валит критерий на любом
совпадении; ревьюеры смотрят и остальное.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-r3b3`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; на хост ничего не
  ставить. Образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` (собирает `bin/ci-local`). Свой кэш гемов:
  `$HOME/.cache/chaskiq-r3b3-ci`. Перед любым `docker run` с `-v …:/app/vendor/bundle` —
  `mkdir -p vendor/bundle` (пробники это делают сами).

Что делает постановщик ДО запуска (на `main`; клон снимается ПОСЛЕДНИМ):

1. Кэш: `$HOME/.cache/chaskiq-r3b3-ci` (уже создан, копия `chaskiq-r3b2-ci`); если нет —
   `cp -a $HOME/.cache/chaskiq-r3b2-ci $HOME/.cache/chaskiq-r3b3-ci`.
2. Дождаться влития **R3b-2** (её AC-008 требует, чтобы три файла этой вехи и блок
   `Rails/StrongParametersExpect` в todo были нетронуты, — раздел 10) и перенести BASE. На новом BASE:
   `git apply --check` двух патчей по порядку; тексты 10 мутантов — каждый ровно один раз в своём файле
   дерева после патчей; имена четырёх новых спек не заняты. Перегенерировать снимки
   `CHASKIQ_R3B3_CACHE=$HOME/.cache/chaskiq-r3b3-ci bash docs/specs/fork-updates-r3b3-probes/rspec_gate_r3b3.sh --write-base`
   на чистом checkout `main`, пересчитать sha256 в AC-008. Сейчас в снимках — список примеров 2b291654
   (перенос сделан 2026-11-21).
3. Закоммитить в `main` одним коммитом: спеку, пробники, патчи, снимки, их sha256 в AC-008 и строку
   BASE_SHA. Только после этого — `make_clone.sh`.

## 3. Места, поведение и почему

Строки — по BASE 2b291654 (три файла кода с e0b470d0 изменились только вне правок: `cookie_namespace`
в `application_controller.rb`).

**`r3b3_path.patch` — два параметра пути, вывод `rubocop -A --only Rails/StrongParametersExpect`.**
- `app/controllers/api/v1/hooks/provider_controller.rb:22` (`global_process_event`, маршруты
  `POST|GET /api/v1/hooks/global/:provider`): `params["provider"]` → `params.expect("provider")`.
- `app/controllers/application_controller.rb:14` (`preview`, маршрут `GET /apps/:app/premailer/:id/`):
  `params[:id]` → `params.expect(:id)`.
Нейтрально: параметр пути всегда есть и всегда строка (иначе маршрут не совпал бы), а параметры пути в
`params` перекрывают одноимённые из тела и query — `expect` возвращает ту же строку. `ParameterMissing`
невозможен: пустой сегмент пути маршрут не принимает.

**`r3b3_iframe.patch` — `app/controllers/concerns/package_iframe_behavior.rb:71`
(`package_iframe_internal`, `POST /package_iframe_internal/:package`), правка руками.** Было
`AppUser.find(params[:user]["id"]).app`, стало `AppUser.find(params.expect(user: [:id])[:id]).app`.
**Автокоррекция RuboCop здесь неверна**: она пишет `params.expect(:user)`, а `expect(:user)` разрешает
только скаляр — рабочий запрос с хешем `user` получил бы `ParameterMissing`. Поведение:
- `user` — хеш с `id` (рабочий путь): то же; `opts[:user]` для презентера по-прежнему весь
  `params[:user]` (строка 81 не меняется — мутант M09 это закрепляет);
- `user` нет: было `NoMethodError` (`nil["id"]`, 500) → стало `ActionController::ParameterMissing` — 400;
- `user` — строка: было `"abc"["id"]` → `nil` → `RecordNotFound` (404) → стало 400;
- `user` — хеш без `id`: было `find(nil)` → 404 → стало 400.
Единственный вызывающий в коде — `package_iframe`/`iframe_package_request` того же concern
(строки 37, 129-131): `Faraday.post` JSON с `user: app_user` — запись `AppUser` (хеш с `id`) или `nil`,
когда пользователь не найден; во втором случае было 500, станет 400. Это запись `Changed` в CHANGELOG
(решение владельца).

`ParameterMissing` → 400 и `RecordNotFound` → 404 дают `ActionDispatch::ExceptionWrapper.rescue_responses`;
в тестовой среде `config.action_dispatch.show_exceptions = false`, поэтому спека 400 на время примера
ставит `Rails.application.env_config["action_dispatch.show_exceptions"] = :rescuable` и восстанавливает
его (`around`, `ensure`) — так ответ проходит тот же путь, что в production.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-20 в Docker (`chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04`, кэш `chaskiq-r3b3-ci`) на
клоне BASE e0b470d0; после переноса повторено 2026-11-21 на BASE 2b291654 (раздел 7, пробный прогон):

1. Rubocop без блока todo на BASE: у копа 3 офенса в трёх файлах раздела 3. После двух патчей —
   0 офенсов во всём `app/`, `lib/`; на рукописной форме `params.expect(user: [:id])[:id]` коп молчит.
2. Образцы четырёх спек постановщика: 8 примеров зелёные на дереве; на BASE три характеризационные
   зелёные, в спеке 400 красные все три примера по нужной причине (`NoMethodError '[]' for nil`,
   `expected: 400 got: 404` дважды).
3. 10/10 мутантов убиты поведением: статус (`expected: 200 got: 500`, `expected: 400 got: 404`), тело
   ответа, отсутствие исключения `RecordNotFound`, значения, переданные презентеру и `process_global_hook`.
4. Черновик ровно по разделу 5: итоги — раздел 7.

Предположение: настоящих интеграций `Calendly`/`Slack` спеки не вызывают — презентер и
`process_global_hook` заглушены, проверяется контроллер (какое приложение, какой пакет, какие параметры).

## 5. Что сделать — по шагам, ровно этими командами

Все команды — из корня клона, в `bash`. Коммиты — ≤ 50 символов, без Co-Authored-By и подписей,
ровно в этом порядке. Код — **только** `git apply` патчей. В каждой спеке
`# frozen_string_literal: true`, `require "rails_helper"`; никаких `pending`/`skip`/`xit`, `# rubocop:`
директив, чтения исходников (раздел 1). **В request-спеках не называй `let(:app)`** — `app` там —
Rack-приложение теста; модель — `let(:chat_app)`. Пакеты и интеграции —
`AppPackage.new(name:).tap { |p| p.save!(validate: false) }`,
`AppPackageIntegration.new(app:, app_package:).save!(validate: false)`. Перед шагом 1:

```bash
P=docs/specs/fork-updates-r3b3-probes
export CHASKIQ_R3B3_CACHE=$HOME/.cache/chaskiq-r3b3-ci
```

**Шаг 1. Характеризационные спеки** — 3 НОВЫХ файла, код = BASE:
- `spec/requests/global_hook_provider_spec.rb` (`type: :request`): пакет `"Slack"`;
  `allow_any_instance_of(AppPackage).to receive(:process_global_hook)` с блоком, который запоминает
  `[pkg.id, params["provider"]]` и возвращает `"pong"`.
  `post "/api/v1/hooks/global/slack", params: { provider: "other", foo: "bar" }` → статус 200, тело
  ровно `"pong"`, запомнено ровно `[[package.id, "slack"]]` (путь важнее тела); `get` того же адреса без
  параметров → тело `"pong"`, то же запомненное.
- `spec/controllers/premailer_preview_spec.rb` (`RSpec.describe ApplicationController, type: :controller`):
  кампании — `FactoryBot.create(:campaign, app:)`. `get :preview, params: { app: app.key, id: campaign.id }`
  → статус 200 и `controller.instance_variable_get(:@campaign) == campaign`; кампания ДРУГОГО приложения
  с ключом своего → `raise_error(ActiveRecord::RecordNotFound)`.
- `spec/requests/package_iframe_internal_spec.rb` (`type: :request`): приложение `chat_app`, пользователь
  `chat_app.add_user(email:)`, пакет `"Calendly"` и его интеграция в `chat_app`; презентер —
  объект с `sheet_view(opts)`, который запоминает `opts` и возвращает `"<p>sheet</p>"`, через
  `allow_any_instance_of(AppPackageIntegration).to receive(:presenter).and_return(presenter)`.
  `post "/package_iframe_internal/Calendly", params: { user: { id: user.id, name: "Ann" }, data: { field: "f" } }`
  → 200, тело ровно `"<p>sheet</p>"`, вызов один, `opts[:app_key] == chat_app.key`,
  `opts[:user]["name"] == "Ann"`, `opts[:field] == "f"`.

```bash
git add spec/requests/global_hook_provider_spec.rb spec/controllers/premailer_preview_spec.rb spec/requests/package_iframe_internal_spec.rb
git status --short        # ожидается: ровно 3 строки "A  spec/…"
python3 -I $P/source_scan.py $(git merge-base HEAD @{u})   # ожидается: SOURCE SCAN PASS 3 files
git commit -m "Add R3b-3 characterization specs"
```

**Шаг 2. Параметры пути:**

```bash
git apply $P/r3b3_path.patch && git commit -qam "Use params.expect for path params"
```

**Шаг 3. Пользователь iframe и спека 400** `spec/requests/package_iframe_internal_params_spec.rb`
(`type: :request`; `around` с `:rescuable`, раздел 3): `post "/package_iframe_internal/Calendly"` —
без `user` (`params: { data: { field: "f" } }`), с `user: "abc"`, с `user: { name: "Ann" }` → в каждом
случае статус ровно 400.

```bash
git apply $P/r3b3_iframe.patch
git add spec/requests/package_iframe_internal_params_spec.rb
git commit -qam "Require user id in package iframe"
```

**Шаг 4. Тесты.** `B=$(git merge-base HEAD @{u}); bash $P/r3b3_tests_gate.sh $B` (≈ 3 мин). Нужны три
строки: `R3B3 TREE PASS … examples`, `R3B3 BASE PASS … char / 1 fix failing`,
`R3B3 MUTANTS PASS 10/10 killed`. Пример красный на дереве, характеризационный — на BASE, спека 400 зелёная
на BASE или мутант выжил — поправь спеку (код, патчи и мутантов не трогать; убийство — только
поведением), не добавляя новых коммитов:

```bash
C1=$(git log --format=%H -1 --grep '^Add R3b-3 characterization specs$')
mkdir -p tmp/r3b3-specs && git diff --name-only --diff-filter=A "$C1~1" HEAD -- spec | xargs cp --parents -t tmp/r3b3-specs
git reset --hard "$C1~1"    # код = BASE, коммитов вехи нет; копии спек — в tmp/r3b3-specs (tmp/ игнорируется)
# поправь спеки в tmp/r3b3-specs/spec/…, затем: cp -r tmp/r3b3-specs/spec/. spec/
# затем — команды шагов 1–3, затем снова шаг 4
```

**Шаг 5. todo** — убрать блок `Rails/StrongParametersExpect` (`cops_whole` конфига):

```bash
python3 -I - <<'EOF'
import json, re
cfg = json.load(open("docs/specs/fork-updates-r3b3-probes/r3b3_config.json"))
has = lambda b, cs: any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in cs)
head, *blocks = open(".rubocop_todo.yml").read().rstrip("\n").split("\n\n")
out = [b for b in blocks if not has(b, cfg["cops_whole"])]
assert len(out) == len(blocks) - len(cfg["cops_whole"]), "stop: section 9"
open(".rubocop_todo.yml", "w").write("\n\n".join([head] + out) + "\n")
EOF
git diff --stat            # ожидается: только .rubocop_todo.yml
git commit -am "Drop R3b-3 entries from RuboCop todo"
```

**Шаг 6. CHANGELOG** — вставь сразу после первой строки `# Changelog` этот блок (с пустой строкой до
и после), текст ниже не трогай:

```
## 2026-11-21 — fork-updates-r3b3

- Changed: `POST /package_iframe_internal/:package` reads the user id with
  `params.expect(user: [:id])` and answers 400 when `user` is missing, not a hash or has no `id`
  (was 500 for a missing `user` and 404 otherwise).
- Changed: Rails/StrongParametersExpect cleaned up: the two path parameters (`provider` of the global
  hooks, `id` of the campaign preview) are read with `params.expect` without behaviour changes;
  specs added for all three sites.
```

```bash
git commit -am "Note fork-updates-r3b3 in changelog"
```

**Шаг 7.** Все девять критериев раздела 7 (каждая команда — как написана); красный — раздел 9.
**Шаг 8.** Ревью и `report.json` — раздел 8. В `note`: AC-002 — строка `paths: …`; AC-003 — три строки
`R3B3 … PASS`; AC-004 — строка `backlog without todo: …`; AC-007 — строка `SOURCE SCAN PASS …`.

## 6. Не трогать

- Всё, кроме трёх файлов кода (только патчами), четырёх новых спек, `.rubocop_todo.yml`, `CHANGELOG.md`.
- `.rubocop.yml`, гемы, `Gemfile*`, `.ruby-version`, `Dockerfile*`, workflows, `bin/*`, `db/`, `config/`
  (в том числе `show_exceptions` тестовой среды — только на время примера в спеке).
- Никаких ручных правок кода и существующих спек, `# rubocop:` директив, `pending`/`skip`,
  `--auto-gen-config`, чтения исходников в спеках; автокоррекцию `params.expect(:user)` не применять.
- `docs/specs/**` — не править (AC-008, sha256).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec через bin/ci-local строго зелёный: SPEC_OPTS не задан, .rspec-local нет, rspec читает только .rspec, тела примеров выполнены (сторож); rspec завершился 0, 0 failures, 0 ошибок вне примеров, выполнены все примеры BASE (новые — сверх), pending только из списка BASE, нет warning-строк, которых не было на BASE.
  `bash -c 'CHASKIQ_R3B3_CACHE=$HOME/.cache/chaskiq-r3b3-ci bash docs/specs/fork-updates-r3b3-probes/rspec_gate_r3b3.sh'`

- **AC-002** — пути и код: изменены ровно 3 файла кода, 4 новых файла спек (новые обычные файлы), todo и CHANGELOG — каждый; нет неотслеживаемых и игнорируемых .rspec*/файлов под app/lib/config/spec; каждый файл кода побайтно равен BASE с двумя патчами по порядку (в package_iframe_behavior.rb — рукописная форма с user: [:id], не автокоррекция expect(:user)); todo = BASE без блока Rails/StrongParametersExpect; .rubocop.yml не тронут; ни одной добавленной rubocop-директивы.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b3-probes/r3b3_probe.py tree $B'`

- **AC-003** — тесты на копии HEAD: все примеры 4 файлов зелёные на коде дерева; на коде BASE 3 характеризационные спеки зелёные, в спеке 400 есть упавший пример; ошибок вне примеров нет; каждый из 10 мутантов r3b3_config.json (текст найден ровно один раз) роняет пример своей спеки, не ошибку загрузки.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B3_CACHE=$HOME/.cache/chaskiq-r3b3-ci bash docs/specs/fork-updates-r3b3-probes/r3b3_tests_gate.sh $B'`

- **AC-004** — бэклог без todo: RuboCop проверил ровно свои целевые файлы без внутренних ошибок; у Rails/StrongParametersExpect 0 офенсов во всём дереве; ни у одного другого копа ни в одном файле (новые спеки тоже) офенсов не больше, чем на BASE; общий счёт уменьшился.
  `bash -c 'B=$(git merge-base HEAD @{u}) && CHASKIQ_R3B3_CACHE=$HOME/.cache/chaskiq-r3b3-ci bash docs/specs/fork-updates-r3b3-probes/r3b3_backlog_probe.sh $B'`

- **AC-005** — строгий RuboCop как в CI (rubocop-analysis.yml): все отслеживаемые файлы, оставшийся todo, ноль офенсов.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r3b3-ci bin/ci-local --only rubocop'`

- **AC-006** — каждый коммит отдельно, ровно в порядке раздела 5: характеризационный добавляет ровно 3 спеки при коде BASE; коммит патча путей меняет только два файла путей и ничего не добавляет; коммит iframe меняет только package_iframe_behavior.rb и добавляет ровно спеку 400; коммит todo — только todo, равный ожидаемому; коммит CHANGELOG и последующие — только CHANGELOG, равный BASE с одним блоком про fork-updates-r3b3 после «# Changelog»; ни один коммит не меняет git-режим, не удаляет путь и не добавляет rubocop-директиву.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b3-probes/r3b3_probe.py commits $B'`

- **AC-007** — ни одна новая или изменённая строка spec/ не читает исходники как текст: нет путей Rails.root в app/lib/config/vendor/db, File/IO/Pathname-чтения таких путей или файла рядом с __FILE__/__dir__, Dir.glob по ним, source_location, method(...).source, парсеров кода, шелла cat/grep/git show.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r3b3-probes/source_scan.py $B'`

- **AC-008** — коммитов в docs/specs нет, пробники, патчи и снимки постановщика не тронуты (sha256), спека не тронута.
  `bash -c 'B=$(git merge-base HEAD @{u}) && L=$(git log --format=%H $B..HEAD -- docs/specs) && test -z "$L" && printf "%s\n" "7275e574de65f72ba9d8d2bc676665580e6dad53b24ff0abcdef155ee05b1009  docs/specs/fork-updates-r3b3-probes/r3b3_probe.py" "885b44e1ea29292dea57704a2ebc974e0539b8b48b119f6d21564c8ea22ece57  docs/specs/fork-updates-r3b3-probes/r3b3_config.json" "069240cf7b3abcaa858e80b83e4f525d2f56cfd1dbfdabf975f8bb7167faf99a  docs/specs/fork-updates-r3b3-probes/r3b3_tests.rb" "788c913831a0aecacddc3866d7858be14f041c82c2defe5f0a0ee059c4112e6b  docs/specs/fork-updates-r3b3-probes/r3b3_tests_gate.sh" "894e568e34e5544cf9f3588ab1a7c46ef7d651625eb0db4410beb66f0080b232  docs/specs/fork-updates-r3b3-probes/r3b3_backlog_probe.sh" "2d10921c04e8f189eeaa95d19a91dc5fb838a07847485db44330e14218219d23  docs/specs/fork-updates-r3b3-probes/source_scan.py" "d56bb9d374354c4498e86ef309825142e89f87ace68527a4212bfc2384817a2a  docs/specs/fork-updates-r3b3-probes/r3b3_path.patch" "2abb051805c9c33bc963144881d14cd3425f4f30e5aee0dfbae477972ab77b05  docs/specs/fork-updates-r3b3-probes/r3b3_iframe.patch" "0246c9e4317381ae6a152db2b35672a80ff7fd41cb6a0667aa7e178a2df2eaa3  docs/specs/fork-updates-r3b3-probes/rspec_gate_r3b3.sh" "334089a75686267d0ab86be410d520fe4ea10b91eab8ef3fc955078c53d199c8  docs/specs/fork-updates-r3b3-probes/r3b3_sentinel.rb" "d7188ace00400a12a5b3ff11cfa30e138d9a67539e2a6709b9c6db20117653c1  docs/specs/fork-updates-r3b3-probes/examples_base.txt" "b5eaf4806a7efc6e92afa8f3a6e12f21cf85feaa62efae9b53404142c3426c33  docs/specs/fork-updates-r3b3-probes/pending_allowed.txt" "afe830dae96a9da4c312e3e048b1f7bf48d859d6ed312d02f9b0ede85f2b3620  docs/specs/fork-updates-r3b3-probes/warnings_base.txt" | sha256sum -c --quiet - && git diff --quiet $B HEAD -- docs/specs'`

- **AC-009** — дерево чистое (сбой git — тоже FAIL), нет игнорируемых, но существующих .rspec-local, .rspec-parallel и файлов под app/, lib/, config/, spec/.
  `bash -c 'git status --porcelain >/dev/null && test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")" && I=$(git status --porcelain --ignored=matching -- .rspec-local .rspec-parallel app lib config spec) && test -z "$I"'`

Ожидаемо на чистом клоне: AC-001, AC-005, AC-007, AC-008, AC-009 зелёные; AC-002 красный (`… is not
BASE + r3b3_path.patch, r3b3_iframe.patch`); AC-003 красный (спек нет — `no examples ran`); AC-004 красный
(`Rails/StrongParametersExpect: 3 offenses left`); AC-006 красный (`missing commits`).

Пробный прогон после переноса BASE (21.11.2026, свежий клон `main` 2b291654 + коммит спеки и пробников
сверху, сборка по разделу 5 буквально, спеки — образцы постановщика):
- чистый клон: AC-001 (rspec 1026 examples, 0 failures, 30 pending, сторож 998), AC-005, AC-007
  (`SOURCE SCAN PASS 0 files`), AC-008, AC-009 зелёные; AC-002, AC-003 (`no examples ran`), AC-004
  (`3 offenses left`, BASE 1093), AC-006 (`missing commits`) красные с сообщениями выше;
- после сборки: все 9 AC зелёные — rspec 1034 examples (8 новых), 0 failures, 30 pending, сторож 1006;
  AC-003 `R3B3 TREE PASS 8 examples`, `R3B3 BASE PASS 5 char / 1 fix failing`, `R3B3 MUTANTS PASS 10/10 killed`;
  AC-004 backlog без todo BASE 1093 → 1090; AC-007 `SOURCE SCAN PASS 4 files`; файлов от root нет;
- порченые правки (все ловятся): `Rails.root.join("app/…/package_iframe_behavior.rb").read` в спеке → AC-007;
  автокоррекция `params.expect(:user)` вместо рукописной формы → AC-002; откат коммита todo → AC-002 и
  AC-006; спека 400 с `be >= 400` вместо `eq(400)` → AC-003, выжил M10 (404 без исключения).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `codex` параллельно на `<BASE_SHA>..REVIEW_SHA` (исполнитель — Qwen,
поэтому второй ревьюер — Codex); один заход исправлений → FINAL_SHA; одна проверка
`REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-r3b3.md --exclude "docs/specs/fork-updates-r3b3-probes/**" --context "chaskiq fork-updates-r3b3: Rails/StrongParametersExpect — два параметра пути (provider глобальных хуков, id превью кампании) через params.expect нейтрально, package_iframe_internal — params.expect(user: [:id])[:id] руками (400 вместо 500/404, решение владельца; автокоррекция expect(:user) неверна); 3 характеризационные спеки и спека 400, красная на BASE; 10 мутантов; спеки не читают исходники как текст; только чтение"`

(то же для `codex`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-r3b3.md
REVIEW_EXCLUDE: docs/specs/fork-updates-r3b3-probes/**

Контекст ревьюерам: найти клиента `package_iframe_internal`, который шлёт `user` не хешем или без `id`
и сломается на 400 (`messenger`, пакеты в `app/javascript`); путь, где параметр пути может отсутствовать
или быть не строкой; спеку, которая проверяет текст, а не ответ. Код править нельзя — замечание по месту
решает постановщик (раздел 9); спеки — можно, одним заходом.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-r3b3.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-r3b3.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Работа заканчивается в одном из двух состояний: (а) все девять критериев зелёные, ревью и
`report.json` готовы; (б) сработал пункт ниже — тогда остановись, запиши `report-blocked.md`
(что сделал, какая команда, дословный вывод) и доложи, НЕ обходя:
- патч не применяется (`git apply` отказал) или после патчей AC-004/AC-005 красные — дефект спеки;
- характеризационный пример не может быть зелёным на BASE или пример 400 не может быть красным на BASE,
  проверяя описанное в разделе 5 поведение — приложи вывод;
- мутант не убивается спекой, проверяющей поведение (эквивалентен) — id и почему; читать исходник,
  чтобы «убить» его, запрещено (раздел 1);
- сьют красный, а причина не в дереве (флап, среда) — приложи два прогона;
- ревьюер нашёл клиента, которого ломает 400, или путь без параметра пути — файл, строка, довод;
- пробник противоречит спеке или коду BASE (дефект спеки); образ, кэш или сервисы недоступны.
Запрещено: ручные правки кода и существующих спек, правка пробников, патчей и мутантов,
`pending`/`skip`, чтение исходников в спеках, глушить вывод и коды возврата.

## 10. Стыки

- **R3b-2 — влита до этой вехи** (merge `6541ba93`, принята `2b291654` = BASE). Её AC-008 требовал, чтобы
  `provider_controller.rb`, `application_controller.rb`, `package_iframe_behavior.rb` и блок
  `Rails/StrongParametersExpect:` в todo остались нетронутыми, — они на месте. Общих файлов кода с R3b-2
  нет; обе правят `.rubocop_todo.yml` (разные блоки) и CHANGELOG — пробник todo считает ожидаемое от BASE,
  поэтому BASE перенесён после R3b-2.
- **R5b-2, R6c, fix-cleanup-bugs** — общих файлов нет.
- После R3b-2 и этой вехи из Rails-копов в todo не остаётся ни одного.
