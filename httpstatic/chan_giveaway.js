import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, H3, LI, SPAN} = choc;
import {simpleconfirm} from "$$static||utils.js$$";

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

let lastrecommended = null;
function recommend(btn) {
	if (btn === lastrecommended) return;
	//Pick a master control button that is likely to be the next one wanted
	const next = document.getElementById(btn).parentElement;
	if (!next) return; //Borked. Don't change.
	const prevnext = DOM("#master li.next"); if (prevnext) prevnext.classList.remove("next");
	lastrecommended = btn;
	next.classList.add("next");
}

let message_timeout = 0;
function update_message(msg) {
	set_content("#errormessage", msg).classList.toggle("hidden", msg === "");
	clearTimeout(message_timeout);
	message_timeout = setTimeout(update_message, 10000, "");
}

export function render(state) {
	if (state.message) {update_message(state.message); return;}
	if (state.title) set_content("h1", "Giveaway - " + state.title + "!");
	if (state.tickets) set_content("#ticketholders", state.tickets.map(t => LI([""+t.tickets, " ", t.name])));
	if ("is_open" in state) {
		if (ticker) {clearInterval(ticker); ticker = null;}
		//Choose a button to recommend based on what's likely to be the next one needed
		if (state.is_open) recommend("close"); //After opening the giveaway, recommend closing it. This is the GUI equivalent of a useless box.
		else if (state.last_winner) recommend("end");
		else if (state.tickets && state.tickets.length > 0) recommend("pick");
		else recommend("open");
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
	fields.forEach(f => el[f].value = "" + (config[f] || ""));
	el.allow_multiwin.checked = config.allow_multiwin === "yes";
	el.refund_nonwinning.checked = config.refund_nonwinning === "yes";
	set_content("#refund_nonwinning_desc", config.refund_nonwinning === "yes" ? "refunding" : "clearing out");
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
	body.refund_nonwinning = el.refund_nonwinning.checked ? "yes" : "no";
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
	set_content("#refund_nonwinning_desc", body.refund_nonwinning === "yes" ? "refunding" : "clearing out");
});

DOM("#showmaster").onclick = e => DOM("#master").showModal();
on("click", ".master", async e => {
	ws_sync.send({cmd: "master", action: e.match.id})
});

on("click", "#makenotifs", simpleconfirm("Create commands? Will overwrite any that exist!", e => ws_sync.send({cmd: "makenotifs"})));
