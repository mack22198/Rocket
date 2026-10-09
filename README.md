# Turbo Ball

A Roblox 2v2 car soccer game built for kids: drive a silly car, hit a giant ball, and there's always a
new car you're *almost* ready to unlock.

This is the **first playable version** (the "vertical slice" from the design): the goal is to find out whether
a kid who finishes one match immediately wants to play another. "Turbo Ball" is a working title; change
`GameName` in [`GameConfig.luau`](src/shared/Config/GameConfig.luau) to rename it.

## What's in it

- **A main menu in a 3D garage showroom.** You start in the menu, not in a match: your car turns on a glowing
  turntable in a dark studio with a polished, reflective floor, spotlights and a big screen. From there: **PLAY**,
  **GARAGE** and **HOW TO PLAY**. After a match you pick **PLAY AGAIN**, **GARAGE** or **MENU**, and the ☰ MENU
  button (or M) lets you leave a match at any time.
- **2v2 matches, 3 minutes long, fun alone.** Bots fill any empty seats, so one kid alone still gets a full game.
  Players team up: two play together against bots (only more than that are split between the teams),
  and someone pressing PLAY mid-match takes over a bot on their team. Bot team-mates play *for* you - they leave
  the ball to you and pass it up to you - and the bots you play against ease off while you're behind (and for
  your first few matches) and push harder while you're ahead, so matches stay close. Bots play under made-up
  usernames (a different set every match, from [`BotNames.luau`](src/shared/Config/BotNames.luau)) with levels
  and titles, so a match with bots in it feels like a match with other kids.
- **Simple to play:** there are only three things to do - drive, jump and set off your **ultimate** - so the
  only buttons are JUMP and ULT (E on a keyboard). No boost to manage, nothing to pick up and juggle.
- **Car soccer:** a roomy curved-wall arena with glowing goals and nets, kickoff countdowns, a scoreboard and clock, a
  play-on-at-0:00 rule, and golden-goal overtime.
- **A real stadium:** team-coloured stands packed with fans (who jump when someone scores and do Mexican waves),
  scrolling LED advert boards that flash team colours after a goal, the game's name painted on the pitch, glass
  walls, floodlights and giant screens showing the live score, under a late-afternoon sky with hills and trees.
