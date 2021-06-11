//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group

let default_handler = null;
let send_socket; //If present, send() is functional.
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
export function connect(group, handler)
{
	if (!handler) handler = default_handler;
	let socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: handler.ws_type || ws_type, group}));
		send_socket = socket; //Don't activate send() until we're initialized
	};
	socket.onclose = () => {
		send_socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250, group, handler);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (!handler) return;
		if (data.cmd === "update") {
			if (handler.render_item && handler.render_parent) {
				//If partial rendering is possible, we need render_item() and render_parent, and
				//optionally render_empty() to special-case the "no items" display.
				if (data.id) {
					const obj = handler.render_parent.querySelector(`[data-id="${data.id}"]`);
					const newobj = data.data && handler.render_item(data.data, obj);
					if (obj && newobj) obj.replaceWith(newobj); //They might be the same
					else if (newobj) handler.render_parent.appendChild(newobj);
					else if (obj) {
						//Delete this item. That might leave the render_parent empty.
						obj.replaceWith();
						if (handler.render_empty && !handler.render_parent.querySelectorAll("[data-id]").length)
							handler.render_empty();
					}
					//else it's currently absent, needs to be absent, nothing to do
				} else {
					set_content(handler.render_parent, data.items.map(i => handler.render_item(i)));
					if (!data.items.length && handler.render_empty) handler.render_empty();
				}
			}
			//Note that render() is called *after* render_item in all cases.
			handler.render(data, group);
		}
		const f = handler["sockmsg_" + data.cmd];
		if (f) f(data);
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {default_handler = await import(ws_code); connect(ws_group);}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg) {if (send_socket) send_socket.send(JSON.stringify(msg));}
