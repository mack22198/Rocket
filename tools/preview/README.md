# Offline previews

These tools draw the game **without Roblox Studio**, using the game's real builder code run in
[Lune](https://lune-org.github.io/docs). They're rough approximations of Roblox's renderer, handy for checking
layouts and proportions from anywhere (including CI machines).

| What | Export (from the repository root) | Draw |
| --- | --- | --- |
| Stadium, lobby, cars, ball | `lune run tools/preview/export tools/preview/scene.json` | `index.html?view=<name>` |
| Menu showroom with a car | `lune run tools/preview/export tools/preview/showroom.json showroom <carId> <stage> <yaw>` | `index.html?scene=showroom.json&view=menu` (or `garage`) |
| Screens (menus, HUD, garage, results) | `lune run tools/preview/ui-export <scenario> tools/preview/ui-<scenario>.json` | `ui.html?scenario=<scenario>` |

3D views: `overview`, `aerial`, `kickoff`, `midfield`, `goal`, `goalInside`, `corner`, `wallRide`, `stands`,
`lobby`, `lobbyShowroom`, `lobbyFromField`, `outside`, `ball`, `cars`, `carsClose` (or pass `pos=x,y,z&at=x,y,z`).

UI scenarios: `menu`, `queued`, `live`, `garage`, `evolve`, `howto`, `match`, `pause`, `touch`, `goal`, `results`. Add
`bg=<image>` to draw them on top of a screenshot of the game (for example a showroom render saved as `bg-menu.png`).

To save PNGs of any of these with headless Chromium:

```bash
cd tools/preview
npm install
node shoot.mjs shots kickoff goal "menu?scene=showroom.json" "ui/menu?bg=bg-menu.png"
```
