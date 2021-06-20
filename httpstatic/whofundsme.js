import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

const minidisplay = DOM("#display");
export function render(state) {
	if (minidisplay) {
		if (state.total) set_content(minidisplay, state.total);
		return;
	}
	if (state.total) set_content("#total", "Donation total: " + state.total);
	set_content("#error", state.error ? "ERROR: " + state.error : "");
	if (!state.donations.length) set_content("#donos", LI("No donations found."));
	else set_content("#donos", state.donations.map(dono => LI(
		dono.name + " donated " + dono.amount + " " + state.currency,
		dono.comment ? SPAN(dono.comment) : undefined,
	)));
}

on("click", "#chattoggle", e => {
	ws_sync.send({cmd: "chattoggle"});
});

export function sockmsg_chatbtn(msg) {
	set_content("#chattoggle", msg.label);
}

on("dragstart", "a", e => { //Yeah you might drag the login link, I don't care
	const url = `${e.match.href}&layer-name=GoFundMe%20goal&layer-width=400&layer-height=120`;
	e.dataTransfer.setData("text/uri-list", url);
});
