# fork-updates-r10t — Размер AppType и резолвер conversations

BASE: `4e1a066f3f4e809306a0e8108b8d57018faf33b3`. Исполнитель `qw2`.

## Где работать

Изолированный клон `/home/deploy/exec-clones/chaskiq-fork-updates-r10t`.
Спека коммитится в `docs/specs/fork-updates-r10t.md`.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты и запуск проекта только в Docker под UID/GID своего пользователя.
Кэш `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10t-ci`. Живой checkout только читать.

## Что проверено вживую

Замер текущим RuboCop из Docker с убранным наследованием todo. Три нарушения: ClassLength (514/300), AbcSize conversations и восемь параметров conversations.

## План

Перенеси связанные группы методов-резолверов в несколько модулей до 100 строк, сохраняя порядок объявлений полей и GraphQL SDL. Сними дамп ChaskiqSchema.to_definition до и после в Docker и сравни побайтно. Закрепи запросы с фильтрами и без них и ошибки term как они ведут себя на BASE. Убери AbcSize лишних выражений conversations выделением помощника и используй kwargs для сохранения GraphQL интерфейса. Запрещены изменения аргументов схемы, результата, visibility, exception semantics и сторонние фиксы. Удали три относящиеся к AppType строки todo.

Создай spec/graphql/types/app_type_r10t_spec.rb и прогони его с другими app_type specs. Сначала подтвердить новые ожидания на BASE, затем закоммитить тесты.
После реализации повторить те же тесты, замер по целевым файлам без todo и строгий RuboCop.
Код, todo и датированный CHANGELOG оформи смысловыми коммитами. Заголовки до 50 символов,
тела без трейлеров, подписей и атрибуции. Без amend или переписывания готовых коммитов.
Постановщик независимо прогонит полный RSpec после интеграции с другими вехами.

## Не трогать

Целевые файлы: app/graphql/types/app_type.rb и модули резолверов AppType в app/graphql/types.
Допустимы ровно эти исходники, новые спеки для вехи, относящиеся к ним строки todo
и датированная запись в CHANGELOG. Спеки должны проверять поведение, без чтения
текста исходников, новых пропусков и rubocop-директив.

## Критерии приёмки

- **AC-001** — целевые тесты в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10t-ci bin/ci-local --only rspec --rspec-args "spec/graphql/types/app_type_r10t_spec.rb"'`
- **AC-002** — строгий RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10t-ci bin/ci-local --only rubocop'`
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
