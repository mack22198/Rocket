# Turbo Ball

A Roblox 3v3 car soccer game built for kids: drive a silly car, hit a giant ball, and there's always a
new car you're *almost* ready to unlock.

This is the **first playable version** (the "vertical slice" from the design): the goal is to find out whether
a kid who finishes one match immediately wants to play another. "Turbo Ball" is a working title; change
`GameName` in [`GameConfig.luau`](src/shared/Config/GameConfig.luau) to rename it.

## What's in it

- **3v3 matches, 5 minutes long.** Bots fill any empty seats, so one kid alone still gets a full game. Players who
  join mid-match take over a bot's seat right away.
- **Car soccer:** a curved-wall arena with glowing goals, boost pads, kickoff countdowns, a scoreboard and clock,
  a play-on-at-0:00 rule, and golden-goal overtime.
- **Arcade driving:** boost, jump, double jump, flips (dodges), air control and air roll, driving up the curved
  walls, and bumping other cars.
- **Mega Shot:** touching the ball, making saves and doing style moves fills a meter. When it's full, press
  F to arm it and your next hit blasts the ball on fire. It's earned in the match, never bought.
- **Style and combos:** air hits, wall hits, passes and Mega Shots chain into combo goals ("🔥 3X COMBO!").
  Saves, style moves and MVP are all announced.
- **Rewards:** everyone earns **Scrap** every match (more for winning, goals, saves and style). Scrap is the
  only currency and there are no loot boxes.
- **6 collectible cars:** Pizza Car (starter), Banana Car, Tiny Kart, Neon Shark, Monster Truck and UFO. Each has
  real strengths and weaknesses, and rarity never means "better".
- **Garage:** spinning 3D previews, stats, prices and unlock/equip. A car showroom in the lobby plus an
  "X more Scrap to unlock" bar on the results screen keep the next goal in sight.
- **Works on computer, gamepad and phone/tablet** (on-screen stick and buttons).
- **Progress saves** with DataStores (once the game is published).

## Play it in Roblox Studio

1. Install [Roblox Studio](https://create.roblox.com/) (free).
2. Get the game file `TurboBall.rbxlx`:
   - Every push to this repo builds it automatically: open the **Actions** tab on GitHub, click the latest
     green run, and download **TurboBall-place** under *Artifacts* (it's a zip; unzip it).
   - Or build it yourself (see [Working on the code](#working-on-the-code)).
3. Double-click `TurboBall.rbxlx` to open it in Studio (or **File → Open from File**).
4. Press **Play** (F5). You spawn on the viewing deck next to the stadium. After a few seconds you're put
   into a car and the countdown starts.
5. To try it with more than one player: **Test** tab → *Clients and Servers* → choose 2+ players → **Start**.

When testing in Studio your progress isn't saved unless the place is published and API access is on (see below).
To try the garage without grinding, set `StudioStartingScrap` in `GameConfig.luau`, e.g. to `5000`.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Drive / brake / reverse | W / S (or arrows) | RT / LT (or left stick) | Stick (left side) |
| Steer | A / D | Left stick | Stick |
| Jump (twice to double jump, jump + direction to flip) | Space or right mouse | A | JUMP |
| Boost | Shift or left mouse | B | BOOST |
| Mega Shot (when the meter is full) | F | X | MEGA |
| Ball cam on/off | C | Y | CAM |
| Air roll | Q / E | LB / RB | |
| In the air: tip the nose | W / S | Left stick | Stick |

## Publishing to Roblox

1. In Studio: **File → Publish to Roblox**.
2. **Game Settings → Places:** set *Max Players* to 6 for pure 3v3 (extra players watch from the deck and join
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

Car looks are built from plain parts in [`CarModelBuilder.luau`](src/shared/Cars/CarModelBuilder.luau), so new
cars need no uploaded models. Sounds use Roblox's built-in ones; to add a goal horn or crowd cheer, paste audio
IDs from the Creator Store into `SOUNDS` in
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

## How it's built

```
src/
  shared/   (ReplicatedStorage.Shared: used by both server and client)
    Config/       GameConfig, CarCatalog, Rewards
    Arena/        ArenaShape: the arena's exact math shape (walls, curved ramps, goals)
    Physics/      BallSim (ball physics), CarPhysics (car handling), HitModel (car-ball hits)
    Match/        MatchState (score/clock/phase), HitValidation (anti-cheat checks for hits)
    Bots/         BotBrain (bot decisions)
    Cars/         CarModelBuilder (car looks), CarDriver (connects CarPhysics to a real car)
    Net/          Remotes
  server/   (ServerScriptService.Server)
    Arena/        ArenaBuilder, LobbyBuilder: build the stadium and lobby when the server starts
    Services/     MatchService (the game loop), BallService, CarService, BotService, StatsService,
                  BoostPadService, BumpService, DataService (saving), GarageService
  client/   (StarterPlayerScripts.Client)
    Controllers/  InputController, CarController, BallView, CameraController, EffectsController
    UI/           HUD, Announcer, ResultsScreen, Garage, TouchControls, Theme
tests/      Lune unit tests (run outside Roblox)
```

- **The ball doesn't use Roblox physics.** `BallSim` is a small deterministic simulation against the exact arena
  shape. The server runs the real ball and streams it to everyone about 30 times a second, and each client runs
  the same simulation in between so it stays smooth.
- **Your own hits feel instant.** Your client applies a touch the moment it happens and tells the server, which
  checks it (`HitValidation`), rewinds the ball to that moment, applies the hit and fast-forwards. Bots' hits
  are handled on the server.
- **Cars** use arcade raycast suspension (`CarPhysics`). Each player's client drives their own car. Bots run
  the same code on the server.
- **Saving** uses a session lock so two servers can't overwrite each other.

## What's next

Ideas from the design, roughly in order:

1. Daily missions with a "pick 1 of 3" reward chest (predictable, not gambling).
2. Car evolutions, e.g. Pizza Car → Burnt → Lava → Galaxy Pizza.
3. Collectible goal celebrations ("Show Off").
4. Short, predictable arena events such as low gravity, ice, or a tornado.
5. A bigger lobby hub with a practice area, mini-games and secrets.
6. Seasons (Spaceball, Dinosaurs, Pirates, Candy...) with new arenas and cars.
7. Car fusion (Shark + Lightning = Storm Shark).

## Known limitations

- This first version was built and checked outside Roblox: unit tests, a simulated bot match, the Roblox
  type checker and a Rojo build. It hasn't been play-tested in Studio yet, so expect some tuning
  (car feel, bot difficulty, UI sizes) after the first real session.
- Other players' hits reach you after a short network delay (standard for online games). Your own hits are instant.
- Sounds are Roblox's built-in placeholders.
