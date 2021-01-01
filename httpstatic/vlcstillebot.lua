-- Install by symlinking into ~/.local/share/vlc/lua/extensions or equivalent

function descriptor()
	return { 
		title = "&StilleBot integration",
		version = "0.1",
		author = "Rosuav",
		capabilities = { "input-listener", "playing-listener" },
	}
end

function activate()
	vlc.msg.info("[StilleBot] Activating")
	s = vlc.stream("https://sikorsky.rosuav.com/channels/rosuav/vlc?foo=bar")
	line = s:readline() -- read a line. Return nil if EOF was reached.
	vlc.msg.info("[StilleBot] Got line: " .. line)
end

function deactivate()
	vlc.msg.info("[StilleBot] Deactivated")
end

function input_changed()
	vlc.msg.info("[StilleBot] Seen track change")
end

function playing_changed(status)
	-- 2 is playing, 3 is paused, 4 is loading?? TODO: Find docs.
	vlc.msg.info("[StilleBot] Status is now " .. status)
end

function meta_changed()
end
