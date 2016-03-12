-- This file is part of fresnel
-- Copyright (C) 2015  Fraser Tweedale
--
-- fresnel is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE RankNTypes #-}

module Data.Fresnel
  (
  -- | Grammars
    Grammar
  , parse
  , print

  -- | Grammar constructors and combinators
  , element
  , satisfy
  , symbol
  , many
  , many1
  , (<<*)
  , (*>>)
  , between
  , literal
  , def
  , opt
  , eof
  , productG
  , (<<*>>)
  , sumG
  , (<<+>>)
  , replicateG
  , bindG
  , adapt
  , (<<$>>)

  -- | Re-exports
  , Cons
  ) where

import Prelude hiding (print)
import Control.Applicative ((<$>), pure)
import Control.Monad ((>=>))
import Data.Bifunctor (first)
import Data.Monoid (Monoid, mempty)
import Numeric.Natural (Natural)

import Control.Lens hiding (element)
import Data.List.NonEmpty (NonEmpty(..))

-- $setup
-- >>> import Data.Char
-- >>> import Data.Fresnel.Char


type Grammar s a = Prism' s (a, s)

element :: Cons s s a a => Grammar s a
element = _Cons

satisfy :: Cons s s a a => (a -> Bool) -> Grammar s a
satisfy f = prism id (\a -> if f a then Right a else Left a) <<$>> element

symbol :: (Cons s s a a, Eq a) => a -> Grammar s a
symbol a = satisfy (== a)

-- | Adapt the 'Grammar' with a 'Prism' or 'Iso'
--
-- >>> let g = reversed `adapt` many (satisfy isAlpha)
-- >>> parse g "live!"
-- Just "evil"
-- >>> print g "evil" :: String
-- "live"
--
-- >>> let shouting s = if all (not . isLower) s then Right (fmap toLower s) else Left s
-- >>> let g = prism (fmap toUpper) shouting <<$>> many element
-- >>> parse g "WOW!!!"
-- Just "wow!!!"
-- >>> parse g "meh"
-- Nothing
-- >>> print g "hello world" :: String
-- "HELLO WORLD"
--
adapt, (<<$>>) :: Prism' a b -> Grammar s a -> Grammar s b
adapt p g = withPrism g $ \as sesa ->
  withPrism p $ \ba aeab ->
    let
      bs (b, s) = as (ba b, s)
      sesb = sesa >=> \(a, s') -> case aeab a of
        Left _ -> Left s'
        Right b -> Right (b, s')
    in prism bs sesb
(<<$>>) = adapt
infixr 4 <<$>>

-- | Sequence two grammars and combine their results as a tuple
--
-- >>> let g = integralG <<*>> many (satisfy isAlpha)
-- >>> parse g "-10abc"
-- Just (-10,"abc")
-- >>> print g (42, "xyz") :: String
-- "42xyz"
--
productG, (<<*>>) :: Grammar s a -> Grammar s b -> Grammar s (a, b)
productG p p' = withPrism p $ \as sesa ->
  withPrism p' $ \bs sesb ->
    let
      as' ((a, b), s) = as (a, bs (b, s))
      sesa' = sesa >=> \(a, s') -> do
        (b, s'') <- sesb s'
        pure ((a, b), s'')
    in prism as' sesa'
(<<*>>) = productG
infixr 6 <<*>>


-- | Choice between two grammars
--
-- >>> let g = integralG <<+>> (many (satisfy isAlpha))
-- >>> parse g "-10!"
-- Just (Left (-10))
-- >>> parse g "abc!"
-- Just (Right "abc")
-- >>> print g (Left 42) :: String
-- "42"
-- >>> print g (Right "xyz") :: String
-- "xyz"
--
sumG, (<<+>>) :: Grammar s a -> Grammar s b -> Grammar s (Either a b)
sumG p1 p2 = withPrism p1 $ \as sesa ->
  withPrism p2 $ \bs sesb ->
    let
      eabs (Left a, s) = as (a, s)
      eabs (Right b, s) = bs (b, s)
      seseab s = case sesa s of
        Left _ -> first Right <$> sesb s
        r -> first Left <$> r
    in prism eabs seseab
(<<+>>) = sumG
infixr 5 <<+>>

-- | Run the grammar as many times as possible on the input,
-- returning or consuming a list.
--
-- >>> let g = many (satisfy isAlpha)
-- >>> parse g ""
-- Just ""
-- >>> parse g "abc!"
-- Just "abc"
-- >>> print g "xyz" :: String
-- "xyz"
--
many :: Grammar s a -> Grammar s [a]
many p = withPrism p $ \bt seta ->
  let
    bt' ([], s) = s
    bt' (a:as, s) = bt (a, bt' (as, s))
    seta' s = case seta s of
      Left _ -> Right ([], s)
      Right (a, s') -> first (a:) <$> seta' s'
  in prism bt' seta'

-- | Run the grammar as many times as possible and at least once.
--
-- >>> let g = many1 (satisfy isDigit)
-- >>> parse g ""
-- Nothing
-- >>> parse g "42"
-- Just ('4' :| "2")
-- >>> print g ('1' :| "23") :: String
-- "123"
--
many1 :: Grammar s a -> Grammar s (NonEmpty a)
many1 g = isoTupleNEL <<$>> g <<*>> many g where
  isoTupleNEL :: Iso' (a, [a]) (NonEmpty a)
  isoTupleNEL = iso (uncurry (:|)) (\(h :| t) -> (h, t))

-- | Sequence two grammars, ignoring the second value.
--
-- >>> let g = integralG <<* literal '~'
-- >>> parse g "123~"
-- Just 123
-- >>> parse g "123!"
-- Nothing
-- >>> print g 123 :: String
-- "123~"
--
(<<*) :: Grammar s a -> Grammar s () -> Grammar s a
p <<* p' = withPrism p $ \as sesa ->
  withPrism p' $ \bs sesb ->
    let
      as' (a, s) = as (a, bs ((), s))
      sesa' = sesa >=> \(a, s') -> do
        ((), s'') <- sesb s'
        pure (a, s'')
    in prism as' sesa'

