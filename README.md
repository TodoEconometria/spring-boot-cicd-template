# Spring Boot CI/CD Template

Script **interactivo** que configura un pipeline completo de CI/CD para cualquier proyecto Spring Boot con PostgreSQL y Docker.

**No necesitas editar codigo** — solo ejecuta el script y responde las preguntas.

## Que hace

Con un solo comando:

- **GitHub Actions** — Pipeline que compila, testea y construye Docker en cada push
- **Docker Compose** — App + PostgreSQL + Adminer, todo con `docker compose up`
- **Secretos seguros** — Passwords en `.env` local (nunca suben a git) y tokens cifrados en GitHub Secrets
- **Docker Hub** — Push automatico de la imagen (opcional)

## Uso rapido

### 1. Copia el script a tu proyecto

```bash
cd tu-proyecto-spring-boot
curl -O https://raw.githubusercontent.com/TodoEconometria/spring-boot-cicd-template/main/setup_cicd.sh
chmod +x setup_cicd.sh
```

### 2. Ejecuta y responde las preguntas

```bash
./setup_cicd.sh
```

El script te pregunta:
```
  Nombre del proyecto [mi-proyecto]:
  Tu usuario de GitHub [tu-usuario]:
  Puerto de la app [8080]:
  Version de Java [17]:
  Nombre de la base de datos [mi-proyecto]:
  Password de PostgreSQL [generada-aleatoriamente]:
  Tu usuario de Docker Hub (vacio = saltar):
```

### 3. Listo

El script hace todo automaticamente:
- Crea `.env` con secretos (NO sube a git)
- Genera `docker-compose.yml` sin passwords hardcodeadas
- Crea el pipeline de GitHub Actions
- Hace commit y push
- Configura secrets en GitHub (cifrados)

## Requisitos

- **Git** instalado
- **GitHub CLI** (`gh`) instalado y logueado (`gh auth login`)
- Un proyecto Spring Boot con `pom.xml` y `Dockerfile`
- Docker (opcional, para probar en local)

## Donde quedan los secretos

| Secreto | Donde esta | Sube a GitHub? |
|---------|-----------|----------------|
| Password BD | `.env` en tu PC | NO (esta en .gitignore) |
| Token Docker Hub | GitHub Secrets (cifrado) | NO (nadie lo ve) |
| Password tests CI | Variable temporal en el pipeline | NO (se borra al terminar) |

## Que genera

```
tu-proyecto/
├── .env                              <- Secretos (NO se sube)
├── .gitignore                        <- Actualizado con .env
├── docker-compose.yml                <- App + PostgreSQL + Adminer
├── src/main/resources/
│   ├── application.properties        <- (tu archivo original)
│   └── application-ci.properties     <- NUEVO: perfil para CI
└── .github/workflows/
    └── ci-cd.yml                     <- Pipeline CI/CD
```

## Pipeline

```
Push a main/develop
       |
       v
 [Build & Test]     Compila + tests con PostgreSQL real
       |
       v (solo en main)
 [Docker Build]     Construye imagen + push a Docker Hub
```

## Probar en local

```bash
docker compose up -d              # Arrancar
docker compose logs -f app        # Ver logs
curl http://localhost:8080/api/... # Probar API
http://localhost:9090              # Adminer (ver BD)
docker compose down -v            # Parar
```

## Licencia

MIT
