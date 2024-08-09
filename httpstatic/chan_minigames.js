import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LI, OPTION, SELECT, UL} = lindt; //autoimport

export function render(data) {
	const crown = data.crown || { };
	replace_content("#seizecrown", UL({"data-section": "crown"}, [
		LI(["Initial price ", INPUT({type: "number", name: "initialprice", value: crown.initialprice || 5000})]),
		LI(["Increase per movement ", INPUT({type: "number", name: "increase", value: crown.increase || 1000})]),
		LI([
			"Grace time after gaining the crown ",
			SELECT({name: "gracetime", value: crown.gracetime || 60}, [
				OPTION({value: "60"}, "One minute"),
				OPTION({value: "600"}, "Ten minutes"),
				OPTION({value: "0"}, "Rest of stream"),
			]),
		]),
		LI([
			"Rapid reclamation ",
			SELECT({name: "perpersonperstream", value: crown.perpersonperstream || "0"}, [
				OPTION({value: "0"}, "Permitted"),
				OPTION({value: "1"}, "Disallowed"),
			]),
			" If disallowed, each person may only claim the crown once per stream.",
		]),
	]));
}

on("change", "input,select", e => {
	const sec = e.match.closest("[data-section]");
	if (!sec) return;
	const params = { };
	sec.querySelectorAll("input,select").forEach(el => params[el.name] = el.type === "checkbox" ? el.checked : el.value);
	ws_sync.send({cmd: "configure", section: sec.dataset.section, params});
});
