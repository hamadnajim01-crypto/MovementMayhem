-- Movement Mayhem — Client Controller
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera


local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- ============= REMOTES =============
local Remotes = {
	UpdateStage = ReplicatedStorage:WaitForChild("UpdateStage"),
	ReachedCheckpoint = ReplicatedStorage:WaitForChild("ReachedCheckpoint"),
	UpdateTimer = ReplicatedStorage:WaitForChild("UpdateTimer"),
	StageComplete = ReplicatedStorage:WaitForChild("StageComplete"),
	ResetToCheckpoint = ReplicatedStorage:WaitForChild("ResetToCheckpoint"),
	UpdateLeaderboard = ReplicatedStorage:WaitForChild("UpdateLeaderboard"),
	ActivateTrap = ReplicatedStorage:WaitForChild("ActivateTrap"),
	RoundInfo = ReplicatedStorage:WaitForChild("RoundInfo"),
	SetRole = ReplicatedStorage:WaitForChild("SetRole"),
}

-- ============= STATE =============
local character, humanoid, rootPart, animator
local animations = {}
local currentAnims = {}

local state = {
	sliding = false,
	crouching = false,
	dashing = false,
	wallRunning = false,
	ledgeGrabbing = false,
	vaulting = false,
	grounded = true,

	currentSpeed = 0,
	dashCooldown = 0,
	slideCooldownEnd = 0,

	currentStage = 1,
	stageStartTime = 0,
	bestTimes = {},
}

-- ============= ANIMATIONS =============
local function loadAnimations()
	if not animator then return end
	for name, id in pairs(GameConfig.Animations) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		animations[name] = animator:LoadAnimation(anim)
	end

	-- Set priorities
	if animations.idle then animations.idle.Priority = Enum.AnimationPriority.Idle end
	if animations.walk then animations.walk.Priority = Enum.AnimationPriority.Movement end
	if animations.run then animations.run.Priority = Enum.AnimationPriority.Movement end
	if animations.jump then animations.jump.Priority = Enum.AnimationPriority.Action end
	if animations.slide then animations.slide.Priority = Enum.AnimationPriority.Action2 end
	if animations.crouchIdle then animations.crouchIdle.Priority = Enum.AnimationPriority.Movement end
	if animations.crouchMove then animations.crouchMove.Priority = Enum.AnimationPriority.Movement end
	if animations.charge then animations.charge.Priority = Enum.AnimationPriority.Action2 end
	if animations.land then animations.land.Priority = Enum.AnimationPriority.Action end
	if animations.swim then animations.swim.Priority = Enum.AnimationPriority.Movement end
	if animations.climb then animations.climb.Priority = Enum.AnimationPriority.Movement end
	if animations.ledgeGrab then animations.ledgeGrab.Priority = Enum.AnimationPriority.Action2 end
	if animations.ledgeClimbUp then animations.ledgeClimbUp.Priority = Enum.AnimationPriority.Action4 end
	if animations.ledgeRoll then animations.ledgeRoll.Priority = Enum.AnimationPriority.Action4 end

	for _, name in ipairs({"dash1","dash2","dashBack","dashLeft","dashRight"}) do
		if animations[name] then animations[name].Priority = Enum.AnimationPriority.Action2 end
	end
	for _, name in ipairs({"tiltLeft","tiltRight","tiltLeftRun","tiltRightRun","tiltBack"}) do
		if animations[name] then animations[name].Priority = Enum.AnimationPriority.Movement end
	end
end

local function stopAnim(name)
	if currentAnims[name] then
		currentAnims[name]:Stop()
		currentAnims[name] = nil
	end
end

local function playAnim(name, fadeTime)
	if not animations[name] then return end
	if currentAnims[name] then return currentAnims[name] end
	currentAnims[name] = animations[name]
	animations[name]:Play(fadeTime or 0.2)
	return animations[name]
end

local function stopAllAnims()
	for name, _ in pairs(currentAnims) do
		stopAnim(name)
	end
end

