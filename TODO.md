- Dev Console : An integrated console in the game that you can run commands. For example:
level new
level resize 2 5
crab move 5 2
level name "grand day out"
level swap 5
level change 7
level change "grand day out"
editortile select lock : Makes current active tile lock instead of whatever it is

- Our own custom font, which would be a sprite atlas font maybe, like older games?

- Patrol enemy: Make Entity struct, make Entity Type be enum of `Blinky` and `Patrol`  something like that. Make Raccoon an entity instead of its own type. Be able to place "patrol tiles" which are essentially trail tiles that are designated that a patrol enemy will patrol on, and have some visual indicator that they are such.

- Laser tile / entity: Not sure if this should be a tile or entity, but essentially a laser machine that shoots a laser until it hits a wall. The laser moves between chunks. Maybe it kills enemies, maybe it doesn't?

- Peg Tile: Certain tiles can be designated "Pegs". Not sure what the correct term here would be. What this means is that they can ONLY be swapped with chunks that have an equivalent peg in the same tile position. Can also use this to create tiles that can not be swapped with ANY tile.

- Shooting hero: I'm imaging a top down, spaceship like avatar that can move around in any direction with tight controls. It uses the right face buttons (A, B, X, Y) to shoot in that direction, basically a twin stick shooter style. I'm also imagining that maybe it has a fixed direction, depending on the direction you enter that chunk. For example, if you enter from the bottom, the ship can only aim up unless you enter from a different direction...

- Tile Unlocked, blinky-like, chase enemy: An enemy that will move towards whatever position the player is at, that is not bound to tile movement.

- Multiple flags to clear a level. Have ability to have multiple flags in level that all need to be collected before clearing a level

- Experiment with 2.5 D graphics. Maybe in a separate project before integrating with this.

- JAM Version TODO: Fix Raccoon AI behavior as it does not act exactly like Blinky from pac man. There is a pac-man dossier one can find archived online that describes the behavior. I also have implementation in my johnblat/pac-man-sdl repository

- JAM Version TODO: Fix Raccoon from going into wall if move chunk at the wrong time. When fox is on edge of chunk and started to move into a tile on the next chunk, if you swap the chunk and now the next tile is a solid tile, the fox will enter it before turning around. The fox should instead continuously check if it can still move to the next tile and if not, then it recognizes it can't move there

- Make recording/playback system better. Use a slot system where it can get written into slots.. Example "recording_0," "recording_01," "recording_02," etc, and that they can be swapped, saved and played back. Makes it so that can save multiple recordings, and also share with each other to demonstrate a bug

- come up with standard for dealing with resolutions, target 1080p, but make the game look great across handheld screens all the way up to 4k monitors

- Joystick can move crab in addition to the d-pad