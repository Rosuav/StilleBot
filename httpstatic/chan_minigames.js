import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, INPUT, LABEL, LI, OPTION, SELECT, UL} = lindt; //autoimport

export function render(data) {
	const boss = {...sections.boss, ...(data.boss || { })};
	replace_content("#boss", UL([
		LI([
			"Enabled? ",
			SELECT({name: "enabled", value: boss.enabled}, [
				OPTION({value: "0"}, "No"),
				OPTION({value: "1"}, "Yes"),
			]),
			" Set to Yes to have a boss to fight!",
		]),
		LI([
			"Initial boss ",
			SELECT({name: "initialboss", value: boss.initialboss}, [
				OPTION({value: "279141671"}, "Mustard Mine"),
				OPTION({value: "274598607"}, "AnAnonymousGifter"),
				//TODO: Broadcaster, and all registered channel voices
			]),
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
		boss.monitorid && LI(["Further configuration (colour, font, etc) can be done ", A({href: "monitors"}, "by editing the bar itself"), "."]),
	]));
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
		["First", "Second", "Third", "Last"].map(which => LI(LABEL([
			INPUT({type: "checkbox", name: which.toLowerCase(), checked: Boolean(first[which.toLowerCase()])}), " " + which,
		]))),
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
