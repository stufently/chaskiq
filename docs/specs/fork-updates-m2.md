# fork-updates-m2 — полный зелёный rspec после переноса из форков

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `fork-updates-m1`.
  Дата спеки: 2026-11-18.
- BASE_SHA: `28a28676eb19b4d99a2907cb83249d98fc03b190` «Update CI workflows to current action
  majors» — HEAD ветки `fork-updates-m1` (итог вехи fork-updates-m1, принята с одним
  известным падением). Клон снимается с СЛЕДУЮЩЕГО коммита — коммита этой спеки и каталога
  `docs/specs/fork-updates-m2-probes/`; других коммитов между BASE_SHA и HEAD клона нет.
- Исполнитель: Codex (`cx`), назначен координатором. Мутации по тестам вехи гоняет
  противоположный исполнитель (Qwen). Исправления внутри вехи — тому же Codex.
- Цель владельца: Codex исправляет все падения тестов после переноса изменений из форков;
  rspec полностью зелёный (0 failures; pending — только уже существующие, с причиной),
  `bundle install` и сборка фронта работают.

## 2. Где работать

- Только одноразовый клон, созданный `make_clone.sh`, рабочая ветка `fork-updates-m2`.
  Живое дерево `/home/deploy/github/chaskiq` не трогать.
- git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root. На хост ничего
  не ставить (никаких gem/bundle/npm/yarn/pip/apt на хосте).
- В клоне есть upstream-тег `1.0.0` (`7f072d051590ddd2303e3339e35a61069cb17511`) и вся
  история main — это единственные источники кода плагинов. Refs форков в клоне нет; ничего
  из форков не брать.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (из `docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.5 + libpq + node/npm + ts-node 10.9.2 |
| гемы | `$HOME/.cache/chaskiq-m1/bundle` (BUNDLE_PATH, общий кэш) | `bundle install` для гейта |
| кэш yarn | `$HOME/.cache/chaskiq-m1/yarn` | `yarn install` в Docker |
| `node_modules/` | в клоне (gitignored), скопирован из клона m1 (тот же `yarn.lock`) | ts-node в спеках (`spec/support/graphql_queries.rb`), сборка фронта |
| образы | `postgres:14-alpine`, `redis:5-alpine`, `node:16.20.2-bullseye-slim` | гейт, фронт |

Команды, которыми работать (из корня клона):

```bash
# bundler; lock меняется только так, точечно
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -v "$HOME/.cache/chaskiq-m1/bundle:/bundle" -v "$PWD:/app" -w /app chaskiq-test:m1 \
  bundle lock --conservative --update <гемы>   # или bundle install после правки Gemfile
# полный строгий rspec (postgres+redis поднимает сам, ~4 мин)
bash docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh
# один файл спеков
bash docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh --only spec/controllers/api/v1/hooks/slack_spec.rb
```

## 3. Задача и почему

После вехи fork-updates-m1 гейт даёт `431 examples, 122 failures, 29 pending`. Все 122 —
отсутствие плагинов appstore в `app/services/message_apis/` (каталог в `.gitignore`, upstream
раздаёт плагины только с платного `appstore.chaskiq.io` по `CHASKIQ_APPSTORE_TOKEN`; токена
нет, API без токена отвечает 401). Плюс одно плавающее падение и два дефекта m1, найденных
ревью Codex. Веха делает suite полностью зелёным честно: подключает исходники плагинов из
upstream-истории, а не глушит тесты.

Что сломается и чинится в этой же вехе: восстановленные плагины 2023 года написаны под
Faraday 1 и под старый формат каталога (описания пакетов жили в `lib/app_packages_catalog.rb`);
сейчас Faraday 2.15 (m1) и каталог читает `MessageApis::<X>::Api.definition_info`. Обе
несовместимости правятся в коде плагинов. Восстановленные плагины становятся отслеживаемыми и
грузятся в production (`eager_load`) — production обязан загружаться (AC-005).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-18 командами в Docker (клон m1 и отдельный клон-проба от BASE_SHA):

1. Гейт m1 на BASE_SHA: `examples=431 failures=122 pending=29 errors_outside=0`; набор
   падений совпадает с `docs/specs/fork-updates-m1-probes/rspec_baseline.txt`
   (0 базовых падений починилось). Группы: hooks-спеки slack 18, zapier 13, twilio 10,
   pipedrive 10, twitter 9, telegram 8, dialog_360 8, vonage 7, message_bird 7, messenger 6,
   telnyx_sms 5, zoom 3, calendly 3, openai 2, twilio_phone 1; graphql app_package_integration 7,
   models/app_package_integration 3, graphql conversations 1 («with package»), app_user 1
   («full contact enrichment»).
2. Откуда плагины в upstream: `.github/workflows/ruby.yml` перед rspec делает
   `bundle exec rails packages:download_and_install["2.1.10"]` с секретом
   `CHASKIQ_APPSTORE_TOKEN` (`lib/tasks/utils.rake` → `Plugins::TarDownloader`, качает tar с
   `https://appstore.chaskiq.io/api/v1/download-plugins`, кладёт в `app/services/message_apis/<x>/`,
   `Plugin.load_plugin_and_create_packages_from_fs`). Не гем, не submodule, не фикстура.
   `curl https://appstore.chaskiq.io/api/v1/list-releases?token=` → 401.
