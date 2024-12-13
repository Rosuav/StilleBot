import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, H3, LI, P, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	//
}

on("click", "#calsync", e => ws_sync.send({cmd: "fetchcal", calendarid: DOM("[name=calendarid]").value}));

export function sockmsg_showcalendar(msg) {
	replace_content("#calendar", [
		H3("Calendar: " + msg.events.summary),
		P(msg.events.description),
		UL(msg.events.items.map(item => LI([
			"From " + item.start.dateTime + " to " + item.end.dateTime + ": ",
			A({href: item.htmlLink}, item.summary),
		]))),
	]);
}
