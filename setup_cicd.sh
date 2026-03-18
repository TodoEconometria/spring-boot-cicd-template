#!/bin/bash
# ============================================================================
#  setup_cicd.sh — Script interactivo de CI/CD para Spring Boot
# ============================================================================
#  Configura un pipeline completo: GitHub Actions + Docker + Docker Hub
#  de forma INTERACTIVA — no necesitas editar nada, solo responder preguntas.
#
#  USO:
#    1. Copia este script a la raiz de tu proyecto Spring Boot
#    2. Ejecuta:  chmod +x setup_cicd.sh && ./setup_cicd.sh
#
#  REQUISITOS:
#    - Git instalado
#    - GitHub CLI (gh) instalado y logueado (gh auth login)
#    - Docker (opcional, para probar en local)
#
#  AUTOR: Jose Marco — https://github.com/TodoEconometria
#  REPO:  https://github.com/TodoEconometria/spring-boot-cicd-template
# ============================================================================

set -e

# ─── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

paso()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${GREEN}  PASO $1: $2${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
info()  { echo -e "${CYAN}  [i] $1${NC}"; }
warn()  { echo -e "${YELLOW}  [!] $1${NC}"; }
error() { echo -e "${RED}  [X] $1${NC}"; exit 1; }
ok()    { echo -e "${GREEN}  [OK] $1${NC}"; }

# Pregunta con valor por defecto
preguntar() {
    local mensaje="$1"
    local defecto="$2"
    local resultado
    if [ -n "$defecto" ]; then
        read -p "  $mensaje [$defecto]: " resultado
        echo "${resultado:-$defecto}"
    else
        read -p "  $mensaje: " resultado
        echo "$resultado"
    fi
}

# ─── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}+--------------------------------------------------------------+${NC}"
echo -e "${BOLD}${CYAN}|   Setup CI/CD para Spring Boot + PostgreSQL + Docker         |${NC}"
echo -e "${BOLD}${CYAN}|   github.com/TodoEconometria/spring-boot-cicd-template       |${NC}"
echo -e "${BOLD}${CYAN}+--------------------------------------------------------------+${NC}"
echo ""

# ─── Verificaciones previas ───────────────────────────────────
if [ ! -f "pom.xml" ]; then
    error "No se encontro pom.xml. Ejecuta este script desde la raiz de tu proyecto Spring Boot."
fi

for cmd in git gh; do
    if ! command -v $cmd &>/dev/null; then
        error "Necesitas '$cmd' instalado. Instala $cmd y vuelve a intentar."
    fi
done

if ! gh auth status &>/dev/null 2>&1; then
    error "No has iniciado sesion en GitHub CLI. Ejecuta primero: gh auth login"
fi

ok "Verificaciones previas correctas"

# ═══════════════════════════════════════════════════════════════
# PREGUNTAS INTERACTIVAS
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}Vamos a configurar tu proyecto. Responde estas preguntas:${NC}"
echo -e "${CYAN}(Pulsa ENTER para aceptar el valor entre corchetes)${NC}"
echo ""

# Detectar nombre del proyecto desde la carpeta actual
DETECTED_NAME=$(basename "$(pwd)")

PROJECT_NAME=$(preguntar "Nombre del proyecto" "$DETECTED_NAME")
GITHUB_USER=$(preguntar "Tu usuario de GitHub" "$(gh api user --jq '.login' 2>/dev/null)")

# Detectar puerto desde application.properties
DETECTED_PORT=$(grep -oP 'server\.port=\K\d+' src/main/resources/application.properties 2>/dev/null || echo "8080")
APP_PORT=$(preguntar "Puerto de la app (server.port)" "$DETECTED_PORT")

# Detectar version de Java desde pom.xml
DETECTED_JAVA=$(grep -oP '<java\.version>\K[^<]+' pom.xml 2>/dev/null || echo "17")
JAVA_VERSION=$(preguntar "Version de Java" "$DETECTED_JAVA")

DB_NAME=$(preguntar "Nombre de la base de datos" "$PROJECT_NAME")
DB_USER=$(preguntar "Usuario de PostgreSQL" "postgres")

# Generar password aleatoria
GENERATED_PW=$(openssl rand -hex 12 2>/dev/null || echo "Password$(date +%s)")
DB_PASSWORD=$(preguntar "Password de PostgreSQL (se genera una aleatoria)" "$GENERATED_PW")

