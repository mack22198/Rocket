# Turbo Ball

A Roblox 3v3 car soccer game built for kids: drive a silly car, hit a giant ball, and there's always a
new car you're *almost* ready to unlock.

This is the **first playable version** (the "vertical slice" from the design): the goal is to find out whether
a kid who finishes one match immediately wants to play another. "Turbo Ball" is a working title; change
`GameName` in [`GameConfig.luau`](src/shared/Config/GameConfig.luau) to rename it.

## What's in it

- **A main menu in a 3D garage showroom.** You start in the menu, not in a match: your car turns on a glowing
  turntable in a dark studio with a polished, reflective floor, spotlights and a big screen. From there: **PLAY**,
  **GARAGE** and **HOW TO PLAY**. After a match you pick **PLAY AGAIN**, **GARAGE** or **MENU**, and the ☰ MENU
  button (or M) lets you leave a match at any time.
- **3v3 matches, 3 minutes long.** Bots fill any empty seats, so one kid alone still gets a full game. Pressing
  PLAY while a match is on takes over a bot's seat right away; otherwise the next match starts a few seconds
  later (so friends who press PLAY together play together).
- **Car soccer:** a curved-wall arena with glowing goals and nets, boost pads, kickoff countdowns, a scoreboard and
  clock, a play-on-at-0:00 rule, and golden-goal overtime.
- **A real stadium:** team-coloured stands packed with fans (who jump when someone scores and do Mexican waves),
  scrolling LED advert boards that flash team colours after a goal, the game's name painted on the pitch, glass
  walls, floodlights and giant screens showing the live score, under a late-afternoon sky with hills and trees.
