# fork-updates-r10p1 — запросы по тегам в Segment

BASE клона: `4e1a066f`. Исполнитель `qw2`. В программе R10p предусмотрены
несколько объёмных методов. Эта веха затрагивает только `Segment#tagged_result`.

## Где работать

Клон `/home/deploy/exec-clones/chaskiq-fork-updates-r10p1`.
Спека коммитится в `docs/specs/fork-updates-r10p1.md`.
git pull в клоне не делать; push в origin запрещён, работу заберёт постановщик через `git fetch` из клона.
Тесты только в Docker как пользователь deploy. Кэш
`CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10p1-ci`. Живое дерево только читать.

## Что проверено вживую

Замер текущим RuboCop в Docker без todo: 10 нарушений в segment.rb.
В `tagged_result` ровно пять (AbcSize 110.2, Cyc 27, MethodLength 85,
Perceived 24, BlockLength 45). Остальные пять у `nested_preds_group` и
`es_search` остаются для второй вехи. По чтению кода `tagged_result`
строит Arel aliases по исходному индексу тегового предиката, исключает
AND-отрицания через EXCEPT, связывает OR через EXISTS и применяет
DISTINCT к ветке с обычными JOIN. Существующие спеки Segment
проверяют часть этих путей по базе.

## План

1. Добавь `spec/models/segment_tagged_result_spec.rb` с поведенческими
   проверками на BASE. Для основных веток сравнивай SQL и фактические
   результаты на тестовых записях. Покрой eq/not_eq, starts/ends/contains,
   not_contains, is_null/is_not_null, пустые теги, несколько тегов в
   AND/OR, сочетание тега с обычным фильтром, разные приложения и
   дубли совпадений. Поведение OR для inverse закрепи как есть по BASE.
   Сначала запусти новые и существующие спеки и закоммить тесты.
2. Сократи `tagged_result` приватными помощниками. Оставь публичный
   интерфейс, условие `taggable_type = AppUser`, порядок aliases,
   SQL-фильтры, связи AND/OR, EXCEPT и результат как relation.
   Допускается небольшой внутренний объект, если помощникам иначе
   пришлось бы передавать общее изменяемое состояние через много
   аргументов. Целевой дифф только `app/models/segment.rb`.
3. Из todo убери ровно строки для `Metrics/BlockLength` и
   `Metrics/PerceivedComplexity` у segment.rb. Остальные три
   исключения этому файлу ещё нужны. Датированная запись в CHANGELOG.
   Смысловые коммиты раздельно, заголовки до 50 символов, без трейлеров.
4. Подтверди те же тесты на BASE и финальном коде, строгий RuboCop,
   полный RSpec и отдельный замер без todo. В файле должно быть 5
   нарушений, все относятся к методам второй вехи. Предложи несколько
   мутаций, показывающих роль NOT/OR и scoping.

## Не трогать

Другие методы Segment, остальные модели, имеющиеся спеки, зависимости,
bin/ и конфигурацию RuboCop. Тесты проверяют SQL результата и строки
реальной БД. Запрещено чтение исходников для проверки, пропуски тестов,
rubocop-директивы и доступ к внешним сервисам.

## Критерии приёмки

- **AC-001** — полный RSpec в Docker.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10p1-ci bin/ci-local --only rspec'`
- **AC-002** — строгий RuboCop.
  `bash -c 'CI_LOCAL_CACHE=$HOME/.cache/chaskiq-r10p1-ci bin/ci-local --only rubocop'`
- **AC-003** — проверка новых спек.
  `bash -c 'B=$(git merge-base HEAD @{u}) && python3 -I docs/specs/fork-updates-r10l-probes/source_scan.py "$B"'`
- **AC-004** — пробелы и чистое дерево.
  `bash -c 'B=$(git merge-base HEAD @{u}) && git diff --check "$B"..HEAD && test -z "$(git status --porcelain --untracked-files=all -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

## Авторевью

Запроси agy через review_run.sh с итоговым продуктовым диффом.
Приложи квитанцию или точное сообщение о блоке.

### Контракт отчёта

В корне `report.json` с четырьмя записями `criteria`. В каждой `id`,
`command` дословно, `status`, `rc`, `note`. Добавь `executor`,
BASE, финальный SHA, итог замера без todo, BASE и targeted RSpec,
предложенные мутации и итог ревью.

## Контракт на невыполнимое

Сохрани завершённые коммиты и дословный вывод. Ожидания исправляй по
наблюдаемому BASE. При временном блоке сначала выполни остальные проверки.
