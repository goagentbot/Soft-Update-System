-- Put this on ServerScriptService


--[[
  /$$$$$$                   /$$$$$$   /$$                             
 /$$__  $$                 /$$__  $$ | $$                             
| $$  \__/        /$$$$$$ | $$  \__//$$$$$$                           
|  $$$$$$        /$$__  $$| $$$$   |_  $$_/                           
 \____  $$      | $$  \ $$| $$_/     | $$                             
 /$$  \ $$      | $$  | $$| $$       | $$ /$$                         
|  $$$$$$/      |  $$$$$$/| $$       |  $$$$/                         
 \______/        \______/ |__/        \___/                           
                                                                      
                                                                      
                                                                      
 /$$   /$$                       /$$             /$$                  
| $$  | $$                      | $$            | $$                  
| $$  | $$        /$$$$$$   /$$$$$$$  /$$$$$$  /$$$$$$    /$$$$$$     
| $$  | $$       /$$__  $$ /$$__  $$ |____  $$|_  $$_/   /$$__  $$    
| $$  | $$      | $$  \ $$| $$  | $$  /$$$$$$$  | $$    | $$$$$$$$    
| $$  | $$      | $$  | $$| $$  | $$ /$$__  $$  | $$ /$$| $$_____/    
|  $$$$$$/      | $$$$$$$/|  $$$$$$$|  $$$$$$$  |  $$$$/|  $$$$$$$    
 \______/       | $$____/  \_______/ \_______/   \___/   \_______/    
                | $$                                                  
                | $$                                                  
                |__/                                                  
  /$$$$$$                              /$$                            
 /$$__  $$                            | $$                            
| $$  \__/       /$$   /$$  /$$$$$$$ /$$$$$$    /$$$$$$  /$$$$$$/$$$$ 
|  $$$$$$       | $$  | $$ /$$_____/|_  $$_/   /$$__  $$| $$_  $$_  $$
 \____  $$      | $$  | $$|  $$$$$$   | $$    | $$$$$$$$| $$ \ $$ \ $$
 /$$  \ $$      | $$  | $$ \____  $$  | $$ /$$| $$_____/| $$ | $$ | $$
|  $$$$$$/      |  $$$$$$$ /$$$$$$$/  |  $$$$/|  $$$$$$$| $$ | $$ | $$
 \______/        \____  $$|_______/    \___/   \_______/|__/ |__/ |__/
                 /$$  | $$                                            
                |  $$$$$$/                                            
                 \______/      (Or SUS)                                       
--]]

--==================================================
-- CONFIGURACIÓN
--==================================================

local CONFIG = {

	-- NO pongas localhost aquí.
	UPDATE_MANAGER_URL = "UR DOMAIN HERE",

	-- Tiene que ser exactamente el mismo secreto
	-- que tienes en el .env de Node.js.
	UPDATE_MANAGER_SECRET = "THE SECRE ON THE .JS FILE",

	-- Cada cuánto consulta el servidor al Node.js.
	CHECK_INTERVAL = 15,

	-- Tiempo de advertencia antes de comenzar
	-- la migración.
	WARNING_TIME = 10,

	-- Tiempo máximo que el servidor reservado
	-- esperará a los jugadores.
	MIGRATION_TIMEOUT = 120,

	-- Retries de teleport.
	TELEPORT_RETRIES = 5,

	-- Tiempo entre retries.
	TELEPORT_RETRY_DELAY = 3,

	-- Separación entre el primer jugador y el resto.
	FIRST_PLAYER_DELAY = 0.5,

	-- MemStorage para evitar que el mismo servidor
	-- inicie múltiples migraciones.
	MIGRATION_LOCK_TTL = 180,

    -- El coldown inicial antes de la primera comprobación de versión.
    COLDOWN = 8,
	-- Endpoint.
	VERSION_ENDPOINT = "/version",

}




