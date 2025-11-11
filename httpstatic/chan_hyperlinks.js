import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, H3, INPUT, LABEL, P, TABLE, TD, TH, TR, UL} = choc; //autoimport

set_content("#settings", [
	TABLE([
		TR(TH({colSpan: 4}, "Who should be allowed to post links?")),
		TR([
			TD(LABEL([INPUT({type: "radio", id: "allowall"}), "Anyone (no filtering)"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "vip"}), "VIPs"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "raider"}), "Raiders"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "permit"}), "!permit command"])),
		]),
	]),
	H3("Penalties"),
	P("First offense gets the first warning. Subsequent offenses will progress through the list."),
	UL({id: "warnings"}),
	DIV({class: "buttonbox"}, [
		BUTTON("Delete message"),
		BUTTON("Purge chat messages"),
		BUTTON("Timeout"), //TODO: After this is clicked, allow specification of the duration
		BUTTON("Ban"),
	]),
]);

/* Also: Have a !!hyperlink special trigger, which is given all the necessary information. Suggest adding /warn to that. */

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
