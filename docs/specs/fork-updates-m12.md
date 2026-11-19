# fork-updates-m12 — сторонние деприкейшены и предупреждения при загрузке и в тестах

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m12.md`.
- BASE_SHA: `bec90cb89308f37c2dd63bee4acfd34657519dae` — `main` с влитыми m1–m8 и ci-parity (Rails 8.1.4.1, load_defaults 8.1, Ruby 3.3.14).
- BASE плавающий: если до запуска `main` уйдёт вперёд (например, влиты вехи m9–m11), постановщик
  коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды критериев
  считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно значению
  строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-010).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Мутации по новым тестам потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: ни загрузка (4 среды, `RUBYOPT=-W:deprecated`), ни полный rspec не печатают ни одного
  деприкейшена или предупреждения; мёртвый git-гем nightfury убран, его код живёт в `lib/`
  без `Redis.current`; данные метрик живых установок читаются как прежде.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m12`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker | ruby 3.3.14 (bookworm), libpq, libvips 8.14, node 18, ts-node |
| гемы | `$HOME/.cache/chaskiq-m6/bundle` | гейт и пробники; веха только УДАЛЯЕТ гем, новый кэш не нужен |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках, сборка фронта на стенде |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4/m12 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m12-probes
bash $P/rspec_gate_m12.sh                     # полный строгий rspec + ноль деприкейшенов, ~6 мин
bash $P/rspec_gate_m12.sh --only <spec-файл>  # один файл
bash $P/m12_boot_probe.sh                     # 4 среды, RUBYOPT=-W:deprecated, ни одной warning-строки
bash $P/m12_compat_probe.sh                   # BASE пишет метрики nightfury, дерево читает и наоборот (~2 мин)
python3 -I $P/m12_mutation_gate.py [NF1 ...]  # мутанты по новым тестам (~3 мин)
```

## 3. Задача и почему

Rails и Ruby-уровень чистые, но сторонний шум остался. Полный список — из прогона BASE в Docker
(полный rspec с `RUBYOPT=-W:deprecated` и загрузка production/test/development):

| # | Что печатается | Откуда | Решение |
|---|---|---|---|
| D1 | `` `Redis.current` is deprecated and will be removed in 5.0 `` — во всех средах | гем `nightfury` из git `michelson/nightfury` (`lib/nightfury.rb:18`), вызов из `config/initializers/nightfury.rb` | **вендорить** в `vendor/nightfury/` (раздел 5 A; `vendor/**` вне rubocop по умолчанию — чужой код не переписываем под стиль): репозиторий жив по `git ls-remote`, но последний push 2019-12-20, это форк SupportBee/nightfury; gemspec держит `redis ~> 4.0` и блокирует redis 5; rubygems-версия 1.0.1 от 2013 года. Path-гем не годится: продовый `Dockerfile` копирует только `Gemfile`/`Gemfile.lock` до `bundle install` |
| D2 | тот же `Redis.current` в рантайме (на загрузке не виден) | `lib/rack/health_check.rb:23`, `app/jobs/offline_checker_job.rb:5`, `app/services/message_apis/twilio_phone/store.rb:30`, `cy.appEval('Redis.current…')` в `spec/cypress/integration/messenger/{task_bot,tours}_spec.js`, комментарии `config/initializers/redis.rb` | **править в приложении** (раздел 5 B), адрес Redis — тот же, что у BASE |
| D3 | `cypress_folder= is deprecated, please use install_folder` (test, development) | `config/initializers/cypress_on_rails.rb:5`; ещё два деприкейшена гема в рантайме: `cypress_helper.rb is deprecated` и `/__cypress__/command is deprecated`; cypress-on-rails 1.20.1 — последняя на rubygems | **править в приложении** (раздел 5 C): `install_folder`, `e2e_helper.rb`, `/__e2e__/command` |
| D4 | `URLcrypt.key=` | уже заменён в `config/application.rb:83-90` (ENV `urlcrypt_key`) | проверено: в 4 средах предупреждения нет; пробник загрузки сторожит (`UC=true`) |
| D5 | `Using any_instance from rspec-mocks' old :should syntax … graphql_controller_spec.rb:145` | 110 строк в 23 файлах `spec/` (`.stub`, `X.any_instance.stub`, один `should_receive`) | **перевести на expect-синтаксис** и запретить старый: `mocks.syntax = :expect` |
| D6 | `WARNING: Using the raise_error matcher without providing a specific error …` | `spec/models/app_user_spec.rb:186` | **уточнить ожидание**: `raise_exception(RuntimeError, "contact origin is not a Lead")` |
| D7 | `rubocop-rails extension supports plugin, specify plugins: rubocop-rails instead of require:` | `.rubocop.yml` | **править конфиг**: `require:` → `plugins:` |

Ruby-деприкейшенов (`-W:deprecated`) на 3.3.14 нет — ни при загрузке, ни в сьюте.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker на клоне BASE и на черновике (только для проверки достижимости,
в веху не идёт):

1. BASE: полный rspec 528 примеров / 0 failures / 30 pending (pending — тот же список, что в m8);
   гейт m12 на BASE красный ровно по D1, D3, D5, D6; `m12_boot_probe.sh` красный по D1.
2. Черновик (D1–D7 по разделу 5): гейт m12 зелёный (528/0/30, ноль warning-строк),
   `m12_boot_probe.sh` зелёный во всех 4 средах (`NF=nf-<env> UC=true`), `m12_compat_probe.sh`
   зелёный (18 проверок), `m12_mutation_gate.py` — 10/10 убиты, `m12_integrity_probe.py` зелёный.
   После `bundle lock` в `Gemfile.lock` исчезли только блок GIT nightfury и строка `nightfury!`
   (11 строк), версии остальных гемов не сдвинулись.
3. Ловушка пространства имён: `Nightfury.namespace = "nf-…"` при уже заданном `Nightfury.redis`
   вкладывает один `Redis::Namespace` в другой, и ключи уезжают в `nf:nf-production:…` —
   дашборды живых установок обнуляются. Сьют этого НЕ видит (на черновике был зелёным); ловит
   только `m12_compat_probe.sh` (на таком черновике 6 FAILED) и мутант NF2. Поэтому строка
   `Nightfury.redis.namespace = "nf-#{Rails.env}"` остаётся дословно как в BASE.
4. Найденный дефект nightfury: при `Redis.exists_returns_integer = true`
   (`config/initializers/redis.rb`) `redis.exists(key)` возвращает Integer, `0` в Ruby истинен,
   поэтому мета-запись серии (score 0) не создаётся НИКОГДА, а `TimeSeries#get_all` берёт
   `zrange(key, 1, -1)` и теряет самую старую точку каждой серии (дашборд
   `app/services/dashboard.rb:31` без первого дня). Чтение по score (`"(0"`..`"+inf"`) НЕ
   годится: `TimeSeries#set` принимает любое время, точки с score ≤ 0 (эпоха и раньше) потерялись
   бы. В черновике `get_all` берёт `zrange(key, 0, -1)` и выкидывает мету по содержимому: мета —
   JSON-объект (`default_meta.to_json`, начинается с `{`), точка — `"<timestamp>:<value>"`. Вызовы
   `redis.exists` НЕ меняются: `exists?` начал бы создавать мету при каждом чтении (изменение
   записи, вне вехи).
5. `rubocop` на BASE: 0 офенсов. Вендоринг в `lib/` дал 23 офенса в коде гема
   (Style/Documentation, Lint/DuplicateMethods, Metrics/*); в `vendor/nightfury/` RuboCop его не
   смотрит (дефолтный `Exclude: vendor/**/*`, `.rubocop.yml` его не отменяет) — на черновике
   `rubocop` по всему дереву: 0 офенсов, 496 файлов.
6. `m4_tree_probe.py` на черновике зелёный (git-источник nightfury уходит из lock).
7. Адреса Redis BASE (проверено в Docker, `REDIS_URL=redis://…/3`): `Redis.current` — это
   `Redis.new` без аргументов, то есть ТОЛЬКО `ENV["REDIS_URL"]`, иначе `redis://127.0.0.1:6379/0`;
   credentials (`Chaskiq::Config`) он не читает. Kredis (`config/redis/shared.yml`) берёт
   `Chaskiq::Config.fetch("REDIS_URL", …)`; записи `staging:` нет, и в staging BASE падает на
   первом `Kredis.hash` (`undefined method 'key?' for nil`). `Kredis.namespace=` поддерживается
   (thread-local префикс `<ns>:`), BASE в `get_values` его игнорирует — читает мимо записанного.
