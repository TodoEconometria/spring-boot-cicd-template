#!/bin/bash
# ============================================================================
#  setup_cicd.sh — Script universal para CI/CD de proyectos Spring Boot
# ============================================================================
#  Configura automáticamente un pipeline completo de CI/CD para cualquier
#  proyecto Spring Boot con PostgreSQL y Docker.
#
#  ¿Qué hace?
#  ──────────
#  1. Inicializa git (si no existe)
#  2. Crea .env con secretos (contraseñas BD, Docker Hub)
#  3. Genera docker-compose.yml con variables de entorno (sin hardcodear)
#  4. Genera GitHub Actions workflow (CI/CD completo)
#  5. Genera application-docker.properties para producción
#  6. Hace el primer commit y push a GitHub
#  7. Configura los secrets en GitHub (Docker Hub)
#
#  USO RÁPIDO:
#  ───────────
#    1. Copia este script a la raíz de tu proyecto Spring Boot
#    2. Edita la sección "CONFIGURACIÓN" de abajo
#    3. Ejecuta:
#         chmod +x setup_cicd.sh
#         ./setup_cicd.sh
#
#  REQUISITOS:
#  ───────────
#    - Git instalado
#    - GitHub CLI (gh) instalado y logueado (gh auth login)
#    - Un repositorio creado en GitHub (puede estar vacío)
#    - Docker (opcional, solo para test local)
#
#  AUTOR: Jose Marco — https://github.com/TodoEconometria
#  REPO:  https://github.com/TodoEconometria/spring-boot-cicd-template
# ============================================================================

set -e

# ╔══════════════════════════════════════════════════════════════╗
# ║  CONFIGURACIÓN — CAMBIA ESTOS VALORES PARA TU PROYECTO     ║
# ╚══════════════════════════════════════════════════════════════╝

# Nombre de tu proyecto (se usa para imagen Docker, nombre BD, etc.)
PROJECT_NAME="mi-proyecto-spring"

# Tu usuario u organización de GitHub
GITHUB_USER="tu-usuario-github"

# Puerto de tu aplicación Spring Boot (mira server.port en application.properties)
APP_PORT="8080"

# Base de datos PostgreSQL
DB_NAME="mibasededatos"
DB_USER="postgres"
DB_PASSWORD="$(openssl rand -base64 16 2>/dev/null || echo 'CambiaEstaPassword123!')"

# Docker Hub (déjalo vacío si no tienes cuenta, el pipeline funciona igual)
DOCKERHUB_USER=""

# Versión de Java (debe coincidir con la de tu pom.xml)
JAVA_VERSION="17"

# ╔══════════════════════════════════════════════════════════════╗
# ║  A PARTIR DE AQUÍ NO NECESITAS TOCAR NADA                  ║
# ╚══════════════════════════════════════════════════════════════╝

# ─── Colores y funciones auxiliares ────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

paso() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ PASO $1: $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
info() { echo -e "${CYAN}  ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
error() { echo -e "${RED}  ❌ $1${NC}"; exit 1; }
ok() { echo -e "${GREEN}  ✔  $1${NC}"; }

# ─── Banner ────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   🚀 Setup CI/CD para Spring Boot + PostgreSQL + Docker    ║${NC}"
echo -e "${BOLD}${CYAN}║   Proyecto: ${PROJECT_NAME}$(printf '%*s' $((37 - ${#PROJECT_NAME})) '')║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ─── Verificaciones previas ────────────────────────────────────
if [ ! -f "pom.xml" ]; then
    error "No se encontró pom.xml. Ejecuta este script desde la raíz del proyecto Spring Boot."
fi

for cmd in git gh; do
    if ! command -v $cmd &>/dev/null; then
        error "Se necesita '$cmd'. Instálalo primero."
    fi
done

if ! gh auth status &>/dev/null; then
    error "No has iniciado sesión en GitHub CLI. Ejecuta: gh auth login"
fi

# Verificar que el repo existe en GitHub
if ! gh repo view "${GITHUB_USER}/${PROJECT_NAME}" &>/dev/null; then
    warn "El repo ${GITHUB_USER}/${PROJECT_NAME} no existe en GitHub."
    read -p "  ¿Quieres crearlo ahora? (s/n): " CREATE_REPO
    if [[ "$CREATE_REPO" =~ ^[sS]$ ]]; then
        gh repo create "${GITHUB_USER}/${PROJECT_NAME}" --public --description "Proyecto Spring Boot con CI/CD"
        ok "Repositorio creado en GitHub"
    else
        error "Crea el repo manualmente: gh repo create ${GITHUB_USER}/${PROJECT_NAME} --public"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# PASO 1: Archivo .env (secretos locales)
# ═══════════════════════════════════════════════════════════════
paso "1" "Creando archivo .env con secretos"

if [ -f ".env" ]; then
    warn ".env ya existe. Se mantiene el existente."
else
    cat > .env << EOF
# ════════════════════════════════════════════════
# Variables de entorno — NO SUBIR A GIT
# ════════════════════════════════════════════════
# Generado por setup_cicd.sh el $(date '+%Y-%m-%d %H:%M')

# Base de datos PostgreSQL
POSTGRES_DB=${DB_NAME}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}