- **Big moments look big:** every goal sets off a shockwave, a fireball and smoke in the net, confetti over the
  goal and fireworks above the stands, then a **slow-motion replay** of the goal (with cinema bars and the
  scorer's name; SKIP to get back to driving). Hard hits flash, Mega Shots explode, boosting cars stream light
  trails and the camera widens as you go faster.
- **The winners' podium:** at the final whistle the top three cars appear on a podium in the middle of the
  pitch - the MVP on the top step - with confetti and fireworks, before the results screen.
- **Arcade driving:** boost, jump, double jump, flips (dodges), air control and air roll, driving up the curved
  walls, and bumping other cars.
- **Item boxes:** spinning "?" boxes on the pitch give you a random item to use whenever you like (R): a
  **Magnet** that pulls the ball to your car, a **Freeze Ray** that freezes the closest opponent, a **Super
  Spring**, **Rocket Fuel** (boost that doesn't run out), a **Bubble Shield** and a **Mega Charge**. A team
  that's behind gets the comeback items more often, so matches stay close.
- **Match twists:** most matches start with a surprise rule for the whole match - 🏀 **Giant Ball**, 🌙 **Low
  Gravity**, 🏐 **Bouncy Ball**, ⛸️ **Ice Rink**, ⚡ **Turbo Mode** (boost never runs out), 💥 **Mega Madness** or
  🌃 **Neon Night**. Each week one twist is featured, and every Saturday and Sunday is a **Twist Weekend**: a
  twist in every match and +50% Scrap.
- **Every car has its own power** (G), which recharges after each use: the Pizza Car drops a gooey **Cheese
  Trap**, the Banana Car a **Banana Peel** that spins cars out, the Tiny Kart has a **Nitro Dash**, the Neon
  Shark a **Shark Dive** that makes it untouchable, the Monster Truck a **Ground Pound** shockwave, the UFO a
  **Tractor Beam** that lifts the ball up for the perfect shot, the Taco Truck **Hot Sauce** (your next hit is a
  Mega Shot), the Rubber Duck a **Quack Attack** that spins out everyone nearby, and the Hot Dog a **Ketchup
  Slick** trail.
- **Mega Shot:** touching the ball, making saves and doing style moves fills a meter. When it's full, press
  F to arm it and your next hit blasts the ball on fire. It's earned in the match, never bought.
- **Style and combos:** air hits, wall hits, passes and Mega Shots chain into combo goals ("🔥 3X COMBO!").
  Saves, style moves and MVP are all announced.
- **Rewards:** everyone earns **Scrap** every match (more for winning, goals, saves and style). Scrap is the
  only currency and there are no loot boxes.
- **Daily reasons to come back:** a **login streak** (more Scrap every day in a row, up to day 7), **three daily
  quests** ("Score 2 goals", "Use 5 items"...) and a **daily chest** once they're done - its three prizes are
  shown face up and you pick one (Scrap, XP for your car, or double Scrap for a few matches). Nothing is random
  or hidden.
- **Collection book:** every car at every evolution stage, with black mystery silhouettes for the ones you
  haven't got yet.
- **9 collectible cars:** a pizza delivery hot hatch (the starter), a banana roadster, a go-kart, a rubber
  duck, a shark supercar, a taco food truck (with a giant taco on the roof), a monster truck, a hot dog and a
  UFO. They're proper little battle-cars - spoked wheels that roll and steer, light bars and spoilers - each with
  real strengths and weaknesses. Rarity never means "better".
- **Car evolutions:** every car earns XP while you drive it (as much as the Scrap you win) and evolves through
  four looks, e.g. Pizza Car → Burnt Pizza Car → Lava Pizza Car → Galaxy Pizza Car. Evolving is earned by playing,
  never bought, and only changes looks. You can switch back to any look you've unlocked, and bots sometimes
  drive evolved cars to show what's possible.
- **Garage:** your cars on the left, the chosen car big on the showroom turntable (drag to spin it), and its stats,
  price and evolution track on the right, with an EVOLVE! button that sets off a light show. The menu's "saving
  up for" card and the results screen keep the next goal in sight.
- **Works on computer, gamepad and phone/tablet** (on-screen stick and buttons).
- **Progress saves** with DataStores (once the game is published).

## Play it in Roblox Studio

1. Install [Roblox Studio](https://create.roblox.com/) (free).
2. Get the game file `TurboBall.rbxlx`:
   - Every push to this repo builds it automatically: open the **Actions** tab on GitHub, click the latest
     green run, and download **TurboBall-place** under *Artifacts* (it's a zip; unzip it).
   - Or build it yourself (see [Working on the code](#working-on-the-code)).
3. Double-click `TurboBall.rbxlx` to open it in Studio (or **File → Open from File**).
4. Press **Play** (F5). The main menu opens in the garage showroom. Press **PLAY**: a match starts a few
   seconds later (bots fill the other seats) and you're dropped into your car for the countdown.
5. To try it with more than one player: **Test** tab → *Clients and Servers* → choose 2+ players → **Start**.

When testing in Studio your progress isn't saved unless the place is published and API access is on (see below).
To try the garage without grinding, set `StudioStartingScrap` in `GameConfig.luau`, e.g. to `5000`. To see
evolutions quickly, lower the numbers in `GameConfig.Evolution.Xp`.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Drive / brake / reverse | W / S (or arrows) | RT / LT (or left stick) | Stick (left side) |
| Steer | A / D | Left stick | Stick |
| Jump (twice to double jump, jump + direction to flip) | Space or right mouse | A | JUMP |
| Boost | Shift or left mouse | B | BOOST |
| Mega Shot (when the meter is full) | F | X | MEGA |
| Use your item | R | RB | ITEM |
| Use your car's power | G | LB | POWER |
| Ball cam on/off | C | Y | CAM |
| Air roll | Q / E | | |
| In the air: tip the nose | W / S | Left stick | Stick |
| Match menu (leave the match) | M | View / Back | ☰ MENU |

## Publishing to Roblox

1. In Studio: **File → Publish to Roblox**.
2. **Game Settings → Places:** set *Max Players* to 6 for pure 3v3 (extra players wait in the menu and join
   when a seat opens).
3. **Game Settings → Security:** turn on *Enable Studio Access to API Services* so saving also works when
   testing in Studio.
4. Players' Scrap, cars and stats are saved automatically in the live game.

## Changing the game

Almost everything is a number in [`src/shared/Config/`](src/shared/Config):

- [`GameConfig.luau`](src/shared/Config/GameConfig.luau): match length, arena size, ball bounciness, car speed,
  boost, jump height, gravity, bot skill, Mega Shot, boost pads and Studio shortcuts.
- [`CarCatalog.luau`](src/shared/Config/CarCatalog.luau): the cars, prices and stats.
- [`Rewards.luau`](src/shared/Config/Rewards.luau): how much Scrap each thing is worth.
- [`Powers.luau`](src/shared/Config/Powers.luau): the items and car powers, how often each item turns up
  (and how much that depends on the score), and how strong they all are.
- [`Daily.luau`](src/shared/Config/Daily.luau): the streak rewards, the daily quests and the chest prizes.
- [`Twists.luau`](src/shared/Config/Twists.luau): the match twists (what each one changes and how often it
  turns up) and the weekend event.
- `GameConfig.Evolution`: how much XP each evolution stage needs.

Car looks (and every evolution stage) are built from plain parts in
[`CarModelBuilder.luau`](src/shared/Cars/CarModelBuilder.luau), so new cars need no uploaded models. The stadium,
lobby and scenery are built the same way in [`src/server/Arena`](src/server/Arena), and the menu showroom in
[`ShowroomBuilder.luau`](src/client/Showroom/ShowroomBuilder.luau); their colours are in
[`Palette.luau`](src/shared/Build/Palette.luau). The stadium lighting (sun, haze, glow) is set in
[`default.project.json`](default.project.json), and the showroom's studio lighting in
[`ShowroomController.luau`](src/client/Controllers/ShowroomController.luau). Sounds use Roblox's built-in ones;
to add a goal horn or crowd cheer, paste audio IDs from the Creator Store into `SOUNDS` in
[`EffectsController.luau`](src/client/Controllers/EffectsController.luau).

## Working on the code

The code lives in files and is synced into Studio with [Rojo](https://rojo.space/).

1. Install [Rokit](https://github.com/rojo-rbx/rokit) (a tool installer), then in this folder run:
   ```sh
   rokit install
   ```
   This installs the exact versions in [`rokit.toml`](rokit.toml): Rojo, StyLua, Selene, Lune and luau-lsp.
2. Install the Rojo plugin in Studio: `rojo plugin install`.
3. Run `rojo serve`, open the place in Studio, and click **Connect** in the Rojo plugin. Saving a file updates
   Studio instantly. Edit the files, not the scripts inside Studio (synced scripts get overwritten).
4. Build a fresh place file any time: `rojo build -o TurboBall.rbxlx`.

### Checks

These all run on GitHub for every push (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

```sh
stylua --check src tests    # formatting
selene src                  # linting
lune run tests/run          # unit tests (physics, bots, rewards, arena, a simulated bot match...)
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=@roblox=roblox.d.luau --sourcemap=sourcemap.json src   # Roblox type check
```

(`roblox.d.luau` comes from
[luau-lsp](https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.0/scripts/globalTypes.None.d.luau).)

### Previews without Studio

[`tools/preview`](tools/preview) draws the stadium, the cars and the UI screens in a web browser using the game's
real building code, which is handy for checking changes to how things look from any computer. See its
[README](tools/preview/README.md).

## How it's built

```
src/
  shared/   (ReplicatedStorage.Shared: used by both server and client)
    Config/       GameConfig, CarCatalog, Rewards, Evolution, Powers (items and car powers), Daily (streaks,
                  quests, daily chest), Twists (match twists and weekend events)
    Arena/        ArenaShape: the arena's exact math shape (walls, curved ramps, goals)
    Physics/      BallSim (ball physics), CarPhysics (car handling), HitModel (car-ball hits)
    Match/        MatchState (score/clock/phase), HitValidation (anti-cheat checks for hits), Replay (replay timing)
    Bots/         BotBrain (bot decisions)
    Cars/         CarModelBuilder (car looks at every evolution stage), CarDriver (connects CarPhysics to a car)
    Ball/         BallModelBuilder (the ball's look)
    Build/        PartKit (part helpers), Palette (colours)
    Net/          Remotes
  server/   (ServerScriptService.Server)
    Arena/        ArenaBuilder (pitch, walls, goals), StadiumBuilder (stands, crowd, roof, screens),
                  LobbyBuilder (VIP deck), EnvironmentBuilder (terrain, trees)
    Services/     MatchService (menu -> queue -> match loop), BallService, CarService, BotService,
                  StatsService, BoostPadService, BumpService, ItemService (item boxes), PowerService
                  (using items and powers, cheese and banana traps), DailyService (streaks, quests, chest),
                  DataService (saving), GarageService
  client/   (StarterPlayerScripts.Client)
    Showroom/     ShowroomBuilder (the menu's garage showroom and its mirror-floor reflection),
                  PodiumBuilder (the winners' podium)
    Controllers/  GameFlow (menu / garage / match), ReplayController (goal replays), PodiumController,
                  TwistController (twist rules and the Neon Night sky on this screen),
                  LocalHide (hides real cars behind replays), InputController, CarController, CarVisuals (wheels,
                  trails), BallView, CameraController, EffectsController, PowerVisuals (item boxes,
                  shields, ice, beams), ShowroomController, StadiumController (live scoreboards, LED boards,
                  cheering crowd)
    UI/           MainMenu, Garage, PauseMenu, HowToPlay, HUD, Announcer, ResultsScreen, ReplayScreen,
                  DailyRewards (streak and chest pop-ups), CollectionBook, TouchControls, Transition, Theme
tests/      Lune unit tests (run outside Roblox)
tools/      Offline previews of the 3D world and the UI
```

- **The ball doesn't use Roblox physics.** `BallSim` is a small deterministic simulation against the exact arena
  shape. The server runs the real ball and streams it to everyone about 30 times a second, and each client runs
  the same simulation in between so it stays smooth.
- **Your own hits feel instant.** Your client applies a touch the moment it happens and tells the server, which
  checks it (`HitValidation`), rewinds the ball to that moment, applies the hit and fast-forwards. Bots' hits
  are handled on the server.
- **Cars** use arcade raycast suspension (`CarPhysics`). Each player's client drives their own car. Bots run
  the same code on the server.
- **Twists change shared numbers only.** The server picks the twist and puts it in the `Twist` attribute; the
  server and every client then swap in the same changed ball and car settings (`Twists.ballConfig` /
  `carConfig`), so the ball's prediction and each player's own car stay in step with the server.
- **Items and powers are decided by the server** (`PowerService`), which then tells each car's driver what
  happened to it (spun out, slowed, frozen). Magnets and Tractor Beams pull the ball with the same maths on the
  server and in every client's prediction of it, so the ball stays smooth.
- **Saving** uses a session lock so two servers can't overwrite each other.
- **Menus and matches:** each player has a `Status` attribute (`Menu`, `Queued` or `Playing`) set by
  `MatchService`; the client's `GameFlow` shows the menu, the garage or the match to match it, fading through
  black when it switches between the showroom and the stadium.
- **The showroom's shiny floor** is a mirror trick: everything in the room is built a second time, upside down,
  under a see-through dark floor.

## What's next

Ideas from the design, roughly in order:

1. Daily missions with a "pick 1 of 3" reward chest (predictable, not gambling).
2. Collectible goal celebrations ("Show Off").
3. Short, predictable arena events such as low gravity, ice, or a tornado.
4. A bigger lobby hub with a practice area, mini-games and secrets.
5. Seasons (Spaceball, Dinosaurs, Pirates, Candy...) with new arenas and cars.
6. Car fusion (Shark + Lightning = Storm Shark).

## Known limitations

- This version was built and checked outside Roblox: unit tests, a simulated bot match, the Roblox type checker,
  a Rojo build, and the offline previews above. It hasn't been play-tested in Studio yet, so expect some tuning
  (car feel, bot difficulty, UI sizes, lighting) after the first real session.
- Other players' hits reach you after a short network delay (standard for online games). Your own hits are instant.
- Sounds are Roblox's built-in placeholders.
- Everything is built from Roblox's basic parts (no uploaded 3D models or textures), which is why the cars and
  stadium have a clean "low-poly" look. The next big visual step would be custom meshes and textures made in
  Blender and uploaded to Roblox. Also: Roblox shows its best lighting, shadows and glow only at high graphics
  quality (Esc → Settings → Graphics Quality).
