# Juma — личный «Life OS» для iOS

MVP приложения для контроля жизни: задачи, привычки, база знаний и AI-сводка дня —
полностью on-device, без серверов и подписок.

## Что умеет (MVP)

- **Сегодня** — дашборд: AI-сводка дня, задачи на сегодня/просроченные, отметка привычек.
- **Задачи** — приоритеты, сроки, выполненные.
- **Привычки** — серии (streaks) и история за 7 дней.
- **Заметки** — база знаний с Markdown и поиском (мини-Obsidian).
- **Экспорт** — вся база одним файлом `.md` или `.json`, чтобы загрузить в ChatGPT/Claude
  как контекст о себе.

AI-сводка генерируется локальной моделью Apple Intelligence
(фреймворк **Foundation Models**, iOS 26): бесплатно, офлайн, данные не покидают устройство.
Если Apple Intelligence недоступен, показывается обычная (детерминированная) сводка.

## Требования

- **Xcode 26** (бесплатно из Mac App Store) — на этой машине пока установлены только
  Command Line Tools, для сборки нужен полный Xcode.
- iPhone с iOS 26. Для AI-сводки — модель с поддержкой Apple Intelligence
  (iPhone 15 Pro и новее) и включённый Apple Intelligence в Настройках.
- Аккаунт Apple ID. Для установки на своё устройство платный аккаунт не нужен
  (бесплатная подпись действует 7 дней); для TestFlight/App Store — Apple Developer
  Program ($99/год).

## Как запустить

1. Установить Xcode из Mac App Store и запустить его один раз (доустановит компоненты).
2. Открыть `Juma.xcodeproj`.
3. В настройках таргета **Juma → Signing & Capabilities** выбрать свой Team.
4. Выбрать симулятор iPhone или своё устройство и нажать **Run** (⌘R).

## Структура

```
Juma/
├── JumaApp.swift            — точка входа, TabView
├── Models/Models.swift      — SwiftData: TaskItem, Habit, HabitLog, Note
├── AI/DailySummaryService.swift — Foundation Models: @Generable-сводка + fallback
├── Views/
│   ├── TodayView.swift      — дашборд «Сегодня»
│   ├── TasksView.swift      — задачи + редактор
│   ├── HabitsView.swift     — привычки + редактор
│   ├── NotesView.swift      — заметки + Markdown-редактор
│   └── ExportView.swift     — экспорт и ShareLink
└── Export/ExportService.swift — генерация Markdown/JSON
```

## Дорожная карта (после MVP)

1. Финансы (ручной ввод, CSV-импорт) и HealthKit (шаги, сон).
2. Векторный поиск по заметкам (VecturaKit / ObjectBox) — «что я знаю о X».
3. CRM: импорт контактов из телефонной книги + LinkedIn CSV, детекция смены работы.
4. Telegram-бот для быстрого ввода, Outlook через Microsoft Graph.
5. RSS-новости с ранжированием локальной моделью, MCP-сервер для ChatGPT/Claude.
