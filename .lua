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
    FlySpeed = 150,
    ServerHopWhenEmpty = true
}

local noclipConn = nil

-- 1. ปิด Collision ตัวละครเต็มรูปแบบ (กัน Anti-Cheat ดึงกลับ)
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

-- 2. ระบบสแกนหากล่องใกล้ที่สุด (สแกนแบบตรงจุดจาก Workspace)
local function getClosestChest()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    
    local hrp = char.HumanoidRootPart
    local closestChest = nil
    local shortestDistance = math.huge

    -- สแกนหากล่องใน Workspace
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name:find("Chest") or obj.Name:find("Chest1") or obj.Name:find("Chest2") or obj.Name:find("Chest3")) then
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

-- 3. เคลื่อนที่ไปหากล่องแบบ Smooth CFrame (แก้ปัญหากระเด้งกลับ 100%)
local function moveToChestNoBounce(chestPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not chestPart or not chestPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")
    
    setNoclip(true)

    -- สั่ง Humanoid อยู่ในภาวะลอยตัว ป้องกันแรงโน้มถ่วงและ Anti-Cheat ดึงกลับ
    if humanoid then
        humanoid.PlatformStand = true
    end

    local targetCFrame = chestPart.CFrame * CFrame.new(0, 1.8, 0)
    local startPos = hrp.Position
    local dist = (startPos - targetCFrame.Position).Magnitude
    local stepCount = math.max(1, math.floor(dist / (CONFIG.FlySpeed * 0.016)))

    -- ลูปเคลื่อนที่ผ่าน Heartbeat (เนียนกว่า Tween และไม่เด้งกลับ)
    for i = 1, stepCount do
        if not CONFIG.AutoFarm or not chestPart or not chestPart.Parent then break end
        
        local alpha = i / stepCount
        local nextPos = startPos:Lerp(targetCFrame.Position, alpha)
        
        -- ล็อกพิกัดและล้าง Velocity แรงดึง
        hrp.CFrame = CFrame.new(nextPos, targetCFrame.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        
        RunService.Heartbeat:Wait()
    end

    -- เมื่อถึงกล่อง แตะรับเงิน
    if CONFIG.AutoFarm and chestPart and chestPart.Parent then
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        
        if firetouchinterest then
            firetouchinterest(hrp, chestPart, 0)
            task.wait(0.1)
            firetouchinterest(hrp, chestPart, 1)
        end
    end

    -- คืนค่า Humanoid
    if humanoid then
        humanoid.PlatformStand = false
    end
    setNoclip(false)
end

-- 4. ระบบ Server Hop
local function serverHop()
    Rayfield:Notify({Title = "Server Hop", Content = "ไม่พบกล่องแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    
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

-- 5. ลูปการทำงานหลัก (สแกน -> เคลื่อนที่ -> สแกนใหม่ทันที)
local function startMainFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local nearestChest = getClosestChest()
            
            if nearestChest and nearestChest.Parent then
                moveToChestNoBounce(nearestChest)
                task.wait(0.05) -- พักนิดเดียวแล้ววนหาตัวถัดไปทันที
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
   Name = "Anti-Bounce Chest Hub",
   LoadingTitle = "Loading Heartbeat Movement...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest (Fixed Bounce)",
   CurrentValue = false,
   Flag = "Toggle_FixAll",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startMainFarmLoop()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty",
   CurrentValue = true,
   Flag = "Toggle_HopAll",
   Callback = function(Value)
       CONFIG.ServerHopWhenEmpty = Value
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed",
   Range = {50, 300},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 150,
   Flag = "Slider_SpeedAll",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
