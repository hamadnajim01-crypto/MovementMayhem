--[[
	GameConfig - Movement Mayhem
]]

local GameConfig = {}

-- ============= ADMINS =============
GameConfig.Admins = {
	[7983402147] = true,
}

-- ============= PLAYER =============
GameConfig.Player = {
	walkSpeed = 24,
	sprintSpeed = 38,
	jumpHeight = 7.2,
	sprintStamina = 100,
	staminaDrainRate = 20,
	staminaRegenRate = 15,
	slideSpeed = 45,
	slideDuration = 0.8,
	dashCooldown = 1.5,
	dashForce = 85,
	chargeCooldown = 3,
}

-- ============= ANIMATIONS =============
GameConfig.Animations = {
	idle = "rbxassetid://71935557483669",
	walk = "rbxassetid://82005370036673",
	run = "rbxassetid://102823137557654",
	jump = "rbxassetid://80467961294619",
	slide = "rbxassetid://106519514756127",
	crouchIdle = "rbxassetid://100444732222169",
	crouchMove = "rbxassetid://134906794187604",
	charge = "rbxassetid://129112524218872",
	dash1 = "rbxassetid://93756773723224",
	dash2 = "rbxassetid://98755969974419",
	dashBack = "rbxassetid://85898248695177",
	dashLeft = "rbxassetid://127681234113604",
	dashRight = "rbxassetid://95989197115634",
	tiltLeft = "rbxassetid://127168902326586",
	tiltRight = "rbxassetid://107739914358998",
	tiltLeftRun = "rbxassetid://79036526097238",
	tiltRightRun = "rbxassetid://117396831335385",
	tiltBack = "rbxassetid://108964944999253",
	swim = "rbxassetid://77675653923109",
	climb = "rbxassetid://77842841463703",
	land = "rbxassetid://80656699787214",
	ledgeGrab = "rbxassetid://81878660258357",
	ledgeClimbUp = "rbxassetid://78015306190560",
	ledgeRoll = "rbxassetid://137964011666431",
}

-- ============= STAGES =============
-- Stages are folders in Workspace named "Stage1", "Stage2", etc.
-- Each stage has a SpawnPart and a FinishPart
GameConfig.Stages = {
	totalStages = 20,
}

-- ============= DIFFICULTY COLORS =============
GameConfig.Difficulty = {
	easy = Color3.fromRGB(100, 255, 100),       -- green
	medium = Color3.fromRGB(255, 255, 50),       -- yellow
	hard = Color3.fromRGB(255, 130, 30),         -- orange
	insane = Color3.fromRGB(255, 50, 50),        -- red
	impossible = Color3.fromRGB(150, 0, 200),    -- purple
}

-- ============= UI =============
GameConfig.UI = {
	primaryColor = Color3.fromRGB(50, 180, 255),
	secondaryColor = Color3.fromRGB(40, 40, 60),
	accentColor = Color3.fromRGB(255, 200, 50),
	textColor = Color3.fromRGB(255, 255, 255),
	backgroundColor = Color3.fromRGB(25, 25, 35),
	successColor = Color3.fromRGB(100, 255, 100),
	errorColor = Color3.fromRGB(255, 80, 80),
	cornerRadius = UDim.new(0, 8),
	fontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
	titleFontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}

return GameConfig
