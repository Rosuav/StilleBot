import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

export function render(state) {
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
