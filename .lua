-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 300,
    ServerHopWhenEmpty = true,
    CollectDelay = 0.1
}

local noclipConn = nil
local CommF = ReplicatedStorage:WaitForChild("Remotes", 5) and ReplicatedStorage.Remotes:WaitForChild("CommF_", 5)

-- 1. ระบบ Noclip ป้องกันติดก้อนหิน/กำแพง
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

-- 2. ค้นหาหีบโดยเช็คความถูกต้องของ Object
local function getPriorityChest()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local hrp = char.HumanoidRootPart
    local chests = {}

    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:find("Chest") then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part and part.Parent and part:IsDescendantOf(Workspace) then
                local priority = 1
                if obj.Name:find("3") or obj.Name:find("Diamond") then
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

-- 3. ระบบเคลื่อนที่แบบรวดเร็วและไม่ค้างลูป (Direct CFrame Step)
local function moveToChest(chestPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not chestPart or not chestPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    setNoclip(true)

    -- คำนวณระยะทางและกรอบเวลาการบิน
    local targetCFrame = chestPart.CFrame * CFrame.new(0, 2, 0)
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    local steps = math.clamp(math.floor(dist / (CONFIG.FlySpeed / 30)), 1, 300)
    
    for i = 1, steps do
        if not CONFIG.AutoFarm or not chestPart or not chestPart.Parent then break end
        
        -- ค่อยๆ เคลื่อน CFrame ไปยังจุดหมายทีละ Step โดยไม่พึ่ง Tween
        hrp.CFrame = hrp.CFrame:Lerp(targetCFrame, i / steps)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.01)
    end

    -- วาร์ปเข้าจุดทันทีเมื่อถึงขั้นตอนสุดท้าย
    if CONFIG.AutoFarm and chestPart and chestPart.Parent then
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        
        -- Trigger เก็บหีบ
        if firetouchinterest then
            firetouchinterest(hrp, chestPart, 0)
            task.wait(CONFIG.CollectDelay)
            firetouchinterest(hrp, chestPart, 1)
        end
    end
    
    setNoclip(false)
end

-- 4. ระบบ Server Hop
local function bloxFruitsServerHop()
    Rayfield:Notify({Title = "Server Hop", Content = "หีบหมดแล้ว กำลังเปลี่ยนเซิร์ฟเวอร์...", Duration = 3})
    if CommF then pcall(function() CommF:InvokeServer("TravelMain") end) end

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

-- 5. Main Loop
local function startFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local chest = getPriorityChest()
            if chest and chest.Parent then
                moveToChest(chest)
                task.wait(0.05)
            else
                setNoclip(false)
                if CONFIG.ServerHopWhenEmpty then
                    bloxFruitsServerHop()
                    break
                else
                    task.wait(2)
                end
            end
        end
        setNoclip(false)
    end)
end

-- 6. Rayfield UI
local Window = Rayfield:CreateWindow({
   Name = "Blox Fruits - Fixed Chest Farm",
   LoadingTitle = "Loading Stable System...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest (เปิด/ปิด)",
   CurrentValue = false,
   Flag = "Toggle_FixChest",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startFarmLoop()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty",
   CurrentValue = true,
   Flag = "Toggle_FixHop",
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
   Flag = "Slider_FixSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
