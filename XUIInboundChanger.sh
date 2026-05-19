#!/bin/bash

# Стили и цвета
BOLD='\033[1m'
B_CYAN='\033[1;36m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_RED='\033[1;31m'
NC='\033[0m'

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo -e "${B_RED}Ошибка: Запустите от имени root.${NC}"
    exit 1
fi

echo -e "${B_CYAN}Конфигурация изменения ID инбаунда для X-UI${NC}"

# Пути к базе данных 3x-ui
DB_PATH="/etc/x-ui/x-ui.db"
BACKUP_PATH="/etc/x-ui/x-ui.db.bak"

# --- Автоматическая установка sqlite3 ---
if ! command -v sqlite3 &> /dev/null; then
    echo -e "${B_YELLOW}sqlite3 не найден. Запуск автоматической установки...${NC}"
    
    if command -v apt &> /dev/null; then
        apt update && apt install sqlite3 -y
    elif command -v dnf &> /dev/null; then
        dnf install sqlite -y
    elif command -v yum &> /dev/null; then
        yum install sqlite -y
    else
        echo -e "${B_RED}Ошибка: Не удалось определить менеджер пакетов. Установите sqlite3 вручную. Выход.${NC}"
        exit 1
    fi

    # Финальная проверка после попытки установки
    if ! command -v sqlite3 &> /dev/null; then
        echo -e "${B_RED}Ошибка: Установка sqlite3 завершилась неудачей. Выход.${NC}"
        exit 1
    fi
    echo -e "${B_GREEN}sqlite3 установлен${NC}"
fi

# Проверка наличия базы данных
if [ ! -f "$DB_PATH" ]; then
    echo -e "${B_RED}Ошибка: База данных не найдена по пути $DB_PATH. Выход.${NC}"
    exit 1
fi

# --- Запрос ID инбаундов ---
echo -e "${B_YELLOW}Введите параметры для замены ID инбаунда:${NC}"
read -p "Текущий ID инбаунда: " OLD_ID
read -p "Новый ID, который хотите присвоить: " NEW_ID

# Проверка ввода на соответствие числовому формату
if [[ ! "$OLD_ID" =~ ^[0-9]+$ ]] || [[ ! "$NEW_ID" =~ ^[0-9]+$ ]]; then
    echo -e "${B_RED}Ошибка: Неверный формат ID. Используйте только целые числа. Выход.${NC}"
    exit 1
fi

# Проверка на совпадение введенных ID
if [ "$OLD_ID" -eq "$NEW_ID" ]; then
    echo -e "${B_RED}Ошибка: Старый и новый ID совпадают. Изменения не требуются. Выход.${NC}"
    exit 1
fi

# Проверка: существует ли вообще инбаунд со старым ID
IS_OLD_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM inbounds WHERE id = $OLD_ID;")
if [ "$IS_OLD_EXISTS" -eq 0 ]; then
    echo -e "${B_RED}Ошибка: Инбаунд со старым ID $OLD_ID не найден в базе данных. Выход.${NC}"
    exit 1
fi

# Проверка: не занят ли уже новый ID кем-то другим
IS_NEW_BUSY=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM inbounds WHERE id = $NEW_ID;")
if [ "$IS_NEW_BUSY" -gt 0 ]; then
    echo -e "${B_RED}Ошибка: Новый ID $NEW_ID уже занят другим инбаундом. Выберите свободный ID. Выход.${NC}"
    exit 1
fi

# --- Процесс изменения ID ---
echo -e "${B_YELLOW}Создание резервной копии базы данных...${NC}"
cp "$DB_PATH" "$BACKUP_PATH"

echo -e "${B_YELLOW}Остановка службы x-ui...${NC}"
systemctl stop x-ui

echo -e "${B_YELLOW}Выполнение SQL-запроса...${NC}"
# Обновляем ID конкретного инбаунда
sqlite3 "$DB_PATH" "UPDATE inbounds SET id = $NEW_ID WHERE id = $OLD_ID;"

# Проверяем успешность выполнения команды
if [ $? -eq 0 ]; then
    echo -e "${B_GREEN}База данных успешно обновлена!${NC}"
    echo -e "ID инбаунда изменен с ${B_CYAN}$OLD_ID${NC} на ${B_CYAN}$NEW_ID${NC}."
else
    echo -e "${B_RED}Ошибка при выполнении SQL-запроса. Восстановление исходной базы...${NC}"
    cp "$BACKUP_PATH" "$DB_PATH"
fi

echo -e "${B_YELLOW}Запуск службы x-ui...${NC}"
systemctl start x-ui

echo -e "${B_GREEN}Процесс завершен! Проверьте изменения в панели.${NC}"