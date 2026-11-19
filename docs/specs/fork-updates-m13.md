# fork-updates-m13 — rack 2.2.25 → 3.2.8

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m13.md`.
- BASE_SHA: `ad0bad62929bd0b38e10b6f729430e7074927433` — сейчас HEAD `main`; веха запускается ПОСЛЕ влития fork-updates-m12.
- BASE плавающий: если до запуска `main` уйдёт вперёд (а он уйдёт — сначала вливается m12),
  постановщик коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-010).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Мутации по новым тестам потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: rack 3.2.x (последний stable — 3.2.8 от 2026-10-30 по rubygems), rack-session 2,
  rackup 2, rack-protection 4; сырые Rack-ответы приложения по спецификации Rack 3; поведение
  HTTP (health, OAuth-токены, Sidekiq Web, Rack::Attack и IP клиента за прокси, несколько
  cookie в ответе, AnyCable RPC) неотличимо от rack 2; старый том гемов docker-compose не ломает
  запуск.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m13`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.

Что делает постановщик ДО запуска (после влития m12, на `main`; строго по порядку — клон
снимается ПОСЛЕДНИМ, когда всё ниже уже закоммичено в `main`):

1. Кэш гемов: `cp -a $HOME/.cache/chaskiq-m6/bundle $HOME/.cache/chaskiq-m13/bundle` (новый набор
   гемов пишется сюда; кэш m6 остаётся нетронутым для параллельных вех).
2. Список примеров BASE на чистом checkout `main` с влитой m12:
   `bash docs/specs/fork-updates-m13-probes/rspec_gate_m13.sh --write-base` (сьют должен быть
   зелёным). Сейчас в файле — заглушка из 528 примеров `main` 7e5523d3, без примеров m12.
3. Закоммитить в `main` одним коммитом постановщика: новый `examples_base.txt`, его sha256 в
   AC-010 и строку BASE_SHA ← HEAD `main` (коммит кода, на котором снят список). Только после
   этого коммита — `make_clone.sh`: исполнитель получает спеку и пробники уже закоммиченными и
   сам в `docs/specs` не коммитит ничего (AC-010).
4. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker | ruby 3.3.14 (bookworm), libpq, libvips 8.14, node 18, ts-node |
| гемы | `$HOME/.cache/chaskiq-m13/bundle` (копия кэша m6) | гейт и пробники m13; `bundle update` пишет сюда |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках, сборка фронта на стенде |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники |

`bundle update` — в Docker, например:
`docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m13/bundle:/bundle" -v "$PWD:/app" -w /app chaskiq-test:m1 bundle update rack --conservative`.

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m13-probes
bash $P/rspec_gate_m13.sh                     # полный строгий rspec + ноль деприкейшенов, ~6 мин
bash $P/rspec_gate_m13.sh --only <spec-файл>  # один файл
bash $P/m13_boot_probe.sh                     # 4 среды на rack 3.2, без warning-строк
bash $P/m13_http_probe.sh                     # Rack::Lint + puma + AnyCable RPC: BASE (rack 2) и дерево отвечают одинаково (~6 мин)
bash $P/m13_compose_volume_probe.sh           # старый том гемов compose не прячет гемы нового образа
python3 -I $P/m13_mutation_gate.py            # мутанты по новому тесту
```

## 3. Задача и почему

rack 2.2 получает только исправления безопасности; Rails 8.1, puma 6, Sidekiq 7.3, Rack::Attack
6.8 и rack-cors 2 работают с rack 3. Что держит rack < 3 (обратные зависимости из `Gemfile.lock`
BASE и метаданные rubygems, проверено 2026-11-19):

| Блокер | Сейчас | Нужно | Ограничение |
|---|---|---|---|
| `Gemfile` | `gem "rack", "~> 2.2", ">= 2.2.25"` | `gem "rack", "~> 3.2", ">= 3.2.8"` | прямой пин |
| rack-session (actionpack) | 1.0.2, `rack < 3` | 2.1.2 | `rack >= 3.0.0` |
| rackup (railties) | 1.0.0, `rack < 3` (+ webrick) | 2.3.1 | `rack >= 3`, webrick уходит |
| rack-protection (omniauth) | 3.2.0, `rack ~> 2.2` | 4.2.2 | `rack >= 3.0.0, < 4`, + logger |
| omniauth | 2.4.1 | 2.4.2 (так решает bundler `--conservative`) | `rack >= 2.2.8` |
| sidekiq 7.3.10 | `rack >= 2.2.4, < 3.3` | — | 3.2.x подходит, sidekiq не трогать |
| rack-attack 6.8.0 / rack-cors 2.0.2 / oauth2 / warden / rack-test 2.1.0 | `< 4` / `>= 2` | — | без изменений |
| puma 6.4.3 (`~> 6.0`) | нет зависимости от rack | — | rack 3 поддерживается с puma 6.0 |
| anycable-rails 1.5.6 | нет зависимости от rack | — | без изменений |

Изменения Rack 3, которые касаются кода приложения: имена заголовков ответа — только в нижнем
регистре (Rack::Lint: `uppercase character in header name`), `Rack::Session` вынесен в гем
rack-session, `Rack::Server`/`rackup` — в гем rackup, `rack.input` может быть не перематываемым,
и **заголовок `Forwarded`**: rack 2.2.25 (`Rack::Request#forwarded_for`) читает только
`X-Forwarded-For`, а rack 3.2.8 по умолчанию `Rack::Request.forwarded_priority = [:forwarded,
:x_forwarded]` — сначала `Forwarded`, и `x_forwarded_proto_priority = [:proto, :scheme]` (в rack 2
сначала `X-Forwarded-Scheme`). `Rack::Attack` (лимит входа m1, ключ `req.ip`) за прокси, который
дописывает `X-Forwarded-For`, но не трогает `Forwarded`, получил бы IP из заголовка клиента —
лимит обходится подменой `Forwarded: for=<любой>`.

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker, черновик поверх черновика m12 (в веху не идёт):

