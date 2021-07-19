# Speedy

Speedy tracks character leveling in both real and in-game time. As your character progresses, Speedy will store cumulative in-game /played time and a real-time timestamp for each level earned.

## Usage

Speedy acts mainly as a data store, persisting leveling times for each character account-wide. It is intended that other in-game addons or external tools will utilize this data for leveling analysis and visualization.

## Slash Commands

* /speedy         - print this usage info
* /speedy version - print version info
* /speedy char    - print character data
* /speedy export  - export all character data as zlib-encoded json string
