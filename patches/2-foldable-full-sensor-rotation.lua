-- 2-foldable-full-sensor-rotation.lua
-- Repository: https://github.com/titandrive/koreader.things
--
-- Lets Android handle all four user-enabled sensor orientations on the
-- Samsung Fold 8 while respecting Android's Auto rotate setting.
-- KOReader normally turns its rotation modes into fixed Android orientation
-- requests. On the Fold's landscape-native inner display, Samsung treats that
-- request as SENSOR_LANDSCAPE, which prevents portrait sensor rotations.
--
-- INSTALLATION:
--   Copy this file into koreader/patches/, then restart KOReader.

local Device = require("device")

if Device:isAndroid() then
    local android = require("android")
    local ffi = require("ffi")
    local C = ffi.C
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")

    local model = tostring(android.prop.model or "")
    local product = tostring(android.prop.product or "")
    local device = tostring(android.prop.device or "")
    local is_fold8 = model == "SM-F971U1"
        or product == "h8quew"
        or device == "h8q"

    if is_fold8 and not Device.screen._foldable_full_sensor_rotation then
        Device.screen._foldable_full_sensor_rotation = true
        local auto_rotation_setting = "foldable_full_sensor_rotation"
        local original_setRotationMode = Device.screen.setRotationMode
        local original_broadcastEvent = UIManager.broadcastEvent
        local android_full_user = 13 -- ActivityInfo.SCREEN_ORIENTATION_FULL_USER

        -- android-luajit-launcher currently validates orientation values only
        -- through FULL_SENSOR (10), although its Java bridge accepts FULL_USER
        -- (13). Reuse the bridge captured by android.orientation.set.
        local orientation_jni
        for index = 1, 10 do
            local name, value = debug.getupvalue(android.orientation.set, index)
            if not name then break end
            if name == "JNI" then
                orientation_jni = value
                break
            end
        end

        local function setFullUserOrientation()
            if orientation_jni then
                orientation_jni:context(android.app.activity.vm, function(jni)
                    jni:callVoidMethod(
                        android.app.activity.clazz,
                        "setScreenOrientation",
                        "(I)V",
                        ffi.new("int32_t", android_full_user)
                    )
                end)
            else
                -- USER honors the system lock, but may be limited to fewer
                -- sensor positions on older Android versions.
                android.orientation.set(C.ASCREEN_ORIENTATION_USER)
            end
        end

        if G_reader_settings:readSetting(auto_rotation_setting) == nil then
            G_reader_settings:saveSetting(auto_rotation_setting, true)
        end

        function Device.screen:setRotationMode(mode)
            if G_reader_settings:isTrue(auto_rotation_setting) then
                setFullUserOrientation()
                return
            end
            original_setRotationMode(self, mode)
        end

        -- Startup restores call onSetRotationMode directly, while explicit
        -- rotation controls (including Zen UI quick settings) broadcast this
        -- event. This lets manual choices disable auto mode without a fragile
        -- startup timer.
        UIManager.broadcastEvent = function(self, event, ...)
            if event and event.handler == "onSetRotationMode"
                    and G_reader_settings:isTrue(auto_rotation_setting) then
                G_reader_settings:saveSetting(auto_rotation_setting, false)
            end
            return original_broadcastEvent(self, event, ...)
        end

        local rotation_menu = require("ui/elements/screen_rotation_menu_table")
        local original_sub_item_table_func = rotation_menu.sub_item_table_func

        rotation_menu.sub_item_table_func = function(...)
            local items = original_sub_item_table_func(...)
            local first_rotation_item

            for index, item in ipairs(items) do
                if item.radio then
                    first_rotation_item = first_rotation_item or index
                    local original_callback = item.callback
                    item.callback = function(...)
                        G_reader_settings:saveSetting(auto_rotation_setting, false)
                        return original_callback(...)
                    end
                end
            end

            if first_rotation_item then
                table.insert(items, first_rotation_item, {
                    text = _("Auto rotate (all orientations)"),
                    radio = true,
                    checked_func = function()
                        return G_reader_settings:isTrue(auto_rotation_setting)
                    end,
                    callback = function(touchmenu_instance)
                        G_reader_settings:saveSetting(auto_rotation_setting, true)
                        setFullUserOrientation()
                        touchmenu_instance:closeMenu()
                    end,
                })
            end

            return items
        end

        if G_reader_settings:isTrue(auto_rotation_setting) then
            setFullUserOrientation()
        end
        android.LOGI("Fold 8: enabled selectable full-sensor rotation user patch")
    end
end
