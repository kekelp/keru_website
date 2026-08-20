# On "Immediate Mode" and GUI performance

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

(People mean a lot of different things when they say "immediate mode". In this section, I will use the term in the way I think most Rust programmers understand it, even if that's probably not what it originally used to mean.)

Even if Keru code sort of looks like it, it's not immediate mode in the sense that it keeps recomputing a lot of things needlessly. The `Ui` struct stays alive for the whole duration for the program, and holds the fully retained state of the GUI, from the node tree to the text layouts and the rander data.

It's also not immediate mode in the sense that it reruns that declaration code "on every frame", or even "on every user interaction". Nodes can specify which input events they care about, so the system knows that it has to rerun it if a mouse click lands on the increase button, but not if it lands on the `LABEL` or outside. If the user is just moving the mouse around or scrolling, the redeclaration code isn't reran either.

When the declarative code runs, it updates the retained state as needed, and only triggers relayouts or rerenders if something actually changed. Keru used to be able to do minimal partial relayouts and even minimal updates to the render data. I ended up removing these capabilities as I experimented with different rendering and layout systems, but I hope to get them back in at some point.

Still, if the click does land on the increase button, we'll have to rerun the declaration code for the whole GUI. There's no system that tracks dependencies and knows that the button increases the `count` variable, and only the label depends on that.

## "Reactivity"?

According to some people, even that amount of redeclaration is not fine. Their theory is that all GUI code has to be "reactive". This is another word that is used with plenty of different meanings, but for the purpose of this post, there's no need to get into the details: we can call "reactive" any system that uses some sort of dependency tracking to avoid paying the cost of redeclaring the GUI too often.

However, it's not easy to build a reactive system without making some sacrifices in terms of the simplicity, flexibility, or ergonomics of the library, or on other important axes. In the rest of this post, I will try to justify Keru's choice of not being reactive.

First, Keru does actually have some experimental ways to skip redeclaring: after all, the whole tree is always retained, so if we know that a branch will stay unchanged, we can just tell the `Ui` to keep it as it is. If a user finds out that redeclaring a certain part of the GUI is a real bottleneck, and doesn't find any other way to fix the problem, they can do some basic dependency tracking themselves and skip it manually. This is shown in the [`reactivity.rs`](https://github.com/kekelp/keru/blob/master/examples/reactivity.rs) example.

But doing this sort of dependency tracking and skipping automatically for every part of the GUI, even the ones who weren't going to be a problem at all, is a completely different problem that brings in a ton of complexity and annoyances. 

Second, we have to keep in mind that many non-immediate-mode libraries already redeclare everything on every update, and it's really not a problem. For example, Iced does it. If people aren't up in arms about it like they are about Egui, it seems to be just because the code looks different enough from the infamous "immediate mode" to avoid raising suspicion.


## How slow is the redeclaration code?

Besides the abstract arguments, it's helpful look at what the declaration code is actually doing.
Many of the people who assume that code like that is expensive probably have something like React in mind, where the declarative code creates a brand new tree from scratch to represent the desired state of the GUI, and then goes through it to compare it to the retained one. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

Is there a more reasonable way to do this? In Keru, whenever we `add()` a node, the function reaches into the node storage, and it either finds the old version of the node or creates it from scratch. If it finds an old node, it marks it as "fresh", updates its parameters, and updates its parent link to put it in the desired position within the tree.

The properties of the new node are immediately diffed against the old one. If we find a difference, we can schedule any relayouts, rerenders, or transition animations if needed.

Then, at the end, we have to do a quick linear scan over the nodes to remove any lingering ones that were excluded from this new declaration.

How efficient is this? I measured this in the [`ten_thousands.rs`](https://github.com/kekelp/keru/blob/master/examples/ten_thousands.rs) example, which shows a non-virtualized list of 10k elements. On my laptop from 2021, rerunning the declaration code takes about 4 milliseconds.

Most of the time is spent moving around and comparing the `Node` structs, which aren't small. In an ideal world, maybe `Node`s would be represented as a list of changes over a default value rather than a full struct with values for every field, but in current day Rust there's no ergonomic way to use many small variable length types without making a lot of small allocations on the global heap (although these would be the sort of short-lived ones that allocators are actually fairly good at dealing with).

We could also change the API so that nodes aren't build as freestanding variables on the stack, and merge the `add()` function and the `Node` creation like this:

    ui.add_button()
        .with_color(Color::RED)
        .with_size(Size::Big)
        .nest(|| { 
            ...
        })

In this case, the property builders could reach directly into the added node and do a much cheaper update and compare for the single field. In fact, many libraries work exactly like this. But I think that using freestanding variables for nodes is a significant ergonomic advantage, because it allows the builder code to be separated from the `nest()` calls that define the tree structure, it allows the programmer to organize them into constants or associated values, to return them from functions, etc.

The more general idea here is that we should always try to create a natural and intuitive mapping between the concepts of a library and the basic concepts of the language, when possible. Mapping a `Node` to a struct is more natural than mapping it to an abstract concept that emerges out of a specific series of function calls, and is only materialized somewhere deep inside the library outside of the user's view.


Anyway, my opinion is that the speed is fine. Let's not forget that about all the other work that the GUI has to do every time something does happen:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with N as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all of this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will be fine either way. At the end of the day, rerunning some declaration code just won't be what makes the difference between an snappy and efficient library and a slow or wasteful one.

<!-- 
## How slow is everything else?

Since we mentioned it, we can spend a couple words about the performance of all the other parts of the pipeline. What should a library do to achieve good performance there?

For rasterizing glyphs and shaping and layouting text, Keru uses Parley. It's not really feasible for any library to have high quality text without depending on a library, so there's not much that the library can do to optimize its text other than not needlessly recomputing things and skipping work for offscreen text when possible.

For everything else, my impression is that some basic heap discipline and a really basic level of data-oriented programming should be enough to do a deal with any realistic GUI. Here is Keru's [`ten_thousands.rs`](https://github.com/kekelp/keru/blob/master/examples/ten_thousands.rs) example, showing a non-virtualized list of 10k elements. 
Running this on my laptop from 2021, I can scroll and interact with the list at the full 165 Hz of my display without issues.
10k is not a big number for a computer, and it's already a lot higher than what a 2D GUI should reasonably show at the same time.

[ example video ]

There's a ton of space for more optimizations in Keru, especially in the unique layout algorithm or to improve general cache efficiency, but I don't want to get to them while the code is still in flux. With a bit of optimization and maybe a newer CPU, we can definitely go much higher than 10k.

Keru also uses a custom `wgpu` renderer, but I don't have a precise idea of how much that helps. In the example above it doesn't matter, because most elements are far offscreen and can be efficiently culled by any renderer. It's only testing the redeclaration, layout, animation updates, and the rest of the CPU-side code that can't be trivially skipped.

It's a very simple and efficient renderer that can draw plenty of shapes, including rounded rectangles, circles, triangles, hexagons, line segments, and quadratic Bézier curves. But it does cut some corners: it can't do arbitrary path fills, non-rectangular clipping, or "layered blending" (I'm not sure what the real term for this is).

It would be cool to have a more modern compute-based renderer that can do all these effects, but I'm probably not writing another renderer from scratch any time soon. The most realistic option would be to switch to `vello` in the future, which would also be a great way to get a cpu-software backend almost for free. -->
