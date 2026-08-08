local config = require 'config.client'
if not config.enableClient then return end

local VEHICLES = exports.qbx_core:GetVehiclesByName()

local VehicleCategory = {
    all = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22},
    car = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 17, 18, 19, 20, 22},
    air = {15, 16},
    sea = {14},
}

local uiOpen = false
local activeGarage
local activeVehicles = {}
local spawnLock = false

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

---@param category VehicleType
---@param vehicle number
---@return boolean
local function isOfType(category, vehicle)
    local classSet = {}

    for _, class in pairs(VehicleCategory[category]) do
        classSet[class] = true
    end

    return classSet[GetVehicleClass(vehicle)] == true
end

---@param vehicle number
local function kickOutPeds(vehicle)
    for i = -1, 5 do
        local seat = GetPedInVehicleSeat(vehicle, i)
        if seat and seat ~= 0 then
            TaskLeaveVehicle(seat, vehicle, 0)
        end
    end
end

local function closeGarageUi()
    uiOpen = false
    activeGarage = nil
    activeVehicles = {}
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

---@param vehicleId number
---@param garageName string
---@param accessPoint integer
local function takeOutOfGarage(vehicleId, garageName, accessPoint)
    if spawnLock then
        exports.qbx_core:Notify(locale('error.spawn_in_progress'), 'error')
        return
    end

    spawnLock = true

    local success, result = pcall(function()
        if cache.vehicle then
            exports.qbx_core:Notify(locale('error.in_vehicle'), 'error')
            return
        end

        local netId = lib.callback.await('qbx_garages:server:spawnVehicle', false, vehicleId, garageName, accessPoint)
        if not netId then return end

        local veh = lib.waitFor(function()
            if NetworkDoesEntityExistWithNetworkId(netId) then
                return NetToVeh(netId)
            end
        end)

        if not veh or veh == 0 then
            exports.qbx_core:Notify(locale('error.spawn_failed'), 'error')
            return
        end

        if config.engineOn then
            SetVehicleEngineOn(veh, true, true, false)
        end
    end)

    spawnLock = false
    assert(success, result)
end

---@param state VehicleState
---@param isDepot boolean
---@return string, string
local function getVehicleStatus(state, isDepot)
    if state == VehicleState.GARAGED then
        return 'Ready', 'ready'
    elseif state == VehicleState.OUT and isDepot then
        return 'Ready for release', 'release'
    elseif state == VehicleState.OUT then
        return 'Currently out', 'out'
    elseif state == VehicleState.IMPOUNDED then
        return 'Authority hold', 'impounded'
    end

    return 'Unavailable', 'unavailable'
end

---@param vehicle PlayerVehicle
---@param garageInfo GarageConfig
---@return table
local function serializeVehicle(vehicle, garageInfo)
    local details = VEHICLES[vehicle.modelName] or {}
    local brand = details.brand or 'Custom'
    local name = details.name or vehicle.modelName or 'Unknown Vehicle'
    local label = ('%s %s'):format(brand, name)
    local isDepot = garageInfo.type == GarageType.DEPOT
    local statusLabel, statusKey = getVehicleStatus(vehicle.state, isDepot)
    local engine = qbx.math.round(clamp(vehicle.props and vehicle.props.engineHealth or 1000, 0, 1000) / 10)
    local body = qbx.math.round(clamp(vehicle.props and vehicle.props.bodyHealth or 1000, 0, 1000) / 10)
    local fuel = qbx.math.round(clamp(vehicle.props and vehicle.props.fuelLevel or 0, 0, 100))
    local canRetrieve = vehicle.state == VehicleState.GARAGED or (isDepot and vehicle.state == VehicleState.OUT)

    return {
        id = vehicle.id,
        modelName = vehicle.modelName,
        brand = brand,
        name = name,
        label = label,
        plate = vehicle.props and vehicle.props.plate or 'UNKNOWN',
        category = details.category or garageInfo.vehicleType or 'car',
        state = vehicle.state,
        status = statusLabel,
        statusKey = statusKey,
        engine = engine,
        body = body,
        fuel = fuel,
        depotPrice = vehicle.depotPrice or 0,
        canRetrieve = canRetrieve,
        actionLabel = isDepot and 'Release Vehicle' or 'Take Vehicle Out',
    }
