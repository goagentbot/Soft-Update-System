/**
 * Roblox Open Cloud Update Manager
 *
 * Node.js 18+ (usa fetch nativo)
 *
 * Funciones:
 *   GET /health
 *   GET /version
 *
 * /version requiere:
 *   x-uts-secret: <ROBLOX_TO_MANAGER_SECRET>
 *
 * Variables de entorno:
 *   PORT=3000
 *   ROBLOX_PLACE_ID=123456789
 *   ROBLOX_API_KEY=xxxxxxxx
 *   ROBLOX_TO_MANAGER_SECRET=xxxxxxxx
 *   CHECK_INTERVAL_MS=15000
 *   CACHE_TTL_MS=12000
 *
 * IMPORTANTE:
 * - NO pongas la API key en Roblox.
 * - NO subas .env a GitHub.
 */

const http = require("node:http");
const { URL } = require("node:url");

// --------------------------------------------------
// CONFIG
// --------------------------------------------------

const PORT = Number(process.env.PORT || 3000);
const PLACE_ID = String(process.env.ROBLOX_PLACE_ID || "").trim();
const API_KEY = String(process.env.ROBLOX_API_KEY || "").trim();
const SHARED_SECRET = String(
  process.env.ROBLOX_TO_MANAGER_SECRET || ""
).trim();

const CACHE_TTL_MS = Number(process.env.CACHE_TTL_MS || 12000);
const REQUEST_TIMEOUT_MS = 10000;

const ROBLOX_HISTORY_URL =
  `https://apis.roblox.com/place-version-history-api/v1/${PLACE_ID}/history`;

// --------------------------------------------------
// VALIDATION
// --------------------------------------------------

function validateConfig() {
  const errors = [];

  if (!PLACE_ID) {
    errors.push("Falta ROBLOX_PLACE_ID");
  }

  if (!API_KEY) {
    errors.push("Falta ROBLOX_API_KEY");
  }

  if (!SHARED_SECRET) {
    errors.push("Falta ROBLOX_TO_MANAGER_SECRET");
  }

  return errors;
}

const configErrors = validateConfig();

if (configErrors.length > 0) {
  console.error("[CONFIG] Configuración incompleta:");
  for (const error of configErrors) {
    console.error(`  - ${error}`);
  }
}

// --------------------------------------------------
// CACHE / STATE
// --------------------------------------------------

let cachedResult = {
  ok: false,
  version: null,
  checkedAt: null,
  source: "roblox-open-cloud",
  error: "No comprobado todavía"
};

let lastSuccessfulCheck = 0;
let inFlightRequest = null;

// --------------------------------------------------
// HELPERS
// --------------------------------------------------

function isFiniteInteger(value) {
  return Number.isFinite(value) && Number.isInteger(value);
}

function normalizeCandidate(value) {
  if (typeof value === "number") {
    if (isFiniteInteger(value) && value >= 0) {
      return value;
    }
    return null;
  }

  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();

  if (!/^\d+$/.test(trimmed)) {
    return null;
  }

  const number = Number(trimmed);

  if (!isFiniteInteger(number) || number < 0) {
    return null;
  }

  return number;
}

/**
 * Intenta extraer el número de versión del formato de respuesta.
 *
 * La API experimental puede cambiar de forma, así que aceptamos
 * varios nombres habituales sin ejecutar nada del contenido remoto.
 */
function extractVersion(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  // Caso habitual: { versions: [ { version: 123, ... } ] }
  if (Array.isArray(payload.versions) && payload.versions.length > 0) {
    for (const item of payload.versions) {
      if (!item || typeof item !== "object") continue;

      for (const key of [
        "version",
        "versionNumber",
        "placeVersion",
        "versionId",
        "id"
      ]) {
        const candidate = normalizeCandidate(item[key]);
        if (candidate !== null) {
          return candidate;
        }
      }
    }
  }

  // Variantes por si Roblox cambia el envoltorio.
  for (const key of [
    "version",
    "versionNumber",
    "placeVersion",
    "latestVersion",
    "latestPlaceVersion"
  ]) {
    const candidate = normalizeCandidate(payload[key]);
    if (candidate !== null) {
      return candidate;
    }
  }

  // Último recurso: buscar objetos con campos de versión.
  const queue = [payload];
  const visited = new Set();

  while (queue.length > 0) {
    const current = queue.shift();

    if (!current || typeof current !== "object") {
      continue;
    }

    if (visited.has(current)) {
      continue;
    }

    visited.add(current);

    for (const key of Object.keys(current)) {
      const value = current[key];

      if (
        typeof value === "string" ||
        typeof value === "number"
      ) {
        const normalized = normalizeCandidate(value);

        if (
          normalized !== null &&
          /version/i.test(key)
        ) {
          return normalized;
        }
      }

      if (value && typeof value === "object") {
        queue.push(value);
      }
    }
  }

  return null;
}

function sendJson(res, statusCode, data) {
  const body = JSON.stringify(data);

  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Content-Length": Buffer.byteLength(body)
  });

  res.end(body);
}

function unauthorized(res) {
  sendJson(res, 401, {
    ok: false,
    error: "Unauthorized"
  });
}

