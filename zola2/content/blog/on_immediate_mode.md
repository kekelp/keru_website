+++
title = "On \"Immediate Mode\""
date = 2026-08-22
+++

In [the previous post about Keru's interface](@/blog/interface.md), I argued that a simple and minimal interface is probably the most important goal for a GUI library, and that this goal pretty much forces us to adopt a model at least superficially similar to "immediate mode", where we often have to rerun all or most of the user's GUI declaration code.

My impression is that especially in the Rust community, immediate-mode GUI is not very popular, so I tried felt like I had defend this choice. Without going into the details again, here's a summary of the defensive arguments: 


- It's not actually immediate mode: there's a `Ui` struct that retains the whole state of the GUI at all times. The declaration code just updates this retained state.

- The declaration code is not rerun "on every frame", but only when a meaningful event happens. If a click lands on a node not set to listen to it, or if the user is just moving the mouse around or scrolling, the Ui knows that nothing needs to be rerun.

- There are many libraries that rerun the declaration code quite often without attracting the same sort of skepticism, such as Iced. This may be a sign that some people are opposed about specific flaws of some naive immediate mode libraries rather than to the whole idea of rerunning declarative code.

- When people argue for avoiding even the price of redeclaration, they usually propose a "reactive" system, but these are usually very complicated with plenty of disadvantages beyond just the interface. Especially in non-web libraries, it seems that it's often implemented as a partial optimization layer over a redeclare-everything model.


These are all good arguments, but as always, we have to look at the other side. If the cost of rerunning the declaration code on every event was truly paralyzing, we'd have to just get over it and use some sort of reactive system anyway.

For this reason, this post will go into some detail into how the redeclaration code is implemented and how expensive it is to run it. 


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

Many of the people who assume that code like that is expensive probably have something like React in mind, where the redeclaration code would create a brand new tree from scratch to represent the desired state of the GUI, and then compared it to the retained one. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

There's definitely more reasonable ways to go about this. In Keru, whenever we `add()` a node, the function reaches into the node storage, and it either finds the old version of the node or creates it from scratch. If it finds an old node, it marks it as "fresh", updates its parameters, and updates its parent link to put it in the desired position within the tree.

Then, the properties of the new node are immediately diffed against the old one. If we find a difference, we can schedule any relayouts, rerenders, or transition animations if needed.

Finally, we have to do a quick linear scan over the node storage to clean up any lingering ones that were excluded from the new declaration.

I measured this in the [`ten_thousand.rs`](https://github.com/kekelp/keru/blob/master/examples/ten_thousand.rs) example, which shows a non-virtualized list of 10k elements. On my laptop from 2021, rerunning the declaration code takes about 4 milliseconds, and we can comfortably scroll and interact with the nodes at 120hz:

[ videos ]

There's a ton of space for more optimizations in Keru, especially in the unique layout algorithm or to improve general cache efficiency, but I don't want to get to them while the code is still in flux. With a bit of optimization and maybe a newer CPU, we can definitely go much higher than 10k.

At the same time, 10k is already way above what a 2D GUI should realistically have on screen at the same time! In reality, the list of 10k elements would be virtualized. 



## Further Optimization?

Still, some applications might have a legitimate need for ten thousand unvirtualized nodes, and four milliseconds isn't nothing.

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

## The Cost of Everything Else

Let's not forget that about all the other work that the GUI has to do every time something does happen:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with the number of nodes as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will probably be fine either way. At the end of the day, it's just unlikely that rerunning the declaration code will be what makes the difference between a snappy and efficient library and a slow or wasteful one.

## Thanks for Reading

If you are interested, check out [Keru's github page](https://github.com/kekelp/keru/), or the [other posts on this blog](@/blog/_index.md) .

