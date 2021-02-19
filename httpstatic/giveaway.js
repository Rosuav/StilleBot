import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, H3, LI, SPAN} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

const fields = "cost desc max multi pausemode".split(" ");

function render(state) {
	if (state.rewards) set_content("#existing", state.rewards.map(r => LI([r.id, " ", r.title])));
	set_content("#ticketholders", state.tickets.map(t => LI([""+t.tickets, " ", t.name])));
	set_content("#master_status", [
		H3("Giveaway is " + (state.is_open ? "OPEN" : "CLOSED")),
		state.last_winner ? DIV([
			"Winner: ",
			SPAN({className: "winner_name"}, state.last_winner[1]),
			` with ${state.last_winner[2]} tickets and a ${state.last_winner[2]*100/state.last_winner[3]}% chance to win!`,
		]) : "",
	]).classList.toggle("is_open", !!state.is_open); //ensure that undefined becomes false :|
}
if (config.cost) {
	const el = DOM("#configform").elements;
	fields.forEach(f => el[f].value = "" + config[f]);
}
/*
1) Create rewards - DONE
2) Activate rewards - DONE
3) Notice redemptions - DONE
4) Deactivate rewards - DONE
5) Pick a winner and remove (accept) all that person's tickets (so you can pick multiple)
   - Picking is done, removing tickets isn't (partly for debugging)
   - Needs an in-chat notification. Need a good system for these. Use for noobs run too. Pick command from dropdown, can edit.
6) Clear all tickets - DONE
7) Cancel giveaway and refund all tickets - DONE
8) Userspace command to refund all my tickets. No need for partials, probably (too hard to manage)
   - Allow this only while the giveaway is open.

When no current giveaway, show most recent winner. (Maybe allow that to be cleared??)
*/

on("submit", "#configform", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = { };
	fields.forEach(f => body[f] = el[f].value);
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
});

DOM("#showmaster").onclick = e => DOM("#master").showModal();
on("click", ".master", async e => {
	const action = e.match.className; //TODO: Whitelist
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({action}),
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
