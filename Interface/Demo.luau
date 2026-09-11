-- Point this at wherever you saved the library file.
local Oshiru = loadstring(game:HttpGet("https://raw.githubusercontent.com/CabineTsv/Oshiru/refs/heads/main/Interface/Source.luau"))()

-- CreateWindow builds the whole window in one call: main frame, loading
-- screen, and a Settings tab (themes, translation, config save/load, etc.)
-- all come included, you don't need to build those yourself.
local Window = Oshiru:CreateWindow({
	Title = "Oshiru Demo",
	LoadingEnabled = false, -- set false to skip the intro loading screen
});

-- Tabs live in the sidebar. Second argument is a rbxassetid icon, swap it
-- for whatever fits your project.
local Tab = Window:create_tab("Demo", "rbxassetid://79095934438045");

-- Modules are the boxes that group related controls inside a tab.
-- "section" is just which column it lands in, left or right.
local Basics = Tab:create_module({
	title = "Basic Controls",
	description = "Labels, buttons, and text",
	flag = "_demo_basic",
	section = "left",
	callback = function() end, -- runs once when the module is built, most people leave this empty
});

-- Three ways to show plain text, pick whichever fits:
-- create_label needs both a title and a body, create_paragraph is the
-- same idea but sized for longer writing, and create_text is just a
-- single block with no title.
Basics:create_label({title = "Label", text = "A short title plus a line of body text."});
Basics:create_paragraph({title = "Paragraph", text = "Same idea as a label, just roomier for longer explanations."});
Basics:create_text({text = "No title, just text."});

-- Buttons just need a label and a callback.
Basics:create_button({buttonText = "Click Me", callback = function()
	Oshiru:SendNotification({title = "Button Clicked", text = "Nice.", duration = 2.5, type = "success"});
end});

-- Anything that saves a value (textbox, checkbox, slider, dropdown, etc.)
-- needs a unique "flag" string. That's the key it's stored under in the
-- config file, so don't reuse flags across different controls.
Basics:create_textbox({title = "Textbox", flag = "_demo_textbox", placeholder = "Type something...", callback = function(text) end});

-- Dividers are just visual breaks. showtopic adds a centered label on the line.
Basics:create_divider({showtopic = true, title = "Toggles & Values"});

Basics:create_checkbox({title = "Checkbox", flag = "_demo_checkbox", callback = function(state) end});

-- Sliders drag to set a value, but you can also double-click the number
-- on the right to type an exact one.
Basics:create_slider({title = "Slider (double-click the value to type)", flag = "_demo_slider", value = 50, minimum_value = 0, maximum_value = 100, round_number = true, callback = function(value) end});

local Inputs = Tab:create_module({title = "Selection & Input", description = "Dropdowns, colors, and keybinds", flag = "_demo_input", section = "right", callback = function() end});

-- Regular dropdown, one choice at a time.
Inputs:create_dropdown({title = "Dropdown", flag = "_demo_dropdown", options = {"Option A", "Option B", "Option C"}, multi_dropdown = false, maximum_options = 3, callback = function(option) end});

-- Same component, but multi_dropdown lets more than one stay selected.
Inputs:create_multidropdown({title = "Multi-Dropdown", flag = "_demo_multidropdown", options = {"Red", "Green", "Blue", "Yellow"}, callback = function(selected) end});

Inputs:create_colorpicker({title = "Color Picker", flag = "_demo_color", default = Color3.fromRGB(130, 100, 255), callback = function(color) end});

-- mode can be "Toggle" (press once to turn on, again to turn off) or "Hold".
Inputs:create_keybind({title = "Keybind", flag = "_demo_keybind", default = Enum.KeyCode.E, mode = "Toggle", callback = function(active) end});

-- Shows which of the listed keybinds are currently active. Pass it the
-- same flag names you gave to create_keybind.
Inputs:create_keybinddisplay({title = "Active Binds", binds = {"_demo_keybind"}});

local Status = Tab:create_module({title = "Status & Progress", description = "Progress bars, status, and groups", flag = "_demo_status", section = "left", callback = function() end});

Status:create_progressbar({title = "Progress Bar", value = 65, callback = function(value) end});
Status:create_status({title = "System Status", status = "Enabled", text = "Online"});

-- A row of buttons sharing one frame. Handy for Save/Load/Delete-style actions.
Status:create_buttongroup({buttons = {
	{text = "Group A", callback = function() end},
	{text = "Group B", callback = function() end},
	{text = "Group C", callback = function() end},
}});

Status:create_image({title = "Image", image = "rbxassetid://79095934438045", size = UDim2.new(1, 0, 0, 80), cornerRadius = 6});

local Showcase = Tab:create_module({title = "Notifications & Dialogs", description = "Try the feedback systems", flag = "_demo_showcase", section = "right", callback = function() end});

-- Notifications: title, text, duration in seconds, and type controls the
-- accent color/icon (success, error, warning, info, loading, default).
-- Call these through Oshiru, not Window, since SendNotification lives on
-- the library's public table.
Showcase:create_buttongroup({buttons = {
	{text = "Success", callback = function()
		Oshiru:SendNotification({title = "Success", text = "Everything worked as expected.", duration = 3, type = "success"});
	end},
	{text = "Error", callback = function()
		Oshiru:SendNotification({title = "Error", text = "Something went wrong.", duration = 3, type = "error"});
	end},
	{text = "Warning", callback = function()
		Oshiru:SendNotification({title = "Warning", text = "Proceed with caution.", duration = 3, type = "warning"});
	end},
}});

-- ShowDialog pops a centered confirm/cancel box, good for anything
-- destructive you don't want happening on a single accidental click.
-- The callback receives true if Confirm was clicked, false for Cancel.
Showcase:create_button({buttonText = "Open Confirm Dialog", callback = function()
	Oshiru:ShowDialog({title = "Demo Dialog", text = "This is the confirm/cancel dialog system.", confirm_text = "Nice", cancel_text = "Close", callback = function(confirmed)
		Oshiru:SendNotification({title = "Dialog Result", text = ((confirmed and "You confirmed.") or "You cancelled."), duration = 2.5, type = "info"});
	end});
end});

-- Watermarks are their own floating window (title, optional fps/ping),
-- independent of the main UI, so they'll keep running even if you close
-- this window. create_watermark lives on Window itself, unlike the two above.
local watermark = nil;
Showcase:create_checkbox({title = "Show Watermark", flag = "_demo_watermark", callback = function(state)
	if (state and not watermark) then
		watermark = Window:create_watermark({title = "Oshiru Demo"});
	elseif (not state and watermark) then
		watermark:Destroy();
		watermark = nil;
	end
end});

-- Everything above is optional, this line alone already gets you a fully
-- working settings menu: themes, live theme editing, translation,
-- notification settings, server codes, and config save/load/import/export.
Oshiru:SendNotification({title = "Demo Loaded", text = "Check the Settings tab for themes, translation, and config tools.", duration = 6, type = "info"});
