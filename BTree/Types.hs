{-# LANGUAGE DeriveGeneric, FlexibleContexts, UndecidableInstances, StandaloneDeriving #-}

module BTree.Types where

import Data.Binary
import GHC.Generics
import Control.Applicative
import Data.Word
import Data.Int

magic :: Word64
magic = 0xdeadbeefbbbbcccc

-- | An offset within the stream         
type Offset = Int64

-- | The number of entries in a B-tree
type Size = Word64

-- | The maximum number of children of a B-tree inner node
type Order = Word64

-- | B-tree file header
data BTreeHeader = BTreeHeader { btMagic   :: !Word64
                               , btVersion :: !Word64
                               , btOrder   :: !Order
                               , btSize    :: !Size
                               }
                 deriving (Show, Eq, Generic)

instance Binary BTreeHeader

-- | 'OnDisk a' is a reference to an object of type 'a' on disk
newtype OnDisk a = OnDisk Offset
                 deriving (Show, Eq, Ord)
                
instance Binary (OnDisk a) where
    get = OnDisk <$> get
    put (OnDisk off) = put off

-- | 'BTree k f e' is a B* tree of key type 'k' with elements of type 'e' contained
-- within a functor 'f'
data BTree k f e = Node (f (BTree k f e)) [(k, f (BTree k f e))]
                 | Leaf !k !(f e)
                 deriving (Generic)
    
deriving instance (Show (f e), Show k, Show (f (BTree k f e))) => Show (BTree k f e)
deriving instance (Eq (f e), Eq k, Eq (f (BTree k f e))) => Eq (BTree k f e)

instance (Binary k, Binary (f (BTree k f e)), Binary (f e))
  => Binary (BTree k f e) where
    get = do typ <- getWord8
             case typ of
               0 -> Node <$> get <*> get
               1 -> Leaf <$> get <*> get
    put (Node e0 es) = put e0 >> put es
    put (Leaf k0 e)  = put k0 >> put e

treeStartKey :: BTree k f e -> k
treeStartKey (Node _ ((k,_):_)) = k
treeStartKey (Leaf k _)           = k
