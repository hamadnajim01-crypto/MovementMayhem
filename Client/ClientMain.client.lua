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
}

-- ============= STATE =============
local character, humanoid, rootPart, animator
local animations = {}
local currentAnims = {}

local state = {
	sprinting = false,
	sliding = false,
	crouching = false,
	dashing = false,
	charging = false,
	wallRunning = false,
	ledgeGrabbing = false,
	vaulting = false,
	shiftLocked = false,
	grounded = true,

	stamina = GameConfig.Player.sprintStamina,
	dashCooldown = 0,
	chargeCooldown = 0,
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

	state.sprinting = false
	state.sliding = false
	state.crouching = false
	state.dashing = false
	state.charging = false
	state.wallRunning = false
	state.ledgeGrabbing = false
	state.vaulting = false
	state.stamina = GameConfig.Player.sprintStamina

	humanoid.WalkSpeed = GameConfig.Player.walkSpeed
	humanoid.JumpPower = GameConfig.Player.jumpHeight * 10
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ============= SPRINT =============
local function startSprint()
	if state.sliding or state.crouching or state.dashing or state.charging then return end
	if state.stamina <= 0 then return end
	state.sprinting = true
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
	end
end

local function stopSprint()
	state.sprinting = false
	if humanoid and not state.sliding and not state.crouching then
		humanoid.WalkSpeed = GameConfig.Player.walkSpeed
	end
end

-- ============= SLIDE =============
local function startSlide()
	if state.sliding or state.dashing or state.charging then return end
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
				if state.sprinting then
					humanoid.WalkSpeed = GameConfig.Player.sprintSpeed
				else
					humanoid.WalkSpeed = GameConfig.Player.walkSpeed
				end
			end
		end)
	end
end

-- ============= CROUCH =============
local function toggleCrouch()
	if state.sliding or state.dashing or state.charging then return end

	if state.crouching then
		state.crouching = false
		stopAnim("crouchIdle")
		stopAnim("crouchMove")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.Player.walkSpeed
		end
	else
		state.crouching = true
		state.sprinting = false
		if humanoid then
			humanoid.WalkSpeed = GameConfig.Player.walkSpeed * 0.5
		end
	end
end

-- ============= DASH =============
local function doDash()
	if state.dashing or state.sliding or state.charging then return end
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

-- ============= CHARGE =============
local function doCharge()
	if state.charging or state.sliding or state.dashing then return end
	if not state.sprinting then return end
	if tick() - state.chargeCooldown < GameConfig.Player.chargeCooldown then return end

	state.charging = true
	state.chargeCooldown = tick()

	stopAnim("run")
	playAnim("charge", 0.1)

	if rootPart then
		local chargeDir = rootPart.CFrame.LookVector
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(60000, 5000, 60000)
		bv.Velocity = chargeDir * (GameConfig.Player.dashForce * 1.2) + Vector3.new(0, 5, 0)
		bv.Parent = rootPart
		bv.Name = "ChargeForce"

		task.delay(0.5, function()
			bv:Destroy()
		end)
	end

	-- Stamina boost after charge
	state.stamina = math.min(state.stamina + 30, GameConfig.Player.sprintStamina)

	task.delay(0.6, function()
		state.charging = false
		stopAnim("charge")
	end)
end

-- ============= WALL RUN =============
local WALL_RUN_DURATION = 1.2
local WALL_RUN_SPEED = 30

local function tryWallRun()
	if state.wallRunning or state.sliding or state.ledgeGrabbing then return end
	if not rootPart or not humanoid then return end
	if humanoid.FloorMaterial ~= Enum.Material.Air then return end

	-- Raycast left and right to find walls
	local directions = {
		rootPart.CFrame.RightVector,
		-rootPart.CFrame.RightVector,
	}

	for _, dir in ipairs(directions) do
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(rootPart.Position, dir * 3, rayParams)
		if result and result.Instance and result.Instance.Anchored then
			state.wallRunning = true

			-- Wall run upward along the wall
			local wallNormal = result.Normal
			local upDir = Vector3.new(0, 1, 0)
			local wallForward = upDir:Cross(wallNormal).Unit

			-- Make sure we run in the direction we're moving
			if rootPart.CFrame.LookVector:Dot(wallForward) < 0 then
				wallForward = -wallForward
			end

			playAnim("run", 0.1)

			local bg = Instance.new("BodyGyro")
			bg.MaxTorque = Vector3.new(100000, 100000, 100000)
			bg.CFrame = CFrame.lookAt(Vector3.zero, wallForward, wallNormal)
			bg.Parent = rootPart
			bg.Name = "WallRunGyro"

			local bv = Instance.new("BodyVelocity")
			bv.MaxForce = Vector3.new(50000, 50000, 50000)
			bv.Velocity = wallForward * WALL_RUN_SPEED + Vector3.new(0, 15, 0)
			bv.Parent = rootPart
			bv.Name = "WallRunForce"

			task.delay(WALL_RUN_DURATION, function()
				bv:Destroy()
				bg:Destroy()
				state.wallRunning = false

				-- Wall jump off
				if rootPart then
					local jumpOff = Instance.new("BodyVelocity")
					jumpOff.MaxForce = Vector3.new(30000, 30000, 30000)
					jumpOff.Velocity = wallNormal * 30 + Vector3.new(0, 40, 0)
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

	-- Use jump animation for vault
	playAnim("jump", 0.05)

	task.delay(0.4, function()
		bv:Destroy()
		state.vaulting = false
		stopAnim("jump")
	end)
end

-- ============= SHIFT LOCK =============
local function toggleShiftLock()
	state.shiftLocked = not state.shiftLocked

	if state.shiftLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		if humanoid then
			humanoid.AutoRotate = false
		end
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
end

-- ============= INPUT =============
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not humanoid or humanoid.Health <= 0 then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		startSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		toggleShiftLock()
	elseif input.KeyCode == Enum.KeyCode.C then
		if state.sprinting then
			startSlide()
		else
			toggleCrouch()
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		doDash()
	elseif input.KeyCode == Enum.KeyCode.F then
		doCharge()
	elseif input.KeyCode == Enum.KeyCode.R then
		Remotes.ResetToCheckpoint:FireServer()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		stopSprint()
	end
end)

