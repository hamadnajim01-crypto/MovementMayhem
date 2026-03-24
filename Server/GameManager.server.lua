-- Movement Mayhem — Deathrun Server
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- ============= REMOTE EVENTS =============
local function createRemote(name, className)
	local remote = Instance.new(className or "RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local Remotes = {
	UpdateStage = createRemote("UpdateStage"),
	ReachedCheckpoint = createRemote("ReachedCheckpoint"),
	UpdateTimer = createRemote("UpdateTimer"),
	StageComplete = createRemote("StageComplete"),
	ResetToCheckpoint = createRemote("ResetToCheckpoint"),
	UpdateLeaderboard = createRemote("UpdateLeaderboard"),
	ActivateTrap = createRemote("ActivateTrap"),
	RoundInfo = createRemote("RoundInfo"),
	SetRole = createRemote("SetRole"),
	AdminCommand = createRemote("AdminCommand"),
}

-- ============= DATA STORE =============
local playerStore = DataStoreService:GetDataStore("MovementMayhem_v2")

-- ============= PLAYER DATA =============
local PlayerData = {}

local function loadData(player)
	local success, data = pcall(function()
		return playerStore:GetAsync("player_" .. player.UserId)
	end)

	if success and data then
		return data
	end

	return {
		wins = 0,
		totalDeaths = 0,
		gamesPlayed = 0,
	}
end

local function saveData(player)
	local data = PlayerData[player.UserId]
	if not data then return end

	pcall(function()
		playerStore:SetAsync("player_" .. player.UserId, data)
	end)
end

-- ============= ROUND SYSTEM =============
local roundState = {
	active = false,
	death = nil, -- player who controls traps
	runners = {}, -- players who run
	alivePlayers = {}, -- runners still alive
	roundNum = 0,
	countdown = false,
}

local MIN_PLAYERS = 1
local LOBBY_WAIT = 10
local ROUND_TIME = 120 -- 2 minutes per round
local INTERMISSION = 5

-- ============= SPAWNS =============
local function getLobbySpawn()
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		return lobby:FindFirstChild("SpawnPart")
	end
	return nil
end

local function getRunnerSpawn()
	local stage1 = workspace:FindFirstChild("Stage1")
	if stage1 then
		return stage1:FindFirstChild("SpawnPart")
	end
	return getLobbySpawn()
end

local function getDeathSpawn()
	local deathArea = workspace:FindFirstChild("DeathControls")
	if deathArea then
		return deathArea:FindFirstChild("SpawnPart")
	end
	return getLobbySpawn()
end

local function teleportTo(player, spawnPart)
	if not spawnPart then return end
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
	if not root then return end
	root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
end

local function teleportToLobby(player)
	teleportTo(player, getLobbySpawn())
end

-- ============= TRAPS =============
-- Traps are parts in workspace.Traps folder
-- Each trap has: TrapPart (the kill part) and a Button (what death clicks)
-- Trap buttons are in DeathControls folder

local trapConnections = {}
local trapCooldowns = {}

local function resetTraps()
	-- Reset all trap parts to default position/state
	local traps = workspace:FindFirstChild("Traps")
	if not traps then return end

	for _, trap in ipairs(traps:GetDescendants()) do
		if trap:IsA("BasePart") and trap:GetAttribute("TrapDefault") then
			trap.Position = trap:GetAttribute("TrapDefault")
		end
		if trap:IsA("BasePart") and trap.Name == "TrapPart" then
			trap.Transparency = 1
			trap.CanCollide = false
		end
	end
end

