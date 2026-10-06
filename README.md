# Roblox Open Cloud Update Manager

Servicio Node.js para consultar el historial de versiones de un Place de Roblox mediante Open Cloud.

## Requisitos

- Node.js 18 o superior.
- Una API key de Roblox Open Cloud con permiso de lectura necesario para el historial del Place.
- El Place ID correcto.
- No subir `.env` ni la API key a GitHub.

## Instalación

```bash
npm install
```

No hacen falta dependencias externas: `fetch` viene incluido en Node.js 18+.

Copia `.env.example` a `.env` y completa:

```env
PORT=3000
ROBLOX_PLACE_ID=123456789
ROBLOX_API_KEY=xxxxxxxx
ROBLOX_TO_MANAGER_SECRET=un-secreto-largo
CACHE_TTL_MS=12000
```

## Ejecutar

```bash
npm start
```

## Probar

Health:

```text
GET /health
```

Versión:

```text
GET /version
Header:
x-uts-secret: tu-secreto-largo
```

Ejemplo con curl:

```bash
curl -H "x-uts-secret: tu-secreto-largo" http://localhost:3000/version
```

Respuesta esperada:

```json
{
  "ok": true,
  "version": 123,
  "checkedAt": "2026-10-06T00:00:00.000Z",
  "source": "roblox-open-cloud",
  "stale": false
}
```

## Seguridad

La API key de Roblox solo existe en el servidor Node.js.

El juego de Roblox nunca recibe la API key. Para hablar con este servicio, Roblox usa únicamente `ROBLOX_TO_MANAGER_SECRET`.

No expongas el secreto en un LocalScript ni lo pongas en `ReplicatedStorage`.
