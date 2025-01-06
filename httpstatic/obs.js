import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {}

export function sockmsg_get_scene(msg) {
	obsstudio.getCurrentScene(scene => ws_sync.send({cmd: "response", key: msg.key, scenename: scene.name}));
}
export function sockmsg_set_scene(msg) {
	obsstudio.setCurrentScene(msg.scenename);
	sockmsg_get_scene(msg);
}

//ws_sync.send({cmd: "logme", keys: Object.keys(obsstudio).sort()});
//obsstudio.getCurrentScene(sc => ws_sync.send({cmd: "logme", sc}));
//obsstudio.setCurrentScene("Big Head Mode");

/*
"getControlLevel",
"getCurrentScene",
"getCurrentTransition",
"getScenes",
"getStatus",
"getTransitions",
"pauseRecording",
"pluginVersion",
"saveReplayBuffer",
"setCurrentScene",
"setCurrentTransition",
"startRecording",
"startReplayBuffer",
"startStreaming",
"startVirtualcam",
"stopRecording",
"stopReplayBuffer",
"stopStreaming",
"stopVirtualcam",
"unpauseRecording"
*/