async function fetchRobloxHistory() {
  if (configErrors.length > 0) {
    throw new Error(
      `Servidor mal configurado: ${configErrors.join("; ")}`
    );
  }

  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    REQUEST_TIMEOUT_MS
  );

  try {
    const response = await fetch(ROBLOX_HISTORY_URL, {
      method: "GET",
      headers: {
        "x-api-key": API_KEY,
        "Accept": "application/json"
      },
      signal: controller.signal
    });

    const rawText = await response.text();

    let payload = null;

    try {
      payload = JSON.parse(rawText);
    } catch {
      throw new Error(
        `Roblox devolvió una respuesta no-JSON (HTTP ${response.status}).`
      );
    }

    if (!response.ok) {
      const detail =
        payload?.message ||
        payload?.error ||
        payload?.errors ||
        `HTTP ${response.status}`;

      throw new Error(
        `Open Cloud respondió ${response.status}: ${JSON.stringify(detail)}`
      );
    }

    const version = extractVersion(payload);

    if (version === null) {
      // No imprimimos toda la respuesta para no llenar logs.
      const keys =
        payload && typeof payload === "object"
          ? Object.keys(payload)
          : [];

      throw new Error(
        `No pude encontrar la versión en la respuesta de Roblox. ` +
        `Claves recibidas: ${keys.join(", ") || "ninguna"}`
      );
    }

    return {
      version,
      checkedAt: new Date().toISOString()
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function checkLatestVersion(force = false) {
  const now = Date.now();

  if (
    !force &&
    cachedResult.ok &&
    now - lastSuccessfulCheck < CACHE_TTL_MS
  ) {
    return cachedResult;
  }

  // Evita que varias peticiones hagan el mismo request simultáneamente.
  if (inFlightRequest) {
    return inFlightRequest;
  }

  inFlightRequest = (async () => {
    try {
      const result = await fetchRobloxHistory();

      cachedResult = {
        ok: true,
        version: result.version,
        checkedAt: result.checkedAt,
        source: "roblox-open-cloud"
      };

      lastSuccessfulCheck = Date.now();

      console.log(
        `[OpenCloud] Place ${PLACE_ID} -> versión ${result.version}`
      );

      return cachedResult;
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : String(error);

      console.error("[OpenCloud] Error:", message);

      cachedResult = {
        ok: false,
        version: cachedResult.version,
        checkedAt: cachedResult.checkedAt,
        source: "roblox-open-cloud",
        error: message
      };

      return cachedResult;
    } finally {
      inFlightRequest = null;
    }
  })();

  return inFlightRequest;
}

// --------------------------------------------------
// HTTP SERVER
// --------------------------------------------------

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(
      req.url || "/",
      `http://${req.headers.host || "localhost"}`
    );

    // GET /health
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, {
        ok: true,
        service: "roblox-opencloud-update-manager",
        placeId: PLACE_ID || null,
        configured: configErrors.length === 0,
        time: new Date().toISOString()
      });

      return;
    }

    // GET /version
    if (req.method === "GET" && url.pathname === "/version") {
      const secret =
        String(req.headers["x-uts-secret"] || "");

      if (!SHARED_SECRET || secret !== SHARED_SECRET) {
        unauthorized(res);
        return;
      }

      const force =
        url.searchParams.get("force") === "true";

      const result =
        await checkLatestVersion(force);

      // Si nunca conseguimos una versión, damos 503.
      if (!result.ok && result.version === null) {
        sendJson(res, 503, {
          ok: false,
          version: null,
          checkedAt: result.checkedAt,
          source: result.source,
          error: result.error
        });

        return;
      }

      // Si falló una consulta pero tenemos una versión anterior,
      // devolvemos esa última versión conocida.
      sendJson(res, 200, {
        ok: result.ok,
        version: result.version,
        checkedAt: result.checkedAt,
        source: result.source,
        stale: !result.ok
      });

      return;
    }

    sendJson(res, 404, {
      ok: false,
      error: "Not Found"
    });
  } catch (error) {
    console.error("[HTTP] Error:", error);

    sendJson(res, 500, {
      ok: false,
      error: "Internal Server Error"
    });
  }
});

// --------------------------------------------------
// OPTIONAL BACKGROUND CHECK
// --------------------------------------------------

async function backgroundLoop() {
  while (true) {
    await checkLatestVersion(false);

    await new Promise((resolve) =>
      setTimeout(resolve, CACHE_TTL_MS)
    );
  }
}

server.listen(PORT, () => {
  console.log("========================================");
  console.log("Roblox Open Cloud Update Manager");
  console.log("========================================");
  console.log(`HTTP:      http://localhost:${PORT}`);
  console.log(`Health:    http://localhost:${PORT}/health`);
  console.log(`Version:   http://localhost:${PORT}/version`);
  console.log(`Place ID:  ${PLACE_ID || "NOT SET"}`);
  console.log("========================================");

  if (configErrors.length === 0) {
    // Primera comprobación inmediata.
    checkLatestVersion(true);

    // El servidor mantiene la caché caliente.
    backgroundLoop().catch((error) => {
      console.error("[Loop] Error fatal:", error);
    });
  }
});

process.on("SIGINT", () => {
  console.log("\n[Server] Cerrando...");
  server.close(() => process.exit(0));
});

process.on("SIGTERM", () => {
  console.log("\n[Server] Cerrando...");
  server.close(() => process.exit(0));
});
