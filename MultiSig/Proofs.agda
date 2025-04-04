module MultiSig.Proofs where

open import Data.Product using (_×_; ∃; ∃-syntax; proj₁; proj₂) renaming (_,_ to ⟨_,_⟩)
open import Agda.Builtin.Char
open import Agda.Builtin.Equality
open import Agda.Builtin.Bool
open import Data.Nat
open import Data.Nat.Properties
open import Agda.Builtin.Nat using (_-_)
open import Agda.Builtin.Int
open import Data.List
open import Data.List.Properties
open import Data.List.Relation.Unary.Any
open import Data.List.Relation.Unary.All as All
open import Relation.Nullary
open import Relation.Binary.PropositionalEquality.Core
open import Data.Empty
open import Data.Sum.Base
open import Data.Product

open import Haskell.Prim hiding (⊥ ; All; Any)
open import Haskell.Prim.Integer
open import Haskell.Prim.Bool
open import Haskell.Prim.Eq
open import Haskell.Prim.Ord using (_<=_ ; _>=_)
open import Haskell.Prim using (lengthNat)

open import MultiSig.Model

record Context : Set where
  field
    value         : Value
    outVal        : Value
    outAdr        : PubKeyHash
    now           : Deadline
    tsig          : PubKeyHash
open Context

record State : Set where
  field
    label         : Label
    context       : Context
    continues     : Bool
open State

_∈_ : ∀ {A : Set} (x : A) (xs : List A) → Set
x ∈ xs = Any (x ≡_) xs

_∉_ : ∀ {A : Set} (x : A) (xs : List A) → Set
x ∉ xs = ¬ (x ∈ xs)

--Transition Rules