end

---@param garageName string
---@param garageInfo GarageConfig
---@param accessPoint integer
local function openGarageMenu(garageName, garageInfo, accessPoint)
    ---@type PlayerVehicle[]?
    local vehicleEntities = lib.callback.await('qbx_garages:server:getGarageVehicles', false, garageName)

    if not vehicleEntities then
        exports.qbx_core:Notify(locale('error.no_vehicles'), 'error')
        return
    end

    table.sort(vehicleEntities, function(a, b)
        return (a.modelName or '') < (b.modelName or '')
    end)

    local vehicles = {}
    for i = 1, #vehicleEntities do
        vehicles[#vehicles + 1] = serializeVehicle(vehicleEntities[i], garageInfo)
    end

    activeGarage = {
        name = garageName,
        label = garageInfo.label,
        type = garageInfo.type == GarageType.DEPOT and 'impound' or 'garage',
        vehicleType = garageInfo.vehicleType,
        accessPoint = accessPoint,
    }
    activeVehicles = vehicles
    uiOpen = true

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        brand = config.tablet.brand,
        tagline = config.tablet.tagline,
        garage = activeGarage,
        vehicles = vehicles,
    })
end

RegisterNUICallback('ready', function(_, cb)
    if not uiOpen then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'close' })
    end

    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeGarageUi()
    cb({ ok = true })
end)

RegisterNUICallback('retrieveVehicle', function(data, cb)
    if not uiOpen or not activeGarage then
        cb({ ok = false, error = 'garage_closed' })
        return
    end

    local vehicleId = tonumber(data.id)
    local selectedVehicle

    for i = 1, #activeVehicles do
        if activeVehicles[i].id == vehicleId then
            selectedVehicle = activeVehicles[i]
            break
        end
    end

    if not selectedVehicle or not selectedVehicle.canRetrieve then
        cb({ ok = false, error = 'vehicle_unavailable' })
        return
    end

    local garageName = activeGarage.name
    local accessPoint = activeGarage.accessPoint
    closeGarageUi()
    cb({ ok = true })

    CreateThread(function()
        takeOutOfGarage(vehicleId, garageName, accessPoint)
    end)
end)

---@param vehicle number
---@param garageName string
local function parkVehicle(vehicle, garageName)
    if GetVehicleNumberOfPassengers(vehicle) ~= 1 then
        local isParkable = lib.callback.await('qbx_garages:server:isParkable', false, garageName, NetworkGetNetworkIdFromEntity(vehicle))

        if not isParkable then
            exports.qbx_core:Notify(locale('error.not_owned'), 'error', 5000)
            return
        end

        kickOutPeds(vehicle)
        SetVehicleDoorsLocked(vehicle, 2)
        Wait(1500)
        lib.callback.await('qbx_garages:server:parkVehicle', false, NetworkGetNetworkIdFromEntity(vehicle), lib.getVehicleProperties(vehicle), garageName)
        exports.qbx_core:Notify(locale('success.vehicle_parked'), 'primary', 4500)
    else
        exports.qbx_core:Notify(locale('error.vehicle_occupied'), 'error', 3500)
    end
end

---@param garage GarageConfig
---@return boolean
local function checkCanAccess(garage)
    if garage.groups and not exports.qbx_core:HasPrimaryGroup(garage.groups, QBX.PlayerData) then
        exports.qbx_core:Notify(locale('error.no_access'), 'error')
        return false
    end

    if cache.vehicle and not isOfType(garage.vehicleType, cache.vehicle) then
        exports.qbx_core:Notify(locale('error.not_correct_type'), 'error')
        return false
    end

    return true
end

