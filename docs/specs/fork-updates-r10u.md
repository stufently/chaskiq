# fork-updates-r10u — Интеграции, загрузчик плагинов и локализованные поля

BASE: `dbfc64dedd61c571ff7935baad9627edb39eadf8`. Исполнитель `qw2`.

## Где работать

Изолированный клон `/home/deploy/exec-clones/chaskiq-fork-updates-r10u`.
Спека коммитится в `docs/specs/fork-updates-r10u.md`.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты и запуск проекта только в Docker под UID/GID своего пользователя.
Кэш `CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10u-ci`. Живой checkout только читать.

## Что проверено вживую

Замер текущим RuboCop из Docker с убранным наследованием todo. Четыре нарушения: AbcSize call_hook и save_plugin_files_to_folder, BlockLength included в GlobalizeAccessors и CyclomaticComplexity initialize в PluginSchemaValidator. App и AppUser уже зелёные.

## План

Сначала тесты на BASE. Для call_hook закрепи параметры, возврат и ошибки на SDK-заглушке. Для сохранения плагинов используй временный каталог, статичный архив, поддельный загрузчик и отсутствие реальных HTTP-вызовов. Не трогай продовый каталог. Для GlobalizeAccessors закрепи методы, атрибуты, локаль и поведение для старой глобализации. Для валидатора проверь точные результаты и исключения на валидном и невалидном вводе. Сохрани Rails callbacks и порядок вычислений. Сними исключения только целевых cop/файл.

Создай spec/r10u/*_spec.rb и прогони их с существующими тестами плагинов и схемы. Сначала подтвердить новые ожидания на BASE, затем закоммитить тесты.
После реализации повторить те же тесты, замер по целевым файлам без todo и строгий RuboCop.
Код, todo и датированный CHANGELOG оформи смысловыми коммитами. Заголовки до 50 символов,
тела без трейлеров, подписей и атрибуции. Без amend или переписывания готовых коммитов.
Постановщик независимо прогонит полный RSpec после интеграции с другими вехами.

## Не трогать

Целевые файлы: app/models/app_package_integration.rb, app/models/plugin.rb, app/models/concerns/globalize_accessors.rb, app/services/plugin_schema_validator.rb.
Допустимы ровно эти исходники, новые спеки для вехи, относящиеся к ним строки todo
и датированная запись в CHANGELOG. Спеки должны проверять поведение, без чтения
текста исходников, новых пропусков и rubocop-директив.

## Критерии приёмки

- **AC-001** — целевые тесты в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10u-ci bin/ci-local --only rspec --rspec-args "spec/r10u/*_spec.rb"'`
- **AC-002** — строгий RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10u-ci bin/ci-local --only rubocop'`
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
