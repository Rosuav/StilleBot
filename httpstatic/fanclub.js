import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, BR, BUTTON, DIV, H3, I, IMG, P} = lindt; //autoimport
import {simpleconfirm, form_values, form_populate} from "$$static||utils.js$$";

const rtf = new Intl.RelativeTimeFormat("en");
const timeunits = {
	minute: 60, hour: 3600, day: 86400,
	week: 604800, month: 30*86400, year: 365*86400, //bit of a cheat
};
function tenure(tm) {
	if (tm < 1) return "just now";
	let curunit = "seconds", divisor = 1;
	for (let unit in timeunits) {
		if (tm < timeunits[unit]) break;
		curunit = unit; divisor = timeunits[unit];
	}
	return rtf.format(-Math.floor(tm / divisor), curunit);
}

export function render(data) {
	form_populate("#managedlg form", data);
	replace_content("#clubtitle", data.title);
	const uid = ws_sync.get_userid();
	const now = +new Date / 1000; //Ensure consistent display of relative timess
	replace_content("#members", [
		//The button can be one of three.
		P([
			!uid ? BUTTON({class: "twitchlogin"}, "Log in to add yourself!") //Start by logging in.
			: !data.members[uid] ? BUTTON({id: "joinclub"}, "Join the club!") //Then you can join!
			: BUTTON({id: "leaveclub"}, "Leave the club."), //But you can then leave if you so desire.
		]),

		H3("Current members:"),
		DIV({class: "members"}, Object.values(data.members)
			.sort((a, b) => b.joined - a.joined)
			.map(u => DIV({class: "member", title: "Member since " + tenure(now - u.joined)}, [
				IMG({class: "avatar", src: u.profile_image_url}),
				DIV({class: "text"}, [
					B(u.display_name),
					BR(),
					I(u.status), " ",
					+u.uid === uid && BUTTON({type: "button", class: "editstatus", "data-status": u.status||""}, "\u{1F589}"),
					is_owner && u.status && BUTTON({type: "button", class: "confirmdelete", "data-uid": u.uid, title: "Delete status"}, "🗑"),
				]),
			]))
		),
	]);
}

on("submit", "#managedlg form", e => ws_sync.send(form_values(e.match, {cmd: "configure"})));
on("click", "#joinclub", e => ws_sync.send({cmd: "join"}));
on("click", "#leaveclub", simpleconfirm("Do you definitely want to leave this club?", e => ws_sync.send({cmd: "remove"})));

on("click", ".editstatus", e => {
	DOM("#statusdlg [name=status]").value = e.match.dataset.status;
	DOM("#statusdlg").showModal();
});
on("submit", "#statusdlg form", e => ws_sync.send(form_values(e.match, {cmd: "set_status"})));
on("click", ".confirmdelete", simpleconfirm("Remove this user's status?", e => ws_sync.send({cmd: "set_status", removeuser: e.match.dataset.uid})));