-- | Sequence two grammars, ignoring the first value.
--
-- >>> let g = literal '~' *>> integralG
-- >>> parse g "~123"
-- Just 123
-- >>> parse g "123"
-- Nothing
-- >>> print g 123 :: String
-- "~123"
--
(*>>) :: Grammar s () -> Grammar s a -> Grammar s a
p *>> p' = withPrism p $ \as sesa ->
  withPrism p' $ \bs sesb ->
    let
      as' (b, s) = as ((), bs (b, s))
      sesa' = sesa >=> \((), s') -> do
        (b, s'') <- sesb s'
        pure (b, s'')
    in prism as' sesa'

-- | Replicate a grammar N times
--
-- >>> let g = replicateG 3 (satisfy isAlpha)
-- >>> parse g "ab3"
-- Nothing
-- >>> parse g "abc"
-- Just "abc"
-- >>> print g "abcd" :: String  -- note there are FOUR dots
-- "abc"
-- >>> print g "ab" :: String  -- can't do much about this
-- "ab"
--
replicateG :: Natural -> Grammar s a -> Grammar s [a]
replicateG n g = withPrism g $ \as sesa ->
  let
    ass = ass' n
    ass' 0 (_, s) = s
    ass' _ ([], s) = s
    ass' n' (x:xs, s) = as (x, ass' (n' - 1) (xs, s))
    sesas = sesas' n
    sesas' 0 = \s -> Right ([], s)
    sesas' n' = sesa >=> \(a, s') -> first (a:) <$> sesas' (n' - 1) s'
  in prism ass sesas

-- | Sequence a grammar based on functions that return the next
-- grammar and yield a determinant.
--
-- >>> let g = bindG integralG (\n -> replicateG n (satisfy isAlpha)) (fromIntegral . length)
-- >>> parse g "3abc2de?"
-- Just "abc"
-- >>> parse g "3ab2de?"
-- Nothing
-- >>> parse (many g) "3abc2de1f?"
-- Just ["abc","de","f"]
-- >>> print (many g) ["hello", "world"] :: String
-- "5hello5world"
--
bindG :: Grammar s a -> (a -> Grammar s b) -> (b -> a) -> Grammar s b
bindG g f ba = withPrism g $ \as sesa ->
  let
    bs (b, s) = let a = ba b in as (a, review (f a) (b, s))
    sesb = sesa >=> \(a, s') -> withPrism (f a) $ \_ sesb' -> sesb' s'
  in prism bs sesb

-- | Given left and right "surrounding" grammars and an interior
-- grammar sequence all three, discarding the surrounds.
--
-- >>> let g = between (literal '<') (literal '>') integralG
-- >>> parse g "<-123>"
-- Just (-123)
-- >>> print g 42 :: String
-- "<42>"
--
between :: Grammar s () -> Grammar s () -> Grammar s a -> Grammar s a
between l r a = l *>> a <<* r

-- | Consumes or produces a literal character (mapped to '()').
--
-- >>> let g = literal '$'
-- >>> parse g "$~"
-- Just ()
-- >>> print g () :: String
-- "$"
--
literal :: (Cons s s a a, Eq a) => a -> Grammar s ()
literal a = withPrism (symbol a) $ \_ sesa ->
  prism (\((), s) -> cons a s) (fmap (first (const ())) . sesa)

-- | Give a default value for a grammar.
--
-- A defaulted grammar can always be viewed.  If a reviewed value
-- is equal to the default nothing is written.
--
-- >>> let g = def 0 integralG
-- >>> parse g "1~"
-- Just 1
-- >>> parse g "~"
-- Just 0
-- >>> print g 1 :: String
-- "1"
-- >>> print g 0 :: String
-- ""
--
def :: Eq a => a -> Grammar s a -> Grammar s a
def a' p = withPrism p $ \as sesa ->
  let
    as' (a, s) = if a == a' then s else as (a, s)
    sesa' s = either (const (Right (a', s))) Right (sesa s)
  in prism as' sesa'