-- ============= CHARACTER SETUP =============
local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart", 5) or char:WaitForChild("Torso", 5)
	animator = humanoid:WaitForChild("Animator", 5) or humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	animations = {}
	currentAnims = {}

	-- Disable default Roblox animations
	local animate = char:FindFirstChild("Animate")
	if animate then animate:Destroy() end

	loadAnimations()

	state.sliding = false
	state.crouching = false
	state.dashing = false
	state.wallRunning = false
	state.ledgeGrabbing = false
	state.vaulting = false

	-- Auto-run: always at sprint speed
	humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
	humanoid.JumpPower = GameConfig.Player.jumpHeight * 10

	-- Death animation
	humanoid.Died:Connect(function()
		stopAllAnims()
		if rootPart then
			rootPart.Anchored = true
		end

		-- Pick random death: death1 = powers (1.3s), death2 = punch (2s), death3 = hands (1.3s)
		local deathAnims = {"death1", "death2", "death3"}
		local durations = {death1 = 1.3, death2 = 2, death3 = 1.3}
		local pick = deathAnims[math.random(1, #deathAnims)]

		if animations[pick] then
			animations[pick].Priority = Enum.AnimationPriority.Action4
			animations[pick]:Play(0.1)
		end

		-- Unanchor after animation finishes, then respawn
		task.delay(durations[pick], function()
			if rootPart then
				rootPart.Anchored = false
			end
		end)
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ============= SLIDE =============
local function startSlide()
	if state.sliding or state.dashing then return end
	if tick() < state.slideCooldownEnd then return end

	state.sliding = true
	state.crouching = false

	if humanoid then
		humanoid.WalkSpeed = GameConfig.Player.slideSpeed
	end

	stopAnim("run")
	stopAnim("walk")
	stopAnim("crouchIdle")
	stopAnim("crouchMove")
	playAnim("slide", 0.1)

	-- Apply slide velocity
	if rootPart then
		local slideDir = rootPart.CFrame.LookVector
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(30000, 0, 30000)
		bv.Velocity = slideDir * GameConfig.Player.slideSpeed
		bv.Parent = rootPart
		bv.Name = "SlideForce"

		task.delay(GameConfig.Player.slideDuration, function()
			bv:Destroy()
			state.sliding = false
			stopAnim("slide")
			state.slideCooldownEnd = tick() + 0.5

			if humanoid then
				humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
			end
		end)
	end
end

-- ============= CROUCH =============
local function toggleCrouch()
	if state.sliding or state.dashing then return end

	if state.crouching then
		state.crouching = false
		stopAnim("crouchIdle")
		stopAnim("crouchMove")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
		end
	else
		state.crouching = true
		if humanoid then
			humanoid.WalkSpeed = GameConfig.Player.sprintSpeed * 0.5
		end
	end
end

-- ============= DASH =============
local function doDash()
	if state.dashing or state.sliding then return end
	if tick() - state.dashCooldown < GameConfig.Player.dashCooldown then return end

	state.dashing = true
	state.dashCooldown = tick()

	if not rootPart then
		state.dashing = false
		return
	end

	-- Determine dash direction
	local moveDir = humanoid.MoveDirection
	local dashAnimName = "dash1"

	if moveDir.Magnitude < 0.1 then
		moveDir = rootPart.CFrame.LookVector
	else
		local localDir = rootPart.CFrame:VectorToObjectSpace(moveDir)
		if localDir.Z > 0.5 then
			dashAnimName = "dashBack"
		elseif localDir.X < -0.5 then
			dashAnimName = "dashLeft"
		elseif localDir.X > 0.5 then
			dashAnimName = "dashRight"
		else
			dashAnimName = math.random(1, 2) == 1 and "dash1" or "dash2"
		end
	end

	stopAnim("walk")
	stopAnim("run")
	playAnim(dashAnimName, 0.05)

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(50000, 10000, 50000)
	bv.Velocity = moveDir.Unit * GameConfig.Player.dashForce + Vector3.new(0, 10, 0)
	bv.Parent = rootPart
	bv.Name = "DashForce"

	task.delay(0.3, function()
		bv:Destroy()
		stopAnim(dashAnimName)
		state.dashing = false
	end)
end

-- ============= WALL RUN =============
local WALL_RUN_SPEED = 30

local function tryWallRun()
	if state.wallRunning or state.sliding or state.ledgeGrabbing then return end
	if not rootPart or not humanoid then return end
	if humanoid.FloorMaterial ~= Enum.Material.Air then return end

	-- Raycast right and left to find walls
	local directions = {
		{dir = rootPart.CFrame.RightVector, anim = "wallRunRight"},
		{dir = -rootPart.CFrame.RightVector, anim = "wallRunLeft"},
	}

	for _, info in ipairs(directions) do
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(rootPart.Position, info.dir * 3, rayParams)
		if result and result.Instance and result.Instance.Anchored then
			state.wallRunning = true

			local wallNormal = result.Normal
			local wallDir = info.dir
			local upDir = Vector3.new(0, 1, 0)
			local wallForward = upDir:Cross(wallNormal).Unit

			if rootPart.CFrame.LookVector:Dot(wallForward) < 0 then
				wallForward = -wallForward
			end

			local wallAnimName = info.anim
			playAnim(wallAnimName, 0.1)

			local bg = Instance.new("BodyGyro")
			bg.MaxTorque = Vector3.new(100000, 100000, 100000)
			bg.CFrame = CFrame.lookAt(Vector3.zero, wallForward, wallNormal)
			bg.Parent = rootPart
			bg.Name = "WallRunGyro"

			local bv = Instance.new("BodyVelocity")
			bv.MaxForce = Vector3.new(50000, 50000, 50000)
			bv.Velocity = wallForward * WALL_RUN_SPEED + Vector3.new(0, 0, 0)
			bv.Parent = rootPart
			bv.Name = "WallRunForce"

			-- Jump off wall with Space
			local jumpConn
			jumpConn = UserInputService.InputBegan:Connect(function(input, gpe)
				if gpe then return end
				if input.KeyCode == Enum.KeyCode.Space and state.wallRunning then
					state.wallRunning = false
				end
			end)

			-- Keep running as long as wall exists, slowly sink down
			task.spawn(function()
				local elapsed = 0
				while state.wallRunning do
					local dt = task.wait()
					elapsed = elapsed + dt

					-- Check if wall still exists next to player
					local wallCheck = workspace:Raycast(rootPart.Position, wallDir * 3, rayParams)
					if not wallCheck or not wallCheck.Instance or not wallCheck.Instance.Anchored then
						break
					end

					-- Check if there's ground below (landed)
					local groundCheck = workspace:Raycast(rootPart.Position, Vector3.new(0, -3, 0), rayParams)
					if groundCheck then
						break
					end

					-- Constant 4 studs/s sink
					bv.Velocity = wallForward * WALL_RUN_SPEED + Vector3.new(0, -4, 0)
				end

				-- Wall run ended
				if jumpConn then jumpConn:Disconnect() end
				bv:Destroy()
				bg:Destroy()
				state.wallRunning = false
				stopAnim(wallAnimName)

				-- Wall jump off
				if rootPart then
					local jumpOff = Instance.new("BodyVelocity")
					jumpOff.MaxForce = Vector3.new(30000, 30000, 30000)
					jumpOff.Velocity = wallNormal * 30 + Vector3.new(0, 30, 0)
					jumpOff.Parent = rootPart
					jumpOff.Name = "WallJump"
					task.delay(0.2, function()
						jumpOff:Destroy()
					end)
				end
			end)

			return
		end
	end
end

-- ============= LEDGE GRAB =============
local LEDGE_GRAB_RANGE = 4
local LEDGE_HEIGHT_CHECK = 6

local function tryLedgeGrab()
	if state.ledgeGrabbing or state.wallRunning or state.sliding then return end
	if not rootPart or not humanoid then return end
	if humanoid.FloorMaterial ~= Enum.Material.Air then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Raycast forward to find a wall
	local forwardResult = workspace:Raycast(
		rootPart.Position + Vector3.new(0, 2, 0),
		rootPart.CFrame.LookVector * LEDGE_GRAB_RANGE,
		rayParams
	)

	if not forwardResult or not forwardResult.Instance.Anchored then return end

	-- Raycast down from above to find the ledge top
	local topStart = rootPart.Position + rootPart.CFrame.LookVector * (LEDGE_GRAB_RANGE - 0.5) + Vector3.new(0, LEDGE_HEIGHT_CHECK, 0)
	local topResult = workspace:Raycast(topStart, Vector3.new(0, -LEDGE_HEIGHT_CHECK * 2, 0), rayParams)

	if not topResult then return end

	-- Check if ledge is above us and reachable
	local ledgeHeight = topResult.Position.Y
	local playerHeight = rootPart.Position.Y
	if ledgeHeight < playerHeight + 1 or ledgeHeight > playerHeight + LEDGE_HEIGHT_CHECK then return end

	state.ledgeGrabbing = true

	-- Freeze player at ledge
	if humanoid then
		humanoid.AutoRotate = false
	end

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(100000, 100000, 100000)
	bg.CFrame = CFrame.lookAt(Vector3.zero, -forwardResult.Normal)
	bg.Parent = rootPart
	bg.Name = "LedgeGyro"

	local bp = Instance.new("BodyPosition")
	bp.MaxForce = Vector3.new(50000, 50000, 50000)
	bp.Position = Vector3.new(rootPart.Position.X, ledgeHeight - 3, rootPart.Position.Z) +
		(-forwardResult.Normal * 1.5)
	bp.Parent = rootPart
	bp.Name = "LedgeHold"

	stopAllAnims()
	playAnim("ledgeGrab", 0.1)

	-- Wait for jump input to climb up
	local conn
	conn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.Space and state.ledgeGrabbing then
			conn:Disconnect()

			stopAnim("ledgeGrab")
			playAnim("ledgeClimbUp", 0.1)

			-- Move to top of ledge
			bp.Position = Vector3.new(rootPart.Position.X, ledgeHeight + 2, rootPart.Position.Z) +
				(-forwardResult.Normal * 3)

			task.delay(0.5, function()
				bp:Destroy()
				bg:Destroy()
				state.ledgeGrabbing = false
				stopAnim("ledgeClimbUp")
				if humanoid then
					humanoid.AutoRotate = true
				end
			end)
		end
	end)

	-- Timeout — drop after 3 seconds if no input
	task.delay(3, function()
		if state.ledgeGrabbing then
			if conn then conn:Disconnect() end
			bp:Destroy()
			bg:Destroy()
			state.ledgeGrabbing = false
			stopAnim("ledgeGrab")
			if humanoid then
				humanoid.AutoRotate = true
			end
		end
	end)
end

-- ============= VAULT =============
local function tryVault()
	if state.sliding or state.dashing or state.ledgeGrabbing then return end
	if not rootPart or not humanoid then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Check for low obstacle in front
	local lowResult = workspace:Raycast(
		rootPart.Position + Vector3.new(0, -1, 0),
		rootPart.CFrame.LookVector * 4,
		rayParams
	)

	if not lowResult or not lowResult.Instance.Anchored then return end

	-- Check if obstacle is low enough to vault (< 5 studs tall from ground)
	local highResult = workspace:Raycast(
		rootPart.Position + Vector3.new(0, 3, 0),
		rootPart.CFrame.LookVector * 4,
		rayParams
	)

	-- If high raycast hits nothing, obstacle is low enough to vault
	if highResult then return end

	state.vaulting = true
	stopAnim("run")
	stopAnim("walk")

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(50000, 50000, 50000)
	bv.Velocity = rootPart.CFrame.LookVector * 35 + Vector3.new(0, 25, 0)
	bv.Parent = rootPart
	bv.Name = "VaultForce"

	playAnim("vault", 0.05)

	task.delay(0.4, function()
		bv:Destroy()
		state.vaulting = false
		stopAnim("vault")
	end)
end

-- ============= ADMIN PANEL =============
local isAdmin = GameConfig.Admins[player.UserId]
local adminPanelOpen = false
local adminPanel
local adminFlying = false
local adminNoclip = false
local flyBV, flyBG
local noclipConn
local tpMode = false
local selectedPlayer = nil

local function adminCmd(cmd, ...)
	Remotes.AdminCommand:FireServer(cmd, ...)
end

if isAdmin then
	local playerGui = player:WaitForChild("PlayerGui")

	adminPanel = Instance.new("ScreenGui")
	adminPanel.Name = "AdminPanel"
	adminPanel.ResetOnSpawn = false
	adminPanel.Parent = playerGui

	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "PanelFrame"
	panelFrame.Size = UDim2.new(0, 400, 0, 580)
	panelFrame.Position = UDim2.new(0.5, -200, 0.5, -290)
	panelFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panelFrame.BackgroundTransparency = 0.02
	panelFrame.Visible = false
	panelFrame.Parent = adminPanel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panelFrame

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 50, 50)
	panelStroke.Thickness = 2
	panelStroke.Parent = panelFrame

	local boldFont = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	local regFont = Font.new("rbxasset://fonts/families/GothamSSm.json")

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 35)
	title.BackgroundTransparency = 1
	title.Text = "ADMIN PANEL [P]"
	title.TextColor3 = Color3.fromRGB(255, 50, 50)
	title.FontFace = boldFont
	title.TextSize = 20
	title.Parent = panelFrame

	local onColor = Color3.fromRGB(50, 200, 100)

	-- ====== SELF POWERS (top section) ======
	local selfLabel = Instance.new("TextLabel")
	selfLabel.Size = UDim2.new(1, 0, 0, 20)
	selfLabel.Position = UDim2.new(0, 10, 0, 35)
	selfLabel.BackgroundTransparency = 1
	selfLabel.Text = "SELF POWERS"
	selfLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	selfLabel.FontFace = boldFont
	selfLabel.TextSize = 12
	selfLabel.TextXAlignment = Enum.TextXAlignment.Left
	selfLabel.Parent = panelFrame

	local selfFrame = Instance.new("Frame")
	selfFrame.Size = UDim2.new(1, -20, 0, 90)
	selfFrame.Position = UDim2.new(0, 10, 0, 55)
	selfFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	selfFrame.Parent = panelFrame
	Instance.new("UICorner", selfFrame).CornerRadius = UDim.new(0, 8)

	local selfGrid = Instance.new("UIGridLayout")
	selfGrid.CellSize = UDim2.new(0, 85, 0, 35)
	selfGrid.CellPadding = UDim2.new(0, 5, 0, 5)
	selfGrid.SortOrder = Enum.SortOrder.LayoutOrder
	selfGrid.Parent = selfFrame
	Instance.new("UIPadding", selfFrame).PaddingTop = UDim.new(0, 5)
	Instance.new("UIPadding", selfFrame).PaddingLeft = UDim.new(0, 5)

	local function makeBtn(name, color, order, parent)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.LayoutOrder = order or 0
		btn.BackgroundColor3 = color
		btn.Text = name
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.FontFace = boldFont
		btn.TextSize = 11
		btn.Parent = parent or selfFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		return btn
	end

	-- Fly
	local flyColor = Color3.fromRGB(50, 100, 200)
	local flyBtn = makeBtn("Fly", flyColor, 1)
	flyBtn.MouseButton1Click:Connect(function()
		adminFlying = not adminFlying
		if adminFlying then
			flyBtn.BackgroundColor3 = onColor; flyBtn.Text = "Fly ON"
			if rootPart then
				flyBV = Instance.new("BodyVelocity")
				flyBV.MaxForce = Vector3.new(100000, 100000, 100000)
				flyBV.Velocity = Vector3.zero; flyBV.Parent = rootPart; flyBV.Name = "AdminFly"
				flyBG = Instance.new("BodyGyro")
				flyBG.MaxTorque = Vector3.new(100000, 100000, 100000)
				flyBG.Parent = rootPart; flyBG.Name = "AdminFlyGyro"
			end
		else
			flyBtn.BackgroundColor3 = flyColor; flyBtn.Text = "Fly"
			if flyBV then flyBV:Destroy(); flyBV = nil end
			if flyBG then flyBG:Destroy(); flyBG = nil end
		end
	end)

	-- Noclip
	local ncColor = Color3.fromRGB(150, 80, 200)
	local noclipBtn = makeBtn("Noclip", ncColor, 2)
	noclipBtn.MouseButton1Click:Connect(function()
		adminNoclip = not adminNoclip
		if adminNoclip then
			noclipBtn.BackgroundColor3 = onColor; noclipBtn.Text = "Noclip ON"
			noclipConn = RunService.Stepped:Connect(function()
				if character then
					for _, p in ipairs(character:GetDescendants()) do
						if p:IsA("BasePart") then p.CanCollide = false end
					end
				end
			end)
		else
			noclipBtn.BackgroundColor3 = ncColor; noclipBtn.Text = "Noclip"
			if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
		end
	end)

	-- God
	local godColor = Color3.fromRGB(200, 180, 50)
	local godBtn = makeBtn("God", godColor, 3)
	godBtn.MouseButton1Click:Connect(function()
		local on = godBtn.Text == "God"
		if on then
			godBtn.BackgroundColor3 = onColor; godBtn.Text = "God ON"
			adminCmd("god", true)
		else
			godBtn.BackgroundColor3 = godColor; godBtn.Text = "God"
			adminCmd("god", false)
		end
	end)

	-- Speed (with input box)
	local speedBtn = makeBtn("Set Speed", Color3.fromRGB(200, 100, 50), 4)
	speedBtn.MouseButton1Click:Connect(function()
		local val = tonumber(speedInput.Text)
		if val then adminCmd("speed", val) end
	end)

	-- SuperJump (with input box)
	local sjBtn = makeBtn("Set Jump", Color3.fromRGB(80, 180, 200), 5)
	sjBtn.MouseButton1Click:Connect(function()
		local val = tonumber(jumpInput.Text)
		if val then adminCmd("jumppower", val) end
	end)

	-- Invisible
	local invisColor = Color3.fromRGB(100, 100, 150)
	local invisBtn = makeBtn("Invisible", invisColor, 6)
	invisBtn.MouseButton1Click:Connect(function()
		local on = invisBtn.Text == "Invisible"
		if on then
			invisBtn.BackgroundColor3 = onColor; invisBtn.Text = "Invis ON"
			if character then
				for _, p in ipairs(character:GetDescendants()) do
					if p:IsA("BasePart") then p.Transparency = 1 end
					if p:IsA("Decal") then p.Transparency = 1 end
				end
			end
		else
			invisBtn.BackgroundColor3 = invisColor; invisBtn.Text = "Invisible"
			if character then
				for _, p in ipairs(character:GetDescendants()) do
					if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.Transparency = 0 end
					if p:IsA("Decal") then p.Transparency = 0 end
				end
			end
		end
	end)

	-- TP Click
	local tpColor = Color3.fromRGB(200, 50, 150)
	local tpBtn = makeBtn("TP Click", tpColor, 7)
	tpBtn.MouseButton1Click:Connect(function()
		tpMode = not tpMode
		if tpMode then
			tpBtn.BackgroundColor3 = onColor; tpBtn.Text = "TP ON"
		else
			tpBtn.BackgroundColor3 = tpColor; tpBtn.Text = "TP Click"
		end
	end)

	-- Respawn
	local respBtn = makeBtn("Respawn", Color3.fromRGB(100, 200, 100), 8)
	respBtn.MouseButton1Click:Connect(function()
		adminCmd("respawn")
	end)

	-- ====== INPUT BOXES ======
	local inputLabel = Instance.new("TextLabel")
	inputLabel.Size = UDim2.new(1, 0, 0, 20)
	inputLabel.Position = UDim2.new(0, 10, 0, 150)
	inputLabel.BackgroundTransparency = 1
	inputLabel.Text = "VALUES"
	inputLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	inputLabel.FontFace = boldFont
	inputLabel.TextSize = 12
	inputLabel.TextXAlignment = Enum.TextXAlignment.Left
	inputLabel.Parent = panelFrame

	local inputFrame = Instance.new("Frame")
	inputFrame.Size = UDim2.new(1, -20, 0, 35)
	inputFrame.Position = UDim2.new(0, 10, 0, 170)
	inputFrame.BackgroundTransparency = 1
	inputFrame.Parent = panelFrame

	local function makeInput(placeholder, posX, width)
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(0, width, 0, 30)
		box.Position = UDim2.new(0, posX, 0, 0)
		box.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
		box.Text = ""
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
		box.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.FontFace = regFont
		box.TextSize = 13
		box.ClearTextOnFocus = false
		box.Parent = inputFrame
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
		Instance.new("UIStroke", box).Color = Color3.fromRGB(80, 80, 100)
		return box
	end

	speedInput = makeInput("Speed (38)", 0, 85)
	jumpInput = makeInput("Jump (72)", 90, 85)
	local banInput = makeInput("Ban mins (60)", 180, 100)

	-- ====== SERVER COMMANDS ======
	local srvLabel = Instance.new("TextLabel")
	srvLabel.Size = UDim2.new(1, 0, 0, 20)
	srvLabel.Position = UDim2.new(0, 10, 0, 210)
	srvLabel.BackgroundTransparency = 1
	srvLabel.Text = "SERVER COMMANDS"
	srvLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	srvLabel.FontFace = boldFont
	srvLabel.TextSize = 12
	srvLabel.TextXAlignment = Enum.TextXAlignment.Left
	srvLabel.Parent = panelFrame

	local srvFrame = Instance.new("Frame")
	srvFrame.Size = UDim2.new(1, -20, 0, 45)
	srvFrame.Position = UDim2.new(0, 10, 0, 230)
	srvFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	srvFrame.Parent = panelFrame
	Instance.new("UICorner", srvFrame).CornerRadius = UDim.new(0, 8)

	local srvGrid = Instance.new("UIGridLayout")
	srvGrid.CellSize = UDim2.new(0, 85, 0, 35)
	srvGrid.CellPadding = UDim2.new(0, 5, 0, 5)
	srvGrid.SortOrder = Enum.SortOrder.LayoutOrder
	srvGrid.Parent = srvFrame
	Instance.new("UIPadding", srvFrame).PaddingTop = UDim.new(0, 5)
	Instance.new("UIPadding", srvFrame).PaddingLeft = UDim.new(0, 5)

	local killAllBtn = makeBtn("Kill All", Color3.fromRGB(200, 30, 30), 1, srvFrame)
	killAllBtn.MouseButton1Click:Connect(function()
		adminCmd("killall")
		killAllBtn.Text = "Done!"; task.delay(0.5, function() killAllBtn.Text = "Kill All" end)
	end)

	local newRoundBtn = makeBtn("New Round", Color3.fromRGB(200, 150, 50), 2, srvFrame)
	newRoundBtn.MouseButton1Click:Connect(function()
		adminCmd("newround")
		newRoundBtn.Text = "Starting..."; task.delay(1, function() newRoundBtn.Text = "New Round" end)
	end)

	local gravBtn = makeBtn("Low Grav", Color3.fromRGB(150, 100, 200), 3, srvFrame)
	gravBtn.MouseButton1Click:Connect(function()
		local on = gravBtn.Text == "Low Grav"
		if on then
			adminCmd("gravity", 50)
			gravBtn.BackgroundColor3 = onColor; gravBtn.Text = "LowG ON"
		else
			adminCmd("gravity", 196.2)
			gravBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 200); gravBtn.Text = "Low Grav"
		end
	end)

	-- ====== PLAYER LIST ======
	local plrLabel = Instance.new("TextLabel")
	plrLabel.Size = UDim2.new(1, 0, 0, 20)
	plrLabel.Position = UDim2.new(0, 10, 0, 280)
	plrLabel.BackgroundTransparency = 1
	plrLabel.Text = "PLAYERS (click to select)"
	plrLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	plrLabel.FontFace = boldFont
	plrLabel.TextSize = 12
	plrLabel.TextXAlignment = Enum.TextXAlignment.Left
	plrLabel.Parent = panelFrame

	local plrScroll = Instance.new("ScrollingFrame")
	plrScroll.Size = UDim2.new(1, -20, 0, 120)
	plrScroll.Position = UDim2.new(0, 10, 0, 300)
	plrScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	plrScroll.ScrollBarThickness = 4
	plrScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	plrScroll.Parent = panelFrame
	Instance.new("UICorner", plrScroll).CornerRadius = UDim.new(0, 8)

	local plrLayout = Instance.new("UIListLayout")
	plrLayout.Padding = UDim.new(0, 2)
	plrLayout.SortOrder = Enum.SortOrder.Name
	plrLayout.Parent = plrScroll

	local selectedLabel = Instance.new("TextLabel")
	selectedLabel.Size = UDim2.new(1, 0, 0, 20)
	selectedLabel.Position = UDim2.new(0, 10, 0, 425)
	selectedLabel.BackgroundTransparency = 1
	selectedLabel.Text = "Selected: None"
	selectedLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	selectedLabel.FontFace = boldFont
	selectedLabel.TextSize = 12
	selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
	selectedLabel.Parent = panelFrame

	-- Player action buttons
	local actFrame = Instance.new("Frame")
	actFrame.Size = UDim2.new(1, -20, 0, 90)
	actFrame.Position = UDim2.new(0, 10, 0, 445)
	actFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	actFrame.Parent = panelFrame
	Instance.new("UICorner", actFrame).CornerRadius = UDim.new(0, 8)

	local actGrid = Instance.new("UIGridLayout")
	actGrid.CellSize = UDim2.new(0, 85, 0, 35)
	actGrid.CellPadding = UDim2.new(0, 5, 0, 5)
	actGrid.SortOrder = Enum.SortOrder.LayoutOrder
	actGrid.Parent = actFrame
	Instance.new("UIPadding", actFrame).PaddingTop = UDim.new(0, 5)
	Instance.new("UIPadding", actFrame).PaddingLeft = UDim.new(0, 5)

	local function plrCmd(cmd)
		if selectedPlayer then
			adminCmd(cmd, selectedPlayer)
		end
	end

	local kickBtn = makeBtn("Kick", Color3.fromRGB(200, 80, 30), 1, actFrame)
	kickBtn.MouseButton1Click:Connect(function() plrCmd("kick") end)

	local banBtn = makeBtn("Ban", Color3.fromRGB(200, 30, 30), 2, actFrame)
	banBtn.MouseButton1Click:Connect(function()
		if selectedPlayer then
			local mins = tonumber(banInput.Text) or 60
			adminCmd("ban", selectedPlayer, mins)
		end
	end)

	local killBtn2 = makeBtn("Kill", Color3.fromRGB(180, 50, 50), 3, actFrame)
	killBtn2.MouseButton1Click:Connect(function() plrCmd("killplayer") end)

	local tpToBtn = makeBtn("TP to Me", Color3.fromRGB(50, 150, 200), 4, actFrame)
	tpToBtn.MouseButton1Click:Connect(function() plrCmd("tptome") end)

	local goToBtn = makeBtn("Go to", Color3.fromRGB(100, 50, 200), 5, actFrame)
	goToBtn.MouseButton1Click:Connect(function() plrCmd("goto") end)

	local freezeBtn = makeBtn("Freeze", Color3.fromRGB(50, 180, 180), 6, actFrame)
	freezeBtn.MouseButton1Click:Connect(function() plrCmd("freezeplayer") end)

	local unfreezeBtn = makeBtn("Unfreeze", Color3.fromRGB(80, 200, 80), 7, actFrame)
	unfreezeBtn.MouseButton1Click:Connect(function() plrCmd("unfreezeplayer") end)

	-- Build player list
	local function refreshPlayerList()
		for _, child in ipairs(plrScroll:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end

		for _, p in ipairs(Players:GetPlayers()) do
			local row = Instance.new("TextButton")
			row.Name = p.Name
			row.Size = UDim2.new(1, 0, 0, 40)
			row.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
			row.BackgroundTransparency = 0
			row.Text = ""
			row.Parent = plrScroll
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

			-- Avatar
			local avatar = Instance.new("ImageLabel")
			avatar.Size = UDim2.new(0, 30, 0, 30)
			avatar.Position = UDim2.new(0, 5, 0.5, -15)
			avatar.BackgroundTransparency = 1
			avatar.Image = Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			avatar.Parent = row
			Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

			-- Name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -45, 1, 0)
			nameLabel.Position = UDim2.new(0, 40, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = p.DisplayName .. " (@" .. p.Name .. ")"
			nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLabel.FontFace = regFont
			nameLabel.TextSize = 12
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			row.MouseButton1Click:Connect(function()
				selectedPlayer = p.Name
				selectedLabel.Text = "Selected: " .. p.DisplayName .. " (@" .. p.Name .. ")"

				-- Highlight selected
				for _, child in ipairs(plrScroll:GetChildren()) do
					if child:IsA("TextButton") then
						child.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
					end
				end
				row.BackgroundColor3 = Color3.fromRGB(60, 50, 100)
			end)
		end
	end

	-- Refresh on open and when players join/leave
	Players.PlayerAdded:Connect(refreshPlayerList)
	Players.PlayerRemoving:Connect(function()
		task.wait(0.1)
		refreshPlayerList()
	end)

	-- TP click handler
	local mouse = player:GetMouse()
	mouse.Button1Down:Connect(function()
		if tpMode and rootPart then
			local target = mouse.Hit
			if target then rootPart.CFrame = target + Vector3.new(0, 5, 0) end
		end
	end)

	-- Fly movement
	RunService.RenderStepped:Connect(function()
		if not adminFlying or not flyBV or not rootPart then return end
		local flySpeed = 80
		local camCF = camera.CFrame
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + camCF.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - camCF.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + camCF.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
		flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * flySpeed or Vector3.zero
		flyBG.CFrame = CFrame.new(Vector3.zero, camCF.LookVector)
	end)

	-- Refresh list on first open
	task.defer(refreshPlayerList)
end

-- ============= INPUT =============
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Admin panel toggle (P) — works even when dead
	if input.KeyCode == Enum.KeyCode.P and isAdmin and adminPanel then
		adminPanelOpen = not adminPanelOpen
		adminPanel.PanelFrame.Visible = adminPanelOpen
		return
	end

	if not humanoid or humanoid.Health <= 0 then return end

	if input.KeyCode == Enum.KeyCode.C then
		if humanoid.MoveDirection.Magnitude > 0.1 then
			startSlide()
		else
			toggleCrouch()
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		doDash()
	elseif input.KeyCode == Enum.KeyCode.R then
		Remotes.ResetToCheckpoint:FireServer()
	end
end)

