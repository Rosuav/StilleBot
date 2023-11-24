import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, TD, TIME, TR} = choc; //autoimport

let msgcount = 0;
export const render_parent = DOM("#msglog tbody");
export function render_item(msg) {
	if (!msg) return 0;
	const when = new Date(msg.datetime * 1000);
	return TR({"data-id": msg.id, class: "lvl-" + msg.level}, [
		TD(INPUT({type: "checkbox", class: "selected"})),
		TD(TIME({datetime: when.toISOString(), title: when.toLocaleString()},
			when.toLocaleString(), //TODO: If today, use toLocaleTimeString, if recent, give time and DOW, else give just date
		)),
		TD(msg.level),
		TD(msg.message),
		TD(msg.context),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 5}, "Message log is empty."),
	]));
}
export function render(data) {
	if (data.visibility) {
		document.querySelectorAll("input[name=show]").forEach(el => el.checked = data.visibility.includes(el.value));
		update_visibility();
	}
	if (typeof data.msgcount !== "undefined") {
		msgcount = data.msgcount;
		set_content("#errcnt", msgcount && "(" + msgcount + ")");
	}
	else if (data.id && data.type === "item") {
		//Assume that any single-item update is a new message. If it's one of the visible
		//levels, add to the message count.
		const el = DOM("input[name=show][value=" + data.data.level + "]");
		if (el && el.checked) {
			msgcount++;
			set_content("#errcnt", "(" + msgcount + ")");
		}
	}
}

on("click", "#selectall", e => {
	const state = e.match.checked;
	render_parent.querySelectorAll(".selected").forEach(el => el.checked = state);
});

on("click", "#deletemsgs", e => {
	const ids = [];
	render_parent.querySelectorAll(".selected").forEach(el => {
		if (el.checked) ids.push(el.closest("[data-id]").dataset.id);
	});
	ws_sync.send({cmd: "delete", ids});
});

function update_visibility() {
	document.querySelectorAll("input[name=show]").forEach(el =>
		render_parent.classList.toggle("hide-" + el.value, !el.checked));
}
on("click", "input[name=show]", update_visibility);
