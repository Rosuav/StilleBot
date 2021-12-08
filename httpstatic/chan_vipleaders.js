import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {BUTTON, DIV, LI, OL} = choc; //autoimport
import {waitlate} from "$$static||utils.js$$";

/*
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