echo ""
echo -e "${BOLD}Docker Hub (OPCIONAL — pulsa ENTER para saltar):${NC}"
echo -e "${CYAN}  Si no tienes cuenta, dejalo vacio. El pipeline funciona igual.${NC}"
DOCKERHUB_USER=$(preguntar "Tu usuario de Docker Hub (vacio = saltar)" "")

DOCKERHUB_TOKEN=""
if [ -n "$DOCKERHUB_USER" ]; then
    echo ""
    echo -e "${YELLOW}  IMPORTANTE: El token NO se guarda en ningun archivo.${NC}"
    echo -e "${YELLOW}  Se envia directamente a GitHub Secrets (cifrado).${NC}"
    read -sp "  Tu token de Docker Hub (no se muestra al escribir): " DOCKERHUB_TOKEN
    echo ""
fi

# ─── Confirmacion ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}Resumen de configuracion:${NC}"
echo -e "  Proyecto:      ${GREEN}$PROJECT_NAME${NC}"
echo -e "  GitHub:        ${GREEN}$GITHUB_USER/$PROJECT_NAME${NC}"
echo -e "  Puerto:        ${GREEN}$APP_PORT${NC}"
echo -e "  Java:          ${GREEN}$JAVA_VERSION${NC}"
echo -e "  BD:            ${GREEN}$DB_NAME (user: $DB_USER)${NC}"
if [ -n "$DOCKERHUB_USER" ]; then
    echo -e "  Docker Hub:    ${GREEN}$DOCKERHUB_USER${NC}"
else
    echo -e "  Docker Hub:    ${YELLOW}No configurado (opcional)${NC}"
fi
echo ""
read -p "  Todo correcto? (s/n) [s]: " CONFIRMAR
CONFIRMAR="${CONFIRMAR:-s}"
if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
    echo "Cancelado. Vuelve a ejecutar el script."
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# PASO 1: Crear repo en GitHub si no existe
# ═══════════════════════════════════════════════════════════════
paso "1/7" "Verificar repositorio en GitHub"

if gh repo view "${GITHUB_USER}/${PROJECT_NAME}" &>/dev/null 2>&1; then
    ok "Repo ${GITHUB_USER}/${PROJECT_NAME} ya existe"
else
    warn "El repo ${GITHUB_USER}/${PROJECT_NAME} no existe en GitHub."
    read -p "  Quieres crearlo ahora? (s/n) [s]: " CREAR
    CREAR="${CREAR:-s}"
    if [[ "$CREAR" =~ ^[sS]$ ]]; then
        gh repo create "${GITHUB_USER}/${PROJECT_NAME}" --public --description "Proyecto Spring Boot con CI/CD" 2>&1
        ok "Repositorio creado"
    else
        error "Crea el repo manualmente y vuelve a ejecutar."
    fi
fi

# ═══════════════════════════════════════════════════════════════
# PASO 2: Archivo .env (secretos locales)
# ═══════════════════════════════════════════════════════════════
paso "2/7" "Creando archivo .env (secretos locales)"

if [ -f ".env" ]; then
    warn ".env ya existe, se mantiene el actual."
else
    cat > .env << EOF
# ================================================
# SECRETOS LOCALES — NUNCA SUBIR A GIT
# ================================================
# Generado el $(date '+%Y-%m-%d %H:%M')

# Base de datos
POSTGRES_DB=${DB_NAME}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}

# Spring Boot
APP_PORT=${APP_PORT}
SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/${DB_NAME}
SPRING_DATASOURCE_USERNAME=${DB_USER}
SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}
EOF
    ok ".env creado (password: ${DB_PASSWORD})"
fi

# Asegurar .gitignore
if [ ! -f ".gitignore" ]; then
    echo -e ".env\n.env.*" > .gitignore
    ok ".gitignore creado"
elif ! grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo -e "\n# Secretos — NUNCA subir\n.env\n.env.*" >> .gitignore
    ok ".env anadido a .gitignore"
fi

# ═══════════════════════════════════════════════════════════════
# PASO 3: docker-compose.yml
# ═══════════════════════════════════════════════════════════════
paso "3/7" "Generando docker-compose.yml"

