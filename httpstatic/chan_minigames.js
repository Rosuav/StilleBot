import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LABEL, LI, OPTION, SELECT, UL} = lindt; //autoimport

export function render(data) {
	const crown = {...sections.crown, ...(data.crown || { })};
	replace_content("#crown", UL([
		LI([
			"Enabled? ",
			SELECT({name: "enabled", value: crown.enabled}, [
				OPTION({value: "0"}, "No"),
				OPTION({value: "1"}, "Yes"),
			]),
			" Set to Yes to make the magic happen!",
		]),
		LI(["Initial price ", INPUT({type: "number", name: "initialprice", value: crown.initialprice})]),
		LI(["Increase per movement ", INPUT({type: "number", name: "increase", value: crown.increase})]),
		LI([
			"Grace time after gaining the crown ",
			SELECT({name: "gracetime", value: crown.gracetime}, [
				OPTION({value: "60"}, "One minute"),
				OPTION({value: "600"}, "Ten minutes"),
				OPTION({value: "0"}, "Rest of stream"),
			]),
		]),
		LI([
			"Rapid reclamation ",
			SELECT({name: "perpersonperstream", value: crown.perpersonperstream}, [
				OPTION({value: "0"}, "Permitted"),
				OPTION({value: "1"}, "Disallowed"),
			]),
			" If disallowed, each person may only claim the crown once per stream.",
		]),
	]));
	const first = {...sections.first, ...(data.first || { })};
	replace_content("#first", UL([
		LI("Select which rewards you want active."),
		LI(LABEL([INPUT({type: "checkbox", name: "first", checked: Boolean(first.first)}), " First"])),
		LI(LABEL([INPUT({type: "checkbox", name: "second", checked: Boolean(first.second)}), " Second"])),
		LI(LABEL([INPUT({type: "checkbox", name: "third", checked: Boolean(first.third)}), " Third"])),
		LI(LABEL([INPUT({type: "checkbox", name: "last", checked: Boolean(first.last)}), " Last"])),
		LI(LABEL([INPUT({type: "checkbox", name: "checkin", checked: Boolean(first.checkin)}), " Check-in (may be redeemed once each by all users)"])),
	]));
}

on("change", "input,select", e => {
	const sec = e.match.closest(".game");
	if (!sec) return;
	const params = { };
	sec.querySelectorAll("input,select").forEach(el => params[el.name] = el.type === "checkbox" ? el.checked : el.value);
	ws_sync.send({cmd: "configure", section: sec.id, params});
});