-- ============= UPDATE LOOP =============
RunService.Heartbeat:Connect(function(dt)
	if not character or not humanoid or not rootPart then return end
	if humanoid.Health <= 0 then return end

	-- Speed ramp: accelerate from 0 to sprint speed
	local maxSpeed = GameConfig.Player.sprintSpeed
	local accelRate = 25 -- studs/s² acceleration
	if state.crouching then
		maxSpeed = GameConfig.Player.sprintSpeed * 0.5
	end

	if not state.sliding and not state.dashing and not state.charging then
		if humanoid.MoveDirection.Magnitude > 0.1 then
			state.currentSpeed = math.min(state.currentSpeed + accelRate * dt, maxSpeed)
		else
			state.currentSpeed = math.max(state.currentSpeed - accelRate * 2 * dt, 0)
		end
		humanoid.WalkSpeed = state.currentSpeed
	end

	-- Ground check
	local wasGrounded = state.grounded
	state.grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	-- Just landed
	if state.grounded and not wasGrounded then
		playAnim("land", 0.05)
		task.delay(0.3, function()
			stopAnim("land")
		end)
	end

	-- Wall run / ledge grab when in air
	if not state.grounded and not state.dashing and not state.charging then
		if humanoid.MoveDirection.Magnitude > 0.1 then
			tryWallRun()
		end
		tryLedgeGrab()
	end

	-- Vault check when running
	if state.grounded and humanoid.MoveDirection.Magnitude > 0.1 then
		if not state.sliding and not state.dashing then
			tryVault()
		end
	end

	-- Animation states
	if state.sliding or state.dashing or state.wallRunning or state.ledgeGrabbing or state.vaulting then
		return
	end

	local speed = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Magnitude

	if state.grounded then
		stopAnim("jump")
		stopAnim("fall")

		if state.crouching then
			if speed > 0.1 then
				stopAnim("crouchIdle")
				stopAnim("idle")
				playAnim("crouchMove")
			else
				stopAnim("crouchMove")
				stopAnim("idle")
				playAnim("crouchIdle")
			end
			stopAnim("walk")
			stopAnim("run")
		elseif speed > 0.1 then
			stopAnim("idle")
			stopAnim("crouchIdle")
			stopAnim("crouchMove")

			-- Walk when slow, run when fast
			local runThreshold = GameConfig.Player.walkSpeed
			if state.currentSpeed < runThreshold then
				stopAnim("run")
				playAnim("walk")

				stopAnim("tiltLeftRun")
				stopAnim("tiltRightRun")
				stopAnim("tiltBack")
				if rootPart then
					local localDir = rootPart.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
					stopAnim("tiltLeft")
					stopAnim("tiltRight")
					if localDir.X < -0.5 then
						playAnim("tiltLeft")
					elseif localDir.X > 0.5 then
						playAnim("tiltRight")
					end
				end
			else
				stopAnim("walk")
				playAnim("run")

				-- Tilt animations while running
				if rootPart then
					local localDir = rootPart.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
					stopAnim("tiltLeft")
					stopAnim("tiltRight")
					stopAnim("tiltLeftRun")
					stopAnim("tiltRightRun")
					stopAnim("tiltBack")

					if localDir.X < -0.5 then
						playAnim("tiltLeftRun")
					elseif localDir.X > 0.5 then
						playAnim("tiltRightRun")
					end
					if localDir.Z > 0.3 then
						playAnim("tiltBack")
					end
				end
			end
		else
			stopAnim("walk")
			stopAnim("run")
			stopAnim("crouchIdle")
			stopAnim("crouchMove")
			stopAnim("tiltLeft")
			stopAnim("tiltRight")
			stopAnim("tiltLeftRun")
			stopAnim("tiltRightRun")
			stopAnim("tiltBack")
			playAnim("idle")
		end
	else
		-- In air
		stopAnim("walk")
		stopAnim("run")
		stopAnim("idle")
		stopAnim("crouchIdle")
		stopAnim("crouchMove")
		stopAnim("tiltLeft")
		stopAnim("tiltRight")
		stopAnim("tiltLeftRun")
		stopAnim("tiltRightRun")
		stopAnim("tiltBack")

		-- Jump when going up, fall when going down
		if rootPart.Velocity.Y < -5 then
			stopAnim("jump")
			playAnim("fall")
		else
			stopAnim("fall")
			playAnim("jump")
		end
	end
end)

