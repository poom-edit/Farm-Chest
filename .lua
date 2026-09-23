-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 300,
    ServerHopWhenEmpty = true
}

local noclipConn = nil

-- 1. ระบบ Noclip ปิดการชน
local function setNoclip(enable)
    if enable then
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then
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

-- 2. ฟังก์ชั่นหาหีบที่ "อยู่ใกล้ที่สุด" ในขณะนั้น
local function getClosestChest()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    
    local hrp = char.HumanoidRootPart
    local closestChest = nil
    local shortestDistance = math.huge

    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Chest") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part and part.Parent and part:IsDescendantOf(Workspace) then
                local dist = (hrp.Position - part.Position).Magnitude
                if dist < shortestDistance then
                    shortestDistance = dist
                    closestChest = part
                end
            end
        end
    end

    return closestChest
end

-- 3. บินไปเก็บหีบเป้าหมาย
local function flyToTarget(targetPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not targetPart or not targetPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    setNoclip(true)

    -- คำนวณระยะทางและบินเคลื่อนที่ไปทีละก้าว
    while CONFIG.AutoFarm and targetPart and targetPart.Parent do
        local currentPos = hrp.Position
        local targetPos = targetPart.Position + Vector3.new(0, 2, 0)
        local distance = (targetPos - currentPos).Magnitude

        -- ถ้าเข้าใกล้หีบระยะ 3 หน่วย ถือว่าถึงจุดหมายแล้ว
        if distance <= 3 then
            break
        end

        -- คำนวณ Direction และบินไปข้างหน้าตาม FlySpeed
        local direction = (targetPos - currentPos).Unit
        local moveStep = math.min(distance, CONFIG.FlySpeed * 0.03)
        
        hrp.CFrame = CFrame.new(currentPos + (direction * moveStep), targetPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.01)
    end

    -- Trigger แตะหีบเมื่อถึงจุดหมาย
    if CONFIG.AutoFarm and targetPart and targetPart.Parent then
        hrp.CFrame = targetPart.CFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        
        if firetouchinterest then
            firetouchinterest(hrp, targetPart, 0)
            task.wait(0.1)
            firetouchinterest(hrp, targetPart, 1)
        end
    end
    
    setNoclip(false)
end

-- 4. ระบบ Server Hop เมื่อไม่เจอหีบเหลือแล้ว
local function serverHop()
    Rayfield:Notify({Title = "Server Hop", Content = "ไม่พบหีบในระยะแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    
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

-- 5. ลูปการทำงานหลัก (หาใกล้สุด -> บินไปเก็บ -> วนใหม่)
local function startNearestFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local nearestChest = getClosestChest()
            
            if nearestChest and nearestChest.Parent then
                flyToTarget(nearestChest)
                task.wait(0.05) -- พักนิดนึงก่อนเช็คหาหีบถัดไป
            else
                setNoclip(false)
                if CONFIG.ServerHopWhenEmpty then
                    serverHop()
                    break
                else
                    task.wait(2)
                end
            end
        end
        setNoclip(false)
    end)
end

-- 6. Rayfield UI Setup
local Window = Rayfield:CreateWindow({
   Name = "Nearest Chest Farm",
   LoadingTitle = "Loading Simple System...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Nearest Chest (เก็บหีบใกล้ที่สุด)",
   CurrentValue = false,
   Flag = "Toggle_NearestChest",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startNearestFarmLoop()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty (ย้ายเซิร์ฟเมื่อกล่องหมด)",
   CurrentValue = true,
   Flag = "Toggle_HopNearest",
   Callback = function(Value)
       CONFIG.ServerHopWhenEmpty = Value
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed",
   Range = {100, 500},
   Increment = 20,
   Suffix = " Speed",
   CurrentValue = 300,
   Flag = "Slider_NearestSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