-- ============= SHIFT LOCK CAMERA =============
RunService.RenderStepped:Connect(function()
	if not character or not rootPart or not humanoid then return end
	if humanoid.Health <= 0 then return end

	if state.shiftLocked then
		local camCF = camera.CFrame
		local lookDir = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + lookDir)

		-- Over-the-shoulder offset
		camera.CFrame = camera.CFrame * CFrame.new(1.5, 0.5, 0)
	end
end)

-- ============= UPDATE LOOP =============
RunService.Heartbeat:Connect(function(dt)
	if not character or not humanoid or not rootPart then return end
	if humanoid.Health <= 0 then return end

	-- Stamina
	if state.sprinting and humanoid.MoveDirection.Magnitude > 0.1 then
		state.stamina = state.stamina - GameConfig.Player.staminaDrainRate * dt
		if state.stamina <= 0 then
			state.stamina = 0
			stopSprint()
		end
	else
		state.stamina = math.min(state.stamina + GameConfig.Player.staminaRegenRate * dt, GameConfig.Player.sprintStamina)
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
	if state.grounded and (state.sprinting or humanoid.MoveDirection.Magnitude > 0.1) then
		if not state.sliding and not state.dashing then
			tryVault()
		end
	end

	-- Animation states
	if state.sliding or state.dashing or state.charging or state.wallRunning or state.ledgeGrabbing or state.vaulting then
		return
	end

	local speed = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z).Magnitude

	if state.grounded then
		stopAnim("jump")

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

			if state.sprinting then
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
			else
				stopAnim("run")
				playAnim("walk")

				-- Tilt animations while walking
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
		playAnim("jump")
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

-- Stage display
local stageFrame = Instance.new("Frame")
stageFrame.Name = "StageFrame"
stageFrame.Size = UDim2.new(0, 200, 0, 50)
stageFrame.Position = UDim2.new(0.5, -100, 0, 10)
stageFrame.BackgroundColor3 = UI.backgroundColor
stageFrame.BackgroundTransparency = 0.3
stageFrame.Parent = screenGui

local stageCorner = Instance.new("UICorner")
stageCorner.CornerRadius = UI.cornerRadius
stageCorner.Parent = stageFrame

local stageLabel = Instance.new("TextLabel")
stageLabel.Name = "StageLabel"
stageLabel.Size = UDim2.new(1, 0, 1, 0)
stageLabel.BackgroundTransparency = 1
stageLabel.Text = "Stage 1"
stageLabel.TextColor3 = UI.textColor
stageLabel.FontFace = UI.titleFontFace
stageLabel.TextSize = 24
stageLabel.Parent = stageFrame

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
timerLabel.Text = "0.00s"
timerLabel.TextColor3 = UI.accentColor
timerLabel.FontFace = UI.fontFace
timerLabel.TextSize = 20
timerLabel.Parent = timerFrame

-- Stamina bar
local staminaFrame = Instance.new("Frame")
staminaFrame.Name = "StaminaFrame"
staminaFrame.Size = UDim2.new(0, 200, 0, 8)
staminaFrame.Position = UDim2.new(0.5, -100, 1, -30)
staminaFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
staminaFrame.BackgroundTransparency = 0.3
staminaFrame.Parent = screenGui

local staminaCorner = Instance.new("UICorner")
staminaCorner.CornerRadius = UDim.new(0, 4)
staminaCorner.Parent = staminaFrame

local staminaBar = Instance.new("Frame")
staminaBar.Name = "Fill"
staminaBar.Size = UDim2.new(1, 0, 1, 0)
staminaBar.BackgroundColor3 = UI.primaryColor
staminaBar.Parent = staminaFrame

local staminaBarCorner = Instance.new("UICorner")
staminaBarCorner.CornerRadius = UDim.new(0, 4)
staminaBarCorner.Parent = staminaBar

