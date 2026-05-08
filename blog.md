
This first post is about the concepts of "Reactive" GUI and how relevant it is in the design of GUI libraries.

Keru is a "declarative" library, but it's not "reactive".

Keru code looks like this:

```rust
fn update_ui(state: &mut State, ui: &mut Ui) {
    // Define a unique identity for the button
    #[node_key] const INCREASE: NodeKey;
    
    // Create a Node struct describing a button
    let increase_button = BUTTON
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

All this code is run on every update. Is this a bad thing?
There's probably many people who would say yes. They might be thinking things like these:

- Oldschool imperative/retained-mode GUI systems were just better, because you'd just write the code for what you want to happen, instead of writing a high level declaration of what you want and having the library diff things to figure it out for you.

- Anything that looks like immediate mode is especially bad, because you're rerunning a bunch of code on every update.

- If anything, you should use a "reactive" system, where the library can keep track of which parts of your state affect which parts of your declarative model. And it better be "fine grained reactivity"!

The point of this post is to answer all these concerns.

# Definitions

Many of these words are used with different meanings by different people, so I'll have to spend some time explaining the sense in which they are used in this post.

## Declarative / Imperative

This is a property of how the library user's code looks like.

In a declarative system, the user writes a single description of the whole GUI. Keru's syntax above is declarative. Other examples are SwiftUI, `egui`, or React.

In contrast, in an imperative system, the user sets up a static initial state, and then manually writes the imperative changes that should happen as a result of input or other events.
This was never very popular, so people wrote plenty of user-level abstractions to try to hide this. But under the hood, you'd still find the manual changes to the retained tree.

## Reactive Programming / Redeclare-On-Every-Update

This is the most important distinction, between two ways of building declarative GUI systems.

Maybe someone can come up with a better term, but for now, I will use the term "Redeclare-On-Every-Update" to describe the systems where the GUI declaration is written in real code, and that whole code is re-executed on every update, to get a fresh new declaration of the target state of the GUI.

Keru's code above fits in this category, as well as egui and Dear Imgui and React. In this kind of system, you can use real language-level control flow to express the dynamicity of your GUI: a simple `if` for a conditionally-visible element, or a simple `for` for a dynamic list of elements.

On the other hand, I will use the term "Reactive Programming" to describe the systems like SwiftUI or SolidJS. In these systems, you write a static declaration of the GUI that is evaluated just once, in some sort of compilation step. The compiler statically analyzes how your declaration depends on the state variables, and inserts something like "setter methods" for them, which make sure that any change in the variable will be followed by a change in the GUI.

In this kind of system, the declarative form will have some sort of pseudo-control-flow structures that get compiled down statically. In SwiftUI, there's extensive compiler magic that can turn language-level `if`s and `for`s into those kind of structures, but that has limitations.

Note that despite the name, vanilla React is Redeclare-On-Every-Update, not Reactive-Programming.

## Retained

This is a property of how a GUI system is implemented internally.

A system is retained when it retains a lot of state between frames. We might be tempted to say that "Immediate" is the opposite of that. However, the word "Immediate" has been used with so many different and confusing meanings, that it's better to use it as little as possible.

## Incremental

A system is incremental when a small change to the program's state results in a small amount of recomputation. This is the performance property that the strawman arguments at the beginning are referring to.

- Note that incrementality is not about what happens "every frame", even when the program is fully idle. It's easy for even the most naive immediate-mode libraries to just do nothing where no input is being received at all.

- It's also easy to annotate which GUI elements should react to which input. So clicking on a non-interactive background element still shouldn't result in any needless work, regardless of the architecture.

- So, incrementality is really only about relatively complex GUIs with multiple parts, and in which it's common to interact with some parts while the rest stays still.

If a system doesn't retain any state, it probably won't be able to be very incremental. But any system that retains some of its state can be more or less incremental. The point of this post is to analyze how much the other distinctions affect incrementality.

In particular, how much incrementality do we lose by not being reactive?



# How to be incremental

Based on our definitions above, we can consider three different classes of GUI:
- However, there's these three types of GUI:

    1) Oldschool imperative GUI
    2) Reactive-Programming declarative GUI
    3) Redeclare-On-Every-Update declarative GUI

In 2026, there's not a whole lot of people who are clamoring for oldschool imperative GUI libraries, but it's useful to consider all three classes.

When an event arrives or some state changes, the GUI system has to do many things. Starting from the top layer, it first has to "consult" the library user's code, to determine what the user wants to change. Depending on the class:

1) In an imperative system, the library user's code will literally be a step by step description of what needs to be changed in the tree. Depending on the era, it would probably have to go through a bunch of wrappers, models, viewmodels, and other abstractions, but at the end of the day it would find some code in a callback somewhere that does all the changes that the wants. So the system just runs that code, and does nothing else.

2) A Reactive-Programming library will be able to look at what state variables changed, and thanks to the relationships that it already registered, it will automatically know what GUI elements it should update.

3) A Redeclare-On-Every-Update library will have to rerun all the declarative code that the library user provided. Then it will do some sort of diffing to see what to update.

In this first step, it's undeniable that the "rerun stuff every frame" libraries are at a disadvantage. They have to rerun their per-frame code to figure out what changes should be applied.

However, after this step, all three kinds of libraries will end up in the same position. They updated the internal element tree, but there's still a lot of work to do:

- recompute the layout
- rasterize new glyphs or relayout text that changed
- rebuild the render data (triangles, paths or other gpu primitives)
- rerender the pixels on the screen.

At this point, we're past the point where the interface differences matter. Any library can choose to make any of these computations more or less incremental depending on their performance characteristics, on how much they value memory usage vs speed, internal implementation complexity, etc.

So, the disadvantage of the "rerun stuff every frame" libraries is that they have to do *some* extra work when something changes. But to understand how much of a difference that really makes for performance, we have to examine what the code that is rerun is actually doing, and how it compares to all the other work that has to be done anyway.


# Keru's Redeclaration Code

It turns out that there's really not that much to do.
Looking back at the code above, we're mostly just creating a bunch of `Node`s on the stack, formatting a string, and calling `ui.add()` for each `Node`.

`ui.add()` will hash the visual and layout parameters of the provided Node, and it will do a lookup on a small HashMap to figure out what GUI node we're redeclaring. Then, it will access that node, set its tree links according to the structure of the nest() calls, and schedule a relayout or a repaint if the hashes are different.

Then, `ui.finish_frame()` will have to actually recompute the layout and rerender. But as we said before, that's the part that would work the same way regardless of the architecture.

`ui.add()` is the sort of function that we can expect to run many thousands of times before we ever get close to showing up in a profiler:
- it doesn't do any heap allocations.
- it's decently cache friendly: all the internal InnerNodes are stored in a contiguous Slab. Right now, the `InnerNode` struct is probably a big too big to be able to claim that it's really cache-friendly, but if that turns out to be measurably slow, it could be optimized, moving all the stuff that's not needed for `ui.add()` in a separate place.


If it's that simple, why did the Redeclare-On-Every-Update even end up with such a bad reputation in the first place? There's a few things that we can blame:

- The infamous "Immediate" name. I won't go into the details into the history of this word, but the result is that many people ended up assuming that when doing Redeclare-On-Every-Update, you'd also necessarily be in a system where there's no retained element tree at all. So you'd have to rebuild it from scratch as you re-executed the declarative code.

- The idea that it would be a good idea to recreate a whole new tree and compare it with the old one, rather than comparing each redeclared nodes with the old version of itself.

- The idea that every sort of tree or list needs to be a horrifically pointer-heavy and cache-inefficient structure spread across N separate heap allocations, rather than a slab and a handful of indices.

These are hopefully all relics of the past. However, there's a scarier one: even though the redeclaration code is usually just a few ui.add() calls, it's still the library user's custom code. The user can always make it arbitrarily bad. Then, he'd be right to complain that the library is slowing his program by reexecuting that code too many times.

I wasn't really there to see it with my own eyes, but it's not hard to imagine something like this happening to React. When you have a billion people writing React components in Javascript that keeps allocating all sort of crap and having the GC clean it up, you can see why some of these assumptions start to break, and why people start caring about component memoization, state management, or give up on Redeclare-On-Every-Update altogether and move to a reactive system.

Is this something that we should worry about in Rust? Well, yes. There's no GC, but doing a lot of needless heap allocations is still sort of common in Rust code. In fact, my example code above is allocating a string on the heap for no good reason.

In the blog post that explains the Xilem architecture, this is the example that justifies its memoization scheme:

> Going back to the counter, every time the app logic is called, it allocates a string for the label, even if it’s the same value as before. That’s not too bad if it’s the only thing going on, but as the UI scales it is potentially wasted work. [[1]](https://raphlinus.github.io/rust/gui/2022/05/07/ui-architecture.html)

But many years have passed since then. Now all the cool programmers on Twitter won't shut up about arenas, and the Bumpalo crate has been out for more than seven years. Maybe it's fine to just ask the library users to think of the planet and use that.
To make this easier, Keru exposes its own Bumpalo arena through a closure:

```rust
with_arena(|arena| {
    let count = bumpalo::format!(in arena, "Count: {:.2}", state.count);

    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&count));
    });
});
```

With the power of arenas and the common sense of the average non-Javascript programmer, we're probably in a solid spot.
We can expect most programs to redeclare their GUI in microseconds.

# The cost-benefit analysis

With this post, I hope to have made the case that despite the very high prevalence of the concept of "reactivity", it probably shouldn't be the first thing to focus on when evaluating GUI systems.

Well, actually, all I did was explain why redeclaring on every update doesn't have to be expensive. The other part of the message is that just like how most people naturally prefer writing GUI code in declarative style rather than imperative, I expect that most people will naturally prefer the simpler programming model of non-reactive systems ("Redeclare-On-Every-Update").

At the end of the day, that's a subjective thing: a matter of aesthetics. However, I feel like these aesthetic concerns are still very important. 

At this point, there's really no shortage or experimental GUI libraries in Rust, trying out all sorts of programming models. But none has really caught on, and none really seems to generate the sort of enthusiasm that people have for other libraries or for Rust itself. There's probably many different reasons for this, but one of the main ones is that the user-friendliness of many of these libraries remains low.

The library users are expected to internalize many concepts about "contexts" or "registers", to lay out all their state into special library-provided containers, or to write all their logic inside closures or trait impls. 

Often they are told that they should read many pages of abstract descriptions so that they can grasp the bigger picture, or maybe even that they shouldn't expect the documentation to hold their hand and they should figure out these complicated systems on their own.

There might be valid reasons for this sort of complexity, but "reactivity" is probably not one of them.


# Next Post: Can we have reactivity anyway, just for fun?

Even if we don't make it a core part of our programming model, it turns out that it's not hard to add some level of opt-in reactivity anyway, by skipping some redeclarations or with memoization. This is what happened in the React world.

In Keru, the "Component" trait allows to define reusable blocks of GUI code. Components can also manage their own state. The next post will show some examples of using Components to make pseudo-reactive components.


