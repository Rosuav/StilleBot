import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LABEL, TD, TH, TR} = choc; //autoimport

set_content("#permitted", [
	TR(TH({colSpan: 4}, "Who should be allowed to post links?")),
	TR([
		TD(LABEL([INPUT({type: "radio", id: "allowall"}), "Anyone (no filtering)"])),
		TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "vip"}), "VIPs"])),
		TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "raider"}), "Raiders"])),
		TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "permit"}), "!permit command"])),
	]),
]);

export function render(data) {
}

//The radio button
on("click", "#allowall", e => {
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked = false);
	ws_sync.send({cmd: "allow", all: 1});
});

//The check boxes
on("click", "[name=allowed]", e => {
	DOM("#allowall").checked = false;
	const msg = {cmd: "allow", all: 0, permit: []};
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked && msg.permit.push(el.value));
	ws_sync.send(msg);
});
