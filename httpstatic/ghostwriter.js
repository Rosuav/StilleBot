import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, H2, IMG, LI, TIME, UL} = choc; //autoimport
import {waitlate} from "$$static||utils.js$$";

function channel_profile(chan) {
	return A({href: "https://twitch.tv/" + chan.login}, [
		IMG({className: "avatar", src: chan.profile_image_url}),
		chan.display_name,
	]);
}

let li_cache = { };
function display_channel(chan) {
	return li_cache[chan.id] = li_cache[chan.id] || LI({"data-id": chan.id}, [
		BUTTON({className: "reorder moveup", "data-dir": -1, title: "Increase priority"}, "\u2191"),
		BUTTON({className: "reorder movedn", "data-dir": +1, title: "Decrease priority"}, "\u2193"),
		BUTTON({type: "button", className: "confirmdelete"}, "🗑"),
		channel_profile(chan),
	]);
}

export function render(state) {
	//If we have a socket connection, enable the primary control buttons
	if (state.active) document.querySelectorAll("button,select").forEach(b => b.disabled = false);
	//Partial updates: only update channels if channels were set
	if (state.channels) {
		if (state.channels.length) set_content("#channels", state.channels.map(display_channel));
		else set_content("#channels", "No channels to autohost yet - add one below!");
	}
	if (state.status) set_content("#statusbox", state.status).className = "status" + state.statustype;
	if (state.pausetime) DOM("#pausetime").value = state.pausetime;
	//Allow the server to explicitly mark us as inactive (for the demo)
	if (state.inactive) {
		document.querySelectorAll("button,select").forEach(b => b.disabled = !b.dataset.scopes);
		set_content("#calendar", "(Your stream schedule would show up here)");
	}
	if (state.schedule_last_checked) {
		const ev = state.schedule_next_event;
		if (ev) set_content("#calendar", [
			"Next scheduled stream: ",
			TIME({
				dateTime: ev.start_time,
				title: ""+new Date(ev.start_time),
			}, ev.start_time), //TODO: Format the human-readable part more nicely, esp if it's coming soon
			" ",
			ev.title,
		]);
		else set_content("#calendar", "");
	}
	if (state.aht) {
		if (state.aht.length) set_content("#autohosts_this", [
			H2("Who autohosts you?"),
			UL(state.aht.map(chan => LI(channel_profile(chan)))),
		]);
		else set_content("#autohosts_this", "");
	}
}

on("submit", "#addchannel", e => {
	e.preventDefault();
	ws_sync.send({cmd: "addchannel", name: e.match.elements.channame.value});
	e.match.elements.channame.value = "";
});

on("click", "#recheck", e => ws_sync.send({cmd: "recheck"}));

on("click", ".reorder", e => {
	ws_sync.send({cmd: "reorder", id: e.match.closest("li").dataset.id, "dir": +e.match.dataset.dir});
});

on("click", ".confirmdelete", waitlate(750, 5000, "Delete?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("li").dataset.id});
}));

on("change", "#pausetime", e => {
	ws_sync.send({cmd: "config", pausetime: +e.match.value});
});
on("click", "#pausenow", e => ws_sync.send({cmd: "pause"}));
