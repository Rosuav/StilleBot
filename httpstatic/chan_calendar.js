import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, H2, H3, IMG, LI, P, SPAN, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	//If you're logged in, replace the login button with your pfp and name.
	if (data.google_id) replace_content("#googlestatus", [
		"You are logged in as ",
		IMG({src: data.google_profile_pic || "", alt: "[profile pic]", style: "height: 1.5em; vertical-align: bottom;"}),
		data.google_name,
		!data.have_credentials && [
			". ",
			BUTTON({id: "googleoauth"}, "Re-log in with Google"),
			" to select from your calendars.",
		],
	]);
	if (data.calendars) replace_content("#calendarlist", [
		H2("Available calendars"),
		UL(data.calendars.map(cal => LI({"data-id": cal.id}, [
			cal.selected ? "" : "(unselected) ", //TODO: Have an option to show unselected, otherwise suppress them
			/*cal.accessRole, //TODO: Show a little icon instead of the word
			" ",*/
			SPAN({title: cal.description || ""}, cal.summary),
			" ",
			BUTTON({class: "showcal"}, "Show"),
		]))),
	]);
	if (data.synchronized_calendar) replace_content("#synchronization", [
		H2("Synchronization active"),
		H3(["Google Calendar: ", data.synchronized_calendar]),
		//TODO: Show current calendar events
		P(["Timezone: ", data.synchronized_calendar_timezone]),
		H3("Twitch schedule"),
		//TODO: Show current schedule segments
		P([
			BUTTON({id: "force_resync"}, "Resynchronize"),
			SPAN({id: "lastsync"}, [" Last synchronized at ", data.sync.synctime]),
		]),
	]);
}

export function sockmsg_showcalendar(msg) {
	console.log("Events", msg.events);
	replace_content("#calendar", [
		H2(["Calendar: ", msg.events.summary]),
		P(msg.events.description),
		P(BUTTON({id: "calsync", "data-id": msg.calendarid}, "Synchronize with Twitch")),
		UL(msg.events.items.map(item => item.status !== "cancelled" && LI([ //TODO: Or should it check that status *does* equal confirmed?
			"From " + item.start.dateTime + " to " + item.end.dateTime + ": ",
			A({href: item.htmlLink}, item.summary),
		]))),
	]);
}
export function sockmsg_privatecalendar(msg) {
	//You tried to query a calendar, probably a valid one, but it's private
	replace_content("#calendar", [
		H2("Calendar is private"),
		P("In order to synchronize your Google Calendar with Twitch, the calendar must be flagged as public."),
		P("TODO: Include instructions on how to do this."),
	]);
}

on("click", ".showcal", e => ws_sync.send({cmd: "fetchcal", calendarid: e.match.closest_data("id")}));
on("click", "#calsync", e => ws_sync.send({cmd: "synchronize", calendarid: e.match.closest_data("id")}));

on("click", "#force_resync", e => {
	ws_sync.send({cmd: "force_resync"});
	set_content("#lastsync", " Synchronizing..."); //Bit hacky but whatever. The server doesn't need to tell us this way.
});

on("click", "#googleoauth", e => ws_sync.send({cmd: "googlelogin"}));
export function sockmsg_googlelogin(msg) {window.open(msg.uri, "login");}