---@param garageName string
---@param garage GarageConfig
---@param accessPoint AccessPoint
---@param accessPointIndex integer
local function createZones(garageName, garage, accessPoint, accessPointIndex)
    CreateThread(function()
        accessPoint.dropPoint = accessPoint.dropPoint or accessPoint.spawn
        local drawRadius = accessPoint.drawRadius or 60
        local dropDrawRadius = accessPoint.dropDrawRadius or 60
        local useRadius = accessPoint.useRadius or 1
        local dropUseRadius = accessPoint.dropUseRadius or 1.5
        local dropZone, coordsZone

        local function createDropZone()
            if dropZone then return end

            dropZone = lib.zones.sphere({
                coords = accessPoint.dropPoint,
                radius = dropUseRadius,
                onEnter = function()
                    if not cache.vehicle then return end
                    lib.showTextUI(locale('info.park_e'))
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if not cache.vehicle then return end
                    if IsControlJustReleased(0, 38) then
                        if not checkCanAccess(garage) then return end
                        parkVehicle(cache.vehicle, garageName)
                    end
                end,
                debug = config.debugPoly
            })
        end

        local function createCoordsZone()
            if coordsZone then return end

            coordsZone = lib.zones.sphere({
                coords = accessPoint.coords,
                radius = useRadius,
                onEnter = function()
                    if accessPoint.dropPoint and cache.vehicle then return end
                    lib.showTextUI((garage.type == GarageType.DEPOT and locale('info.impound_e')) or (cache.vehicle and locale('info.park_e')) or locale('info.car_e'))
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if accessPoint.dropPoint and cache.vehicle then return end
                    if IsControlJustReleased(0, 38) then
                        if not checkCanAccess(garage) then return end
                        if cache.vehicle and garage.type ~= GarageType.DEPOT then
                            parkVehicle(cache.vehicle, garageName)
                        else
                            openGarageMenu(garageName, garage, accessPointIndex)
                        end
                    end
                end,
                debug = config.debugPoly
            })
        end

        lib.zones.sphere({
            coords = accessPoint.coords,
            radius = drawRadius,
            onEnter = createCoordsZone,
            onExit = function()
                if coordsZone then
                    coordsZone:remove()
                    coordsZone = nil
                end
            end,
            inside = function()
                config.drawGarageMarker(accessPoint.coords.xyz, useRadius)
            end,
            debug = config.debugPoly,
        })

        if accessPoint.dropPoint and garage.type ~= GarageType.DEPOT then
            lib.zones.sphere({
                coords = accessPoint.dropPoint,
                radius = dropDrawRadius,
                onEnter = createDropZone,
                onExit = function()
                    if dropZone then
                        dropZone:remove()
                        dropZone = nil
                    end
                end,
                inside = function()
                    config.drawDropOffMarker(accessPoint.dropPoint, dropUseRadius)
                end,
                debug = config.debugPoly,
            })
        end
    end)
end

---@param garageInfo GarageConfig
---@param accessPoint AccessPoint
local function createBlips(garageInfo, accessPoint)
    local blip = AddBlipForCoord(accessPoint.coords.x, accessPoint.coords.y, accessPoint.coords.z)
    SetBlipSprite(blip, accessPoint.blip.sprite or 357)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.60)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, accessPoint.blip.color or config.defaultBlipColor or 8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(accessPoint.blip.name or garageInfo.label)
    EndTextCommandSetBlipName(blip)
end

local function createGarage(name, garage)
    local accessPoints = garage.accessPoints
    for i = 1, #accessPoints do
        local accessPoint = accessPoints[i]

        if accessPoint.blip then
            createBlips(garage, accessPoint)
        end

        createZones(name, garage, accessPoint, i)
    end
end

local function createGarages()
    local garages = lib.callback.await('qbx_garages:server:getGarages')
    for name, garage in pairs(garages) do
        createGarage(name, garage)
    end
end

RegisterNetEvent('qbx_garages:client:garageRegistered', function(name, garage)
    createGarage(name, garage)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end
    closeGarageUi()
end)

RegisterCommand('closegarageui', function()
    closeGarageUi()
end, false)

CreateThread(function()
    Wait(0)
    closeGarageUi()
end)

CreateThread(createGarages)
