module BTree ( -- * Basic types
               BLeaf(..)
             , Size
             , Order
               -- * Building trees
             , fromOrdered
               -- * Looking up in trees
             , LookupTree
             , open
             , lookup
             ) where

import Prelude hiding (lookup)
import BTree.Types
import BTree.Merge
import BTree.Builder
import BTree.Lookup