# QoLify

A collection of small quality of life tweaks plus bigger optional modules, all in one
addon. Everything starts off. Tweaks toggle on and off instantly, and a module's code
is not even loaded until you enable it, so you only pay for what you actually use.

Type `/qolify` or right-click the minimap button to open the settings.

## Tweaks

- **Quick delete**: fills in the "type DELETE to confirm" popup for you.
- **Auto-accept resurrection**: accepts resurrections automatically out of combat.
- **Party Keys in Group Finder**: when you go to "Start a group", a dropdown shows your party's
  keystones and picking one fills in the dungeon and activity for you.

## Modules

**SoundScaper** switches your volume settings automatically as you move between
activities, so you stop digging through the sound options. Five sections, each with its
own sliders and mutes per audio channel: Outdoors, Dungeon, Mythic+, Raid and Raid Boss,
which kicks in the instant a boss encounter starts. Full music out in the world, effects
only in a key, everything but Master muted on a raid pull. The sync goes both ways, so
a change made in the game's own audio options is picked up by the section you are in.

**Decor Tools** is a pair of tools for housing decor. The shopping cart is a wish list you
fill while decorating: hit the + on catalog entries, or drop the piece you have
selected in the house editor straight into the cart window. It remembers quantities and
shows price estimates from the catalog. At a vendor, carted items get a "buy N" line on
their tooltips that counts down as you buy, with buy buttons in the cart for whatever
that vendor stocks. The spend watcher is the budget half: pick a per-item gold cap and
anything priced above it gets a red warning on its vendor tooltip, buy it anyway and
you get a note in chat, and a running total tracks what decor has cost you.

Both also exist as standalone addons
([SoundScaper](https://www.curseforge.com/wow/addons/soundscaper-volume-profiles-for-dungeon-raid),
[Decor Tools](https://www.curseforge.com/wow/addons/decor-spendwatch)). If you
already run the standalone, the QoLify module stands by and lets it work. Your settings
copy over by themselves the first time you log out with both installed, and from then
on removing the standalone hands everything to the module. Just don't uninstall the
standalone before installing QoLify, since your settings would stay behind in its old
saved variables file where the module can't reach them.
