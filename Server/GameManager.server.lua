-- Movement Mayhem — Main Server Script
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
}

-- ============= DATA STORE =============
local playerStore = DataStoreService:GetDataStore("MovementMayhem_v1")

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
		currentStage = 1,
		bestTimes = {}, -- best time per stage
		totalDeaths = 0,
	}
end

local function saveData(player)
	local data = PlayerData[player.UserId]
	if not data then return end

	pcall(function()
		playerStore:SetAsync("player_" .. player.UserId, data)
	end)
end

-- ============= CHECKPOINT SYSTEM =============
local function getStageSpawn(stageNum)
	local stageFolder = workspace:FindFirstChild("Stage" .. stageNum)
	if stageFolder then
		return stageFolder:FindFirstChild("SpawnPart")
	end
	-- Fallback to lobby spawn
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		return lobby:FindFirstChild("SpawnPart")
	end
	return nil
end

local function teleportToStage(player, stageNum)
	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
	if not root then return end

	local spawn = getStageSpawn(stageNum)
	if spawn then
		root.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	end
end

-- ============= PLAYER SETUP =============
Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	PlayerData[player.UserId] = data

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = GameConfig.Player.walkSpeed
		humanoid.JumpPower = GameConfig.Player.jumpHeight * 10

		-- Teleport to their current stage
		task.wait(0.5)
		teleportToStage(player, data.currentStage)
		Remotes.UpdateStage:FireClient(player, data.currentStage, data.bestTimes)

		-- Death counter
		humanoid.Died:Connect(function()
			data.totalDeaths = data.totalDeaths + 1
			-- Respawn at current stage
			task.wait(2)
			player:LoadCharacter()
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	PlayerData[player.UserId] = nil
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

-- ============= STAGE COMPLETION =============
Remotes.ReachedCheckpoint.OnServerEvent:Connect(function(player, stageNum, completionTime)
	local data = PlayerData[player.UserId]
	if not data then return end

	-- Validate — must be at or near this stage
	if stageNum ~= data.currentStage then return end

	-- Update best time
	local stageKey = tostring(stageNum)
	if not data.bestTimes[stageKey] or completionTime < data.bestTimes[stageKey] then
		data.bestTimes[stageKey] = completionTime
	end

	-- Advance to next stage
	data.currentStage = stageNum + 1
	Remotes.StageComplete:FireClient(player, stageNum, completionTime, data.bestTimes[stageKey])
	Remotes.UpdateStage:FireClient(player, data.currentStage, data.bestTimes)

	-- Teleport to next stage
	task.wait(1)
	teleportToStage(player, data.currentStage)

	saveData(player)
	print("[MovementMayhem] " .. player.Name .. " completed Stage " .. stageNum .. " in " .. string.format("%.2f", completionTime) .. "s")
end)

-- Reset to checkpoint
Remotes.ResetToCheckpoint.OnServerEvent:Connect(function(player)
	local data = PlayerData[player.UserId]
	if not data then return end
	teleportToStage(player, data.currentStage)
end)

-- ============= KILL BRICKS =============
-- Any part named "KillBrick" or with attribute "KillOnTouch" kills the player
local function setupKillBricks()
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and (part.Name == "KillBrick" or part:GetAttribute("KillOnTouch")) then
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

-- ============= STAGE FINISH PARTS =============
local function setupFinishParts()
	for i = 1, 100 do
		local stageFolder = workspace:FindFirstChild("Stage" .. i)
		if not stageFolder then break end

		local finishPart = stageFolder:FindFirstChild("FinishPart")
		if finishPart then
			finishPart.Touched:Connect(function(hit)
				local char = hit.Parent
				local player = Players:GetPlayerFromCharacter(char)
				if not player then return end

				local data = PlayerData[player.UserId]
				if not data then return end

				-- Only trigger if this is their current stage
				if data.currentStage == i then
					-- Fire completion (client tracks time)
					Remotes.StageComplete:FireClient(player, i, 0)
					data.currentStage = i + 1
					Remotes.UpdateStage:FireClient(player, data.currentStage, data.bestTimes)

					task.wait(1)
					teleportToStage(player, data.currentStage)
					saveData(player)
				end
			end)
		end
	end
end

task.defer(function()
	setupKillBricks()
	setupFinishParts()
end)

print("[Movement Mayhem] Server loaded!")