-- ============= UI =============
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MovementMayhemUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local UI = GameConfig.UI
local currentRole = "spectator"

-- Role display (top center)
local roleFrame = Instance.new("Frame")
roleFrame.Name = "RoleFrame"
roleFrame.Size = UDim2.new(0, 250, 0, 50)
roleFrame.Position = UDim2.new(0.5, -125, 0, 10)
roleFrame.BackgroundColor3 = UI.backgroundColor
roleFrame.BackgroundTransparency = 0.3
roleFrame.Parent = screenGui

local roleCorner = Instance.new("UICorner")
roleCorner.CornerRadius = UI.cornerRadius
roleCorner.Parent = roleFrame

local roleLabel = Instance.new("TextLabel")
roleLabel.Name = "RoleLabel"
roleLabel.Size = UDim2.new(1, 0, 1, 0)
roleLabel.BackgroundTransparency = 1
roleLabel.Text = "Lobby"
roleLabel.TextColor3 = UI.textColor
roleLabel.FontFace = UI.titleFontFace
roleLabel.TextSize = 24
roleLabel.Parent = roleFrame

-- Timer display
local timerFrame = Instance.new("Frame")
timerFrame.Name = "TimerFrame"
timerFrame.Size = UDim2.new(0, 150, 0, 40)
timerFrame.Position = UDim2.new(0.5, -75, 0, 65)
timerFrame.BackgroundColor3 = UI.secondaryColor
timerFrame.BackgroundTransparency = 0.3
timerFrame.Parent = screenGui

