import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {}

export function sockmsg_get_status(msg) {
	obsstudio.getStatus(status => ws_sync.send({cmd: "response", key: msg.key, ...status}));
}
export function sockmsg_get_scene(msg) {
	obsstudio.getCurrentScene(scene => ws_sync.send({cmd: "response", key: msg.key, scenename: scene.name}));
}
export function sockmsg_set_scene(msg) {
	obsstudio.setCurrentScene(msg.scenename);
	sockmsg_get_scene(msg);
}
//TODO maybe: saveReplayBuffer?

//ws_sync.send({cmd: "logme", keys: Object.keys(obsstudio).sort()});
//obsstudio.getControlLevel(sc => ws_sync.send({cmd: "logme", sc}));
