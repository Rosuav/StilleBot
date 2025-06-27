import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, TD, TH, TR} = choc; //autoimport

export function render(data) {
	set_content("#notifgroups tbody", Object.entries(data.groups)
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([grp, n]) => TR({"data-group": grp}, [		
			TH(grp),
			TD(""+n),
			TD(BUTTON({class: "send_notif"}, "Send")),
		]))
	);
}

on("click", ".send_notif", e => ws_sync.send({cmd: "send_notif", group: e.match.closest_data("group")}));
