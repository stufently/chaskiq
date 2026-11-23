# slack-block-kit-tests — усиление тестов slack_block_kit

BASE: коммит этой спеки поверх `8445fddc` (Refuse revoked tokens, keep re-login session). Исполнитель `qw2`.
Решение владельца 23.11.2026 (передано соседней сессией). Мутации M1–M4 гоняет
детерминированный скрипт постановщика, а не исполнитель, поэтому машинная приёмка
перезапускает их сама.

## Где работать

Изолированный клон `/home/deploy/exec-clones/chaskiq-slack-block-kit-tests`, ветка `slack-block-kit-tests`.
Спека `docs/specs/slack-block-kit-tests.md` и скрипт мутаций уже закоммичены постановщиком.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты только в Docker под UID/GID своего пользователя.
Кэш `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci`. Живой checkout только читать.

## Задача и почему

Веха `fork-updates-r10k` разбила `MessageApis::Slack::Api` без изменения поведения и закрыла
его снимком `spec/fixtures/slack/block_kit_payloads.json` и спекой
`spec/services/message_apis/slack_block_kit_payloads_spec.rb`. Ревью Codex нашло четыре пробела
в тестах: мутации, которые меняют поведение, а сьют остаётся зелёным.

| # | Где | Пробел |
|---|-----|--------|
| 1 | payloads-спека, помощник stub_http, `request.uri.omit(:port)` | порт вырезается до сравнения: запрос на `https://slack.com:8443` проходит как `https://slack.com` |
| 2 | заглушка `direct_upload` в build_api | только хэш или nil, исключение не моделируется: вынос загрузки из `rescue` в `fetch_attachment` не ловится |
| 3 | фабрика частей, `authorable: people.fetch(...)` | у каждой части есть автор, хотя `belongs_to :authorable, optional: true`: если в `notify_message` не вычислять `format_user_name(part.authorable)` для replied-блока, сообщение без автора уйдёт в Slack вместо нынешнего NoMethodError |
| 4 | фикстура | нет ответа `users.lookupByEmail` с `ok: true` и непустым `user` без `id`: пропажа упоминания `"\n <@>"` в `assignee_mention` не ловится |

## Что проверено вживую

- `app/services/message_apis/slack/api.rb:90` — `BASE_URL = "https://slack.com"`.
- `fetch_attachment` (около стр. 1077) вызывает `handle_direct_upload` внутри метода с
  `rescue StandardError => e` → лог и `nil`; `attachment_file` возвращает nil при `file_data.nil?`.
  `handle_direct_upload` → `direct_upload(file:, filename:, content_type:)`.
- `notify_message` (стр. 797) вычисляет `format_user_name(part.authorable)` ДО ветки
  `ConversationPartBlock`; `format_user_name(nil)` вызывает `nil.display_name` → NoMethodError.
- `assignee_mention` (стр. 842): `"\n <@#{slack_user['id']}>" if slack_user.present?`.
- Скрипт мутаций `docs/specs/slack-block-kit-tests-probes/mutate.py`: якоря всех четырёх мутаций
  найдены в BASE ровно по одному разу.
- Предположение (не проверено): `ConversationPart` с `authorable: nil` сохраняется валидациями.
  Если нет — см. контракт на невыполнимое.

## План

1. AC-001: в `stub_http` payloads-спеки перестань вырезать порт. Каждый запрос проверяй на точные
   схему, хост и порт (`https`, `slack.com`, `443`) — например, отдельным ожиданием в помощнике или
   записью URI с портом и сравнением с ожидаемым; снимок при этом обязан совпадать без правки.
2. Создай `spec/services/message_apis/slack_block_kit_edge_cases_spec.rb` (WebMock, те же
   помощники-фабрики, что в payloads-спеке; общие помощники можно вынести новым файлом в `spec/support/`):
   - AC-002: `serialize_content` с файлом Slack, заглушка `direct_upload` бросает StandardError →
     результат тот же, что при nil-загрузке (вложение пропущено), исключение наружу не выходит.
     Сравни оба результата явно.
   - AC-003: `notify_message` для replied `ConversationPartBlock` без автора (`authorable: nil`) →
     NoMethodError и ни одного запроса `chat.postMessage` (фиксирует текущее поведение).
   - AC-004: событие `assigned` с `data.email`, ответ `users.lookupByEmail` =
     `{"ok":true,"user":{"name":"x"}}` → тело `chat.postMessage` содержит текст события с хвостом
     `"\n <@>"` (точное сравнение блока).
3. Перед коммитом сам прогони `python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M1` … `M4`:
   каждый обязан напечатать KILLED. Выживший мутант — дыра в тесте, доработай тест, не скрипт.
4. Коммиты ≤50 символов, без трейлеров, подписей и атрибуции, без amend. Запись в CHANGELOG.md
   (датированный раздел 2026-11-23, одна-две строки: тесты, без изменения поведения).

## Не трогать

- Прод-код: `app/`, `lib/`, `config/`, `db/`, `Gemfile*`, `.rubocop*.yml`, `.rspec`.
- Снимок `spec/fixtures/slack/block_kit_payloads.json`, пробники `docs/specs/fork-updates-r10k*`
  и скрипт `docs/specs/slack-block-kit-tests-probes/mutate.py` — не менять.
- Существующие примеры payloads-спеки не удалять и не ослаблять; меняется только помощник stub_http.
- Тесты проверяют поведение: запрещено читать текст прод-исходников (`File.read`,
  `Rails.root.join("app...")`); такая проверка не считается убийством мутанта.

## Критерии приёмки

- **AC-001** — оба Slack-спека зелёные в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci bin/ci-local --only rspec --rspec-args "spec/services/message_apis/slack_block_kit_payloads_spec.rb spec/services/message_apis/slack_block_kit_edge_cases_spec.rb"'`
- **AC-002** — мутант M1 (порт) убит payloads-спекой.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M1'`
- **AC-003** — мутант M2 (загрузка вне rescue) убит edge-спекой.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M2'`
- **AC-004** — мутант M3 (автор replied-блока) убит edge-спекой.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M3'`
- **AC-005** — мутант M4 (упоминание без id) убит edge-спекой.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M4'`
- **AC-006** — RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-sbk-ci bin/ci-local --only rubocop'`
- **AC-007** — новые спеки не читают текст прод-исходников.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/source_scan.py "$B"'`
- **AC-008** — изменены только разрешённые пути, пробелы, чистое дерево.
  `bash -c 'B=$(git merge-base HEAD @{u}) && test -z "$(git diff --name-only "$B"..HEAD | grep -vE "^(spec/|CHANGELOG\.md$)")" && git diff --check "$B"..HEAD && test -z "$(git status --porcelain --untracked-files=all -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

## Авторевью

До сдачи сверь дифф с BASE: прод-код не тронут, снимок не изменён, существующие примеры не ослаблены,
каждый новый пример падает по ожидаемой причине (для M2 — проброшенное исключение, а не другой payload;
для M3 — ушёл POST или нет исключения; для M4 — пропал хвост `"\n <@>"`).

### Контракт отчёта

В корне `report.json` с восемью записями `criteria`. Поля записи `id`, `command` дословно, `status`,
`rc`, `note`. Добавь BASE, финальный SHA и таблицу «мутант → упавший пример → причина».

## Контракт на невыполнимое

Если пример для AC-003..AC-005 нельзя построить без правки прод-кода или снимка (например,
`ConversationPart` с `authorable: nil` не сохраняется валидациями) — остановись и доложи в
`report-blocked.md` с полным выводом; обходить правкой `app/` запрещено. Сохрани завершённые коммиты.
