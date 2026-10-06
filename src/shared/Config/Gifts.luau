--!strict
-- Playtime gifts: free gifts that unlock the longer you play in one visit (3 minutes, 6, 10...). Every prize is
-- shown up front - nothing random - and the ladder starts again next time you join.

local Gifts = {}

export type Gift = {
	Minutes: number, -- playing time in this visit before it can be opened
	Kind: string, -- "scrap" or "boost" (matches of double Scrap)
	Amount: number,
}

Gifts.Ladder = {
	{ Minutes = 3, Kind = "scrap", Amount = 50 },
	{ Minutes = 6, Kind = "scrap", Amount = 75 },
	{ Minutes = 10, Kind = "scrap", Amount = 100 },
	{ Minutes = 15, Kind = "boost", Amount = 2 },
	{ Minutes = 20, Kind = "scrap", Amount = 150 },
	{ Minutes = 30, Kind = "scrap", Amount = 250 },
	{ Minutes = 45, Kind = "boost", Amount = 3 },
	{ Minutes = 60, Kind = "scrap", Amount = 500 },
} :: { Gift }

-- (emoji, short text) for a gift, e.g. ("🔩", "100 Scrap").
function Gifts.describe(gift: Gift): (string, string)
	if gift.Kind == "boost" then
		return "🚀", `Double Scrap x{gift.Amount}`
	end
	return "🔩", `{gift.Amount} Scrap`
end

-- Can gift `index` be opened after `seconds` of playing, if these are already `opened`?
function Gifts.ready(index: number, seconds: number, opened: { [number]: boolean }): boolean
	local gift = Gifts.Ladder[index]
	return gift ~= nil and not opened[index] and seconds >= gift.Minutes * 60
end

-- How many gifts are waiting to be opened.
function Gifts.readyCount(seconds: number, opened: { [number]: boolean }): number
	local count = 0
	for index in Gifts.Ladder do
		if Gifts.ready(index, seconds, opened) then
			count += 1
		end
	end
	return count
end

-- Seconds until the next gift that isn't ready yet (nil when they're all ready or opened).
function Gifts.nextIn(seconds: number, opened: { [number]: boolean }): number?
	for index, gift in Gifts.Ladder do
		if not opened[index] and seconds < gift.Minutes * 60 then
			return gift.Minutes * 60 - seconds
		end
	end
	return nil
end

return Gifts
