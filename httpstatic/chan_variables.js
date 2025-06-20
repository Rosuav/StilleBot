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
		TD(
			item.per_user ? "(per-user)"
			: item.is_group ? "(group)"
			: INPUT({class: "value", value: item.curval})
		),
		TD(
			item.per_user ? BUTTON({type: "button", class: "showuservars"}, "Show users")
			: item.is_group ? BUTTON({type: "button", class: "showgroupvars"}, "Show vars")
			: [BUTTON({type: "button", class: "setvalue"}, "Set value"),
				BUTTON({type: "button", class: "delete"}, "Delete")]
		),
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
	const tr = e.match.closest("tr");
	ws_sync.send({cmd: "delete", id: tr.dataset.id});
	if (tr.dataset.id.includes(":")) tr.remove(); //Hack: We don't get signalled by the back end when grouped vars change, so do a local removal. You'll need to reopen the dialog to see other changes anyway.
}));

on("click", ".showgroupvars", e => {
	ws_sync.send({cmd: "getgroupvars", id: e.match.closest("tr").dataset.id});
});

on("click", ".showuservars", e => {
	ws_sync.send({cmd: "getuservars", id: e.match.closest("tr").dataset.id});
});

let editing_basevar = null, editmode;
let uservars_sortcol = -1, uservars_sortdesc = false;
on("click", "#groupedvars th", e => {
	if (editmode !== "per_user") return;
	const col = e.match.cellIndex;
	if (col === uservars_sortcol) uservars_sortdesc = !uservars_sortdesc;
	else {uservars_sortcol = col; uservars_sortdesc = false;}
	document.querySelectorAll("#groupedvars th").forEach((el, i) => {
		el.classList.toggle("sortasc", i === col && !uservars_sortdesc);
		el.classList.toggle("sortdesc", i === col && uservars_sortdesc);
	});
	sort_uservars();
});

function sort_uservars() {
	if (uservars_sortcol === -1) return;
	const rows = [...DOM("#groupedvars tbody").children];
	rows.sort((r1, r2) => {
		//textContent doesn't include the value of an input, so special-case that one
		const a = uservars_sortcol === 2 ? r1.querySelector("input").value : r1.children[uservars_sortcol].textContent;
		const b = uservars_sortcol === 2 ? r2.querySelector("input").value : r2.children[uservars_sortcol].textContent;
		let diff = a.localeCompare(b);
		if (+a > 0 && +b > 0) diff = +a - +b;
		if (uservars_sortdesc) return -diff;
		return diff;
	});
	set_content("#groupedvars tbody", rows);
}

export function sockmsg_uservars(msg) {
	editmode = "per_user";
	set_content("#basevarname", editing_basevar = msg.varname);
	set_content("#groupedvars table tbody", msg.users.map(u => TR([
		TD(u.uid),
		TD(u.username),
		TD(INPUT({class: "value", "data-uid": u.uid, value: u.value})),
	])));
	DOM("#groupedvars").classList.add("clean");
	set_content("#groupedvars #close_or_cancel", "Close");
	sort_uservars();
	DOM("#groupedvars").showModal();
}

export function sockmsg_groupvars(msg) {
	editmode = "group";
	set_content("#basevarname", editing_basevar = msg.prefix);
	set_content("#groupedvars table tbody", msg.vars.map(v => TR({"data-id": msg.prefix + v.suffix}, [
		TD(BUTTON({type: "button", class: "delete"}, "Delete")),
		TD(v.suffix),
		TD(INPUT({class: "value", "data-uid": v.suffix, value: v.value})),
	])));
	DOM("#groupedvars").classList.add("clean");
	set_content("#groupedvars #close_or_cancel", "Close");
	DOM("#groupedvars").showModal();
}

function dirty(el) {
	el.classList.add("dirty");
	DOM("#groupedvars").classList.remove("clean");
	set_content("#groupedvars #close_or_cancel", "Cancel");
}
on("input", "#groupedvars input", e => dirty(e.match));
on("change", "#groupedvars input", e => dirty(e.match));
on("paste", "#groupedvars input", e => dirty(e.match));

on("submit", "#groupedvars form", e => {
	//Note that this might be group variables, but it's still called user.
	const users = { };
	e.match.querySelectorAll(".dirty").forEach(input => users[input.dataset.uid] = input.value);
	//Assumes there'll be at least one, since the submit button isn't enabled otherwise.
	//If you go fiddling, it'll potentially send an empty message back to the server.
	ws_sync.send({cmd: "update", id: editing_basevar, [editmode]: users});
});
