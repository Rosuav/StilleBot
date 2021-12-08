import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {BUTTON, DIV, LI, OL} = choc; //autoimport
import {waitlate} from "$$static||utils.js$$";

/* TODO: Get this info from the server without massively spamming it, and without being late with updates
const is_mod = { };
mods.forEach(m => is_mod[m.user_id] = 1);

function update_leaders(periodicdata) {
	set_content("#leaders", periodicdata.map(period => DIV(
		{"data-starttime": period[2]},
		period[1].length ? [
			period[0],
			BUTTON({className: "addvip", title: "Add VIPs"}, "💎"),
			BUTTON({className: "remvip", title: "Remove VIPs"}, "X"),
			OL(period[1].map(person => LI(
				{className: is_mod[person.user_id] ? "is_mod" : ""},
				person.user_name
			))),
		] : period[0] + " (no data)",
	)));
}
update_leaders(periodicdata);

on("click", ".addvip", waitlate(750, 5000, "Add VIPs from this period?", e => {
	console.log("Adding!");
	fetch("/bitsbadges?period=" + period + "&vip=" + e.match.closest("DIV").dataset.starttime);
}));

on("click", ".remvip", waitlate(750, 5000, "Remove VIPs from this period?", e => {
	console.log("Removing!");
	fetch("/bitsbadges?period=" + period + "&unvip=" + e.match.closest("DIV").dataset.starttime);
}));
*/

const id_to_info = { };

//Take a date in digital format ("202112") and return a human-readable form
function reformat_date(yearmonth) {
	const months = ["???", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	return months[+yearmonth.slice(4)] + " " + yearmonth.slice(0, 4);
}

function remap_to_array(stats) {
	const people = Object.entries(stats).map(e => ({id: e[0], ...(id_to_info[e[0]]||{}), qty: e[1]}));
	//FIXME: Would be better to use "oldest timestamp this month" but I don't
	//really have that available.
	people.sort((a,b) => b.qty - a.qty || a.login.localeCompare(b.login));
	if (people.length > 25) people.length = 25;
	return people;
}

export function render(data) {
	if (data.all) data.all.forEach(s => id_to_info[s.giver.user_id] = s.giver);
	if (data.monthly) set_content("#monthly", Object.entries(data.monthly).map(e => [
		reformat_date(e[0]),
		OL(remap_to_array(e[1]).map(p => LI([p.displayname, " with ", p.qty]))),
	]));
}

on("click", "#recalc", e => ws_sync.send({cmd: "recalculate"}));
