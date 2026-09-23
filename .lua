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
    FlySpeed = 180, -- ปรับระดับความเร็วให้อยู่ในช่วง Ultra Smooth เนียนตา
    ServerHopWhenEmpty = true
}

local noclipConn = nil

-- 1. ระบบ Noclip ไร้แรงปะทะ
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

-- 2. ค้นหากล่องที่ใกล้ที่สุด
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

-- 3. ระบบบิน Ultra Smooth ด้วย BodyMovement + Safety Timeout
local function flyUltraSmooth(targetPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not targetPart or not targetPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    setNoclip(true)

    -- สร้าง ตัวควบคุมแรงบิน (BodyVelocity & BodyGyro)
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.P = 10000 -- เพิ่มความนุ่มนวลในการหมุนหน้าไปหากล่อง
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    local startTime = tick()
    local dist = (hrp.Position - targetPart.Position).Magnitude
    local maxAllowedTime = (dist / CONFIG.FlySpeed) + 2.5 -- กำหนดเวลาบินสูงสุด ป้องกันการติดค้าง

    while CONFIG.AutoFarm and targetPart and targetPart.Parent do
        local currentPos = hrp.Position
        local targetPos = targetPart.Position + Vector3.new(0, 1.5, 0)
        local distance = (targetPos - currentPos).Magnitude

        -- ถึงเป้าหมาย (ระยะห่างน้อยกว่า 4 หน่วย) หรือ บินนานเกินเวลา
        if distance <= 4 or (tick() - startTime) > maxAllowedTime then
            break
        end

        -- เคลื่อนที่แบบ Smooth Vector
        local direction = (targetPos - currentPos).Unit
        bv.Velocity = direction * CONFIG.FlySpeed
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)

        task.wait(0.02)
    end

    -- ลบตัวควบคุมการบินออกเมื่อถึงจุด
    bv:Destroy()
    bg:Destroy()
    
    -- ล็อคตำแหน่งหยุดและกดเก็บ
    if CONFIG.AutoFarm and targetPart and targetPart.Parent then
        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 1.5, 0)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        if firetouchinterest then
            firetouchinterest(hrp, targetPart, 0)
            task.wait(0.12)
            firetouchinterest(hrp, targetPart, 1)
        end
    end
    
    setNoclip(false)
end

-- 4. ระบบ Server Hop
local function serverHop()
    Rayfield:Notify({Title = "Server Hop", Content = "ไม่พบหีบแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    
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

-- 5. ลูปหลักค้นหาและบินเก็บ
local function startSmoothFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local nearestChest = getClosestChest()
            
            if nearestChest and nearestChest.Parent then
                flyUltraSmooth(nearestChest)
                task.wait(0.1) -- พักจังหวะเล็กน้อยก่อนเริ่มหากล่องถัดไป
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
   Name = "Ultra Smooth Chest Farm",
   LoadingTitle = "Loading Smooth System...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest (Ultra Smooth)",
   CurrentValue = false,
   Flag = "Toggle_SmoothChest",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startSmoothFarmLoop()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty",
   CurrentValue = true,
   Flag = "Toggle_SmoothHop",
   Callback = function(Value)
       CONFIG.ServerHopWhenEmpty = Value
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed (แนะนำ 150 - 220)",
   Range = {80, 350},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 180,
   Flag = "Slider_SmoothSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
