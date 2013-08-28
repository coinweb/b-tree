{-# LANGUAGE TemplateHaskell, BangPatterns, GeneralizedNewtypeDeriving #-}

module BTree.Merge ( mergeTrees
                   , mergeLeaves
                   , sizedProducerForTree
                   ) where

import Prelude hiding (sum, compare)
import Control.Applicative
import Data.Function (on)
import Data.List (sortBy)
import Data.Either (rights)
import Data.Foldable
import Control.Monad.State hiding (forM_)
import Data.Binary       
import Control.Lens
import Pipes

import BTree.Types
import BTree.Builder
import BTree.Walk

mergeStreams :: (Monad m, Functor m)
             => (a -> a -> Ordering) -> [Producer a m ()] -> Producer a m ()
mergeStreams compare producers = do
    xs <- lift $ rights <$> mapM Pipes.next producers
    go xs
  where --go :: (Monad m, Functor m) => [(a, Producer a m ())] -> Producer a m ()
        go [] = return ()
        go xs = do let (a,producer):xs' = sortBy (compare `on` fst) xs
                   yield a
                   x' <- lift $ next producer
                   go $ either (const xs') (:xs') x'

combine :: (Monad m)
        => (a -> a -> Bool)    -- ^ equality test
        -> (a -> a -> a)       -- ^ combine operation
        -> Producer a m r -> Producer a m r
combine eq append producer = lift (next producer) >>= either return (uncurry go)
  where go a producer' = do
          n <- lift $ next producer'
          case n of
            Left r                 -> yield a >> return r
            Right (a', producer'')
              | a `eq` a'          -> go (a `append` a') producer''
              | otherwise          -> yield a >> go a' producer''
    
mergeCombine :: (Monad m, Functor m)
             => (a -> a -> Ordering) -> (a -> a -> a)
             -> [Producer a m ()] -> Producer a m ()
mergeCombine compare append producers =
    combine (\a b->compare a b == EQ) append
    $ mergeStreams compare producers 

-- | Merge trees' leaves taking ordered leaves from a set of producers.
-- 
-- Each producer must be annotated with the number of leaves it is
-- expected to produce. The size of the resulting tree will be at most
-- the sum of these sizes.
mergeLeaves :: (Binary k, Binary e)
            => (k -> k -> Ordering)          -- ^ ordering on keys
            -> (e -> e -> e)                 -- ^ merge operation on elements
            -> Order                         -- ^ order of merged tree
            -> FilePath                      -- ^ name of output file
            -> [(Size, Producer (BLeaf k e) IO ())]   -- ^ producers of leaves to merge
            -> IO ()
mergeLeaves compare append destOrder destFile producers = do
    let size = sum $ map fst producers
    fromOrderedToFile destOrder size destFile $
      mergeCombine (compare `on` key) doAppend (map snd producers)
  where doAppend (BLeaf k e) (BLeaf _ e') = BLeaf k $ append e e'
        key (BLeaf k _) = k

-- | Merge several 'LookupTrees'
--
-- This is a convenience function for merging several trees already on
-- disk. For a more flexible interface, see 'mergeLeaves'.
mergeTrees :: (Binary k, Binary e)
           => (k -> k -> Ordering)   -- ^ ordering on keys
           -> (e -> e -> e)          -- ^ merge operation on elements
           -> Order                  -- ^ order of merged tree
           -> FilePath               -- ^ name of output file
           -> [LookupTree k e]       -- ^ trees to merge
           -> IO ()
mergeTrees compare append destOrder destFile trees = do
    mergeLeaves compare append destOrder destFile
    $ map sizedProducerForTree trees

-- | Get a sized producer suitable for 'mergeLeaves' from a 'LookupTree'
sizedProducerForTree :: (Monad m, Binary k, Binary e)
                     => LookupTree k e   -- ^ a tree
                     -> (Size, Producer (BLeaf k e) m ())
                                         -- ^ a sized Producer suitable for passing 
                                         -- to 'mergeLeaves'
sizedProducerForTree lt = (lt ^. ltHeader . btSize, void $ walkLeaves lt)
