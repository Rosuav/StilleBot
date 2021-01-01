-- Install by symlinking into ~/.local/share/vlc/lua/extensions or equivalent

URL = "$$url$$?auth=$$auth$$&"

function descriptor()
	return { 
		title = "&StilleBot integration",
		version = "0.1",
		author = "Rosuav",
		capabilities = { "input-listener", "playing-listener" },
	}
end

function notify(args)
	vlc.msg.info(args)
	local s = vlc.stream(URL .. args)
	local line = s:readline() -- read a line. Return nil if EOF was reached.
	vlc.msg.info("[StilleBot] Got line: " .. line)
end

function activate()
	vlc.msg.info("[StilleBot] Activating")
	input_changed() -- Notify the bot with the current track name
end

function deactivate()
	-- NOTE: This is NOT guaranteed to send a signal when VLC closes.
	-- (Probably b/c the HTTP request is asynchronous.)
	vlc.msg.info("[StilleBot] Deactivated")
	notify("shutdown=1")
end

function input_changed()
	vlc.msg.info("[StilleBot] Seen track change")
	local item = vlc.input.item()
	if not item then
		return
	end
	-- Be paranoid. Decode, then encode, don't rely on it not breaking stuff.
	local fn = vlc.strings.decode_uri(item:uri())
	notify("now_playing=" .. vlc.strings.encode_uri_component(fn))
end

last_status = nil
function playing_changed(status)
	-- 2 is playing, 3 is paused, 4 is loading?? TODO: Find docs.
	if status ~= 4 and status ~= last_status then
		last_status = status
		vlc.msg.info("[StilleBot] Status is now " .. status)
		notify("status=" .. vlc.playlist.status())
	end
end

function meta_changed()
end
