# Forever Warlock Arcade

Little Warlock games for **WoW: Forever**. Play them **in the browser** or **in the game** as an addon: the same games, from the same code.

**Play in the browser:** https://xnwlk.github.io/ForeverWarlockArcade/

The games use real numbers from the [Forever Warlock Sim](https://xnwlk.github.io/WarlockSIM/): spell crit chance, crit damage, talent and spell texts, icons.

## The games

| Game | What it is | State |
|---|---|---|
| **Shard & Mult** | A poker-hand roguelike. The suits are Shadow Bolt, Corruption, Immolate and Incinerate, J/Q/K are demons, talents are your jokers, Molten Core bosses are the blinds and Ragnaros waits at ante 8. | Playable |
| DoT Juggler | Keep your DoTs ticking on every dummy. | Coming soon |
| Higher or Lower | Which build sims higher? | Coming soon |
| Warlockle | A daily guessing puzzle. | Coming soon |
| Warlock Ware | Micro-games of a few seconds each. | Coming soon |
| Shadow Pegs | Bounce a Shadow Bolt through the pegs. | Coming soon |
| Tap Tap DPS | Your rotation is the song chart. | Coming soon |
| Demon 2048 | Merge soul shards into bigger demons. | Coming soon |

## In the game

Copy the `WarlockArcade` folder into `World of Warcraft\_classic_beta_\Interface\AddOns`, restart the game and type `/arcade`. (A CurseForge page will follow once the first version is out.)

## The other Warlock projects

| Project | Page | Source |
|---|---|---|
| Forever Warlock Sim: DPS simulator | https://xnwlk.github.io/WarlockSIM/ | https://github.com/XNWLK/WarlockSIM |
| Forever Warlocking: 3D rotation practice | https://xnwlk.github.io/ForeverWarlocking/ | https://github.com/XNWLK/ForeverWarlocking |
| Xn's Warlock Sim: the sim as an addon | https://www.curseforge.com/wow/addons/xns-warlock-sim | https://github.com/XNWLK/WarlockSIMAddon |

## How it works

The games are written once, in Lua, as a WoW addon (`WarlockArcade/`). The web page runs those same Lua files with [fengari](https://github.com/fengari-lua/fengari) (a Lua engine for the browser, MIT licence) and a small stand-in for the game's frames, textures, text and mouse (`web/`). Spell icons are Wowhead's (wow.zamimg.com).
