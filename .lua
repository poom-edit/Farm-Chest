-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 150, -- ล็อคความเร็ว 150 นุ่มนวลกำลังดี
    ServerHopWhenEmpty = true
}

local noclipConn = nil
local currentTween = nil

-- 1. ระบบ Noclip ป้องกันการติดก้อนหินระหว่าง Tween
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

-- 2. Step 1: สแกนหากล่องที่ใกล้ที่สุด
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

-- 3. Step 2: Tween ตรงไปที่ CFrame ของกล่อง
local function tweenToChest(chestPart)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") or not chestPart or not chestPart.Parent then return end
    
    local hrp = char.HumanoidRootPart
    setNoclip(true)

    -- คำนวณระยะทางและเวลาในการ Tween (ใช้ Speed 150)
    local targetCFrame = chestPart.CFrame
    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local tweenTime = distance / CONFIG.FlySpeed

    -- ตั้งค่า TweenInfo (Linear = ความเร็วคงที่นุ่มนวล)
    local tweenInfo = TweenInfo.new(
        tweenTime,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
    )

    -- สร้างและสั่งเล่น Tween ไปที่ CFrame ของกล่องตรงๆ
    currentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    -- ตัวแปรเช็คว่า Tween จบหรือยัง
    local completed = false
    local conn
    conn = currentTween.Completed:Connect(function()
        completed = true
        if conn then conn:Disconnect() end
    end)

    -- รอจนกว่า Tween จะเล่นจบ หรือผู้ใช้ปิด AutoFarm
    local startTime = tick()
    repeat 
        task.wait(0.05)
        -- Safety Breakout: เผื่อเกิดการค้าง ให้หลุดออกมาถ้าเวลาเกิน
    until completed or not CONFIG.AutoFarm or (tick() - startTime) > (tweenTime + 1.5) or not chestPart.Parent

    -- ยกเลิก Tween เผื่อปิดกลางทาง
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    -- Trigger แตะกล่องเพื่อรับเงิน
    if CONFIG.AutoFarm and chestPart and chestPart.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
        if firetouchinterest then
            firetouchinterest(hrp, chestPart, 0)
            task.wait(0.05)
            firetouchinterest(hrp, chestPart, 1)
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

-- 5. Step 3: ลูปทำงาน (สแกนใกล้สุด -> Tween ไป CFrame -> สแกนหาใหม่ทันที)
local function startTweenFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            local nearestChest = getClosestChest()
            
            if nearestChest and nearestChest.Parent then
                tweenToChest(nearestChest)
                task.wait(0.02) -- พักจังหวะแป๊บเดียว แล้ววนลูปสแกนหากล่องใกล้สุดตัวต่อไปทันที
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
        
        if currentTween then
            currentTween:Cancel()
        end
        setNoclip(false)
    end)
end

-- 6. Rayfield UI Setup
local Window = Rayfield:CreateWindow({
   Name = "Direct CFrame Tween Farm",
   LoadingTitle = "Loading Direct Tween...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm Chest (Direct Tween CFrame)",
   CurrentValue = false,
   Flag = "Toggle_DirectTween",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startTweenFarmLoop()
       elseif currentTween then
           currentTween:Cancel()
       end
   end,
})

FarmTab:CreateToggle({
   Name = "Server Hop When Empty",
   CurrentValue = true,
   Flag = "Toggle_DirectHop",
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
   Flag = "Slider_DirectSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
