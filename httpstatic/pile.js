const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
//NOTE: For debugging and testing, background and fillStyle are both colours. For
//production, they should probably be set to transparent, with actual elements for
//interaction purposes.
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: "aliceblue", width, height,
}});
const Rectangle = Matter.Bodies.rectangle;
//The ground. TODO: Size this to the available space.
//???? The x position of this rectangle confuses me. Setting it to 0 has the floor
//run way off the left edge, having it at (roughly) half the width works. Why?
Matter.Composite.add(engine.world, Rectangle(width / 2, height + 10, width + 10, 60,
	{isStatic: true, render: {fillStyle: "rebeccapurple", lineWidth: 0}}));
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.renderer = renderer; //For debugging, eg toggle wireframes mode

//Map a category ID to the array of things
const thingcategories = { };
//Map category ID to the server-provided information about it
let thingtypes = { };
export function render(data) {
	if (data.data?.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
	if (data.newcount) {
		const cat = thingtypes[data.thingtype];
		if (!cat) return;
		if (!thingcategories[data.thingtype]) thingcategories[data.thingtype] = [];
		const things = thingcategories[data.thingtype];
		while (things.length > data.newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < data.newcount) {
			const img = cat.images[Math.floor(Math.random() * cat.images.length)];
			const scale = cat.xsize / img.xsize;
			const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), cat.xsize, Math.ceil(img.ysize * scale), {
				render: {sprite: {
					texture: img.fn,
					//xOffset: cat.xoffset || 0, yOffset: cat.yoffset || 0, //Not currently configured on the back end
					xScale: scale, yScale: scale, 
				}},
			});
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
		}
	}
}

//Demo mode? Emote dropping mode?
if (0) setInterval(() => {
	const cat = thingtypes.emotes; //TODO: User selection from the available categories
	if (!cat) return;
	const img = cat[Math.floor(Math.random() * cat.length)];
	const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), img.xsize, img.ysize, {
		render: {sprite: {texture: img.fn, xOffset: img.xoffset, yOffset: img.yoffset}},
	});
	//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
	//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
	//taken into account). Provide each newly-added element with a bit of rotation, either direction.
	Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
	Matter.Composite.add(engine.world, obj);
}, 2000);
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
/* Next steps:

* Create an object type ("category", need a good name for it)
* Upload an image for an object type - may be done more than once. If not done, will use Mustard Mine squavatar.
* Builtin to manipulate objects
  - Needs a type. Will only manipulate objects of that type.
  - Add N (default to 1), remove N (default to 1), or set to N on screen
    - "+1", "-1", "1"?
* Handle objects falling off the bottom?
* On the edit dlg, button to add/remove objects given a type

*/
