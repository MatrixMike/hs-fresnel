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

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -ddump-splices #-}

module Data.Fresnel.Char
  (
    integralG
  ) where

import Prelude hiding (print)
import Control.Lens
import Data.Char (isDigit)

import Data.Fresnel

-- $setup
-- >>> import Numeric.Natural
-- >>> import Data.Fresnel

-- |
-- >>> parse integralG "01." :: Maybe Integer
-- Just 1
-- >>> parse integralG "-1" :: Maybe Natural
-- Nothing
-- >>> print integralG 42 :: String
-- "42"
-- >>> print integralG (-42) :: String
-- "-42"
--
integralG
  :: (Cons s s Char Char, Integral a, Read a, Show a)
  => Grammar s a
integralG =
  iso (\(c,s) -> maybe s (:s) c) (Nothing,) . _Show
  <<$>> productG (opt (symbol '-')) (many (satisfy isDigit))