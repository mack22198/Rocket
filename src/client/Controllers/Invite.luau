--!strict
-- Inviting Roblox friends to play (Roblox shows its own invite window). Playing in the same match as a friend pays
-- +25% Scrap, and the first time is an achievement.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Invite = {}

-- Opens Roblox's invite window. Returns false and why not if this player can't send invites right now.
function Invite.prompt(): (boolean, string?)
	local player = Players.LocalPlayer
	local ok, allowed = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok or not allowed then
		return false, "Inviting friends isn't available right now."
	end
	local shown = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not shown then
		return false, "Inviting friends isn't available right now."
	end
	return true, nil
end

return Invite