-- | Make a grammar optional; a failed view yields 'Nothing' and
-- a review of 'Nothing' writes nothing.
--
-- >>> let g = opt integralG
-- >>> parse g "1~"
-- Just (Just 1)
-- >>> parse g "~"
-- Just Nothing
-- >>> print g (Just 1) :: String
-- "1"
-- >>> print g Nothing :: String
-- ""
--
opt :: Grammar s a -> Grammar s (Maybe a)
opt p = withPrism p $ \as sesa ->
  let
    as' (Just a, s) = as (a, s)
    as' (Nothing, s) = s
    sesa' s = case sesa s of
      Left _ -> pure (Nothing, s)
      Right (a, s') -> Right (Just a, s')
  in prism as' sesa'

-- | Matches at end of input; writes nothing
--
-- >>> parse eof ""
-- Just ()
-- >>> parse eof "~"
-- Nothing
-- >>> print eof () :: String
-- ""
--
eof :: Cons s s a a => Grammar s ()
eof = prism as sesa where
  as ((), s) = s
  sesa s = case uncons s of
    Just _ -> Left s
    Nothing -> Right ((), s)

-- | Parse with a grammar, discarding any remaining input.
--
-- If remaining input is an error, apply '(<<* eof)'
-- to your grammar first.
--
parse :: Grammar s b -> s -> Maybe b
parse g s = fst <$> preview g s

-- | Print with a grammar
--
print :: Monoid s => Grammar s b -> b -> s
print g b = review g (b, mempty)