import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, LI, IMG, BUTTON} = choc;
import {waitlate} from "$$static||utils.js$$";

let li_cache = { };
function display_channel(chan) {
	return li_cache[chan.id] = li_cache[chan.id] || LI({"data-id": chan.id}, [
		BUTTON({className: "reorder moveup", "data-dir": -1, title: "Increase priority"}, "\u2191"),
		BUTTON({className: "reorder movedn", "data-dir": +1, title: "Decrease priority"}, "\u2193"),
		BUTTON({type: "button", className: "confirmdelete"}, "🗑"),
		A({href: "https://twitch.tv/" + chan.login}, [
			IMG({className: "avatar", src: chan.profile_image_url}),
			chan.display_name,
		]),
	]);
}

export function render(state) {
	//If we have a socket connection, enable the primary control buttons
	if (state.active) document.querySelectorAll("button").forEach(b => b.disabled = false);
	//Partial updates: only update channels if channels were set
	if (state.channels) {
		if (state.channels.length) set_content("#channels", state.channels.map(display_channel));
		else set_content("#channels", "No channels to autohost yet - add one below!");
	}
	if (state.status) set_content("#statusbox", state.status).className = "status" + state.statustype;
	//Allow the server to explicitly mark us as inactive (for the demo)
	if (state.inactive) document.querySelectorAll("button").forEach(b => b.disabled = !b.dataset.scopes);
}

//NOTE: Do not save channel list on input/change on textarea as it would be disruptive.
//Ultimately, save immediately on any *real* change, after validating the channel name.
//For now, there's an explicit button to commit the change.
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
