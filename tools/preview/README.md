# Offline previews

These tools draw the game **without Roblox Studio**, using the game's real builder code run in
[Lune](https://lune-org.github.io/docs). They're rough approximations of Roblox's renderer, handy for checking
layouts and proportions from anywhere (including CI machines).

| What | Export (from the repository root) | Draw |
| --- | --- | --- |
| Stadium, lobby, cars, ball | `lune run tools/preview/export tools/preview/scene.json` | `index.html?view=<name>` |
| Screens (HUD, garage, results) | `lune run tools/preview/ui-export <scenario> tools/preview/ui-<scenario>.json` | `ui.html?scenario=<scenario>` |

3D views: `overview`, `aerial`, `kickoff`, `midfield`, `goal`, `goalInside`, `corner`, `wallRide`, `stands`,
`lobby`, `lobbyShowroom`, `lobbyFromField`, `outside`, `ball`, `cars`, `carsClose` (or pass `pos=x,y,z&at=x,y,z`).

UI scenarios: `lobby`, `match`, `touch`, `goal`, `garage`, `evolve`, `results`. Add `bg=<image>` to draw them on top of
a screenshot of the game.

To save PNGs of any of these with headless Chromium:

```bash
cd tools/preview
npm install
node shoot.mjs shots kickoff goal "ui/garage?bg=bg-lobby.png"
```
