#!/bin/bash
# Автоматическое обновление версии манифеста
# Аргументы: 1) Репозиторий (user/repo), 2) Путь к манифесту
#
# Пример: ./update_manifest.sh "user/repo" "manifests/com.app.MyApp.json"

set -e

REPO_URL=$1
MANIFEST_FILE=$2

# ============================================
# Проверка аргументов
# ============================================
if [ -z "$REPO_URL" ]; then
    echo "❌ Ошибка: Не указан репозиторий (аргумент 1)"
    echo "Использование: $0 <user/repo> <путь_к_манифесту>"
    exit 1
fi

if [ -z "$MANIFEST_FILE" ]; then
    echo "❌ Ошибка: Не указан путь к манифесту (аргумент 2)"
    echo "Использование: $0 <user/repo> <путь_к_манифесту>"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "❌ Ошибка: Манифест не найден: $MANIFEST_FILE"
    exit 1
fi

echo "📋 Репозиторий: $REPO_URL"
echo "📋 Манифест: $MANIFEST_FILE"

# ============================================
# Получение информации о релизе
# ============================================
echo ""
echo "🔍 Проверка последнего релиза..."

RELEASE_DATA=$(curl -s --fail "https://api.github.com/repos/$REPO_URL/releases/latest" 2>/dev/null)

if [ -z "$RELEASE_DATA" ]; then
    echo "❌ Ошибка: Не удалось получить информацию о релизе"
    echo "   Проверьте, что репозиторий существует и имеет публичные релизы"
    exit 1
fi

TAR_URL=$(echo "$RELEASE_DATA" | jq -r '.tarball_url // empty')
VERSION_TAG=$(echo "$RELEASE_DATA" | jq -r '.tag_name // empty')

if [ -z "$TAR_URL" ] || [ "$TAR_URL" = "null" ]; then
    echo "❌ Ошибка: Не удалось получить URL архива из релиза"
    exit 1
fi

if [ -z "$VERSION_TAG" ] || [ "$VERSION_TAG" = "null" ]; then
    echo "❌ Ошибка: Не удалось получить тег версии из релиза"
    exit 1
fi

echo "✅ Найдена версия: $VERSION_TAG"
echo "✅ URL архива: $TAR_URL"

# ============================================
# Проверка текущей версии в манифесте
# ============================================
CURRENT_URL=$(jq -r '.modules[0].sources[0].url // empty' "$MANIFEST_FILE" 2>/dev/null)

if [ "$CURRENT_URL" = "$TAR_URL" ]; then
    echo ""
    echo "ℹ️  Манифест уже содержит актуальную версию ($VERSION_TAG)"
    echo "   Обновление не требуется"
    exit 0
fi

# ============================================
# Скачивание и вычисление SHA256
# ============================================
echo ""
echo "⬇️  Скачивание архива для вычисления SHA256..."

TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

HTTP_CODE=$(curl -L -s -w "%{http_code}" -o "$TEMP_FILE" "$TAR_URL")

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Ошибка: Не удалось скачать архив (HTTP $HTTP_CODE)"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$TEMP_FILE" 2>/dev/null || stat -f%z "$TEMP_FILE" 2>/dev/null)
echo "✅ Скачано: $(( FILE_SIZE / 1024 )) КБ"

SHA256=$(sha256sum "$TEMP_FILE" | awk '{print $1}')

if [ -z "$SHA256" ]; then
    echo "❌ Ошибка: Не удалось вычислить SHA256"
    exit 1
fi

echo "✅ SHA256: $SHA256"

# ============================================
# Обновление манифеста
# ============================================
echo ""
echo "📝 Обновление манифеста..."

# Проверяем структуру манифеста
MODULES_COUNT=$(jq '.modules | length' "$MANIFEST_FILE" 2>/dev/null)
if [ -z "$MODULES_COUNT" ] || [ "$MODULES_COUNT" = "0" ]; then
    echo "❌ Ошибка: Манифест не содержит модулей (modules)"
    exit 1
fi

SOURCES_COUNT=$(jq '.modules[0].sources | length' "$MANIFEST_FILE" 2>/dev/null)
if [ -z "$SOURCES_COUNT" ] || [ "$SOURCES_COUNT" = "0" ]; then
    echo "❌ Ошибка: Первый модуль не содержит источников (sources)"
    exit 1
fi

# Обновляем URL и SHA256
tmp=$(mktemp)
jq --arg url "$TAR_URL" --arg sha "$SHA256" \
   '.modules[0].sources[0].url = $url | .modules[0].sources[0].sha256 = $sha' \
   "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Манифест успешно обновлён!"
    echo ""
    echo "📊 Изменения:"
    echo "   Версия: $VERSION_TAG"
    echo "   URL: $TAR_URL"
    echo "   SHA256: $SHA256"
else
    echo "❌ Ошибка при обновлении манифеста"
    exit 1
fi
