# fork-updates-m6 — Rails 7.2.1.1 → 8.1.4.1 (гемы и совместимость, defaults прежние)

## 1. Шапка

- Репозиторий: `chaskiq` (локально `/home/deploy/github/chaskiq`), ветка `main`. Дата спеки:
  2026-11-19.
- BASE_SHA: `eba9ac87d36380e37f66d372a1d3b148c3ab7e25` «Update CHANGELOG for fork-updates-m5» (m4 и m5 влиты). Поверх него в
  `main` лежат только коммиты постановщика, правящие эту строку; клон снят с последнего из них, и
  `B` указывает на него. В `report.json` поле `base_sha` = значение этой строки (как его читает
  `accept_run.py`), а команды критериев считают `B` сами. **BASE плавающий:** веха запускается после влития m5
  (пересылка вложений и SSRF в Twitter). Все команды вычисляют BASE сами:
  `B=$(git merge-base HEAD @{u})` — коммит `main`, от которого снят клон (`make_clone.sh
  --work-branch fork-updates-m6` ставит upstream `origin/main`). Если `main` ушёл вперёд,
  постановщик ДО создания клона коммитит в `main` новое значение BASE_SHA в этой строке; после
  этого `B` совпадает с BASE_SHA. Коммиты исполнителя в `docs/specs` запрещены (AC-008).
- Исполнитель: Codex (`cx`). Мутации и приёмка — постановщик; исправления внутри вехи — тот же Codex.
- Цель: приложение на Rails 8.1.4.1 (последний патч единственной поддерживаемой ветки), с
  прежними `config.load_defaults 7.0`, тем же поведением и зелёными тестами/пробниками m1–m4.

## 2. Где работать

- Только одноразовый клон из `make_clone.sh`, рабочая ветка `fork-updates-m6`. Живое дерево
  `/home/deploy/github/chaskiq` не трогать. git pull в клоне не делать; push запрещён,
  постановщик заберёт работу `git fetch` из клона.
- Docker — только под своим uid (`--user "$(id -u):$(id -g)"`), без sudo/root; сервисные
  postgres/redis без bind-mount можно без `--user`. На хост ничего не ставить.

Что кладёт постановщик ДО запуска:

| Что | Где | Зачем |
|---|---|---|
| образ `chaskiq-test:m1` | локальный Docker (`docs/specs/fork-updates-m1-probes/Dockerfile.test`) | ruby 3.3.5, libpq, libvips 8.14, node |
| гемы Rails 8.1 | `$HOME/.cache/chaskiq-m6/bundle` (копия кэша m1 + гемы черновика 8.1) | гейт и пробники m6; `bundle update` пишет сюда |
| `node_modules/` | в клоне (gitignored) | ts-node в graphql-спеках, сборка фронта на стенде |
| образы | `postgres:14-alpine`, `redis:8.10-alpine`, `redis:5-alpine` | гейт, пробники m3/m4 |

`bundle update` — в Docker (сеть нужна для rubygems и git-гемов), например:
`docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$HOME/.cache/chaskiq-m6/bundle:/bundle" -v "$PWD:/app" -w /app chaskiq-test:m1 bundle update rails --conservative`.

Команды (из корня клона):

```bash
P=docs/specs/fork-updates-m6-probes
bash $P/rspec_gate_m6.sh                    # полный строгий rspec на кэше m6, ~5 мин
bash $P/rspec_gate_m6.sh --only <spec-файл> # один файл
bash $P/m6_boot_probe.sh                    # загрузка 4 сред на 8.1 без деприкейшенов
```

## 3. Задача и почему

Rails 7.2 вне поддержки с августа 2026 (endoflife.date). Из поддерживаемых веток осталась только
8.1 (8.0 — EOL). Прыжок делается в один заход, но **только фреймворк**: `load_defaults` остаётся
7.0. Подъём defaults меняет поведение: SHA256-генератор ключей обнуляет все зашифрованные
cookie и сессии, меняются сериализация cookie, форматы кэша и т. п. Это отдельная веха m7 с
ротацией cookie (раздел 10).

