import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, CODE, TR, TD, LABEL, INPUT, SPAN} = choc;

export const render_parent = DOM("#features tbody");
export function render_item(msg, obj) {
	if (obj) {
		set_content(obj.querySelector(".desc"), msg.desc);
		obj.querySelector(`[value="${msg.state}"]`).checked = true;
	}
	return TR({"data-id": msg.id}, [
		TD(msg.id),
		TD({className: "desc"}, msg.desc),
		TD((featurecmds[msg.id] || []).map(cmd => CODE("!" + cmd + " "))),
		TD(["Active", "Inactive", "Default"].map(s =>
			(s !== "Default" || msg.id != "allcmds") && LABEL([INPUT({
				type: "radio", className: "featurestate",
				name: msg.id, value: s.toLowerCase(),
				checked: msg.state == s.toLowerCase(),
				disabled: !ws_group.startsWith("control#"),
			}), SPAN(s)]),
		)),
	]);
}

export function render(data) {
	const parent = DOM("#enableables tbody");
	const rows = [];
	for (let kwd in data.enableables) {
		const info = data.enableables[kwd];
		const row = parent.querySelector(`[data-id="${kwd}"]`);
		if (row) {
			row.querySelector(".enable_activate").disabled = !(info.manageable&1);
			row.querySelector(".enable_deactivate").disabled = !(info.manageable&2);
			rows.push(row);
			continue;
		}
		let link = "/" + info.module, mgr = info.module;
		if (mgr.startsWith("chan_")) link = mgr = info.module.slice(5);
		rows.push(TR({"data-id": kwd}, [
			TD(kwd),
			TD(info.description),
			TD(A({href: link, target: "_blank"}, mgr)),
			TD([
				BUTTON({className: "enabl_activate", type: "button", "disabled": !(info.manageable&1)}, "Activate"),
				" ",
				BUTTON({className: "enabl_deactivate", type: "button", "disabled": !(info.manageable&2)}, "Deactivate"),
			]),
		]));
	}
	set_content(parent, rows);
}

on("change", ".featurestate", e => {
	ws_sync.send({cmd: "update", id: e.match.name, "state": e.match.value});
});

on("click", ".enabl_activate", e => {
	ws_sync.send({cmd: "enable", id: e.match.closest("tr").dataset.id, "state": true});
});

on("click", ".enabl_deactivate", e => {
	ws_sync.send({cmd: "enable", id: e.match.closest("tr").dataset.id, "state": false});
});
