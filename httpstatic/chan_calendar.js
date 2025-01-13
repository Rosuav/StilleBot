import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, H2, IMG, LI, P, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function show_calendar(events, pfx) {
	console.log("Events", events);
	replace_content("#calendar", [
		H2([pfx, events.summary]),
		P(events.description),
		UL(events.items.map(item => item.status !== "cancelled" && LI([ //TODO: Or should it check that status *does* equal confirmed?
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
	//If you're logged in, replace the login button with your pfp and name.
	if (data.google_name) replace_content("#googlestatus", [
		"You are logged in as ",
		IMG({src: data.google_profile_pic || "", alt: "[profile pic]", style: "height: 1.5em; vertical-align: bottom;"}),
		data.google_name,
	]);
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
