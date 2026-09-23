--!strict
-- A tiny event helper: signal:Connect(fn) / signal:Fire(...).

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}
	local signal = {}

	function signal.Connect(_self: Signal<T...>, callback: (T...) -> ()): Connection
		table.insert(listeners, callback)
		local connection = {}
		function connection.Disconnect(_: Connection)
			local index = table.find(listeners, callback)
			if index then
				table.remove(listeners, index)
			end
		end
		return connection :: Connection
	end

	function signal.Fire(_self: Signal<T...>, ...: T...)
		for _, callback in table.clone(listeners) do
			task.spawn(callback, ...)
		end
	end

	function signal.DisconnectAll(_self: Signal<T...>)
		table.clear(listeners)
	end

	return signal :: any
end

return Signal