3. Upstream переписал историю main весной 2023: в текущей истории main каталогов slack/twilio/…
   нет вовсе, но upstream-тег `1.0.0` (`7f072d05`, 2023-03-03, `git ls-remote upstream
   refs/tags/1.0.0` совпадает) содержит все нужные плагины: slack, twilio, twilio_phone,
   pipedrive, twitter, telegram, dialog360, vonage, message_bird, messenger, telnyx_sms, zoom,
   calendly, open_ai, full_contact (23 файла .rb, ~6.8 тыс. строк, только Ruby, без eval/system/
   обратных кавычек). Zapier в новом формате (с `definition_info`, `PROVIDER`) есть в истории
   main: коммит `07b747ae` «Plugin installation (#928)» — родитель `dfd2aabc` «removed (#929)».
   Лицензия тега та же, что у репо (AGPL + Commons Clause, `LICENSE.txt`).
4. Hooks-спеки с тега 1.0.0 почти не менялись (`git diff --shortstat 1.0.0 main`): calendly,
   pipedrive, twilio_phone, zapier, zoom, models/app_package_integration, app_user — без
   изменений; dialog_360/message_bird/messenger/telegram/telnyx_sms/vonage — по 1–2 строки
   (#936 block manager); slack/twilio/twitter/openai — 9–21 строка (#935 Dante3);
   graphql app_package_integration/conversations — заметно (#978). То есть спеки — правда
   upstream, плагины подгоняются под них, а не наоборот.
5. Формат каталога сейчас: `AppPackagesCatalog.update_all` → `Plugin.restore_plugins_from_fs`
   обходит все папки `app/services/message_apis/*` и для каждой зовёт
   `"MessageApis::#{File.basename(dir).camelize}::Api".constantize.definition_info`
   (`app/models/plugin.rb`). Описания пакетов (name, capability_list, tag_list, description,
   icon, state, definitions, иногда oauth/urls) в теге 1.0.0 лежат в
   `lib/app_packages_catalog.rb` (`git show 1.0.0:lib/app_packages_catalog.rb`, метод
   `packages`) — оттуда их и переносить в `self.definition_info` каждого плагина.
6. ПРОБА (клон от BASE_SHA, НЕ веха): папки 15 плагинов из тега 1.0.0 + zapier из `07b747ae`
   скопированы как есть, к каждому `api.rb` механически дописан `definition_info` из каталога
   1.0.0. Результат полного гейта: `examples=431 failures=24 pending=30 errors_outside=0` — 98 из 122
   починились без единой правки кода плагинов. Остаток 24: 18× `Faraday::Error: :basic_auth is not
   registered on Faraday::Request` (twilio 10, vonage 7, graphql conversations 1 — Faraday 2 убрал
   `request :basic_auth`, замена `request :authorization, :basic, user, pass`); 6× `NoMethodError …
   for nil` (`inject` — twitter 3, messenger 1; `map` — twitter `api.rb:194 send_message` 1;
   `find` — dialog_360 1) — формат контента после Dante3/block manager (#935/#936), под который
   upstream уже обновил спеки. Pending стал 30: в `twilio_phone_spec.rb:148` внутри примера есть
   `pending("not implemented specs")`, до него доходит только с загруженным плагином — это
   существующий pending upstream, он внесён в `pending_allowed.txt`. Пробные правки C и D (ниже)
   на том же клоне: `m2_prod_boot.sh` → PASS (включая eager_load восстановленных плагинов),
   `m2_runtime_probe_spec.rb` → 6/6 (SES-правка пробы: `config.action_mailer.ses_settings =
   { credentials: creds, region: zone }` + `delivery_method = :ses` — доставка через адаптер со
   стабами прошла, region и ключ дошли) (без правки D — 4 падения), `bundle install` добавил в lock
   ровно `aws-actionmailer-ses 1.2.0`, `aws-sdk-ses 1.102.0`, `aws-sdk-sesv2 1.107.0`; пробник
   целостности на этом дереве краснел только на campaign_spec
7. `spec/models/campaign_spec.rb:109` («template compilation will render subscriber
   attributes») — ПЛАВАЮЩИЙ тест, бампы гемов ни при чём: имя подписчика —
   `Faker::Name.unique.name`, Mustache `{{name}}` всегда HTML-экранирует (`CGI.escapeHTML`,
   `'` → `&#39;`). Mustache 1.1.1 и faker 3.2.1 (git `7cf0bbb9`) в lock BASE и m1 одинаковы.
   Замер в Docker: `Mustache.render("{{name}}", name: "Dee O'Keefe")` → `Dee O&#39;Keefe`;
   в `faker/lib/locales/en/name.yml` есть O'Connell/O'Conner/O'Hara/O'Keefe/O'Kon/O'Reilly;
   30 из 2000 `Faker::Name.name` содержат апостроф (~1.5% на прогон). Повторный гейт на том же
   коммите m1 этот тест прошёл.
8. Дефект m1 №1 (ревью Codex, воспроизведён): m1 поднял `aws-sdk-rails` 3.9.0 → 5.2.0, где нет
   `Aws::Rails.add_action_mailer_delivery_method`. Ветка SES в `config/environments/production.rb`
   (срабатывает при любом `SMTP_DELIVERY_METHOD`, кроме `smtp`, то есть по умолчанию) и
   аналогичная в `development.rb` падают при загрузке: production-загрузка офлайн с фиктивными
   AWS-переменными → `NoMethodError: undefined method 'add_action_mailer_delivery_method' for
   module Aws::Rails` (production.rb:129); та же загрузка с `SMTP_DELIVERY_METHOD=smtp` проходит
   (`DM=smtp EL=true`). Официальная замена — гем AWS `aws-actionmailer-ses` (rubygems: 1.2.0 от
   2026-05-21; зависимости `actionmailer >= 7.1.0`, `aws-sdk-ses ~> 1, >= 1.50.0`,
   `aws-sdk-sesv2 ~> 1, >= 1.34.0`); README: `config.action_mailer.delivery_method = :ses` и
   `config.action_mailer.ses_settings = { region: … }` (или `:ses_v2` / `ses_v2_settings`).
   Предположение: `ses_settings` принимает `credentials:` (передаётся в `Aws::SES::Client.new`) —
   сверить по исходнику гема 1.2.0 в кэше бандла.
9. Дефект m1 №2 (ревью Codex): в `config/initializers/rack_attack.rb` результат `JSON.parse`
   используется как Hash (`parsed["grant_type"]`), ловится только `JSON::ParserError`.
   JSON-тело `null` даёт `NoMethodError`, `[]` — `TypeError` прямо в middleware → 500 и запрос
   не учитывается в троттлинге.
10. Остальные мажоры m1 (devise 4.9.3 → 5.0.4, faraday 1 → 2, rack-cors 1 → 2, propshaft 0.7 → 1.3,
    dotenv 2 → 3, google-cloud-* , rubocop-rspec 2 → 3 и др.) на текущих спеках новых падений не
    дали (гейт m1). Новые транзитивные гемы `anonymous_loader`/`auth-sanitizer` пришли с
    oauth2 2.1.0 (тот же автор/организация ruby-oauth) — легитимны.

Предположения (не проверены): что адаптация плагинов под Faraday 2 обходится без новых гемов,
кроме `faraday-multipart` (в теге 1.0.0 dialog360 упоминает `Faraday::UploadIO` в комментарии);
что graphql-спеки app_package_integration/conversations проходят после появления пакетов.

## 5. Что сделать

Коммиты — по смыслу, сообщения ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Плагины appstore из upstream-истории.**
1. ПЕРВЫЙ коммит вехи (сразу после коммита спеки) — дословное восстановление, без единой
   правки: `git checkout 7f072d051590ddd2303e3339e35a61069cb17511 -- app/services/message_apis/<x>`
   для slack, twilio, twilio_phone, pipedrive, twitter, telegram, dialog360, vonage, message_bird,
   messenger, telnyx_sms, zoom, calendly, open_ai, full_contact; `git checkout
   07b747ae00ba170883fcf36a0baef174de337305 -- app/services/message_apis/zapier`; в `.gitignore`
   — исключения, чтобы эти 16 папок отслеживались (например `!app/services/message_apis/slack/`
   и `!app/services/message_apis/slack/**`). Больше ничего в этом коммите. Проверяет AC-004.
2. Следующими коммитами — адаптация ТОЛЬКО внутри этих 16 папок: `self.definition_info` для 15
   плагинов из `git show 1.0.0:lib/app_packages_catalog.rb` (по одному хешу на плагин, имя пакета
   = CamelCase папки, как ждёт `Plugin.load_plugin_and_create_packages_from_fs`); совместимость с
   Faraday 2 и текущим кодом (`MessageApis::BasePackage`, `MessageApis::BlockManager`, Dante3),
   пока соответствующие спеки не зелёные. Плагины, не нужные спекам, не добавлять.
   Обязательно перенести upstream-правку #917 «less permissions on slack app» (`cfa689e8`,
   вышла после тега 1.0.0, в клоне её нет): в `slack/api.rb#oauth_authorize`
   `user_scope: "channels:history,channels:write,channels:read"` (вместо
   `"chat:write,channels:history,channels:write,groups:write,channels:read,groups:read,mpim:read,im:read"`,
   `scope:` без изменений), а в `definition_info` Slack у обоих полей «Slack channel for Leads and
   Visitors.» — `required: false`. Других upstream-правок плагинов после 1.0.0 нет
   (`git diff 1.0.0 35bc71b0` по 15 папкам — только эта строка).
3. Код приложения вне `app/services/message_apis/<16 папок>` ради плагинов не править; если без
   этого никак — контракт на невыполнимое (раздел 9).

**B. Плавающий campaign_spec.** В `spec/models/campaign_spec.rb`, пример «will render subscriber
attributes»: внутри примера создать подписчика с фиксированным именем, например
`named = app.add_user(email: "dee.okeefe@example.com", properties: { name: "Dee O'Keefe" })`, и
проверять `expect(campaign.mustache_template_for(named)).to include("Dee O&#39;Keefe")`; Faker в
этом примере не использовать. Экранирование в HTML-письме —
правильное поведение, код приложения и шаблон не трогать. Остальные примеры файла не менять.

**C. SES после aws-sdk-rails 5.** Оставить aws-sdk-rails 5.x, добавить `gem "aws-actionmailer-ses",
"~> 1.2"`, lock — `bundle lock --conservative` / `bundle install` (новые гемы в lock — только из
списка AC-003). В SES-ветках `production.rb` и `development.rb` заменить
`Aws::Rails.add_action_mailer_delivery_method(:ses, credentials:, region:)` на API нового гема с
теми же credentials и region (`delivery_method = :ses` + `ses_settings`, или `:ses_v2` +
`ses_v2_settings`). Ветку SMTP и умолчания из m1 не трогать.

**D. Rack::Attack и не-объектный JSON.** В `config/initializers/rack_attack.rb` grant_type из
JSON брать только если разобранное тело — Hash; иначе считать «не refresh» (запрос учитывается).
Любая ошибка разбора не должна выпускать исключение из middleware. Добавить в существующий
`spec/requests/rack_attack_spec.rb` случаи `null` и `[]` (новых файлов в `spec/` не заводить). Троттлинг 20/час, пути и исключение
refresh_token — как в m1.

## 6. Не трогать

- Всё вне списка критерия AC-008. В частности: `app/` вне 16 папок плагинов, `lib/`, `db/`,
  `config/` (кроме `production.rb`, `development.rb`, `rack_attack.rb`), `package.json`,
  `yarn.lock`, workflows, `Dockerfile*`, `docker-compose.yml`, `config.ru`.
- Всё, что принесла m1, не откатывать: версии гемов в lock (кроме `aws-*` ради пакета C),
  globalize/roadie-rails, rack-attack и его троттлинг, письма Devise (`devise.rb`,
  `Agent#send_devise_notification`), SMTP-умолчания, puma.rb, CI, `.gitattributes`, axios.
  Если откат чего-то из m1 кажется неизбежным — контракт на невыполнимое, с причиной в отчёте.
- Существующие спеки: удалять, переименовывать, skip-ать (`xit`, `skip`, `pending`, метаданные
  `:skip`), ослаблять ассерты запрещено. Изменять можно ТОЛЬКО `spec/models/campaign_spec.rb`
  (пакет B) и `spec/requests/rack_attack_spec.rb` (пакет D, только добавлять). Новые файлы в
  `spec/` (в том числе `spec/support/`), правки `spec/rails_helper.rb`, `spec/spec_helper.rb`,
  `.rspec` и любая фильтрация примеров через конфигурацию RSpec запрещены.
- `docs/specs/fork-updates-m1*`, `docs/specs/fork-updates-m2.md`, `docs/specs/fork-updates-m2-probes/**`
  — уже закоммичены постановщиком; не править, не удалять, не перекоммичивать (AC-008, sha256).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq
  (вредоносный код: eval в `esbuild.config.mjs`, стилер через `.vscode/tasks.json`). Запрещены:
  `.vscode/`, workflows на self-hosted runner, `skip_client_authentication_for_password_grant`,
  закоммиченные `.env*` (кроме `.env.example`), чужой брендинг, `eval`/`new Function` в JS,
  невидимые Unicode-символы, git- и path-источники в Gemfile, любые новые гемы вне списка AC-003.
- Не брать токен appstore, не ходить в `appstore.chaskiq.io`, не звать `packages:download_and_install`.
- Не апгрейдить Rails (7.2.1.1 остаётся), не делать `bundle update` без списка гемов.

## 7. Критерии приёмки

Команды запускаются из корня клона. Образы и кэши — раздел 2. BASE —
`28a28676eb19b4d99a2907cb83249d98fc03b190`.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме (свежий BUNDLE_PATH), пробник зависимостей m1 зелёный (rails 7.2.1.x, snyk-границы m1 соблюдены).
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m1-probes/m1_deps_probe.rb"'`

- **AC-002** — полный rspec строго зелёный: процесс rspec завершился кодом 0, 0 failures, 0 ошибок вне примеров, выполнены все 431 пример BASE (список examples_base.txt), pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh`

- **AC-003** — целостность: в lock не изменилась ни одна версия гема BASE (кроме aws-*), новые гемы только aws-actionmailer-ses/aws-sdk-ses/aws-sdk-sesv2/faraday-multipart/multipart-post, package.json и yarn.lock не тронуты, ни одна спека не удалена, не добавлена и не пропущена, правки существующих спек только в двух разрешённых файлах, campaign-пример детерминирован (фиксированное имя, экранированное ожидание, без Faker), в Slack применена правка 917 с урезанным user_scope, инварианты безопасности m1 на месте, вызова add_action_mailer_delivery_method нет.
  `python3 -I docs/specs/fork-updates-m2-probes/m2_integrity_probe.py 28a28676eb19b4d99a2907cb83249d98fc03b190`

- **AC-004** — первый рабочий коммит вехи дословно восстанавливает 16 папок плагинов из upstream-тега 1.0.0 и коммита 07b747ae (плюс .gitignore), все 16 api.rb отслеживаются в HEAD.
  `bash -c 'r=$(git rev-list --reverse 28a28676eb19b4d99a2907cb83249d98fc03b190..HEAD | sed -n 2p) && test -n "$r" && for d in slack twilio twilio_phone pipedrive twitter telegram dialog360 vonage message_bird messenger telnyx_sms zoom calendly open_ai full_contact; do git diff --quiet 7f072d051590ddd2303e3339e35a61069cb17511 "$r" -- "app/services/message_apis/$d" && test -n "$(git ls-files "app/services/message_apis/$d/api.rb")" || exit 1; done && git diff --quiet 07b747ae00ba170883fcf36a0baef174de337305 "$r" -- app/services/message_apis/zapier && test -z "$(git diff --name-only "$r^" "$r" | grep -v -x -E "[.]gitignore|app/services/message_apis/(slack|twilio|twilio_phone|pipedrive|twitter|telegram|dialog360|vonage|message_bird|messenger|telnyx_sms|zoom|calendly|open_ai|full_contact|zapier)/.+")"'`

- **AC-005** — production загружается офлайн (eager_load, все плагины): без SMTP_DELIVERY_METHOD метод доставки ses или ses_v2 с region и credentials из ENV и рабочим адаптером (доставка со стабами AWS проходит), с smtp — smtp.
  `bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh`

- **AC-006** — Rack::Attack на JSON-телах null, массив, строка, число не падает, не отдаёт 500 и учитывает запрос; refresh_token по-прежнему не считается.
  `bash docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb`

- **AC-007** — пробник рантайма m1 (Rack::Attack один раз, троттлинг 20/час, письма Devise в очереди, guard таблицы plugins) и пробник дерева (невидимый Unicode, eval, .vscode, self-hosted, .env, брендинг, источники lock-файлов) зелёные.
  `bash -c 'bash docs/specs/fork-updates-m1-probes/rspec_gate.sh --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && python3 -I docs/specs/fork-updates-m2-probes/m2_tree_probe.py 28a28676eb19b4d99a2907cb83249d98fc03b190'`

- **AC-008** — вне разрешённых путей ничего не изменено, спеки и пробники постановщика не тронуты (sha256).
  `bash -c 'test "$(git log --format=%H 28a28676eb19b4d99a2907cb83249d98fc03b190..HEAD -- docs/specs | wc -l)" = 1 && git diff --quiet 28a28676eb19b4d99a2907cb83249d98fc03b190 HEAD -- docs/specs/fork-updates-m1.md docs/specs/fork-updates-m1-probes && printf "%s\n" "200c0c4fc3c5d2df365055eedd8896f32d1c4c7208cb3dbbc6ceb3654564ee1f  docs/specs/fork-updates-m2-probes/examples_base.txt" "51099bba153b2f74d1fdc15ebdb2a953852884c85ac61b759c0d8fcbc05de7a4  docs/specs/fork-updates-m2-probes/m2_integrity_probe.py" "65f6c520f5ccaf37e80abc1eba6baa2896c381f4e31efcd799aa11d2286dfa63  docs/specs/fork-updates-m2-probes/m2_prod_boot.sh" "8372cfd2c967824f3e566597d86b0cdaeacfdc6f7d3f2fb5a234ff149ac95f19  docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb" "e1d5f57de731c873ea6743f537dbd37e1ba3aa7976da46f167aeaa47c7b7c2a6  docs/specs/fork-updates-m2-probes/m2_tree_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m2-probes/pending_allowed.txt" "e2c872cadc779a7a8e241a4fa4d5cca0288637ac21a24bb32c55b4c67574db18  docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only 28a28676eb19b4d99a2907cb83249d98fc03b190...HEAD | grep -v -x -E "[.]gitignore|Gemfile|Gemfile[.]lock|config/environments/production[.]rb|config/environments/development[.]rb|config/initializers/rack_attack[.]rb|app/services/message_apis/(slack|twilio|twilio_phone|pipedrive|twitter|telegram|dialog360|vonage|message_bird|messenger|telnyx_sms|zoom|calendly|open_ai|full_contact|zapier)/.+|spec/.+|docs/specs/fork-updates-m2[.]md|docs/specs/fork-updates-m2-probes/.+")"'`

- **AC-009** — фронт собирается из lock (frozen).
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e YARN_CACHE_FOLDER=/ycache -v "$HOME/.cache/chaskiq-m1/yarn:/ycache" -v "$PWD:/app" -w /app node:16.20.2-bullseye-slim sh -c "yarn install --frozen-lockfile --non-interactive --silent && yarn build"'`

- **AC-010** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-001, AC-007 (рантайм m1 + дерево),
AC-008, AC-009, AC-010 зелёные; AC-002 красный (122 падения), AC-003 красный (нет рабочих
коммитов / campaign / add_action_mailer_delivery_method), AC-004 красный (нет рабочего коммита),
AC-005 красный (NoMethodError add_action_mailer_delivery_method), AC-006 красный (исключение на
теле null).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила, раздел «Автономное
перекрёстное ревью»). Коротко: коммит → REVIEW_SHA; исполнитель Codex → ревьюеры `agy` +
`qwen`, оба параллельно на `28a28676eb19b4d99a2907cb83249d98fc03b190..REVIEW_SHA`; один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только
обёртка, путь абсолютный:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base 28a28676eb19b4d99a2907cb83249d98fc03b190 --range 28a28676eb19b4d99a2907cb83249d98fc03b190..<REVIEW_SHA> --exclude docs/specs/fork-updates-m2.md --exclude "docs/specs/fork-updates-m2-probes/**" --exclude "app/services/message_apis/**" --exclude Gemfile.lock --context "chaskiq fork-updates-m2: плагины appstore восстановлены из upstream-тега 1.0.0 (папки app/services/message_apis/* исключены из диффа: дословное восстановление проверяет AC-004, адаптацию смотри сам: git -C <клон> diff <первый рабочий коммит>..<REVIEW_SHA> -- app/services/message_apis), SES через aws-actionmailer-ses, rack-attack на не-объектном JSON, детерминированный campaign_spec; только чтение"`

(то же для `qwen`). Восстановленный код плагинов (~7 тыс. строк) в дифф ревью не влезает
(потолок 100 КБ), поэтому исключён целиком; адаптационные правки ревьюеры читают сами по
команде из контекста. Gemfile.lock — сгенерированный, его состав проверяют AC-001 и AC-003.
Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m2.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m2-probes/**
REVIEW_EXCLUDE: app/services/message_apis/**
REVIEW_EXCLUDE: Gemfile.lock

Контекст ревьюерам: не ушёл ли дифф за раздел 6; не ослаблены ли спеки; SES-ветка с теми же
credentials/region; rack-attack не выпускает исключений; адаптация плагинов не тащит сеть,
eval и чужие источники.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 10: AC-001…AC-010.
`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная
ошибка в `note`. Обходить несовместимость запрещено. В `note` AC-002 — итоговые числа
examples/failures/pending; в `note` AC-004 — SHA восстановительного коммита и размер
адаптации (`git diff --shortstat <он>..HEAD -- app/services/message_apis`).

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m2.md>",
  "base_sha": "28a28676eb19b4d99a2907cb83249d98fc03b190",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m2.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- спека падает так, что починка требует правки кода приложения вне 16 папок плагинов и трёх
  файлов `config/` из раздела 6, или правки существующего теста вне двух разрешённых файлов;
- зелёный rspec недостижим без отката чего-то из m1 (назови гем/файл и падающие спеки);
- плагину нужен гем вне списка AC-003 или сеть во время тестов;
- нужного плагина нет ни в теге 1.0.0, ни в истории main;
- образ, кэш или сервисы из раздела 2 недоступны (Docker, сеть до rubygems);
- `aws-actionmailer-ses` не даёт сохранить credentials/region SES-ветки.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, ставить `pending` без причины,
отключать проверки безопасности из m1, подменять окружение и глушить коды возврата в командах.

## 10. Стыки

Следующим вехам: suite зелёный, плагины appstore — отслеживаемый код в
`app/services/message_apis/` (обновление через appstore по-прежнему перезапишет их,
`AppPackage#frozen?` защищает). Rails 8 — отдельная веха. Продовый `Dockerfile` этой вехой не
проверялся. Мажоры m1 (devise 5, faraday 2, aws-sdk-rails 5, propshaft 1, rack-cors 2,
dotenv 3) покрыты только текущими спеками и пробой production-загрузки.
