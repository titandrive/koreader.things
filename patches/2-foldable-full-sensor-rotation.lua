-- 2-foldable-full-sensor-rotation.lua
-- Repository: https://github.com/titandrive/koreader.things
--
-- Lets Android handle all four sensor orientations on the Samsung Fold 8.
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

        if G_reader_settings:readSetting(auto_rotation_setting) == nil then
            G_reader_settings:saveSetting(auto_rotation_setting, true)
        end

        function Device.screen:setRotationMode(mode)
            if G_reader_settings:isTrue(auto_rotation_setting) then
                if mode == self:getRotationMode() then
                    android.orientation.set(C.ASCREEN_ORIENTATION_FULL_SENSOR)
                    return
                end
                G_reader_settings:saveSetting(auto_rotation_setting, false)
            end
            original_setRotationMode(self, mode)
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
                        android.orientation.set(C.ASCREEN_ORIENTATION_FULL_SENSOR)
                        touchmenu_instance:closeMenu()
                    end,
                })
            end

            return items
        end

        if G_reader_settings:isTrue(auto_rotation_setting) then
            android.orientation.set(C.ASCREEN_ORIENTATION_FULL_SENSOR)
        end
        android.LOGI("Fold 8: enabled selectable full-sensor rotation user patch")
    end
end
