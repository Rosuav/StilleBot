import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, LI} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

function render(state) {
	if (state.rewards) set_content("#existing", state.rewards.map(r => LI([r.id, " ", r.title])));
	set_content("#ticketholders", state.tickets.map(t => LI([""+t.tickets, " ", t.name])));
}

/*
1) Create rewards - DONE
2) Activate rewards
   - PUT request with a single flag. Back end will clear counts and activate.
3) Notice redemptions - possibly with caps and autorejection?
   - Have to retain credentials
4) Deactivate rewards and pick a winner
5) Multiple winners?? Will need a way to say "pick another without clearing".

When no current giveaway, show most recent winner. (Maybe allow that to be cleared??)
*/

on("submit", "#configform", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = {cost: el.cost.value, desc: el.desc.value, multi: el.multi.value, max: el.max.value};
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
});

let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
function connect()
{
	socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: "chan_giveaway", group: channelname}));
	};
	socket.onclose = () => {
		socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (data.cmd === "update") render(window.laststate = data);
	};
}
if (channelname) connect();
