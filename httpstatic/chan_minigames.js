import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, INPUT, LABEL, LI, OPTION, SELECT, SPAN, UL} = lindt; //autoimport
import {simpleconfirm} from "./utils.js";

export function render(data) {
	const boss = {...sections.boss, ...(data.boss || { })};
	replace_content("#boss", UL([
		LI([
			"Enabled? ",
			SELECT({name: "enabled", value: boss.enabled, "data-dangerous": boss.enabled ? "Are you sure you want to disable the stream boss entirely?" : ""}, [
				OPTION({value: "0"}, "No"),
				OPTION({value: "1"}, "Yes"),
			]),
			" Set to Yes to have a boss to fight!",
		]),
		LI([
			"Initial boss ",
			SELECT({name: "initialboss", value: boss.initialboss}, Object.entries(voices).map(([id, name]) =>
				OPTION({value: id}, name)
			)),
		]),
		LI([
			"Gift subs ",
			SELECT({name: "giftrecipient", value: boss.giftrecipient}, [
				OPTION({value: "0"}, "Credit the giver"),
				OPTION({value: "1"}, "Credit the recipient"),
			]),
		]),
		LI([
			"Support from current boss ",
			SELECT({name: "selfheal", value: boss.selfheal}, [
				OPTION({value: "0"}, "Deals damage as normal"),
				OPTION({value: "1"}, "Heals the boss"),
			]),
		]),
		LI([
			"Reset boss each stream ",
			SELECT({name: "autoreset", value: boss.autoreset}, [
				OPTION({value: "0"}, "No"),
				OPTION({value: "1"}, "Yes"),
			]),
			BR(),
			"Boss can be reset any time with the ", CODE("!resetboss"), " command, or here: ",
			BUTTON({".onclick": () => ws_sync.send({cmd: "resetboss"})}, "Reset boss"),
		]),
		LI(["Initial HP ", INPUT({type: "number", name: "initialhp", value: boss.initialhp})]),
		LI(["Increase per victory ", INPUT({type: "number", name: "hpgrowth", value: boss.hpgrowth}), " or -1 for overkill mode"]),
		boss.monitorid && LI(["To see the bar, ", A({class: "monitorlink", href: "monitors?view=" + boss.monitorid}, "drag this to OBS")]),
		boss.monitorid && LI(["Further configuration (colour, font, etc) can be done ", A({href: "monitors"}, "by editing the bar itself"), "."]),
		boss.monitorid && LI(["For testing purposes, you may ", BUTTON({id: "dealdamage"}, "deal some damage to the boss")]),
	]));
	const crown = {...sections.crown, ...(data.crown || { })};
	replace_content("#crown", UL([
		LI([
			"Enabled? ",
			SELECT({name: "enabled", value: crown.enabled, "data-dangerous": crown.enabled ? "Are you sure you want to disable crown seizing entirely?" : ""}, [
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
		["First", "Second", "Third", "Last"].map(which => LI([
			LABEL([
				INPUT({type: "checkbox", name: which.toLowerCase(), checked: Boolean(first[which.toLowerCase()])}),
				SPAN({style: "display: inline-block; width: 4em; padding-left: 0.25em;"}, which),
			]),
			" ",
			INPUT({name: which.toLowerCase() + "desc", value: first[which.toLowerCase() + "desc"] || "", size: 80}),
		])),
		LI(LABEL([INPUT({type: "checkbox", name: "checkin", checked: Boolean(first.checkin)}), " Check-in (may be redeemed once each by all users)"])),
	]));
}

function update_all(e) {
	const sec = e.match.closest(".game");
	if (!sec) return;
	const params = { };
	sec.querySelectorAll("input,select").forEach(el => params[el.name] = el.type === "checkbox" ? el.checked : el.value);
	ws_sync.send({cmd: "configure", section: sec.id, params});
}
on("change", "input,select", e => {
	if (e.match.dataset.dangerous) simpleconfirm(e.match.dataset.dangerous, update_all)(e); else update_all(e);
});

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=Mustard%20Mine%20monitor&layer-width=750&layer-height=90`;
	e.dataTransfer.setData("text/uri-list", url);
});

on("click", "#dealdamage", e => ws_sync.send({cmd: "dealdamage"}));