## 4. Что проверено вживую, а что предположение

Проверено 2026-11-19 в Docker, черновик в отдельном клоне от `9fa8d4e1` (код тот же, что в BASE; в веху не идёт):

1. Версии: endoflife.date `rails` — живая только 8.1 (latest 8.1.4.1, EOL 2027-10-10); rubygems:
   rails 8.1.4.1 (2026-11-04) требует ruby >= 3.2.0. Ruby 3.3 поддерживается до 2027-03-31,
   проект на 3.3.5 — Ruby в этой вехе НЕ меняется (`Gemfile` `ruby "3.3.5"`, `.ruby-version`).
2. Разрешение зависимостей (`bundle update … --conservative`, BUNDLED WITH 2.4.10 не меняется):
   - `acts-as-taggable-on` из git `mbleigh/acts-as-taggable-on` (11.0.0) требует activerecord < 8.0 →
     заменить на rubygems `~> 13.0` (13.0.0: activerecord >= 7.1, < 8.2);
   - `gem "uri", "0.12.5"`: activesupport 8 требует uri >= 0.13.1 → `~> 1.1` (1.1.2);
   - Active Storage 8.1 при загрузке требует ruby-vips >= 2.2.1 (было 2.1.4; libvips в образе 8.14 ≥ 8.13)
     и mini_magick >= 5.1 (`gem "mini_magick", "~> 4.8"` → `~> 5.1`; 5.4.0, image_processing 1.14.0).
     Прямых вызовов MiniMagick в app/lib/config нет;
   - jbuilder 2.11.5 требует удалённый `active_support/proxy_object` → 2.15.1.
   Итог черновика: изменены ровно гемы из allowlist `m6_deps_probe.rb`, rack остаётся 2.2.x,
   globalize 7.1, devise 5.0.4, doorkeeper 5.6.9, roadie-rails 3.4.0 без изменений.
3. Код: `app/models/preview_card.rb:10` `enum type: {…}` — keyword-синтаксис удалён в Rails 8
   (ArgumentError при загрузке) → `enum :type, {…}`. Других keyword-enum в app/lib нет.
4. Деприкейшены: `config/application.rb:12` `Dotenv::Railtie` (dotenv 3.2) →
   `Dotenv::Rails.load if defined?(Dotenv::Rails)`; `spec/rails_helper.rb:49` singular
   `config.fixture_path` (rspec-rails) → `config.fixture_paths = [Rails.root.join("spec/fixtures")]`.
   Прочие предупреждения при загрузке — от гемов вне вехи (`URLcrypt.key=`, `Redis.current` в
   nightfury, `cypress_folder=`), без префикса `DEPRECATION WARNING` — их не трогать.
5. Черновик с пп. 2–4: полный rspec 479 примеров / 0 failures / 30 pending (те же pending, что в
   m4); `m6_boot_probe.sh` зелёный (production/staging/development/test на 8.1.4.1, LD=7.0,
   VIPS=true/true), с возвращённым `Dotenv::Railtie` — красный по деприкейшену; все пробники
   m1–m4 (runtime-спеки, загрузки, compose, puma, config) зелёные на кэше m6; живой стенд m3
   (yarn build, precompile, puma production): ассеты 15 МБ, лимит 21-го входа на всех вариантах пути.
6. Продовый `Dockerfile` (bullseye) libvips не ставит. Тогда ruby-vips падает с LoadError
   «…libvips…», Active Storage его глотает (`raise error unless error.message.match?(/libvips|ruby-vips/)`),
   проверено сообщением ffi в Docker: совпадает. variant_processor — `:mini_magick`
   (config/application.rb:54), ImageMagick в образе есть.
