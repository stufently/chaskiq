# fork-updates-m14 — Ruby 3.3.14 → 4.0.10

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19. Спека — `docs/specs/fork-updates-m14.md`.
- BASE_SHA: `d07bc92f9fbab58272ceb44a7853b2306fe9cc0d` — сейчас HEAD `main`; веха запускается ПОСЛЕ влития fork-updates-m13.
- BASE плавающий: если до запуска `main` уйдёт вперёд (а он уйдёт — сначала вливаются m12 и m13),
  постановщик коммитит новое значение в строку BASE_SHA и только потом снимает клон. Команды
  критериев считают `B=$(git merge-base HEAD @{u})` сами. В `report.json` поле `base_sha` равно
  значению строки BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-010).
- **Ревью — от BASE_SHA шапки, не от `B`:** `review_run.sh --base` и начало диапазона
  `--range` берут значение строки BASE_SHA (после переноса постановщиком оно совпадает с `B`):
  `accept_run.py` ищет квитанции ревью по фиксированному `base_sha` из `report.json`.
- Исполнитель: Codex (`cx`). Независимую проверку потом гоняет противоположный исполнитель
  (Qwen, панель `qw2`); исправления внутри вехи — тот же Codex.
- Цель: приложение, тесты, CI и продовый образ на Ruby 4.0.10 и bundler 4.0.20, без единого
  деприкейшена или warning; всё, что живые установки на Ruby 3.3 положили в кэш, cookie и токены,
  читается, и наоборот — то, что выдал Ruby 4, читает старый `main` на Ruby 3.3 (откат, поэтапный
  выкат); `bin/ci-local` (образ раннеров ubuntu-26.04, GCC 15) зелёный на Ruby 4.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m14`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push в origin запрещён,
  работу заберёт постановщик через `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.

Что делает постановщик ДО запуска (после влития m13, на `main`; строго по порядку — клон
снимается ПОСЛЕДНИМ, когда всё ниже уже закоммичено в `main`):

1. Убедиться, что ни одна другая веха не гоняет `chaskiq-test:m1`
   (`python3 ~/.claude/skills/executor-milestone/scripts/run_journal.py list --project .`):
   шаг 4 переводит этот тег на Ruby 4, и пробники всех вех (m1–m13) дальше идут на Ruby 4.
2. Список примеров BASE — пока `chaskiq-test:m1` ещё Ruby 3.3, на чистом checkout `main` с
   влитыми m12 и m13: `CHASKIQ_M14_BUNDLE=$HOME/.cache/chaskiq-m13/bundle bash docs/specs/fork-updates-m14-probes/rspec_gate_m14.sh --write-base`
   (сьют должен быть зелёным). Снят постановщиком: 670 примеров `main` d07bc92f.
3. Закоммитить в `main` одним коммитом постановщика: новый `examples_base.txt`, его sha256 в
   AC-010 и строку BASE_SHA ← HEAD `main` (коммит кода, на котором снят список). Только после
   этого коммита — `make_clone.sh`: исполнитель получает спеку и пробники уже закоммиченными и
   сам в `docs/specs` не коммитит ничего (AC-010).
4. Образ: `docker tag chaskiq-test:m1 chaskiq-test:m1-ruby3314`;
   `docker build -t chaskiq-test:m14 -f docs/specs/fork-updates-m14-probes/Dockerfile.test docs/specs/fork-updates-m14-probes`;
   `docker tag chaskiq-test:m14 chaskiq-test:m1`. Откат — `docker tag chaskiq-test:m1-ruby3314 chaskiq-test:m1`.
5. Кэш гемов: `mkdir -p $HOME/.cache/chaskiq-m14/bundle $HOME/.cache/chaskiq-m14-ci` (пустые: у
   Ruby 4 свой ABI-каталог `ruby/4.0.0`, из кэша m13 ничего не переносится; первый `bundle
   install` собирает нативные расширения, ~5 мин). Кэш `chaskiq-m13` остаётся — на нём
   BASE-сторона AC-003. `chaskiq-m14-ci` — отдельный `CI_LOCAL_CACHE` для AC-012, чтобы не
   делить кэш с pre-push хуком живого дерева.