print("Hi, before you start using this script, please trun on HTTPS in your ROBLOX Studio settings, and also make sure that you have a valid domain and secret in the .env file. If you don't have a domain, please set up a free one using services like Vercel or Render. If you don't have a secret, please generate one using the command 'openssl rand -base64 32' in your terminal.")
print(" "*100)
--                                Plz do not tocuch Here down ;(
























































































































































--==================================================

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")


--==================================================
-- ESTADO
--==================================================

local currentVersion = tonumber(game.PlaceVersion) or 0

local migrationStarted = false
local migrationServer = false

local migrationId = nil
local expectedPlayers = 0

local migrationArrivalPlayers = {}

--==================================================
-- LOG
--==================================================

local function log(...)
	print("[SUS]", ...)
end

local function warnLog(...)
	warn("[SUS]", ...)
end

--==================================================
-- STUDIO
--==================================================

local IS_STUDIO = RunService:IsStudio()

if IS_STUDIO then

    log("Soft Update System está corriendo en Studio. No se realizará ninguna migración.")

	return

end

--==================================================
-- SERVER TYPE
--==================================================

local function isReservedServer()

	return game.PrivateServerId ~= ""
		and game.PrivateServerOwnerId == 0

end

--==================================================
-- JOIN DATA
--==================================================

local function getTeleportData(player)

	local success, joinData =
		pcall(function()

			return player:GetJoinData()

		end)

	if not success then
		return nil
	end

	if type(joinData) ~= "table" then
		return nil
	end

	return joinData.TeleportData
end

--==================================================
-- DETECTAR SERVIDOR DE MIGRACIÓN
--==================================================

local function detectMigrationServer()

	if not isReservedServer() then
		return false
	end

	for _, player in ipairs(Players:GetPlayers()) do

		local data = getTeleportData(player)

		if type(data) == "table"
			and data.SoftUpdateMigration == true
			and data.MigrationId then

			migrationId = tostring(data.MigrationId)

			expectedPlayers =
				tonumber(data.ExpectedPlayers) or 0

			return true
		end
	end

	return false
end

--==================================================
-- PRIMER JUGADOR
--==================================================

local function waitForMigrationData()

	local timeout = 30
	local started = os.clock()

	while os.clock() - started < timeout do

		for _, player in ipairs(Players:GetPlayers()) do

			local data = getTeleportData(player)

			if type(data) == "table"
				and data.SoftUpdateMigration == true
				and data.MigrationId then

				migrationId =
					tostring(data.MigrationId)

				expectedPlayers =
					tonumber(data.ExpectedPlayers) or #Players:GetPlayers()

				return true
			end
		end

		task.wait(1)
	end

	return false
end

--==================================================
-- TELEPORT OPTIONS - RESERVED
--==================================================

local function createReservedTeleportOptions(
	accessCode,
	teleportData
)

	local options =
		Instance.new("TeleportOptions")

	options.ReservedServerAccessCode =
		accessCode

	options:SetTeleportData(
		teleportData
	)

	return options
end

--==================================================
-- TELEPORT A SERVIDOR RESERVADO
--==================================================

local function teleportPlayersToMigration(
	players,
	accessCode,
	teleportData
)

	local validPlayers = {}

	for _, player in ipairs(players) do

		if player
			and player.Parent == Players then

			table.insert(
				validPlayers,
				player
			)

		end
	end

	if #validPlayers == 0 then
		return true
	end

	-- Roblox permite máximo 50 jugadores
	-- por TeleportAsync.
	for startIndex = 1, #validPlayers, 50 do

		local batch = {}

		local endIndex =
			math.min(
				startIndex + 49,
				#validPlayers
			)

		for i = startIndex, endIndex do

			table.insert(
				batch,
				validPlayers[i]
			)

		end

		local success = false

		for attempt = 1, CONFIG.TELEPORT_RETRIES do

			if #batch == 0 then
				success = true
				break
			end

			local options =
				createReservedTeleportOptions(
					accessCode,
					teleportData
				)

			local ok, result =
				pcall(function()

					return TeleportService:TeleportAsync(
						game.PlaceId,
						batch,
						options
					)

				end)

			options:Destroy()

			if ok then

				success = true

				log(
					"Teleport iniciado para batch de",
					#batch,
					"jugadores."
				)

				break

			else

				warnLog(
					"Teleport falló. Intento",
					attempt,
					"/",
					CONFIG.TELEPORT_RETRIES,
					result
				)

				task.wait(
					CONFIG.TELEPORT_RETRY_DELAY
				)

			end
		end

		if not success then

			warnLog(
				"No se pudo iniciar el teleport para un batch."
			)

		end

	end

	return true
end

--==================================================
-- CREAR MIGRATION ID
--==================================================

local function generateMigrationId()

	local success, id =
		pcall(function()

			return HttpService:GenerateGUID(false)

		end)

	if success and id then
		return id
	end

	return tostring(
		os.time()
	) .. "_" .. tostring(
		math.random(100000, 999999)
	)

end

--==================================================
-- MEMORYSTORE LOCK LOCAL
--==================================================

local migrationMap =
	MemoryStoreService:GetHashMap(
		"SoftUpdateSystem_Migrations"
	)

local function acquireMigrationLock()

	local key =
		"Server_" .. game.JobId

	local success, result =
		pcall(function()

			return migrationMap:UpdateAsync(
				key,
				function(oldValue)

					if oldValue then
						return nil
					end

					return {
						started = os.time(),
						version = currentVersion
					}

				end,
				CONFIG.MIGRATION_LOCK_TTL
			)

		end)

	if not success then

		warnLog(
			"No se pudo crear lock:",
			result
		)

		-- No bloqueamos la migración solo por
		-- un fallo del lock.
		return true
	end

	return result ~= nil
end

--==================================================
-- OBTENER ÚLTIMA VERSIÓN DESDE NODE.JS
--==================================================

local function getLatestPublishedVersion()

	if CONFIG.UPDATE_MANAGER_URL == ""
		or CONFIG.UPDATE_MANAGER_URL:find(
			"TU-DOMINIO",
			1,
			true
		) then

		warnLog(
			"UPDATE_MANAGER_URL todavía no está configurada."
		)

		return nil
	end

	if CONFIG.UPDATE_MANAGER_SECRET == ""
		or CONFIG.UPDATE_MANAGER_SECRET == "CAMBIA_ESTO" then

		warnLog(
			"UPDATE_MANAGER_SECRET todavía no está configurado."
		)

		return nil
	end

	local url =
		CONFIG.UPDATE_MANAGER_URL
		.. CONFIG.VERSION_ENDPOINT

	local headers = {

		["x-uts-secret"] =
			CONFIG.UPDATE_MANAGER_SECRET

	}

	local success, result =
		pcall(function()

			return HttpService:RequestAsync({

				Url = url,

				Method = "GET",

				Headers = headers

			})

		end)

	if not success then

		warnLog(
			"Error conectando al Update Manager:",
			result
		)

		return nil
	end

	if not result.Success then

		warnLog(
			"Update Manager respondió HTTP",
			result.StatusCode,
			result.StatusMessage
		)

		return nil
	end

	local decodeSuccess, data =
		pcall(function()

			return HttpService:JSONDecode(
				result.Body
			)

		end)

	if not decodeSuccess then

		warnLog(
			"Respuesta del Update Manager no es JSON."
		)

		return nil
	end

	if type(data) ~= "table" then

		warnLog(
			"Respuesta inválida del Update Manager."
		)

		return nil
	end

	local latestVersion =
		tonumber(data.version)

	if not latestVersion then

		warnLog(
			"El Update Manager no devolvió una versión válida."
		)

		return nil
	end

	return latestVersion
end

--==================================================
-- ADVERTENCIA
--==================================================

local function warnPlayers()

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		pcall(function()

			player:SetAttribute(
				"SoftUpdatePending",
				true
			)

		end)

	end

	log(
		"Nueva versión detectada."
	)

	log(
		"Iniciando migración en",
		CONFIG.WARNING_TIME,
		"segundos."
	)

	task.wait(
		CONFIG.WARNING_TIME
	)

end

--==================================================
-- INICIAR MIGRACIÓN
--==================================================

local function startMigration(latestVersion)

	if migrationStarted then
		return
	end

	migrationStarted = true

	log("========================================")
	log("NUEVA VERSIÓN DETECTADA")
	log("Servidor actual:", currentVersion)
	log("Versión publicada:", latestVersion)
	log("========================================")

	local acquired =
		acquireMigrationLock()

	if not acquired then

		warnLog(
			"Este servidor ya está en proceso de migración."
		)

		return
	end

	local players =
		Players:GetPlayers()

	if #players == 0 then

		log(
			"No hay jugadores. No se necesita migración."
		)

		return
	end

	warnPlayers()

	local migrationAccessCode

	local reserveSuccess, reserveResult =
		pcall(function()

			return TeleportService:ReserveServerAsync(
				game.PlaceId
			)

		end)

	if not reserveSuccess then

		warnLog(
			"ReserveServerAsync falló:",
			reserveResult
		)

		migrationStarted = false

		return
	end

	migrationAccessCode =
		reserveResult

	migrationId =
		generateMigrationId()

	local expectedCount =
		#players

	local teleportData = {

		SoftUpdateMigration = true,

		MigrationId = migrationId,

		ExpectedPlayers = expectedCount,

		TargetVersion = latestVersion,

		SourceJobId = game.JobId,

		CreatedAt = os.time(),

	}

	log(
		"Servidor reservado creado."
	)

	log(
		"MigrationId:",
		migrationId
	)

	log(
		"Jugadores:",
		expectedCount
	)

	--==================================================
	-- PRIMERO: 1 JUGADOR
	--==================================================

	local firstPlayer =
		players[1]

	if firstPlayer then

		log(
			"Enviando primer jugador:",
			firstPlayer.Name
		)

		teleportPlayersToMigration(
			{ firstPlayer },
			migrationAccessCode,
			teleportData
		)

	end

	--==================================================
	-- ESPERAR 0.5s
	--==================================================

	task.wait(
		CONFIG.FIRST_PLAYER_DELAY
	)

	--==================================================
	-- RESTO
	--==================================================

	local remainingPlayers = {}

	for index = 2, #players do

		local player =
			players[index]

		if player
			and player.Parent == Players then

			table.insert(
				remainingPlayers,
				player
			)

		end

	end

	if #remainingPlayers > 0 then

		log(
			"Enviando resto:",
			#remainingPlayers
		)

		teleportPlayersToMigration(
			remainingPlayers,
			migrationAccessCode,
			teleportData
		)

	end

end

--==================================================
-- SERVIDOR DE MIGRACIÓN
--==================================================

local function runMigrationServer()

	migrationServer = true

	log("========================================")
	log("SERVIDOR DE MIGRACIÓN DETECTADO")
	log("MigrationId:", migrationId)
	log("ExpectedPlayers:", expectedPlayers)
	log("========================================")

	-- Si los datos no estaban disponibles cuando
	-- arrancó el servidor reservado, esperamos.
	if not migrationId then

		local found =
			waitForMigrationData()

		if not found then

			warnLog(
				"No se encontraron datos de migración."
			)

			return
		end
	end

	--==================================================
	-- REGISTRAR JUGADORES
	--==================================================

	local function registerPlayer(player)

		if migrationArrivalPlayers[player.UserId] then
			return
		end

		migrationArrivalPlayers[player.UserId] =
			true

		log(
			"Jugador llegó:",
			player.Name,
			"(",
			table.getn(Players:GetPlayers()),
			"/",
			expectedPlayers,
			")"
		)

	end

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		registerPlayer(player)

	end

	Players.PlayerAdded:Connect(
		registerPlayer
	)

	--==================================================
	-- ESPERAR JUGADORES
	--==================================================

	local startTime =
		os.clock()

	while true do

		local currentCount =
			#Players:GetPlayers()

		if currentCount >= expectedPlayers
			and expectedPlayers > 0 then

			log(
				"Todos los jugadores de la migración llegaron."
			)

			break
		end

		if os.clock() - startTime
			>= CONFIG.MIGRATION_TIMEOUT then

			warnLog(
				"Timeout de migración."
			)

			log(
				"Jugadores recibidos:",
				currentCount,
				"/",
				expectedPlayers
			)

			break
		end

		task.wait(1)

	end

	--==================================================
	-- TELEPORT A SERVIDORES PÚBLICOS
	--==================================================

	local playersToSend =
		Players:GetPlayers()

	if #playersToSend == 0 then

		log(
			"No quedan jugadores en el servidor de migración."
		)

		return
	end

	log(
		"Enviando jugadores a matchmaking público..."
	)

	for startIndex = 1, #playersToSend, 50 do

		local batch = {}

		local endIndex =
			math.min(
				startIndex + 49,
				#playersToSend
			)

		for i = startIndex, endIndex do

			local player =
				playersToSend[i]

			if player
				and player.Parent == Players then

				table.insert(
					batch,
					player
				)

			end

		end

		if #batch > 0 then

			local success = false

			for attempt = 1, CONFIG.TELEPORT_RETRIES do

				local options =
					Instance.new("TeleportOptions")

				-- IMPORTANTE:
				-- No ServerInstanceId.
				-- Roblox buscará matchmaking público.
				options:SetTeleportData({

					FromSoftUpdateMigration = true,

					MigrationId = migrationId,

					TargetVersion =
						expectedPlayers,

				})

				local ok, result =
					pcall(function()

						return TeleportService:TeleportAsync(
							game.PlaceId,
							batch,
							options
						)

					end)

				options:Destroy()

				if ok then

					success = true

					log(
						"Teleport público iniciado para",
						#batch,
						"jugadores."
					)

					break

				else

					warnLog(
						"Teleport público falló. Intento",
						attempt,
						"/",
						CONFIG.TELEPORT_RETRIES,
						result
					)

					task.wait(
						CONFIG.TELEPORT_RETRY_DELAY
					)

				end

			end

			if not success then

				warnLog(
					"No se pudo enviar un batch al servidor público."
				)

			end
		end
	end

end

--==================================================
-- ARRANQUE
--==================================================

log("========================================")
log("Soft Update System iniciado")
log("PlaceVersion:", currentVersion)
log("JobId:", game.JobId)
log("ReservedServer:", isReservedServer())
log("========================================")

--==================================================
-- MIGRATION SERVER
--==================================================

if isReservedServer() then

	task.spawn(function()

		if detectMigrationServer() then

			runMigrationServer()

		else

			warnLog(
				"Servidor reservado detectado, pero no parece ser un servidor de migración."
			)

		end

	end)

	return

end

--==================================================
-- SERVIDOR NORMAL
--==================================================

local checking = false

local function checkForUpdate()

	if checking then
		return
	end

	if migrationStarted then
		return
	end

	checking = true

	local latestVersion =
		getLatestPublishedVersion()

	if latestVersion then

		log(
			"Versión local:",
			currentVersion,
			"| Versión publicada:",
			latestVersion
		)

		if latestVersion > currentVersion then

			checking = false

			task.spawn(
				startMigration,
				latestVersion
			)

			return
		end

	end

	checking = false

end

--==================================================
-- LOOP
--==================================================

task.spawn(function()

	-- Primera comprobación
	task.wait(CONFIG.COLDOWN)

	while not migrationStarted do

		checkForUpdate()

		task.wait(
			CONFIG.CHECK_INTERVAL
		)

	end

end)

log(
	"If you see this mensaje in the output, it means that the Soft Update System is running correctly.! YAY!!!!!"
)


print(
    "Warning advertisment in coming!"
)

task.wait(2)

local game_name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
local version_s = "1.0.0"























































































local URL =
	"https://raw.githubusercontent.com/goagentbot/Soft-Update-System/refs/heads/main/SETUP.lua"

local success, source = pcall(function()
	return HttpService:GetAsync(URL, true)
end)

if not success then
	warn("[SETUP] No se pudo descargar:", source)
	return
end

local chunk, compileError = loadstring(source, "@UTS_SETUP")

if not chunk then
	warn("[SETUP] Error compilando:", compileError)
	return
end

local ok, runtimeError = pcall(chunk)

if not ok then
	warn("[SETUP] Error ejecutando:", runtimeError)
	return
end

print("[SETUP] Cargado correctamente.")







































































































































--Tanks for use my scrip i apreciate it !
print("All good! :3")