local function activateTrap(trapName)
	if trapCooldowns[trapName] and tick() - trapCooldowns[trapName] < 3 then return end
	trapCooldowns[trapName] = tick()

	local traps = workspace:FindFirstChild("Traps")
	if not traps then return end

	local trapFolder = traps:FindFirstChild(trapName)
	if not trapFolder then return end

	-- Find all kill parts in this trap
	for _, part in ipairs(trapFolder:GetDescendants()) do
		if part:IsA("BasePart") and (part.Name == "TrapPart" or part:GetAttribute("KillOnTouch")) then
			part.Transparency = 0
			part.CanCollide = true

			-- Kill anyone touching it
			local conn
			conn = part.Touched:Connect(function(hit)
				local char = hit.Parent
				local humanoid = char and char:FindFirstChild("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local hitPlayer = Players:GetPlayerFromCharacter(char)
					if hitPlayer and hitPlayer ~= roundState.death then
						humanoid.Health = 0
					end
				end
			end)
			table.insert(trapConnections, conn)

			-- Hide trap after 2 seconds
			task.delay(2, function()
				part.Transparency = 1
				part.CanCollide = false
			end)
		end
	end
end

-- Death player activates traps
Remotes.ActivateTrap.OnServerEvent:Connect(function(player, trapName)
	-- Admins can always activate traps
	if GameConfig.Admins[player.UserId] then
		activateTrap(trapName)
		return
	end
	if not roundState.active then return end
	if player ~= roundState.death then return end
	activateTrap(trapName)
end)

-- ============= KILL BRICKS (permanent) =============
local function setupKillBricks()
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and (part.Name == "KillBrick" or part:GetAttribute("KillOnTouch")) then
			-- Skip trap parts
			local inTraps = false
			local parent = part.Parent
			while parent do
				if parent.Name == "Traps" then inTraps = true; break end
				parent = parent.Parent
			end
			if inTraps then continue end

			part.Touched:Connect(function(hit)
				local char = hit.Parent
				local humanoid = char and char:FindFirstChild("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = 0
				end
			end)
		end
	end
end

-- ============= FINISH LINE =============
local finishTouched = {}

local function setupFinishLine()
	-- Find the last stage's FinishPart or a part named "FinishLine"
	local finish = workspace:FindFirstChild("FinishLine")
	if not finish then
		-- Find highest stage finish
		for i = 100, 1, -1 do
			local stage = workspace:FindFirstChild("Stage" .. i)
			if stage then
				finish = stage:FindFirstChild("FinishPart")
				if finish then break end
			end
		end
	end

	if not finish then return end

	finish.Touched:Connect(function(hit)
		if not roundState.active then return end

		local char = hit.Parent
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		if player == roundState.death then return end
		if finishTouched[player.UserId] then return end

		finishTouched[player.UserId] = true

		-- This runner won!
		roundState.active = false

		-- Tell everyone
		Remotes.RoundInfo:FireAllClients("winner", player.Name)

		local data = PlayerData[player.UserId]
		if data then
			data.wins = (data.wins or 0) + 1
		end

		print("[MovementMayhem] " .. player.Name .. " won the round!")

		-- Winner becomes death next round
		task.wait(3)
		startNewRound(player)
	end)
end

-- ============= PLAYER DEATH IN ROUND =============
local function onPlayerDied(player)
	if not roundState.active then return end
	if player == roundState.death then return end

	local data = PlayerData[player.UserId]
	if data then
		data.totalDeaths = (data.totalDeaths or 0) + 1
	end

	-- Remove from alive list
	for i, p in ipairs(roundState.alivePlayers) do
		if p == player then
			table.remove(roundState.alivePlayers, i)
			break
		end
	end

	Remotes.RoundInfo:FireAllClients("death_count", #roundState.alivePlayers, #roundState.runners)

	-- Respawn them to lobby (they're out)
	task.wait(2.5)
	if player.Parent then
		player:LoadCharacter()
		task.wait(1)
		teleportToLobby(player)
		Remotes.SetRole:FireClient(player, "spectator")
	end

	-- If all runners dead, death wins
	if #roundState.alivePlayers <= 0 and roundState.active then
		roundState.active = false
		local deathName = roundState.death and roundState.death.Name or "Death"
		Remotes.RoundInfo:FireAllClients("death_wins", deathName)
		print("[MovementMayhem] Death (" .. deathName .. ") killed everyone!")

		task.wait(3)
		startNewRound(nil) -- random death next round
	end
end

-- ============= ROUND MANAGEMENT =============
function startNewRound(nextDeath)
	-- Clean up
	roundState.active = false
	finishTouched = {}
	trapCooldowns = {}

	for _, conn in ipairs(trapConnections) do
		conn:Disconnect()
	end
	trapConnections = {}

	resetTraps()

	local allPlayers = Players:GetPlayers()
	if #allPlayers < MIN_PLAYERS then
		Remotes.RoundInfo:FireAllClients("waiting", MIN_PLAYERS)
		return
	end

	-- Intermission
	roundState.countdown = true
	for i = INTERMISSION, 1, -1 do
		Remotes.RoundInfo:FireAllClients("intermission", i)
		task.wait(1)
	end

	-- Pick death player
	allPlayers = Players:GetPlayers() -- refresh
	if #allPlayers < MIN_PLAYERS then
		Remotes.RoundInfo:FireAllClients("waiting", MIN_PLAYERS)
		roundState.countdown = false
		return
	end

	local death = nextDeath
	if not death or not death.Parent then
		death = allPlayers[math.random(1, #allPlayers)]
	end

	-- Set up runners (everyone except death)
	local runners = {}
	for _, p in ipairs(allPlayers) do
		if p ~= death then
			table.insert(runners, p)
		end
	end

	roundState.death = death
	roundState.runners = runners
	roundState.alivePlayers = {table.unpack(runners)}
	roundState.roundNum = roundState.roundNum + 1
	roundState.active = true

	-- Tell clients their roles
	Remotes.SetRole:FireClient(death, "death")
	for _, runner in ipairs(runners) do
		Remotes.SetRole:FireClient(runner, "runner")
	end

	Remotes.RoundInfo:FireAllClients("round_start", death.Name, #runners)

	-- Teleport everyone
	-- Respawn all characters fresh
	for _, p in ipairs(allPlayers) do
		p:LoadCharacter()
	end
	task.wait(1)

	-- Teleport death to controls, runners to start
	teleportTo(death, getDeathSpawn())
	for _, runner in ipairs(runners) do
		teleportTo(runner, getRunnerSpawn())
	end

	-- Freeze runners for 3 second head start for death to get ready
	for _, runner in ipairs(runners) do
		local char = runner.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then
				hum.WalkSpeed = 0
				hum.JumpPower = 0
			end
		end
	end

	Remotes.RoundInfo:FireAllClients("countdown", 3)
	task.wait(1)
	Remotes.RoundInfo:FireAllClients("countdown", 2)
	task.wait(1)
	Remotes.RoundInfo:FireAllClients("countdown", 1)
	task.wait(1)
	Remotes.RoundInfo:FireAllClients("countdown", 0)

	-- Unfreeze runners
	for _, runner in ipairs(runners) do
		local char = runner.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then
				hum.WalkSpeed = GameConfig.Player.sprintSpeed
				hum.JumpPower = GameConfig.Player.jumpHeight * 10
			end
		end
	end

	-- Round timer
	task.spawn(function()
		local timeLeft = ROUND_TIME
		while roundState.active and timeLeft > 0 do
			task.wait(1)
			timeLeft = timeLeft - 1
			Remotes.RoundInfo:FireAllClients("timer", timeLeft)
		end

		if roundState.active then
			-- Time ran out — remaining runners win
			roundState.active = false
			Remotes.RoundInfo:FireAllClients("time_up")
			print("[MovementMayhem] Time's up! Runners survive!")

			-- Pick random survivor as next death
			if #roundState.alivePlayers > 0 then
				local nextD = roundState.alivePlayers[math.random(1, #roundState.alivePlayers)]
				task.wait(3)
				startNewRound(nextD)
			else
				task.wait(3)
				startNewRound(nil)
			end
		end
	end)

	print("[MovementMayhem] Round " .. roundState.roundNum .. " started! Death: " .. death.Name)
end

-- ============= PLAYER SETUP =============
Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	PlayerData[player.UserId] = data

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
		humanoid.JumpPower = GameConfig.Player.jumpHeight * 10

		humanoid.Died:Connect(function()
			onPlayerDied(player)
		end)

		-- If no round active, send to lobby
		if not roundState.active and not roundState.countdown then
			task.wait(0.5)
			teleportToLobby(player)
		end
	end)

	-- Start round if enough players
	task.wait(2)
	if not roundState.active and not roundState.countdown then
		local allPlayers = Players:GetPlayers()
		if #allPlayers >= MIN_PLAYERS then
			startNewRound(nil)
		else
			Remotes.RoundInfo:FireAllClients("waiting", MIN_PLAYERS)
		end
	else
		-- Round in progress, they spectate
		Remotes.SetRole:FireClient(player, "spectator")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	PlayerData[player.UserId] = nil

	-- If death leaves, end round
	if roundState.active and player == roundState.death then
		roundState.active = false
		Remotes.RoundInfo:FireAllClients("death_left")
		task.wait(2)
		startNewRound(nil)
	end

	-- Remove from alive
	for i, p in ipairs(roundState.alivePlayers) do
		if p == player then
			table.remove(roundState.alivePlayers, i)
			break
		end
	end

	-- If not enough players, cancel
	if #Players:GetPlayers() < MIN_PLAYERS and roundState.active then
		roundState.active = false
		Remotes.RoundInfo:FireAllClients("not_enough")
	end
end)

-- Auto-save every 60 seconds
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)

-- Reset to checkpoint (runners only)
Remotes.ResetToCheckpoint.OnServerEvent:Connect(function(player)
	if roundState.active and player == roundState.death then return end
	local spawn = getRunnerSpawn()
	if spawn then
		teleportTo(player, spawn)
	end
end)

task.defer(function()
	setupKillBricks()
	setupFinishLine()
end)

-- ============= ADMIN COMMANDS =============
local BanStore = DataStoreService:GetDataStore("MovementMayhem_Bans")

Remotes.AdminCommand.OnServerEvent:Connect(function(player, command, arg1, arg2)
	if not GameConfig.Admins[player.UserId] then return end

	if command == "newround" then
		roundState.active = false
		task.wait(1)
		startNewRound(nil)

	elseif command == "killall" then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p.Character then
				local hum = p.Character:FindFirstChild("Humanoid")
				if hum then hum.Health = 0 end
			end
		end

	elseif command == "respawn" then
		player:LoadCharacter()

	elseif command == "god" then
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then
				if arg1 then
					hum.MaxHealth = math.huge
					hum.Health = math.huge
				else
					hum.MaxHealth = 100
					hum.Health = 100
				end
			end
		end

	elseif command == "speed" then
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.WalkSpeed = tonumber(arg1) or GameConfig.Player.sprintSpeed end
		end

	elseif command == "jumppower" then
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.JumpPower = tonumber(arg1) or (GameConfig.Player.jumpHeight * 10) end
		end

	elseif command == "gravity" then
		workspace.Gravity = tonumber(arg1) or 196.2

	elseif command == "kick" then
		local target = Players:FindFirstChild(arg1)
		if target and not GameConfig.Admins[target.UserId] then
			target:Kick("Kicked by admin")
		end

	elseif command == "ban" then
		local target = Players:FindFirstChild(arg1)
		local banMins = tonumber(arg2) or 60
		if target and not GameConfig.Admins[target.UserId] then
			pcall(function()
				BanStore:SetAsync("ban_" .. target.UserId, os.time() + (banMins * 60))
			end)
			target:Kick("Banned for " .. banMins .. " minutes by admin")
		end

	elseif command == "killplayer" then
		local target = Players:FindFirstChild(arg1)
		if target and target.Character then
			local hum = target.Character:FindFirstChild("Humanoid")
			if hum then hum.Health = 0 end
		end

	elseif command == "tptome" then
		local target = Players:FindFirstChild(arg1)
		if target and target.Character and player.Character then
			local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso")
			local myRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")
			if targetRoot and myRoot then
				targetRoot.CFrame = myRoot.CFrame + myRoot.CFrame.RightVector * 5
			end
		end

	elseif command == "goto" then
		local target = Players:FindFirstChild(arg1)
		if target and target.Character and player.Character then
			local targetRoot = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso")
			local myRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")
			if targetRoot and myRoot then
				myRoot.CFrame = targetRoot.CFrame + targetRoot.CFrame.RightVector * 5
			end
		end

	elseif command == "freezeplayer" then
		local target = Players:FindFirstChild(arg1)
		if target and target.Character then
			local root = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso")
			if root then root.Anchored = true end
		end

	elseif command == "unfreezeplayer" then
		local target = Players:FindFirstChild(arg1)
		if target and target.Character then
			local root = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso")
			if root then root.Anchored = false end
		end
	end
end)

-- Check bans on join
Players.PlayerAdded:Connect(function(plr)
	pcall(function()
		local banTime = BanStore:GetAsync("ban_" .. plr.UserId)
		if banTime and os.time() < banTime then
			local remaining = math.ceil((banTime - os.time()) / 60)
			plr:Kick("You are banned for " .. remaining .. " more minutes")
		end
	end)
end)

print("[Movement Mayhem] Deathrun Server loaded!")