local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UI.cornerRadius
timerCorner.Parent = timerFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, 0, 1, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = ""
timerLabel.TextColor3 = UI.accentColor
timerLabel.FontFace = UI.fontFace
timerLabel.TextSize = 20
timerLabel.Parent = timerFrame

-- Alive counter
local aliveFrame = Instance.new("Frame")
aliveFrame.Name = "AliveFrame"
aliveFrame.Size = UDim2.new(0, 150, 0, 35)
aliveFrame.Position = UDim2.new(0.5, -75, 0, 110)
aliveFrame.BackgroundColor3 = UI.secondaryColor
aliveFrame.BackgroundTransparency = 0.3
aliveFrame.Parent = screenGui

local aliveCorner = Instance.new("UICorner")
aliveCorner.CornerRadius = UI.cornerRadius
aliveCorner.Parent = aliveFrame

local aliveLabel = Instance.new("TextLabel")
aliveLabel.Name = "AliveLabel"
aliveLabel.Size = UDim2.new(1, 0, 1, 0)
aliveLabel.BackgroundTransparency = 1
aliveLabel.Text = ""
aliveLabel.TextColor3 = UI.textColor
aliveLabel.FontFace = UI.fontFace
aliveLabel.TextSize = 16
aliveLabel.Parent = aliveFrame

