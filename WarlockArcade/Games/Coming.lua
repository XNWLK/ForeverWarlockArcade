-- The games still to come: shown in the picker as "Coming soon", in the order Xn asked for them (2026-10-18).
local ADDON, A = ...
local S = A.SPELLS
local function soon(key, order, name, icon, tagline)
  A.RegisterGame({ key = key, name = name, order = order, ready = false, icon = icon, tagline = tagline })
end
soon('merge', 8, 'Demon 2048', A.PETS.imp.spell, 'Merge soul shards into ever bigger demons.')
