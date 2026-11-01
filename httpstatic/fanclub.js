import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, H3, IMG, P} = lindt; //autoimport
import {simpleconfirm, form_values} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#clubtitle", data.title);
	const uid = ws_sync.get_userid();
	replace_content("#members", [
		//The button can be one of three.
		P([
			!uid ? BUTTON({class: "twitchlogin"}, "Log in to add yourself!") //Start by logging in.
			: !data.members.find(u => +u.id === uid) ? BUTTON({id: "joinclub"}, "Join the club!") //Then you can join!
			: BUTTON({id: "leaveclub"}, "Leave the club."), //But you can then leave if you so desire.
		]),

		H3("Current members:"),
		DIV({class: "members"}, data.members.map(u => DIV({class: "member"}, [
			IMG({class: "avatar", src: u.profile_image_url}),
			u.display_name,
		]))),
	]);
}

on("submit", "#managedlg form", e => ws_sync.send(form_values(e.match, {cmd: "configure"})));
on("click", "#joinclub", e => ws_sync.send({cmd: "join"}));
on("click", "#leaveclub", simpleconfirm("Do you definitely want to leave this club?", e => ws_sync.send({cmd: "remove"})));
