import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, TR, TD, UL, LI, B, INPUT, BUTTON} = choc;
import {simpleconfirm} from "$$static||utils.js$$";

function describe_usage(u) {
	switch (u.type) {
		case "command": return A({href: "commands"}, [B(u.name), " " + u.action]);
		case "special": return A({href: "specials"}, [B(u.name), " " + u.action]);
		case "trigger": return A({href: "triggers"}, ["Trigger: " + u.action]);
		case "goalbar": return A({href: "monitors"}, "Goal bar - " + u.name);
		case "monitor": return A({href: "monitors"}, "Monitor - " + u.name);
	}
}

export const render_parent = DOM("#variables tbody");
export function render_item(item) {
	return TR({"data-id": item.id}, [
		TD(item.id),
		TD(item.per_user ? "(per-user)" : INPUT({class: "value", value: item.curval})),
		TD(item.per_user ? BUTTON({type: "button", class: "showuservars"}, "Show users")
			: [BUTTON({type: "button", class: "setvalue"}, "Set value"),
				BUTTON({type: "button", class: "delete"}, "Delete variable")]),
		TD(UL(item.usage.map(u => LI(describe_usage(u))))),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 4}, "No variables found."),
	]));
}
export function render(data) { }

on("click", ".setvalue", e => {
	const tr = e.match.closest("tr");
	ws_sync.send({cmd: "update", id: tr.dataset.id, value: tr.querySelector(".value").value});
});

on("click", ".delete", simpleconfirm("Delete this variable?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));

on("click", ".showuservars", e => {
	ws_sync.send({cmd: "getuservars", id: e.match.closest("tr").dataset.id});
});

let editing_uservar = null;
export function sockmsg_uservars(msg) {
	set_content("#uservarname", editing_uservar = msg.varname);
	set_content("#uservars table tbody", msg.users.map(u => TR([
		TD(u.uid),
		TD(u.username),
		TD(INPUT({class: "value", "data-uid": u.uid, value: u.value})),
	])));
	DOM("#uservars").classList.add("clean");
	set_content("#uservars #close_or_cancel", "Close");
	DOM("#uservars").showModal();
}

function dirty(el) {
	el.classList.add("dirty");
	DOM("#uservars").classList.remove("clean");
	set_content("#uservars #close_or_cancel", "Cancel");
}
on("input", "#uservars input", e => dirty(e.match));
on("change", "#uservars input", e => dirty(e.match));
on("paste", "#uservars input", e => dirty(e.match));

on("submit", "#uservars form", e => {
	const users = { };
	e.match.querySelectorAll(".dirty").forEach(input => users[input.dataset.uid] = input.value);
	//Assumes there'll be at least one, since the submit button isn't enabled otherwise.
	//If you go fiddling, it'll potentially send an empty message back to the server.
	ws_sync.send({cmd: "update", id: editing_uservar, per_user: users});
});
