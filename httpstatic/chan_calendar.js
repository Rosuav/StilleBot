import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, H2, IMG, LI, P, SPAN, TABLE, TBODY, TD, TH, THEAD, TR, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

//Given two sorted lists of events, return an array of pairs. If two events have the same
//time_t, return [time_t, ev1, ev2]; otherwise return [time_t, ev1, null] or [time_t, null, ev2]
//as required. The resultant array will be in time_t order.
//This is largely a merge operation, but with matching timestamps merging the elements instead
//of zipping them together.
function pair_events(arr1, arr2) {
	arr1 = arr1 || []; arr2 = arr2 || [];
	const ret = [];
	let d1 = 0, d2 = 0, s1 = arr1.length, s2 = arr2.length;
	while (d1 < s1 && d2 < s2) {
		const t1 = arr1[d1].time_t, t2 = arr2[d2].time_t;
		if (t1 === t2)
			ret.push([t1, arr1[d1++], arr2[d2++]]);
		else if (t1 < t2)
			ret.push([t1, arr1[d1++], null]);
		else
			ret.push([t2, arr2[d2++], null]);
	}
	//And collect any residue. One of these loops won't have any content to process.
	for (let i = d1; i < s1; ++i)
		ret.push([arr1[i].time_t, arr1[i], null]);
	for (let i = d2; i < s2; ++i)
		ret.push([arr2[i].time_t, null, arr2[i]]);
	return ret;
}

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
		TABLE([
			THEAD(TR([
				TH("Date/time"),
				TH(data.synchronized_calendar || "Google Calendar"),
				TH("Twitch schedule"),
			])),
			TBODY(pair_events(data.sync?.events, data.sync?.segments).map(([ts, ev, seg]) => TR([
				TD(ts), //TODO: Format nicely eg "Mon 17th 10AM"
				TD(ev ? A({href: ev.htmlLink}, ev.summary) : "-"),
				TD(seg ? seg.title : "-"),
			]))),
		]),
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
