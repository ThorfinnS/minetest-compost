--File name: init.lua
--Project name: compost, a Mod for Minetest
--License: General Public License, version 3 or later
--Original Work Copyright (C) 2016 cd2 (cdqwertz) <cdqwertz@gmail.com>
--Modified Work Copyright (C) Vitalie Ciubotaru <vitalie at ciubotaru dot tk>

minetest.log('action', 'MOD: Compost loading...')
compost_version = '0.0.1'

local i18n --internationalization
	if minetest.get_modpath("intllib") then
minetest.log('action', 'intllib loaded')
		i18n = intllib.Getter()
	else
		i18n = function(s,a,...)
		a={a,...}
		local v = s:gsub("@(%d+)", function(n)
			return a[tonumber(n)]
			end)
		return v
	end
end

compost = {}
compost.compostable_groups = {'flora', 'leaves', 'flower', 'sapling'}
compost.compostable_nodes = {
	'default:cactus',
	'default:papyrus',
	'default:dry_shrub',
	'default:junglegrass',
	'default:grass_1',
	'default:dry_grass_1',
	'farming:wheat',
	'farming:straw',
	'farming:cotton',
	'nodetest:papyrus_roots',
}
compost.compostable_items = {}
for _, v in pairs(compost.compostable_nodes) do
	compost.compostable_items[v] = true
end

compost.rare_seeds = {}

local seeds_dedup = {}
-- add simple decorations (flowers, grass, mushrooms) to rare seeds list
for _, deco in pairs(minetest.registered_decorations) do
	if deco.deco_type == "simple" then
		local entry = deco.decoration
		local list = minetest.get_node_drops(entry)
		for _, itemname in ipairs(list) do
			seeds_dedup[itemname] = true
		end
	end
end
-- add saplings and flowers by group to the rare seeds list
for _, item in pairs(minetest.registered_items) do
	if item.groups.sapling or item.groups.flower then
		seeds_dedup[item.name] = true
	end
end
-- add to indexed table
for k,_ in pairs(seeds_dedup) do
	table.insert(compost.rare_seeds, k)
	-- all output flora things are compostable
	compost.compostable_items[k] = true
end


local function formspec(pos, progress)
	local spos = pos.x..','..pos.y..','..pos.z
	local formspec =
		'size[8,8.5]'..
		'list[nodemeta:'..spos..';src;0.5,1;4,2;]'..
		'list[nodemeta:'..spos..';dst;5.5,1;2,2;]'..
		"image[4.5,1.5;1,1;gui_furnace_arrow_bg.png^[lowpart:"..
		(progress)..":gui_furnace_arrow_fg.png^[transformR270]"..
		'list[current_player;main;0,4.25;8,4;]'..
		'listring[nodemeta:'..spos ..';dst]'..
		'listring[current_player;main]'..
		'listring[nodemeta:'..spos ..';src]'..
		'listring[current_player;main]'..
		default.get_hotbar_bg(0, 4.25)
	return formspec
end