-- Big center text (countdown, winner, etc)
local centerLabel = Instance.new("TextLabel")
centerLabel.Name = "CenterLabel"
centerLabel.Size = UDim2.new(0, 400, 0, 100)
centerLabel.Position = UDim2.new(0.5, -200, 0.35, 0)
centerLabel.BackgroundTransparency = 1
centerLabel.Text = ""
centerLabel.TextColor3 = UI.accentColor
centerLabel.FontFace = UI.titleFontFace
centerLabel.TextSize = 48
centerLabel.TextStrokeTransparency = 0.5
centerLabel.Parent = screenGui

-- Trap buttons container (only visible for death role)
local trapButtonsFrame = Instance.new("ScrollingFrame")
trapButtonsFrame.Name = "TrapButtons"
trapButtonsFrame.Size = UDim2.new(0, 200, 0, 300)
trapButtonsFrame.Position = UDim2.new(0, 10, 0.5, -150)
trapButtonsFrame.BackgroundColor3 = UI.backgroundColor
trapButtonsFrame.BackgroundTransparency = 0.3
trapButtonsFrame.ScrollBarThickness = 4
trapButtonsFrame.Visible = false
trapButtonsFrame.Parent = screenGui

local trapCorner = Instance.new("UICorner")
trapCorner.CornerRadius = UI.cornerRadius
trapCorner.Parent = trapButtonsFrame

