import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, TR, TD, LABEL, INPUT} = choc;

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
			LABEL([INPUT({
				type: "radio", className: "featurestate",
				name: msg.id, value: s.toLowerCase(),
				checked: msg.state == s.toLowerCase(),
			}), s]),
		)),
	]);
}

export function render(data) {
	if (data.defaultstate) set_content("#defaultstate", data.defaultstate);
}

on("change", ".featurestate", e => {
	ws_sync.send({cmd: "update", id: e.match.name, "state": e.match.value});
});