-- choose the seed
function compost.get_rare_seed()
	if math.random(100) == 1 then
		return compost.rare_seeds[math.random(#compost.rare_seeds)]
	end
end

function compost.is_compostable(input)
	if compost.compostable_items[input] then
		return true
	end
	for _, v in pairs(compost.compostable_groups) do
		if minetest.get_item_group(input, v) > 0 then
			return true
		end
	end
	return false
end

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

local function is_distributed(pos)
	local meta = minetest.get_meta(pos)
	for k, stack in pairs(meta:get_inventory():get_list('src')) do
		if stack:is_empty() then
			return false
		end
	end
	return true
end

local function is_empty(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stacks = inv:get_list('src')
	for k in pairs(stacks) do
		if not inv:get_stack('src', k):is_empty() then
			return false
		end
	end
	if not inv:get_stack('dst', 1):is_empty() then
		return false
	end
	return true
end

local function update_nodebox(pos)
	if is_empty(pos) then
		swap_node(pos, "compost:wood_barrel_empty")
	else
		swap_node(pos, "compost:wood_barrel")
	end
end

local function update_timer(pos)
	local timer = minetest.get_node_timer(pos)
	local meta = minetest.get_meta(pos)
	local progress = meta:get_int('progress') or 0
	if not is_distributed(pos) then
		timer:stop()
		progress = 0
		meta:set_int('progress', progress)
		meta:set_string('infotext', i18n('To start composting, place some organic matter inside.'))
	else
		if not timer:is_started() then
			timer:start(30)
		end
		meta:set_string('infotext', i18n('progress: @1%', progress))
	end
	meta:set_string('formspec', formspec(pos, progress))
end

function compost.create_compost(pos)
	-- get items from compost inventory
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stacks = inv:get_list('src')
	for k, stack in ipairs(stacks) do
		stack:take_item()
		inv:set_stack('src', k, stack)
	end
	local item = compost.get_rare_seed() or 'default:dirt'
	inv:add_item("dst", item)
end

local function on_timer(pos)
	local timer = minetest.get_node_timer(pos)
	local meta = minetest.get_meta(pos)
	local progress = meta:get_int('progress') + 10
	if progress >= 100 then
		compost.create_compost(pos)
		progress = 0
		update_nodebox(pos)
	end
	meta:set_int('progress', progress)
	update_timer(pos)
end

local function on_construct(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size('src', 8)
	inv:set_size('dst', 4)
	update_timer(pos)
end

local function can_dig(pos,player)
	local meta = minetest.get_meta(pos)
	local inv  = meta:get_inventory()
	if inv:is_empty('src') and inv:is_empty('dst') then
		return true
	else
		return false
	end
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if listname == 'src' and compost.is_compostable(stack:get_name()) then
		return stack:get_count()
	else
		return 0
	end
end

local function on_metadata_inventory_put(pos, listname, index, stack, player)
	update_timer(pos)
	update_nodebox(pos)
	minetest.log('action', player:get_player_name() .. ' moves stuff to compost bin at ' .. minetest.pos_to_string(pos))
	return
end

local function on_metadata_inventory_take(pos, listname, index, stack, player)
	update_timer(pos)
	update_nodebox(pos)
	minetest.log('action', player:get_player_name() .. ' takes stuff from compost bin at ' .. minetest.pos_to_string(pos))
	return
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local inv = minetest.get_meta(pos):get_inventory()
	if from_list == to_list then 
		return inv:get_stack(from_list, from_index):get_count()
	else
		return 0
	end
end

local function on_punch(pos, node, player, pointed_thing)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local wielded_item = player:get_wielded_item()
	if not wielded_item:is_empty() and wielded_item:get_name() ~= 'default:dirt' then
		-- anything wielded. Try to place it to the compost
		if compost.is_compostable(wielded_item:get_name()) then
			if is_distributed(pos) then
				-- all slot contains someting. Just add if fits
				player:set_wielded_item(inv:add_item('src', wielded_item))
			else
				-- not all slots filled. Add to a free slot
				for i, stack in ipairs(inv:get_list('src')) do
					if stack:is_empty() then
						inv:set_stack('src', i, wielded_item)
						player:set_wielded_item(nil)
						break
					end
				end
			end
		end
	else
		-- empty hand. Try to get from compost
		local stacks = inv:get_list('dst')
		for k, stack in ipairs(stacks) do
			if not stack:is_empty() then
				inv:set_stack('dst', k, wielded_item:add_item(stack))
			end
		end
		if not wielded_item:is_empty() then
			--player:set_wielded_item(wielded_item) -- does not work proper with empty wielded item?
			player:get_inventory():set_stack(player:get_wield_list(), player:get_wield_index(), wielded_item)
			minetest.log('action', player:get_player_name() .. ' takes stuff from compost bin at ' .. minetest.pos_to_string(pos))
		end
	end
	update_nodebox(pos)
	update_timer(pos)
end

minetest.register_node("compost:wood_barrel_empty", {
	description = i18n('Empty Compost Bin'),
	tiles = {
		"default_wood.png",
	},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {{-1/2, -1/2, -1/2, -3/8, 1/2, 1/2},
			{3/8, -1/2, -1/2, 1/2, 1/2, 1/2},
			{-1/2, -1/2, -1/2, 1/2, 1/2, -3/8},
			{-1/2, -1/2, 3/8, 1/2, 1/2, 1/2}},
	},
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}
	},
	paramtype = "light",
	is_ground_content = false,
	groups = {choppy = 3},
	sounds =  default.node_sound_wood_defaults(),
	on_timer = on_timer,
	on_construct = on_construct,
	can_dig = can_dig,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
	on_punch = on_punch,
})

minetest.register_node("compost:wood_barrel", {
	description = i18n('Compost Bin'),
	tiles = {
		"default_wood.png^compost_compost.png",
		"default_wood.png^compost_compost.png",
		"default_wood.png",
	},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {{-1/2, -1/2, -1/2, 1/2, -3/8, 1/2},
			{-1/2, -1/2, -1/2, -3/8, 1/2, 1/2},
			{3/8, -1/2, -1/2, 1/2, 1/2, 1/2},
			{-1/2, -1/2, -1/2, 1/2, 1/2, -3/8},
			{-1/2, -1/2, 3/8, 1/2, 1/2, 1/2},
			{-3/8, -1/2, -3/8, 3/8, 3/8, 3/8}},
	},
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}
	},
	paramtype = "light",
	is_ground_content = false,
	groups = {choppy = 3, not_in_creative_inventory = 1},
	sounds =  default.node_sound_wood_defaults(),
	on_timer = on_timer,
	on_construct = on_construct,
	can_dig = can_dig,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
	on_punch = on_punch,
})

minetest.register_craft({
	output = "compost:wood_barrel_empty",
	recipe = {
		{"group:wood", "", "group:wood"},
		{"group:wood", "", "group:wood"},
		{"group:wood", "group:stick", "group:wood"}
	}
})

minetest.log('action', 'MOD: Compost version ' .. compost_version .. ' loaded.')