data _⊢_~[_]~>_ : Params → State → Input → State → Set where
  TPropose : ∀ {v pkh d s s' par}
    → value (context s) ≥ v
    → v ≥ minValue
    → label s ≡ Holding
    → label s' ≡ Collecting v pkh d []
    → value (context s) ≡ value (context s')
    → d ≤ (now (context s')) + (maxWait par)
    → continues s ≡ true
    → continues s' ≡ true
    -------------------
    → par ⊢ s ~[ (Propose v pkh d) ]~> s'

  TAdd : ∀ {sig par s s' v pkh d sigs}
    → sig ∈ (authSigs par)
    → tsig (context s') ≡ sig
    → label s ≡ Collecting v pkh d sigs
    → label s' ≡ Collecting v pkh d (insert sig sigs)
    → value (context s) ≡ value (context s')
    → continues s ≡ true
    → continues s' ≡ true
    -------------------
    → par ⊢ s ~[ (Add sig) ]~> s'

  TPay : ∀ {v pkh d sigs s s' par}
    → tsig (context s') ≡ pkh
    → value (context s) ≡ value (context s') + v
    → length sigs ≥ nr par
    → label s ≡ Collecting v pkh d sigs
    → label s' ≡ Holding
    → outVal (context s') ≡ v
    → outAdr (context s') ≡ pkh
    → continues s ≡ true
    → continues s' ≡ true
    -------------------
    → par ⊢ s ~[ Pay ]~> s'

  TCancel : ∀ {s s' par v pkh d sigs}
    → now (context s') > d
    → label s ≡ Collecting v pkh d sigs
    → label s' ≡ Holding
    → value (context s) ≡ value (context s')
    → continues s ≡ true
    → continues s' ≡ true
    -------------------
    → par ⊢ s ~[ Cancel ]~> s'

  TClose : ∀ {par s s'}
    → label s ≡ Holding
    → minValue > value (context s)
    → continues s ≡ true
    → continues s' ≡ false
    -------------------
    → par ⊢ s ~[ Close ]~> s'

data Unique {a : Set} : List a → Set where
  root : Unique []
  _::_ : {x : a} {l : List a} → x ∉ l → Unique l → Unique (x ∷ l)

≡ᵇto≡ : ∀ {a b} → (a ≡ᵇ b) ≡ true → a ≡ b
≡ᵇto≡ {zero} {zero} pf = refl
≡ᵇto≡ {suc a} {suc b} pf = cong suc (≡ᵇto≡ pf)

≡ⁱto≡ : ∀ {a b : Int} → (a == b) ≡ true → a ≡ b
≡ⁱto≡ {pos n} {pos m} pf = cong pos (≡ᵇto≡ pf)
≡ⁱto≡ {negsuc n} {negsuc m} pf = cong negsuc (≡ᵇto≡ pf)

==ito≡ : ∀ (a b : Int) → (a == b) ≡ true → a ≡ b
==ito≡ (pos n) (pos m) pf = cong pos (≡ᵇto≡ pf)
==ito≡ (negsuc n) (negsuc m) pf = cong negsuc (≡ᵇto≡ pf)

--Valid State
data ValidS : State → Set where

  Hol : ∀ {s}
    → label s ≡ Holding
    ----------------
    → ValidS s

  Col : ∀ {s v pkh d sigs}
    → label s ≡ Collecting v pkh d sigs
    → value (context s) ≥ v
    → v ≥ minValue
    → Unique sigs
    --------------------------------
    → ValidS s

  Stp : ∀ {s}
    → continues s ≡ false
    ----------------
    → ValidS s

--Multi-Step Transition
data _⊢_~[_]~*_ : Params → State → List Input → State → Set where

  root : ∀ { s par }
    ------------------
    → par ⊢ s ~[ [] ]~* s

  cons : ∀ { par s s' s'' i is }
    → par ⊢ s ~[ i ]~> s'
    → par ⊢ s' ~[ is ]~* s''
    -------------------------
    → par ⊢ s ~[ (i ∷ is) ]~* s''


--State Validity sub-lemmas
diffLabels : ∀ {v pkh d sigs} (l : Label) → l ≡ Holding
           → l ≡ Collecting v pkh d sigs → ⊥
diffLabels Holding p1 ()
diffLabels (Collecting v pkh d sigs) () p2

sameValue : ∀ {v v' pkh pkh' d d' sigs sigs'}
  → Collecting v pkh d sigs ≡ Collecting v' pkh' d' sigs' → v ≡ v'
sameValue refl = refl

sameSigs : ∀ {v v' pkh pkh' d d' sigs sigs'}
  → Collecting v pkh d sigs ≡ Collecting v' pkh' d' sigs' → sigs ≡ sigs'
sameSigs refl = refl

get⊥ : true ≡ false → ⊥
get⊥ ()

v=v : ∀ (v : Value) → (v ≡ᵇ v) ≡ true
v=v zero = refl
v=v (suc v) = v=v v

=/=ito≢ : ∀ {a b : Int} → (a == b) ≡ false → a ≢ b
=/=ito≢ {pos n} {pos .n} pf refl rewrite v=v n = get⊥ pf
=/=ito≢ {negsuc n} {negsuc .n} pf refl rewrite v=v n = get⊥ pf


reduce∈ : ∀ {A : Set} {x y : A} {xs} → y ∈ (x ∷ xs) → y ≢ x → y ∈ xs
reduce∈ (here px) p2 = ⊥-elim (p2 px)
reduce∈ (there p1) p2 = p1

insertPreserves∈ : ∀ {x y zs}
  → x ∈ insert y zs → (y == x) ≡ false → x ∈ zs
insertPreserves∈ {zs = []} (here px) p2 = ⊥-elim (=/=ito≢ p2 (sym px))
insertPreserves∈ {x} {y} {z ∷ zs} p1 p2 with y == x in eq1
...| true =  ⊥-elim (get⊥ p2)
...| false with y == z in eq2
...| true rewrite ==ito≡ y z eq2 = p1
...| false with x == z in eq3
...| true rewrite ==ito≡ x z eq3 = here refl
...| false = there (insertPreserves∈ (reduce∈ p1 (=/=ito≢ eq3)) eq1)


insertPreservesUniqueness : ∀ {sig sigs}
  → Unique sigs → Unique (insert sig sigs)
insertPreservesUniqueness root = (λ ()) :: root
insertPreservesUniqueness {sig} {(x ∷ xs)} (p :: ps) with sig == x in eq
...| false = (λ z → p (insertPreserves∈ z eq)) :: (insertPreservesUniqueness ps)
...| true rewrite ==ito≡ sig x eq = p :: ps

--State Validity Invariant
validStateTransition : ∀ {s s' : State} {i par}
  → ValidS s
  → par ⊢ s ~[ i ]~> s'
  → ValidS s'
validStateTransition iv (TPropose p1 (s≤s p2) p3 p4 p5 p6 p7 p8) rewrite p5 = Col p4 p1 (s≤s p2) root
validStateTransition {s} (Hol pf) (TAdd p1 p2 p3 p4 p5 p6 p7) = ⊥-elim (diffLabels (label s) pf p3)
validStateTransition (Col pf1 pf2 pf3 pf4) (TAdd p1 p2 p3 p4 p5 p6 p7)
                     rewrite pf1 | sameValue p3 | p5 | sameSigs p3
                     = Col p4 pf2 pf3 (insertPreservesUniqueness pf4)
validStateTransition (Stp pf) (TAdd p1 p2 p3 p4 p5 p6 p7) rewrite pf = ⊥-elim (get⊥ (sym p6))
validStateTransition iv (TPay p1 p2 p3 p4 p5 p6 p7 p8 p9) = Hol p5
validStateTransition iv (TCancel p1 p2 p3 p4 p5 p6) = Hol p3
validStateTransition iv (TClose p1 p2 p3 p4) = Stp p4

validStateMulti : ∀ {s s' : State} {is par}
  → ValidS s
  → par ⊢ s ~[ is ]~* s'
  → ValidS s'
validStateMulti iv root = iv
validStateMulti iv (cons pf x) = validStateMulti (validStateTransition iv pf) x

--Prop1 sub-lemmas and helper functions
makeIs : List PubKeyHash → List Input
makeIs [] = []
makeIs (x ∷ pkhs) = Add x ∷ makeIs pkhs

insertList : List PubKeyHash → List PubKeyHash → List PubKeyHash
insertList [] sigs = sigs
insertList (x ∷ asigs) sigs = insertList asigs (insert x sigs)

appendLemma : ∀ (x : PubKeyHash) (a b : List PubKeyHash) → a ++ x ∷ b ≡ (a ++ x ∷ []) ++ b
appendLemma x [] b = refl
appendLemma x (a ∷ as) b = cong (λ y → a ∷ y) (appendLemma x as b)

∈lemma : ∀ (xs ys : List PubKeyHash) (z : PubKeyHash) → z ∈ (xs ++ z ∷ ys)
∈lemma [] ys z = here refl
∈lemma (x ∷ xs) ys z = there (∈lemma xs ys z)

finalSig : ∀ (s : State) → (ls : List Input) → PubKeyHash
finalSig s [] = tsig (context s)
finalSig s (Propose x x₁ x₂ ∷ [])  = tsig (context s)
finalSig s (Add sig ∷ []) = sig
finalSig s (Pay ∷ []) = tsig (context s)
finalSig s (Cancel ∷ []) = tsig (context s)
finalSig s (i ∷ ls) = finalSig s ls

finalSigLemma : ∀ (s s' : State) (x : PubKeyHash) (xs : List PubKeyHash)
  → tsig (context s') ≡ x → finalSig s (makeIs (x ∷ xs)) ≡ finalSig s' (makeIs xs)
finalSigLemma s1 s2 x [] pf = sym pf
finalSigLemma s1 s2 x (y ∷ []) pf = refl
finalSigLemma s1 s2 x (y ∷ z ∷ xs) pf = finalSigLemma s1 s2 x (z ∷ xs) pf

--Generalized Prop1 (Can add signatures 1 by 1)
prop : ∀ {v pkh d sigs} (s s' : State) (par : Params) (asigs asigs' asigs'' : List PubKeyHash)
         → asigs ≡ (authSigs par)
         → asigs ≡ (asigs' ++ asigs'')
         → label s ≡ Collecting v pkh d sigs
         → label s' ≡ Collecting v pkh d (insertList asigs'' sigs)
         → outVal (context s) ≡ outVal (context s')
         → outAdr (context s) ≡ outAdr (context s')
         → now (context s) ≡ now (context s')
         → value (context s) ≡ value (context s')
         → tsig (context s') ≡ finalSig s (makeIs asigs'')
         → continues s ≡ true
         → continues s' ≡ true
         → par ⊢ s ~[ makeIs asigs'' ]~* s'

prop {v} {pkh} {d} {sigs}
  record { label = .(Collecting v pkh d sigs) ;
           context = record { value = .value₁ ;
                              outVal = .outVal₁ ;
                              outAdr = .outAdr₁ ;
                              now = .now₁ ;
                              tsig = tsig₁ } ;
           continues = True }
  record { label = .(Collecting v pkh d (insertList [] sigs)) ;
           context = record { value = value₁ ;
                              outVal = outVal₁ ;
                              outAdr = outAdr₁ ;
                              now = now₁ ;
                              tsig = .(finalSig (record { label = Collecting v pkh d sigs ;
                                                          context = record { value = value₁ ;
                                                                             outVal = outVal₁ ;
                                                                             outAdr = outAdr₁ ;
                                                                             now = now₁ ;
                                                                             tsig = tsig₁ } ;
                                                          continues = true }) (makeIs [])) } ;
           continues = True }
  record { authSigs = .(sigs2 ++ []) ;
           nr = nr₁ }
  .(sigs2 ++ []) sigs2 [] refl refl refl refl refl refl refl refl refl refl refl = root

prop {v} {pkh} {d} {sigs}
  s1@(record { label = .(Collecting v pkh d sigs) ;
               context = record { value = .value₁ ;
                                  outVal = .outVal₁ ;
                                  outAdr = .outAdr₁ ;
                                  now = .now₁ ;
                                  tsig = tsig₁ } })
  s2@(record { label = .(Collecting v pkh d (insertList (x ∷ sigs3) sigs)) ;
               context = record { value = value₁ ;
                                  outVal = outVal₁ ;
                                  outAdr = outAdr₁ ;
                                  now = now₁ ;
                                  tsig = .(finalSig s1 (makeIs (x ∷ sigs3))) } })
  par@(record { authSigs = .(sigs2 ++ x ∷ sigs3) ; nr = nr₁ })
  .(sigs2 ++ x ∷ sigs3) sigs2 (x ∷ sigs3) refl refl refl refl refl refl refl refl refl refl refl

  = cons
    (TAdd (∈lemma sigs2 sigs3 x) refl refl refl refl refl refl)
    (prop s' s2 par (sigs2 ++ x ∷ sigs3) (sigs2 ++ [ x ]) sigs3 refl
          (appendLemma x sigs2 sigs3) refl refl refl refl refl refl
          (finalSigLemma s1 s' x sigs3 refl) refl refl)
    where
      s' = record { label = Collecting v pkh d (insert x sigs) ;
                    context = record { value = value₁ ;
                                       outVal = outVal₁ ;
                                       outAdr = outAdr₁ ;
                                       now = now₁ ;
                                       tsig = x }}



prop' : ∀ {v pkh d sigs} (s s' : State) (par : Params) (asigs asigs' asigs'' asigs''' : List PubKeyHash)
         → asigs ≡ (authSigs par)
         → asigs ≡ (asigs' ++ asigs'' ++ asigs''')
         → label s ≡ Collecting v pkh d sigs
         → label s' ≡ Collecting v pkh d (insertList asigs'' sigs)
         → outVal (context s) ≡ outVal (context s')
         → outAdr (context s) ≡ outAdr (context s')
         → now (context s) ≡ now (context s')
         → value (context s) ≡ value (context s')
         → tsig (context s') ≡ finalSig s (makeIs asigs'')
         → continues s ≡ true
         → continues s' ≡ true
         → par ⊢ s ~[ makeIs asigs'' ]~* s'

prop' {v} {pkh} {d} {sigs}
  record { label = .(Collecting v pkh d sigs) ;
           context = record { value = .value₁ ;
                              outVal = .outVal₁ ;
                              outAdr = .outAdr₁ ;
                              now = .now₁ ;
                              tsig = tsig₁ } ;
           continues = True }
  record { label = .(Collecting v pkh d (insertList [] sigs)) ;
           context = record { value = value₁ ;
                              outVal = outVal₁ ;
                              outAdr = outAdr₁ ;
                              now = now₁ ;
                              tsig = .(finalSig (record { label = Collecting v pkh d sigs ;
                                                          context = record { value = value₁ ;
                                                                             outVal = outVal₁ ;
                                                                             outAdr = outAdr₁ ;
                                                                             now = now₁ ;
                                                                             tsig = tsig₁ } ;
                                                          continues = true }) (makeIs [])) } ;
           continues = True }
  record { authSigs = .(sigs2 ++ [] ++ sigs3) ;
           nr = nr₁ }
  .(sigs2 ++ [] ++ sigs3) sigs2 [] sigs3 refl refl refl refl refl refl refl refl refl refl refl = root

prop' {v} {pkh} {d} {sigs}
  s1@(record { label = .(Collecting v pkh d sigs) ;
               context = record { value = .value₁ ;
                                  outVal = .outVal₁ ;
                                  outAdr = .outAdr₁ ;
                                  now = .now₁ ;
                                  tsig = tsig₁ } })
  s2@(record { label = .(Collecting v pkh d (insertList (x ∷ sigs3) sigs)) ;
               context = record { value = value₁ ;
                                  outVal = outVal₁ ;
                                  outAdr = outAdr₁ ;
                                  now = now₁ ;
                                  tsig = .(finalSig s1 (makeIs (x ∷ sigs3))) } })
  par@(record { authSigs = .(sigs2 ++ x ∷ sigs3 ++ sigs4) ; nr = nr₁ })
  .(sigs2 ++ x ∷ sigs3 ++ sigs4) sigs2 (x ∷ sigs3) sigs4 refl refl refl refl refl refl refl refl refl refl refl

  = cons
    (TAdd (∈lemma sigs2 (sigs3 ++ sigs4) x) refl refl refl refl refl refl)

    (prop' s' s2 par (sigs2 ++ x ∷ sigs3 ++ sigs4) (sigs2 ++ [ x ]) sigs3 sigs4 refl
          (appendLemma x sigs2 (sigs3 ++ sigs4)) refl refl refl refl refl refl
          (finalSigLemma s1 s' x sigs3 refl) refl refl)
    where
      s' = record { label = Collecting v pkh d (insert x sigs) ;
                    context = record { value = value₁ ;
                                       outVal = outVal₁ ;
                                       outAdr = outAdr₁ ;
                                       now = now₁ ;
                                       tsig = x }}


--Actual Prop1 (Can add all signatures 1 by 1)
prop1 : ∀ { v pkh d sigs } (s s' : State) (par : Params)
        → label s ≡ Collecting v pkh d sigs
        → label s' ≡ Collecting v pkh d (insertList (authSigs par) sigs)
        → outVal (context s) ≡ outVal (context s')
        → outAdr (context s) ≡ outAdr (context s')
        → now (context s) ≡ now (context s')
        → value (context s) ≡ value (context s')
        → tsig (context s') ≡ finalSig s (makeIs (authSigs par))
        → continues s ≡ true
        → continues s' ≡ true
        → par ⊢ s ~[ (makeIs (authSigs par)) ]~* s'
prop1 s s' par p1 p2 p3 p4 p5 p6 p7 p8 p9 = prop s s' par (authSigs par) [] (authSigs par) refl refl p1 p2 p3 p4 p5 p6 p7 p8 p9


--UniqueInsertLemma sub-lemmas
_⊆_ : List a → List a → Set
l1 ⊆ l2 = All (_∈ l2) l1

⊆-cons : (x : a){l1 l2 : List a} → l1 ⊆ l2 → l1 ⊆ (x ∷ l2)
⊆-cons x [] = []
⊆-cons x (px ∷ p) = there px ∷ ⊆-cons x p

⊆-refl : (l : List a) → l ⊆ l
⊆-refl [] = []
⊆-refl (x ∷ l) = here refl ∷ ⊆-cons x (⊆-refl l)

⊆-trans : {l1 l2 l3 : List a} → l1 ⊆ l2 → l2 ⊆ l3 → l1 ⊆ l3
⊆-trans [] p2 = []
⊆-trans (px ∷ p1) p2 = All.lookup p2 px ∷ ⊆-trans  p1 p2


insert-lem1 : (x : PubKeyHash)(l : List PubKeyHash) → x ∈ insert x l
insert-lem1 x [] = here refl
insert-lem1 x (y ∷ l) with x == y in eq
... | false = there (insert-lem1 x l)
... | true rewrite ==ito≡ x y eq = here refl

insert-lem2 : (x y : PubKeyHash)(l : List PubKeyHash) → x ∈ l → x ∈ insert y l
insert-lem2 x y [] pf = there pf
insert-lem2 x y (z ∷ l) (here px) with y == z in eq
...| false rewrite px = here refl
...| true rewrite ==ito≡ y z eq | px = here refl
insert-lem2 x y (z ∷ l) (there pf) with y == z in eq
...| false = there (insert-lem2 x y l pf)
...| true rewrite ==ito≡ y z eq = there pf

del : ∀{x} (l : List a) → x ∈ l → List a
del (_ ∷ xs) (here px) = xs
del (x ∷ xs) (there p) = x ∷ del xs p

length-del : ∀{x}{l : List a} (p : x ∈ l) → suc (length (del l p)) ≡ length l
length-del (here px) = refl
length-del (there p) = cong suc (length-del p)

∈-del : ∀{x y}{l : List a} (p : x ∈ l) → x ≢ y → y ∈ l → y ∈ del l p
∈-del (here refl) e (here refl) = ⊥-elim (e refl)
∈-del (there p)   e (here refl) = here refl
∈-del (here refl) e (there w) = w
∈-del (there p)   e (there w) = there (∈-del p e w)

subset-del : ∀{x}{l1 l2 : List a} (p : x ∈ l2) → (x ∉ l1) → l1 ⊆ l2 → l1 ⊆ del l2 p
subset-del p n [] = []
subset-del p n (px ∷ su) = ∈-del p (λ e → n (here e)) px ∷ subset-del p (λ p → n (there p)) su

unique-lem : {l1 l2 : List a} → l1 ⊆ l2 → Unique l1 → length l2 ≥ length l1
unique-lem [] root = z≤n
unique-lem (px ∷ sub) (x :: un) rewrite sym (length-del px) = s≤s (unique-lem (subset-del px x sub) un)

insertList-sublem : (l1 l2 : List PubKeyHash) (x : PubKeyHash) → x ∈ l2 → x ∈ insertList l1 l2
insertList-sublem [] l x pf = pf
insertList-sublem (y ∷ l1) l2 x pf = insertList-sublem l1 (insert y l2) x (insert-lem2 x y l2 pf)


insertList-lem : (l1 l2 : List PubKeyHash) → l1 ⊆ insertList l1 l2
insertList-lem [] l = []
insertList-lem (x ∷ l1) l2 = insertList-sublem l1 (insert x l2) x (insert-lem1 x l2) ∷ insertList-lem l1 (insert x l2)

--Unique Insert Lemma
uil : ∀ (l1 l2 : List PubKeyHash) (pf : Unique l1) → (length (insertList l1 l2) ≥ length l1)
uil l1 l2 pf = unique-lem (insertList-lem l1 l2) pf


--Valid Parameters
data ValidP : Params → Set where

  Always : ∀ {par}
    → Unique (authSigs par)
    → length (authSigs par) ≥ nr par
    ------------------
    → ValidP par


--Multi-Step lemma
lemmaMultiStep : ∀ (par : Params) (s s' s'' : State) (is is' : List Input)
                   → par ⊢ s  ~[ is  ]~* s'
                   → par ⊢ s' ~[ is' ]~* s''
                   → par ⊢ s  ~[ is ++ is' ]~* s''
lemmaMultiStep par s .s s'' [] is' root p2 = p2
lemmaMultiStep par s s' s'' (x ∷ is) is' (cons {s' = s'''} p1 p2) p3 = cons p1 (lemmaMultiStep par s''' s' s'' is is' p2 p3)


--Prop2 (Can add signatures 1 by 1 and then pay)
prop2' : ∀ { v pkh d sigs } (s s' : State) (par : Params)
          → ValidS s
          → label s ≡ Collecting v pkh d sigs
          → label s' ≡ Holding
          → outVal (context s') ≡ v
          → outAdr (context s') ≡ pkh
          → value (context s) ≡ value (context s') + v
          → ValidP par
          → continues s ≡ true
          → continues s' ≡ true
          → tsig (context s') ≡ pkh
          → par ⊢ s ~[ ((makeIs (authSigs par)) ++ [ Pay ]) ]~* s'
prop2' {d = d} {sigs = sigs}
  s1@(record { label = .(Collecting (outVal context₁) (outAdr context₁) d sigs) ;
               context = record { value = .(addNat (value context₁) (outVal context₁)) ;
                                  outVal = outVal₁ ;
                                  outAdr = outAdr₁ ;
                                  now = now₁ ;
                                  tsig = tsig₁ } })
  s2@record { label = .Holding ; context = context₁ }
  par (Col p1 p2 p3 p6) refl refl refl refl refl (Always p4 p5) refl refl refl
  = lemmaMultiStep par s1 s' s2 (makeIs (authSigs par)) [ Pay ]
    (prop1 s1 s' par refl refl refl refl refl refl refl refl refl)
    (cons (TPay refl refl (≤-trans p5 (uil (authSigs par) sigs p4)) refl refl refl refl refl refl) root)
      where
        s' = record { label = Collecting (outVal context₁) (outAdr context₁) d (insertList (authSigs par) sigs) ;
                       context = record { value = (addNat (value context₁) (outVal context₁)) ;
                                          outVal = outVal₁ ;
                                          outAdr = outAdr₁ ;
                                          now = now₁ ;
                                          tsig = finalSig (record { label = (Collecting (outVal context₁) (outAdr context₁) d sigs) ;
                                                                    context = record { value = (addNat (value context₁) (outVal context₁)) ;
                                                                              outVal = outVal₁ ;
                                                                              outAdr = outAdr₁ ;
                                                                              now = now₁ ;
                                                                              tsig = tsig₁ } }) (makeIs (authSigs par)) } }


takeLength : ∀ {a : Nat} {l : List PubKeyHash} → length l ≥ a → a ≤ length (take a l)
takeLength {.zero} {[]} z≤n = z≤n
takeLength {zero} {x ∷ l} p = z≤n
takeLength {suc a} {x ∷ l} (s≤s p) rewrite length-take a (x ∷ l) = s≤s (takeLength p)

∈take : ∀ {y : PubKeyHash} {a : Nat} {l : List PubKeyHash} → y ∈ take a l → y ∈ l
∈take {y} {suc a} {x ∷ l} (here px) = here px
∈take {y} {suc a} {x ∷ l} (there p) = there (∈take p)

∉take : ∀ {y : PubKeyHash} {a : Nat} {l : List PubKeyHash} → y ∉ l → y ∉ take a l
∉take {y} {zero} {[]} p = p
∉take {y} {zero} {x ∷ l} p = λ ()
∉take {y} {suc a} {[]} p = p
∉take {y} {suc a} {x ∷ l} p = λ { (here px) → p (here px) ; (there z) → p (there (∈take z))}

takeUnique : ∀ {a : Nat} {l : List PubKeyHash} → Unique l → Unique (take a l)
takeUnique {zero} {[]} p = p
takeUnique {zero} {x ∷ l} p = root
takeUnique {suc a} {[]} p = p
takeUnique {suc a} {x ∷ l} (p :: ps) = ∉take p :: (takeUnique ps)

v≤v : ∀ (v : Value) → v ≤ v
v≤v zero = z≤n
v≤v (suc v) = s≤s (v≤v v)


≤ᵇto≤ : ∀ {a b} → (a <ᵇ b || a ≡ᵇ b) ≡ true → a ≤ b
≤ᵇto≤ {zero} {zero} pf = z≤n
≤ᵇto≤ {zero} {suc b} pf = z≤n
≤ᵇto≤ {suc a} {suc b} pf = s≤s (≤ᵇto≤ pf)

≤ᵇto≤' : ∀ {a b} → (a <ᵇ b || b ≡ᵇ a) ≡ true → a ≤ b
≤ᵇto≤' {zero} {zero} pf = z≤n
≤ᵇto≤' {zero} {suc b} pf = z≤n
≤ᵇto≤' {suc a} {suc b} pf = s≤s (≤ᵇto≤' pf)

n≤ᵇto> : ∀ {a b} → (a <ᵇ b || a ≡ᵇ b) ≡ false → a > b
n≤ᵇto> {suc a} {zero} pf = s≤s z≤n
n≤ᵇto> {suc a} {suc b} pf = s≤s (n≤ᵇto> pf)

--Liquidity (For any state that is valid and has valid parameters,
--there exists another state and some inputs such that we can transition
--there and have no value left in the contract)
liquidity : ∀ (par : Params) (s : State) (pkh : PubKeyHash)
          → ValidS s → ValidP par → continues s ≡ true
          → ∃[ s' ] ∃[ is ] ((par ⊢ s ~[ is ]~* s') × (value (context s') ≡ 0) )
liquidity par s pkh (Stp p1) valid p2 rewrite p1 = ⊥-elim (get⊥ (sym p2))

liquidity par
  s@(record { label = .Holding ;
              context = record { value = value ;
                                 outVal = outVal ;
                                 outAdr = outAdr ;
                                 now = now ;
                                 tsig = tsig }})
  pkh (Hol refl) (Always p2 p3) pf with minValue <= value in eq
...| false  = ⟨ s' , ⟨  [ Close ] , ⟨ cons (TClose refl (n≤ᵇto> eq) pf refl) root , refl ⟩ ⟩ ⟩
      where
        s' = record { label = Holding ;
                      context = record { value = zero ;
                                         outVal = value ;
                                         outAdr = pkh ;
                                         now = now ;
                                         tsig = tsig } ;
                      continues = false }
...| true  = ⟨ s'' , ⟨ (Propose value pkh 0) ∷ ((makeIs (authSigs par)) ++ [ Pay ]) ,
    ⟨ cons (TPropose (v≤v value) (≤ᵇto≤ eq) refl refl refl z≤n pf refl)
    (prop2' s' s'' par (Col refl (v≤v value) (≤ᵇto≤ eq) root) refl refl refl refl refl (Always p2 p3) refl refl refl ) , refl ⟩ ⟩ ⟩
      where
        s'' = record { label = Holding ;
                      context = record { value = zero ;
                                         outVal = value ;
                                         outAdr = pkh ;
                                         now = now ;
                                         tsig = pkh } ;
                      continues = true }
        s' = record { label = Collecting value pkh 0 [] ;
                       context = record { value = value ;
                                          outVal = outVal ;
                                          outAdr = outAdr ;
                                          now = now ;
                                          tsig = tsig } ;
                      continues = true }
liquidity par
  s@(record { label = (Collecting v' pkh' d' sigs') ;
             context = record { value = value ;
                                outVal = outVal ;
                                outAdr = outAdr ;
                                now = now ;
                                tsig = tsig } } )
  pkh (Col refl p2 p3 p6) (Always p4 p5) pf with minValue <= value in eq
...| false  = ⊥-elim (≤⇒≯ (≤-trans p3 p2) (n≤ᵇto> eq))

...| true  = ⟨ s''' , ⟨ Cancel ∷ (Propose value pkh 0) ∷ ((makeIs (authSigs par)) ++ [ Pay ]) ,
    ⟨ cons (TCancel {s' = s'}
    (s≤s (v≤v d')) refl refl refl pf refl)
    (cons (TPropose (v≤v value) (≤ᵇto≤ eq) refl refl refl z≤n refl refl)
    (prop2' s'' s''' par (Col refl (v≤v value) (≤ᵇto≤ eq) root) refl refl refl refl refl (Always p4 p5) refl refl refl)) , refl ⟩ ⟩ ⟩
      where
        s''' = record { label = Holding ;
                       context = record { value = zero ;
                                          outVal = value ;
                                          outAdr = pkh ;
                                          now = now ;
                                          tsig = pkh } ;
                      continues = true }
        s' = record { label = Holding ;
                      context = record { value = value ;
                                         outVal = outVal ;
                                         outAdr = outAdr ;
                                         now = suc d' ;
                                         tsig = tsig } ;
                      continues = true }
        s'' = record { label = Collecting value pkh 0 [] ;
                        context = record { value = value ;
                                           outVal = outVal ;
                                           outAdr = outAdr ;
                                           now = 0 + 1 ;
                                           tsig = tsig } ;
                      continues = true }


--sub-lemmas and helper functions for validator returning true implies transition
<ᵇto< : ∀ {a b} → (a <ᵇ b) ≡ true → a < b
<ᵇto< {zero} {suc b} pf = s≤s z≤n
<ᵇto< {suc a} {suc b} pf = s≤s (<ᵇto< pf)

3&&false : ∀ (a b c : Bool) → (a && b && c && false) ≡ true → ⊥
3&&false true true true ()

4&&false : ∀ (a b c d : Bool) → (a && b && c && d && false) ≡ true → ⊥
4&&false true true true true ()

5&&false : ∀ (a b c d f : Bool) → (a && b && c && d && f && false) ≡ true → ⊥
5&&false true true true true true ()

2&&false : ∀ (a b : Bool) → (a && b && false) ≡ true → ⊥
2&&false true true ()

&&false : ∀ (a : Bool) → (a && false) ≡ true → ⊥
&&false true ()


get : ∀ (a : Bool) {b} → (a && b) ≡ true → a ≡ true
get true pf = refl

go : ∀ (a : Bool) {b} → (a && b) ≡ true → b ≡ true
go true {b} pf = pf

goo : ∀ {a b : Bool} → (a && b) ≡ true → b ≡ true
goo {true} {true} pf = pf

gett : ∀ {a b : Bool} → (a && b) ≡ true → a ≡ true
gett {true} {true} pf = refl

≡ˡto≡ : ∀ {a b : List PubKeyHash} → (a == b) ≡ true → a ≡ b
≡ˡto≡ {[]} {[]} pf = refl
≡ˡto≡ {(x ∷ a)} {(y ∷ b)} pf rewrite (==ito≡ x y (get (x == y) pf)) = cong (λ x → y ∷ x) (≡ˡto≡ (go (x == y) pf))

==lto≡ : ∀ (a b : List PubKeyHash) → (a == b) ≡ true → a ≡ b
==lto≡ [] [] pf = refl
==lto≡ (x ∷ a) (y ∷ b) pf rewrite (==ito≡ x y (get (x == y) pf)) = cong (λ x → y ∷ x) (==lto≡ a b (go (x == y) pf))

p1 : ∀ (a b c d e f : Bool) (x y : Value) → ((x ≡ᵇ y) && a && b && c && d && e && f) ≡ true → x ≡ y
p1 a b c d e f x y pf = ≡ᵇto≡ (get (x ≡ᵇ y)  pf)

p2 : ∀ (a b c d e f : Bool) (x y : Value) → (a && (x <ᵇ y || x ≡ᵇ y) && b && c && d && e && f) ≡ true → x ≤ y
p2 a b c d e f x y pf = ≤ᵇto≤ ( get ((x <ᵇ y || x ≡ᵇ y)) (go a pf) )

p3 : ∀ (a b c d e f : Bool) (x y : Value) → (a && b && (x <ᵇ y) && c && d && e && f) ≡ true → x < y
p3 a b c d e f x y pf = <ᵇto< ( get (x <ᵇ y) (go b (go a pf)) )

p4 : ∀ (a b c d e f : Bool) (x y : Value) → (a && b && c && (x ≡ᵇ y) && d && e && f) ≡ true → x ≡ y
p4 a b c d e f x y pf = ≡ᵇto≡ (get (x ≡ᵇ y) (go c (go b (go a pf))) )

p5 : ∀ (a b c d e f : Bool) (x y : PubKeyHash) → (a && b && c && d && (x == y) && e && f) ≡ true → x ≡ y
p5 a b c d e f x y pf = ==ito≡ x y (get (x == y) (go d (go c (go b (go a pf)))) )

p6 : ∀ (a b c d e f : Bool) (x y : Deadline) → (a && b && c && d && e && (x ≡ᵇ y) && f) ≡ true → x ≡ y
p6 a b c d e f x y pf = ≡ᵇto≡ (get (x ≡ᵇ y) (go e (go d (go c (go b (go a pf))))))

p7 : ∀ (a b c d e f : Bool) (x y : List PubKeyHash) → (a && b && c && d && e && f && (x == y)) ≡ true → x ≡ y
p7 a b c d e f x y pf = ==lto≡ x y (go f (go e (go d (go c (go b (go a pf))))))

pr6 : ∀ (b c d e f g h i : Bool) (x y : Value)
      → (b && c && d && e && f && (x == y) && g && h && i) ≡ true → x ≡ y
pr6 b c d e f g h i x y pf = ≡ᵇto≡ (gett (go f (go e (go d (go c (go b pf))))))

pr7 : ∀ (b c d e f g h i : Bool) (x y : PubKeyHash)
      → (b && c && d && e && f && g && (x == y) && h && i) ≡ true → x ≡ y
pr7 b c d e f g h i x y pf = ≡ⁱto≡ (gett (go g(go f (go e (go d (go c (go b pf)))))))

pr8 : ∀ (b c d e f g h i : Bool) (x y : Value)
      → (b && c && d && e && f && g && h && (x == y) && i) ≡ true → x ≡ y
pr8 b c d e f g h i x y pf = ≡ᵇto≡ (gett (go h (go g (go f (go e (go d (go c (go b pf))))))))

pr9 : ∀ (b c d e f g h i : Bool) (x y : List PubKeyHash)
      → (b && c && d && e && f && g && h && i && (x == y)) ≡ true → x ≡ y
pr9 b c d e f g h i x y pf = ≡ˡto≡ (go i (go h (go g (go f (go e (go d (go c (go b pf))))))))

ar5 : ∀ (c d e f g h i : Bool) (x y : Value)
      → (c && d && e && f && (x == y) && g && h && i) ≡ true → x ≡ y
ar5 c d e f g h i x y pf = ≡ᵇto≡ (gett (go f (go e (go d (go c pf)))))

ar6 : ∀ (c d e f g h i : Bool) (x y : PubKeyHash)
      → (c && d && e && f && g && (x == y) && h && i) ≡ true → x ≡ y
ar6 c d e f g h i x y pf = ≡ⁱto≡ (gett (go g(go f (go e (go d (go c pf))))))

ar7 : ∀ (c d e f g h i : Bool) (x y : Value)
      → (c && d && e && f && g && h && (x == y) && i) ≡ true → x ≡ y
ar7 c d e f g h i x y pf = ≡ᵇto≡ (gett (go h (go g (go f (go e (go d (go c pf)))))))

ar8 : ∀ (c d e f g h i : Bool) (x y : List PubKeyHash)
      → (c && d && e && f && g && h && i && (x == y)) ≡ true → x ≡ y
ar8 c d e f g h i x y pf = ≡ˡto≡ (go i (go h (go g (go f (go e (go d (go c pf)))))))

orToSum : ∀ (a b : Bool) → (a || b) ≡ true → a ≡ true ⊎ b ≡ true
orToSum false true pf = inj₂ refl
orToSum true b pf = inj₁ refl

queryTo∈ : ∀ {sig sigs} → (query sig sigs) ≡ true → sig ∈ sigs
queryTo∈ {sig} {x ∷ sigs} pf with orToSum (x == sig) (query sig sigs) pf
... | inj₁ a = here (sym (==ito≡ x sig a))
... | inj₂ b = there (queryTo∈ b)

a2 : ∀ (a b c d e f : Bool) (x y : PubKeyHash) → (a && (x == y) && b && c && d && e && f) ≡ true → x ≡ y
a2 a b c d e f x y pf = ==ito≡ x y ( get (x == y) (go a pf) )

a3 : ∀ (a b c d e f : Bool) (sig : PubKeyHash) (sigs : List PubKeyHash) → (a && b && (query sig sigs) && c && d && e && f) ≡ true → sig ∈ sigs
a3 a b c d e f sig sigs pf = queryTo∈ ( get (query sig sigs) (go b (go a pf)) )

lengthNatToLength : ∀ (n : ℕ) (l : List PubKeyHash) → (n <ᵇ lengthNat l || lengthNat l ≡ᵇ n ) ≡ true → n ≤ length l
lengthNatToLength zero [] pf = z≤n
lengthNatToLength zero (x ∷ l) pf = z≤n
lengthNatToLength (suc n) (x ∷ l) pf = s≤s (lengthNatToLength n l pf)

y1 : ∀ (a b c : Bool) (n : ℕ) (sigs : List PubKeyHash) → ((n <ᵇ lengthNat sigs || lengthNat sigs ≡ᵇ n) && (a && b) && c) ≡ true → n ≤ length sigs
y1 a b c n sigs pf = lengthNatToLength n sigs (get (n <ᵇ lengthNat sigs || lengthNat sigs ≡ᵇ n) pf)

y2 : ∀ (a b c : Bool) (x y : PubKeyHash) → (a && ((x == y) && b) && c) ≡ true → x ≡ y
y2 a b c x y pf = ==ito≡ x y (get (x == y) (get ((x == y) && b) (go a pf)))

y3 : ∀ (a b c : Bool) (x y : Value) → (a && (b && (x ≡ᵇ y)) && c) ≡ true → x ≡ y
y3 a b c x y pf = ≡ᵇto≡ (go b (get (b && (x ≡ᵇ y)) (go a pf)))

y4 : ∀ (a b c : Bool) (x y : Value) → (a && (b && c) && x ≡ᵇ y) ≡ true → x ≡ y
y4 a b c x y pf = ≡ᵇto≡ (go (b && c) (go a pf))

c1 : ∀ (a : Bool) (x y : Value) → (x ≡ᵇ y && a) ≡ true → x ≡ y
c1 a x y pf = ≡ᵇto≡ (get (x ≡ᵇ y) pf)

c2 : ∀ (a : Bool) (x y : Deadline) → (a && (x <ᵇ y)) ≡ true → x < y
c2 a x y pf = <ᵇto< (go a pf)

--Validator returning true implies transition relation is inhabited
validatorImpliesTransition : ∀ {oV oA t s} (par : Params) (l : Label) (i : Input) (ctx : ScriptContext)
                           → (pf : agdaValidator par l i ctx ≡ true)
                           → par ⊢
                           record { label = l ; context = record { value = (inputVal ctx) ;
                           outVal = oV ; outAdr = oA ; now = t ; tsig = s } ; continues = true }
                           ~[ i ]~>
                           record { label = (outputLabel ctx) ; context = record { value = (outputVal ctx) ;
                           outVal = payAmt ctx ; outAdr = payTo ctx ; now = time ctx ; tsig = signature ctx } ;
                           continues = continuing ctx}

validatorImpliesTransition par Holding (Propose v pkh d)
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = Holding ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = ⊥-elim (5&&false (eqNat outputVal inputVal) (ltNat v inputVal || eqNat inputVal v) (ltNat 2 v || eqNat v 2)
    (ltNat d (addNat time (maxWait par)) || eqNat d (addNat time (maxWait par))) continues pf)

validatorImpliesTransition par Holding (Propose v pkh d)
  ctx@record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting v' pkh' d' sigs') ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  rewrite sym (pr6 (outputVal == inputVal) (inputVal >= v) (v >= 2) (notTooLate par d ctx) continues (pkh == pkh') (d == d') (sigs' == []) v v' pf)
  | sym (pr7 (outputVal == inputVal) (inputVal >= v) (v >= 2) (notTooLate par d ctx) continues (v == v') (d == d') (sigs' == []) pkh pkh' pf)
  | sym (pr8 (outputVal == inputVal) (inputVal >= v) (v >= 2) (notTooLate par d ctx) continues (v == v') (pkh == pkh') (sigs' == []) d d' pf)
  | pr9 (outputVal == inputVal) (inputVal >= v) (v >= 2) (notTooLate par d ctx) continues (v == v') (pkh == pkh') (d == d') sigs' [] pf
  = TPropose (≤ᵇto≤' (gett (go (eqNat outputVal inputVal) pf)))
             (≤ᵇto≤' (gett (go (ltNat v inputVal || eqNat inputVal v) (go (eqNat outputVal inputVal) pf)))) refl
             refl (sym (≡ᵇto≡ (gett pf)))
             (≤ᵇto≤ (gett (go (v >= 2) (go (ltNat v inputVal || eqNat inputVal v) (go (eqNat outputVal inputVal) pf))))) refl
             (gett (go (notTooLate par d ctx) (go (v >= 2) (go (ltNat v inputVal || eqNat inputVal v) (go (eqNat outputVal inputVal) pf)))))

validatorImpliesTransition par (Collecting v pkh d sigs) (Add sig)
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = Holding ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = ⊥-elim (4&&false (eqNat outputVal inputVal) (eqInteger sig signature) (query sig (authSigs par)) continues pf)
validatorImpliesTransition par (Collecting v pkh d sigs) (Add sig)
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting v' pkh' d' sigs') ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  rewrite ar5 (outputVal == inputVal) (sig == signature) (query sig (authSigs par)) continues (pkh == pkh') (d == d') (sigs' == (insert sig sigs)) v v' pf
  | ar6 (outputVal == inputVal) (sig == signature) (query sig (authSigs par)) continues (v == v') (d == d') (sigs' == (insert sig sigs)) pkh pkh' pf
  | ar7 (outputVal == inputVal) (sig == signature) (query sig (authSigs par)) continues (v == v') (pkh == pkh') (sigs' == (insert sig sigs)) d d' pf
  | ar8 (outputVal == inputVal) (sig == signature) (query sig (authSigs par)) continues (v == v') (pkh == pkh') (d == d') sigs' (insert sig sigs) pf
  = TAdd (queryTo∈ (gett (go (sig == signature) (go (outputVal == inputVal) pf))))
  (sym (≡ⁱto≡ (gett (go (outputVal == inputVal) pf)))) refl refl
  (sym (≡ᵇto≡ (gett pf))) refl
  (gett (go ( query sig (authSigs par)) (go (sig == signature) (go (outputVal == inputVal) pf))))
validatorImpliesTransition par (Collecting v pkh d sigs) Pay
  ctx@record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = Holding ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = TPay (sym (≡ⁱto≡ (go (inputVal == outputVal + v) (go (eqInteger pkh payTo && eqNat v payAmt) (go continues (go ((lengthNat sigs) >= (nr par)) pf))))))
  (≡ᵇto≡ (gett (go (eqInteger pkh payTo && eqNat v payAmt) (go continues (go ((lengthNat sigs) >= (nr par)) pf)))))
  (lengthNatToLength (nr par) sigs (gett pf)) refl refl
  (sym (≡ᵇto≡ (go (pkh == payTo) (gett (go continues (go ((lengthNat sigs) >= (nr par)) pf))))))
  (sym (≡ⁱto≡ (gett (gett (go continues (go ((lengthNat sigs) >= (nr par)) pf)))))) refl (gett (go ((lengthNat sigs) >= (nr par)) pf))
validatorImpliesTransition par (Collecting v pkh d sigs) Pay
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting v' pkh' d' sigs') ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = ⊥-elim (2&&false (ltNat (nr par) (lengthNat sigs) || eqNat (lengthNat sigs) (nr par)) continues pf)
validatorImpliesTransition par (Collecting v pkh d sigs) Cancel
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = Holding ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = TCancel (<ᵇto< (go continues (go (outputVal == inputVal) pf))) refl refl
  (sym (≡ᵇto≡ (gett pf))) refl (gett (go (outputVal == inputVal) pf))
validatorImpliesTransition par (Collecting v pkh d sigs) Cancel
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting v' pkh' d' sigs') ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues } pf
  = ⊥-elim (2&&false (eqNat outputVal inputVal) continues pf)
validatorImpliesTransition par Holding Close
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = outputLabel ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = True } pf
  = ⊥-elim (&&false (ltNat inputVal 2) pf)
validatorImpliesTransition par Holding Close
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = outputLabel ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = False } pf
  = TClose refl (<ᵇto< (gett pf)) refl refl


--sub-lemmas for transition implies validation returns true
≡to≡ᵇ : ∀ {a b} → a ≡ b → (a ≡ᵇ b) ≡ true
≡to≡ᵇ {zero} refl = refl
≡to≡ᵇ {suc a} refl = ≡to≡ᵇ {a} refl

≤to≤ᵇ : ∀ {a b} → a ≤ b → (a <ᵇ b || a ≡ᵇ b) ≡ true
≤to≤ᵇ {b = zero} z≤n = refl
≤to≤ᵇ {b = suc b} z≤n = refl
≤to≤ᵇ (s≤s pf) = ≤to≤ᵇ pf

≤to≤ᵇ' : ∀ {a b} → a ≤ b → (a <ᵇ b || b ≡ᵇ a) ≡ true
≤to≤ᵇ' {b = zero} z≤n = refl
≤to≤ᵇ' {b = suc b} z≤n = refl
≤to≤ᵇ' (s≤s pf) = ≤to≤ᵇ' pf

<to<ᵇ : ∀ {a b} → a < b → (a <ᵇ b) ≡ true
<to<ᵇ {zero} (s≤s pf) = refl
<to<ᵇ {suc a} (s≤s pf) = <to<ᵇ pf

i=i : ∀ (i : Int) → (eqInteger i i) ≡ true
i=i (pos zero) = refl
i=i (pos (suc n)) = i=i (pos n)
i=i (negsuc zero) = refl
i=i (negsuc (suc n)) = i=i (pos n)


l=l : ∀ (l : List PubKeyHash) → (l == l) ≡ true
l=l [] = refl
l=l (x ∷ l) rewrite i=i x = l=l l

||true : ∀ {b} → (b || true) ≡ true
||true {false} = refl
||true {true} = refl

∈toQuery : ∀ {sig sigs} → sig ∈ sigs → (query sig sigs) ≡ true
∈toQuery {sig} (here refl) rewrite i=i sig = refl
∈toQuery (there pf) rewrite ∈toQuery pf = ||true

lengthToLengthNat : ∀ (n : ℕ) (l : List PubKeyHash) → n ≤ length l → (n <ᵇ lengthNat l || lengthNat l ≡ᵇ n) ≡ true
lengthToLengthNat zero [] z≤n = refl
lengthToLengthNat zero (x ∷ l) z≤n = refl
lengthToLengthNat (suc n) (x ∷ l) (s≤s pf) = lengthToLengthNat n l pf


transitionImpliesValidator : ∀ {oV oA t s cont} (par : Params) (l : Label) (i : Input) (ctx : ScriptContext)
                           → (pf : par ⊢
                           record { label = l ; context = record { value = (inputVal ctx) ;
                           outVal = oV ; outAdr = oA ; now = t ; tsig = s } ; continues = cont }
                           ~[ i ]~>
                           record { label = (outputLabel ctx) ; context = record { value = (outputVal ctx) ;
                           outVal = payAmt ctx ; outAdr = payTo ctx ; now = time ctx ; tsig = signature ctx } ;
                           continues = continuing ctx })
                           → agdaValidator par l i ctx ≡ true


transitionImpliesValidator par Holding (Propose v pkh d)
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting _ _ _ []) ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = continues }
           (TPropose p1 p2 p3 refl p5 p6 p7 refl)
  rewrite ≡to≡ᵇ (sym p5) | v=v v | i=i pkh | v=v d | ≤to≤ᵇ' p1 | ≤to≤ᵇ' p2 | ≤to≤ᵇ p6  = refl
transitionImpliesValidator par Holding Close
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = outputLabel ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = false }
           (TClose p1 p2 p3 p4)
  rewrite <to<ᵇ p2 = refl
transitionImpliesValidator par (Collecting v pkh d sigs) (Add sig)
  record { inputVal = inputVal ;
           outputVal = outputVal ;
           outputLabel = (Collecting .v .pkh .d .(insert sig sigs)) ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = .sig ;
           continues = .true }
           (TAdd p1 refl refl refl p5 p6 refl)
  rewrite ≡to≡ᵇ (sym p5) | i=i sig | ∈toQuery p1 | v=v v | i=i pkh | v=v d | l=l (insert sig sigs) = refl
transitionImpliesValidator par (Collecting v pkh d sigs) Pay
  record { inputVal = .(addNat outputVal v) ;
           outputVal = outputVal ;
           outputLabel = Holding ;
           time = time ;
           payTo = .pkh ;
           payAmt = .v ;
           signature = .pkh ;
           continues = .true }
           (TPay refl refl p3 refl refl refl refl p8 refl)
  rewrite i=i pkh | v=v v | lengthToLengthNat (nr par) sigs p3 | v=v (outputVal + v) = refl
transitionImpliesValidator par (Collecting v pkh d sigs) Cancel
  record { inputVal = inputVal ;
           outputVal = .(inputVal) ;
           outputLabel = Holding ;
           time = time ;
           payTo = payTo ;
           payAmt = payAmt ;
           signature = signature ;
           continues = .true }
           (TCancel p1 refl p3 refl p5 refl)
  rewrite v=v inputVal | <to<ᵇ p1 = refl
