-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [CONFIG & VARIABLES]
-- ==========================================
local CONFIG = {
    AutoFarm = false,
    FlySpeed = 280,              -- ความเร็วบิน
    ServerHopWhenEmpty = true,   -- ย้ายเซิร์ฟอัตโนมัติเมื่อกล่องหมด
    CollectDelay = 0.15,         -- เวลาหน่วงเก็บกล่อง
    GlowColor = Color3.fromRGB(0, 255, 180) -- สีไฟใต้เท้า
}

local noclipConn = nil
local activeTweens = {}
local activeGlowSessions = {}
local CommF = ReplicatedStorage:WaitForChild("Remotes", 5) and ReplicatedStorage.Remotes:WaitForChild("CommF_", 5)

-- ==========================================
-- [1. TWEENSYSTEM & FOOT GLOW MODULE]
-- ==========================================
local TweenSystem = {}
local EASING_STYLES = { Linear = Enum.EasingStyle.Linear, Quad = Enum.EasingStyle.Quad }
local EASING_DIRECTIONS = { Out = Enum.EasingDirection.Out }

function TweenSystem.Cancel(instance)
    if activeTweens[instance] then
        activeTweens[instance]:Cancel()
        activeTweens[instance] = nil
    end
    if activeGlowSessions[instance] then
        activeGlowSessions[instance].Stop()
        activeGlowSessions[instance] = nil
    end
end

function TweenSystem.Play(instance, props, time, style, direction, onComplete)
    TweenSystem.Cancel(instance)
    local tweenInfo = TweenInfo.new(time or 0.3, EASING_STYLES[style] or Enum.EasingStyle.Linear, EASING_DIRECTIONS[direction] or Enum.EasingDirection.Out)
    local tween = TweenService:Create(instance, tweenInfo, props)
    activeTweens[instance] = tween

    local conn
    conn = tween.Completed:Connect(function(state)
        if conn then conn:Disconnect() end
        if activeTweens[instance] == tween then activeTweens[instance] = nil end
        if state == Enum.PlaybackState.Completed and onComplete then onComplete() end
    end)

    tween:Play()
    return tween
end

local function getFeet(character)
    local feet = {}
    local left = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
    local right = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
    if left then table.insert(feet, left) end
    if right then table.insert(feet, right) end
    return feet
end

local function createGlowPart(foot, options)
    local glow = Instance.new("Part")
    glow.Name = "FootGlow"
    glow.Material = Enum.Material.Neon
    glow.Color = options.Color or Color3.fromRGB(0, 255, 200)
    glow.Size = options.Size or Vector3.new(1.2, 0.2, 1.8)
    glow.Transparency = options.Transparency or 0.2
    glow.Anchored = true
    glow.CanCollide = false
    glow.CanQuery = false
    glow.CastShadow = false
    glow.CFrame = foot.CFrame * CFrame.new(0, -foot.Size.Y / 2, 0)
    glow.Parent = foot.Parent

    if options.Light then
        local light = Instance.new("PointLight")
        light.Color = glow.Color
        light.Range = 6
        light.Brightness = 2
        light.Parent = glow
    end
    return glow
end

local function startFootGlow(character, options)
    local feet = getFeet(character)
    if #feet == 0 then return {Stop = function() end} end

    local glowParts = {}
    for _, foot in ipairs(feet) do
        glowParts[foot] = createGlowPart(foot, options)
    end

    local hb = RunService.Heartbeat:Connect(function()
        for foot, glow in pairs(glowParts) do
            if foot.Parent and glow.Parent then
                glow.CFrame = foot.CFrame * CFrame.new(0, -foot.Size.Y / 2, 0)
            end
        end
    end)

    local stopped = false
    return {
        Stop = function()
            if stopped then return end
            stopped = true
            hb:Disconnect()
            for _, glow in pairs(glowParts) do
                if glow.Parent then glow:Destroy() end
            end
        end
    }
end

function TweenSystem.PlayWithFootGlow(character, props, time, style, direction, glowOptions, onComplete)
    if activeGlowSessions[character] then
        activeGlowSessions[character].Stop()
        activeGlowSessions[character] = nil
    end

    local glowSession = startFootGlow(character, glowOptions)
    activeGlowSessions[character] = glowSession
    local target = character:FindFirstChild("HumanoidRootPart") or character

    return TweenSystem.Play(target, props, time, style, direction, function()
        glowSession.Stop()
        if activeGlowSessions[character] == glowSession then activeGlowSessions[character] = nil end
        if onComplete then onComplete() end
    end)