1. `bundle update rack --conservative` после правки `Gemfile`: изменились ровно rack 3.2.8,
   rack-session 2.1.2, rackup 2.3.1, rack-protection 4.2.2, omniauth 2.4.2, ушёл webrick 1.8.2.
2. Полный rspec на rack 3.2.8: 528 примеров / 0 failures / 30 pending, без новых предупреждений.
   Загрузка 4 сред (`m13_boot_probe.sh`) зелёная: `RACK=3.2.8 RS=2.1.2 RU=2.3.1`.
3. `config/middleware/maintenance_mode.rb:10` отдаёт `'Content-Type'` — Rack::Lint на rack 3
   падает (`uppercase character in header name: Content-Type`); после `'content-type'` зелёный.
   `lib/rack/health_check.rb` (заголовки `{}`) Lint проходит.
4. `m13_http_probe.sh` на черновике: BASE (rack 2.2.25) и дерево (rack 3.2.8) под puma production
   ответили одинаково: health 200, токен по JSON-телу и по форме 200 (тело доходит до doorkeeper
   после чтения и `rewind` в Rack::Attack), неверный пароль 400 `invalid_grant`, Sidekiq Web 401
   без пароля и 200 с basic auth. С `'Content-Type'` пробник красный.
5. `m13_mutation_gate.py` на черновике: MM1, MM2, FW1, FW2 убиты.
6. RuboCop 1.92.3 / rubocop-rails 2.38.0 с rack 3 в lock: новый офенс
   `Rails/HttpStatusNameConsistency` в `api/graphql_controller.rb:55` (`:unprocessable_entity`);
   спека «will return 422» (`spec/controllers/api/graphql_controller_spec.rb:131`) сторожит код.
7. `rack.input`: puma 6 всегда буферизует тело (StringIO/Tempfile), `req.body&.rewind` в
   `config/initializers/rack_attack.rb` работает; `Rack::Request.include GeocoderRequestOverride`
   (`config/initializers/geocoder_request.rb`) на rack 3 грузится.
8. `Forwarded` (проверено `m13_http_probe.sh` на черновике): без настройки дерево отдаёт
   `fwd_ip 1.2.3.4 http` (IP и схема из подменённых заголовков), лимит входа с постоянным
   `X-Forwarded-For` и разным `Forwarded: for=1.2.3.<n>` не срабатывает (21-й ответ не 429); с
   `config/initializers/rack_forwarded.rb` (раздел 5 п. 6) — `198.51.100.7 https` и 429, как BASE.