-- Controls hint
local controlsFrame = Instance.new("Frame")
controlsFrame.Name = "ControlsFrame"
controlsFrame.Size = UDim2.new(0, 220, 0, 140)
controlsFrame.Position = UDim2.new(1, -230, 1, -160)
controlsFrame.BackgroundColor3 = UI.backgroundColor
controlsFrame.BackgroundTransparency = 0.5
controlsFrame.Parent = screenGui

local controlsCorner = Instance.new("UICorner")
controlsCorner.CornerRadius = UI.cornerRadius
controlsCorner.Parent = controlsFrame

local controlsLabel = Instance.new("TextLabel")
controlsLabel.Size = UDim2.new(1, -10, 1, -10)
controlsLabel.Position = UDim2.new(0, 5, 0, 5)
controlsLabel.BackgroundTransparency = 1
controlsLabel.Text = "[Shift] Sprint\n[Ctrl] Shift Lock\n[C] Slide / Crouch\n[Q] Dash\n[F] Charge\n[R] Reset to Checkpoint\n[Space] Jump / Ledge Climb"
controlsLabel.TextColor3 = UI.textColor
controlsLabel.FontFace = UI.fontFace
controlsLabel.TextSize = 14
controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
controlsLabel.Parent = controlsFrame

-- Stage complete popup
local completeFrame = Instance.new("Frame")
completeFrame.Name = "CompleteFrame"
completeFrame.Size = UDim2.new(0, 300, 0, 120)
completeFrame.Position = UDim2.new(0.5, -150, 0.3, 0)
completeFrame.BackgroundColor3 = UI.backgroundColor
completeFrame.BackgroundTransparency = 0.1
completeFrame.Visible = false
completeFrame.Parent = screenGui

local completeCorner = Instance.new("UICorner")
completeCorner.CornerRadius = UI.cornerRadius
completeCorner.Parent = completeFrame

local completeTitle = Instance.new("TextLabel")
completeTitle.Name = "Title"
completeTitle.Size = UDim2.new(1, 0, 0, 40)
completeTitle.BackgroundTransparency = 1
completeTitle.Text = "Stage Complete!"
completeTitle.TextColor3 = UI.successColor
completeTitle.FontFace = UI.titleFontFace
completeTitle.TextSize = 26
completeTitle.Parent = completeFrame

local completeTime = Instance.new("TextLabel")
completeTime.Name = "Time"
completeTime.Size = UDim2.new(1, 0, 0, 30)
completeTime.Position = UDim2.new(0, 0, 0, 40)
completeTime.BackgroundTransparency = 1
completeTime.Text = "Time: 0.00s"
completeTime.TextColor3 = UI.textColor
completeTime.FontFace = UI.fontFace
completeTime.TextSize = 20
completeTime.Parent = completeFrame

local completeBest = Instance.new("TextLabel")
completeBest.Name = "Best"
completeBest.Size = UDim2.new(1, 0, 0, 30)
completeBest.Position = UDim2.new(0, 0, 0, 70)
completeBest.BackgroundTransparency = 1
completeBest.Text = "Best: 0.00s"
completeBest.TextColor3 = UI.accentColor
completeBest.FontFace = UI.fontFace
completeBest.TextSize = 18
completeBest.Parent = completeFrame

-- Update stamina bar
RunService.Heartbeat:Connect(function()
	local pct = state.stamina / GameConfig.Player.sprintStamina
	staminaBar.Size = UDim2.new(pct, 0, 1, 0)

	if pct < 0.3 then
		staminaBar.BackgroundColor3 = UI.errorColor
	elseif pct < 0.6 then
		staminaBar.BackgroundColor3 = UI.accentColor
	else
		staminaBar.BackgroundColor3 = UI.primaryColor
	end
end)

-- Update timer
RunService.Heartbeat:Connect(function()
	if state.stageStartTime > 0 then
		local elapsed = tick() - state.stageStartTime
		timerLabel.Text = string.format("%.2fs", elapsed)
	end
end)

-- ============= REMOTE HANDLERS =============
Remotes.UpdateStage.OnClientEvent:Connect(function(stageNum, bestTimes)
	state.currentStage = stageNum
	state.bestTimes = bestTimes or {}
	state.stageStartTime = tick()
	stageLabel.Text = "Stage " .. stageNum
end)

Remotes.StageComplete.OnClientEvent:Connect(function(stageNum, completionTime, bestTime)
	completeTitle.Text = "Stage " .. stageNum .. " Complete!"
	completeTime.Text = "Time: " .. string.format("%.2fs", completionTime)
	if bestTime then
		completeBest.Text = "Best: " .. string.format("%.2fs", bestTime)
	else
		completeBest.Text = ""
	end

	completeFrame.Visible = true
	completeFrame.Position = UDim2.new(0.5, -150, 0.2, 0)
	completeFrame.BackgroundTransparency = 0.1

	-- Animate in
	TweenService:Create(completeFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -150, 0.3, 0)
	}):Play()

	-- Fade out after 3 seconds
	task.delay(3, function()
		TweenService:Create(completeFrame, TweenInfo.new(0.5), {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, -150, 0.25, 0)
		}):Play()
		task.wait(0.5)
		completeFrame.Visible = false
	end)

	state.stageStartTime = tick()
end)

print("[Movement Mayhem] Client loaded!")