7. Пробник зависимостей m1 (`m1_deps_probe.rb`) жёстко держит rails 7.2.1.x и uri — в m6 он
   намеренно НЕ входит в критерии; его инварианты (кроме rails/uri) перенесены в `m6_deps_probe.rb`.
   `m4_integrity_probe.py` привязан к границам m4 (падает на «Gemfile changed») — тоже не входит,
   его инварианты перенесены в `m6_integrity_probe.py`.

Предположения: что `Rails.application.config.loaded_config_version` на 8.1 возвращает "7.0" для
`load_defaults 7.0` (на черновике — да); что m5 не трогает Gemfile/config — иначе перепроверить
AC-001/AC-007 на новом BASE.

## 5. Что сделать

Коммиты — по смыслу, ≤ 50 символов, imperative, без Co-Authored-By и подписей.

**A. Gemfile/Gemfile.lock** (только в Docker, `--conservative`):
1. `gem "rails", "~> 8.1.4", ">= 8.1.4.1"` вместо пина 7.2.1.1.
2. `gem "acts-as-taggable-on", "~> 13.0"` (rubygems) вместо git-источника mbleigh.
3. `gem "uri", "~> 1.1"`; `gem "mini_magick", "~> 5.1"`; ruby-vips >= 2.2.1 и jbuilder — через
   lock (`bundle update ruby-vips jbuilder --conservative`), отдельные строки в Gemfile не нужны
   (разрешена только `gem "ruby-vips", "~> 2.x"`, если без неё не разрешается).
4. Сменить версию можно только гемам из allowlist `m6_deps_probe.rb`; BUNDLED WITH, RUBY VERSION,
   rack 2.2.x, globalize, roadie-rails, devise, doorkeeper, sidekiq — как в BASE.
**B. Код:** `app/models/preview_card.rb` — `enum :type, { link: 0, photo: 1, video: 2, rich: 3 }`;
прочие ошибки загрузки/тестов Rails 8.1 — точечно в app/, lib/, config/ (не меняя поведение).
**C. Деприкейшены:** `config/application.rb` — `Dotenv::Rails.load if defined?(Dotenv::Rails)`;
`spec/rails_helper.rb` — ровно одна строка `config.fixture_path = …` → `config.fixture_paths = [Rails.root.join("spec/fixtures")]`.
**D. Не делать:** `config.load_defaults` остаётся `7.0`; `rails app:update`, новые
`new_framework_defaults_*`, правки `bin/*` без нужды — не запускать и не добавлять.

## 6. Не трогать

- Всё вне путей AC-008: `Dockerfile*`, `docker-compose.yml`, `package.json`, `yarn.lock`, `db/`,
  `.github/`, `config.ru`, `CHANGELOG.md`, `docs/`.
- `config.load_defaults 7.0` и `config/initializers/new_framework_defaults_*.rb`.
- Всё, что принесли m1–m4 (и m5, если влита): Rack::Attack, письма Devise, SES через
  aws-actionmailer-ses, SMTP без логина, puma.rb, CI, плагины и BlockManager, redis 8.10 в compose,
  пути ассетов.
- Существующие спеки: удалять, переименовывать, skip-ать, ослаблять или менять строки запрещено —
  только добавлять; единственное исключение — строка `fixture_path` (5 C). Новые файлы в
  `spec/support/`, правки `spec/spec_helper.rb`, `.rspec` запрещены.
- `docs/specs/**` — постановщика (sha256 пробников m6 в AC-008).
- Форки, особенно VooDooNoir/chaskiq и kreasialamteknologi/chaskiq, не трогать; новые git-
  и path-источники в Gemfile запрещены; `.vscode/`, `.env*` (кроме `.env.example`), невидимые
  Unicode-символы, `eval`/`new Function` в JS — запрещены.
- Ruby не менять; rack 3 не делать (отдельная веха).

## 7. Критерии приёмки

Команды — из корня клона. BASE вычисляется командой `git merge-base HEAD @{u}`.