8. Офлайн-чекер BASE: Action Cable в production/staging — адаптер redis с
   `channel_prefix: hermes_<env>` (`config/cable.yml`), адаптер подписывается на
   `hermes_production:presence:…`, а BASE спрашивает `PUBSUB CHANNELS presence:…` без префикса —
   ответ всегда пуст, и пользователь уходит офлайн, даже если у него открыта вторая вкладка.
   Существующий дефект; исправляется в вехе (раздел 5 B) и фиксируется в `CHANGELOG.md`.

Предположения: что никакой внешний код (плагины из app store) не зовёт `Nightfury.redis` до
инициализатора; что метрики в живых установках пишутся только через `AppIdentity` (поиск по
`app lib config` других обращений к `nf-` ключам не нашёл).

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Nightfury в `vendor/nightfury/` (D1).**
1. Скопировать `lib/` гема (ревизия `b9014eec30d94c52a63f724ef449a34d3b3f42c2`, файлы уже лежат в
   `$HOME/.cache/chaskiq-m6/bundle/ruby/3.3.0/bundler/gems/nightfury-b9014eec30d9/` — брать оттуда,
   из сети и из форков не качать) в `vendor/nightfury/lib/nightfury.rb` и
   `vendor/nightfury/lib/nightfury/{version,identity,metric}.rb`,
   `vendor/nightfury/lib/nightfury/metric/{value,time_series,count_time_series,avg_time_series}.rb`
   — те же имена классов; внутренние `require "nightfury/…"` можно заменить на `require_relative`.
   `LICENSE` гема → `vendor/nightfury/LICENSE` без изменений (MIT, «Copyright (c) 2012
   Avinasha Shastry»).
