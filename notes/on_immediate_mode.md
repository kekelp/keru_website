# On "Immediate Mode"

This is Keru's API for building a GUI looks like:

```rust
fn update_ui(state: &mut State, ui: &mut Ui) {
    // Define a unique identity for the button
    #[node_key] const INCREASE: NodeKey;
    
    // Create a Node struct describing a button
    let increase_button: Node = BUTTON
        .color(Color::RED)
        .text("Increase")
        .key(INCREASE);

    // Place the nodes into the tree and define the layout
    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&state.count.to_string()));
    });

    // Change the state in response to events
    if ui.is_clicked(INCREASE) {
        state.count += 1;
    }
}
```


It sort of looks like "immediate mode". Isn't that wasteful and slow?

People mean a lot of different things when they say "immediate mode". In this section, I will use the term in the way I think most Rust programmers understand it, even if that's probably not what it originally used to mean.

Anyway, even if Keru code sort of looks like it, it's not immediate mode in the sense that it keeps recomputing a lot of things needlessly. The `Ui` struct stays alive for the whole duration for the program, and holds the fully retained state of the GUI, from the node tree to the text layouts and the rander data.

It's also not immediate mode in the sense that it reruns that declaration code "on every frame", or even "on every user interaction". Nodes can specify which input events they care about, so the system knows that it has to rerun it if a mouse click lands on the increase button, but not if it lands on the `LABEL` or outside.

When the declarative code runs, it updates the retained state as needed, and only triggers relayouts or rerenders if something actually changed. Keru used to be able to do minimal partial relayouts and even minimal updates to the render data. I ended up removing these capabilities as I experimented with different rendering and layout systems, but I hope to get them back in at some point.

Still, if the click does land on the increase button, we'll have to rerun the declaration code for the whole GUI. There's no system that tracks dependencies and knows that the button increases the `count` variable, and only the label depends on that.

## "Reactivity"?

According to many people, even this is not fine. Their theory is that all GUI code has to be "reactive". This is another word that is used with plenty of different meanings, but for the purpose of this post, there's no need to get into the details: we can call "reactive" any system that uses some sort of dependency tracking to avoid paying the cost of redeclaring the GUI too often.

However, it's not easy to build a reactive system without making some sacrifices in terms of the simplicity, flexibility, ergonomics, or other important axes. In the rest of this post, I will try to justify Keru's choice of not being reactive by default.

First, Keru does actually have some experimental ways to skip redeclaring: after all, the whole tree is always retained, so if we know that a branch will stay unchanged, we can just tell the library to keep it as it is. If a user finds out that redeclaring a certain part of the GUI is a real bottleneck, and doesn't find any other way to fix the problem, they can do some basic dependency tracking themselves and skip it manually. This is shown in the [`reactivity.rs`](https://github.com/kekelp/keru/blob/master/examples/reactivity.rs) example in Keru.

But doing this sort of dependency tracking and skipping automatically for every part of the GUI, even the ones who weren't going to be a problem at all, is a completely different problem that brings in a ton of complexity and annoyances. 

Second, we have to keep in mind that many non-immediate-mode libraries already redeclare everything on every update, and it's really not a problem. For example, Iced does it. If people aren't up in arms about it like they are about Egui, it seems to be just because the code looks different enough from the dreaded "immediate mode" to not raise suspicion.


## How expensive is it really?

Besides the abstract arguments, we should look at what the declaration code is actually doing.

Many of the people who assume that code like that is expensive probably got their impression from the early discussions around React. 

React's idea of "diffing" was to create a brand new tree from scratch to represent the desired state of the GUI, and then go through it to compare it to the retained one. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

Is there a more reasonable way to do this? In Keru, whenever we `add()` a node, the function reaches into the node storage, and it either finds the old version of the node or creates it from scratch. If it finds an old node, it "refreshes" it and updates its parameters. The properties of the new node are immediately diffed against the old one, so that we can schedule any relayouts, rerenders, or transition animations if needed.

Then, at the end, we have to do a quick linear scan over the nodes to remove any lingering ones that were excluded from this new declaration.

How efficient do we expect this to be? To give a rough idea of the order of magnitude, the N hashmap lookups to find the old node in the tree account for about 50% of the whole redeclaration time in the profiling that I've done.

Even reasoning in absolute terms, it's easy to feel like one or two hashmap lookups for each GUI node shouldn't be something that we should be scared of, if it buys us something significant in terms of flexibility or simplicity. But the most important thing is how this compares to all the other work that the GUI has to do every time something does happen:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with N as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all of this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will be fine either way. At the end of the day, rerunning some declaration code just won't be what makes the difference between an snappy and efficient library and a slow or wasteful one.

What should we do to optimize all of that?

For glyph rasterization, text shaping and layout, Keru uses Parley, so there's not much to do other than not needlessly recomputing things, and skipping work for offscreen text when possible.

For everything else, it just boils down to some basic data-oriented-programming and being disciplined about short-lived allocations.

It turns out that it's plenty enough: here is an example (`ten_thousands.rs`) showing a non-virtualized list of 10k elements. 
With the Ryzen 7 5800H in my laptop from 2021, I can scroll and interact with it at the full 165 Hz of my display without any issues. 10k is not a big number for a computer!

[ example video ]

There's also space for more optimizations to improve cache efficiency, but I don't want to get to them while the code is still in flux. With a bit more optimization and maybe a newer CPU, we can definitely go much higher than 10k.

Keru also uses a custom `wgpu` renderer, but I don't have a precise idea of how much that helps. In the example above it doesn't matter, because most elements are far offscreen and can be efficiently culled by any renderer. It's only testing the redeclaration, layout, animation updates, and the rest of the CPU-side code that can't be trivially skipped.

It's a very simple and efficient renderer that can draw plenty of shapes, including rounded rectangles, circles, triangles, hexagons, line segments, and quadratic Bézier curves. But it does cut some corners: it can't do arbitrary path fills, non-rectangular clipping, or "layered blending" (I'm not sure what the real term for this is).

It would be cool to have a more modern compute-based renderer that can do all these effects, but I'm probably not writing another renderer from scratch any time soon. The most realistic option would be to switch to `vello` in the future, which would also be a great way to get a cpu-software backend almost for free.