- **AC-001** — Gemfile и lock ставятся с нуля во frozen-режиме, Rails 8.1.4.1+, сопутствующие гемы и инварианты m1 на месте, изменены только гемы из allowlist.
  `bash -c 'B=$(git merge-base HEAD @{u}) && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/tmp/fresh-bundle -e BUNDLE_FROZEN=true -e BUNDLE_JOBS=16 -e M6_BASE=$B -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle install --quiet && ruby docs/specs/fork-updates-m6-probes/m6_deps_probe.rb"'`

- **AC-002** — полный rspec строго зелёный: rspec завершился 0, 0 failures, 0 ошибок вне примеров, не меньше 479 примеров, выполнены все примеры BASE, pending только из разрешённого списка.
  `bash docs/specs/fork-updates-m6-probes/rspec_gate_m6.sh`

- **AC-003** — production, staging, development и test загружаются на Rails 8.1.4.1+ с load_defaults 7.0, защитой libvips и без единого деприкейшена.
  `bash docs/specs/fork-updates-m6-probes/m6_boot_probe.sh`

- **AC-004** — нет регрессий рантайма m1–m4: пробные спеки m1, m2, m3 и m4 зелёные.
  `bash -c 'G=docs/specs/fork-updates-m6-probes/rspec_gate_m6.sh; bash $G --only docs/specs/fork-updates-m1-probes/m1_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb && bash $G --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb && bash $G --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb'`

- **AC-005** — нет регрессий загрузки m1–m4: пробники загрузки m2, m3 и m4, redis из compose, puma и конфиг m1.
  `bash -c 'export CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle; bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh && bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh && bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh && docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"'`

- **AC-006** — живой стенд production: фронт собирается, ассеты отдаются, лимит входа срабатывает на всех вариантах пути.
  `bash -c 'CHASKIQ_M1_BUNDLE=$HOME/.cache/chaskiq-m6/bundle bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh'`

- **AC-007** — целостность: load_defaults 7.0, удалённые в Rails 8 конструкции убраны, Gemfile изменён только в разрешённых строках, спеки только дополнены, инварианты m1–m4 на месте, supply-chain чистый.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-m6-probes/m6_integrity_probe.py $B && python3 -I docs/specs/fork-updates-m4-probes/m4_tree_probe.py $B'`

- **AC-008** — вне разрешённых путей ничего не изменено, коммитов в docs/specs нет, пробники постановщика не тронуты (sha256).
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git log --format=%H $B..HEAD -- docs/specs)" && printf "%s\n" "fecc336ce81d7a7c1cfe9b67353cd10634d38279ee177a06a14a4c3c3d99222d  docs/specs/fork-updates-m6-probes/examples_base.txt" "fe5806e470435d8f2de2d3de6f440c5336a2ce95b80d28c76d06521b479486bd  docs/specs/fork-updates-m6-probes/m6_boot_probe.sh" "bc6cb5e388970ae6f3f6e6ac9121b318a6a7fd0a4cbb101339cd795b37383cf7  docs/specs/fork-updates-m6-probes/m6_deps_probe.rb" "6579ac19f27129bd70540dffc9262ac0b8393d5cc2ca75d9189b7afe25611d91  docs/specs/fork-updates-m6-probes/m6_integrity_probe.py" "7a1a51b777ce531a1213d8b222bd47f8b049728a8b640fae06d92859877bba17  docs/specs/fork-updates-m6-probes/pending_allowed.txt" "07054985b5231d9fcb6b4d6be15f8e22deba60840768d16f06ade6b256395a4b  docs/specs/fork-updates-m6-probes/rspec_gate_m6.sh" | sha256sum -c --quiet - && test -z "$(git diff --name-only $B...HEAD | grep -v -x -E "Gemfile|Gemfile[.]lock|config/.+|bin/.+|app/.+|lib/.+|spec/.+")"'`

