Practical Dependent Types in Haskell: Existential Neural Networks and Types at
Runtime
======================================================================================

> Originally posted by [Justin Le](https://blog.jle.im/).
> [Read online!](https://blog.jle.im/entry/practical-dependent-types-in-haskell-2.html)

We’re back to continue on [our
journey](https://blog.jle.im/entries/series/+practical-dependent-types-in-haskell.html)
in using dependent types to write type-safe neural networks! In [Part
1](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html), we
wrote things out in normal, untyped Haskell, and looked at red flags and general
design principles that nudged us in the direction of adding dependent types to
our program. We learned to appreciate what dependent types offered in terms of
guiding us in writing our code, helping the compiler check our correctness,
providing a better interface for users, and more.

We also learned how to use singletons to work around some of Haskell’s
fundamental limitations to let us “pattern match” on the structure of types, and
how to use typeclasses to generate singletons reflecting the structure of types
we are dealing with.

(If you read [Part
1](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html)
*before* the singletons section was re-written to use the
[singletons](https://hackage.haskell.org/package/singletons) library, [here’s a
link to the
section](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#singletons-and-induction)
in specific. This tutorial will assume familiarity with what is discussed
there!)

All of what we’ve dealt with so far has essentially been with types that are
fixed at compile-time. All the networks we’ve made have had “static” types, with
their sizes in their types indicated directly in the source code.

Today, we’re going to dive into the world of types that *depend* on factors
unknown until runtime, and see how dependent types in a strongly typed language
like Haskell helps us write safer, more correct, and more maintainable code.
Along the way, we’ll encounter and learn first-hand about techniques and guiding
high-level principles that we can apply to our other dependently typed coding
endeavours.

This post was written for GHC 8 on stackage snapshot
[nightly-2016-06-28](https://www.stackage.org/nightly-2016-06-28), but should
work with GHC 7.10 for the most part. All of the set-up instructions and caveats
(like the *singletons-2.0.1* bug affecting GHC 7.10 users and the unreleased
*hmatrix* version) are the same as for [part 1’s
setup](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#setup).

All of the code in this post is [downloadable as a standalone source
file](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs)
so you can follow along!

Types at Runtime
----------------

Recall the type we had for our neural networks:

``` {.haskell}
ghci> :k Network
Network :: Nat -> [Nat] -> Nat -> *
```

They’re of the form `Network i hs o`, where `i` is the size of the input vector
it expects, `hs` is the list of hidden layer sizes, and `o` is the size of the
output vector it produces. Something of type `Network 10 '[6, 4] 3` is a network
with 10 input nodes, two input layers of size 6 and 4, and 3 output nodes.

This is great and all, but there’s an severe limitation to this: Haskell is a
statically typed language, right? So doesn’t this mean that using a network
requires that you know the entire structure of the network at compile-time?

It’s conceivable that you might be able to have the input and output sizes known
at compile-time, but it’s possible that you don’t care or know your hidden layer
structure. You might load it from a configuration file, or have it depend on
user input. You might even want to receive one over a network channel without
knowing what the internal structure is. But can a type really depend on things
that you can’t know until runtime?

To illustrate more clearly:

``` {.haskell}
main :: IO ()
main = do
    putStrLn "What hidden layer structure do you want?"
    hs  <- readLn        :: IO [Integer]
    net <- randomNetwork :: IO 10 ??? 3   -- what is ???
    -- ...?
```

We *want* to put `hs` there where `???` is, but…`???` has to be a type (of kind
`[Nat]`). `hs` is a value (of type `[Integer]`). It’s clear here that the *type*
of our network depends on something we can’t write down or decide until runtime.

### An Existential Crisis

There are two main ways to go about solving this issue in Haskell. We’ll look at
both, and then see that they are really actually just two styles of doing the
same thing.

#### Types hiding behind constructors

Now, having the entire structure of your neural network in the type is nice and
all for cool tricks like `randomNet`…but do you *really* want to work with this
directly? After all, from the user’s perspective, the user really only ever
needs to know `i` and `o`: What vectors the network *expects*, and what vectors
the network *outputs*. In the end, all a (feed-forward) Neural Network really is
is an abstraction over a function `R i -> R o`.

Remember, the main benefits of having the entire structure in the type was to
help us *implement* our functions more safely, with the compiler’s help, and
also for cute return type polymorphism tricks like `randomNet` and `getNet`. The
first type of benefit really doesn’t benefit the *user* of the network.

Another downside of having the structure in the type is that we can’t store all
of them in the same list or data structure. A `Network 10 '[5,3] 1` won’t share
a list with a `Network 10 '[5,2] 1`, despite having the same inputs/outputs and
API.

Imagine that we had written a `Network` type that *didn’t* have the internal
structure in the type —

``` {.haskell}
data OpaqueNet i o
```

Recall that our issue earlier was that we had to write `Network i ??? o`, but we
had no idea what to put in for `???`. But, what if we worked with an
`OpaqueNet i o`, we wouldn’t even care! We wouldn’t have to tell GHC what the
internal structure is.

In fact, I’d actually argue that `OpaqueNet` is the type you should be offering
to your users or using yourself, because it only exposes the types that are a
part of its usage/API. You can store them in a list or MVar — `[OpaqueNet 10 3]`
and `MVar (OpaqueNet 10 3)`, serialize/deserialize them without knowing their
internal structure in advance (`loadNet :: FilePath -> IO (OpaqueNet 10 3)`),
etc. (if you wanted to load a `Network`, you would need to know exactly what
internal structure was stored, in advance). Though `Network` is a much easier
type when writing the *implementation*, `OpaqueNet` is a often much more ideal
type to *use*.

We can implement our vision for `OpaqueNet` as an “existential” wrapper over
`Network`, actually:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L106-107
data OpaqueNet :: Nat -> Nat -> * where
    ONet :: Network i hs o -> OpaqueNet i o

```

So, if you have `net :: Network 6 '[10,6,3] 2`, you can create
`ONet net :: OpaqueNet 6 2`. When you use the `ONet` constructor, the structure
of the hidden layers disappears from the type!

How do we use this type? We *pattern match* on `ONet` to get the net back, and
we can use them:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L109-121
runOpaqueNet :: (KnownNat i, KnownNat o)
             => OpaqueNet i o
             -> R i
             -> R o
runOpaqueNet n x = case n of
                     ONet n' -> runNet n' x

numHiddens :: OpaqueNet i o -> Int
numHiddens = \case ONet n -> go n
  where
    go :: Network i hs o -> Int
    go = \case O _      -> 0
               _ :&~ n' -> 1 + go n'

```

With the *ScopedTypeVariables* extension, we can even bring `hs` back into
scope, as in `ONet (n :: Network i hs o) -> ...`

This pattern is sometimes called the **dependent pair**, because pattern
matching on `ONet` gives yields the hidden **existentially quantified** type
(`hs`) and also a type that is based on it (`Network i hs o`). It’s like `hs`
“paired” with `Network i hs o`. Pattern match on the results to give both the
type (`hs`) *and* the data structure. (If we had implemented it as
`ONet :: Sing hs -> Network i hs o -> OpaqueNet i o`, this would be slightly
clearer!)

And here’s the key to making this all work: once you *do* pattern match on
`ONet`, you have to handle the `hs` in a *completely polymorphic way*. You’re
not allowed to assume anything about `hs`…you have to provide a completely
parametrically polymorphic way of dealing with it!

For example, this function is completely *not* ok:

``` {.haskell}
bad :: OpaqueNet i o -> Network i hs o
bad = \case ONet n -> n          -- nope, not ok at all.
```

Why not? Well, a type signature like `OpaqueNet i o -> Network i hs o` means
that the *caller* can decide what `hs` can be — just like
`read :: Read a => String -> a`, where the caller decides what `a` is.

Of course, this isn’t the case in the way we’ve written the function…the
function only returns a *specific* `hs` that the `OpaqueNet` decides. The
*caller* has to accommodate whatever is inside `ONet`.

#### The Universal and the Existential

We just brushed here on something at the heart of using existential types in
Haskell: the issue of who has the power to decide what the types will be
instantiated as. Most polymorphic functions you work with in Haskell are
“universally qualified”. For example, for a function like

``` {.haskell}
map :: (a -> b) -> [a] -> [b]
```

`a` and `b` are universally quantified, which means that the person who *uses*
`map` gets to decide what `a` and `b` are. To be more explicit, that type
signature can be written as:

``` {.haskell}
map :: forall a b. (a -> b) -> [a] -> [b]
```

This means that `map` is defined in a way that will work for *any* `a` and `b`
that the *caller* wants. As a caller, you can request:

``` {.haskell}
map :: (Int -> Bool)    -> [Int]    -> [Bool]
map :: (Double -> Void) -> [Double] -> [Void]
map :: (String -> (Bool -> Char)) -> [String] -> [Bool -> Char]
```

Consequentially, the function has to be implemented in a way that will work for
*any* `a` and `b`. The function’s implementation has the burden of being
flexible enough to handle whatever the caller asks for.

But, for a function like:

``` {.haskell}
foo :: [Int] -> OpaqueNet i o
```

While the caller can choose what `i` and `o` are, the *function* gets to choose
what `hs` (in the hidden `Network i hs o`) is. If I want to *use* the thing that
`foo` returns…then *I* have to be flexible. *I* have the burden of being
flexible enough to handle whatever the *function* returns.

In summary:

-   For universally quantified types, the *caller* chooses the type being
    instanced, and the *function’s implementation* has to accommodate
    any choice.

-   For existentially quantified types, the *function’s implementation* chooses
    the type being instanced, and the *caller* has to accommodate any choice.

Indeed, we saw earlier that if we ever wanted to *use* the `Network i hs o`
inside the `OpaqueNet i o`, we were forced to deal with it in a parametrically
polymorphic way. We had to be able to handle *any* `hs` that the `ONet` could
throw at us!

#### A familiar friend

I called `OpaqueNet i o` a “dependent pair” earlier, pairing `hs` with
`Network i hs o`. But there’s another common term for it: a **dependent sum**.

People familiar with Haskell might recognize that “sum types” are `Either`-like
types that can be one thing or another. Sum types are one of the first things
you learn about in Haskell — heck, even `Maybe a` is the sum of `a` and `()`.
Dependent pairs/existential types actually are very similar to `Either`/sum
types, in spirit, and it might help to see the parallel so that you can see that
they’re nothing scary, and that the fundamentals/intuition of working with
existential types in Haskell is no different than working with `Either`!

If I had:

``` {.haskell}
foo :: String -> Either Int Bool
```

I have to handle the result for both the case where I get an `Int` and the case
where I get a `Bool`. The *function* gets to pick what type I have to handle
(`Int` or `Bool`), and *I* have to adapt to whatever it returns. Sound familiar?
In fact, you can even imagine that `OpaqueNet i o` as being just a recursive
*Either* over `'[]`, `'[1]`, `'[1,2]`, etc.[^1]

Remember that the basic way of handling an `Either` and figuring out what the
type of the value is inside is through *pattern matching* on it. You can’t know
if an `Either Int Bool` contains an `Int` or `Bool` until you pattern match.
But, once you do, all is revealed, and GHC lets you take advantage of knowing
the type.

For `OpaqueNet i o`, it’s the same! You don’t know the actual type of the
`Network i hs o` it contains until you *pattern match* on the network! Once you
pattern match on it, all is revealed…and GHC lets you take advantage of knowing
the type!

### Reification

For simplicity, let’s re-write `randomNet` the more sensible way — with the
explicit singleton input style:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L78-85
randomNet' :: forall m i hs o. (MonadRandom m, KnownNat i, KnownNat o)
           => Sing hs -> m (Network i hs o)
randomNet' = \case SNil            ->     O <$> randomWeights
                   SNat `SCons` ss -> (:&~) <$> randomWeights <*> randomNet' ss

randomNet :: forall m i hs o. (MonadRandom m, KnownNat i, SingI hs, KnownNat o)
          => m (Network i hs o)
randomNet = randomNet' sing

```

We use `sing :: SingI hs => Sing hs` to go call the `Sing hs ->`-style function
from the `SingI hs =>` one.[^2]

Now, we still need to somehow get our list of integers to the type level so that
we can create a `Network i hs o` to stuff into our `ONet`. For that, the
*singletons* library offers the necessary tooling. It gives us `SomeSing`, which
is a lot like our `OpaqueNet` above, wrapping the `Sing a` inside an existential
data constructor. `toSing` takes the term-level value (for us, an `[Integer]`)
and returns a `SomeSing` wrapping the type-level value (for us, a `[Nat]`). When
we pattern match on the `SomeSing` constructor, we get `a` in scope!

As of *singletons-2.2* and GHC 8[^3], `SomeSing` is implemented as:

``` {.haskell}
data SomeSing :: * -> * where
    SomeSing :: Sing (a :: k) -> SomeSing k
```

And you have:

``` {.haskell}
foo :: SomeSing Bool
foo = SomeSing STrue

bar :: SomeSing Nat
bar = SomeSing (SNat :: Sing 10)
```

Pattern matching looks like:

``` {.haskell}
main :: IO ()
main = do
    putStrLn "How many cats do you own?"
    c <- readLn :: IO Integer
    case toSing c of
      SomeSing (SNat :: Sing n) -> -- ...
```

Now, inside the case statement branch (the `...`), we have *type* `n :: Nat` in
scope! And by pattern matching on the `SNat` constructor, we also have a
`KnownNat n` instance (As discussed in [previous
part](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#singletons-and-induction)).

`toSing` works using a simple typeclass mechanism with associated types whose
job is to associate *value*’s types with the kinds of their singletons. It
associates `Bool` (the type) with `Bool` (the kind), `Integer` (the type) with
`Nat` (the kind), `[Integer]` (the type) with `[Nat]` (the kind), etc., and it
does it with simple applications of type families — here’s a [nice tutorial on
type families](https://ocharles.org.uk/blog/posts/2014-12-12-type-families.html)
courtesy of Oliver Charles.

We now have enough to write our `randomONet`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L123-127
randomONet :: (MonadRandom m, KnownNat i, KnownNat o)
           => [Integer]
           -> m (OpaqueNet i o)
randomONet hs = case toSing hs of
                  SomeSing ss -> ONet <$> randomNet' ss

```

This process of bringing a term-level value into the type level is known in
Haskell as **reification**. With this, our original goal is (finally) within
reach:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L182-188
main :: IO ()
main = do
    putStrLn "What hidden layer structure do you want?"
    hs <- readLn
    ONet (net :: Network 10 hs 3) <- randomONet hs
    print net
    -- blah blah stuff with our dynamically generated net

```

#### The Boundary

With the power of existentially quantified types (like in `SomeSing`), we
essentially gained the ability to work with types that depend on runtime
results.

In a way, you can consider the `toSing` and the `SomeSing` as our “boundary”
between the “untyped world” and the “typed world”. This layer (and the process
of reification) cleanly separates the two.

This “boundary” can be thought of as a lot like the boundary we talk about
between “pure” functions and values and “impure” (IO, etc.) ones. People say to
always write as much of your program as possible in the “pure” world, and to
separate and pull out as much logic as you can to be pure logic. That’s one of
the first things you learn about as a Haskell programmer: how to separate logic
that *can* be pure from logic that is “impure” (IO, etc.), and then “combine
them” at the very end, as late as possible.

It’s easy to think that just because the final program is going to “be in IO in
the end anyway”, there isn’t any point in separating out pure and impure parts
of your program logic. But we know that we gain separation of concerns, the
increased ability to reason with your code and analyze what it does, the
compiler’s ability to check what you write, the limitation of implementations,
etc.

You can think of the general philosophy of working with typed/untyped worlds as
being the same thing. You can write as much of your program as possible in the
“typed” world, like we did in Part 1. Take advantage of the increased ability to
reason with your code, parametric polymorphism helping you *write* your code,
limit your implementations, nab you compiler help, etc. All of those are
benefits of working in the typed world.

Then, write what you must in your “untyped” world, such as dealing with values
that pop up at runtime like the `[Integer]` above.

Finally, at the end, *unite* them at the boundary. Pass the control football
from the untyped world to the typed world!

The great part about this all is that GHC and the type system is there at every
step holding your hand, guiding you as you implement your programs and making
sure everything is type-safe and fits together!

### Continuation-Based Existentials

There’s another way in Haskell that we work with existential types that can be
more natural to use in a lot of cases. Remember that when we pattern match on an
existential data type, you have to work with the values in the constructor in a
parametrically polymorphic way. For example, if we had:

``` {.haskell}
oNetToFoo :: OpaqueNet i o -> Foo
oNetToFoo = \case ONet n -> f n
```

`f` has to take a `Network i hs o` but deal with it in a way that works *for
all* `hs`. It has to be:

``` {.haskell}
f :: forall hs. Network i hs o -> Foo
```

That is, it can’t be written for *only* `'[5]` or *only* `'[6,3]`…it has to work
for *any* `hs`. That’s the whole “existential vs. universal quantification”
thing we just talked about.

Well, we could really also just skip the data type together and represent an
existential type as something *taking* the continuation `f` and giving it what
it needs.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L150-150
type OpaqueNet' i o r = (forall hs. Network i hs o -> r) -> r

```

“Tell me how you would make an `r` if you had a `Network i hs o` (that works for
any `hs`) and I’ll make it for you!”

(This takes advantage of Rank-N types. If you’re unfamiliar with them, Gregor
Riegler has a [nice
tutorial](http://sleepomeno.github.io/blog/2014/02/12/Explaining-Haskell-RankNTypes-for-all/)
on the subject.)

This “continuation transformation” is known as formally **skolemization**.[^4]
We can “wrap” a `Network i hs o` into an `OpaqueNet' i o r`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L152-153
oNet' :: Network i hs o -> OpaqueNet' i o r
oNet' n = \f -> f n

```

Let’s write a version of `randomONet` that returns a continuation-style
existential, instead:

``` {.haskell}
withRandomONet' :: (MonadRandom m, KnownNat i, KnownNat o)
                => [Integer]
                -> (forall hs. Sing hs -> Network i hs o -> m r)
                -> m r
--         aka, => [Integer]
--              -> OpaqueNet' i o (m r)
withRandomONet' hs f = case toSing hs of
                         SomeSing ss -> do
                           net <- randomNet' ss
                           f ss net
```

But, hey, because we’re skolemizing everything, let’s do it with the skolemized
version of `toSing`, `withSomeSing`:

``` {.haskell}
-- a version of `toSing` that returns a skolemized `SomeSing`
withSomeSing :: [Integer]
             -> (forall (hs :: [Nat]). Sing hs -> r)
             -> r
```

Because why not? Skolemize all the things!

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L155-163
withRandomONet' :: (MonadRandom m, KnownNat i, KnownNat o)
                => [Integer]
                -> (forall hs. Network i hs o -> m r)
                -> m r
--         aka, => [Integer]
--              -> OpaqueNet' i o (m r)
withRandomONet' hs f = withSomeSing hs $ \ss -> do
                         net <- randomNet' ss
                         f net

```

We can use it to do the same things we used the constructor-based existential
for, as well…and, in a way, it actually seems (oddly) more natural.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L190-196
main' :: IO ()
main' = do
    putStrLn "What hidden layer structure do you want?"
    hs <- readLn
    withRandomONet' hs $ \(net :: Network 10 hs 3) -> do
      print net
      -- blah blah stuff with our dynamically generated net

```

You can sort of see that, like the case statement pattern match represented the
lexical “wall”/“boundary” between the untyped and typed world when using
constructor-style existentials, the `... $ \net -> ...` can be thought of the
“wall” for the continuation-style existentials.

A Tale of Two Styles
--------------------

We’ve just discussed two ways of doing the same thing. Two styles of
representing/working with existential types. The two are equivalent, in that you
can always “convert” between one or the other, but the choice of which one you
use/reach for/offer can make a difference in code clarity. After working with
both styles a lot (sometimes, libraries only offer one style), you start to get
a feel for which one you like more in which situations. In the end, I don’t
think there are any hard or fast rules. Just use whichever one you feel is more
readable!

That being said, here are some general Pros and Cons that I’ve noticed over the
years:

-   Most obviously, continuation-style doesn’t require you to define a throwaway
    data type/constructor. While new types are cheap in Haskell, they force your
    users to learn a new set of types and constructors for every single
    existential type you return. If you or the library you’re writing
    uses/returns a *lot* of different existentially qualified types, all those
    extra dumb wrappers are a huge hassle.

-   When you have to use several existentials at once, continuation-style is
    much better because each nested existential doesn’t force another level of
    indentation:

    ``` {.haskell}
    foo = withSomeSing x $ \sx ->
          withSomeSing y $ \sy ->
          withSomeSing z $ \sz ->
            -- ...
    ```

    vs.

    ``` {.haskell}
    foo = case toSing x of
            SomeSing sx ->
              case toSing y of
                SomeSing sy ->
                  case toSing z of
                    SomeSing sz ->
                      -- ...
    ```

    Every time you nest a case statement, you actually waste *two* levels of
    indentation, which can be annoying even at 2-space indentation. But you
    don’t need *any* to nest in the continuation style!

-   If you’re working monadically, though, you can take advantage of do notation
    and *ScopedTypeVariables* for a nicer style that doesn’t require any nesting
    at all:

    ``` {.haskell}
    main = do
        ONet n1 <- randomONet [7,5,3] :: IO (OpaqueNet 10 1)
        ONet n2 <- randomONet [5,5,5] :: IO (OpaqueNet 10 1)
        ONet n3 <- randomONet [5,4,3] :: IO (OpaqueNet 10 1)
        hs <- readLn
        ONet (n4 :: Network 10 hs 1) <- randomONet hs
        -- ...
    ```

    Which is arguably nicer than

    ``` {.haskell}
    main = withRandomONet' [7,5,3] $ \n1 ->
           withRandomONet' [5,5,5] $ \n2 ->
           withRandomONet' [5,4,3] $ \n3 -> do
             hs <- readLn
             withRandomONet' hs $ \(n4 :: Network 10 hs 1) -> do
               -- ...
    ```

    A lot of libraries return existentials in `Maybe`’s ([base is
    guilty](http://hackage.haskell.org/package/base-4.9.0.0/docs/GHC-TypeLits.html#v:someNatVal)),
    so this trick can be useful for those, too!

    This trick is less useful for functions like `toSing` where things are *not*
    returned in a monad. You could wrap it in Identity, but that’s kind of
    silly:

    ``` {.haskell}
    foo = runIdentity $ do
            SomeSing sx <- Identity $ toSing x
            SomeSing sy <- Identity $ toSing y
            SomeSing sz <- Identity $ toSing z
            return $ -- ...
    ```

-   Constructor-style is necessary for writing typeclass instances. You can’t
    write a `Show` instance for `(forall hs. Network i hs o -> r) -> r`, but you
    can write one for `OpaqueNet i o`. We’ll also be writing `Binary` instances
    later for serialization/deserialization, and it only works
    with constructor-style.

-   Haskell doesn’t allow you to use Rank-N types as arguments to type
    constructors, so you can have `[OpaqueNet i o]`, but *not*
    `[OpaqueNet' i o r]` or `[(forall hs. Network i hs o -> r) -> r]`. You can
    have `IO (OpaqueNet i o)`, but not
    `IO ((forall hs. Network i hs o -> r) -> r)`. These are known as
    *impredicative* types, which are a big no-no in GHC Haskell. Don’t even go
    there! The constructor style is necessary in these situations unless you
    want to do a ContT-style skolemization, like
    `(forall hs. Network i hs o -> [r]) -> [r]` and
    `(forall hs. Network i hs o -> IO r) -> IO r`.

-   When writing functions that *take* existentials as inputs, the
    constructor-style is arguably more natural. For example, we wrote a function
    to find the number of hidden layers in a network earlier:

    ``` {.haskell}
    numHiddens :: OpaqueNet i o -> Int
    ```

    But the continuation-style version would have a slightly messier type:

    ``` {.haskell}
    numHiddens' :: ((forall hs. Network i hs o -> Int) -> Int)
                -> Int
    ```

    Even with with the type synonym, it’s a little awkward.

    ``` {.haskell}
    numHiddens' :: OpaqueNet' i o Int -> Int
    ```

    This is why you’ll encounter more functions *returning* continuation-style
    existentials than *taking* them in the wild, for the most part.

These are just general principles, not hard-fast rules. This list is nowhere
near exhaustive and reflects my current progress in my journey towards a
dependently typed lifestyle and also the things come to mind as I write this
blog post. If you come back in a month, you might see more things listed here!

All said, I do find myself very happy when I see that a library I’m using offers
*both* styles for me to use. And I’ve been known to submit PR’s to a library to
have it offer one style or another, if it’s lacking.

Be judicious. If you’re writing a library, don’t spam it with too many throwaway
constructors. After a while, you’ll begin to intuitively see which style shines
in which situations! (And, in some case, there might not even be a definitive
“better” style to use.)

Serializing Networks
--------------------

Let’s apply what we learned about existential types and reification to another
simple application: serialization.

### Recap on the Binary Library

Serializing networks of *known* size — whose sizes are statically in their types
— is pretty straightforward, and its ease is one of the often-quoted advantages
of having sizes in your types. I’m going to be using the
*[binary](https://hackage.haskell.org/package/binary)* library, which offers a
very standard typeclass-based approach for serializing and deserializing data.
There are a lot of tutorials online (and I even [wrote a small
one](https://blog.jle.im/entry/streaming-huffman-compression-in-haskell-part-2-binary.html)
myself a few years ago), but a very high-level view is that the library offers
monads (`Get`, `Put`) for describing serialization schemes and also a typeclass
used to provide serialization instructions for different types.

In practice, we usually don’t write our own instances from scratch. Instead, we
use GHC’s generics features to give us instances for free:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L25-30
data Weights i o = W { wBiases :: !(R o)
                     , wNodes  :: !(L o i)
                     }
  deriving (Show, Generic)

instance (KnownNat i, KnownNat o) => Binary (Weights i o)

```

For simple types like `Weights`, which simply contain serializable things, the
*binary* library is smart enough to write your instances automatically for you!
However, for GADTs like `Network`, we have to things manually.

#### Serializing `Network`

Writing `putNet` and `getNet` to put/get `Network`s is nice because the entire
structure is already known ahead of time:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L87-91
putNet :: (KnownNat i, KnownNat o)
       => Network i hs o
       -> Put
putNet = \case O w     -> put w
               w :&~ n -> put w *> putNet n

```

If it’s an `O w`, just serialize the `w`. If it’s a `w :&~ net`, serialize the
`w` then the rest of the `net`. The reason we can get away without any flags is
because we already *know* how many `:&~` layers to expect *just from the type*.
If we want to deserialize a `Network 5 '[10,6,3] 2`, we *know* we want three
`(:&~)`’s and one `O`.

We’ll write `getNet` similarly to how we wrote
[`randomNet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L78-81):

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L93-97
getNet :: forall i hs o. (KnownNat i, KnownNat o)
       => Sing hs
       -> Get (Network i hs o)
getNet = \case SNil            ->     O <$> get
               SNat `SCons` ss -> (:&~) <$> get <*> getNet ss

```

We have to “pattern match” on `hs` using singletons to see the constructor we
are expecting to deserialize and then just follow what the singleton’s structure
tells us.

To write a `Binary` instance for `Network`, we can’t have `get` take a `Sing hs`
input — that’d change the arity/type of the function. We have to switch to
`SingI`-style had have their `Binary` instances require a `SingI hs` constraint.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L99-101
instance (KnownNat i, SingI hs, KnownNat o) => Binary (Network i hs o) where
    put = putNet
    get = getNet sing

```

### Serializating `OpaqueNet`

Armed with all that we learned during our long and winding journey through
“run-time types”, writing a serializing plan for `OpaqueNet` is straightforward.
(We are doing it for `OpaqueNet`, the constructor-style existential, because we
can’t directly write instances for the continuation-style one)

It’s arguably much more useful to serialize/deserialize `OpaqueNet`s. Between
different iterations of your program, you might have the same inputs/outputs,
but want to try out different internal structures. You’d want to store them and
access them uniformly, or send them over a network without requiring the
receiver to know the internal structure beforehand. Remember, you can’t even
*load* a `Network i hs o` without knowing its complete structure!

Because the complete structure of the network is not in the type, to serialize
them, we have to encode it as a flag in the binary serialization. We can write a
simple function to get the `[Integer]` of a network’s structure:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L72-76
hiddenStruct :: Network i hs o -> [Integer]
hiddenStruct = \case O _    -> []
                     _ :&~ (n' :: Network h hs' o)
                            -> natVal (Proxy @h)
                             : hiddenStruct n'

```

Recall that `natVal :: KnownNat n => Proxy n -> Integer` returns the value-level
`Integer` corresponding to the type-level `n :: Nat`. (I’m also using GHC 8’s
fancy *TypeApplications* syntax, and `Proxy @h` is the same as
`Proxy :: Proxy h`).

Note that `natVal` and `hiddenStruct` take type-level information (`n`, `hs`)
and turns them into term-level values (`Integer`s, `[Integer]`s). They are kind
of the opposites of our reification functions like `toSing`. Going from the
“type level” to the “value level” is known in Haskell as **reflection**, and is
the dual concept of reification. (The *singletons* library offers reflectors for
all of its singletons, as `fromSing`.)

And that’s all we need!

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L129-134
putONet :: (KnownNat i, KnownNat o)
        => OpaqueNet i o
        -> Put
putONet = \case ONet net -> do
                  put (hiddenStruct net)
                  putNet net

```

“Put the structure (as a flag), and then put the network itself.”

Now, to deserialize, we want to *load* the list of `Integer`s and reify it back
to the type level to know what type of network we’re expecting to load:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L136-141
getONet :: (KnownNat i, KnownNat o)
        => Get (OpaqueNet i o)
getONet = do
    hs <- get
    withSomeSing hs $ \ss ->
      ONet <$> getNet ss

```

We load our flag, reify it, and once we’re back in the typed land again, we can
do our normal business. Isn’t it nice that GHC is also there at every step to
make sure we make the transition safely?

Our final instance:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L143-145
instance (KnownNat i, KnownNat o) => Binary (OpaqueNet i o) where
    put = putONet
    get = getONet

```

An Existance For All
--------------------

We’ve learned about how to “cross” from the untyped world to the typed world and
bring about contexts involving types that can depend on runtime factors. To me,
this is really where dependently typed programming starts — when you start
having to work with types that depend on run-time factors.

We’ve already been able to reap a lot of benefits. All of the type safety we
discovered in the last part is now available to us in a fully dynamic world, as
well. We also learned the advantages of *separating* the typed world from the
untyped world and how the compiler helps us make the transition safely.

But really, this is all just the *start* of dependently typed programming. This
is where things *really* start to get fun. For the most part, except for what is
basically syntactic sugar, everything we learned in the first part is mostly
standard, non-dependent Haskell, after all.

Stepping into this new world can be disorienting at first. There’s a lot of
unexpected things that come up when we start working more with these fancy new
types. We have to deal with types coming from multiple different sources,
convincing the type system about their properties and relationships between
them, and a whole bunch of other concerns that just don’t happen when you
program only at the value level. But, like all things, it comes more naturally
with practice.

We’ll see where our journey takes us next time!

#### Exercises

Here are some fun exercises you can try, if you want to test your understanding!
Links are to the solutions.

1.  Implement
    [`putONet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L165-170)
    and
    [`getONet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L172-180)
    using the continuation-style existentials, instead.

2.  Work with an existential wrapper over the *entire* network structure (inputs
    and outputs, too):

    ``` {.haskell}
    data SomeNet where
        SNet :: (KnownNat i, KnownNat o)
             => Network i hs o
             -> SomeNet
    ```

    (We need the `KnownNat` constraints because of type erasure, to recover the
    original input/output dimensions back once we pattern match)

    And write:

    -   A function to [convert `SomeNet`s to
        `OpaqueNet`s](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L206-210).
        Return the `OpaqueNet` with existentially quantified `i` and `o`
        in continuation-style. (You can write a data type to return it in
        constructor-style, too, for funsies.)
    -   [`randomSNet`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L212-221),
        returning `m SomeNet`.
    -   While you’re at it, write it to return [a random continuation-style
        `SomeNet`,
        too](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L223-234)!
        (See the type of
        [`withRandomONet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L155-163)
        for reference on how to write the type)
    -   The [binary
        instance](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L236-250)
        for `SomeNet`.

        Hint: Remember `natVal :: KnownNat n => Proxy n -> Integer`!

    Hint: Remember that `toSomeSing` also works for `Integer`s, to get `Sing`s
    for `Nat`s, too!

[^1]: A bit of a stretch, because the set of all `[Nat]`s is non-enumerable and
    uncountable, but hopefully you get the picture!

[^2]: Recall that I recommend (personally, and subjectively) a style where your
    external API functions and typeclass instances are implemented in
    `SingI a =>` style, and your internal ones in `Sing a ->` style. This lets
    all of your internal functions fit together more nicely (`Sing a ->` style
    tends to be easier to write in, especially if you stay in it the entire
    time, because `Sing`s are normal first-class values, unlike those global and
    magical typeclasses) while at the same time removing the burden of calling
    with explicit singletons from people using the functionality externally.

[^3]: In older versions of singletons, before GHC 8 and *TypeInType*, we had to
    implement it using “kind proxies”. Don’t worry if you’re following along in
    7.8; the basic usage of `SomeSing` is essentially identical either way.

[^4]: Skolemization is probably one of the coolest words you’ll encounter when
    learning/using Haskell, and sometimes just knowing that you’re “skolemizing”
    something makes you feel cooler. Thank you [Thoralf
    Skolem](https://en.wikipedia.org/wiki/Thoralf_Skolem). If you ever see a
    “rigid, skolem” error in GHC, you can thank him for that too! He is also the
    inspiration behind my decision to name my first-born son Thoralf. (My second
    son’s name will be Curry)