# Aplicación Spring Boot
APP_PORT=${APP_PORT}
SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/${DB_NAME}
SPRING_DATASOURCE_USERNAME=${DB_USER}
SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}

# Docker Hub (rellenar cuando tengas cuenta)
DOCKERHUB_USERNAME=${DOCKERHUB_USER}
DOCKERHUB_TOKEN=
EOF
    ok "Archivo .env creado con contraseña generada aleatoriamente"
    info "Password BD generada: ${DB_PASSWORD}"
fi

# Asegurar que .env está en .gitignore
if [ ! -f ".gitignore" ]; then
    echo ".env" > .gitignore
    ok ".gitignore creado con .env"
elif ! grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo -e "\n# Secretos locales\n.env" >> .gitignore
    ok ".env añadido a .gitignore"
fi

# ═══════════════════════════════════════════════════════════════
# PASO 2: docker-compose.yml
# ═══════════════════════════════════════════════════════════════
paso "2" "Generando docker-compose.yml (sin secretos hardcodeados)"

# Backup si existe
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.bak
    info "Backup guardado: docker-compose.yml.bak"
fi

cat > docker-compose.yml << 'COMPOSE_EOF'
# ════════════════════════════════════════════════════════════════
# Docker Compose — Spring Boot + PostgreSQL + Adminer
# ════════════════════════════════════════════════════════════════
# Uso:
#   docker compose up -d          → Arrancar todo en background
#   docker compose logs -f app    → Ver logs de la aplicación
#   docker compose down           → Parar servicios
#   docker compose down -v        → Parar y borrar volúmenes (BD)
#
# Los valores se leen del archivo .env automáticamente.
# ════════════════════════════════════════════════════════════════

services:
  # ─── Tu aplicación Spring Boot ───────────────────────────────
  app:
    build: .
    ports:
      - "${APP_PORT:-8080}:${APP_PORT:-8080}"
    environment:
      - SPRING_DATASOURCE_URL=${SPRING_DATASOURCE_URL:-jdbc:postgresql://db:5432/mydb}
      - SPRING_DATASOURCE_USERNAME=${SPRING_DATASOURCE_USERNAME:-postgres}
      - SPRING_DATASOURCE_PASSWORD=${SPRING_DATASOURCE_PASSWORD:-secret}
      - SPRING_DATASOURCE_DRIVER_CLASS_NAME=org.postgresql.Driver
      - SPRING_JPA_DATABASE_PLATFORM=org.hibernate.dialect.PostgreSQLDialect
      - SPRING_JPA_HIBERNATE_DDL_AUTO=update
      - SPRING_SQL_INIT_MODE=never
      - SPRING_H2_CONSOLE_ENABLED=false
      - SPRING_PROFILES_ACTIVE=docker
    depends_on:
      db:
        condition: service_healthy
    restart: on-failure

  # ─── Base de datos PostgreSQL ────────────────────────────────
  db:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-mydb}
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-secret}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 5s
      timeout: 5s
      retries: 5

  # ─── Adminer (panel web para la BD) ─────────────────────────
  adminer:
    image: adminer
    ports:
      - "9090:8080"
    depends_on:
      db:
        condition: service_healthy

volumes:
  postgres_data:
COMPOSE_EOF

ok "docker-compose.yml generado"

# ═══════════════════════════════════════════════════════════════
# PASO 3: Perfil Docker para Spring Boot
# ═══════════════════════════════════════════════════════════════
paso "3" "Creando perfil Docker para Spring Boot"

PROPS_DIR="src/main/resources"
DOCKER_PROPS="${PROPS_DIR}/application-docker.properties"