9. Несколько `Set-Cookie` через puma 6.4.3 на rack 3: `DELETE /agents/sign_out` вошедшего агента
   отдаёт две отдельные строки `set-cookie` (`_chaskiq_session` и удаление `remember_agent_token`)
   — так же, как BASE. `POST /agents/sign_in` для проверки не годится: на BASE он отвечает 500
   (`Agents::SessionsController#create` зовёт `Doorkeeper::AccessToken.find_or_create_for`
   позиционными аргументами, а doorkeeper 5.8 ждёт ключевые) — существующий дефект, вне вехи.
10. AnyCable: gRPC RPC-сервер `bundle exec anycable` (production) поднимается в том же контейнере;
   `Connect` с `?token=<валидный doorkeeper-токен>` → `SUCCESS`, идентификатор — агент; с
   неизвестным токеном → `ERROR` («invalid user»); одинаково на rack 2 и rack 3. anycable-go не
   поднимался: RPC-сторона (где Rails строит Rack-env из запроса) проверена напрямую по gRPC.
11. `docker-compose.yml` монтирует именованный том `bundle` поверх `/usr/local/bundle`; Docker
   заполняет том из образа только при создании, дальше том главнее образа, и после пересборки
   образа с rack 3 у оператора со старым томом `bundle exec` не найдёт rack 3.2.8.
   `m13_compose_volume_probe.sh` на черновике с томом `bundle_rack3`: BASE видит старый том,
   дерево — гемы образа.


Предположения: прокси перед установками ставят `X-Forwarded-For`/`X-Forwarded-Proto` и не
ставят `Forwarded` (иначе порядок rack 2 и так был единственным рабочим); WebSocket-сторона
anycable-go от версии rack не зависит.

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. `Gemfile`: `gem "rack", "~> 3.2", ">= 3.2.8"` вместо пина 2.2; больше строк `Gemfile` не
   менять. `Gemfile.lock` — в Docker `bundle update rack --conservative` на кэше m13; изменятся
   только гемы из раздела 3 (AC-006 сверяет список). BUNDLED WITH, PLATFORMS, RUBY VERSION — как в BASE.
2. `config/middleware/maintenance_mode.rb`: имя заголовка `content-type` (значение то же).
   Другие сырые Rack-ответы (`lib/rack/*.rb`, `config/middleware/*.rb`) — только нижний регистр.
3. `app/controllers/api/graphql_controller.rb:55` `status: :unprocessable_entity` →
   `status: :unprocessable_content` (тот же код 422; на rack ≥ 3.1 старое имя устарело, и
   RuboCop `Rails/HttpStatusNameConsistency` даёт офенс — AC-005).
4. Прочие падения загрузки/тестов/пробников на rack 3 — точечно в `app/`, `lib/`, `config/`,
   без изменения поведения.
5. Новый тест `spec/middleware/maintenance_mode_spec.rb` (имена примеров — маркеры AC-004):
   пример со словом «Lint» — `Rack::Lint.new(Middleware::MaintenanceMode.new(nil))` на
   `Rack::MockRequest.env_for("/")` проходит, тело прочитано и закрыто; пример «maintenance
   page» — статус 200, `headers["content-type"] == "text/html"`, тело равно
   `public/maintenance.html`.
6. `config/initializers/rack_forwarded.rb` — порядок rack 2 для заголовков прокси, ровно эти строки
   кода (комментарии и magic comment можно):
   ```ruby
   Rack::Request.forwarded_priority = [:x_forwarded]
   Rack::Request.x_forwarded_proto_priority = %i[scheme proto]
   ```
   Новый тест `spec/lib/rack_forwarded_spec.rb` (маркеры AC-004): пример со словами «Forwarded
   header» — `Rack::Request` с `REMOTE_ADDR` 10.0.0.1, `X-Forwarded-For: 198.51.100.7` и
   `Forwarded: for=1.2.3.4` → `ip == "198.51.100.7"`; пример со словом «scheme» —
   `X-Forwarded-Scheme: https`, `X-Forwarded-Proto: http`, `Forwarded: proto=http` → `scheme == "https"`.