2. `Nightfury.redis` без настройки бросает `Nightfury::NotConfiguredError` (новый класс
   `< StandardError`, сообщение содержит «not configured»); `Redis.current` нигде не вызывается.
3. `Identity::Base.metric` — без строкового `class_eval <<-…`: `define_method`, то же поведение
   (мемоизация в `@_<name>`, `store_as`, `step` по умолчанию `:minute`).
4. `TimeSeries#get_all` отдаёт ВСЕ точки серии, включая точки с score 0 и отрицательным, и не
   отдаёт мета-запись; мету узнавать по содержимому члена (JSON-объект `default_meta.to_json`), а
   не по score и не по позиции (раздел 4 п. 4). Остальное поведение и формат ключей/значений — как
   в геме; вызовы `redis.exists(...)` не трогать.
5. Убрать строку `gem "nightfury", github: "michelson/nightfury" # "~> 1.0"` из `Gemfile`,
   `Gemfile.lock` обновить в Docker (`bundle lock`, на кэше m6); других изменений lock нет.
6. `config/initializers/nightfury.rb` — ровно эти строки кода (комментарии и magic comment можно):
   ```ruby
   require Rails.root.join("vendor/nightfury/lib/nightfury").to_s

   Nightfury.redis = Redis.new
   Nightfury.redis.namespace = "nf-#{Rails.env}"
   ```
   `Redis.new` без аргументов — ровно адрес прежнего `Redis.current` (раздел 4 п. 7): `ENV["REDIS_URL"]`
   с той же базой, иначе `redis://127.0.0.1:6379/0`; credentials сюда НЕ подмешивать, иначе
   установка с `REDIS_URL` в credentials молча переедет на другой Redis/DB.
7. RuboCop на `main` строгий (любой офенс валит CI; `.rubocop.yml` + `.rubocop_todo.yml`,
   `inherit_mode: merge: Exclude`): после вехи `bundle exec rubocop` по ВСЕМУ дереву — ноль
   офенсов (AC-005), без `rubocop:disable` и без правок `.rubocop_todo.yml` (AC-006). Версия
   RuboCop в этой вехе не меняется.

**B. `Redis.current` в приложении (D2).** Правило: каждое место читает тот же Redis и ту же DB,
что в BASE.
1. `lib/rack/health_check.rb` — пинг соединением `Redis.new` без аргументов (адрес BASE,
   мемоизировать в экземпляре можно); ошибка → `false`, как было.