local trapLayout = Instance.new("UIListLayout")
trapLayout.Padding = UDim.new(0, 5)
trapLayout.SortOrder = Enum.SortOrder.Name
trapLayout.Parent = trapButtonsFrame

local trapPadding = Instance.new("UIPadding")
trapPadding.PaddingTop = UDim.new(0, 5)
trapPadding.PaddingLeft = UDim.new(0, 5)
trapPadding.PaddingRight = UDim.new(0, 5)
trapPadding.Parent = trapButtonsFrame

-- Controls hint
local controlsFrame = Instance.new("Frame")
controlsFrame.Name = "ControlsFrame"
controlsFrame.Size = UDim2.new(0, 220, 0, 110)
controlsFrame.Position = UDim2.new(1, -230, 1, -130)
controlsFrame.BackgroundColor3 = UI.backgroundColor
controlsFrame.BackgroundTransparency = 0.5
controlsFrame.Parent = screenGui

local controlsCornerUI = Instance.new("UICorner")
controlsCornerUI.CornerRadius = UI.cornerRadius
controlsCornerUI.Parent = controlsFrame

local controlsLabel = Instance.new("TextLabel")
controlsLabel.Size = UDim2.new(1, -10, 1, -10)
controlsLabel.Position = UDim2.new(0, 5, 0, 5)
controlsLabel.BackgroundTransparency = 1
controlsLabel.Text = "[C] Slide / Crouch\n[Q] Dash\n[R] Reset\n[Space] Jump / Ledge Climb"
controlsLabel.TextColor3 = UI.textColor
controlsLabel.FontFace = UI.fontFace
controlsLabel.TextSize = 14
controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
controlsLabel.Parent = controlsFrame

