import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {TD, TIME, TR} = choc; //autoimport

export const render_parent = DOM("#msglog tbody");
export function render_item(msg) {
	if (!msg) return 0;
	const when = new Date(msg.datetime);
	return TR({"data-id": msg.id}, [
		TD(TIME({datetime: when.toISOString(), title: when.toLocaleString()},
			when.toLocaleString(), //TODO: If today, use toLocaleTimeString, if recent, give time and DOW, else give just date
		)),
		TD(msg.level),
		TD(msg.message),
		TD(msg.context),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 4}, "Message log is empty."),
	]));
}
export function render(data) { }
