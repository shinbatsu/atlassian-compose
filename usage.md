# Atlassian Keygen Usage Guide

## Содержание
- [Atlassian Keygen Usage Guide](#atlassian-keygen-usage-guide)
  - [Содержание](#содержание)
  - [Rust Keygen CLI (рекомендуется)](#rust-keygen-cli-рекомендуется)
    - [Сборка](#сборка)
    - [Использование](#использование)
    - [Флаги](#флаги)
    - [Примеры](#примеры)
  - [Java Agent](#java-agent)
    - [Список продуктов](#список-продуктов)
  - [Алгоритм генерации лицензии](#алгоритм-генерации-лицензии)

---

## Rust Keygen CLI (рекомендуется)

Быстрая и безопасная утилита для генерации лицензий, написанная на Rust.

### Сборка

```bash
cd rust-keygen
./build.sh              # сборка для текущей платформы
# или
cargo build --release   # через cargo напрямую
```

Бинарный файл: `rust-keygen/target/release/atlassian-keygen`

### Использование

```bash
./atlassian-keygen -p <product> -m <email> -n <name> -o <org> -s <server-id> [-d]
```

### Флаги

| Флаг | Описание                                                                                           |
| ---- | -------------------------------------------------------------------------------------------------- |
| `-p` | Продукт: `crowd`, `jira`, `conf`, `bitbucket`, `bamboo`, `fisheye`, `crucible`, `jsm`, `jc`, `jsd` |
| `-m` | Email лицензии (обязательно)                                                                       |
| `-n` | Имя пользователя (по умолчанию = email)                                                            |
| `-o` | Организация (обязательно)                                                                          |
| `-s` | Server ID (обязательно)                                                                            |
| `-d` | Data Center лицензия                                                                               |

### Примеры

**Crowd (Server):**
```bash
./atlassian-keygen -p crowd -m admin@company.com -n "Admin" -o "Company Ltd" -s ABCD-1234-EFGH-5678
```

**Crowd (Data Center):**
```bash
./atlassian-keygen -p crowd -m admin@company.com -n "Admin" -o "Company Ltd" -s ABCD-1234-EFGH-5678 -d
```

**Jira Software:**
```bash
./atlassian-keygen -p jira -m admin@company.com -n "Admin" -o "Company Ltd" -s ABCD-1234-EFGH-5678
```

**Confluence:**
```bash
./atlassian-keygen -p conf -m admin@company.com -n "Admin" -o "Company Ltd" -s ABCD-1234-EFGH-5678
```

**Bitbucket:**
```bash
./atlassian-keygen -p bitbucket -m admin@company.com -n "Admin" -o "Company Ltd" -s ABCD-1234-EFGH-5678 -d
```

---

## Java Agent

Оригинальная Java-версия:

```bash
java -jar ./agent/handler.jar -p <product> -m <email> -n <name> -o <org> -s <server-id> [-d]
```

### Список продуктов

```
crowd:       Crowd
jira:        JIRA Software
conf:        Confluence
bitbucket:   Bitbucket
bamboo:      Bamboo
fisheye:     FishEye
crucible:    Crucible
jsm:         JIRA Service Management
jc:          JIRA Core
jsd:         JIRA Service Desk
```

---

## Алгоритм генерации лицензии

```
1. Формирование данных: ключ=значение (даты, версия, тип, контакты)
2. Вычисление licenseHash: SHA-256 от отсортированных свойств
3. Формирование текста: #<timestamp>\n<key>=<value>\n...
4. Сжатие: zlib (Deflate)
5. Подпись: DSA-1024 / SHA-1
6. Упаковка: [4-байт длина][данные][DSA-подпись]
7. Base64: base64(data) + "X02" + hex(длина_распак)
8. Разбивка: по 76 символов в строке