import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, IMG, LI, SPAN} = choc;

const date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});

export function render(data) {
	if (!data.messages.length) return set_content("#messages", LI("You have no messages from this channel."));
	set_content("#messages", data.messages.map(msg => LI([
		BUTTON({className: "confirmdelete"}),
		SPAN({className: "date"}, " [" + date_format.format(new Date(msg.received * 1000)) + "] "),
		msg.parts ? SPAN(msg.parts.map(p =>
			typeof(p) === "string" ? p :
			p.type === "link" ? A({href: p.href || p.text}, p.text) :
			p.type === "image" ? IMG({src: p.url, title: p.text, alt: p.text}) :
			p.text //Shouldn't happen, but if we get an unknown type, just emit the text
		)) : msg.message,
	])));
}

on("click", ".confirmdelete", e => {
	e.preventDefault();
	e.match.classList.toggle("pending");
});