- **AC-009** — дерево чистое.
  `bash -c 'test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

Ожидаемо на чистом клоне (проверено постановщиком): AC-002, AC-004, AC-005, AC-006, AC-008,
AC-009 зелёные; AC-001 красный (`rails must be >= 8.1.4.1`, acts-as-taggable-on из git, uri,
mini_magick, ruby-vips ниже порога); AC-003 красный (`RAILS=7.2.1.1`); AC-007 красный
(`Dotenv::Railtie`, keyword-enum в preview_card.rb, singular `fixture_path`).

## 8. Авторевью и контракт отчёта

Политика `cross-review-v1` (полный текст — `spec-template.md` скила). Коротко: коммит →
REVIEW_SHA; ревьюеры `agy` + `qwen` параллельно на `<B>..REVIEW_SHA` (B — из
`git merge-base HEAD @{u}`, подставить значение); один заход исправлений → FINAL_SHA; одна
проверка `REVIEW_SHA..FINAL_SHA`. Квитанции пишет только обёртка:

`bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial agy --clone <клон> --base <B> --range <B>..<REVIEW_SHA> --exclude docs/specs/fork-updates-m6.md --exclude "docs/specs/fork-updates-m6-probes/**" --context "chaskiq fork-updates-m6: Rails 7.2.1.1 -> 8.1.4.1 при load_defaults 7.0, acts-as-taggable-on 13 с rubygems, uri 1.1, mini_magick 5.1, ruby-vips 2.3, jbuilder 2.15, enum :type в PreviewCard, Dotenv::Rails, fixture_paths; только чтение"`

(то же для `qwen`). Исключения:

REVIEW_EXCLUDE: docs/specs/fork-updates-m6.md
REVIEW_EXCLUDE: docs/specs/fork-updates-m6-probes/**

Контекст ревьюерам: не изменилось ли поведение (defaults, cookie, сессии, сериализация); не ушёл
ли дифф за раздел 6; не ослаблены ли спеки; lock меняет только allowlist.

### Контракт отчёта

`report.json` в КОРНЕ клона, untracked. Записей в `criteria` ровно 9: AC-001…AC-009. `blocked` —
штатный исход, когда среда не даёт выполнить критерий: `"rc": null` и дословная ошибка в `note`.
В `note` AC-002 — итоговые examples/failures/pending; в `note` AC-001 — строка `changed:` пробника.

```json
{
  "schema_version": 2,
  "policy_id": "cross-review-v1",
  "spec_sha256": "<sha256 файла docs/specs/fork-updates-m6.md>",
  "base_sha": "<вывод git merge-base HEAD @{u}>",
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

После сборки — `python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py <клон> --spec docs/specs/fork-updates-m6.md --dry-run`, добиться кода 2.

## 9. Контракт на невыполнимое

Остановись, запиши `report-blocked.md` и доложи, НЕ обходя:
- зависимость не разрешается без смены гема вне allowlist, новой git/path-зависимости, смены Ruby,
  BUNDLED WITH или rack 3;
- зелёный rspec или загрузка недостижимы без `load_defaults` > 7.0, без правки существующей строки
  теста или отката чего-то из m1–m5;
- пробник постановщика противоречит спеке или коду BASE (дефект спеки);
- образ, кэш `chaskiq-m6`, `node_modules` или сервисы из раздела 2 недоступны.
Запрещено: удалять и skip-ать тесты, ослаблять ассерты, менять пробники, глушить коды возврата,
подменять окружение.

## 10. Стыки

- **m7 — `load_defaults` 7.0 → 8.1** поэтапно (7.1, 7.2, 8.0, 8.1) через `new_framework_defaults_*`:
  ротация cookie/ключей при `key_generator_hash_digest_class = SHA256` (иначе разлогинит всех),
  `cookies_serializer :json`, формат кэша, `raise_on_missing_callback_actions` и т. д.; каждая
  настройка — отдельный коммит с тестом.
- rack 3 (Rack::Attack, puma 6, заголовки в нижнем регистре); Ruby 3.4; продовый `Dockerfile` на
  bullseye (Debian 11 вне LTS с 2026-08) → bookworm/trixie, libvips по желанию;
  деприкейшены сторонних гемов (`URLcrypt.key=`, `Redis.current` в nightfury, redis 4 → 5).