6. Прогнать критерии на свежем клоне (раздел 7, «Ожидаемо на чистом клоне»).

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` (= `chaskiq-test:m14`) | `docs/specs/fork-updates-m14-probes/Dockerfile.test` | ruby 4.0.10 (trixie), libpq, libvips 8.16, ImageMagick 7, node 20, ts-node 10.9.2 |
| образ `chaskiq-test:m1-ruby3314` | старый `chaskiq-test:m1` | BASE-сторона AC-003 |
| гемы | `$HOME/.cache/chaskiq-m14/bundle` (новый), `$HOME/.cache/chaskiq-m13/bundle` | дерево / BASE |
| `node_modules/` | в клоне (gitignored), копия `$HOME/.cache/chaskiq-m6/node_modules` | ts-node в graphql-спеках, сборка фронта |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine`, `node:16.20.2-bullseye-slim` | гейт, пробники, стенд m3 |

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m14-probes
bash $P/rspec_gate_m14.sh                     # полный строгий rspec на Ruby 4 + ноль warning-строк
bash $P/rspec_gate_m14.sh --only <spec-файл>  # один файл
bash $P/m14_boot_probe.sh                     # 4 среды на Ruby 4.0.10, YJIT в production/staging
bash $P/m14_compat_probe.sh                   # 3.3 -> 4.0 и 4.0 -> 3.3: cookie/токены/кэш принимаются в обе стороны
bash $P/m14_compose_volume_probe.sh           # старый том гемов compose не прячет гемы нового образа
CI_LOCAL_CACHE=$HOME/.cache/chaskiq-m14-ci bin/ci-local   # как раннер: ubuntu-26.04, GCC 15, scout_apm
```

## 3. Задача и почему

Ruby 3.3 — EOL 2027-03-31. Проверка версий 2026-11-19:

- `curl -fsSL "https://endoflife.date/api/v1/products/ruby/"` + `jq '[.result.releases[] | select(.isMaintained and .isEol == false)] | max_by(.releaseDate)'`
  → ветка `4.0` (releaseDate 2025-12-25, isLts false, eolFrom 2029-03-31, latest 4.0.9 по
  endoflife.date — база отстаёт). Живые ветки: 4.0, 3.4 (EOL 2028-03-31), 3.3 (EOL 2027-03-31).
- GitHub `ruby/ruby` releases: v4.0.10 (2026-11-18, вместе с 3.4.13 и 3.3.14) — последний патч 4.0.
- Docker Hub `library/ruby`: тег `4.0.10-slim-trixie` есть (2026-11-19).
- ruby/setup-ruby: `ruby-builder-versions.json` содержит 4.0.10; релиз ruby-builder `ruby-4.0.10`
  несёт `ruby-4.0.10-ubuntu-26.04-x64.tar.gz`, sha256
  `d08c941aa89ddf5aa6bf2228daa8de21af25bab8b68a6e9f24f933b1d4c6d7d7` (дайджест из API релиза,
  перепроверен скачиванием).
- bundler: в Ruby 4.0.10 встроен 4.0.20 (последний на rubygems — 4.1.0). Берём 4.0.20, чтобы
  образы не скачивали другой bundler при каждом запуске; bundler 2.4.10 на Ruby 4 печатает
  `warning: already initialized constant Gem::Platform::JAVA`.

Места, где закреплена версия (по `main` 8dea3d52):

| Файл | Что | Станет |
|---|---|---|
| `Gemfile` | `ruby "3.3.14"` | `ruby "4.0.10"` |
| `.ruby-version` | `3.3.14` (читают workflows через setup-ruby и `bin/ci-local`) | `4.0.10` |
| `Gemfile.lock` | `RUBY VERSION ruby 3.3.14p208`, `BUNDLED WITH 2.4.10` | ruby 4.0.10, 4.0.20 |
| `Dockerfile`, `Dockerfile.development` | `ARG RUBY_VERSION=3.3.14` | 4.0.10 |
| `docker-compose.yml` | `RUBY_VERSION: '3.3.14'`, `BUNDLER_VERSION: '2.3.26'`; том `bundle_rack3:/usr/local/bundle` (после m13) | 4.0.10, 4.0.20; том `bundle_ruby4` (раздел 5 п. 7) |
| `hooks/build` | `RUBY_VERSION=3.3.14`, `BUNDLER_VERSION=2.3.26` | 4.0.10, 4.0.20 |
| `.github/workflows/{anchore-analysis,dockerimage,docker-image-ghcr}.yml` | `RUBY_VERSION=3.3.14`, `BUNDLER_VERSION=2.4.10` | 4.0.10, 4.0.20 |
| `bin/ci-local` (по `main` 352f8c09: строки 32, 33, 184) | `RUBY_BUILDER_VERSION=3.3.14`, `RUBY_BUILDER_SHA256=dc801dd9…`, `--build-arg BUNDLER_VERSION=2.4.10` (docker job) | 4.0.10, `d08c941a…`, 4.0.20 |
| `docs/specs/*-probes` | образ `chaskiq-test:m1` | пересобирает постановщик (раздел 2) |

## 4. Что проверено вживую, а что предположение

Черновик 2026-11-19 в Docker на `ruby:4.0.10-slim-trixie` (образ из `Dockerfile.test`), поверх
черновиков m12 и m13 (в веху не идёт):

1. `bundle install` на Ruby 4.0.10: падает сборка stringio 3.1.1 (`rb_io_extract_modeenc`) →
   3.2.0; minitest 5.25.1 требует ruby < 4.0 → bundler берёт 6.1.0. Нативные scout_apm 5.3.5,
   nokogiri 1.19.7, pg 1.5.4, ffi 1.16.3, sassc 2.4.0, google-protobuf 3.25.8, bootsnap 1.16.0
   собираются (GCC 14 в trixie); grpc 1.85.0 — готовый x86_64-linux-gnu, грузится.
2. Загрузка: `cannot load such file -- csv` (roo) и затем `ostruct` — гемы, ушедшие из default
   gems → `gem "csv", "~> 3.3"`, `gem "ostruct", "~> 0.6"` (rubygems: csv 3.3.7, ostruct 0.6.3).
3. Сьют: `NoMethodError: undefined method 'parse' for class CGI` в oauth 0.5.14
   (`request_proxy/net_http.rb:38`, Twitter-спека) — в Ruby 4.0 из стандартной библиотеки убрали
   CGI, кроме `cgi/escape`. oauth 1.1.9 (последний) делает то же. Решение: `gem "cgi", "~> 0.5"`
   (0.5.2 с rubygems возвращает `CGI.parse`; проверено), oauth не трогать.
4. Предупреждения при `-W:deprecated`: `literal string will be frozen in the future` —
   `app/services/dante/utils.rb:6,9` (`inject("")` + `<<`) и
   `app/services/message_apis/telnyx_sms/api.rb:213` (`phone.gsub!` по чужой строке), mustache
   1.1.1 (→ 1.1.3); `constant Net::HTTPSession is deprecated` — webmock 3.19.1 (→ 3.35.0);
   bundler 4: `[DEPRECATED] Platform :mingw, :mswin, :x64_mingw` (`Gemfile`, tzinfo-data →
   `platforms: %i[windows jruby]`) и `Found x64-mingw32 in lockfile` (`bundle lock
   --remove-platform x64-mingw32 x86-mingw32`).
5. С пп. 1–4 и `BUNDLED WITH 4.0.20`: полный rspec 528 / 0 failures / 30 pending, ноль
   warning-строк; `m14_boot_probe.sh` зелёный (`RUBY=4.0.10`, YJIT true в production/staging);
   `m14_compat_probe.sh` зелёный в обе стороны (по 14 проверок: BASE на Ruby 3.3.14 выдал —
   дерево на 4.0.10 приняло, и дерево на 4.0.10 выдало — BASE на 3.3.14 принял, включая
   Marshal-записи кэша, cookie сессии/remember и `CHASKIQ_VERIFIER`); продовый `Dockerfile` с
   `RUBY_VERSION=4.0.10 BUNDLER_VERSION=4.0.20` собрался вместе с `assets:precompile`.
6. RuboCop 1.92.3 «analyzing as Ruby 4.0» новых офенсов от Ruby 4 не дал; `+""` в
   `dante/utils.rb` с `inject` даёт `Style/EachWithObject` — писать сразу через
   `each_with_object(+"")` или `String.new`.
7. Флак `spec/mailers/campaign_spec.rb` (Faker-имя с апострофом) исправлен в `main` 352f8c09.
8. `docker-compose.yml` монтирует именованный том поверх `/usr/local/bundle`; Docker заполняет том
   из образа только при создании, дальше том главнее образа. У оператора с томом от Ruby 3.3 после
   пересборки образа на Ruby 4 в `/usr/local/bundle` остаются гемы `ruby/3.3.0`, и `bundle exec`
   падает. `m14_compose_volume_probe.sh` на черновике с томом `bundle_ruby4`: BASE видит старый
   том, дерево — гемы образа.

9. `bin/ci-local` (по `main` 352f8c09) с `RUBY_BUILDER_VERSION=4.0.10`, `RUBY_BUILDER_SHA256=d08c941a…`
   и `BUNDLER_VERSION=4.0.20` на черновике (поверх черновиков m12 и m13, с отдельным
   `CI_LOCAL_CACHE`): образ `chaskiq-ci-local:ruby-4.0.10-ubuntu-26.04` — gcc 15.2.0, ruby 4.0.10;
   `bundle install` собрал scout_apm 5.3.5 с `BUNDLE_BUILD__SCOUT_APM=--with-cflags=-std=gnu17`
   (`gem.build_complete` в `ruby/4.0.0/extensions`); `rubocop: clean`; rspec 542 / 0 failures /
   30 pending; `ci-local: all jobs passed (rubocop rspec)`. Первый прогон на устаревшем черновике
   дал офенсы старого `lib/nightfury` и флак campaign — оба ушли с актуальными m12 и `main`.

Предположения: продовая память с YJIT на Ruby 4 не замерялась; GitHub-раннеры ведут себя как
`bin/ci-local` (тот же образ ubuntu-26.04, тот же ruby-builder, те же флаги scout_apm).

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей.

1. Версии — все места из таблицы раздела 3 (Ruby 4.0.10, bundler 4.0.20,
   `RUBY_BUILDER_SHA256=d08c941aa89ddf5aa6bf2228daa8de21af25bab8b68a6e9f24f933b1d4c6d7d7`).
   Если к запуску в `main` появились новые места с версией Ruby/bundler — обновить и их (AC-005
   ищет `3.3.x`, `2.4.10`, `2.3.26` по дереву). Версии писать только эти, по памяти не подставлять.
2. `Gemfile`: `ruby "4.0.10"`; `gem "csv", "~> 3.3"`, `gem "ostruct", "~> 0.6"`,
   `gem "cgi", "~> 0.5"`; tzinfo-data — `platforms: %i[windows jruby]`. Другие добавляемые строки —
   только гемы, ушедшие из default gems Ruby 4 (AC-005 сверяет список).
3. `Gemfile.lock` — в Docker на образе Ruby 4 и кэше m14: `bundle install`/`bundle update <gem>
   --conservative` для stringio, minitest, webmock, mustache и новых гемов;
   `bundle lock --remove-platform x64-mingw32 x86-mingw32`; `BUNDLED WITH 4.0.20`. rack, rails,
   puma, rubocop, nokogiri, scout_apm, oauth не менять.
4. Код: убрать мутацию «будущих замороженных» строк — `app/services/dante/utils.rb`
   (`each_with_object(+"")` или `String.new`), `app/services/message_apis/telnyx_sms/api.rb`
   (`resolve_outbound_phone` не мутирует аргумент; `send_sms_message` один раз нормализует
   `channel_id = channel_id.delete("+")`, чтобы `to: "+#{channel_id}"` не стал `++…`). Если m11
   (Telnyx MMS) изменила этот файл — то же по смыслу в новом коде. Прочие предупреждения
   Ruby 4 — точечно в `app/`, `lib/`, `config/`, без изменения поведения.
5. RuboCop на `main` строгий (любой офенс валит CI; `.rubocop.yml` + `.rubocop_todo.yml`,
   `inherit_mode: merge: Exclude`): после вехи `bundle exec rubocop` по ВСЕМУ дереву на Ruby 4 —
   ноль офенсов (AC-004). Версия RuboCop не меняется, поэтому `.rubocop*.yml` не трогать,
   `rubocop:disable` не добавлять (AC-005). Если без новой версии RuboCop не обойтись — это
   контракт на невыполнимое; рост `.rubocop_todo.yml` без причины в `report.json` не принимается.
6. Новых тестов веха не требует (поведение не меняется); добавлять можно, менять существующие
   строки спек — нет.
7. `docker-compose.yml`: том поверх `/usr/local/bundle` — новое имя `bundle_ruby4` (строка тома в
   `x-backend` и ключ в `volumes:`), больше ничего, кроме версий п. 1. В `CHANGELOG.md` — запись
   вехи с разделом для операторов: после `git pull` нужен `docker compose build`; старый том
   `<проект>_bundle_rack3` больше не монтируется, его можно удалить
   (`docker volume rm <проект>_bundle_rack3`), новый заполнится из образа при первом запуске;
   откат на Ruby 3.3 — старый коммит снова монтирует старый том.
8. `bin/ci-local` на Ruby 4 зелёный (AC-012): rubocop + rspec в образе ubuntu-26.04 с ruby-builder
   4.0.10 и GCC 15, scout_apm собирается с флагами из BASE.

## 6. Не трогать

- Всё вне списка AC-010, в том числе `.githooks/`, `README.md`, `db/`,
  `package.json`, `yarn.lock`, `config.ru`.
- В `bin/ci-local` и workflows — только строки версий Ruby/bundler и sha256 (NODE_MAJOR, образы
  postgres/redis, флаги scout_apm и прочее как в BASE).
- Гемы вне раздела 5 п. 2–3; Rails, rack, puma; `config.load_defaults 8.1`.
- Всё, что принесли m1–m13, не откатывать.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять существующие строки
  запрещено. Новые файлы в `spec/support/`, правки `spec/spec_helper.rb`, `spec/rails_helper.rb`,
  `.rspec` запрещены.
- `docs/specs/**` — закоммичены постановщиком; не править (AC-010, sha256). Образы Docker не
  перетегировать (это делает постановщик).
- Запрещено брать что-либо из форков, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq;
  новые git- и path-источники в Gemfile запрещены.

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — полный rspec на Ruby 4 строго зелёный и без единой строки деприкейшена или warning: rspec завершился 0, 0 failures, 0 ошибок вне примеров, примеров не меньше, чем в списке BASE, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m14-probes/rspec_gate_m14.sh`

- **AC-002** — production, staging, development и test грузятся на Ruby 4.0.10+ с rack 3.2, YJIT в production и staging, без единой строки деприкейшена или warning.
  `bash docs/specs/fork-updates-m14-probes/m14_boot_probe.sh`

- **AC-003** — cookie, токены, signed id, GlobalID, записи кэша и счётчик принимаются в обе стороны: выданное BASE на Ruby 3.3 принимает дерево на Ruby 4.0, выданное деревом на Ruby 4.0 принимает BASE на Ruby 3.3; новые токены сохраняют символьные ключи.
  `bash docs/specs/fork-updates-m14-probes/m14_compat_probe.sh`

- **AC-004** — lock ставится во frozen-режиме на Ruby 4, rubocop по всему дереву без офенсов и без предупреждений о конфиге.
  `bash -c 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true -v "$HOME/.cache/chaskiq-m14/bundle:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "ruby -v | grep -q \"^ruby 4[.]0[.]\" && bundle install --quiet && bundle exec rubocop --cache false > /tmp/rc.out 2>&1; rc=\$?; tail -3 /tmp/rc.out; test \$rc = 0 && ! grep -Eiq \"supports plugin|deprecat|warning:\" /tmp/rc.out"'`

- **AC-005** — целостность: все места версии на 4.0.10 и 4.0.20, старых версий в дереве нет, Gemfile и lock меняют только разрешённое, rubocop-конфиг не тронут, спеки не ослаблены, supply-chain чистый, старый том гемов compose не монтируется поверх гемов нового образа.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m14-probes/m14_integrity_probe.py $B && python3 -I docs/specs/fork-updates-m4-probes/m4_tree_probe.py $B && bash docs/specs/fork-updates-m14-probes/m14_compose_volume_probe.sh'`

- **AC-006** — продовый образ собирается на Ruby 4.0.10 и bundler 4.0.20 (включая assets:precompile), в нём Ruby 4.0.10 и Rails 8.1.
  `bash -c 'docker build -q --build-arg APP_ENV=production --build-arg NODE_ENV=production --build-arg RUBY_VERSION=4.0.10 --build-arg PG_MAJOR=15 --build-arg NODE_MAJOR=26 --build-arg YARN_VERSION=1.13.0 --build-arg BUNDLER_VERSION=4.0.20 -t chaskiq-m14-prod:probe . >/dev/null && docker run --rm chaskiq-m14-prod:probe ruby -v | grep -q "^ruby 4[.]0[.]10 " && docker run --rm chaskiq-m14-prod:probe bundle exec rails -v | grep -q "^Rails 8[.]1[.]"'`

- **AC-007** — нет регрессий рантайма m1–m5 на Ruby 4: пробные спеки m1, m2, m3, m4 и m5 зелёные.
  `bash -c 'G=docs/specs/fork-updates-m14-probes/rspec_gate_m14.sh; bash $G --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $G --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb && bash $G --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb'`

- **AC-008** — нет регрессий загрузки m1–m13 на Ruby 4: пробники загрузки m2, m3, m4, m12 и m13, redis из compose, puma и конфиг m1.
  `bash -c 'export CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m14/bundle CHASKIQ_M6_BUNDLE=$HOME/.cache/chaskiq-m14/bundle CHASKIQ_M13_BUNDLE=$HOME/.cache/chaskiq-m14/bundle; bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh && bash docs/specs/fork-updates-m12-probes/m12_boot_probe.sh && bash docs/specs/fork-updates-m13-probes/m13_boot_probe.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-009** — живой стенд production на Ruby 4: фронт собирается, ассеты отдаются, лимит входа срабатывает на всех вариантах пути.
  `bash -c 'CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m14/bundle bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh'`

- **AC-010** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "c9dc94c8d8436d2a8c4e9b0d4d06c31384e3276f53a98810c7b425c1667a3b40  docs/specs/fork-updates-m14-probes/Dockerfile.test" "2ddc24df34c5c6398772ae1f8463376997d5799a225a9b3509a70d3b1f9d35ae  docs/specs/fork-updates-m14-probes/examples_base.txt" "39ecf03fc3bc1e9365edbdaa6779bab31785c422fa63364baae7a21c7d505f6f  docs/specs/fork-updates-m14-probes/m14_boot_probe.sh" "f6da07241e0a753838adb9510d462cfd60b14c8d7bd5b69181d2e630fd771edc  docs/specs/fork-updates-m14-probes/m14_compat_probe.sh" "e1ab74983fd72352c5ea141abfa32d676ecab905a9b1a8338068201e4e2bbe5d  docs/specs/fork-updates-m14-probes/m14_compose_volume_probe.sh" "c0680c70a1e5dc7a57a5c41f170cf07108d8fe8fa55cffc1fde262feb4be61b2  docs/specs/fork-updates-m14-probes/m14_integrity_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m14-probes/pending_allowed.txt" "9fd17b5f13e593692fb0e24168c950ca65b89e21cd585696a2411ab071d66562  docs/specs/fork-updates-m14-probes/rspec_gate_m14.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "Gemfile|Gemfile[.]lock|[.]ruby-version|Dockerfile|Dockerfile[.]development|docker-compose[.]yml|hooks/build|[.]github/workflows/.+|bin/ci-local|CHANGELOG[.]md|app/.+|lib/.+|config/.+|spec/.+")"'`

- **AC-011** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

- **AC-012** — bin/ci-local как раннер (ubuntu-26.04, GCC 15, ruby-builder) зелёный на Ruby 4.0.10: rubocop и полный rspec, scout_apm собран.
  `bash -c 'export CI_LOCAL_CACHE=$HOME/.cache/chaskiq-m14-ci; grep -qx "4[.]0[.]10" .ruby-version && bin/ci-local && ls "$CI_LOCAL_CACHE"/bundle-*/ruby/4.0.0/extensions/*/4.0.0/scout_apm-*/gem.build_complete'`

