+++
title = "On \"Immediate Mode\""
date = 2026-08-22
+++

In the previous post about Keru's interface, I stated that a simple and minimal interface is probably the most important goal for a GUI library, and that this goal pretty much forces the library to adopt a immediate-looking model where we often have to rerun all or most of the declaration code.

Especially in the Rust community, there's a feel that everyone hates everything that looks like immediate mode, so I "immediately" began presenting some defensive arguments about this choice. Without going into the details again, here's a summary of the arguments: 


- it's not actually immediate mode: everything is retained and just updated.
- the redeclaration code is not ran on every frame but only when an event that the GUI cares about happens.
- Iced and many others redeclare anything and nobody complains. Maybe more of an opposition to the abstract concept of "immediate mode" rather than a real performance concern?
- true reactivity is a big pain in the ass with many big tradeoffs. Especially in non-web libraries, people often do reactivity as skipping/optimizations over a redeclare-everything model.


These are all strong arguments, but as always, we have to look at the other side. If the cost of rerunning the declaration code on every event was truly paralyzing, we'd have to just get over it and use a different system anyway. For this reason, this post will go into some detail into how the redeclaration code is implemented and how expensive it is to run it. 


For reference, this is what Keru's redeclaration code looks like:

```rust
fn update_ui(state: &mut State, ui: &mut Ui) {
    #[node_key] const INCREASE: NodeKey;
    
    let increase_button: Node = BUTTON
        .color(Color::RED)
        .text("Increase")
        .key(INCREASE);

    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&state.count.to_string()));
    });

    if ui.is_clicked(INCREASE) {
        state.count += 1;
    }
}
```

What is this code actually doing, and how expensive is it? 

Many of the people who assume that code like that is expensive probably have something like React in mind, where the redeclaration code creates a brand new tree from scratch to represent the desired state of the GUI, and then compares it to the retained one. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

There's definitely more reasonable ways to go about this. In Keru, whenever we `add()` a node, the function reaches into the node storage, and it either finds the old version of the node or creates it from scratch. If it finds an old node, it marks it as "fresh", updates its parameters, and updates its parent link to put it in the desired position within the tree.

Then, the properties of the new node are immediately diffed against the old one. If we find a difference, we can schedule any relayouts, rerenders, or transition animations if needed.

Finally, we have to do a quick linear scan over the node storage to clean up any lingering ones that were excluded from the new declaration.

I measured this in the [`ten_thousand.rs`](https://github.com/kekelp/keru/blob/master/examples/ten_thousand.rs) example, which shows a non-virtualized list of 10k elements. On my laptop from 2021, rerunning the declaration code takes about 4 milliseconds, and we can comfortably scroll and interact with the nodes at 120hz:

[ videos ]

Most of the time is spent moving around and comparing the `Node` structs, which aren't small.

If we were willing to go back and change the interface for the sake of performance, we also could merge the `add()` function and the `Node` creation like this:

```rust
ui.add_button()
    .with_color(Color::RED)
    .with_size(Size::Big)
    .nest(|| { 
        ...
    })
```

In this case, the property builders themselves could reach directly into the node storage and compare and diff the single field, which would likely be much cheaper.

But I think that using free stack variables for nodes is a significant ergonomic advantage, because it allows the builder code to be separated from the `nest()` calls that define the tree structure, it allows the programmer to organize them into constants or associated values, to return them from functions, and so on.

The more general point here is that it's always more flexible and more natural to map the concepts of a library to the basic primitives of the language, when it is possible. It's much better for a `Node` to be a struct than an abstract concept that emerges out of a series of function calls, and is only materialized somewhere deep inside the library outside of the user's view.

Another possible performance improvement could be to represent `Node`s as a list of changes over a default value rather than a full struct with values for every field. But that wouldn't be quite as natural, and in current day Rust there's no ergonomic way to use many variable length objects without making a lot of allocations on the global heap (although these would be the sort of short-lived ones that allocators are actually fairly good at dealing with).

Anyway, my opinion is that the speed is fine. Let's not forget that about all the other work that the GUI has to do every time something does happen:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with N as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all of this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will be fine either way. At the end of the day, rerunning some declaration code just won't be what makes the difference between an snappy and efficient library and a slow or wasteful one.


For everything else, my impression is that some basic heap discipline and a really basic level of data-oriented programming should be enough to do a deal with any realistic GUI. 

There's a ton of space for more optimizations in Keru, especially in the unique layout algorithm or to improve general cache efficiency, but I don't want to get to them while the code is still in flux. With a bit of optimization and maybe a newer CPU, we can definitely go much higher than 10k.

At the same time, 10k is already way above what a 2D GUI should realistically have on screen at the same time! In reality, the list of 10k elements would be virtualized. 


