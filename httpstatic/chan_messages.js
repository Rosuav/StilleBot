import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, IMG, LI, SPAN} = choc;

const full_date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});
const date_format = new Intl.DateTimeFormat('default', {
	weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
});
const time_format = new Intl.DateTimeFormat('default', {
	hour: 'numeric', minute: 'numeric', second: 'numeric',
});
function date_display(date) {
	let shortdate;
	if (date.toLocaleDateString() === new Date().toLocaleDateString())
		//Message is from today. Show the timestamp only.
		shortdate = time_format.format(date);
	else
		//Older message. Show the date only. Either way, hover for full timestamp.
		shortdate = date_format.format(date);
	return SPAN({className: "date", title: full_date_format.format(date)}, " [" + shortdate + "] ");
}

export const render_parent = DOM("#messages");
export function render_item(msg) {
	set_content("#loading", "");
	return LI({"data-id": msg.id}, [
		BUTTON({className: "confirmdelete"}, "🗑"),
		date_display(new Date(msg.received * 1000)),
		msg.parts ? SPAN(msg.parts.map(p =>
			typeof(p) === "string" ? p :
			p.type === "link" ? A({href: p.href || p.text}, p.text) :
			p.type === "image" ? IMG({src: p.url, title: p.text, alt: p.text}) :
			p.text //Shouldn't happen, but if we get an unknown type, just emit the text
		)) : msg.message,
	]);
}

export function render_empty() {set_content("#loading", "You have no messages from this channel.");}
export function render(data) { }

on("click", ".confirmdelete", e => {
	const btn = e.match; //Snapshot for closure
	e.preventDefault();
	if (btn.classList.toggle("pending")) {
		set_content(btn, "Delete?");
		setTimeout(() => set_content(btn, "🗑").classList.remove("pending"), 5000);
	} else {
		set_content(btn, "🗑");
		ws_sync.send({cmd: "delete", id: btn.closest("li").dataset.id});
	}
});
