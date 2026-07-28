# Changelog

## [1.1.0] — 2026-07-28

### Исправлено

- Оверлей не работал в данжах из-за state reference bug в `ShowPreStartOverlay()` — `SMPState:Reset()` заменял таблицу, а код модифицировал старую ссылку
- Добавлен ивент `CHALLENGE_MODE_START` для корректного обнаружения активации ключа
- Исправлена инициализация — `CheckChallenge()` вызывается после регистрации ивентов, а не от уже сработавшего `PLAYER_ENTERING_WORLD`
- `INSTANCE_ENCOUNTERS_UPDATE` теперь обновляет и боссов, и силы (аргумент `isForces` не всегда корректен на Sirus)
- Консолидирован event frame — один фрейм на все ивенты вместо отдельного на каждый
- `RegisterCustomEvent` вызывается только для Sirus-специфичных событий, а не для стандартных WoW ивентов

### Добавлено

- Авто-вставка ключа при открытии гнезда (`CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN`), настраивается через `insertKeystoneAutomatically`
- Лог смертей по игрокам через `COMBAT_LOG_EVENT_UNFILTERED` — отслеживание `UNIT_DIED` с привязкой к участникам группы
- Тултип смертей при наведении мыши на текст смертей в оверлее (два стиля: по времени / по игрокам)
- Конфигурация формата текста сил — плейсхолдеры `:percent:`, `:count:`, `:totalcount:`, `:remainingcount:`, `:remainingpercent:`
- Конфигурация формата текста пулла — плейсхолдеры `:percent:`, `:count:`
- Система сплитов — отслеживание лучших времён по боссам, сравнение с текущим забегом, цветовая индикация (зелёный = быстрее, красный = медленнее)
- Модуль `SMPSplitsData` для хранения сплитов в `SMPConfigDB.global.splits`
- Окно поиска игрока (`/smp search <имя>`) — рейтинг, место в ладдере, лучший ключ, таблица данжей
- ПКМ по кнопке миникарты открывает окно поиска
- Поле `splitRecord` и `splits` в `SMPState`
- Async-обработка поиска игрока — ожидание `LADDER_MYTHIC_PLUS_SEARCH_RESULT` вместо слепого `C_Timer.After(0.5)`
- Обработка ошибок и задержек ладдера (`LADDER_MYTHIC_PLUS_SEARCH_ERROR`, `LADDER_MYTHIC_PLUS_SEARCH_DELAY`)
- ElvUI поддержка — defensive `SetBackdrop` guards, определение текстур через `IsAddOnLoaded("ElvUI")` и LibSharedMedia
- Инвалидация кеша текстур при загрузке ElvUI/SharedMedia (`ADDON_LOADED`)
- Окно поиска на AceGUI — автоматический ElvUI skin при наличии ElvUI
- Retry-механизм для поиска — polling каждую секунду до 10 попыток
- `RegisterCustomEvent` вызывается ДО `RegisterEvent` для Sirus-ивентов (порядок важен)
- `deathsText` тултип через frame-обёртку вместо `EnableMouse` на FontString
