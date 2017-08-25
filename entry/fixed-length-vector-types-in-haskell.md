Fixed-Length Vector Types in Haskell (an Update for 2017)
=========================================================

> Originally posted by [Justin Le](https://blog.jle.im/).
> [Read online!](https://blog.jle.im/entry/fixed-length-vector-types-in-haskell.html)

This post is a follow-up to my [fixed-length vectors in haskell in
2015](https://blog.jle.im/entry/fixed-length-vector-types-in-haskell-2015.html)
post! When I was writing the post originally, I was new to the whole type-level
game in Haskell; I didn’t know what I was talking about, and that post was a way
for me to push myself to learn more.

Immediately after it was posted, people taught me where I went wrong in the
idioms I explained, and better and more idiomatic ways to do things.
Unfortunately, I have noticed people referring to the post in a
canonical/authoritative way…so the post became an immediate regret to me. I
tried correcting things with my [practical dependent types in
haskell](https://blog.jle.im/entries/series/+practical-dependent-types-in-haskell.html)
series the next year, which incorporated what I had learned. But I still saw my
2015 post being used as a reference, so I figured that writing a direct
replacement/follow-up as the only way I would ever fix this!

So here we are in 2017. What’s the “right” way to do fixed-length vectors in
Haskell?

We’ll be looking at two methods here: The first one we will be looking at is a
*performant* fixed-length vector that you will probably be using for any code
that requires a fixed-length container — especially for tight numeric code and
situations where performance matters.

The second one we will be looking at is a *structural* fixed-length inductive
vector. It’s…actually more like a fixed-length *list* (lazily linked list) than
a vector, but it’s just called a vector because of tradition. The length of the
list is enforced by the very structure of the data type (similar to how
`Identity` is a container that is structurally enforced to have exactly one
item). This type is more useful as a streaming data type, and also in situations
where you want take advantage of the structural characteristics of lengths in
the context of a dependently typed program. It’s also very useful as an
“introduction” to dependently typed programming with inductive proofs.

The Non-Structural Way
----------------------

In most situations, if you use vectors, you want some sort of constant-time
indexed data structure. The best way to do this in Haskell is to wrap the
heavily optimized *[vector](http://hackage.haskell.org/package/vector)* library
with a newtype wrapper that contains its length as a phantom type parameter.

``` {.haskell}
import qualified Data.Vector as V

data Vec (n :: Nat) a = UnsafeMkVec { getVector :: V.Vector a }
    deriving Show
```

A `Vec n a` will represent an `n`-element vector of `a`s. So, a `Vec 5 Int` will
be a vector of five `Int`s, a `Vec 10 String` is a vector of 10 `String`s, etc.

For our numeric types, we’re using the fancy “type literals” that GHC offers us
with the `DataKinds` extension. Basically, alongside the normal kinds `*`,
`* -> *`, etc., we also have the `Nat` kind; type literals `1`, `5`, `100`, etc.
are all *types* with the *kind* `Nat`.

``` {.haskell}
ghci> :k 5
Nat
ghci> :k Vec
Vec :: Nat -> * -> *
```

You can “reflect” the type-level numeral as a value using the `KnownNat`
typeclass, provided by GHC, which lets you gain back the number as a run-time
value using `natVal`: (This process is called “reflection”)

``` {.haskell}
natVal :: KnownNat n => p n -> Natural
```

(Where `Natural`, from
*[Numeric.Natural](http://hackage.haskell.org/package/base-4.10.0.0/docs/Numeric-Natural.html)*,
is a non-negative `Integer` type.)

``` {.haskell}
ghci> natVal (Proxy @10)   -- or, natVal (Proxy :: Proxy 10)
10
ghci> natVal (Proxy @7)
7
```

Super low-level utility functions for the `Nat` kind (like `natVal`) are found
in the
*[GHC.TypeNats](http://hackage.haskell.org/package/base/docs/GHC-TypeNats.html)*
module (and also in
*[GHC.TypeLits](http://hackage.haskell.org/package/base/docs/GHC-TypeLits.html)*
for a slightly different API)

### The Smart Constructor

We can use `natVal` with the `KnownNat` typeclass to write a “smart constructor”
for our type – make a `Vec` from a `Vector`, but only if the length is the
correct type:

``` {.haskell}
mkVec :: forall n. KnownNat n => V.Vector a -> Maybe (Vec n a)
mkVec v | V.length v == l = Just (UnsafeMkVec v)
        | otherwise       = Nothing
  where
    l = fromIntegral (natVal (Proxy @n))
```

Here, we use `ScopedTypeVariables` so we can refer to the `n` in the type
signature in the function body (for `natVal (Proxy @n)`). We need to use an
explicit forall, then, to bring the `n` into scope.

### Utilizing type-level guarantees

Another operation we might want to do with vectors is do things with them that
might change their length in a predetermined way. We might want the type of our
vectors to describe the nature of the operations they are undergoing. For
example, if you saw a function:

``` {.haskell}
someFunc :: (a -> b) -> Vec n a -> Vec n b
```

You can see that it takes a function and a vector of length `n`, and returns
another vector of length `n`. Clearly, this function might be a “map” function,
which applies the function to all of the values in the `Vec`! We know that it
must have the same length, so it can’t drop or add items. (However, it could
still be shuffling or duplicating or permuting the items, as long as the
resulting length is the same)

In this situation, we can write such a mapping function in an “unsafe” way, and
then give it our type signature as a form of documentation:

``` {.haskell}
mapVec :: (a -> b) -> Vec n a -> Vec n b
mapVec f v = UnsafeMakeVec $ V.map f (getVector v)

-- just for fun
instance Functor (Vec n) where
    fmap = mapVec
```

The compiler didn’t help us write this function, and we have to be pretty
careful that the guarantees we specify in our types are reflected in the actual
unsafe operations. This is because our types don’t *structurally* enforce their
type-level lengths.

So, why bother? For us, here, our fixed-length vector types basically act as
“active documentation”, in a way. Compare:

``` {.haskell}
-- | Maps the function over the items in the vector, returning a vector of the
-- same length
mapVec :: V.Vector a -> V.Vector a -> V.Vector a
```

We have to rely on the documentation to *tell* us what the length of the final
resulting vector is, even though it can be known statically if you know the
length of the input vectors. The vectors have a *static relationship* in their
length, but this isn’t specified in a way that the compiler can take advantage
of.

By having our `mapVec :: (a -> b) -> Vec n a -> Vec m b`, the relationship
between the input lengths and output length is right there in the types, when
you *use* `mapVec`, GHC is aware of the relationships and can give you help in
the form of typed hole suggestions and informative type errors. You can even
catch errors in logic at compile-time instead of runtime!

``` {.haskell}
-- the resulting vector's length is the sum of the input vectors' lengths
(++) :: Vec n a -> Vec m a -> Vec (n + m) a
-- you must zip two vectors of the same length
zipVec :: Vec n a -> Vec n b -> Vec n (a, b)
-- type-level arithmetic to let us 'take'
take :: Vec (n + m) a -> Vec n a
-- splitAt, as well
splitAt :: Vec (n + m) a -> (Vec n a, Vec m a)
```

Here, `(+)` comes from GHC, which provides it as a type family (type-level
function) we can use, with proper meaning and semantics.

### Indexing

We need an appropriate type for indexing these, but we’d like a type where
indexing is “safe” – that is, that you can’t compile a program that will result
in an index error.

For this, we can use the
*[finite-typelits](http://hackage.haskell.org/package/finite-typelits)* package,
which provides the `Finite n` type.

A `Finite n` type is a type with exactly `n` distinct inhabitants/values. For
example, `Finite 4` contains four “anonymous” inhabitants. For convenience,
sometimes we like to name them 0, 1, 2, and 3. In general, we sometimes refer to
the values of type `Finite n` as 0 … (n - 1).

So, we can imagine that `Finite 6` has inhabitants corresponding to 0, 1, 2, 3,
4, and 5. We can convert back and forth between a `Finite n` and its `Integer`
representation using `packFinite` and `getFinite`:

``` {.haskell}
packFinite :: KnownNat n => Integer  -> Maybe (Finite n)
getFinite  ::               Finite n -> Integer
```

``` {.haskell}
ghci> map packFinite [0..3] :: [Finite 3]
[Just (finite 0), Just (finite 1), Just (finite 2), Nothing]
ghci> getFinite (finite 2 :: Finite 5)
2
```

We can use a `Finite n` to “index” a `Vector n a`. A `Vector n a` has exactly
`n` slots, and a `Finite n` has `n` possible values. Clearly, `Finite n` only
contains valid indices into our vector!

``` {.haskell}
index :: Vec n a -> Finite n -> a
index v i = getVector v V.! fromIntegral (getFinite i)
```

`index` will never fail at runtime due to a bad index — do you see why? Valid
indices of a `Vector 5 a` are the integers 0 to 4, and that is precisely the
exact things that `Finite 5` can store!

### Generating

We can directly generate these vectors in interesting ways. Using return-type
polymorphism, we can have the user *directly* request a vector length, *just* by
using type inference or a type annotation. (kind of like `read`)

For example, we can write a version of `replicate`:

``` {.haskell}
replicate :: forall n a. KnownNat n => a -> Vec n a
replicate x = UnsafeMkVec $ V.replicate l x
  where
    l = fromIntegral $ natVal (Proxy @n)
```

``` {.haskell}
ghci> replicate 'a' :: Vec 5 Char
UnsafeMkVec (V.fromList ['a','a','a','a','a'])
```

Note that normally, `replicate` takes an `Int` argument so that the user can
give how long the resulting vector needs to be. However, with our new
`replicate`, we don’t need that `Int` argument — the size of the vector we want
can more often than not be inferred automatigically using type inference!

With this new cleaner type signature, we can actually see that `replicate`’s
type is something very similar. Look at it carefuly:

``` {.haskell}
replicate :: KnownNat n => a -> Vec n a
```

You might recognize it as the haskellism `pure`:

``` {.haskell}
pure :: Applicative f => a -> f a
```

`replicate` is actually `pure` for the Applicative instance of `Vec n`! As an
extra challenge, what would `<*>` be?

#### Generating with indices

We can be a little more fancy with `replicate`, to get what we normally call
`generate`:

``` {.haskell}
generate :: forall n. KnownNat n => (Finite n -> a) -> Vec n a
generate f = UnsafeMkVec $ V.generate l (f . finite)
  where
    l = fromIntegral $ natVal (Proxy @n)
```

#### A discussion on the advantages of type-safety

I think it’s an interesting point that we’re using `Finite n` in a different
sense here than in `index`, for different reasons. In `index`, `Finite` is in
the “negative” position — it’s something that the function “takes”. In
`generate`, `Finite` is in the “positive” position — it’s something that the
function “gives” (to the `f` in `generate f`).

In the negative position, `Finite n` and type-safety is useful because:

1.  It tells the user what sort of values that the function expects. The user
    *knows*, just from the type, that indexing a `Vec 5 a` requires a
    `Finite 5`, or a number between 0 and 4.
2.  It guarantees that whatever `Finite n` index you give to `index` is a *valid
    one*. It’s impossible to give `index` an “invalid index”, so `index` is
    allowed to use “unsafe indexing” in its implementation, knowing that nothing
    bad can be given.
3.  It lets you develop code in “typed-hole” style: if a function requires a
    `Finite 4`, put an underscore there, and GHC will tell you about all the
    `Finite 4`s you have in scope. It can help you write your code for you!

In the positive position, `Finite n` and the type-safety have different uses and
advantages: it tells the user what sort of values the function can return, and
also also the type of values that the user has to be expected to handle. For
example, in `generate`, the fact that the user has to provide a `Finite n -> a`
tells the user that they have to handle every number between 0 and n-1, and
nothing else.

### Between Sized and Unsized

One key part of our API is missing: how to convert seamlessly between “sized”
and “unsized” vectors.

Converting from sized to unsized is easy, and we already have it:

``` {.haskell}
getVector :: Vec n a -> V.Vector a
```

Converting from unsized to sized is harder. We already saw a “shoe-horning”
method, if we know the size we want at compile-time:

``` {.haskell}
mkVec :: forall n. KnownNat n => V.Vector a -> Maybe (Vec n a)
```

But what if we don’t know what size `n` we want? What if we want `n` to be
whatever the actual size of the input vector is?

In general we can’t predict the size of our input vector at compile-time, so we
can’t just directly put in a size we want. What we want is a method to return a
`Vec n`, where `n` is the length of the input vector, determined at runtime.

I’m going to try to convince you that a plausible API is:

``` {.haskell}
withVec
    :: V.Vector a
    -> (forall n. KnownNat n => Vec n a -> r)
    -> r
```

People familiar with dependent types might recognized it as a CPS-style
existential. Basically, give the function a vector, and a way to “handle” a
`Vec n` of *any possible size*. The function will then give your handler a
`Vec n` of the proper type/size.

Within your continuation/handler, you can take advantage of the size, and do
take advantage of all of the type-level guarantees and benefits of a
length-indexed vector. In a way, it is its own “world” where your vector has a
fixed size. However, the caveat is that you have to treat the size *universally*
— you have to be able to handle any possible size given to you, in a
parametrically polymorphic way.

For example:

``` {.haskell}
ghci> myVector = V.fromList [10,5,8] :: V.Vector Int
ghci> withVec myVector $ \(v :: Vec n Int) ->
          -- in this function body, `v :: Vec 3 Int`, and `n ~ 3`
          -- whatever I return here will be the return value of the entire line
          case packFinite 1 :: Maybe (Finite n) of      -- Finite 3
            Nothing -> 0
            Just i  -> v `index` i
5
```

We could write, say, a function to always safely get the third item:

``` {.haskell}
getThird :: V.Vector a -> Maybe a
getThird v0 = withVec v0 $ \v -> fmap (v `index`) (packFinite 2)
```

And we can run it:

``` {.haskell}
ghci> getThird $ V.fromList [1,2,3]
Just 3
ghci> getThird $ V.fromList [1,2]
Nothing
```

We can even do something silly like convert an unsized vector to a sized vector
and then back again:

``` {.haskell}
vectorToVector :: V.Vector a -> V.Vector a
vectorToVector v = withVec toVector
```

Now that I’ve (hopefully) convinced you that this function really does convert
an unsized vector into a sized vector that you can use, let’s see how we can
implement it!

To do this, we can take advantage of the `someNatVal` function (from
*[GHC.TypeNats](http://hackage.haskell.org/package/base/docs/GHC-TypeNats.html)*):

``` {.haskell}
data SomeNat = forall n. KnownNat n => SomeNat (Proxy n)

someNatVal :: Natural -> SomeNat
```

`SomeNat` contains what we call an existentially quantified type, `n`.
Basically, a value of `SomeNat` contains a `Proxy n` with *some specific `n`*,
that is hidden “inside” the constructor. The only way to figure it out is to
pattern match on the constructor and use it in a generic and parametrically
polymorphic way. Sound familiar?

`someNatVal` converts `Natural` (a non-negative `Integer`) into a `SomeNat` — it
“picks” the right `n` (the one that corresponds to that `Natural`) and
stuffs/hides it into `SomeNat`. We can leverage this to write our `withVec`:

``` {.haskell}
withVec :: V.Vector a -> (forall n. KnownNat n => Vec n a -> r) -> r
withVec v0 f = case someNatVal (fromIntegral (V.length v0)) of
    SomeNat (Proxy :: Proxy m) -> f (UnsafeMkVec @m v0)
```

(The `TypeApplications` syntax `@m` is used with `UnsafeMkVec` to specify that
we want a `Vec m a`.)

This process is actually called “reification” – we take a value-level runtime
property (the length) and “reify” it, bringing it up to the type-level.

And now, we have both of our conversion functions! We can convert from sized to
unsized using `getVector`, and from unsized to sized using `withVec`.

### Verifying Properties

The final useful API aspect we will be looking at is how to verify properties of
our vector lengths at the type level, and let us use those properties.

One common thing we might want to do is ensure that two vectors have the same
length. This might happen when we use `withVec` from two different vectors, and
we get a `Vec n a` and `Vec m a` of two (potentially) different lengths.

We can do this using `sameNat` from
*[GHC.TypeNats](http://hackage.haskell.org/package/base/docs/GHC-TypeNats.html)*:

``` {.haskell}
-- `Type` is just a synonym for * from Data.Kind
data (:~:) :: k -> k -> Type where
    Refl :: x :~: x

sameNat
    :: (KnownNat n, KnownNat m)
    => Proxy n
    -> Proxy m
    -> Maybe (n :~: m)
```

The only way we can have a non-bottom value of type `n :~: m` is with the `Refl`
constructor, which can only be used in the case that `n` and `m` are equal.
`sameNat` gives us that `Refl`, if possible — that is, if `n` and `m` are equal.
If not, it gives us `Nothing`.

Now, we can write:

``` {.haskell}
exactLength :: forall n m. (KnownNat n, KnownNat m) => Vec n a -> Maybe (Vec m a)
exactLength v = case sameNat (Proxy @n) (Proxy @m) of
    Just Refl -> Just v     -- here, n ~ m, so a `Vec n a` is a `Vec m a`, too
    Nothing   -> Nothing
```

(We could also write this by using `getVector` and `mkLength`, which wraps and
unwraps, but let’s pretend it is expensive to construct and re-construct).

Now we can do:

``` {.haskell}
zipVec :: Vec n a -> Vec n b -> Vec n (a, b)

zipSame :: V.Vector a -> V.Vector b -> Maybe (V.Vector (a, b))
zipSame v1 v2 = withVec v1 $ \(v1' :: Vec n a) ->
                withVec v2 $ \(v2' :: Vec m a) ->
      case exactLength v1' of
        Just v1Same -> Just $ getVector
                          (zipVec v1Same v2')     -- v1' has the same length as v2'
        Nothing     -> Nothing
```

Which will zip two unsized vectors, but only if their lengths are the same.

### Help from singletons

You have probably heard that `TypeNats` and `TypeLits` provide a very bare-bones
and primitive interface. This is true. Its interface also doesn’t play well with
other type-level mechanisms in other libraries. To prepare you for the real
world, let’s re-implement these things using the
*[singletons](http://hackage.haskell.org/package/singletons)* library, which
provides a unified interface for type-level programming in general.

Instead of `KnownNat`, `Proxy`, `natVal`, `SomeNat`, and `someNatVal`, we can
use the singletons equivalents, `SingI` (or `Sing`), `fromSing`, `SomeSing`, and
`toSing`:

``` {.haskell}
-- TypeNats style
natVal :: KnownNat n => p n -> Natural

-- Singletons style
sing     :: SingI n => Sing n
fromSing :: Sing n -> Natural       -- (for n :: Nat)

-- TypeNats style
data SomeNat = forall n. KnownNat n => SomeNat (Proxy n)
someNatVal :: Natural -> SomeNat

-- Singletons style
data SomeSing Nat = forall n. SomeSing (Sing n)
someSing :: Natural -> SomeSing Nat

withSomeSing :: Natural -> (forall n. Sing n -> r) -> r
```

Hopefully the above should give you a nice “key” for translating between the two
styles. But here are some practical translations:

``` {.haskell}
-- "explicit Sing" style
mkVec_ :: Sing n -> V.Vector a -> Maybe (Vec n a)
mkVec_ s v | V.length v == l = Just (UnsafeMkVec v)
           | otherwise       = Nothing
  where
    l = fromIntegral (fromSing s)


-- "implicit SingI" style
mkVec_ :: forall n a. SingI n => V.Vector a -> Maybe (Vec n a)
mkVec_ v | V.length v == l = Just (UnsafeMkVec v)
         | otherwise       = Nothing
  where
    l = fromIntegral (fromSing (sing :: Sing n))

-- alternatively
mkVec :: SingI n => V.Vector a -> Maybe (Vec n a)
mkVec = mkVec_ sing
```

As you can see, in singletons, we have the luxury of defining our functions in
“explicit” style (where the user passes in a `Sing` token which reveals what
length they want) or “implicit” style (where the length is inferred from the
return type, requiring a `SingI n =>` constraint), like we have been writing up
to this point. `Sing n ->` and `SingI n =>` really have the same power.

``` {.haskell}
replicate_ :: Sing n -> a -> Vec n a
replicate_ s x = UnsafeMkVec $ V.replicate l x
  where
    l = fromIntegral (fromSing s)

replicate :: SingI n => a -> Vec n a
replicate = replicate_ sing

withVec :: V.Vector a -> (forall n. Sing n -> Vec n a -> r) -> r
withVec v0 f = case toSing (fromIntegral (V.length v0)) of
    SomeSing (s :: Sing m) -> f (UnsafeMkVec @m v0)

-- alternatively, skipping `SomeSing` altogether:
withVec :: V.Vector a -> (forall n. Sing n -> Vec n a -> r) -> r
withVec v0 f = withSomeSing (fromIntegral (V.length v0) :: Natural) $ \(s :: Sing m) ->
    f (UnsafeMkVec @m v0)
```

One slight bit of friction comes when using libraries that work with `KnownNat`,
like *finite-typelits* and the `Finite` type. But we can convert between the two
using `SNat` or `withKnownNat`

``` {.haskell}
-- SNat can be used to construct a `Sing` if we have a `KnownNat` constraint
-- It can also be pattern matched on to reveal a `KnownNat constraint`
SNat :: KnownNat n => Sing n

-- we can give a `Sing n` and be able to execute something in the context where
-- that `n` has a `KnownNat` constraint
withKnownNat :: Sing n -> (KnownNat n => r) -> r
```

``` {.haskell}
generate_ :: Sing n -> (Finite n -> a) -> Vec n a
generate_ s f = withKnownNat s $
    UnsafeMkVec $ V.generate l (f . finite)
  where
    l = fromIntegral $ natVal s

-- alternatively, via pattern matching:
generate_ :: Sing n -> (Finite n -> a) -> Vec n a
generate_ SNat f = UnsafeMkVec $ V.generate l (f . finite)
  where
    l = fromIntegral $ natVal s

generate :: SingI n => (Finite n -> a) -> Vec n a
generate = generate_ sing
```

As you can see, singletons-style programming completely subsumes programming
with `TypeNats` and `KnownNat`. What we don’t see here is that singletons style
integrates very well with the rest of the singletons ecosystem…so you might just
have to take my word for it :)

### Real-World Examples

This exact pattern is used in many real-world libraries. The canonical
fixed-length vector library implemented in this style is
*[vector-sized](http://hackage.haskell.org/package/vector-sized)*, which more or
less re-exports the entire *[vector](http://hackage.haskell.org/package/vector)*
library, but with a statically-sized interface. This is the library I use for
all my my modern sized-vector needs.

It’s also used to great benefit by the
*[hmatrix](http://hackage.haskell.org/package/hmatrix)* library, which I take
advantage of in my [dependently typed neural
networks](https://blog.jle.im/entries/series/+practical-dependent-types-in-haskell.html)
tutorial series.

It’s also provided in the
*[linear](http://hackage.haskell.org/package/linear-1.20.7/docs/Linear-V.html)*
library, which was one of the first major libraries to adopt this style.
However, it offers an incomplete API, and requires lens — its main purpose is
for integration with the rest of the
*[linear](http://hackage.haskell.org/package/linear-1.20.7/docs/Linear-V.html)*
library, which it does very well.

The Structural Way
------------------

The problem with `TypeNats` from GHC is that it has no internal structure. It’s
basically the same as the `Integer` or `Natural` type — every single value
(constructor) is completely structurally unrelated to the next.

Just like we can imagine

``` {.haskell}
data Int = .. -2 | -1 | 0 | 1 | 2 ...
```

We can also think of `Nat` as just `0 | 1 | 2 | 3 | 4 ...`. Each constructor is
completely distinct.

This is useful for most practical applications. However, when we want to use our
fixed-length types in a more subtle and nuanced way, it might help to work with
a length type that is more…structurally aware.

So, enough of this non-structural blasphemy. We are proper dependent type
programmers, dangit! We want structural verification! Compiler verification from
the very bottom!

For this, we’ll dig into *inductive* type-level nats.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L18-18
data Nat = Z | S Nat

```

We’re using the `DataKinds` extension, so not only does that define the *type*
`Nat` with the *values* `Z` and `S :: Nat -> Nat`, it also defines the *kind*
`Nat` with the *types* `'Z` and `'S :: Nat -> Nat`! (note the backticks)

``` {.haskell}
ghci> :t S Z
Nat
ghci> :k 'S 'Z
Nat
```

So `'Z` represents 0, and `'S` represents the “successor” function: one plus
whatever number it contains. `'S 'Z` represents 1, `'S ('S 'Z)` represents 2,
etc.

And now we can define a fixed-length *list*, which is basically a normal haskell
list “zipped” with `S`s.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L20-24
data Vec :: Nat -> Type -> Type where
    VNil :: Vec 'Z a
    (:+) :: a -> Vec n a -> Vec ('S n) a

infixr 5 :+

```

Here, we’re using `GADT` syntax to define our type using its constructors: the
`VNil` constructor (which creates a `Vec 'Z a`, or the empty vector, like `[]`)
and the `(:+)` constructor (like cons, or `(:)`), which conses an item to a
`Vec n a` to get a `Vec ('S n) a`, or a vector with one more element.

Basically, all usage of nil and cons (`VNil` and `:+`) keeps track of the
current “length” of the vectors in its type. Observe that the only way to
construct a `Vec ('S ('S 'Z)) a` is by using two `:+`s and a `VNil`!

``` {.haskell}
ghci> :t VNil
Vec 'Z a
ghci> :t True :+ VNil
Vec ('S 'Z) Bool
ghci> :t False :+ True :+ VNil
Vec ('S ('S 'Z)) Bool
```

### Type-level Guarantees are Structurally Free

One nice thing about this is that there is no “unsafe” way to construct a `Vec`.
Any `Vec` is *inherently of the correct size*. The very act of constructing it
enforces its length.

Remember our “unsafe” `mapVec`? We had to implement it unsafely, and trust that
our implementation is correct. Even worse — our *users* have to trust that our
implementation is correct!

But writing such a `mapVec` function using `Vec` is guaranteed to preserve the
lengths:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L26-29
mapVec :: (a -> b) -> Vec n a -> Vec n b
mapVec f = \case
    VNil    -> VNil
    x :+ xs -> f x :+ mapVec f xs



-- compare to
map :: (a -> b) -> [a] -> [b]
map f = \case
    [] -> []
    x:xs -> f x : map f xs
```

Our implementation is guaranteed to have the correct length. Neat! We get all of
the documentation benefits described in our previous discussion of `mapVec`,
plus more.

We can write `zip` too:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L31-36
zipVec :: Vec n a -> Vec n b -> Vec n (a, b)
zipVec = \case
    VNil -> \case
      VNil -> VNil
    x :+ xs -> \case
      y :+ ys -> (x,y) :+ zipVec xs ys

```

Isn’t it neat how the code reads exactly like the code for map/zip for *lists*?
Because their structure is identical, their only real difference is the
type-level tag. All of the functions we write are the same.

#### Type-Level Arithmentic

GHC provided our `+` before, so we have to write it ourselves if we want to be
able to use it for our `Nat`s. We can write it as a type family:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L38-45
type family (n :: Nat) + (m :: Nat) :: Nat where
    'Z   + m = m
    'S n + m = 'S (n + m)

(++) :: Vec n a -> Vec m a -> Vec (n + m) a
(++) = \case
    VNil    -> \ys -> ys
    x :+ xs -> \ys -> x :+ (xs ++ ys)

```

This works! However, we have to be careful that GHC can verify that the final
vector *really does* have the length `n + m`. GHC can do this automatically only
in very simple situations. In our situation, it is possible because `+` and `++`
have the *exact same structure*.

Take a moment to stare at the definition of `+` and `++` very closely, and then
squint really hard. You can see that `+` and `++` really describe the “same
function”, using the exact same structure. First, if the first item is a Z-y
thing, return the second item as-is. If the first item is a consy thing, return
the second item consed with the rest of the first item. Roughly speaking, of
course.

For examples where the function we write doesn’t exactly match the structure as
the type family we write, this won’t work. However, it works in these simple
cases. Conquering the trickier cases is a problem for another blog post!

### Indexing

To index our previous type, we used some abstract `Finite` type, where
`Finite n` conveniently represented the type of all possible indices to a
`Vec n a`. We can do something similar, inductively, as well:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L47-51
data Fin :: Nat -> Type where
    FZ :: Fin ('S n)
    FS :: Fin n -> Fin ('S n)

deriving instance Show (Fin n)

```

I always thought of this inductive definition of `Fin` as a cute trick, because
I don’t think there was any way I could have thought of it on my own. But if you
play around it enough, you might be able to convince yourself that there are
exactly `n` inhabitants of `Fin n`.

For example, for `Fin ('S 'Z)` (indices for a one-item vector), there should be
only one inhabitant. And there is! It’s `FZ`. `FS FZ` is not a valid inhabitant,
because it has type `Fin ('S ('S m))` for some `m`, so cannot possibly have the
type `Fin ('S 'Z)`.

Let’s see the inhabitants of `Fin ('S ('S ('S 'Z)))` (indices for three-item
vectors):

``` {.haskell}
ghci> FZ              :: Fin ('S ('S ('S 'Z)))
FZ
ghci> FS FZ           :: Fin ('S ('S ('S 'Z)))
FS FZ
ghci> FS (FS FZ)      :: Fin ('S ('S ('S 'Z)))
FS (FS FZ)
ghci> FS (FS (FS FZ)) :: Fin ('S ('S ('S 'Z)))
TYPE ERROR!  TYPE ERROR!  TYPE ERROR!
```

As GHC informs us, `FS (FS (FS FZ))` is not an inhabitant of
`Fin ('S ('S ('S 'Z)))`, which is exactly what we wanted. This is because
`FS (FS (FS FZ))` has type `Fin ('S ('S ('S ('S m))))` for some `m`, and this
can’t fit `Fin ('S ('S ('S 'Z)))`.

Also, note that there are no inhabitants of `Fin 'Z`. There is no constructor or
combinations of constructor that can yield that type.

Armed with this handy `Fin` type, we can do structural type-safe indexing:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L53-58
index :: Fin n -> Vec n a -> a
index = \case
    FZ -> \case
      x :+ _ -> x
    FS i -> \case
      _ :+ xs -> index i xs

```

Note that our `Fin` type structurally precludes us from being able to index into
a `Vec 'Z a` (an empty vector), because to do that, we would have to pass in a
`Fin 'Z`…but there is no such value with that type!

### Generating

Now, generating these is a bit tricky. Recall that we needed to use a
`KnownNat n` constraint to be able to *reflect* a `n` type down to the value
level. Alternatively, if we were super slick and used singletons, we could have
just used `fromSing` from the beginning.

Luckily, we don’t have the baggage of `KnownNat` on our new `Nat`. We can do
things the right way from the start: using singletons!

First, we need to get singletons for our `Nat`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L60-60
genSingletons [''Nat]



-- this creates:
data instance Sing :: Nat -> Type where
    SZ :: Sing 'Z
    SS :: Sing n -> Sing ('S n)
```

`Sing n` is a singleton for our `Nat`, in that there is only one `Sing n` for
every `n`. So, if we receive a value of type `Sing n`, we can pattern match on
it to figure out what `n` is. Essentially, we can *pattern match* on `n`.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L62-69
singSize :: Sing (n :: Nat) -> String
singSize = \case
    -- here, n is 'Z
    SZ        -> "Size of zero!"
    -- here, n is ('S 'Z)
    SS SZ     -> "Size of one!"
    -- here, n is ('S ('S n))
    SS (SS _) -> "Wow, so big!"

```

We can now branch depending on what `n` is!

Note that because of the inductive nature of our original `Nat` type, the
singletons are also inductive, as well. This is handy, because then our whole
ecosystem remains inductive.

Now, to write `replicate`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L71-74
replicate_ :: Sing n -> a -> Vec n a
replicate_ = \case
    SZ   -> \_ -> VNil
    SS l -> \x -> x :+ replicate_ l x

```

And we can recover our original “implicit” style, with type-inference-driven
lengths, using `SingI` and `sing :: SingI n => Sing n`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L71-74
replicate_ :: Sing n -> a -> Vec n a
replicate_ = \case
    SZ   -> \_ -> VNil
    SS l -> \x -> x :+ replicate_ l x

```

See how useful the whole singletons ecosystem is? :)

#### Generating with indices

Writing `generate` using the inductive `Fin` and `Nat` is an interesting
challenge. It’s actually a fairly standard pattern that comes up when working
with inductive types like these. I’m going to leave it as an exercise to the
reader – click the link at the top corner of the text box to see the solution,
and see how it compares to your own :)

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/fixvec-2/VecInductive.hs#L79-85
generate_ :: Sing n -> (Fin n -> a) -> Vec n a

generate :: SingI n => (Fin n -> a) -> Vec n a
generate = generate_ sing

```