Ожидаемо на чистом клоне (после влития m13 и шагов раздела 2): AC-010, AC-011 зелёные; AC-012
красный (`.ruby-version` ещё 3.3.14); AC-001,
AC-002, AC-004, AC-007, AC-008, AC-009 красные (`Your Ruby version is 4.0.10, but your Gemfile
specified 3.3.14` — образ уже Ruby 4, дерево ещё нет); AC-003 красный (`tree Gemfile does not pin
ruby 4.0`); AC-005 красный (старые версии во всех местах таблицы); AC-006 красный (bundler 2.4.10
и stringio 3.1.1 на Ruby 4).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<BASE_SHA>..REVIEW_SHA` (BASE_SHA — значение
строки шапки, НЕ вычисленный `B`: по нему `accept_run.py` ищет квитанции); один заход
исправлений → FINAL_SHA; одна проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <BASE_SHA> --range <BASE_SHA>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m14.md --exclude "docs/specs/fork-updates-m14-probes/**" --context "chaskiq fork-updates-m14: Ruby 3.3.14 -> 4.0.10, bundler 4.0.20, csv/ostruct/cgi как гемы, stringio/minitest/webmock/mustache, без мутации замороженных строк, версии в Dockerfile/compose/hooks/workflows/bin/ci-local, том compose bundle_ruby4; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m14.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m14-probes/**

Контекст ревьюерам: все ли места версии обновлены; не изменилось ли поведение при правке
строк (telnyx `to:`); не ушёл ли дифф за раздел 6.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 12: AC-001…AC-012. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-001 — итоговые examples/failures/pending; в `note` AC-005 — список изменённых гемов.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m14.md>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m14.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- гем не ставится или не грузится на Ruby 4.0.10 без смены гема вне раздела 5 (rack, rails, puma,
  rubocop, nokogiri, scout_apm, oauth), новой git/path-зависимости или патча чужого гема;
- предупреждение Ruby 4 идёт из гема, у которого нет исправленной версии (опиши строку, гем,
  вариант);
- зелёный rubocop недостижим без новой версии RuboCop, правки `.rubocop*.yml` или `rubocop:disable`;
- образ `chaskiq-test:m1` не Ruby 4.0.10, нет кэшей, `chaskiq-test:m1-ruby3314`, `node_modules`
  или сервисов из раздела 2; `examples_base.txt` не соответствует BASE (дефект спеки);
- `bin/ci-local` красный на Ruby 4 из-за сборки нативного гема (scout_apm и др.) на GCC 15, а
  флагов из BASE не хватает — опиши ошибку компилятора; флаги и версии гемов вне раздела 5 не
  менять;
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, глушить вывод
(`Warning[:deprecated] = false`, `$VERBOSE = nil`, `RUBYOPT`), глушить коды возврата, подменять
окружение.

## 10. Стыки

- После влития все пробники вех m1–m13 гоняются на Ruby 4 (тег `chaskiq-test:m1`); откат —
  `docker tag chaskiq-test:m1-ruby3314 chaskiq-test:m1`.
- Продовые установки: образ на trixie уже был; Marshal-записи кэша, cookie и токены читаются в обе
  стороны 3.3 ↔ 4.0 (AC-003) — откат и поэтапный выкат на общей БД/redis безопасны.
- Операторы docker-compose: новый том `bundle_ruby4` (CHANGELOG, раздел 5 п. 7).
- puma 8, sidekiq 8, redis-rb 5 — отдельные вехи.
