import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

const date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});

export function render(data) {
	if (!data.messages.length) return set_content("#messages", LI("You have no messages from this channel."));
	set_content("#messages", data.messages.map(msg => LI([
		SPAN({className: "date"}, "[" + date_format.format(new Date(msg.received * 1000)) + "] "),
		msg.message,
	])));
}
