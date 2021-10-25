import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, IMG} = choc;

let channels = [];
function display_channel(chan) {
	return LI({"data-id": chan.id}, [
		IMG({className: "avatar", src: chan.profile_image_url}),
		chan.display_name,
	]);
}

export function render(state) {
	//If we have a socket connection, enable the primary control buttons
	document.querySelectorAll("button").forEach(b => b.disabled = false);
	//Partial updates: only update channels if channels were set
	if (state.channels) set_content("#channels", (channels = state.channels).map(display_channel));
	if (state.status) set_content("#statusbox", state.status).className = "status" + state.statustype;
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
