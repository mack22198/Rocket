--!strict
-- Quick chat: a handful of friendly phrases anyone can send in a match ("Nice shot!", "What a save!", "GG!"),
-- shown in a bubble over their car and in the feed. There's no typing, so nobody can say anything unkind, and
-- players whose Roblox settings don't allow chat neither send nor see them (see QuickChatService). Bots join in
-- now and then, so a match with bots doesn't feel empty.

local QuickChat = {}

export type Phrase = { Id: string, Emoji: string, Text: string }

-- In order: keys 1-8 send these.
QuickChat.Phrases = {
	{ Id = "niceshot", Emoji = "👏", Text = "Nice shot!" },
	{ Id = "save", Emoji = "🧤", Text = "What a save!" },
	{ Id = "mine", Emoji = "🙋", Text = "I got it!" },
	{ Id = "pass", Emoji = "🤝", Text = "Great pass!" },
	{ Id = "shoot", Emoji = "🎯", Text = "Take the shot!" },
	{ Id = "wow", Emoji = "😮", Text = "Wow!" },
	{ Id = "oops", Emoji = "😅", Text = "Oops!" },
	{ Id = "gg", Emoji = "🏆", Text = "GG!" },
} :: { Phrase }

-- Gamepad D-pad shortcuts (the D-pad's up is the horn).
QuickChat.Gamepad = { Left = "niceshot", Right = "mine", Down = "gg" }

QuickChat.Burst = 3 -- at most this many messages...
QuickChat.Window = 8 -- ...in this many seconds,
QuickChat.Gap = 1 -- and at least this long between two
QuickChat.BubbleTime = 2.5 -- seconds a bubble stays over the car

-- What bots say when something happens, and how likely they are to say it (only one bot speaks at a time).
export type BotLine = { Chance: number, Phrases: { string } }
QuickChat.BotLines = {
	goal = { Chance = 0.5, Phrases = { "niceshot", "wow" } }, -- a team-mate scored
	conceded = { Chance = 0.25, Phrases = { "oops", "wow" } }, -- the other team scored
	save = { Chance = 0.35, Phrases = { "save" } }, -- a team-mate made a save
} :: { [string]: BotLine }

local indexById: { [string]: number } = {}
for index, phrase in QuickChat.Phrases do
	indexById[phrase.Id] = index
end

function QuickChat.phrase(index: number): Phrase?
	return QuickChat.Phrases[index]
end

function QuickChat.indexOf(id: string): number?
	return indexById[id]
end

-- Can someone who sent messages at the times in `history` send another one at `now`? If so, `now` is added to
-- their history. (Old times are dropped as it goes, so the history stays short.) The server allows `leeway`
-- seconds for messages that bunched up on the way.
function QuickChat.allow(history: { number }, now: number, leeway: number?): boolean
	local slack = leeway or 0
	for i = #history, 1, -1 do
		if now - history[i] >= QuickChat.Window - slack then
			table.remove(history, i)
		end
	end
	local latest = history[#history]
	if (latest and now - latest < QuickChat.Gap - slack) or #history >= QuickChat.Burst then
		return false
	end
	table.insert(history, now)
	return true
end

-- What a bot says about `event` ("goal", "conceded", "save"), if anything. `roll` and `pick` are random numbers
-- in [0, 1).
function QuickChat.botLine(event: string, roll: number, pick: number): number?
	local line = QuickChat.BotLines[event]
	if not line or roll >= line.Chance or #line.Phrases == 0 then
		return nil
	end
	local id = line.Phrases[math.clamp(math.floor(pick * #line.Phrases) + 1, 1, #line.Phrases)]
	return indexById[id]
end

return QuickChat