2. `app/services/message_apis/twilio_phone/store.rb` `get_values` — через тот же Kredis-путь,
   которым `Store` пишет (`hash(conversation_key).to_h` или эквивалент), чтобы читать по адресу
   записи и с учётом `Kredis.namespace`. В `config/redis/shared.yml` добавить ровно
   `staging:` / `  <<: *production` перед `development:` (staging берёт адрес production);
   других правок в нём нет.
3. `app/jobs/offline_checker_job.rb` — исправить дефект раздела 4 п. 8: спрашивать
   `PUBSUB CHANNELS` у Redis Action Cable (`ActionCable.server.config.cable` — `url`) по имени
   канала с префиксом адаптера (`"#{channel_prefix}:#{key}"`, без префикса — просто `key`), как
   его строит `ActionCable::SubscriptionAdapter::ChannelPrefix`; при адаптере не redis (`async`
   в test, development без redis) — подписчиков не видно, пользователь уходит офлайн (поведение
   BASE). Запись в `CHANGELOG.md` раздела «Исправлено» — одна строка.
4. `config/initializers/redis.rb` — только две строки комментариев с `Redis.current`
   (удалить/переформулировать); код не трогать.
5. Тесты и e2e: `cy.appEval('Redis.current.del("…")')` в двух cypress-спеках →
   `Redis::Objects.redis.with { |r| r.del("…") }` (тот же ключ).
После вехи `git grep -n "Redis\.current" -- . ':!docs'` — пусто (AC-006).

**C. cypress (D3):** `c.cypress_folder =` → `c.install_folder =` (значение то же);
`spec/cypress/cypress_helper.rb` → `git mv` в `spec/cypress/e2e_helper.rb` без правок содержимого;
`/__cypress__/command` → `/__e2e__/command` в `spec/cypress/support/index.js` (два места). После
вехи `git grep -n "__cypress__" -- . ':!docs'` — пусто; `POST /__e2e__/command` в test отвечает
201 без строки деприкейшена (AC-003).

**D. rspec (D5, D6):** все `x.stub(:m)` → `allow(x).to receive(:m)`, `X.any_instance.stub(:m)` →
`allow_any_instance_of(X).to receive(:m)`, `X.any_instance.should_receive(:m)` →
`expect_any_instance_of(X).to receive(:m)` — с сохранением всех `.and_return/.with/...` цепочек
(включая `spec/support/stub_current_user.rb`). В `spec/spec_helper.rb` внутрь `RSpec.configure`
добавить ровно блок `config.mock_with :rspec do |mocks|` / `mocks.syntax = :expect` / `end`.
`spec/models/app_user_spec.rb:186` → `raise_exception(RuntimeError, "contact origin is not a Lead")`
(разрешено переложить в `expect do … end` по rubocop).

**E. Новые тесты** (имена примеров — маркеры мутационных ворот, раздел 7 AC-004):
- `spec/lib/nightfury_spec.rb`: пример с «not configured» в описании — без настройки
  `Nightfury.redis` бросает `NotConfiguredError` и не зовёт `Redis.current` (вернуть настройку в
  `ensure`); «key prefix» — после `AppIdentity.new(k).visits.incr(1, t)` в сыром redis
  (`Redis.new(url: ENV.fetch("REDIS_URL"))`) есть ключ `nf-test:app_identity.<k>:visits`;
  «counts» — два `incr` за один день → `get_all` содержит `"2"`; «without meta» — серия, записанная
  сырым `zadd` без мета-записи, целиком читается `get_all`; «zero and negative» — точки на
  `Time.at(0)` и `Time.at(-86_400)` плюс сырая мета-запись `zadd(key, 0, {}.to_json)` → `get_all`
  ровно `{"-86400" => "2", "0" => "1"}`; «averages» — `first_response_time.set(10, t)` и
  `set(20, t)` → `"15.0"`.
- `spec/lib/rack/health_check_spec.rb`: «200» — redis отвечает, статус 200; «503» — redis
  недоступен (например, `Redis.new` подменён соединением на `redis://127.0.0.1:1/0`), статус 503.