- **Big moments look big:** every goal sets off a shockwave, a fireball and smoke in the net, confetti over the
  goal and fireworks above the stands, then a **slow-motion replay** of the goal (with cinema bars and the
  scorer's name; SKIP to get back to driving). Hard hits flash, Mega Shots explode, dashing cars stream light
  trails and the camera widens as you go faster.
- **The winners' podium:** at the final whistle the top three cars appear on a podium in the middle of the
  pitch - the MVP on the top step - with confetti and fireworks, before the results screen.
- **Arcade driving:** quick cars, jump, double jump, flips (dodges), air control, driving up the curved walls, and
  bumping other cars. The ball is big (about as wide as a car is long) and the goals are wide, so
  it's easy to hit and easy to score.
- **Driving help (on by default),** so a keyboard is all you need: steering keys ease in, so a tap of A or D is
  a nudge, not a swerve; while you hold W with the ball ahead, the car steers itself toward the spot that knocks
  the ball at the other team's goal (your own steering always wins); your hits bend part of the way toward the
  goal; jumping near a ball in the air leans the jump toward it and the second jump flips into it; and holding
  W in the air keeps the car level instead of tipping it over. Players who want full control switch it off in
  the match menu (☰ MENU → DRIVING HELP); it's remembered.
- **Demolitions:** smash into the other team on a Tiny Kart's **Nitro Rocket** and their car goes **POOF** - a
  cartoon cloud, stars and toy-car bits flying everywhere - then pops back in at its own goal two seconds later. Each one is worth a
  little Scrap (and there's a daily quest for it). Bots never demolish players in their first five matches.
- **Every car has its own ultimate**, like the big moves in hero shooters: the Pizza Car floods the pitch all
  around it with gooey **Cheese**, the Banana Car throws a **Banana Storm** of peels out in front, the Tiny Kart
  fires off a **Nitro Rocket** (the only way to demolish a car), the Neon Shark does a **Shark Dive** that makes
  it untouchable, the Monster Truck leaps up and comes down in a **Ground Pound** shockwave, the UFO's **Tractor
  Beam** grabs the ball from far away and lifts it up for the perfect shot, the Taco Truck catches fire with
  **Hot Sauce** (your next hit is a flaming Mega Shot), the Rubber Duck lets out a **Quack Attack** that spins out
  everyone nearby, and the Hot Dog squirts a **Ketchup Slick** out in front. Fused cars get a **combo** of both
  their parents' ultimates.
- **Ultimates are made to be seen:** when you set yours off, the screen flashes its colour, its name bursts
  onto the screen and the camera kicks; your car glows while it lasts, and everything it does happens where
  your camera is looking - the cheese floods out from under you, the peels fly through the air and land ahead
  of you, the ketchup squirts forward. Everyone else gets a popup ("TurboTaco9: CHEESE FLOOD!") so they see it
  coming, and cars stuck in the cheese drip with it.
- **The ultimate meter fills mostly from playing:** every touch of the ball (once a second at most), air and wall
  hits, shots, saves, goals, assists, big bumps and the charge orb. It only creeps up by itself (faster for a
  team that's behind), so everyone's is ready at a different moment - and each car's fills at its own pace.
  When it's full the meter glows and one press (E, X or ULT) sets it off.
- **The charge orb:** every so often one glowing orb appears somewhere on the halfway line, under a beam of
  light with a "ULT +30%" tag. Whoever drives through it first gets a big chunk of ultimate charge. There's only
  ever one, so the pitch stays clear and it's always a race.
- **Match twists:** most matches start with a surprise rule for the whole match - 🏀 **Giant Ball**, 🌙 **Low
  Gravity**, 🏐 **Bouncy Ball**, ⛸️ **Ice Rink**, ⚡ **Speed Demons** (every car is faster), 💥 **Ultimate Rush**
  (ultimates charge three times as fast) or 🌃 **Neon Night**. Each week one twist is featured, and every Saturday and Sunday is a **Twist Weekend**: a
  twist in every match and +50% Scrap.
- **Style and combos:** air hits, wall hits, passes and Mega Shots chain into combo goals ("3X COMBO!").
  Saves, style moves and MVP are all announced.
- **Player levels:** every match earns level XP (as much as the Scrap you win) and every level pays Scrap with
  a big LEVEL UP! card. The first match takes you to level 2 and the early levels come quickly; there's no top
  level. Your level shows over your car for everyone to see.
- **Win streaks:** win matches in a row for more and more Scrap (+10% for 2 wins in a row, up to +50%). A draw
  keeps the streak going.
- **Achievements and titles:** 25 achievements ("Make 25 saves", "Score a hat trick", "Win after being 2 goals
  behind", "Fuse a car"...) each pay Scrap once, and many unlock a **title** (🧱 Brick Wall, 💥 Wrecking Ball,
  🎩 Hat Trick Hero...) to wear under your name - so do levels 5, 10, 20, 30 and 50. Tap your card in the menu
  for your profile: your stats, every achievement with how close you are, and the titles to choose from. Each
  achievement can also award a Roblox badge (see *Publishing*).
- **Playtime gifts:** free gifts that unlock the longer you play in one visit (3, 6, 10, 15, 20, 30, 45 and 60
  minutes) - Scrap and double-Scrap matches, every prize shown up front. The 🎁 GIFTS button shows how many are
  waiting.
- **Weekly leaderboard:** 🏆 TOP 50 shows this week's best drivers by Scrap won in matches (and your own
  score); everyone starts again on Monday. It needs DataStores, so it fills in once the game is published.
- **Invite friends:** 👋 INVITE opens Roblox's invite window. Playing in the same match as a friend pays +25%
  Scrap, and the first time is an achievement.
- **A Robux shop:** Scrap packs, a Gold Season Pass and VIP (see *Making money*). Everything in it can also be
  earned by playing, nothing is random, and it reminds kids to ask a grown-up first.
- **Rewards:** everyone earns **Scrap** every match (more for winning, goals, saves and style, and +25% when one
  of your Roblox friends is in the match too). Scrap is the only currency and there are no loot boxes.
- **Seasons:** a free reward track that changes every six weeks, starting with 🍔 **Season 1: Food Fight**. Every
  match earns season XP (as much as the Scrap you win), and each of the 20 tiers pays out the moment you reach it:
  Scrap, matches of double Scrap, and season-only style - a 🎺 fanfare horn, a 🌈 rainbow goal party and a 👑
  Golden Crown at the end. The optional **Gold Season Pass** adds a gold reward to every tier (with gold-only
  style: a 📣 Stadium Air Horn, a 🪙 Gold Rush goal party and a 🏆 Gold Trophy hat). The menu shows your tier,
  what's next and the days left, and the whole track (free and gold) is one tap away.
- **Daily reasons to come back:** a **login streak** (more Scrap every day in a row, up to day 7), **three daily
  quests** ("Score 2 goals", "Grab 2 charge orbs"...) and a **daily chest** once they're done - its three prizes are
  shown face up and you pick one (Scrap, XP for your car, or double Scrap for a few matches). Nothing is random
  or hidden.
- **Collectible style:** hats for your car's roof (🧢 🥳 🚧 🎩 🐣 🦄, and a 👑 from the season track), horns to
  honk in a match (H), and goal parties that go off when YOU score - fireworks, a confetti storm, a star shower,
  duck rain, a taco party or a rainbow. All in the garage's STYLE tab at fixed prices; only looks and sounds.
- **Collection book:** every car at every evolution stage, plus every hat, horn and goal party, with black
  mystery silhouettes for the ones you haven't got yet.
- **9 collectible cars:** a pizza delivery hot hatch (the starter), a banana roadster, a go-kart, a rubber
  duck, a shark supercar, a taco food truck (with a giant taco on the roof), a monster truck, a hot dog and a
  UFO. They're proper little battle-cars - spoked wheels that roll and steer, light bars and spoilers - each with
  real strengths and weaknesses. Rarity never means "better".
- **Car fusion:** own two cars that go together and you can fuse them into a new one for 🔩1,000 (you keep both):
  🦈 **Pizza Shark** (Neon Shark + Pizza Car: a cheese shark covered in pepperoni with a pizza-slice fin, whose
  **Cheesy Dive** dives and drops a Cheese Trap), 🛸 **Duck Saucer** (UFO + Rubber Duck: a rubber duck flying the
  saucer, with a **Quack Beam**) and 🛻 **Monster Taco** (Monster Truck + Taco Truck: a giant taco in the back,
  and a **Spicy Pound**). Fused cars sit halfway between their parents' stats and evolve like any other car.
- **Car evolutions:** every car earns XP while you drive it (as much as the Scrap you win) and evolves through
  four looks, e.g. Pizza Car → Burnt Pizza Car → Lava Pizza Car → Galaxy Pizza Car. Evolving is earned by playing,
  never bought, and only changes looks. You can switch back to any look you've unlocked, and bots sometimes
  drive evolved cars to show what's possible.
- **Garage:** your cars on the left, the chosen car big on the showroom turntable (drag to spin it), and its stats,
  price and evolution track on the right, with an EVOLVE! button that sets off a light show (and a 🧬 FUSE
  button for fused cars). The menu's "saving
  up for" card and the results screen keep the next goal in sight.
- **Quick chat:** eight friendly phrases (👏 Nice shot!, 🧤 What a save!, 🙋 I got it!, 🏆 GG!...) from the 💬
  CHAT button, keys 1-8 (T opens the list) or the gamepad's D-pad. They pop up in a speech bubble over your car
  and in the feed. There's no typing, so nobody can say anything unkind; it can't be spammed; and players whose
  Roblox settings don't allow chat neither send nor see it. Bots chat too, now and then, after goals and saves.
- **A coach for new players:** during your first three matches, one short tip at a time pops up when it's useful
  ("Your Cheese Flood is ready! Press E!", "Press SPACE to jump!" when the ball's in the air, "Grab the glowing
  orb!"), with the buttons for whatever you're playing on, and each only until you've done it.
- **Works on computer, gamepad and phone/tablet.** On touch screens you drag your thumb toward where you want to
  go on the screen and the car drives there (easy steering - it can be switched off in the match menu). There are
  just two big buttons, JUMP and ULT (which fills up like the meter and glows when it's ready), and the car
  levels itself out in the air so it lands on its wheels.
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

### Smooth car bodies (one-time import, recommended)

The cars' bodies have smooth versions made in Blender (rounded panels, curved fenders, a proper rubber duck...),
every wheel gets a treaded tyre, and the ball gets crisp pentagons and stitching like a real soccer ball.
Roblox only lets meshes into a game through Studio, so this takes one import:

1. Download [`assets/meshes/TurboBallCars.fbx`](assets/meshes/TurboBallCars.fbx) from this repo.
2. In Studio, open the place, then **Home** tab → **Import 3D** (or **File → Import 3D**) and pick the file.
   Leave the settings as they are (don't turn on *Merge Meshes*) and click **Import**. A model called
   `TurboBallCars` appears in the Workspace: a row of car bodies.
3. **File → Save** (or publish). That's it - when the game starts it moves the meshes into ReplicatedStorage
   and every car uses them. The Output window says `Smooth car meshes found.`

Until then (or if something's missing) the cars are built from plain parts, exactly as before. If the meshes are
ever remade (see [tools/meshes](tools/meshes)), delete the old `TurboBallCars` and import the new file.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Drive / brake / reverse | W / S (or arrows) | RT / LT (or left stick) | Drag toward where you want to go |
| Steer | A / D | Left stick | (the same drag) |
| Jump (twice to double jump, jump + direction to flip) | Space or right mouse | A | JUMP |
| Ultimate (when the meter is full) | E (Q, F, R and G work too) | X (B, RB and LB work too) | ULT |
| Horn | H | D-pad up | HORN |
| Quick chat | T (the list), 1-8 (say one) | D-pad left / right / down | 💬 CHAT |
| Ball cam on/off | C | Y | CAM |
| In the air: tip the nose | W / S | Left stick | Stick |
| Match menu (leave the match, driving help) | M | View / Back | ☰ MENU |

Driving help (see above) is on for every new player; ☰ MENU → DRIVING HELP switches it off and on.

## Publishing to Roblox

1. In Studio: **File → Publish to Roblox**.
2. **Game Settings → Places:** set *Max Players* to 4 for pure 2v2 (extra players wait in the menu and join
   when a seat opens). The team size is `Match.TeamSize` in `GameConfig.luau`, if you ever want 3v3 back.
3. **Game Settings → Security:** turn on *Enable Studio Access to API Services* so saving also works when
   testing in Studio.
4. Players' Scrap, cars and stats are saved automatically in the live game.
5. **Badges (optional):** every achievement can award a Roblox badge, which shows on players' Roblox profiles.
   On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open the game → *Engagement →
   Badges* → *Create a Badge* (a few a day are free), then paste the badge's ID as `Badge = <id>` on that
   achievement in [`Achievements.luau`](src/shared/Config/Achievements.luau) (`WelcomeBadge` is given to
   everyone the first time they play).

## Making money (Robux)

The shop (🛒 SHOP in the menu) sells, for Robux:

| Item | Kind | Suggested price | What you get |
| --- | --- | --- | --- |
| Bag / Box / Crate / Truckload of Scrap | Developer Products | 49 / 99 / 199 / 449 | 1,000 / 2,500 / 6,000 / 15,000 Scrap (bigger packs are better value) |
| Gold Season Pass | Developer Product (once per season) | 399 | A gold reward on every season tier: 4,800 more Scrap, 14 Double Scrap matches and 3 gold-only items; tiers already reached pay out at once |
| VIP | Game Pass (forever) | 249 | +20% Scrap every match, the 💎 Diamond Crown hat, the 💎 VIP title and a 💎 by your name |

Roblox Premium members also get +10% Scrap every match (free), and Roblox pays you **Premium Payouts** for the
time Premium members spend in the game. Nothing in the shop is random and everything can also be earned by
playing. To switch it on:

1. Publish the game, then open it on the [Creator Dashboard](https://create.roblox.com/dashboard/creations).
2. **Monetization → Developer Products → Create a Developer Product** for each of the five products above
   (name, price, an icon). Copy each product's ID into `ProductId` in
   [`src/shared/Config/Shop.luau`](src/shared/Config/Shop.luau). The Gold Season Pass is one product for every
   season.
3. **Monetization → Passes → Create a Pass** called VIP, put it on sale, and copy its ID into `Shop.Vip.PassId`.
4. **Monetization → Private Servers:** turn them on and pick a monthly price (100 Robux is common) - friends
   and families can then have their own server.
5. Build, publish again. The shop shows Roblox's real prices once the IDs are in.

Until an item has an ID it shows "Coming soon" in the live game, and in Studio pressing BUY simply hands it over
(nothing is charged) so you can try everything. Products that are set up open Roblox's test purchase window in
Studio. Every purchase is saved with the player's progress before Roblox is told it's done, so a purchase is never
lost or given twice.

## Changing the game

Almost everything is a number in [`src/shared/Config/`](src/shared/Config):

- [`GameConfig.luau`](src/shared/Config/GameConfig.luau): team size, match length, arena and goal size (the
  stands, the VIP deck and the scenery all move to fit), ball size and bounciness, car speed, jump height,
  gravity, bot skill, how fast the ultimate meter fills and what charges it (`Ultimate`), the charge orb (`Orb`: how often, where, how long it stays), how much hits bend
  toward the goal with driving help (`Hit.ShotAssist`) and Studio shortcuts.
- [`DriveAssist.luau`](src/shared/Cars/DriveAssist.luau): how strong the rest of the driving help is (keyboard
  steering, aim assist, jump assist).
- `CarCatalog.Scale`: how big the cars are built (1.2x their design).
- [`CarCatalog.luau`](src/shared/Config/CarCatalog.luau): the cars, prices and stats, and the fusion recipes.
- [`Rewards.luau`](src/shared/Config/Rewards.luau): how much Scrap each thing is worth.
- [`Sounds.luau`](src/shared/Config/Sounds.luau): every sound in the game - paste Toolbox sound IDs here.
- [`Season.luau`](src/shared/Config/Season.luau): when seasons start, how much XP a tier takes, and each season's
  rewards.
- [`Powers.luau`](src/shared/Config/Powers.luau): every car's ultimate, what it does and how strong it is
  (`Tuning`), where the Banana Storm's peels land, and how fast each car's meter fills (`ChargeRate`).
- [`BotNames.luau`](src/shared/Config/BotNames.luau): the made-up usernames bots play under.
- [`Daily.luau`](src/shared/Config/Daily.luau): the streak rewards, the daily quests and the chest prizes.
- [`Twists.luau`](src/shared/Config/Twists.luau): the match twists (what each one changes and how often it
  turns up) and the weekend event.
- [`Cosmetics.luau`](src/shared/Config/Cosmetics.luau): hats, horns and goal parties, and their prices.
- `GameConfig.Evolution`: how much XP each evolution stage needs.

The screens share one look, set in [`Theme.luau`](src/client/UI/Theme.luau): cream cards and dark slabs with
thick dark outlines, chunky buttons with a lip along the bottom, one colour per job (yellow for the main button,
green for buying and "done", purple for evolving, pink for the shop), Luckiest Guy for titles and buttons and
Gotham for the rest, and no emoji in the middle of text (Scrap has its own coin).

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

### Smooth car meshes

[`tools/meshes`](tools/meshes) makes the smooth car bodies with Blender (run from Python, no Blender window
needed) straight from the car designs in `CarModelBuilder.luau`. See its [README](tools/meshes/README.md).

## How it's built

```
src/
  shared/   (ReplicatedStorage.Shared: used by both server and client)
    Config/       GameConfig, CarCatalog, Rewards, Evolution, Powers (every car's ultimate), Daily (streaks,
                  quests, daily chest), Twists (match twists and weekend events), Cosmetics (hats, horns,
                  goal parties), Season (the free season reward track), Sounds (every sound, for Toolbox IDs),
                  QuickChat (the quick chat phrases), Levels (player levels), Achievements (achievements and
                  titles), Gifts (playtime gifts), Leaderboard (the weekly leaderboard), Shop (Robux products),
                  BotNames (the bots' usernames)
    Arena/        ArenaShape: the arena's exact math shape (walls, curved ramps, goals)
    Physics/      BallSim (ball physics), CarPhysics (car handling), HitModel (car-ball hits)
    Match/        MatchState (score/clock/phase), HitValidation (anti-cheat checks for hits), Replay (replay
                  timing), Teams (who plays on which team), Demolition (when a bump is a demolition)
    Bots/         BotBrain (bot decisions)
    Cars/         CarModelBuilder (car looks at every evolution stage), CarDriver (connects CarPhysics to a car),
                  DriveAssist (driving help), EasySteer (touch steering)
    Ball/         BallModelBuilder (the ball's look)
    Build/        PartKit (part helpers), Palette (colours)
    Net/          Remotes
  server/   (ServerScriptService.Server)
    Arena/        ArenaBuilder (pitch, walls, goals), StadiumBuilder (stands, crowd, roof, screens),
                  LobbyBuilder (VIP deck), EnvironmentBuilder (terrain, trees)
    Services/     MatchService (menu -> queue -> match loop), BallService, CarService (cars and ultimate
                  meters), BotService, StatsService, BumpService, DemolitionService, OrbService (the charge
                  orb), PowerService (ultimates, and the cheese, peels and ketchup they leave behind),
                  DailyService (streaks, quests, chest),
                  SeasonService (season XP and tier rewards), ProgressService (levels, achievements, titles,
                  badges), GiftService (playtime gifts), LeaderboardService (the weekly top 50), ShopService
                  (Robux purchases, VIP, the Premium bonus),
                  QuickChatService, SettingsService (driving help on/off), DataService (saving),
                  GarageService (unlocking, fusing, evolving, style)
  client/   (StarterPlayerScripts.Client)
    Showroom/     ShowroomBuilder (the menu's garage showroom and its mirror-floor reflection),
                  PodiumBuilder (the winners' podium)
    Controllers/  GameFlow (menu / garage / match), ReplayController (goal replays), PodiumController,
                  TwistController (twist rules and the Neon Night sky on this screen),
                  LocalHide (hides cars behind replays, and demolished ones), InputController, CarController, CarVisuals (wheels,
                  trails), BallView, CameraController, EffectsController, SoundController (effects, music,
                  crowd, whistle), PowerVisuals (the charge orb, ultimates, beams), ShowroomController,
                  StadiumController (live scoreboards, LED boards, cheering crowd)
    UI/           MainMenu, Garage, PauseMenu, HowToPlay, HUD, Announcer, ResultsScreen, ReplayScreen,
                  DailyRewards (streak and chest pop-ups), CollectionBook, StylePanel (the garage's STYLE tab),
                  SeasonTrack (every tier of the season), Coach (first-match tips), QuickChatPanel (the chat
                  button, its list and the speech bubbles), ProfilePanel (stats, achievements, titles), Toasts
                  (level-up and achievement cards), GiftsPanel, LeaderboardPanel, ShopPanel, TouchControls,
                  Transition,
                  Theme
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
- **Ultimates are decided by the server** (`PowerService`), which keeps every car's meter (`CarService`) and
  tells each car's driver what happened to it (spun out, slowed). Your own Nitro Rocket or Shark Dive launches
  your car the moment you press the button, so it feels instant. The Tractor Beam pulls the ball with the same
  maths on the server and in every client's prediction of it, so the ball stays smooth.
- **Saving** uses a session lock so two servers can't overwrite each other.
- **Menus and matches:** each player has a `Status` attribute (`Menu`, `Queued` or `Playing`) set by
  `MatchService`; the client's `GameFlow` shows the menu, the garage or the match to match it, fading through
  black when it switches between the showroom and the stadium.
- **The showroom's shiny floor** is a mirror trick: everything in the room is built a second time, upside down,
  under a see-through dark floor.

## What's next

Ideas from the design, roughly in order:

1. A bigger lobby hub with a practice area, mini-games and secrets.
2. More season themes (Spaceball, Dinosaurs, Pirates, Candy...) with their own rewards, arenas and cars.
3. More fusions (Shark + Banana, Kart + Hot Dog...).

## Known limitations

- This version was built and checked outside Roblox: unit tests, a simulated bot match, the Roblox type checker,
  a Rojo build, and the offline previews above. It hasn't been play-tested in Studio yet, so expect some tuning
  (car feel, bot difficulty, UI sizes, lighting) after the first real session.
- Other players' hits reach you after a short network delay (standard for online games). Your own hits are instant.
- Sounds are Roblox's built-in placeholders, and there's no music yet. Every sound has a slot in
  [`Sounds.luau`](src/shared/Config/Sounds.luau): paste a Toolbox sound's ID there (menu music, match music, a
  crowd, a goal horn, a whistle, a cheer, an engine hum that rises with your speed, an ultimate blast...) and the game
  uses it.
- Apart from the optional smooth car bodies (above), everything is built from Roblox's basic parts, which is why
  the stadium has a clean "low-poly" look. The next visual steps would be more Blender meshes (wheels, the
  stadium, the ball) and textures. Also: Roblox shows its best lighting, shadows and glow only at high graphics
  quality (Esc → Settings → Graphics Quality).
