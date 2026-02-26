#!/bin/bash
# Автоматическое обновление версии манифеста
# Аргументы: 1) Репозиторий (user/repo), 2) Путь к манифесту

REPO_URL=$1
MANIFEST_FILE=$2

if [ -z "$REPO_URL" ] || [ -z "$MANIFEST_FILE" ]; then
    echo "Ошибка: Недостаточно аргументов."
    exit 1
fi

echo "Проверка релиза для: $REPO_URL"

# Получаем данные о последнем релизе
RELEASE_DATA=$(curl -s "https://api.github.com/repos/$REPO_URL/releases/latest")
if [ -z "$RELEASE_DATA" ]; then
    echo "Ошибка: Не удалось получить информацию о релизе."
    exit 1
fi

TAR_URL=$(echo "$RELEASE_DATA" | jq -r '.tarball_url')
VERSION_TAG=$(echo "$RELEASE_DATA" | jq -r '.tag_name')

echo "Найдена версия: $VERSION_TAG"
echo "URL архива: $TAR_URL"

# Скачиваем архив для подсчета SHA256
TEMP_FILE=$(mktemp)
curl -L -s "$TAR_URL" -o "$TEMP_FILE"
SHA256=$(sha256sum "$TEMP_FILE" | awk '{print $1}')
rm "$TEMP_FILE"

echo "Вычисленный SHA256: $SHA256"

# Обновляем JSON манифест
# ВАЖНО: Эта команда обновляет первый источник (sources[0]) в первом модуле (modules[0]).
# Если ваша структура JSON сложнее, адаптируйте команду jq.
tmp=$(mktemp)
jq --arg url "$TAR_URL" --arg sha "$SHA256" \
   '.modules[0].sources[0].url = $url | .modules[0].sources[0].sha256 = $sha' \
   "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"

echo "Манифест обновлен: $MANIFEST_FILE"