7. `docker-compose.yml`: том поверх `/usr/local/bundle` — новое имя `bundle_rack3` (строка тома в
   `x-backend` и ключ в `volumes:`), больше ничего. `CHANGELOG.md` — запись вехи (rack 3, порядок
   заголовков прокси) с разделом для операторов: после `git pull` нужен `docker compose build`;
   старый том `<проект>_bundle` больше не монтируется, его можно удалить
   (`docker volume rm <проект>_bundle`), новый заполнится из образа при первом запуске; откат —
   старый коммит снова монтирует старый том.
8. RuboCop на `main` строгий (любой офенс валит CI; `.rubocop.yml` + `.rubocop_todo.yml`,
   `inherit_mode: merge: Exclude`): после вехи `bundle exec rubocop` по ВСЕМУ дереву — ноль
   офенсов (AC-005). Версия RuboCop в этой вехе не меняется (не в списке гемов), поэтому
   `.rubocop.yml`/`.rubocop_todo.yml` не трогать и `rubocop:disable` не добавлять (AC-006).

## 6. Не трогать

- Всё вне списка AC-010. В частности: `Dockerfile*`, `docker-compose.yml` кроме тома (раздел 5
  п. 7), workflows, `bin/*`
  (включая `bin/ci-local`), `.githooks/`, `db/`, `package.json`, `yarn.lock`, `config.ru`
  (на rack 3 работает без правок).
- Гемы вне списка раздела 3, в том числе puma, sidekiq, rack-attack, rack-cors, rails, Ruby.
- Всё, что принесли m1–m12, не откатывать (Rack::Attack, вендоренный nightfury, health check).
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено — только добавлять. Новые файлы в `spec/support/`, правки `spec/spec_helper.rb`,
  `spec/rails_helper.rb`, `.rspec` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-010, sha256).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq;
  новые git- и path-источники в Gemfile запрещены.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec строго зелёный и без единой строки деприкейшена или warning: rspec завершился 0, 0 failures, 0 ошибок вне примеров, примеров не меньше, чем в списке BASE, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m13-probes/rspec_gate_m13.sh`

- **AC-002** — production, staging, development и test грузятся на rack 3.2.8+, rack-session 2 и rackup 2 без единой строки деприкейшена или warning.
  `bash docs/specs/fork-updates-m13-probes/m13_boot_probe.sh`

- **AC-003** — сырые Rack-ответы проходят Rack::Lint, а puma production на rack 3 отвечает так же, как BASE на rack 2: health, OAuth-токен по JSON и по форме, неверный пароль, Sidekiq Web, IP и схема за прокси при подменённом Forwarded и лимит входа по нему, две отдельные set-cookie при выходе агента, AnyCable RPC Connect с валидным и чужим токеном.
  `bash docs/specs/fork-updates-m13-probes/m13_http_probe.sh`

- **AC-004** — новые тесты убивают мутанты: заголовок с заглавными буквами, не та страница обслуживания, порядок Forwarded и X-Forwarded-Proto как в rack 3.
  `python3 -I docs/specs/fork-updates-m13-probes/m13_mutation_gate.py`

- **AC-005** — lock ставится во frozen-режиме, rubocop по всему дереву без офенсов и без предупреждений о конфиге.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true -v "$HOME/.cache/chaskiq-m13/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && bundle exec rubocop --cache false > /tmp/rc.out 2>&1; rc=\$?; tail -3 /tmp/rc.out; test \$rc = 0 && ! grep -Eiq \"supports plugin|deprecat|warning:\" /tmp/rc.out"'`

- **AC-006** — целостность: Gemfile меняет только строку rack, lock меняет только гемы rack-стека, rack 3.2.8+, заголовки в нижнем регистре, порядок заголовков прокси rack 2, rubocop-конфиг не тронут, спеки только дополнены, supply-chain чистый, том гемов compose переименован и старый том не прячет гемы нового образа, CHANGELOG для операторов.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m13-probes/m13_integrity_probe.py $B && python3 -I docs/specs/fork-updates-m4-probes/m4_tree_probe.py $B && bash docs/specs/fork-updates-m13-probes/m13_compose_volume_probe.sh'`

- **AC-007** — нет регрессий рантайма m1–m5: пробные спеки m1, m2, m3, m4 и m5 зелёные на rack 3.
  `bash -c 'G=docs/specs/fork-updates-m13-probes/rspec_gate_m13.sh; bash $G --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $G --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb && bash $G --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb'`