end

-- ==========================================
-- [2. NOCLIP SYSTEM]
-- ==========================================
local function setNoclip(enable)
    if enable then
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") and p.CanCollide then
                            p.CanCollide = false
                        end
                    end
                end
            end)
        end
    else
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
    end
end

-- ==========================================
-- [3. CHEST FINDER & PRIORITY SYSTEM]
-- ==========================================
local function getPriorityChest()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local hrp = char.HumanoidRootPart
    local chests = {}

    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Chest") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                local priority = 1
                if obj.Name:find("3") or obj.Name:find("Diamond") or obj.Name:find("Ultra") then
                    priority = 3
                elseif obj.Name:find("2") or obj.Name:find("Gold") then
                    priority = 2
                end
                
                local dist = (hrp.Position - part.Position).Magnitude
                table.insert(chests, {Part = part, Dist = dist, Priority = priority})
            end
        end
    end

    if #chests == 0 then return nil end

    table.sort(chests, function(a, b)
        if a.Priority == b.Priority then return a.Dist < b.Dist end
        return a.Priority > b.Priority
    end)

    return chests[1].Part
end

-- ==========================================
-- [4. SERVER HOP SYSTEM]
-- ==========================================
local function bloxFruitsServerHop()
    Rayfield:Notify({Title = "Server Hop", Content = "ไม่พบหีบแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    
    if CommF then
        pcall(function() CommF:InvokeServer("TravelMain") end)
    end

    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local foundServer = nil
    local cursor = ""

    for page = 1, 5 do
        local url = "https://games.roblox.com/v1/places/" .. placeId .. "/servers/0?sortOrder=Desc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end

        local success, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and res and res.data then
            cursor = res.nextPageCursor or ""
            for _, s in ipairs(res.data) do
                if s.id ~= currentJobId and s.playing < s.maxPlayers - 1 and s.playing > 1 then
                    foundServer = s.id
                    break
                end
            end
        end

        if foundServer or cursor == "" then break end
    end

    if foundServer then
        TeleportService:TeleportToPlaceInstance(placeId, foundServer, LocalPlayer)
    else
        TeleportService:Teleport(placeId, LocalPlayer)
    end
end

-- ==========================================
-- [5. MAIN FLY & FARM LOGIC]
-- ==========================================
local function flyToAndCollect(chestPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not chestPart then return end

    local hrp = char.HumanoidRootPart
    local flyTime = (hrp.Position - chestPart.Position).Magnitude / CONFIG.FlySpeed
    local completed = false

    setNoclip(true)

    TweenSystem.PlayWithFootGlow(
        char,
        { CFrame = chestPart.CFrame * CFrame.new(0, 2, 0) },
        flyTime,
        "Linear",
        "Out",
        { Color = CONFIG.GlowColor, Size = Vector3.new(1.2, 0.2, 1.8), Light = true },
        function()
            setNoclip(false)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            if firetouchinterest then
                firetouchinterest(hrp, chestPart, 0)
                task.wait(CONFIG.CollectDelay)
                firetouchinterest(hrp, chestPart, 1)
            end
            completed = true
        end
    )

    repeat task.wait(0.05) until completed or not CONFIG.AutoFarm
end

local function startFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local chest = getPriorityChest()
            if chest and chest.Parent then
                flyToAndCollect(chest)
                task.wait(0.1)
            else
                setNoclip(false)
                if CONFIG.ServerHopWhenEmpty then
                    bloxFruitsServerHop()
                    break
                else
                    task.wait(3)
                end
            end
        end
        setNoclip(false)
    end)
end

-- ==========================================
-- [6. RAYFIELD UI SETUP]
-- ==========================================
local Window = Rayfield:CreateWindow({
   Name = "Blox Fruits - Chest Hub V3.0 Pro",
   LoadingTitle = "Loading Advanced Farm System...",
   LoadingSubtitle = "by Assistant",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest V3.0 (เปิด/ปิด ระบบฟาร์ม)",
   CurrentValue = false,
   Flag = "Toggle_BloxFruitsChest",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startFarmLoop()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty (ย้ายเซิร์ฟเมื่อหมด)",
   CurrentValue = true,
   Flag = "Toggle_ServerHop",
   Callback = function(Value)
       CONFIG.ServerHopWhenEmpty = Value
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed (ความเร็วบิน)",
   Range = {100, 350},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 280,
   Flag = "Slider_FlySpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})

-- Handle Error Rejoin
TeleportService.TeleportInitFailed:Connect(function()
    task.wait(1)
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end)