if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.bak
    info "Backup: docker-compose.yml.bak"
fi

cat > docker-compose.yml << 'COMPOSE_EOF'
# Docker Compose — Spring Boot + PostgreSQL + Adminer
# Los valores se leen del archivo .env automaticamente
#
# Uso:
#   docker compose up -d        (arrancar)
#   docker compose logs -f app  (ver logs)
#   docker compose down -v      (parar y borrar BD)

services:
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
      - SPRING_JPA_HIBERNATE_DDL_AUTO=create
      - SPRING_SQL_INIT_MODE=always
      - SPRING_JPA_DEFER_DATASOURCE_INITIALIZATION=true
      - SPRING_H2_CONSOLE_ENABLED=false
    depends_on:
      db:
        condition: service_healthy
    restart: on-failure

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

ok "docker-compose.yml generado (sin passwords en el codigo)"

# ═══════════════════════════════════════════════════════════════
# PASO 4: Perfil CI para tests
# ═══════════════════════════════════════════════════════════════
paso "4/7" "Creando perfiles de Spring Boot (CI + Docker)"

PROPS_DIR="src/main/resources"

# Perfil CI (para GitHub Actions)
if [ -d "$PROPS_DIR" ] && [ ! -f "$PROPS_DIR/application-ci.properties" ]; then
    cat > "$PROPS_DIR/application-ci.properties" << 'EOF'
# Perfil CI — GitHub Actions con PostgreSQL
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.datasource.driver-class-name=org.postgresql.Driver
spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.hibernate.ddl-auto=create-drop
spring.jpa.show-sql=true
spring.h2.console.enabled=false
spring.sql.init.mode=always
spring.jpa.defer-datasource-initialization=true
EOF
    ok "application-ci.properties creado"
fi

# ═══════════════════════════════════════════════════════════════
# PASO 5: GitHub Actions Workflow
# ═══════════════════════════════════════════════════════════════
paso "5/7" "Generando pipeline CI/CD (GitHub Actions)"

mkdir -p .github/workflows

# Determinar si incluir push a Docker Hub
if [ -n "$DOCKERHUB_USER" ]; then
    DOCKER_PUSH="true"
    DOCKER_TAGS="          tags: |
            $DOCKERHUB_USER/$PROJECT_NAME:latest
            $DOCKERHUB_USER/$PROJECT_NAME:\${{ github.sha }}"
    DOCKER_LOGIN="      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: \${{ secrets.DOCKERHUB_USERNAME }}
          password: \${{ secrets.DOCKERHUB_TOKEN }}

"
else
    DOCKER_PUSH="false"
    DOCKER_TAGS="          tags: ${PROJECT_NAME}:latest"
    DOCKER_LOGIN=""
fi

cat > .github/workflows/ci-cd.yml << WORKFLOW_EOF
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    name: Build & Test
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
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup JDK ${JAVA_VERSION}
        uses: actions/setup-java@v4
        with:
          java-version: '${JAVA_VERSION}'
          distribution: 'temurin'
          cache: maven

      - name: Build and test
        run: mvn clean verify -B
        env:
          SPRING_PROFILES_ACTIVE: ci
          SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/${DB_NAME}_test
          SPRING_DATASOURCE_USERNAME: postgres
          SPRING_DATASOURCE_PASSWORD: test_password

      - name: Upload test reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: target/surefire-reports/

  docker-build:
    name: Docker Build
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v3

${DOCKER_LOGIN}      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${DOCKER_PUSH}
${DOCKER_TAGS}
          cache-from: type=gha
          cache-to: type=gha,mode=max
WORKFLOW_EOF

ok "Pipeline creado en .github/workflows/ci-cd.yml"

# ═══════════════════════════════════════════════════════════════
# PASO 6: Git init + commit + push
# ═══════════════════════════════════════════════════════════════
paso "6/7" "Git: commit y push"

REMOTE_URL="https://github.com/${GITHUB_USER}/${PROJECT_NAME}.git"

if [ ! -d ".git" ]; then
    git init
    ok "Git inicializado"
fi

# Remote
if git remote get-url origin &>/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL"
else
    git remote add origin "$REMOTE_URL"
fi
ok "Remote: $REMOTE_URL"

git branch -M main 2>/dev/null || true
git add -A