- **AC-008** — нет регрессий загрузки m1–m12: пробники загрузки m2, m3, m4 и m12, redis из compose, puma и конфиг m1.
  `bash -c 'export CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m13/bundle CHASKIQ_M6_BUNDLE=$HOME/.cache/chaskiq-m13/bundle; bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh && bash docs/specs/fork-updates-m12-probes/m12_boot_probe.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-009** — живой стенд production на rack 3: фронт собирается, ассеты отдаются, лимит входа срабатывает на всех вариантах пути.
  `bash -c 'CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m13/bundle bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh'`

- **AC-010** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "90f99a2135ba2973d838d72531ae2de8ad7c693562ee00413dfee82fc1b8a214  docs/specs/fork-updates-m13-probes/examples_base.txt" "68e1421f1c70bcabae7f625490436035eb76e169c5df097dae24b5dcb503637d  docs/specs/fork-updates-m13-probes/m13_boot_probe.sh" "59d6c0b970c5e5d17bdb72178d8436e078334fb5e27c88a6425ae26777b6ff87  docs/specs/fork-updates-m13-probes/m13_compose_volume_probe.sh" "7ebe51325fdbbdbff2d7d7549be91973cf57a6e7e8f3223458f65c02bf390e61  docs/specs/fork-updates-m13-probes/m13_http_probe.sh" "6d5d8e5864b0a4ab61fe5a675153423f3a0f5e462e2efaefdb2c7ab107d5854e  docs/specs/fork-updates-m13-probes/m13_integrity_probe.py" "5a09d1c396bc0a611d861314528534d1c970e3da1fd1d7bf4e6a5c6633ce2866  docs/specs/fork-updates-m13-probes/m13_mutation_gate.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m13-probes/pending_allowed.txt" "842b2ac911de01999ca888f53ee0a539cc5248813caadabde7b6bc28e2fec4e6  docs/specs/fork-updates-m13-probes/rspec_gate_m13.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "Gemfile|Gemfile[.]lock|docker-compose[.]yml|CHANGELOG[.]md|app/.+|lib/.+|config/.+|spec/.+")"'`

- **AC-011** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (после влития m12 и шагов раздела 2): AC-001, AC-005, AC-007, AC-008,
AC-009, AC-010, AC-011 зелёные; AC-002 красный (`RACK=2.2.25`); AC-003 красный (`tree
Gemfile.lock is not on rack 3.2`); AC-004 красный (`spec/middleware/maintenance_mode_spec.rb
missing`); AC-006 красный (rack 2.2 в Gemfile и lock, `'Content-Type'`, нет
`rack_forwarded.rb`, том `bundle`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m13.md --exclude "docs/specs/fork-updates-m13-probes/**" --context "chaskiq fork-updates-m13: rack 2.2.25 -> 3.2.8 (rack-session 2, rackup 2, rack-protection 4, omniauth 2.4.2), заголовки сырых Rack-ответов в нижнем регистре, порядок заголовков прокси rack 2 (Forwarded не читается), том compose bundle_rack3; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m13.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m13-probes/**

Контекст ревьюерам: перематываемость тела запроса (Rack::Attack), IP клиента за прокси, cookie и сессии, заголовки;
не ушёл ли дифф за раздел 6; lock меняет только rack-стек.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 11: AC-001…AC-011. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-004 — строка по каждому мутанту.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m13.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m13.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- зависимость не разрешается без смены гема вне списка раздела 3, новой git/path-зависимости,
  смены Ruby или BUNDLED WITH;
- поведение HTTP на rack 3 отличается от rack 2 (AC-003) и это нельзя исправить в `app/`, `lib/`,
  `config/` без изменения поведения;
- зелёный rubocop недостижим без правки `.rubocop*.yml` или `rubocop:disable`;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки), в том числе
  `examples_base.txt` не соответствует BASE;
- образ, кэш `chaskiq-m13`, `node_modules` или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, глушить вывод и коды
возврата, подменять окружение.

## 10. Стыки

- **Ruby 3.3 → 4.0** — следующая веха (fork-updates-m14), запускается после влития этой.
- puma 6.4.3 → 8.x (последняя на rubygems 8.1.2) — отдельная веха; rack 3 её не требует.
- `POST /agents/sign_in` отвечает 500 и на BASE (раздел 4 п. 9) — отдельная мелкая правка.
- rack-cors 2 → 3, sidekiq 7 → 8 — отдельно.
