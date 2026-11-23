# fork-updates-r10r — GraphQL, iframe и обработчик почты

BASE: `4e1a066f3f4e809306a0e8108b8d57018faf33b3`. Исполнитель `qw2`.

## Где работать

Изолированный клон `/home/deploy/exec-clones/chaskiq-fork-updates-r10r`.
Спека коммитится в `docs/specs/fork-updates-r10r.md`.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты и запуск проекта только в Docker под UID/GID своего пользователя.
Кэш `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10r-ci`. Живой checkout только читать.

## Что проверено вживую

Замер текущим RuboCop из Docker с убранным наследованием todo. Пять нарушений AbcSize: два execute, process_email_notification, package_iframe и handle_user_data.

## План

Добавь request/controller-спеки до изменений. Закрепи точный статус и тело GraphQL при успешном запросе и ошибке, уведомления и контекст, включая порядок авторизации. Для iframe проверь альтернативные маршруты, аутентификацию, идентификатор пользователя и ответы. Для почтовой нотификации закрепи существующие ветки, ответ, обработку данных и вызовы SDK на заглушках. Сними только AbcSize-исключения этих файлов, сохрани сигнатуры, фильтры, последовательность побочных эффектов, видимость методов, формат ответа и границы rescue. Тесты работают локально на синтетических данных и без обращения к внешним провайдерам.

Создай spec/requests/r10r_*_spec.rb. Прогони их и затронутые существующие request/controller-спеки. Сначала подтвердить новые ожидания на BASE, затем закоммитить тесты.
После реализации повторить те же тесты, замер по целевым файлам без todo и строгий RuboCop.
Код, todo и датированный CHANGELOG оформи смысловыми коммитами. Заголовки до 50 символов,
тела без трейлеров, подписей и атрибуции. Без amend или переписывания готовых коммитов.
Постановщик независимо прогонит полный RSpec после интеграции с другими вехами.

## Не трогать

Целевые файлы: app/controllers/api/graphql_controller.rb, app/controllers/graphql_controller.rb, app/controllers/api/v1/hooks_controller.rb и app/controllers/concerns/package_iframe_behavior.rb.
Допустимы ровно эти исходники, новые спеки для вехи, относящиеся к ним строки todo
и датированная запись в CHANGELOG. Спеки должны проверять поведение, без чтения
текста исходников, новых пропусков и rubocop-директив.

## Критерии приёмки

- **AC-001** — целевые тесты в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10r-ci bin/ci-local --only rspec --rspec-args "spec/requests/r10r_*_spec.rb"'`
- **AC-002** — строгий RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10r-ci bin/ci-local --only rubocop'`
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