if git diff --cached --quiet 2>/dev/null; then
    info "No hay cambios nuevos"
else
    git commit -m "feat: configurar CI/CD pipeline completo

- GitHub Actions (build + test + docker)
- docker-compose con PostgreSQL + Adminer
- Secretos en .env (no se suben a git)"
    ok "Commit creado"
fi

info "Haciendo push a GitHub..."
if git push -u origin main 2>&1; then
    ok "Push completado"
elif git pull origin main --allow-unrelated-histories --no-edit 2>&1 && git push -u origin main 2>&1; then
    ok "Push completado (se integraron cambios remotos)"
else
    warn "Push fallo. Ejecuta manualmente:"
    info "  git pull origin main --allow-unrelated-histories"
    info "  git push -u origin main"
fi

# ═══════════════════════════════════════════════════════════════
# PASO 7: GitHub Secrets (Docker Hub)
# ═══════════════════════════════════════════════════════════════
paso "7/7" "Configurar secretos en GitHub"

if [ -n "$DOCKERHUB_USER" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "$DOCKERHUB_USER" | gh secret set DOCKERHUB_USERNAME --repo "${GITHUB_USER}/${PROJECT_NAME}" 2>&1
    echo "$DOCKERHUB_TOKEN" | gh secret set DOCKERHUB_TOKEN --repo "${GITHUB_USER}/${PROJECT_NAME}" 2>&1
    ok "Secrets de Docker Hub configurados en GitHub (cifrados, nadie los ve)"
    # Limpiar variable de memoria
    unset DOCKERHUB_TOKEN
elif [ -n "$DOCKERHUB_USER" ]; then
    echo "$DOCKERHUB_USER" | gh secret set DOCKERHUB_USERNAME --repo "${GITHUB_USER}/${PROJECT_NAME}" 2>&1
    warn "Falta el token. Configuralo con:"
    info "  gh secret set DOCKERHUB_TOKEN --repo ${GITHUB_USER}/${PROJECT_NAME}"
else
    info "Docker Hub no configurado. El pipeline compila y testea pero no sube imagen."
    info "Para activarlo mas tarde:"
    info "  gh secret set DOCKERHUB_USERNAME --repo ${GITHUB_USER}/${PROJECT_NAME}"
    info "  gh secret set DOCKERHUB_TOKEN --repo ${GITHUB_USER}/${PROJECT_NAME}"
fi

# ═══════════════════════════════════════════════════════════════
# RESUMEN
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}+--------------------------------------------------------------+${NC}"
echo -e "${BOLD}${GREEN}|                  SETUP COMPLETADO                            |${NC}"
echo -e "${BOLD}${GREEN}+--------------------------------------------------------------+${NC}"
echo ""
echo -e "${CYAN}  Archivos creados:${NC}"
echo "     .env                           -> Secretos (NUNCA sube a git)"
echo "     docker-compose.yml             -> App + PostgreSQL + Adminer"
echo "     application-ci.properties      -> Perfil para tests en CI"
echo "     .github/workflows/ci-cd.yml    -> Pipeline CI/CD"
echo ""
echo -e "${CYAN}  Enlaces:${NC}"
echo "     Repo:     https://github.com/${GITHUB_USER}/${PROJECT_NAME}"
echo "     Actions:  https://github.com/${GITHUB_USER}/${PROJECT_NAME}/actions"
if [ -n "$DOCKERHUB_USER" ]; then
echo "     Docker:   https://hub.docker.com/r/${DOCKERHUB_USER}/${PROJECT_NAME}"
fi
echo ""
echo -e "${CYAN}  Probar en local:${NC}"
echo "     docker compose up -d              -> Arrancar todo"
echo "     curl http://localhost:${APP_PORT}  -> Probar la API"
echo "     http://localhost:9090              -> Adminer (ver BD)"
echo "     docker compose down -v            -> Parar y limpiar"
echo ""
echo -e "${CYAN}  Donde estan los secretos:${NC}"
echo "     Password BD:     Solo en .env (tu PC, nunca sube a git)"
echo "     Docker Hub:      Cifrado en GitHub Secrets (nadie lo ve)"
echo "     Tests CI:        Usa password temporal que se borra al terminar"
echo ""
echo -e "${YELLOW}  IMPORTANTE: NUNCA subas .env a git${NC}"
echo ""
