-- Real Time Stancer for Assetto Corsa
-- CSP Lua App for real-time stance adjustment
-- Requires CSP 0.1.80+

local sim = ac.getSim()
local car = ac.getCar(0) or error("Car not found")
local ui = ac.getUI()

-- Version check
if not ac.getPatchVersionCode then
    ac.error("RealTimeStancer", "This app requires CSP 0.1.80 or higher")
    error("CSP version too old")
end

local cspVersion = ac.getPatchVersionCode()
if cspVersion < 2286 then -- CSP 0.1.80 = build 2286
    ac.error("RealTimeStancer", "This app requires CSP 0.1.80 or higher. Current: " .. tostring(cspVersion))
    error("CSP version too old")
end

-- App state
local appVisible = false
local windowSize = vec2(420, 600)
local windowPos = vec2(50, 50)

-- Stance parameters per wheel (FL, FR, RL, RR)
local stanceData = {
    wheelOffset = {0, 0, 0, 0},     -- mm offset (positive = outward)
    trackWidth = {0, 0, 0, 0},      -- mm track width adjustment
    camber = {0, 0, 0, 0},          -- degrees (negative = top inward)
    rideHeight = {0, 0, 0, 0},      -- mm height adjustment (negative = lower)
    globalMultiplier = 1.0
}

-- UI state
local selectedWheel = 0 -- 0=all, 1=FL, 2=FR, 3=RL, 4=RR
local presetName = ""
local presets = {}
local configFile = ac.getFolder(ac.FolderID.ACApps) .. "/lua/RealTimeStancer/config_presets.json"

local wheelNames = {"Front Left", "Front Right", "Rear Left", "Rear Right"}
local wheelShortNames = {"FL", "FR", "RL", "RR"}