- `spec/jobs/offline_checker_presence_spec.rb` (новый файл; существующий
  `offline_checker_job_spec.rb` не трогать): конфиг cable подменён на
  `{"adapter" => "redis", "url" => ENV["REDIS_URL"], "channel_prefix" => "hermes_test"}`;
  «another client» — два клиента: второй подписчик на `hermes_test:<key>` жив, первый ушёл, job
  выполнен → пользователь остался online; «no client» — подписчиков нет → offline.

**F. `.rubocop.yml` (D7):** `require:` → `plugins:` для `rubocop-rails`, больше ничего.

## 6. Не трогать

- Всё вне списка AC-010. В частности: `config/application.rb` (URLcrypt уже исправлен),
  код `config/initializers/redis.rb` (только комментарии, раздел 5 B.4), `config/cable.yml`, `Dockerfile*`, `docker-compose.yml`, workflows, `bin/*`
  (включая `bin/ci-local`), `.githooks/`, `db/`, `package.json`, `yarn.lock`.
- Версии гемов: меняется только удаление nightfury. redis остаётся 4.8 (redis 5 — отдельной вехой).
- Всё, что принесли m1–m8 (и m9–m11, если влиты), не откатывать.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять запрещено. Менять строки можно
  ТОЛЬКО ради D5/D6 (раздел 5 D); новые файлы в `spec/support/`, правки `spec/rails_helper.rb`,
  `.rspec` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-010, sha256). Чужие спеки и клоны не
  трогать.
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq;
  новые git- и path-источники в Gemfile запрещены.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный и без единой строки деприкейшена или warning: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 528 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m12-probes/rspec_gate_m12.sh`

- **AC-002** — production, staging, development и test грузятся с RUBYOPT=-W:deprecated без единой строки деприкейшена или warning, Nightfury пишет в nf-env, у URLcrypt есть ключ.
  `bash docs/specs/fork-updates-m12-probes/m12_boot_probe.sh`

- **AC-003** — на REDIS_URL с DB 3: метрики и данные Store, записанные BASE, дерево читает так же и из DB 3, get_all отдаёт все точки, Store учитывает Kredis.namespace и работает в staging, health check 200 и 503, cypress /__e2e__/command без деприкейшенов, BASE читает то, что записало дерево.
  `bash docs/specs/fork-updates-m12-probes/m12_compat_probe.sh`

- **AC-004** — новые тесты убивают мутанты: возврат Redis.current, вложенное пространство имён, сломанные incr и среднее, get_all по позиции и по score, офлайн-чекер без префикса и никогда не уводящий офлайн, health check всегда 200 и всегда 503.
  `python3 -I docs/specs/fork-updates-m12-probes/m12_mutation_gate.py`

- **AC-005** — lock ставится во frozen-режиме, rubocop без офенсов и без предупреждений о конфиге.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true -v "$HOME/.cache/chaskiq-m6/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && bundle exec rubocop --cache false > /tmp/rc.out 2>&1; rc=\$?; tail -3 /tmp/rc.out; test \$rc = 0 && ! grep -Eiq \"supports plugin|deprecat|warning:\" /tmp/rc.out"'`

- **AC-006** — целостность: Gemfile и lock минус только nightfury, Nightfury вендорен с лицензией и без Redis.current и строкового eval, инициализатор дословный, Redis.current и /__cypress__/ нигде в репозитории нет, e2e_helper.rb, staging в shared.yml, install_folder, rubocop-конфиг, спеки переведены без потери ожиданий, supply-chain чистый.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m12-probes/m12_integrity_probe.py $B && python3 -I docs/specs/fork-updates-m4-probes/m4_tree_probe.py $B'`

- **AC-007** — нет регрессий рантайма m1–m5: пробные спеки m1, m2, m3, m4 и m5 зелёные.
  `bash -c 'G=docs/specs/fork-updates-m12-probes/rspec_gate_m12.sh; bash $G --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $G --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb && bash $G --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb'`

