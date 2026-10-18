-- The games still to come: shown in the picker as "Coming soon", in the order Xn asked for them (2026-10-18).
local ADDON, A = ...
local S = A.SPELLS
local function soon(key, order, name, icon, tagline)
  A.RegisterGame({ key = key, name = name, order = order, ready = false, icon = icon, tagline = tagline })
end
soon('higher', 3, 'Higher or Lower', S.baneOfDoom.id, 'Which build sims higher? Guess right, keep your streak.')
soon('warlockle', 4, 'Warlockle', S.curseOfElements.id, 'A daily puzzle: guess the spell or talent from its clues.')
soon('ware', 5, 'Warlock Ware', S.lifeTap.id, 'Micro-games of a few seconds each. Life Tap! Spell queue! Catch the proc!')
soon('pegs', 6, 'Shadow Pegs', S.shadowBolt.id, 'Bounce a Shadow Bolt through the pegs and light them all up.')
soon('taptap', 7, 'Tap Tap DPS', S.rainOfFire.id, 'Your rotation is the song chart. Hit the notes on time, see your DPS.')
soon('merge', 8, 'Demon 2048', A.PETS.imp.spell, 'Merge soul shards into ever bigger demons.')
