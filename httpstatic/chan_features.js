import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, BUTTON, CODE, TR, TD, LABEL, INPUT, SPAN} = choc;

const active_desc = {
	Active: "Active: Chat commands are available",
	Inactive: "Inactive: Chat commands disabled, web access only",
};
const prefix_len = {Active: 2, Inactive: 4, Default: 3}; //Number of characters that get kept even on small screens
export const render_parent = DOM("#features tbody");
export function render_item(msg, obj) {
	if (obj) {
		set_content(obj.querySelector(".desc"), msg.desc);
		obj.querySelector(`[value="${msg.state}"]`).checked = true;
		return obj;
	}
	return TR({"data-id": msg.id}, [
		TD(msg.id),
		TD({className: "desc"}, msg.desc),
		TD((featurecmds[msg.id] || []).map(cmd => [A(
			{href: "https://rosuav.github.io/StilleBot/commands/" + cmd},
			CODE("!" + cmd)
		), " "])),
		TD({className: "no-wrap"}, ["Active", "Inactive"].map(s =>
			LABEL([INPUT({
				type: "radio", className: "featurestate",
				name: msg.id, value: s.toLowerCase(),
				checked: msg.state == s.toLowerCase(),
				disabled: !ws_group.startsWith("control#"),
			}), ABBR({title: active_desc[s]}, [s.slice(0, prefix_len[s]), SPAN(s.slice(prefix_len[s]))])]),
		)),
	]);
}

export function render(data) {
	if (data.enableables) {
		const parent = DOM("#enableables tbody");
		const rows = [];
		for (let kwd in data.enableables) {
			const info = data.enableables[kwd];
			const row = parent.querySelector(`[data-id="${kwd}"]`);
			if (row) {
				row.querySelector(".enabl_activate").disabled = !(info.manageable&1);
				row.querySelector(".enabl_deactivate").disabled = !(info.manageable&2);
				rows.push(row);
				continue;
			}
			let link = "/" + info.module, mgr = info.module;
			if (mgr.startsWith("chan_")) link = mgr = info.module.slice(5);
			rows.push(TR({"data-id": kwd}, [
				TD(kwd),
				TD(info.description),
				TD(A({href: link + (info.fragment||""), target: "_blank"}, mgr)),
				TD({className: "no-wrap"}, ws_group.startsWith("control#") ? [
					BUTTON({className: "enabl_activate", type: "button", "disabled": !(info.manageable&1)}, "Activate"),
					" ",
					BUTTON({className: "enabl_deactivate", type: "button", "disabled": !(info.manageable&2)}, "Deactivate"),
				] : {1: "Inactive", 2: "Active", 3: "Half-active"}[info.manageable]),
			]));
		}
		set_content(parent, rows);
	}
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
