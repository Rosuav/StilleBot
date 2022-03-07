//Generic websocket synchronization handler
//Relies on globals ws_type and ws_group

let default_handler = null;
let send_socket; //If present, send() is functional.
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
let pending_message = null; //Allow at most one message to be queued on startup (will be sent after initialization)
let prefs = { }; //Updated from the server as needed
const prefs_hooks = [];
let reconnect_delay = 250;
let empty_desc = null; //If present, will be removed upon non-empty render
export function connect(group, handler)
{
	if (!handler) handler = default_handler;
	let socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		reconnect_delay = 250;
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: handler.ws_type || ws_type, group}));
		if (handler.socket_connected) handler.socket_connected(socket);
		else send_socket = socket; //Don't activate send() until we're initialized
		if (pending_message) {socket.send(JSON.stringify(pending_message)); pending_message = null;}
	};
	socket.onclose = () => {
		if (handler.socket_connected) handler.socket_connected(null);
		else send_socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, reconnect_delay, group, handler);
		if (reconnect_delay < 5000) reconnect_delay *= 1.5 + 0.5 * Math.random(); //Exponential back-off with a (small) random base
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		if (!handler) {console.log("Got message from server:", data); return;}
		let unknown = " UNKNOWN";
		if (data.cmd === "update") {
			if (handler.render_item && handler.render_parent) {
				//If partial rendering is possible, we need render_item() and render_parent, and
				//optionally render_empty() to special-case the "no items" display. If render_empty
				//returns a DOM element, that element will be destroyed upon any future non-empty
				//render; otherwise, you are responsible to "un-empty" the display as appropriate.
				//Note that something rendered on empty may or may not be a child of render_parent.
				if (data.id) {
					const obj = handler.render_parent.querySelector(`[data-id="${data.id}"]`);
					const newobj = data.data && handler.render_item(data.data, obj);
					if (newobj && empty_desc) {empty_desc.replaceWith(); empty_desc = null;}
					if (obj && newobj) obj.replaceWith(newobj); //They might be the same
					else if (newobj) handler.render_parent.appendChild(newobj);
					else if (obj) {
						//Delete this item. That might leave the render_parent empty.
						obj.replaceWith();
						if (handler.render_empty && !handler.render_parent.querySelectorAll("[data-id]").length)
							empty_desc = handler.render_empty();
					}
					//else it's currently absent, needs to be absent, nothing to do
				} else if (data.items) {
					set_content(handler.render_parent, data.items.map(i => handler.render_item(i)));
					if (!data.items.length && handler.render_empty) empty_desc = handler.render_empty();
					if (data.items.length && empty_desc) {empty_desc.replaceWith(); empty_desc = null;}
				}
			}
			//Note that render() is called *after* render_item in all cases.
			handler.render(data, group);
			unknown = "";
		}
		else if (data.cmd === "prefs_replace") {
			const oldprefs = prefs;
			prefs = data.prefs;
			prefs_hooks.forEach(p => {
				if (!p.key) p.func(prefs);
				else if (prefs[p.key] !== oldprefs[p.key]) p.func(prefs[p.key]);
			});
			unknown = "";
		}
		else if (data.cmd === "prefs_update") {
			for (let k in data.prefs) prefs[k] = data.prefs[k];
			prefs_hooks.forEach(p => {
				//Note: We assume that the server only sends us what's changed, so we'll
				//push a change through for everything that's in the update message.
				if (!p.key) p.func(prefs);
				else if (data.prefs[p.key]) p.func(prefs[p.key]);
			});
			unknown = "";
		}
		const f = handler["sockmsg_" + data.cmd];
		if (f) {f(data); unknown = "";}
		console.log("Got " + unknown + "message from server:", data);
	};
}
//When ready, import the handler code. It'll be eg "/subpoints.js" but with automatic mtime handling.
async function init() {default_handler = await import(ws_code); connect(ws_group);}
if (document.readyState !== "loading") init();
else window.addEventListener("DOMContentLoaded", init);

export function send(msg) {console.log("Sending to server:", msg); if (send_socket) send_socket.send(JSON.stringify(msg)); else pending_message = msg;}
//Usage: prefs_notify("favs", favs => {...})
//Or: prefs_notify(prefs => {...})
//With a key, will notify with the value of that key, when it changes
//Without a key, will notify on all changes to all prefs.
//Note that, on startup, keyless notifications are always called, but
//keyed notifications are only called if there is a value set.
export function prefs_notify(key, func) {
	if (!func) {func = key; key = null;}
	prefs_hooks.push({key, func});
}
export function get_prefs() {return prefs;}
