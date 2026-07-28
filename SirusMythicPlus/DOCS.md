# SirusMythicPlus — Документация

**Версия:** 1.0.1
**Автор:** NastyaLove
**Интерфейс:** 3.3.5a (Sirus)
**SavedVariables:** `SMPConfigDB`, `SMPOverlayDB`

---

## Оглавление

1. [Обзор](#1-обзор)
2. [Структура проекта](#2-структура-проекта)
3. [Архитектура](#3-архитектура)
4. [Модули](#4-модули)
5. [Игровые API](#5-игровые-api)
6. [Утилиты и инструменты](#6-утилиты-и-инструменты)
7. [Конфигурация](#7-конфигурация)
8. [Команды](#8-команды)
9. [События](#9-события)
10. [MessageBus](#10-messagebus)
11. [Pull Tracking (Nameplate)](#11-pull-tracking-nameplate)
12. [Демо-режим](#12-демо-режим)
13. [Ladder Data Pipeline](#13-ladder-data-pipeline)
14. [Зависимости (Libs)](#14-зависимости-libs)
15. [Известные ограничения](#15-известные-ограничения)

---

## 1. Обзор

**SirusMythicPlus** — аддон для WoW 3.3.5a (приватный сервер Sirus), добавляющий:

- **Тултип** с Mythic+ рейтингом, местом в ладдере, лучшим ключом и списком данжей
- **Оверлей** (таймер) для отслеживания M+ в реальном времени: таймер +1/+2/+3, прогресс сил (enemy forces), боссы, смерти, предсказание пулла
- **Кнопку на миникарте** для быстрого доступа к настройкам
- **Кэшированные данные ладдера** (рейтинги игроков) с возможностью обновления через скрипт

---

## 2. Структура проекта

```
SirusMythicPlus/
├── .gitignore
├── .luacheckrc                    # Конфиг luacheck (глобалы WoW API)
├── LICENSE
├── SirusMythicPlus/               # ← Это и есть аддон (папка для WoW)
│   ├── SirusMythicPlus.toc        # Манифест аддона
│   ├── embeds.xml                 # Подключение библиотек (Libs)
│   ├── SMP.lua                    # Точка входа (OnInitialize)
│   ├── Media/
│   │   └── icon.tga               # Иконка для миникарты
│   ├── Libs/                      # Внешние библиотеки
│   │   ├── AceAddon-3.0/
│   │   ├── AceConfig-3.0/         # (Registry, Dialog, Cmd)
│   │   ├── AceConsole-3.0/
│   │   ├── AceDB-3.0/
│   │   ├── AceEvent-3.0/
│   │   ├── CallbackHandler-1.0/
│   │   ├── LibCompat-1.0/         # Полифилы для 3.3.5a
│   │   ├── LibCustomGlow-1.0/     # Анимации свечения
│   │   ├── LibDataBroker-1.1/
│   │   ├── LibDBIcon-1.0/         # Кнопка на миникарте
│   │   └── LibStub/
│   ├── Modules/
│   │   ├── Libs/                  # Внутренние утилиты
│   │   │   ├── SMPLoader.lua      # Система модулей
│   │   │   ├── SMPCompat.lua      # C_Timer полифил
│   │   │   ├── SMPLib.lua         # Версия, утилиты
│   │   │   ├── ThreadLib.lua      # Coroutine-based треды
│   │   │   └── SMPMessageBus.lua  # Шина сообщений
│   │   ├── Config/
│   │   │   ├── SMPConfigDefaults.lua  # Дефолты конфига
│   │   │   └── SMPConfig.lua      # AceDB + AceConfig панель
│   │   ├── Core/
│   │   │   ├── SMPEventHandler.lua # Обработчик WoW-ивентов (тултип)
│   │   │   └── SMPSlash.lua        # Slash-команды (/smp)
│   │   ├── Tooltip/
│   │   │   └── SMPTaboo.lua        # Рендер тултипа (рейтинг, ключи, ладдер)
│   │   ├── UI/
│   │   │   ├── SMPMinimapButton.lua # Кнопка на миникарте
│   │   │   └── SMPPlayerSearch.lua  # Окно поиска игрока
│   │   ├── Database/
│   │   │   ├── SMPData.lua          # Менеджер данных ладдера
│   │   │   ├── SMPDataSchema.lua    # Валидация данных
│   │   │   ├── SMPForcesData.lua    # Менеджер данных сил мобов
│   │   │   ├── SMPSplitsData.lua    # Хранилище сплитов
│   │   │   └── Data/
│   │   │       ├── EnemyForcesData.lua  # Таблица: NPC ID → силы (статика)
│   │   │       └── LadderData.lua       # Таблица: игрок → рейтинг (генерируется)
│   │   └── Overlay/
│   │       ├── SMPState.lua         # Состояние M+ (state machine)
│   │       ├── SMPFrame.lua         # UI оверлея (фреймы, рендер)
│   │       └── SMPCore.lua          # Логика M+ (ивенты, таймер, пулл)
│   └── tools/
│       ├── update_ladder.ps1        # PowerShell скрипт обновления ладдера
│       └── update.bat               # Обёртка для запуска .ps1
```

---

## 3. Архитектура

### 3.1 Паттерн: Модульная загрузка через SMPLoader

Аддон **не использует** AceAddon-модули (`self:NewModule()`). Вместо этого — собственный лёгкий лоадер:

```lua
-- Создание модуля (в файле модуля):
local MyModule = SMPLoader:CreateModule("MyModule")

-- Импорт модуля (в другом файле):
local MyModule = SMPLoader:ImportModule("MyModule")
```

Каждый модуль — таблица с полем `private` для приватных данных. `SMPLoader` хранит все модули в `modules` (closure), а в `SMP.lua` вызывается `SMPLoader:PopulateGlobals()` (хотя в текущем коде это не используется — модули доступны по имени через `_G`).

### 3.2 Порядок загрузки (TOC)

```
1. embeds.xml          → LibStub, Ace*, LibCompat, LibCustomGlow
2. SMPLoader.lua       → Система модулей
3. SMPCompat.lua       → C_Timer полифил
4. SMPLib.lua          → Утилиты
5. ThreadLib.lua       → Coroutine треды
6. SMPMessageBus.lua   → Шина сообщений
7. SMPConfigDefaults.lua → Дефолты
8. SMPConfig.lua       → Конфиг (AceDB + AceConfig)
9. SMPEventHandler.lua → WoW-ивенты для тултипа
10. SMPSlash.lua       → Slash-команды
11. SMPTaboo.lua       → Тултип
12. SMPMinimapButton.lua → Миникарта
13. SMPForcesData.lua  → Менеджер данных сил
14. EnemyForcesData.lua → Статические данные сил
15. SMPData.lua        → Менеджер ладдер-данных
16. LadderData.lua     → Генерируемые данные ладдера
17. SMPState.lua       → Состояние M+
18. SMPFrame.lua       → UI оверлея
19. SMPCore.lua        → Логика M+ (главный контроллер)
20. SMP.lua            → Точка входа (OnInitialize)
```

### 3.3 Паттерн: MessageBus

Все модули общаются через `SMPMessageBus.shared` (singleton). Это decoupled архитектура:

```
SMPCore → fire("ChallengeStarted") → SMPFrame:Show()
SMPCore → fire("TimerTick")        → SMPFrame:RenderTimer()
SMPCore → fire("ForcesUpdated")    → SMPFrame:RenderForces()
SMPCore → fire("BossesUpdated")    → SMPFrame:RenderObjectives()
SMPCore → fire("DeathsUpdated")    → SMPFrame: обновление текста смертей
SMPConfig → fire("ConfigChanged")  → SMPFrame:RenderLayout() + SMPCore:CheckPullTracking()
```

---

## 4. Модули

### 4.1 SMPLoader (`Modules/Libs/SMPLoader.lua`)

Система модулей. `CreateModule` и `ImportModule` — идемпотентны (создают при отсутствии).

```lua
SMPLoader:CreateModule("Name")  → { private = {} }
SMPLoader:ImportModule("Name")  → тот же объект
```

### 4.2 SMPCompat (`Modules/Libs/SMPCompat.lua`)

Полифил `C_Timer` для 3.3.5a:
- `C_Timer.After(delay, callback)` — одноразовый таймер через OnUpdate
- `C_Timer.NewTicker(delay, callback, iterations)` — повторяющийся таймер с `:Cancel()`

### 4.3 SMPLib (`Modules/Libs/SMPLib.lua`)

- `SMPLib:GetAddonVersionInfo()` → major, minor, patch
- `SMPLib:GetAddonVersionString()` → "v1.0.1"
- `SMPLib:Count(tbl)` → количество ключей в таблице
- `SMPLib.AddonPath` → `"Interface\\Addons\\SirusMythicPlus\\"`

### 4.4 ThreadLib (`Modules/Libs/ThreadLib.lua`)

Coroutine-based планировщик:
- `ThreadLib.Thread(fn, delay, errorMsg, callback)` — запускает coroutine, resume каждые `delay` сек
- `ThreadLib.ThreadCallback(fn, delay, callback)` — то же, без errorMsg
- `ThreadLib.ThreadSimple(fn, delay)` — то же, без callback

Используется в `SMPData` для валидации данных ладдера батчами по 500 записей.

### 4.5 SMPMessageBus (`Modules/Libs/SMPMessageBus.lua`)

Шина сообщений с двумя типами подписок:
- `bus:RegisterRepeating(event, callback)` — вызывается каждый раз
- `bus:RegisterOnce(event, callback)` — вызывается один раз, потом удаляется
- `bus:Fire(event, ...)` — отправка события
- `bus:UnregisterRepeating(event, callback)` — отписка
- `bus:UnregisterAll(event)` — отписка всех

Защита от рекурсии: если событие уже firing, выбрасывает ошибку.

### 4.6 SMPConfig (`Modules/Config/SMPConfig.lua`)

Обёртка над AceDB + AceConfig:
- `SMPConfig:Initialize()` — создаёт AceDB с дефолтами, регистрирует AceConfig
- `SMPConfig:Get(path, scope)` / `SMPConfig:Set(path, value, scope)` — доступ по dot-path (`"overlay.timerFont"`)
- `SMPConfig:GetProfileConfig(path)` / `SMPConfig:UpdateProfileConfig(path, value)` — шорткаты для profile scope
- `SMPConfig:GetGlobalConfig(path)` / `SMPConfig:UpdateGlobalConfig(path, value)` — шорткаты для global scope
- `SMPConfig:RunMigrations()` — миграции версий БД

### 4.7 SMPConfigDefaults (`Modules/Config/SMPConfigDefaults.lua`)

Возвращает таблицу дефолтов. См. [Конфигурация](#7-конфигурация).

### 4.8 SMPEventHandler (`Modules/Core/SMPEventHandler.lua`)

Обрабатывает WoW-ивенты для тултипа:
- `MYTHIC_PLUS_PLAYER_STAT_UPDATE` → обновление тултипа
- `CHALLENGE_MODE_SCORE_UPDATE` → обновление тултипа
- `CHALLENGE_MODE_MAPS_UPDATE` → обновление тултипа
- `LADDER_MYTHIC_PLUS_SEARCH_RESULT` → обновление тултипа
- `MODIFIER_STATE_CHANGED` → обновление при зажатии Shift/Ctrl/Alt

Все ивенты используют `RegisterCustomEvent` (Sirus-specific) для кастомных ивентов.

### 4.9 SMPSlash (`Modules/Core/SMPSlash.lua`)

Регистрирует `/smp` и `/mythicplus`. См. [Команды](#8-команды).

### 4.10 SMPTaboo (`Modules/Tooltip/SMPTaboo.lua`)

Рендер Mythic+ информации в GameTooltip:
- **Рейтинг M+** — цветовой градиент от серого (0) до золотого (2500)
- **Место в ладдере** — через `C_Ladder.RequestSearch()` (цвет: золото ≤20, оранжев ≤100, фиолет ≤1000)
- **Макс. ключ** — уровень + название данжа (цвет: синий <10, фиолет <15, золото ≥15)
- **Забеги** — статистика (в таймер / всего)
- **Список данжей** — по Shift (или всегда, если включено в конфиге): название + время + уровень

Два пути данных:
- **Локальный игрок**: `C_ChallengeMode.GetOverallDungeonScore()`, `C_ChallengeMode.GetMapScoreInfo()`, `C_MythicPlus.GetRunHistory()`
- **Другой игрок**: `C_Inspect.GetMythicRating(unit)`, `C_MythicPlus.GetPlayerStatsForMap(name, mapID)`

Патч фреймов ладдера: `patchLadderFrames()` создаёт заглушки для `SearchFrame`/`SearchButton` на нескольких Ladder-фреймах, чтобы избежать ошибок.

### 4.11 SMPMinimapButton (`Modules/UI/SMPMinimapButton.lua`)

Кнопка на миникарте через LibDataBroker + LibDBIcon:
- ЛКМ → открыть настройки
- Позиция сохраняется в `SMPConfigDB.global.minimap.minimapPos`
- Видимость: `/smp minimap` / `/smp minimap hide`

### 4.12 SMPData (`Modules/Database/SMPData.lua`)

Менеджер данных ладдера:
- `SMPData:RegisterLadderData(data)` — регистрация таблицы данных
- `SMPData:LadderLookup(name)` → `{ score, rank, bestLevel, timed, total, ... }`
- `SMPData:StartValidation()` — валидация батчами по 500 через ThreadLib

### 4.13 SMPDataSchema (`Modules/Database/SMPDataSchema.lua`)

Валидация записи ладдера:
```lua
{ score: number?, rank: number?, bestLevel: number?, timed: number?, total: number? }
```

### 4.14 SMPForcesData (`Modules/Database/SMPForcesData.lua`)

Менеджер данных сил мобов:
- `SMPForcesData:GetTotal(areaID)` → общее количество сил (по умолчанию 900)
- `SMPForcesData:GetCount(areaID, npcID)` → количество сил за конкретного моба
- `SMPForcesData:LookupByNPC(npcID)` → количество сил + areaID

### 4.15 EnemyForcesData (`Modules/Database/Data/EnemyForcesData.lua`)

Статическая таблица данных сил. Формат:
```lua
[areaID] = { total = 900, mobs = { [npcID] = { name = "...", count = N }, ... } }
```

Покрытые данжи:
| areaID | Данж |
|--------|------|
| 522 | Королевство Ан'кахет |
| 722 | Аукенайские гробницы |
| 534 | Крепость Драк'Тарон |
| 525 | Чертоги Молний |
| 848 | Бастионы Адского Пламени |
| 842 | Гробницы Маны |
| 835 | Кузня Крови |
| 838 | Узилище |
| 523 | Крепость Утгард |

### 4.16 LadderData (`Modules/Database/Data/LadderData.lua`)

Генерируемая таблица данных ладдера. Обновляется через `tools/update_ladder.ps1`. Формат:
```lua
["ИмяИгрока"] = { rank=N, score=N, bestLevel=N, timed=N, total=N, ... }
```

### 4.17 SMPState (`Modules/Overlay/SMPState.lua`)

State machine для M+. Хранит:
- `inChallenge`, `preStart`, `completed`, `completedOnTime`, `timerStarted`, `demoModeActive`
- `timer`, `timeLimit`, `timeLimitSilver`, `timeLimitGold`, `timeLimits[3]`, `completionTimeMs`
- `deathCount`, `deathTimeLost`, `deathDetails[]`
- `mapId`, `level`, `affixes[]`, `affixIds[]`
- `forcesPercent`, `forcesCompleted`, `forcesCompletionTime`
- `bosses[]`, `numBosses`, `numBossesKilled`
- `currentPull{}`, `pullCount`, `pullPercent`

### 4.18 SMPFrame (`Modules/Overlay/SMPFrame.lua`)

UI оверлея. Создаёт:
- `f.root` — главный фрейм (перетаскивается в unlocked)
- `f.deathsText` — текст смертей
- `f.timerText` — текст таймера ("8:40 / 35:00")
- `f.timerSplitText` — текст сплитов
- `f.keyText` — текст уровня ключа ("[15]")
- `f.keyDetailsText` — текст аффиксов ("Tyrannical - Bolstering")
- `f.bar1`, `f.bar2`, `f.bar3` — три полосы таймера (+1/+2/+3)
- `f.forces` — полоса прогресса сил
- `f.forcesOverlay` — полоса предсказания пулла
- `f.objectiveTexts[1..10]` — тексты боссов

Рендер:
- `RenderLayout()` — полная перераскладка (при изменении конфига)
- `RenderTimer()` — обновление таймера и полос
- `RenderForces()` — обновление прогресса сил + свечение
- `RenderObjectives()` — обновление боссов

Свечение (LibCustomGlow):
- Голубое свечение когда пулл доведёт до 100%
- Красное свечение в бою с активным пуллом

### 4.19 SMPCore (`Modules/Overlay/SMPCore.lua`)

Главный контроллер логики M+.

**CM_TO_AREA** — маппинг ChallengeMode ID → areaID для данных сил:
```lua
{ [4]=523, [5]=848, [6]=838, [8]=534, [9]=525, [10]=835, [11]=522, [13]=722 }
```

**Жизненный цикл M+:**
1. `PLAYER_ENTERING_WORLD` → `CheckChallenge()`
   - Если M+ активен → `StartChallenge()`
   - Если в эпохальном инсте, но ключ не вставлен → `ShowPreStartOverlay()` + `StartPolling()`
   - Иначе → `StopPolling()` + `StopChallenge()`
2. Polling каждые 2с проверяет `C_ChallengeMode.IsChallengeModeActive()`
3. При активации ключа → `ActivateChallenge()` (получает level, affixes, timeLimits, forces, bosses)
4. `WORLD_STATE_TIMER_START` → `UpdateTimerState()`
5. `INSTANCE_ENCOUNTERS_UPDATE(isForces)` → `UpdateForces()` или `UpdateBosses()`
6. `CHALLENGE_MODE_DEATH_COUNT_UPDATED` → `UpdateDeaths()`
7. `CHALLENGE_MODE_COMPLETED` → `CompleteChallenge()`
8. `CHALLENGE_MODE_CANCEL` → `StopChallenge()`

**Таймер:** OnUpdate фрейм с throttle 100мс, читает `GetWorldElapsedTime(1)`.

---

## 5. Игровые API

### Sirus-specific API

| API | Назначение |
|-----|-----------|
| `C_InstanceEncounters.GetNumEncounters()` | Количество боссов в инсте |
| `C_InstanceEncounters.GetEncounterInfo(i)` | `name`, `isDead` босса |
| `C_ChallengeMode.GetEnemyForcesProgress()` | Процент сил (0-100) |
| `C_ChallengeMode.GetDeathCount()` | Кол-во смертей + потерянное время |
| `C_ChallengeMode.GetCompletionInfo()` | Время завершения + onTime |
| `C_ChallengeMode.GetMapUIInfo(mapID)` | Имя, лимиты времени (bronze/silver/gold) |
| `C_ChallengeMode.GetActiveKeystoneInfo()` | Уровень ключа + affix IDs |
| `C_ChallengeMode.GetAffixInfo(affixID)` | Имя + описание аффикса |
| `C_ChallengeMode.GetMapTable()` | Список всех map IDs |
| `C_ChallengeMode.GetMapScoreInfo()` | Инфо о скоре по картам |
| `C_ChallengeMode.GetOverallDungeonScore()` | Общий M+ рейтинг |
| `C_ChallengeMode.GetDungeonScoreRarityColor()` | Цвет рейтинга |
| `C_MythicPlus.IsMythicPlusActive()` | Активен ли M+ сезон |
| `C_MythicPlus.GetPlayerStatsForMap(name, mapID)` | Статы игрока по карте |
| `C_MythicPlus.GetRunHistory(all, show)` | История забегов |
| `C_MythicPlus.GetSeasonBestForMap(mapID)` | Лучший результат сезона |
| `C_MythicPlus.RequestMapInfo()` | Запрос инфо о картах |
| `C_MythicPlus.RequestPlayerStat(name)` | Запрос статов игрока |
| `C_Ladder.RequestSearch(bracket, name)` | Поиск в ладдере |
| `C_Ladder.GetNumSearchResults(bracket)` | Кол-во результатов |
| `C_Ladder.GetSearchResultPlayerInfo(bracket, i)` | rank, name |
| `C_Inspect.GetMythicRating(unit)` | M+ рейтинг юнита |
| `GetWorldElapsedTime(1)` | Текущее время таймера |
| `RegisterCustomEvent(frame, event)` | Регистрация кастомного ивента |

### Стандартные WoW API

| API | Использование |
|-----|--------------|
| `GetInstanceInfo()` | Тип инстанса и сложность |
| `C_NamePlate.GetNamePlates()` | Список неймплейтов |
| `UnitGUID(unit)` | GUID юнита (для NPC ID) |
| `strsplit("-", guid)` | Парсинг GUID → NPC ID (6-й сегмент) |
| `UnitCanAttack(unit, "player")` | Враждебный ли юнит |
| `GetCVar("nameplateEnableNew")` | Новые неймплейты включены? |

---

## 6. Утилиты и инструменты

### 6.1 `tools/update_ladder.ps1`

PowerShell скрипт для обновления данных ладдера с API Sirus.

**Что делает:**
1. Загружает страницы рейтингов (`/api/base/22/leaderboard/challenge/scores`) — 200 страниц параллельно (16 воркеров)
2. Загружает timed runs (`/api/base/22/leaderboard/challenge/runs?timed=true`) — 300 страниц
3. Загружает all runs (`/api/base/22/leaderboard/challenge/runs`) — 300 страниц
4. Объединяет данные и пишет в `Modules/Database/Data/LadderData.lua`

**Поля на выходе:**
- `rank` — позиция в ладдере
- `score` — текущий рейтинг
- `bestLevel` — лучший ключ (из scores API)
- `timed` — количество забегов в таймер
- `total` — общее количество забегов
- `bestTimedLevel` — лучший timed ключ
- `bestTimedDungeon` — данж лучшего timed ключа
- `bestOverallLevel` — лучший общий ключ
- `bestOverallDungeon` — данж лучшего общего ключа

**Запуск:**
```bat
tools\update.bat
# или
powershell -ExecutionPolicy Bypass -File tools\update_ladder.ps1
```

### 6.2 `tools/update.bat`

Обёртка для запуска PowerShell скрипта.

### 6.3 `.luacheckrc`

Конфигурация luacheck:
- Стандарт: `lua51c`
- Исключены: `.git`, `Libs/**`
- Глобалы: полный список WoW API (~2000+ функций)
- Игнорируемые: неиспользованные переменные, шадоуинг, пустые ветки

---

## 7. Конфигурация

### SavedVariables

- `SMPConfigDB` — AceDB (профили, глобальные настройки)
- `SMPOverlayDB` — кэш времен убийства боссов `{ [mapId] = { [bossName] = killTime } }`

### Дефолты конфига

```lua
{
    global = {
        dbVersion = 1,
        splits = {},
    },
    profile = {
        tooltip = {
            showSeparator = true,           -- Пустая строка перед заголовком
            showDungeonListAlways = false,   -- Всегда показывать список данжей
            abbreviateDungeons = false,      -- Сокращать названия (БАП, АГ, ...)
        },
        overlay = {
            insertKeystoneAutomatically = true,
            showMillisecondsWhenDungeonCompleted = false,
            showPullBar = true,              -- Предсказание пулла через неймплейты
            forcesFormat = ":percent:",       -- Формат текста сил
            currentPullFormat = "(+:percent:)", -- Формат текста пулла
            -- Glow (свечение)
            showForcesGlow = true,
            forcesGlowColor = "FF479AED",
            forcesGlowLineCount = 8,
            forcesGlowLength = 5,
            forcesGlowThickness = 2,
            forcesGlowFrequency = 0.2,
            -- Смерти
            showDeathsTooltip = true,
            deathLogStyle = "time",          -- "time" или "count"
            -- Сплиты
            splitsEnabled = false,
            showSplitRecords = "always",
            fallbackSplitBehavior = "none",
            -- Отображение
            frameScale = 1.0,
            framePadding = 8,
            alignTexts = "right",
            alignBarTexts = "right",
            alignBossClear = "start",
            verticalOffset = 4,
            objectivesOffset = 2,
            barPadding = 4,
            -- Цвета таймера
            timerRunningColor = "FFFFFFFF",
            timerSuccessColor = "FFFFD100",
            timerExpiredColor = "FFFF2020",
            -- Шрифты (все по умолчанию "Friz Quadrata TT")
            timerFont, timerFontSize(20), timerFontFlags("OUTLINE"),
            deathsFont, deathsFontSize(14), deathsFontFlags, deathsColor,
            keyFont, keyFontSize(14), keyFontFlags, keyColor,
            keyDetailsFont, keyDetailsFontSize(14), keyDetailsFontFlags, keyDetailsColor,
            objectivesFont, objectivesFontSize(14), objectivesFontFlags,
            objectivesColor, completedObjectivesColor,
            forcesFont, forcesFontSize(12), forcesFontFlags,
            forcesColor, completedForcesColor,
            -- Бары
            barWidth = 280,
            barHeight = 14,
            backdropTexture = "Solid",
            backdropTextureColor = "FF000000",
            bar1/2/3Font, bar1/2/3FontSize(12), bar1/2/3FontFlags,
            bar1/2/3Texture = "Solid", bar1/2/3TextureColor = "FFB3B3B3",
            forcesTexture = "Solid", forcesTextureColor = "FF479AED",
            forcesOverlayTexture = "Solid", forcesOverlayTextureColor = "FFFFD100",
        },
    },
}
```

### Панель настроек

Открывается через `/smp` или кнопку на миникарте. Вкладки:
- **Tooltip** — настройки тултипа
- **Overlay > General** — авто-вставка ключа, форматы текста, свечение
- **Overlay > Deaths** — настройки смертей
- **Overlay > Splits** — настройки сплитов
- **Overlay > Display** — масштаб, отступы, выравнивание, цвета
- **Overlay > Fonts** — шрифты для всех элементов
- **Overlay > Bars** — размеры и текстуры баров
- **Overlay > Demo** — демо-режим и блокировка
- **Profile** — профили AceDB

---

## 8. Команды

| Команда | Действие |
|---------|----------|
| `/smp` или `/mythicplus` | Открыть настройки |
| `/smp demo` | Вкл/выкл демо-режим |
| `/smp unlock` | Разблокировать оверлей |
| `/smp lock` | Заблокировать оверлей |
| `/smp toggle` | Переключить блокировку |
| `/smp minimap` | Показать кнопку на миникарте |
| `/smp minimap hide` | Скрыть кнопку на миникарте |
| `/smp check` | Принудительно проверить статус инстанса |
| `/smp poll stop` | Остановить polling |
| `/smp version` / `/smp ver` | Версия аддона |
| `/smp help` / `/smp ?` | Справка |

---

## 9. События

### WoW Events (зарегистрированы в SMPCore)

| Event | Действие |
|-------|----------|
| `PLAYER_ENTERING_WORLD` | `CheckChallenge()` — определение контекста |
| `CHALLENGE_MODE_COMPLETED` | `CompleteChallenge()` |
| `CHALLENGE_MODE_CANCEL` | `StopChallenge()` + `StopPolling()` |
| `CHALLENGE_MODE_DEATH_COUNT_UPDATED` | `UpdateDeaths()` |
| `INSTANCE_ENCOUNTERS_UPDATE(isForces)` | `UpdateForces()` или `UpdateBosses()` |
| `WORLD_STATE_TIMER_START` | `UpdateTimerState()` |
| `NAME_PLATE_UNIT_ADDED` | `OnNameplateAdded()` (pull tracking) |
| `NAME_PLATE_UNIT_REMOVED` | `OnNameplateRemoved()` (pull tracking) |

### WoW Events (зарегистрированы в SMPEventHandler)

| Event | Действие |
|-------|----------|
| `MYTHIC_PLUS_PLAYER_STAT_UPDATE` | Обновление тултипа |
| `CHALLENGE_MODE_SCORE_UPDATE` | Обновление тултипа |
| `CHALLENGE_MODE_MAPS_UPDATE` | Обновление тултипа |
| `LADDER_MYTHIC_PLUS_SEARCH_RESULT` | Обновление тултипа |
| `MODIFIER_STATE_CHANGED` | Обновление при модификаторах |

---

## 10. MessageBus

### События шины

| Событие | Источник | Данные |
|---------|----------|--------|
| `ChallengeStarted` | SMPCore | state |
| `ChallengeCompleted` | SMPCore | state |
| `ChallengeStopped` | SMPCore | — |
| `ChallengeStateChanged` | SMPCore | state |
| `TimerTick` | SMPCore (OnUpdate) | timer, timeLimit |
| `BossesUpdated` | SMPCore | bosses |
| `ForcesUpdated` | SMPCore | percent |
| `DeathsUpdated` | SMPCore | count, timeLost |
| `PullUpdated` | SMPCore | pullCount, pullPercent |
| `PullTrackingStarted` | SMPCore | — |
| `PullTrackingStopped` | SMPCore | — |
| `TimerStarted` | SMPCore | — |
| `ConfigChanged` | SMPConfig (AceDB callback) | — |
| `OverlayConfigChanged` | SMPCore (proxy) | — |

---

## 11. Pull Tracking (Nameplate)

Система предсказания прогресса пулла через неймплейты.

**Требование:** Новые неймплейты включены (`nameplateEnableNew = 1`).

**Как работает:**
1. При включении отслеживания регистрируются `NAME_PLATE_UNIT_ADDED/REMOVED`
2. Каждые 250мс (`PULL_TICK_INTERVAL`) вызывается `UpdatePullForces()`
3. Для каждого неймплейта проверяется, атакует ли он кого-то из группы
4. Если да — извлекается NPC ID из GUID, ищется в `SMPForcesData`
5. Сумма сил всех враждебных неймплейтов = `pullPercent`
6. Оверлей показывает `(+X.XX%)` и полосу предсказания

**CM_TO_AREA маппинг:**
```lua
[4]=523, [5]=848, [6]=838, [8]=534, [9]=525, [10]=835, [11]=522, [13]=722
```

---

## 12. Демо-режим

Включается через `/smp demo` или кнопку в настройках.

**Что делает:**
- Генерирует случайные данные: уровень ключа (5-25), таймер (5-30 мин), силы (10-95%), боссы (0-5 убито), смерти (0-8)
- Показывает оверлей с этими данными
- Позволяет настраивать позицию и внешний вид

**Команды в демо:**
- `/smp unlock` — перемещение оверлея
- `/smp lock` — фиксация
- `/smp demo` — выключение

---

## 13. Ladder Data Pipeline

### Обновление данных

1. Запустить `tools\update.bat`
2. Скрипт загружает ~800 страниц с API Sirus параллельно (16 воркеров)
3. Данные записываются в `Modules/Database/Data/LadderData.lua`
4. При загрузке аддона данные валидируются батчами по 500

### API Sirus

- `https://sirus.su/api/base/22/leaderboard/challenge/scores?page=N&week=1`
- `https://sirus.su/api/base/22/leaderboard/challenge/runs?page=N&timed=true`
- `https://sirus.su/api/base/22/leaderboard/challenge/runs?page=N`

### Данные в LadderData.lua

```lua
["ИмяИгрока"] = {
    rank = 1,           -- Позиция в ладдере
    score = 2150.5,     -- Рейтинг
    bestLevel = 18,     -- Лучший ключ (из scores)
    timed = 45,         -- Забегов в таймер
    total = 67,         -- Всего забегов
    bestTimedLevel = 18,
    bestTimedDungeon = "Крепость Утгард",
    bestOverallLevel = 20,
    bestOverallDungeon = "Чертоги Молний",
},
```

---

## 14. Зависимости (Libs)

| Библиотека | Версия | Назначение |
|------------|--------|-----------|
| LibStub | - | Менеджер библиотек |
| CallbackHandler-1.0 | 1.0 | Система callback'ов |
| AceAddon-3.0 | 3.0 | Фреймворк аддона |
| AceEvent-3.0 | 3.0 | Система событий |
| AceDB-3.0 | 3.0 | SavedVariables с профилями |
| AceConsole-3.0 | 3.0 | Slash-команды |
| AceConfig-3.0 | 3.0 | Панель настроек (Registry + Dialog + Cmd) |
| LibDataBroker-1.1 | 1.1 | Data broker для миникарты |
| LibDBIcon-1.0 | 1.0 | Кнопка на миникарте |
| LibCompat-1.0 | 1.0 | Полифилы для 3.3.5a |
| LibCustomGlow-1.0 | 1.0 | Анимации свечения |

---

## 15. Известные ограничения

1. **Нет данных сил для некоторых данжей** — `EnemyForcesData` покрывает только 9 данжей. Для остальных `SMPForcesData:GetTotal()` возвращает 900 (дефолт).

2. **Pull tracking требует новые неймплейты** — без `nameplateEnableNew = 1` предсказание пулла не работает. В настройках есть кнопка "Включить новые плейты".

3. **Ladder данные могут устареть** — `LadderData.lua` обновляется вручную через скрипт. Нет автообновления.

4. **C_Ladder.RequestSearch может падать** — на некоторых версиях Sirus API может быть нестабильным. Аддон делает pcall и отключает ладдер-ранг при ошибке.

5. **Boss kill time — клиентский таймер** — Sirus не присылает точное время убийства босса. Используется `GetWorldElapsedTime(1)` в момент получения `INSTANCE_ENCOUNTERS_UPDATE`.

6. **SMPOverlayDB хранит только последний забег** — при `StopChallenge()` данные очищаются. При `CompleteChallenge()` сохраняются.
