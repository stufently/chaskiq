# fork-updates-m1 — перенос полезных изменений из форков chaskiq

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`, ветка `main`). Дата спеки: 2026-11-17.
- BASE_SHA: `46dfdd11c63c6849ecde16a0dcc54d388e2613a3` «Include AWS S3 endpoint in storage
  configuration» (main == upstream/main). Клон снимается с СЛЕДУЮЩЕГО коммита — коммита
  этой спеки и каталога пробников `docs/specs/fork-updates-m1-probes/`; других коммитов
  между BASE_SHA и HEAD клона нет.
- Исполнитель: Qwen Code (`qw`), назначен координатором. Мутации по тестам вехи гоняет
  противоположный исполнитель (Codex/Spark). Исправления внутри вехи — тому же Qwen.
- Пакеты, выбранные владельцем: A (globalize/roadie-rails), B (SMTP и dev-фиксы), C
  (безопасность и зависимости), D (CI) плюс `.gitattributes`, puma.rb, compose. Апгрейд
  Rails до 8 в веху НЕ входит.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m1`.
  Живое дерево `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root. На хост ничего
  не ставить (никаких gem/bundle/npm/yarn/pip/apt на хосте).
- В клоне есть refs форков для cherry-pick/просмотра: `refs/forks/Haris16-code/*`,
  `refs/forks/antonburesh/*`, `refs/forks/PriDebnath/*`, `refs/forks/HayimG/*`,
  `refs/forks/pr/930`. Других форков в клоне нет и брать из них нечего.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker, собран из `docs/specs/fork-updates-m1-probes/Dockerfile.test` | ruby 3.3.5 + libpq + node/npm + глобальный ts-node 10.9.2 (его зовёт `spec/support/graphql_queries.rb`, CI делает так же) |
| гемы | `$HOME/.cache/chaskiq-m1/bundle` (BUNDLE_PATH, общий кэш) | `bundle install` для гейта |
| кэш yarn | `$HOME/.cache/chaskiq-m1/yarn` | `yarn install` в Docker |
| `node_modules/` | в клоне (gitignored), `yarn install --frozen-lockfile` на BASE | ts-node в спеках, сборка фронта |
| образы | `postgres:14-alpine`, `redis:5-alpine`, `node:16.20.2-bullseye-slim`, `rhysd/actionlint:1.7.12` | гейт, фронт, CI |

Команды, которыми работать (из корня клона):

```bash
# bundler (Gemfile/Gemfile.lock); lock меняется только так, точечно
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app" -w /app chaskiq-test:m1 \
  bundle lock --conservative --update <гемы>
# yarn
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e YARN_CACHE_FOLDER=/ycache \
  -v "$HOME/.cache/chaskiq-m1/yarn:/ycache" -v "$PWD:/app" -w /app node:16.20.2-bullseye-slim yarn <…>
# полный rspec против базовой линии (postgres+redis поднимает сам, ~4–5 мин)
bash docs/specs/fork-updates-m1-probes/rspec_gate.sh
# один или несколько своих файлов спеков: --only <файл>
```

## 3. Задача и почему

С нуля проект не собирается: `Gemfile` тянет два удалённых репозитория — `jules-w2/globalize`
и `frederikspang/roadie-rails` (оба 404), `bundle install` падает на первом же из них.
Форки уже нашли рабочие замены, плюс у них есть фиксы SMTP, dev-окружения, CI и
безопасности. Веха переносит выбранное владельцем, ничего «заодно».

Что сломается и чинится в этой же вехе: смена globalize 6.3 → 7.1 и roadie-rails 3.0 →
3.4 (rubygems) обязана пройти полный rspec без НОВЫХ падений против базовой линии;
включение писем Devise не должно ронять существующие спеки; бампы гемов — только те, что
не добавляют падений (см. 5.C3).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-17 командами в Docker на копии `main`:

1. `bundle install` на чистом main падает: `git clone … frederikspang/roadie-rails.git …
   could not read Username` (репозиторий 404). `curl` на github: `jules-w2/globalize` 404,
   `frederikspang/roadie-rails` 404, `globalize/globalize` 200. Остальные git-источники lock
   (`chaskiq/emoji_data.rb`, `mbleigh/acts-as-taggable-on`, `michelson/nightfury`,
   `roo-rb/roo`, `stympy/faker` → 301) отвечают `git ls-remote`.
2. Минимальный фикс A: `gem "globalize", "~> 7.1"` и `gem "roadie-rails", "~> 3.4"` +
   `bundle lock --conservative --update globalize roadie-rails` → lock меняется на 31 строку
   (globalize 7.1.3, roadie-rails 3.4.0, два блока GIT удалены), BUNDLED WITH остаётся 2.4.10.
   rubygems 2026-11-17: globalize 7.1.3 (activerecord >= 7.0, < 8.2), roadie-rails 3.4.0
   (railties >= 5.1, < 8.2). Haris `1a215e7936` держит globalize на git `globalize/globalize`
   — мы берём rubygems, как велел владелец.
3. **Базовая линия rspec** (main + только фикс из п.2, образ `chaskiq-test:m1`, без
   appstore-плагинов): `420 examples, 122 failures, 29 pending, errors_outside=0`, 3 мин 17 с.
   Два прогона дали одинаковый набор падений. Все 122 — отсутствие плагинов appstore:
   68× `undefined method 'definitions' for nil`, `uninitialized constant MessageApis::Slack/
   Zapier/Twitter/Messenger/Zoom` и т.п. (`spec/controllers/api/v1/hooks/*`,
   `app_package_integration`). Список — `docs/specs/fork-updates-m1-probes/rspec_baseline.txt`.
   Чинить их — НЕ эта веха (следующая веха Codex).
4. Без node ExecJS не грузит Rails; `spec/support/graphql_queries.rb` зовёт `npx ts-node` —
   отсюда node/npm/ts-node в образе.
5. `yarn install --frozen-lockfile` и `yarn build` на BASE в `node:16.20.2-bullseye-slim`
   проходят (сборка 6 с). axios: `package.json` `^0.25.0`; в yarn.lock есть ещё
   транзитивный `axios@^1.3.5` (1.3.6). Импортов `axios` пять: `packages/messenger/.../giphy.tsx`,
   `packages/messenger/.../graphql/client.ts` (`axios.create`), `packages/store/src/actions/auth.ts`
   (`axios.defaults.withCredentials`), `packages/store/src/graphql/client.ts`,
   `src/pages/auth/acceptInvitation.tsx`; `CancelToken`/`interceptors` нигде нет. Свежий axios
   по npm 2026-11-17 — 1.21.1 (от 2026-11-09). Пробно: `yarn add -W axios@^1.21.1` меняет
   только `package.json` (строка axios + перевод строки в конце) и yarn.lock; `yarn build`
   проходит, в бандле `"1.21.1"`.
6. rubygems 2026-11-17: rack 2.2.x — свежий 2.2.25; rack-attack 6.8.0 (rack >= 1.0, < 4).
   В rack-attack 6.8.0 есть `Rack::Attack::Railtie` — `app.middleware.use(Rack::Attack)`;
   значит строка `use Rack::Attack` в `config.ru` из PR #930 даст ДВОЙНУЮ вставку — её не
   ставить. Пробный порт PR #930 (initializer + флаги Devise) прошёл и пробник, и полный rspec
   без новых падений.
7. Пробная резолюция snyk-бампов (opensearch-ruby >= 3.1, dialogflow >= 1.7, twilio ~> 5.67,
   omniauth-oauth2 >= 1.9, faraday >= 2.14.1, aws-sdk-s3 ~> 1.208, rails 7.2.1.1, uri 0.12.5,
   doorkeeper ~> 5.6, rack-cors ~> 2.0, rack 2.2.25) через `bundle lock --conservative
   --update …` резолвится (lock −183/+180). Прошли ли тесты на этом — НЕ проверено,
   это работа вехи.
8. `config/puma.rb`, puma 6.4.3 (`lib/puma/configuration.rb`): DEFAULTS `workers: 0`,
   `wait_for_less_busy_worker: 0.005`; `puma_options_from_env` берёт workers из
   `WEB_CONCURRENCY`. Сейчас `workers` в файле закомментирован, а `wait_for_less_busy_worker`
   и `on_worker_boot` объявлены безусловно. Значит сегодня: WEB_CONCURRENCY не задан → 0
   воркеров (single), задан N → N. Версия PriDebnath `f877c09b8c` (`workers_count =
   ENV.fetch("WEB_CONCURRENCY") { 0 }.to_i`) это поведение сохраняет — проверено пробником.
9. `config/environments/production.rb` (ветка `SMTP_DELIVERY_METHOD=smtp`): сейчас в
   `smtp_settings` НЕТ ни `port`, ни `domain` — действуют умолчания mail 2.8.1
   (`port: 25`, `domain: 'localhost.localdomain'`, `lib/mail/network/delivery_methods/smtp.rb`).
   antonburesh `8ac45dd0f3` ставит дефолты 587 и `wowvendor.com` — оба меняют прод молча;
   берём ENV с умолчаниями, равными сегодняшнему поведению (5.B1).
10. `config/environments/development.rb`: `ws = ENV.fetch('WS') { 'ws://locahost:3000/cable' }`
    — опечатка. `config/chaskiq_boot.rb`: `Plugin.save_all_plugins` зовётся без проверки
    таблицы. `app/javascript/src/App.tsx`: `document.querySelector("meta[name='chaskiq-host']")
    .getAttribute('content')` без null-проверки, auth0-меты через `//@ts-ignore`.
11. Devise: в `config/initializers/devise.rb` оба флага закомментированы; шаблоны
    `app/views/devise/mailer/password_change.html.erb` и `email_changed.html.erb` есть;
    `Agent` — `database_authenticatable`, без `confirmable`. Фронт шлёт и `/oauth/token.json`,
    и `/oauth/token` (`packages/store/src/actions/auth.ts`). В `config/initializers/doorkeeper.rb`
    `skip_client_authentication_for_password_grant` закомментирован. В test.rb
    `cache_store = :null_store` — тесту троттлинга нужен свой MemoryStore. Фронт шлёт JSON:
    password-grant на `/oauth/token.json` (`auth.ts:30`), refresh_token-grant на `/oauth/token`
    (`auth.ts:138`, токен живёт `USER_TOKEN_EXPIRES_IN`, по умолчанию 1 час) — значит
    троттлинг всех POST на token резал бы обновление токена, а `Rack::Attack::Request#params`
    JSON-тело не разбирает. Devise 4.9 шлёт эти письма в `after_update` (внутри транзакции),
    а в production `raise_delivery_errors` не выключен (дефолт Rails — true): сбой SMTP/SES
    откатил бы смену пароля. В проде `active_job.queue_adapter = :sidekiq`, очередь `mailers`
    есть в `config/sidekiq.yml`, `deliver_later` в приложении уже используется.
12. CRLF в индексе у 5 файлов: `spec/fixtures/emails/*.eml` (3), `spec/fixtures/requests/idn.txt`,
    `.../client_messenger/icons/chat.svg`. С `* text=auto eol=lf` без исключений они станут
    «изменёнными», а фикстуры писем — побайтно другими.
13. GitHub releases 2026-11-17: actions/checkout v7.0.1, docker/login-action v4.8.0,
    docker/metadata-action v6.2.0, docker/build-push-action v7.4.0 (у antonburesh v4/v3/v5/v6 —
    устарели). actionlint 1.7.12 на текущих двух workflow даёт 6 замечаний (старые раннеры,
    `set-output`).
14. Вредоносные форки VooDooNoir/chaskiq и kreasialamteknologi/chaskiq (eval в
    `esbuild.config.mjs`, стилер через `.vscode/tasks.json`) в локальные refs не загружены.

Предположения (не проверены): что входы `with:` у новых мажоров actions прежние — сверить
по `action.yml` нужного тега (5.D); что Snyk-бампы проходят тесты.

## 5. Что сделать

Коммиты — по пакетам, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Гемы с умершими git-источниками.**
1. `Gemfile`: `gem "globalize", "~> 7.1"` и `gem "roadie-rails", "~> 3.4"` вместо git-строк
   (закомментированную строку `globalize/globalize` можно убрать).
2. `bundle lock --conservative --update globalize roadie-rails` — lock минимально,
   BUNDLED WITH остаётся 2.4.10. Широкую пересборку lock (antonburesh `8d70144e8e`) НЕ брать,
   `bundle update` без списка гемов — запрещён.

**B. SMTP и dev-фиксы.**
1. `production.rb`, хеш `smtp_settings`: добавить `port: ENV.fetch('SMTP_PORT', 25).to_i` и
   `domain: ENV.fetch('SMTP_DOMAIN', 'localhost.localdomain')`; остальные ключи не трогать.
2. `development.rb`: опечатка `locahost` → `localhost` в дефолте WS. `asset_host` НЕ трогать.
3. `config/chaskiq_boot.rb`: `Plugin.save_all_plugins` только если
   `ActiveRecord::Base.connection.table_exists?("plugins")`, иначе одна строка в stdout
   (как в PriDebnath `4a421c55ff`). Печать backtrace из того коммита — не брать.
4. `app/javascript/src/App.tsx`: null-safe чтение метатегов — PriDebnath `c236c1ff18`
   (можно cherry-pick): `?.getAttribute`, фолбэк `window.location.origin`, типизированные
   auth0-меты вместо `@ts-ignore`.
5. `config/puma.rb` — из `f877c09b8c`: `workers_count = ENV.fetch("WEB_CONCURRENCY") { 0 }.to_i`,
   `workers workers_count if workers_count > 0`, `wait_for_less_busy_worker` и `on_worker_boot`
   только в кластерном режиме. Без WEB_CONCURRENCY поведение обязано остаться прежним (п.4.8).
6. `docker-compose.yml`: из Haris `7cef190ede` — убрать `tmpfs: /tmp` у `x-app`; данные
   postgres — ровно `${POSTGRES_DATA:-postgres}:/var/lib/postgresql/data` (по умолчанию
   именованный том, существующая база доступна через `POSTGRES_DATA=~/apps/postgres`);
   из `f877c09b8c` — в env backend
   `WEB_CONCURRENCY: 0`, `HOST: http://localhost:3000`, `WS: ws://localhost:3000/cable`.
   Образ `chaskiq/chaskiq:1.1.0` и остальное не трогать.
7. `.gitattributes` (PriDebnath): `* text=auto eol=lf`, `*.sh text eol=lf`, `bin/* text eol=lf`
   плюс исключения `-text` для пяти CRLF-файлов из п.4.12 (маской `*.eml` и путями), чтобы
   ни один файл не перенормализовался.

**C. Безопасность и зависимости.**
1. Ручной порт upstream PR #930 (`refs/forks/pr/930`, коммит `5849f167`):
   `gem "rack-attack", "~> 6.8"`; `config/initializers/rack_attack.rb` — throttle `"logins/ip"`,
   `limit: 20, period: 1.hour`, ключ `req.ip` для POST на ровно `/oauth/token` и
   `/oauth/token.json`, КРОМЕ запросов с `grant_type=refresh_token`; grant_type читать так,
   чтобы работали и form, и JSON (например
   `ActionDispatch::Request.new(req.env).request_parameters["grant_type"]`, ошибку разбора
   считать «не refresh»); подписка на событие троттлинга пишет в `Rails.logger`, не `puts`.
   В `config.ru` `use Rack::Attack` НЕ добавлять (railtie, п.4.6). В `devise.rb` включить
   `send_email_changed_notification = true` и `send_password_change_notification = true`.
   Проверку сложности пароля (`password_complexity` в `Agent`) НЕ переносить.
   В `app/models/agent.rb` — только переопределение `send_devise_notification`: для
   `:password_change` и `:email_changed` — `devise_mailer.send(notification, self, *args).deliver_later`,
   для остальных уведомлений — `super` (сброс пароля и прочее остаются синхронными).
2. axios → `^1.21.1` через `yarn add -W axios@^1.21.1` в Docker (меняются только
   `package.json` и `yarn.lock`); пять импортов из п.4.5 проверить на совместимость с 1.x.
3. rack → свежий 2.2.x (2.2.25, `gem "rack", "~> 2.2", ">= 2.2.25"` или эквивалент).
   Snyk-бампы HayimG (`refs/forks/HayimG/snyk-fix-*`, полу-таблица печатается в выводе AC-001):
   aws-sdk-s3, omniauth-oauth2, faraday, twilio-ruby (в пределах 5.x), opensearch-ruby,
   google-cloud-dialogflow и широкий список из `e43ff787…`/`ee671e76…`/`ffd10d7c…`
   (anycable-rails, uri, jsbundling-rails, propshaft, devise, graphiql-rails, devise_invitable,
   doorkeeper ~> 5.6, sidekiq, aws-sdk-rails, net-http, rack-cors ~> 2.0, dotenv-rails,
   cypress-on-rails, rspec-rails, factory_bot_rails, rubocop*). rails — 7.2.1.1 (snyk-нижняя
   граница); 7.2.2+ и 8.x запрещены. Берутся ВСЕ бампы, с которыми полный rspec (AC-002) не
   даёт новых падений; бамп, ломающий тесты (типично faraday 2, connection_pool 3), не брать
   и назвать в `note` критерия AC-001: имя гема словом, целевая версия, какие спеки упали и с
   чем. AC-001 падает, пока хоть одна невзятая snyk-граница не названа в этом note.
   Правка кода приложения под бамп — вне вехи.
4. Новые тесты (они попадут и в полный прогон):
   `spec/requests/rack_attack_spec.rb` (21-й password-POST на token с одного IP → 429, JSON
   и form; другой IP не задет; refresh_token не считается; другой путь не задет; свой
   `ActiveSupport::Cache::MemoryStore`),
   `spec/models/agent_notifications_spec.rb` (два уведомления ставятся в очередь, а не шлются
   синхронно; с inline-адаптером письмо на смену пароля — владельцу, на смену email — старому
   адресу; пароль без спецсимволов валиден), `spec/lib/chaskiq_boot_spec.rb`
   (нет таблицы → `save_all_plugins` не зовётся; есть → зовётся).

**D. CI** — только `.github/workflows/dockerimage.yml` и `docker-image-ghcr.yml`, по мотивам
antonburesh `b73424a51f`: `actions/checkout@v7`, `docker/login-action@v4` (вместо
`azure/docker-login`), `docker/metadata-action@v6`, `docker/build-push-action@v7`;
`set-output` → `echo "short_sha=…" >> "$GITHUB_OUTPUT"`; в `dockerimage.yml` checkout ДО шага
с `git rev-parse`; `BUNDLER_VERSION=2.4.10` в build-args; `workflow_dispatch` и
`timeout-minutes` — можно. Имя образа и теги — НАШИ: `$GITHUB_REPOSITORY`/`github.repository`,
у ghcr теги `type=ref,event=branch`, `type=ref,event=pr`, `type=sha` как сейчас; образ
`DOCKER_USERNAME/chaskiq` из `75c9d7fd9c` и `type=raw,value=latest`, `type=sha,prefix=` — НЕ
брать. Входы `with:` сверить с `action.yml` выбранных тегов (curl raw.githubusercontent.com),
итог — в note AC-006.

## 6. Не трогать

- Всё вне списка критерия AC-008; в частности `app/` (кроме `App.tsx` и одного метода в
  `app/models/agent.rb`), `lib/`, `db/`,
  существующие файлы `spec/`, `Dockerfile*`, `config.ru`, `config/routes.rb`,
  `config/initializers/doorkeeper.rb`, `esbuild.config.mjs`, остальные workflows.
- `docs/specs/fork-updates-m1.md` и `docs/specs/fork-updates-m1-probes/**` — уже закоммичены
  постановщиком в HEAD клона; не править, не удалять, не перекоммичивать (проверяет AC-008
  по sha256).
- Запрещено брать что-либо из VooDooNoir/chaskiq и kreasialamteknologi/chaskiq (вредоносный код).
  Запрещены: `.vscode/` (в т.ч. `tasks.json`), workflows на self-hosted runner,
  `skip_client_authentication_for_password_grant`, закоммиченные `.env*` (кроме `.env.example`),
  чужой брендинг (`wowvendor`, `DOCKER_USERNAME/chaskiq`, имена форков), `eval`/`new Function`
  в JS-конфигах, невидимые Unicode-символы.
- Не брать: Rails 8 и 7.2.2+, Heroku stack 24 (`2863d73433`), PR #1018, проверку сложности
  пароля, широкую пересборку lock antonburesh, asset_host из `4a421c55ff`, esbuild-плагины и
  `bin/dev`/`Procfile.dev`/`before_start.rb` PriDebnath.

## 7. Критерии приёмки

Команды запускаются из корня клона по порядку. Базовые образы и кэши — раздел 2.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме (свежий BUNDLE_PATH внутри контейнера), умершие git-источники ушли, globalize/roadie-rails/rack/rack-attack нужных версий, rails остаётся 7.2.1.x, каждая невзятая snyk-граница названа в note AC-001 файла report.json.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m1-probes/m1_deps_probe.rb"'`

- **AC-002** — полный rspec: число примеров не меньше базовой линии и нет ни одного падения вне базовой линии.
  `bash docs/specs/fork-updates-m1-probes/rspec_gate.sh`

- **AC-003** — пробник рантайма: Rack::Attack вставлен один раз, throttle 20/час по IP ровно на двух token-путях для password-grant (JSON и form), refresh_token не считается, письма Devise о пароле и email ставятся в очередь и доходят, сброс пароля остаётся синхронным, пароль без сложности валиден, client auth для password grant не отключён, guard таблицы plugins работает.
  `bash docs/specs/fork-updates-m1-probes/rspec_gate.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb`

- **AC-004** — compose валиден; puma.rb держит прежнее поведение без WEB_CONCURRENCY; SMTP из ENV с прежними умолчаниями; WS-опечатка; App.tsx; compose; .gitattributes.
  `bash -c 'docker compose -f docker-compose.yml config -q && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-005** — фронт: lock согласован, сборка проходит, axios ровно 1.21.1, старого 0.x в lock нет.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e YARN_CACHE_FOLDER=/ycache -v "$HOME/.cache/chaskiq-m1/yarn:/ycache" -v "$PWD:/app" -w /app node:16.20.2-bullseye-slim sh -c "yarn install --frozen-lockfile --non-interactive --silent && yarn build" && test "$(jq -r .dependencies.axios package.json)" = "^1.21.1" && test "$(jq -r .version node_modules/axios/package.json)" = 1.21.1 && ! grep -q "^axios@.0[.]" yarn.lock'`

- **AC-006** — два Docker-workflow проходят actionlint и пробник CI (мажоры actions, GITHUB_OUTPUT, наши имена и теги).
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:1.7.12 -shellcheck= .github/workflows/dockerimage.yml .github/workflows/docker-image-ghcr.yml && bash docs/specs/fork-updates-m1-probes/m1_ci_probe.sh'`

- **AC-007** — дерево и дифф чисты от вредоносных маркеров: нет невидимых Unicode (U+FE00–FE0F, U+E0100–E01EF, zero-width, bidi, BOM), нет eval в esbuild-конфиге, нет .vscode, нет self-hosted, нет skip_client_authentication, нет .env, нет чужого брендинга, источники lock-файлов только ожидаемые, CRLF-файлы не перенормализуются.
  `python3 -I docs/specs/fork-updates-m1-probes/m1_tree_probe.py 46dfdd11c63c6849ecde16a0dcc54d388e2613a3`

- **AC-008** — вне разрешённых путей ничего не изменено, пробники и спека не тронуты (sha256).
  `bash -c 'test "$(git log --format=%H 46dfdd11c63c6849ecde16a0dcc54d388e2613a3..HEAD -- docs/specs | wc -l)" = 1 && printf "%s\n" "107cfbebb178ef7a6008db179d1e87cb566127a267f396fec0f0102ab3be0da4  docs/specs/fork-updates-m1-probes/Dockerfile.test" "d10b704b93b5c6cc081f27f714d10edf1f5601faea2af2935d681deb26cbaebd  docs/specs/fork-updates-m1-probes/m1_ci_probe.sh" "b12ce0abaa89b7ab8077e5c9ce006418993d0d1f384b264c013addde21339a01  docs/specs/fork-updates-m1-probes/m1_config_probe.rb" "32d3bc31ee6c0d32bc3623f7d61cbe3ead0f468837678255b7bca8f5e9987d81  docs/specs/fork-updates-m1-probes/m1_deps_probe.rb" "7506da077dfe8832c1836a5b843aa055f2fd4f39689bad3f4d8e275fb4c5ce1b  docs/specs/fork-updates-m1-probes/m1_puma_probe.rb" "e1a86cb634405dc2c0128222932c612bbae03d680f59a088f34483ea9e4c1ee8  docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb" "1b42a50b7f920f190246386e2c318c2b26652e6e2ef1cd81f4ef0e0230bc7efb  docs/specs/fork-updates-m1-probes/m1_tree_probe.py" "a8608d408e332b6c55b99e7ee54d133b74603b60756f7f3dcede402a40e10588  docs/specs/fork-updates-m1-probes/rspec_baseline.txt" "364093acd94c22c83defda3e202175cfd4b50e8ea9c226810b6b306a99cc0c0a  docs/specs/fork-updates-m1-probes/rspec_gate.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only 46dfdd11c63c6849ecde16a0dcc54d388e2613a3...HEAD | grep -v -x -E "Gemfile|Gemfile[.]lock|package[.]json|yarn[.]lock|[.]gitattributes|docker-compose[.]yml|config/puma[.]rb|config/chaskiq_boot[.]rb|config/environments/production[.]rb|config/environments/development[.]rb|config/initializers/rack_attack[.]rb|config/initializers/devise[.]rb|app/models/agent[.]rb|app/javascript/src/App[.]tsx|[.]github/workflows/dockerimage[.]yml|[.]github/workflows/docker-image-ghcr[.]yml|spec/requests/rack_attack_spec[.]rb|spec/models/agent_notifications_spec[.]rb|spec/lib/chaskiq_boot_spec[.]rb|docs/specs/fork-updates-m1[.]md|docs/specs/fork-updates-m1-probes/.+")"'`

- **AC-009** — все обязательные файлы вехи есть в диффе.
  `bash -c 'for f in Gemfile Gemfile.lock package.json yarn.lock .gitattributes docker-compose.yml config/puma.rb config/chaskiq_boot.rb config/environments/production.rb config/environments/development.rb config/initializers/rack_attack.rb config/initializers/devise.rb app/models/agent.rb app/javascript/src/App.tsx .github/workflows/dockerimage.yml .github/workflows/docker-image-ghcr.yml spec/requests/rack_attack_spec.rb spec/models/agent_notifications_spec.rb spec/lib/chaskiq_boot_spec.rb; do git diff --name-only 46dfdd11c63c6849ecde16a0dcc54d388e2613a3...HEAD | grep -qx "$f" || exit 1; done'`

- **AC-010** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001 красный («GIT source jules-w2/globalize»
или ошибка bundler), AC-002 красный («no rspec json»), AC-003…AC-007 и AC-009 красные по
своим пунктам, AC-008 и AC-010 зелёные.

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила, раздел «Автономное
перекрёстное ревью»). Коротко: коммит → REVIEW_SHA; исполнитель Qwen → ревьюеры `codex` +
`agy`, оба параллельно на `46dfdd11c63c6849ecde16a0dcc54d388e2613a3..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только
обёртка, путь абсолютный:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial codex --clone <клон> --base 46dfdd11c63c6849ecde16a0dcc54d388e2613a3 --range 46dfdd11c63c6849ecde16a0dcc54d388e2613a3..<REVIEW_SHA> --exclude docs/specs/fork-updates-m1.md --exclude "docs/specs/fork-updates-m1-probes/**" --exclude yarn.lock --context "chaskiq fork-updates-m1: перенос из форков (globalize/roadie, SMTP, rack-attack, axios, snyk, CI); только чтение"`

(то же для `agy`). Спека и пробники закоммичены постановщиком и в диапазон ревью не входят;
yarn.lock — сгенерированный, его источники проверяет AC-007. Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m1.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m1-probes/**
REVIEW_EXCLUDE: yarn.lock

Контекст ревьюерам: не ушёл ли дифф за раздел 6; поведение прода без новых ENV (SMTP,
puma); двойная вставка Rack::Attack; совместимость axios 1.x в пяти импортах; не тянет ли
lock чужие источники.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-001 — список невзятых
snyk-бампов с причиной; в `note` AC-002 — итоговые числа примеров/падений и сколько
базовых падений починилось само; в `note` AC-006 — сверка входов actions.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m1.md>",
  "base_sha": "46dfdd11c63c6849ecde16a0dcc54d388e2613a3",
  "reviewed_sha": "<коммит, отданный на ревью>",
  "final_sha": "<HEAD после единственного захода фиксов>",
  "executor": {"backend": "qwen", "model": "<точная модель>"},
  "review": {
    "initial_receipts": ["<квитанция codex>", "<квитанция agy>"],
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m1.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- globalize 7.1 или roadie-rails 3.4 дают новые падения, которые не чинятся без правки
  кода приложения вне раздела AC-008;
- включение писем Devise роняет существующие спеки;
- для работы нужен файл вне AC-008 или правка пробника/базовой линии;
- образ, кэш или сервисы из раздела 2 недоступны (Docker, сеть до rubygems/npm);
- axios 1.21.1 ломает сборку или один из пяти импортов без правки вне `package.json`/`yarn.lock`.
Ломающий snyk-бамп — НЕ повод останавливаться: не брать и описать в note AC-001.
Подмена окружения и глушители кода возврата в командах запрещены.

## 10. Стыки

Следующей вехе (Codex, починка падений): базовая линия и гейт — в
`docs/specs/fork-updates-m1-probes/`; 122 падения — отсутствие appstore-плагинов
(`packages:download_and_install` требует `CHASKIQ_APPSTORE_TOKEN`). Невзятые snyk-мажоры
— из note AC-001. Rails 8 — отдельная веха. Rack::Attack использует `Rails.cache`
(в проде — дефолтный store процесса); общий Redis-store для нескольких реплик — отдельно.
Существующим dev-окружениям с базой в `~/apps/postgres` — `POSTGRES_DATA=~/apps/postgres`.
Продовый `Dockerfile` (nodesource setup_16, apt.postgresql.org bullseye) этой вехой не
проверялся.
