-- Install by downloading into ~/.local/share/vlc/lua/extensions or equivalent

URL = "$$url$$?auth=$$auth$$&"
nextnotif = ""

function descriptor()
	return { 
		title = "&StilleBot integration",
		version = "0.1",
		author = "Rosuav",
		capabilities = { "input-listener", "playing-listener" },
	}
end

function notify(args)
	local s = vlc.stream(URL .. args .. nextnotif)
	nextnotif = ""
	local line = s:readline() -- read a line. Return nil if EOF was reached.
end

function activate()
	vlc.msg.info("[StilleBot] Activating")
	nextnotif = "&status=" .. vlc.playlist.status() -- On first viable track message, also say whether we're playing or not
	input_changed() -- Notify the bot with the current track name
end

function deactivate()
	-- NOTE: This is NOT guaranteed to send a signal when VLC closes.
	-- (Probably b/c the HTTP request is asynchronous.)
	vlc.msg.info("[StilleBot] Deactivated")
	notify("shutdown=1")
end

function input_changed()
	vlc.msg.dbg("[StilleBot] Seen track change")
	local item = vlc.input.item()
	if not item then
		return
	end
	-- Be paranoid. Decode, then encode, don't rely on it not breaking stuff.
	local fn = vlc.strings.decode_uri(item:uri())
	local notif = "now_playing=" .. vlc.strings.encode_uri_component(fn)
	notif = notif .. "&name=" .. vlc.strings.encode_uri_component(item:name())
	notif = notif .. "&usec=" .. vlc.var.get(vlc.object.input(), "time")
	-- TODO: Try to get more metadata out of the file
	notify(notif)
end

last_status = nil
function playing_changed(status)
	-- 2 is playing, 3 is paused, 4 is loading?? TODO: Find docs.
	-- Not sure what 1 is, but it seems to contribute to the doubled-announcement problem.
	if status ~= 1 and status ~= 4 and status ~= last_status then
		last_status = status
		vlc.msg.dbg("[StilleBot] Status is now " .. status)
		nextnotif = "" -- Shouldn't happen, but just in case, don't say status twice
		notify("status=" .. vlc.playlist.status() .. "&usec=" .. vlc.var.get(vlc.object.input(), "time"))
	end
end

function meta_changed()
end