if [ -d "$PROPS_DIR" ]; then
    if [ ! -f "$DOCKER_PROPS" ]; then
        cat > "$DOCKER_PROPS" << 'PROPS_EOF'
# ════════════════════════════════════════════════
# Perfil "docker" — Se activa automáticamente en contenedores
# ════════════════════════════════════════════════
# Las variables ${...} se resuelven desde el environment del docker-compose

spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.datasource.driver-class-name=org.postgresql.Driver

spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false

spring.h2.console.enabled=false
spring.sql.init.mode=never
PROPS_EOF
        ok "application-docker.properties creado"
    else
        warn "application-docker.properties ya existe, se mantiene"
    fi
else
    warn "No se encontró ${PROPS_DIR}. Crea application-docker.properties manualmente."
fi

# ═══════════════════════════════════════════════════════════════
# PASO 4: GitHub Actions Pipeline
# ═══════════════════════════════════════════════════════════════
paso "4" "Generando GitHub Actions CI/CD pipeline"

mkdir -p .github/workflows

cat > .github/workflows/ci-cd.yml << WORKFLOW_EOF
# ════════════════════════════════════════════════════════════════
# CI/CD Pipeline — Spring Boot + Docker
# ════════════════════════════════════════════════════════════════
# Se ejecuta en:
#   - Push a main o develop
#   - Pull requests hacia main
#
# Qué hace:
#   1. Compila con Maven y ejecuta todos los tests
#   2. Construye la imagen Docker
#   3. (Opcional) Sube la imagen a Docker Hub
#
# Secrets necesarios en GitHub → Settings → Secrets:
#   - DOCKERHUB_USERNAME  (opcional, para subir imagen)
#   - DOCKERHUB_TOKEN     (opcional, token de Docker Hub)
# ════════════════════════════════════════════════════════════════

