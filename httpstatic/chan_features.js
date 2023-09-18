import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, BUTTON, CODE, TR, TD, LABEL, INPUT, SPAN} = choc;

export function render(data) {
	if (data.enableables) {
		const parent = DOM("#enableables tbody");
		const rows = [];
		//Sort the enableables by their descriptions
		const kwds = Object.keys(data.enableables);
		kwds.sort((a, b) => data.enableables[a].description.localeCompare(data.enableables[b].description));
		for (let kwd of kwds) {
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
	if (data.timezone) DOM("input[name=timezone]").value = data.timezone;
	if (data.flags) Object.entries(data.flags).forEach(([flg, state]) => DOM('.flag[name="' + flg + '"]').checked = state);
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

on("click", "input[type=checkbox].flag", e => {
	ws_sync.send({cmd: "enable", id: e.match.name, "state": e.match.checked});
});

/* TODO: Replace this boring input+button with a nice dialog.

* Have an option to use the browser's configured timezone
  - Intl.DateTimeFormat().resolvedOptions().timeZone;
* Have some sort of picker, probably with more levels than just "continent" and "city"
* Show the current time in these time zones, to help with the picking
* Explain what this setting actually does, which isn't much
  - Command automation (incl !repeat) if set to a time rather than a period
  - Quote timestamps (cosmetic only)

Don't forget that a mod may be using this tool, and the "correct" selection is usually
going to be the broadcaster's timezone.
*/
on("click", "#settimezone", e => {
	ws_sync.send({cmd: "settimezone", timezone: DOM("input[name=timezone]").value});
});
