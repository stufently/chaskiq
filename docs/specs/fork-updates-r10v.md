# fork-updates-r10v — Размер UserHandler

BASE: `dbfc64dedd61c571ff7935baad9627edb39eadf8`. Исполнитель `qw2`.

## Где работать

Изолированный клон `/home/deploy/exec-clones/chaskiq-fork-updates-r10v`.
Спека коммитится в `docs/specs/fork-updates-r10v.md`.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты и запуск проекта только в Docker под UID/GID своего пользователя.
Кэш `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10v-ci`. Живой checkout только читать.

## Что проверено вживую

Замер текущим RuboCop из Docker с убранным наследованием todo. UserHandler — 123 строки при общем Max 123. Нужно вернуть установленный RuboCop стандартный порог, убрав строку Max, и сохранить существующий Exclude.

## План

Добавь реальные модели-спеки для add_user, add_lead и add_anonymous_user. Закрепи атрибуты, find-or-initialize, properties, побочные эффекты, исходные типы и ошибки, включая disable_callbacks в add_anonymous_user. Без починки посторонних ошибок. Раздели связанные методы между двумя concerns с сохранением include chain, публичной видимости, сигнатур и состояний. Удали только Max: 123 и устаревший комментарий к нему. Полный RuboCop после снятия исключения должен быть зелёным.

Создай spec/models/user_handler_r10v_spec.rb и прогони его с app_user и app model tests. Сначала подтвердить новые ожидания на BASE, затем закоммитить тесты.
После реализации повторить те же тесты, замер по целевым файлам без todo и строгий RuboCop.
Код, todo и датированный CHANGELOG оформи смысловыми коммитами. Заголовки до 50 символов,
тела без трейлеров, подписей и атрибуции. Без amend или переписывания готовых коммитов.
Постановщик независимо прогонит полный RSpec после интеграции с другими вехами.

## Не трогать

Целевые файлы: app/models/concerns/user_handler.rb, один новый concern в app/models/concerns и настройка Metrics/ModuleLength в .rubocop.yml.
Допустимы ровно эти исходники, новые спеки для вехи, относящиеся к ним строки todo
и датированная запись в CHANGELOG. Спеки должны проверять поведение, без чтения
текста исходников, новых пропусков и rubocop-директив.

## Критерии приёмки

- **AC-001** — целевые тесты в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10v-ci bin/ci-local --only rspec --rspec-args "spec/models/user_handler_r10v_spec.rb"'`
- **AC-002** — строгий RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10v-ci bin/ci-local --only rubocop'`
- **AC-003** — проверка новых спек.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/source_scan.py "$B"'`
- **AC-004** — пробелы и чистое дерево.
  `bash -c 'B=$(git merge-base HEAD @{u}) && git diff --check "$B"..HEAD && test -z "$(git status --porcelain --untracked-files=all -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

## Авторевью

До сдачи сверить дифф с BASE, включая область rescue, return, видимость,
порядок вызовов и команды ворот. Сохрани вывод при блоке внешнего ревьюера.

### Контракт отчёта

В корне `report.json` с четырьмя записями `criteria`. Поля записи `id`, `command`
дословно, `status`, `rc`, `note`. Добавь BASE, финальный SHA, конкретные результаты
целевого прогона на BASE и финале, замер без todo и итог ревью.

## Контракт на невыполнимое

При блоке сохрани завершённые коммиты и полный вывод ошибочной команды.
Ожидания по поведению сверяй на BASE. При временном блоке сначала выполни остальные проверки.