-- Load presets from file
local function loadPresets()
    if io.fileExists(configFile) then
        local content = io.load(configFile)
        if content then
            local success, data = pcall(JSON.parse, content)
            if success and data then
                presets = data
                ac.log("RealTimeStancer: Loaded " .. #presets .. " presets")
            end
        end
    end
end

-- Save presets to file
local function savePresets()
    local json = JSON.stringify(presets, true)
    io.save(configFile, json)
    ac.log("RealTimeStancer: Saved " .. #presets .. " presets")
end

-- Save current stance as preset
local function savePreset(name)
    if name == "" then
        name = "Preset_" .. os.date("%Y%m%d_%H%M%S")
    end

    local preset = {
        name = name,
        data = table.clone(stanceData),
        timestamp = os.time()
    }

    table.insert(presets, preset)
    savePresets()
    ac.log("RealTimeStancer: Saved preset '" .. name .. "'")
end

-- Load preset by index
local function loadPreset(index)
    if presets[index] then
        stanceData = table.clone(presets[index].data)
        applyStance()
        ac.log("RealTimeStancer: Loaded preset '" .. presets[index].name .. "'")
    end
end

-- Delete preset
local function deletePreset(index)
    if presets[index] then
        local name = presets[index].name
        table.remove(presets, index)
        savePresets()
        ac.log("RealTimeStancer: Deleted preset '" .. name .. "'")
    end
end

-- Reset stance to defaults
local function resetStance()
    for i = 1, 4 do
        stanceData.wheelOffset[i] = 0
        stanceData.trackWidth[i] = 0
        stanceData.camber[i] = 0
        stanceData.rideHeight[i] = 0
    end
    stanceData.globalMultiplier = 1.0
    applyStance()
end

-- Apply stance modifications to car wheels
function applyStance()
    if not car then return end

    for i = 0, 3 do
        local wheelIndex = i + 1

        -- Get wheel transformation
        if car.wheels and car.wheels[i] then
            local wheel = car.wheels[i]

            -- Apply offset (lateral position)
            local offsetMM = stanceData.wheelOffset[wheelIndex] * stanceData.globalMultiplier
            local trackMM = stanceData.trackWidth[wheelIndex] * stanceData.globalMultiplier
            local totalOffset = (offsetMM + trackMM) / 1000 -- Convert to meters

            -- Apply camber (rotation around longitudinal axis)
            local camberRad = math.rad(stanceData.camber[wheelIndex] * stanceData.globalMultiplier)

            -- Apply ride height (vertical position)
            local heightMM = stanceData.rideHeight[wheelIndex] * stanceData.globalMultiplier
            local heightM = heightMM / 1000

            -- Use CSP physics APIs to modify wheel position
            -- Note: These are visual modifications primarily
            if ac.setWheelVisualOffset then
                -- Set lateral offset
                ac.setWheelVisualOffset(0, i, vec3(totalOffset, heightM, 0))
            end

            if ac.setWheelVisualCamber then
                -- Set camber angle
                ac.setWheelVisualCamber(0, i, camberRad)
            end
        end
    end
end

-- Initialize
loadPresets()

-- Main update loop
function script.update(dt)
    if not car then
        car = ac.getCar(0)
        return
    end

    -- Toggle app visibility with keyboard shortcut (Ctrl+Shift+S)
    if ui.keyboardButtonPressed(ui.KeyIndex.S) and
       ui.keyboardButtonDown(ui.KeyIndex.Control) and
       ui.keyboardButtonDown(ui.KeyIndex.Shift) then
        appVisible = not appVisible
    end
end

-- Draw slider with label and value display
local function drawStanceSlider(label, valueTable, wheelIdx, minVal, maxVal, format, step)
    ui.text(label .. ":")
    ui.sameLine(0, 10)
    ui.pushItemWidth(200)

    local changed, newValue = ui.slider("##" .. label .. wheelIdx, valueTable[wheelIdx], minVal, maxVal, format, step)
    ui.popItemWidth()

    if changed then
        valueTable[wheelIdx] = newValue
        applyStance()
    end

    ui.sameLine(0, 10)
    if ui.button("Reset##" .. label .. wheelIdx, vec2(50, 0)) then
        valueTable[wheelIdx] = 0
        applyStance()
    end
end

-- Draw main UI window
function script.windowMain(dt)
    if not appVisible then return end

    ui.beginWindow("RealTimeStancer", windowPos, windowSize, true)

    -- Header
    ui.text("Real Time Stance Adjuster")
    ui.separator()
    ui.newLine(5)

    -- Wheel selector
    ui.text("Adjust:")
    ui.sameLine(0, 10)

    local wheelOptions = {"All Wheels", "Front Left", "Front Right", "Rear Left", "Rear Right"}
    ui.pushItemWidth(150)
    local changedWheel, newWheel = ui.combo("##wheelSelect", selectedWheel, wheelOptions)
    ui.popItemWidth()
    if changedWheel then
        selectedWheel = newWheel
    end

    ui.newLine(10)
    ui.separator()
    ui.newLine(5)

    -- Determine which wheels to show controls for
    local wheelIndices = {}
    if selectedWheel == 0 then
        wheelIndices = {1, 2, 3, 4}
    else
        wheelIndices = {selectedWheel}
    end

    -- Draw controls for selected wheel(s)
    for _, idx in ipairs(wheelIndices) do
        if selectedWheel ~= 0 then
            ui.text(wheelNames[idx] .. " (" .. wheelShortNames[idx] .. ")")
            ui.newLine(5)
        end

        -- Wheel Offset
        drawStanceSlider("Offset", stanceData.wheelOffset, idx, -100, 100, "%.0f mm", 1)

        -- Track Width
        drawStanceSlider("Track Width", stanceData.trackWidth, idx, -50, 50, "%.0f mm", 1)

        -- Camber
        drawStanceSlider("Camber", stanceData.camber, idx, -10, 10, "%.1f°", 0.1)

        -- Ride Height
        drawStanceSlider("Ride Height", stanceData.rideHeight, idx, -100, 50, "%.0f mm", 1)

        if selectedWheel == 0 and idx < 4 then
            ui.newLine(10)
        end
    end

    ui.newLine(10)
    ui.separator()
    ui.newLine(5)

    -- Global multiplier
    ui.text("Global Multiplier:")
    ui.sameLine(0, 10)
    ui.pushItemWidth(200)
    local changedMult, newMult = ui.slider("##globalMult", stanceData.globalMultiplier, 0, 2, "%.2fx", 0.01)
    ui.popItemWidth()
    if changedMult then
        stanceData.globalMultiplier = newMult
        applyStance()
    end

    ui.newLine(10)
    ui.separator()
    ui.newLine(5)

    -- Preset management
    ui.text("Presets:")
    ui.newLine(5)

    -- Save preset
    ui.pushItemWidth(200)
    presetName = ui.inputText("Preset Name", presetName, ui.InputTextFlags.None)
    ui.popItemWidth()
    ui.sameLine(0, 10)
    if ui.button("Save Preset", vec2(100, 0)) then
        savePreset(presetName)
        presetName = ""
    end

    ui.newLine(5)

    -- List presets
    if #presets > 0 then
        ui.childWindow("presetList", vec2(400, 150), function()
            for i, preset in ipairs(presets) do
                ui.text(i .. ". " .. preset.name)
                ui.sameLine(0, 10)
                if ui.button("Load##" .. i, vec2(50, 0)) then
                    loadPreset(i)
                end
                ui.sameLine(0, 5)
                if ui.button("Delete##" .. i, vec2(50, 0)) then
                    deletePreset(i)
                end
            end
        end)
    else
        ui.textDisabled("No presets saved")
    end

    ui.newLine(10)
    ui.separator()
    ui.newLine(5)

    -- Action buttons
    if ui.button("Reset All", vec2(100, 0)) then
        resetStance()
    end
    ui.sameLine(0, 10)
    if ui.button("Apply", vec2(100, 0)) then
        applyStance()
    end
    ui.sameLine(0, 10)
    if ui.button("Close", vec2(100, 0)) then
        appVisible = false
    end

    ui.endWindow()
end

-- Show/hide app
function script.windowSettings()
    appVisible = not appVisible
end

ac.log("RealTimeStancer v1.0 loaded successfully")
ac.log("Press Ctrl+Shift+S to open/close the app")
