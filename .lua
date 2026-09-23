-- โหลด Rayfield UI Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    FlySpeed = 150
}

local noclipConn = nil
local currentTween = nil

-- 1. Noclip กันติดบล็อก
local function setNoclip(enable)
    if enable then
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
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

-- 2. สแกนหา CFrame ของกล่อง "ทั้งหมด" ในแมพ (Chest1, Chest2, Chest3)
local function getAllChestData()
    local chestList = {}

    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name == "Chest1" or obj.Name == "Chest2" or obj.Name == "Chest3" or obj.Name:find("Chest")) then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part and part.Parent and part:IsDescendantOf(Workspace) then
                table.insert(chestList, {
                    Model = obj,
                    Part = part,
                    CFrame = part.CFrame
                })
            end
        end
    end

    return chestList
end

-- 3. ระบบ Tween บินไปที่ CFrame แล้วเช็กว่ากล่องหายไปหรือยัง
local function flyToChestCFrame(chestData)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart

    local targetCFrame = chestData.CFrame
    local targetPart = chestData.Part
    local targetModel = chestData.Model

    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    local time = distance / CONFIG.FlySpeed

    setNoclip(true)

    -- สั่ง Tween บินไปที่ CFrame ของกล่องตรงๆ
    local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    currentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    -- วนลูปเช็กระหว่างบิน: ถ้ากล่องโดนเก็บจนหายไปแล้ว (Parent == nil) ให้ยกเลิก Tween ทันที ไม่ต้องบินต่อให้เสียเวลา
    local startTime = tick()
    while CONFIG.AutoFarm do
        task.wait(0.05)
        
        -- เช็กว่ากล่องหายไปจากแมพแล้วหรือยัง (Parent กลายเป็น nil)
        local isChestGone = not targetModel.Parent or not targetPart.Parent or not targetPart:IsDescendantOf(Workspace)
        
        -- ถ้าบินถึงแล้ว หรือ กล่องหายไปแล้ว หรือ เวลาบินเกินกำหนด
        if isChestGone or (tick() - startTime) >= (time + 0.5) then
            break
        end
    end

    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    -- ส่งคำสั่งสัมผัส (Touch) เผื่อกล่องยังไม่หาย
    if targetPart and targetPart.Parent and firetouchinterest then
        firetouchinterest(hrp, targetPart, 0)
        task.wait(0.05)
        firetouchinterest(hrp, targetPart, 1)
    end

    setNoclip(false)
end

-- 4. ลูปหลัก: สแกนหา CFrame ทั้งหมด -> บินไล่เก็บทีละอันจนหมด -> สแกนใหม่
local function startListFarmLoop()
    task.spawn(function()
        while CONFIG.AutoFarm do
            -- Step 1: ดึงรายการ CFrame ของกล่องทั้งหมดในแมพมาเก็บไว้ในรายการ
            local chestList = getAllChestData()

            if #chestList > 0 then
                -- Step 2: วนลูปบินไปทีละ CFrame ตามรายการที่สแกนได้
                for index, chestData in ipairs(chestList) do
                    if not CONFIG.AutoFarm then break end
                    
                    -- เช็กอีกรอบก่อนบินว่ากล่องใน CFrame นี้ยังอยู่ไหม
                    if chestData.Part and chestData.Part.Parent then
                        flyToChestCFrame(chestData)
                        task.wait(0.05) -- พัก 0.05 วินาที แล้วไป CFrame ถัดไปทันที
                    end
                end
            else
                -- ถ้าสแกนแล้วไม่พบกล่องเลย ให้รอ 3 วินาทีแล้วสแกนใหม่
                task.wait(3)
            end
        end
    end)
end

-- 5. Rayfield UI Setup
local Window = Rayfield:CreateWindow({
   Name = "CFrame List Scan Farm",
   LoadingTitle = "Scanning All Chest CFrames...",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local FarmTab = Window:CreateTab("Auto Farm", 4483362458)

FarmTab:CreateToggle({
   Name = "Auto Farm All CFrames (สแกน CFrame ทั้งหมดแล้วบินไล่เก็บ)",
   CurrentValue = false,
   Flag = "Toggle_ListFarm",
   Callback = function(Value)
       CONFIG.AutoFarm = Value
       if Value then
           startListFarmLoop()
       elseif currentTween then
           currentTween:Cancel()
       end
   end,
})

FarmTab:CreateSlider({
   Name = "Fly Speed",
   Range = {50, 300},
   Increment = 10,
   Suffix = " Speed",
   CurrentValue = 150,
   Flag = "Slider_ListSpeed",
   Callback = function(Value)
       CONFIG.FlySpeed = Value
   end,
})
