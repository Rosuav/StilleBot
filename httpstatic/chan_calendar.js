import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, H2, LI, P, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function show_calendar(events, pfx) {
	console.log("Events", events);
	replace_content("#calendar", [
		H2([pfx, events.summary]),
		P(events.description),
		UL(events.items.map(item => LI([
			"From " + item.start.dateTime + " to " + item.end.dateTime + ": ",
			A({href: item.htmlLink}, item.summary),
		]))),
	]);
}

export function sockmsg_showcalendar(msg) {
	show_calendar(msg.events, "PREVIEW: ");
	if (msg.calendarid === DOM("[name=calendarid]").value)
		replace_content("#calsync", "Synchronize").dataset.calendarid = msg.calendarid;
}

export function render(data) {
	//
}

on("click", "#calsync", e => {
	const calendarid = DOM("[name=calendarid]").value;
	ws_sync.send({cmd: (e.match.dataset.calendarid === calendarid) ? "synchronize" : "fetchcal", calendarid});
});

function backtofetch() {
	const calendarid = DOM("[name=calendarid]").value;
	const btn = DOM("#calsync");
	const previd = btn.dataset.calendarid;
	if (previd && calendarid !== previd) {
		delete btn.dataset.calendarid;
		replace_content(btn, "Preview");
	}
}
on("input", "[name=calendarid]", backtofetch);
on("change", "[name=calendarid]", backtofetch);
on("paste", "[name=calendarid]", backtofetch);

on("click", "#googleoauth", e => ws_sync.send({cmd: "googlelogin"}));
export function sockmsg_googlelogin(msg) {window.open(msg.uri, "login");}