-- ============= TRAP BUTTONS =============
local function buildTrapButtons()
	-- Clear old buttons
	for _, child in ipairs(trapButtonsFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	local traps = workspace:FindFirstChild("Traps")
	if not traps then return end

	for _, trapFolder in ipairs(traps:GetChildren()) do
		if trapFolder:IsA("Folder") or trapFolder:IsA("Model") then
			local btn = Instance.new("TextButton")
			btn.Name = trapFolder.Name
			btn.Size = UDim2.new(1, -10, 0, 40)
			btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			btn.Text = trapFolder.Name
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.FontFace = UI.titleFontFace
			btn.TextSize = 16
			btn.Parent = trapButtonsFrame

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = btn

			btn.MouseButton1Click:Connect(function()
				Remotes.ActivateTrap:FireServer(trapFolder.Name)
				-- Flash feedback
				btn.BackgroundColor3 = Color3.fromRGB(100, 20, 20)
				task.delay(0.3, function()
					btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
				end)
			end)
		end
	end
end

-- ============= SHOW CENTER TEXT =============
local function showCenterText(text, duration, color)
	centerLabel.Text = text
	centerLabel.TextColor3 = color or UI.accentColor
	task.delay(duration or 3, function()
		if centerLabel.Text == text then
			centerLabel.Text = ""
		end
	end)
end

-- ============= REMOTE HANDLERS =============
local Remotes_ActivateTrap = ReplicatedStorage:WaitForChild("ActivateTrap")
local Remotes_RoundInfo = ReplicatedStorage:WaitForChild("RoundInfo")
local Remotes_SetRole = ReplicatedStorage:WaitForChild("SetRole")

Remotes_SetRole.OnClientEvent:Connect(function(role)
	currentRole = role

	if role == "death" then
		roleLabel.Text = "DEATH - Activate Traps!"
		roleLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
		roleFrame.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
		trapButtonsFrame.Visible = true
		controlsFrame.Visible = false
		buildTrapButtons()
	elseif role == "runner" then
		roleLabel.Text = "RUNNER - Reach the End!"
		roleLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		roleFrame.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
		trapButtonsFrame.Visible = false
		controlsFrame.Visible = true
	else
		roleLabel.Text = "Spectating"
		roleLabel.TextColor3 = UI.textColor
		roleFrame.BackgroundColor3 = UI.backgroundColor
		trapButtonsFrame.Visible = false
		controlsFrame.Visible = true
	end
end)

Remotes_RoundInfo.OnClientEvent:Connect(function(msgType, ...)
	local args = {...}

	if msgType == "waiting" then
		showCenterText("Waiting for " .. args[1] .. " players...", 5)
		timerLabel.Text = ""
		aliveLabel.Text = ""

	elseif msgType == "intermission" then
		showCenterText("Next round in " .. args[1] .. "...", 1.5)

	elseif msgType == "round_start" then
		local deathName = args[1]
		local runnerCount = args[2]
		showCenterText("Death: " .. deathName, 3, Color3.fromRGB(255, 50, 50))
		aliveLabel.Text = "Alive: " .. runnerCount .. "/" .. runnerCount

	elseif msgType == "countdown" then
		local num = args[1]
		if num > 0 then
			showCenterText(tostring(num), 1, UI.accentColor)
		else
			showCenterText("GO!", 1, UI.successColor)
		end

	elseif msgType == "timer" then
		local timeLeft = args[1]
		local mins = math.floor(timeLeft / 60)
		local secs = timeLeft % 60
		timerLabel.Text = string.format("%d:%02d", mins, secs)

	elseif msgType == "death_count" then
		local alive = args[1]
		local total = args[2]
		aliveLabel.Text = "Alive: " .. alive .. "/" .. total

	elseif msgType == "winner" then
		showCenterText(args[1] .. " WINS!", 4, UI.successColor)
		timerLabel.Text = ""

	elseif msgType == "death_wins" then
		showCenterText("Death wins! " .. args[1] .. " killed everyone!", 4, Color3.fromRGB(255, 50, 50))
		timerLabel.Text = ""

	elseif msgType == "time_up" then
		showCenterText("Time's up! Runners survive!", 4, UI.successColor)
		timerLabel.Text = ""

	elseif msgType == "death_left" then
		showCenterText("Death left! New round...", 3)

	elseif msgType == "not_enough" then
		showCenterText("Not enough players!", 3, UI.errorColor)
		timerLabel.Text = ""
		aliveLabel.Text = ""
	end
end)

print("[Movement Mayhem] Client loaded!")
