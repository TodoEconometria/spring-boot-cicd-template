# 🚀 Spring Boot CI/CD Template

Script automatizado que configura un pipeline completo de **CI/CD** para cualquier proyecto **Spring Boot** con **PostgreSQL** y **Docker**.

## ¿Qué hace?

Con un solo comando, tu proyecto tiene:

| Componente | Descripción |
|-----------|-------------|
| **GitHub Actions** | Pipeline que compila, testea y construye Docker en cada push |
| **Docker Compose** | App + PostgreSQL + Adminer, todo con un `docker compose up` |
| **Secretos seguros** | Contraseñas en `.env` (nunca en el código) |
| **Docker Hub** | Push automático de la imagen (opcional) |

## Uso rápido

### 1. Copia el script a tu proyecto

```bash
# Desde la raíz de tu proyecto Spring Boot:
curl -O https://raw.githubusercontent.com/TodoEconometria/spring-boot-cicd-template/main/setup_cicd.sh
chmod +x setup_cicd.sh
```

### 2. Edita la configuración

Abre `setup_cicd.sh` y cambia las variables al principio:

```bash
PROJECT_NAME="mi-proyecto"        # Nombre de tu proyecto
GITHUB_USER="tu-usuario"          # Tu usuario de GitHub
APP_PORT="8080"                   # Puerto de tu app
DB_NAME="mibasededatos"           # Nombre de la BD
DOCKERHUB_USER=""                 # Tu usuario de Docker Hub (opcional)
JAVA_VERSION="17"                 # Versión de Java
```

### 3. Ejecuta

```bash
./setup_cicd.sh
```

## Requisitos previos

- **Git** instalado
- **GitHub CLI** instalado y logueado (`gh auth login`)
- Un **repositorio en GitHub** (el script lo crea si no existe)
- **Docker** (opcional, solo para probar en local)

## ¿Qué genera?

```
tu-proyecto/
├── .env                          # Secretos (NO se sube a git)
├── .gitignore                    # Actualizado con .env
├── docker-compose.yml            # App + PostgreSQL + Adminer
├── Dockerfile                    # (ya existente en tu proyecto)
├── src/main/resources/
│   ├── application.properties         # (ya existente, perfil desarrollo)
│   └── application-docker.properties  # NUEVO: perfil para contenedores
└── .github/
    └── workflows/
        └── ci-cd.yml             # Pipeline completo
```

## El pipeline en detalle

```
Push a main/develop
    │
    ▼
┌─────────────────────┐
│  🔨 Build & Test    │  ← Compila con Maven
│                     │  ← Ejecuta tests con PostgreSQL real
│                     │  ← Sube reportes como artifact
└────────┬────────────┘
         │ (solo en main)
         ▼
┌─────────────────────┐
│  🐳 Docker Build    │  ← Construye imagen multi-stage
│                     │  ← Push a Docker Hub (si configurado)
│                     │  ← Caché con GitHub Actions cache
└─────────────────────┘
```

## Docker Compose en local

```bash
# Arrancar todo
docker compose up -d

# Ver logs
docker compose logs -f app

# Adminer (gestor visual de BD)
open http://localhost:9090

# Parar
docker compose down

# Parar y borrar datos de BD
docker compose down -v
```

## Configurar Docker Hub (opcional)

Si quieres que el pipeline suba la imagen automáticamente:

```bash
# 1. Crea un token en https://hub.docker.com/settings/security
# 2. Configura los secrets en GitHub:
gh secret set DOCKERHUB_USERNAME --repo tu-usuario/tu-proyecto
gh secret set DOCKERHUB_TOKEN --repo tu-usuario/tu-proyecto
```

## Tecnologías

- Java 17+ / Spring Boot
- PostgreSQL 16
- Docker & Docker Compose
- GitHub Actions
- Maven

## Licencia

MIT — Úsalo libremente en tus proyectos.
