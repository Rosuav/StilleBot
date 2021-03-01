//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group

let handler = null;
let send_socket; //If present, send() is functional.
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
export function connect(group)
{
	let socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: ws_type, group}));
		send_socket = socket; //Don't activate send() until we're initialized
	};
	socket.onclose = () => {
		send_socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250, group);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (!handler) return;
		if (data.cmd === "update") {
			if (handler.render_item) {
				//If partial rendering is possible, we need render_item() and render_parent, and
				//optionally render_empty() to special-case the "no items" display.
				if (data.id) {
					const obj = handler.render_parent.querySelector(`[data-id="${data.id}"]`);
					if (obj && data.data) obj.replaceWith(handler.render_item(data.data));
					else if (data.data) handler.render_parent.appendChild(handler.render_item(data.data));
					else if (obj) {
						//Delete this item.
						obj.replaceWith();
						if (handler.render_empty && !handler.render_parent.querySelectorAll("[data-id]").length)
							handler.render_empty();
					}
					//else it's currently absent, needs to be absent, nothing to do
				} else {
					if (!data.items.length && handler.render_empty) handler.render_empty();
					set_content(handler.render_parent, data.items.map(handler.render_item));
				}
			}
			//Note that render() is called *after* render_item in all cases.
			handler.render(data, group);
		}
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {handler = await import(ws_code); connect(ws_group);}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg) {if (send_socket) send_socket.send(JSON.stringify(msg));}
