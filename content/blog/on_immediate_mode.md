+++
title = "On \"Immediate Mode\""
date = 2026-08-21
+++

In [the previous post about Keru's interface](@/blog/interface.md), I argued that a simple and minimal interface is probably the most important goal for a GUI library, and if we take this goal really seriously, it leads us to adopt a model at least superficially similar to "immediate mode", where we often have to rerun all or most of the user's GUI declaration code.

My impression is that especially in the Rust community, anything that looks like "immediate mode" GUI is not very popular, so I felt like I had to defend this choice. Here's a summary of the arguments from that post: 


- It's not actually immediate mode: there's a `Ui` struct that retains the whole state of the GUI at all times. The declaration code just updates this retained state.

- The declaration code is not rerun "on every frame", but only when a meaningful event happens. If a click lands on a node not set to listen to it, or if the user is just moving the mouse around scrolling, or looking at animations, the Ui knows that nothing needs to be rerun.

- There are many libraries that rerun their declaration code quite often without attracting the same sort of skepticism, such as Iced. This may be a sign that people might be opposed to specific flaws of some naive immediate mode libraries rather than to the whole idea of rerunning declarative code.

- When people argue for avoiding even the price of redeclaration, they usually propose a "reactive" system, but these are usually very complicated with plenty of disadvantages beyond just the interface.

As always, we have to look at the other side. If the cost of rerunning the declaration code on every event was truly paralyzing, we'd have to just get over it and use some sort of reactive system anyway.

For this reason, this post will go into some detail on how the redeclaration code is implemented and how expensive it is to run it, and talk a bit about the usefulness of "immediate mode" as a label. 


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

As mentioned, we're not recreating a tree from scratch, but only detecting differences between the new declared state of the GUI and the retained state from last frame.

Many of the people who assume that's still expensive probably have something like React in mind, where the code would create a brand new tree from scratch to represent the new declared state, and then go through it to compare it to the retained one. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

There are definitely more reasonable ways to go about this. In Keru, whenever we `add()` a node, the function reaches into the node storage, and it either finds the old version of the node or creates it from scratch. If it finds an old node, it marks it as "fresh", updates its parameters, and updates its parent link to put it in the desired position within the tree.

Then, the properties of the new node are immediately diffed against the old one. If we find a difference, we can schedule any relayouts, rerenders, or transition animations if needed.

Finally, we have to do a quick linear scan over the node storage to clean up any lingering ones that were excluded from the new declaration.

I measured this in the [`ten_thousand.rs`](https://github.com/kekelp/keru/blob/master/examples/ten_thousand.rs) example, which shows a non-virtualized list of 10k elements. On my laptop from 2021, rerunning the declaration code takes about 4 milliseconds, and we can comfortably scroll and interact with the nodes at 120hz:

<video src="https://kekelp.github.io/keru/videos/ten_thousand.mp4" loop muted playsinline controls preload="metadata" style="width: 100%; height: auto;"></video>

Ten thousand isn't a big number for a computer, but it's already way above what a 2D GUI should realistically have on screen at the same time. In reality, a list like this should probably be virtualized regardless of the cost of redeclaring it. Offscreen nodes can be skipped when rendering, but they still take up memory and usually still need to be layouted.

In most realistic cases, we can expect the redeclaration to take a few hundred µs or less for a simple GUI, and maybe one or two ms for a complicated one. Nobody will mind.


## Further Optimization?

Still, some applications might have a legitimate need for ten thousand unvirtualized nodes, and four milliseconds isn't nothing.

Most of the time is spent moving around and comparing the `Node` structs, which aren't small.

If we were willing to go back and change the interface for the sake of performance, we could merge the `add()` function and the `Node` creation like this:

```rust
ui.add_button()
    .with_color(Color::RED)
    .with_size(Size::Big)
    .nest(|| { 
        ...
    })
```

In this case, the property builders themselves could reach directly into the node storage and compare the single field, which would likely be much cheaper.

But I think that using free stack variables for nodes is a significant ergonomic advantage, because it allows the builder code to be separated from the `nest()` calls that define the tree structure, and it allows the programmer to organize them into constants or associated values, to return them from functions, and so on.

The more general point here is that it's always more natural and more flexible to map the concepts of a library to the basic primitives of the language, when it is possible. It's much better for a `Node` to be a struct than an abstract concept that emerges out of a series of function calls and is only materialized somewhere deep inside the library outside of the user's view.

Another possible performance improvement could be to represent `Node`s as a list of changes over a default value rather than a full struct with values for every field. But that wouldn't be quite as natural, and in current day Rust there's no ergonomic way to use many variable length objects without making a lot of allocations on the global heap (although these would be the sort of short-lived ones that allocators are actually fairly good at dealing with).

If we *don't* want to make any changes to the interface, but we still want it to run a bit faster, there's probably space for some more internal optimizations as well. The cache efficiency of the internal node structs could definitely be improved, and maybe we could tweak the external `Node` so that the comparison can take advantage of vectorization. I'll get to it at some point.


## The Cost of Everything Else

Let's not forget about all the other work that the GUI has to do every time anything happens:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with the number of nodes as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will probably be fine either way. At the end of the day, it's just unlikely that rerunning the declaration code will be what makes the difference between a snappy and efficient library and a slow or wasteful one.

## Conclusion

What we have studied here is the tradeoff of rerunning declaration code to get the user's desired GUI state and diffing it, rather than setting up a reactive system that "already knows" how the GUI should change in all situations and can do minimal updates.

Every library has to choose where it wants to sit in this tradeoff space, and its decision will have important consequences on the outer interface of the library, so that it won't be able to change it without basically "becoming another library" in the eyes of its users. For this reason, this ends up being a meaningful architectural distinction, and it would make sense to give it an important sounding name, maybe something like **"declarative mode"** GUIs as opposed to **"reactive mode"**.

But what about **"immediate mode"**? The tradeoffs that people often associate with "immediate mode" are things like being unable to do partial relayouts or partial rerenders, having to rebuild the full node tree from scratch very often, or having to rerender on literally every frame (nobody actually does this).

As we saw in this post, none of these things are tied to the outer interface of the library in any way. The interfaces of immediate mode libraries look about the same as the ones in Keru and other non-immediate declarative libraries that don't make any of these other tradeoffs. In addition, most immediate mode libraries usually have some degree of retained state hidden somewhere, where they cache things like text and images. They're definitely not re-rasterizing text or re-decoding images "every frame".

So, as far as I understand it, there's really no reason why "immediate mode" should be treated as an important architectural decision in the tradeoff space of GUI libraries. Its tradeoffs are tradeoffs in the same sense as implementing or not implementing an optimization: you trade some simplicity in the internal architecture for some performance, but it's not really something that defines what the whole library is or isn't, and you can always get back to it and implement it later. It might not be easy, but it wouldn't be a major breaking change that turns your whole library into something else.


## Thanks for Reading

If you are interested, check out [Keru's github page](https://github.com/kekelp/keru/), or the [other posts on this blog](@/blog/_index.md).

