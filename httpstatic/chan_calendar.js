import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, H2, IMG, LI, P, SPAN, UL} = lindt; //autoimport
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
	if (data.google_id) replace_content("#googlestatus", [
		"You are logged in as ",
		IMG({src: data.google_profile_pic || "", alt: "[profile pic]", style: "height: 1.5em; vertical-align: bottom;"}),
		data.google_name,
	]);
	replace_content("#calendarlist", UL(data.calendars.map(cal => LI({"data-id": cal.id}, [
		cal.selected ? "Selected" : "Unselected", //TODO: Have an option to show unselected, otherwise suppress them
		" ",
		cal.accessRole, //TODO: Show a little icon instead of the word
		" ",
		SPAN({title: cal.description || ""}, cal.summary),
		" ",
		BUTTON({class: "showcal"}, "Show"),
	]))));
}

on("click", ".showcal", e => {
	const calendarid = e.match.closest_data("id");
	ws_sync.send({cmd: "fetchcal", calendarid});
});

on("click", "#calsync", e => {
	const calendarid = DOM("[name=calendarid]").value;
	ws_sync.send({cmd: (e.match.dataset.calendarid === calendarid) ? "synchronize" : "fetchcal", calendarid});
});

on("click", "#googleoauth", e => ws_sync.send({cmd: "googlelogin"}));
export function sockmsg_googlelogin(msg) {window.open(msg.uri, "login");}
