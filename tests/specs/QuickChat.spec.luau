-- Quick chat: only the preset phrases, keys and D-pad shortcuts point at real phrases, nobody can flood the
-- chat, and bots only ever say something that fits.
local QuickChat = require(Shared.Config.QuickChat)

return function(t)
	local expect = t.expect

	t.test("every phrase is short, friendly and listed once", function()
		local seen: { [string]: boolean } = {}
		for index, phrase in QuickChat.Phrases do
			expect.falsy(seen[phrase.Id], `{phrase.Id} is listed twice`)
			seen[phrase.Id] = true
			expect.equal(QuickChat.indexOf(phrase.Id), index)
			expect.truthy(QuickChat.phrase(index) == phrase)
			expect.truthy(#phrase.Text > 0 and #phrase.Text <= 16, `{phrase.Id} fits in a bubble`)
			expect.truthy(phrase.Emoji ~= "")
		end
		expect.atMost(#QuickChat.Phrases, 8, "keys 1-8 cover every phrase")
		expect.equal(QuickChat.phrase(0), nil)
		expect.equal(QuickChat.phrase(#QuickChat.Phrases + 1), nil)
		for _, id in { QuickChat.Gamepad.Left, QuickChat.Gamepad.Right, QuickChat.Gamepad.Down } do
			expect.truthy(QuickChat.indexOf(id) ~= nil, `the D-pad's {id} is a phrase`)
		end
	end)

	t.test("nobody can flood the chat", function()
		local history: { number } = {}
		expect.truthy(QuickChat.allow(history, 100))
		expect.falsy(QuickChat.allow(history, 100 + QuickChat.Gap / 2), "too soon after the last one")
		expect.truthy(QuickChat.allow(history, 100 + QuickChat.Gap))
		expect.truthy(QuickChat.allow(history, 100 + QuickChat.Gap * 2))
		expect.equal(QuickChat.Burst, 3)
		expect.falsy(QuickChat.allow(history, 100 + QuickChat.Gap * 3), "a burst of three is the most")
		expect.truthy(QuickChat.allow(history, 100 + QuickChat.Window + 0.01), "the window moves on")
		expect.atMost(#history, QuickChat.Burst, "old messages are forgotten")
	end)

	t.test("the server allows for messages bunching up on the way", function()
		local history: { number } = {}
		expect.truthy(QuickChat.allow(history, 50, 0.3))
		expect.truthy(QuickChat.allow(history, 50 + QuickChat.Gap - 0.2, 0.3))
		expect.falsy(QuickChat.allow(history, 50 + QuickChat.Gap - 0.2 + 0.5, 0.3))
	end)

	t.test("bots say things that fit, and not always", function()
		for event, line in QuickChat.BotLines do
			expect.truthy(line.Chance > 0 and line.Chance < 1, `{event} isn't every time`)
			for _, id in line.Phrases do
				expect.truthy(QuickChat.indexOf(id) ~= nil, `{event}: {id} is a phrase`)
			end
			expect.equal(QuickChat.botLine(event, line.Chance, 0), nil, "a high roll says nothing")
			local said = QuickChat.botLine(event, 0, 0.99)
			assert(said)
			expect.truthy(table.find(line.Phrases, (QuickChat.phrase(said) :: QuickChat.Phrase).Id) ~= nil)
		end
		expect.equal(QuickChat.botLine("nothing", 0, 0), nil)
		expect.equal(QuickChat.phrase(QuickChat.botLine("save", 0, 0) :: number), QuickChat.phrase(2))
	end)
end
