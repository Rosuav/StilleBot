import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

export function render(state) {
	//If we have a socket connection, enable the primary control buttons
	document.querySelectorAll("button").forEach(b => b.disabled = false);
	//Partial updates: only update channels if channels were set
	if (state.channels) DOM("#channels").value = state.channels.map(c => c.name).join("\n");
	if (state.status) set_content("#statusbox", state.status).className = "status" + state.statustype;
}


//NOTE: Do not save channel list on input/change on textarea as it would be disruptive.
//Ultimately, save immediately on any *real* change, after validating the channel name.
//For now, there's an explicit button to commit the change.
on("click", "#updatechannels", e => {
	ws_sync.send({cmd: "setchannels", channels: DOM("#channels").value.split("\n").map(name => ({name}))});
});

on("click", "#recheck", e => ws_sync.send({cmd: "recheck"}));