name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  # ─── Job 1: Build + Test ─────────────────────────────────────
  build-and-test:
    name: "🔨 Build & Test"
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: ${DB_NAME}_test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: test_password
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=5s
          --health-timeout=5s
          --health-retries=5

    steps:
      - name: "📥 Checkout código"
        uses: actions/checkout@v4

      - name: "☕ Configurar JDK ${JAVA_VERSION}"
        uses: actions/setup-java@v4
        with:
          java-version: '${JAVA_VERSION}'
          distribution: 'temurin'
          cache: maven

      - name: "🧪 Compilar y ejecutar tests"
        run: mvn clean verify -B
        env:
          SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/${DB_NAME}_test
          SPRING_DATASOURCE_USERNAME: postgres
          SPRING_DATASOURCE_PASSWORD: test_password

      - name: "📊 Subir reportes de test"
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: target/surefire-reports/

  # ─── Job 2: Docker Build + Push ─────────────────────────────
  docker-build:
    name: "🐳 Docker Build"
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.ref == 'refs/heads/main'

    steps:
      - name: "📥 Checkout código"
        uses: actions/checkout@v4

      - name: "🐳 Configurar Docker Buildx"
        uses: docker/setup-buildx-action@v3

      - name: "🔑 Login en Docker Hub"
        if: \${{ secrets.DOCKERHUB_USERNAME != '' }}
        uses: docker/login-action@v3
        with:
          username: \${{ secrets.DOCKERHUB_USERNAME }}
          password: \${{ secrets.DOCKERHUB_TOKEN }}

      - name: "📋 Metadata de la imagen"
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: \${{ secrets.DOCKERHUB_USERNAME }}/\${{ github.event.repository.name }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: "🏗️ Construir y publicar imagen"
        uses: docker/build-push-action@v5
        with:
          context: .
          push: \${{ secrets.DOCKERHUB_USERNAME != '' }}
          tags: \${{ steps.meta.outputs.tags }}
          labels: \${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: "✅ Resumen"
        run: |
          echo "### 🐳 Docker Build Completado" >> \$GITHUB_STEP_SUMMARY
          echo "" >> \$GITHUB_STEP_SUMMARY
          echo "**Imagen construida correctamente**" >> \$GITHUB_STEP_SUMMARY
WORKFLOW_EOF

ok "Pipeline CI/CD creado en .github/workflows/ci-cd.yml"

# ═══════════════════════════════════════════════════════════════
# PASO 5: Inicializar Git
# ═══════════════════════════════════════════════════════════════
paso "5" "Configurando Git"

REMOTE_URL="https://github.com/${GITHUB_USER}/${PROJECT_NAME}.git"

if [ ! -d ".git" ]; then
    git init
    ok "Repositorio git inicializado"
else
    ok "Git ya inicializado"
fi

# Configurar remote
if git remote get-url origin &>/dev/null; then
    CURRENT_REMOTE=$(git remote get-url origin)
    if [ "$CURRENT_REMOTE" != "$REMOTE_URL" ]; then
        warn "Cambiando remote de $CURRENT_REMOTE a $REMOTE_URL"
        git remote set-url origin "$REMOTE_URL"
    fi
else
    git remote add origin "$REMOTE_URL"
fi
ok "Remote origin: $REMOTE_URL"

git branch -M main 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════
# PASO 6: Primer commit y push
# ═══════════════════════════════════════════════════════════════
paso "6" "Commit y push a GitHub"

git add -A

if git diff --cached --quiet 2>/dev/null; then
    info "No hay cambios nuevos que commitear"
else
    if git log --oneline -1 &>/dev/null 2>&1; then
        git commit -m "feat: añadir pipeline CI/CD y configuración Docker

- GitHub Actions: build, test con PostgreSQL, docker build & push
- docker-compose.yml con variables de entorno (sin hardcodear secretos)
- application-docker.properties para perfil de producción
- .env para secretos locales (no se sube a git)"
    else
        git commit -m "feat: proyecto inicial con CI/CD completo

- Aplicación Spring Boot
- Docker multi-stage build
- docker-compose (PostgreSQL + Adminer)
- GitHub Actions CI/CD pipeline
- Secretos externalizados via .env"
    fi
    ok "Commit creado"
fi

info "Haciendo push a GitHub..."
if git push -u origin main 2>&1; then
    ok "Push completado exitosamente"
else
    warn "El push falló. Puede que el repo tenga commits previos."
    info "Intenta manualmente:"
    info "  git pull origin main --allow-unrelated-histories"
    info "  git push -u origin main"
fi

# ═══════════════════════════════════════════════════════════════
# PASO 7: GitHub Secrets
# ═══════════════════════════════════════════════════════════════
paso "7" "Configurar GitHub Secrets (Docker Hub)"

if [ -n "$DOCKERHUB_USER" ]; then
    echo "$DOCKERHUB_USER" | gh secret set DOCKERHUB_USERNAME --repo "${GITHUB_USER}/${PROJECT_NAME}"
    ok "DOCKERHUB_USERNAME configurado en GitHub"
    echo ""
    warn "Falta configurar DOCKERHUB_TOKEN:"
    info "  1. Ve a https://hub.docker.com/settings/security"
    info "  2. Crea un Access Token"
    info "  3. Ejecuta:"
    info "     gh secret set DOCKERHUB_TOKEN --repo ${GITHUB_USER}/${PROJECT_NAME}"
else
    info "Docker Hub no configurado. El pipeline compilará y testeará"
    info "pero no subirá imagen a Docker Hub."
    info ""
    info "Para activar Docker Hub más tarde:"
    info "  gh secret set DOCKERHUB_USERNAME --repo ${GITHUB_USER}/${PROJECT_NAME}"
    info "  gh secret set DOCKERHUB_TOKEN --repo ${GITHUB_USER}/${PROJECT_NAME}"
fi

# ═══════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                    🎉 ¡SETUP COMPLETADO!                    ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}  📁 Archivos creados/modificados:${NC}"
echo -e "     • .env                              → Secretos locales"
echo -e "     • docker-compose.yml                → Servicios Docker"
echo -e "     • application-docker.properties      → Perfil producción"
echo -e "     • .github/workflows/ci-cd.yml       → Pipeline CI/CD"
echo ""
echo -e "${CYAN}  🔗 Enlaces:${NC}"
echo -e "     • Repo:     https://github.com/${GITHUB_USER}/${PROJECT_NAME}"
echo -e "     • Actions:  https://github.com/${GITHUB_USER}/${PROJECT_NAME}/actions"
echo -e "     • Adminer:  http://localhost:9090"
echo ""
echo -e "${CYAN}  🧪 Próximos pasos:${NC}"
echo -e "     1. docker compose up -d              → Probar localmente"
echo -e "     2. Abre http://localhost:${APP_PORT}  → Ver tu API"
echo -e "     3. Haz un cambio y push              → Ver CI/CD en acción"
echo ""
echo -e "${YELLOW}  ⚠️  RECUERDA: No subas el archivo .env a git${NC}"
echo ""