- **AC-008** — нет регрессий загрузки m1–m8: пробники загрузки m2, m3, m4 и m8, redis из compose, puma и конфиг m1.
  `bash -c 'export CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle; bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh && bash docs/specs/fork-updates-m8-probes/m8_boot_probe.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-009** — живой стенд production: фронт собирается, ассеты отдаются, лимит входа срабатывает на всех вариантах пути.
  `bash -c 'CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh'`

- **AC-010** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "bd332915a5840c062c0dc3f0c3c3352cb1e11d1bf19cc86ad08cdc86b4fe6aba  docs/specs/fork-updates-m12-probes/examples_base.txt" "774eca2a8e0ca8f315863e89522e1d26448c183da32db13ad9568f52779cbd29  docs/specs/fork-updates-m12-probes/m12_boot_probe.sh" "98f74178ec2d0050a549cc57dec87d0742b4428a8428cdc680569a8134391ddf  docs/specs/fork-updates-m12-probes/m12_compat_probe.sh" "9d910cdfa7734c03e1db0f7d4997aa518f99640ba11bb0f3f243f0c8d36c768d  docs/specs/fork-updates-m12-probes/m12_integrity_probe.py" "bbc46e8d931ccd9179e4ce566fd616024681c5c0d26900fd548f4bdf369c4251  docs/specs/fork-updates-m12-probes/m12_mutation_gate.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m12-probes/pending_allowed.txt" "8b67999d66d9d7c6d4a5d9dd42f097c1fe7190957cdfa6457ab77dfabdaba877  docs/specs/fork-updates-m12-probes/rspec_gate_m12.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "Gemfile|Gemfile[.]lock|[.]rubocop[.]yml|CHANGELOG[.]md|config/initializers/(nightfury|cypress_on_rails|redis)[.]rb|config/redis/shared[.]yml|vendor/nightfury/.+|lib/rack/health_check[.]rb|app/jobs/offline_checker_job[.]rb|app/services/message_apis/twilio_phone/store[.]rb|spec/.+")"'`

- **AC-011** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-007, AC-008, AC-009, AC-010, AC-011
зелёные; AC-001 красный (D1, D3, D5, D6 в выводе); AC-002 красный (`Redis.current` при загрузке
production); AC-003 красный (`tree Gemfile still references nightfury`); AC-004 красный
(`vendor/nightfury/lib/nightfury.rb missing`); AC-005 красный (предупреждение rubocop о `plugins:`); AC-006
красный (nightfury в Gemfile, `Redis.current`, `__cypress__`, `cypress_folder`, старый синтаксис в спеках).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m12.md --exclude "docs/specs/fork-updates-m12-probes/**" --context "chaskiq fork-updates-m12: nightfury вендорен в vendor/nightfury без Redis.current (ключи nf-<env> и адрес ENV REDIS_URL как прежде, get_all все точки без меты), Redis.current заменён в health check/twilio store/cypress e2e, offline checker учитывает channel_prefix cable, cypress install_folder и /__e2e__, rspec-mocks только expect-синтаксис, rubocop plugins; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m12.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m12-probes/**

Контекст ревьюерам: не поменялся ли формат ключей и значений метрик и адрес Redis/DB каждого места; не ослаблены ли спеки при
конвертации синтаксиса; не ушёл ли дифф за раздел 6.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 11: AC-001…AC-011. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-004 — строка по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m12.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m12.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- деприкейшен или warning, которого нет в таблице раздела 3 и который не убирается правкой в
  разрешённых путях (опиши строку, источник и вариант: апгрейд гема, патч, замена);
- зелёный rubocop недостижим без `rubocop:disable`/`.rubocop_todo.yml`, или сьют — без изменения
  смысла существующего теста;
- `m12_compat_probe.sh` красный, а причина — в формате данных BASE, а не в дереве;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-m6`, `node_modules` или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, глушить вывод (`$stderr` в `/dev/null`,
`Warning[:deprecated] = false`, `ActiveSupport::Deprecation.silenced`, `RSpec::Mocks`-конфиг
`:should`, `on_potential_false_positives = :nothing`), менять пробники, глушить коды возврата.

## 10. Стыки

- **rack 2.2 → 3** — следующая веха (fork-updates-m13), запускается после влития этой.
- redis-rb 4.8 → 5: после вендоринга ни один гем не держит `redis ~> 4`; в redis 5 нет
  `Redis.exists_returns_integer=` (`config/initializers/redis.rb`) — отдельная веха.
- Квирк `redis.exists` в nightfury (раздел 4 п. 4) оставлен как есть: мета-записи серий не
  создаются; `get_all` теперь отдаёт все точки, дашборды получат самый старый день.
- Шум `puts` OpenStruct-ошибок GraphQL в выводе тестов — не деприкейшен, вне вехи.
