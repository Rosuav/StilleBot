import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, H3, LI, SPAN} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});
import {waitlate} from "$$static||utils.js$$";

const fields = "title cost desc max multi pausemode duration".split(" ");

let ticker = null;
function show_end_time(end_time, el, init) {
	//NOTE: We assume that the server and client have mostly-synchronized clocks.
	//If not, the countdown may be wrong. It's the server's clock that will auto-close.
	let end = Math.ceil(end_time - (+new Date()) / 1000);
	if (end < 0) end = "Ending SOON";
	else end = "Ending in " + Math.floor(end / 60) + ":" + ("0" + end % 60).slice(-2);
	set_content(el, end);
	if (init) {ticker = setInterval(show_end_time, 1000, end_time, el); return el;}
}
export function render(state) {
	if (state.message) {console.warn(state.message); return;} //TODO: Handle info/warn/error, and put in the DOM, kthx
	if (state.rewards) set_content("#existing", state.rewards.map(r => LI([r.id, " ", r.title])));
	if (state.title) set_content("h1", state.title);
	if (state.tickets) set_content("#ticketholders", state.tickets.map(t => LI([""+t.tickets, " ", t.name])));
	if ("is_open" in state) {
		if (ticker) {clearInterval(ticker); ticker = null;}
		set_content("#master_status", [
			H3("Giveaway is " + (state.is_open ? "OPEN" : "CLOSED")),
			state.is_open && state.end_time && show_end_time(state.end_time, H3(), 1),
			state.last_winner ? DIV([
				"Winner: ",
				SPAN({className: "winner_name"}, state.last_winner[1]),
				` with ${state.last_winner[2] === 1 ? "one ticket" : state.last_winner[2] + " tickets"}` +
				` and a ${state.last_winner[2]*100/state.last_winner[3]}% chance to win!`,
			]) : "",
		]).classList.toggle("is_open", !!state.is_open); //ensure that undefined becomes false :|
	}
}
if (config.cost) {
	const el = DOM("#configform").elements;
	fields.forEach(f => el[f].value = "" + config[f]);
	el.allow_multiwin.checked = config.allow_multiwin === "yes";
}
/*
1) Create rewards - DONE
2) Activate rewards - DONE
3) Notice redemptions - DONE
4) Deactivate rewards - DONE
5) Pick a winner and remove (accept) all that person's tickets (so you can pick multiple winners) - DONE
   - Needs an in-chat notification. Need a good system for these. Use for noobs run too. Pick command from dropdown, can edit.
6) Clear all tickets - DONE
7) Cancel giveaway and refund all tickets - DONE
8) Userspace command to refund all my tickets. No need for partials, probably (too hard to manage)
   - Allow this only while the giveaway is open.

When no current giveaway, show most recent winner - DONE
*/

on("submit", "#configform", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = { };
	fields.forEach(f => body[f] = el[f].value);
	body.allow_multiwin = el.allow_multiwin.checked ? "yes" : "no";
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
});

DOM("#showmaster").onclick = e => DOM("#master").showModal();
on("click", ".master", async e => {
	ws_sync.send({cmd: "master", action: e.match.id})
});

on("click", "#makenotifs", waitlate(2000, 10000, "Create commands? Will overwrite any that exist!", e => ws_sync.send({cmd: "makenotifs"})));