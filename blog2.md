

## Simplicity

- Simplicity is the most important thing. Nobody is using all these libraries because they're too hard to use. You can't require hours of study from a user to even get started, just to then hit them "you can't even have properly rendered text, btw". Let's try to be a bit more humble!

- keru minimal example. the basic concepts there are basically all that you really need.

- Nowadays it's easy to vibecode a half-baked library in an afternoon, then say that it's so much simpler than the full-featured alternatives. Try to convinve that this is a "simple things simple, complex things possible" situation, there is also more stuff like components with encapsulated state, advanced layout with grids and stuff, drag and drop, canvas drawing, imperative tree manipulation, integration with custom winit and wgpu, etc. 

## Flexibility

- Don't give up the winit loop, access all advanced winit features and wgpu rendering directly. Winit and wgpu are already wrappers! We can't go on wrapping things N times over.

- Freedom to organize the code however you want.
    - use keys to separate effects (still easily linked by go-to-definition.). 
    - use regular rust variables and constants to separate styling and other node params.
    - let the nesting structure be readable.
    - if you don't want, you're free to inline everything, or just write the effect right below, or even fall back to imgui style if you really want.

- freedom to separate code in helper functions. hint at key scopes and Components for even cleaner separation.

- Stateful Components can help with "state management" if you want. But totally optional. centralized-state is probably the best default. But if you want a button to have a fancy stateful animation, you can have that state be managed by the library, one instance for every button, cleaned up when the button disappears. 

- No "big idea" about the elm architecture or similar things. Still flexible enough to use the elm architecture if you want.

- Or even to make it retained/imperative mode. Tasteful hint at how literally nobody else does this. And how it can be used to make advanced components like the drag and drop thing.

- Not reactive by default, which means full flexibility about where to store state. If the program does anything interesting at all with the state besides displaying it in the gui, chances are that it won't be happy about having to fetch it from the GUI library's weird reactive containers! Full control over the data layout is also the #1 important thing for performance.

- very short rehearsal of why reactivity is overrated anyway from the other blog.md. Probably just the "every update not every frame" part, briefly the "redeclaration is a small part anyway, we have to do all this relayout and rerendering" part, and the "just use an arena" part.

- manual reactivity with readd_branch, and how doing manual change tracking isn't that hard to do at a component boundary, and how you can even make the component implicitly hold some state like a hash of the previous arguments.

## Performance

- Good heap discipline and data-oriented-programming in the internals.

- Can handle many thousands of nodes smoothly. ten_thousands.rs example with a non-virtualized list of 10k elements. It just works. There are no big numbers in GUI. It should be fast by default really.

- Most advanced cache efficiency optimizations not done yet to keep the code simple while it's in flux, but were tried a bit. definitely potential for even more performance if needed. Stop making excuses! GUI should be fast.

- Very fast custom renderer. Single draw call with dense primitive buffers and instance buffer for painter's order. A very branchy shader that switches on primitive type on the instance. Very simple and works great. Would still be cool to have a more modern compute-based renderer for partial blending and other effects. Open to using vello if it gets more usable in the future.

## Experimentation

- random list 