{-# LANGUAGE ExistentialQuantification, FlexibleInstances, GADTs #-}
{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}

-- |
-- Module      : Criterion.Types
-- Copyright   : (c) 2009, 2010 Bryan O'Sullivan
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com
-- Stability   : experimental
-- Portability : GHC
--
-- Types for benchmarking.
--
-- The core class is 'Benchmarkable', which admits both pure functions
-- and 'IO' actions.
--
-- For a pure function of type @a -> b@, the benchmarking harness
-- calls this function repeatedly, each time with a different 'Int'
-- argument, and reduces the result the function returns to weak head
-- normal form.  If you need the result reduced to normal form, that
-- is your responsibility.
--
-- For an action of type @IO a@, the benchmarking harness calls the
-- action repeatedly, but does not reduce the result.

module Criterion.Types
    (
      Benchmarkable(..)
    , Benchmark(..)
    , Pure
    , whnf
    , nf
    , nfIO
    , whnfIO
    , bench
    , bench'
    , bgroup
    , bcompare
    , benchNames
    ) where

import Criterion.Monad ( Criterion )
import Control.DeepSeq (NFData, rnf)
import Control.Exception (evaluate)

-- | A benchmarkable function or action.
class Benchmarkable a where
    -- | Run a function or action the specified number of times.
    run :: a                    -- ^ The function or action to benchmark.
        -> Int                  -- ^ The number of times to run or evaluate it.
        -> IO ()

-- | A container for a pure function to benchmark, and an argument to
-- supply to it each time it is evaluated.
data Pure where
    WHNF :: (a -> b) -> a -> Pure
    NF :: NFData b => (a -> b) -> a -> Pure

-- | Apply an argument to a function, and evaluate the result to weak
-- head normal form (WHNF).
whnf :: (a -> b) -> a -> Pure
whnf = WHNF
{-# INLINE whnf #-}

-- | Apply an argument to a function, and evaluate the result to head
-- normal form (NF).
nf :: NFData b => (a -> b) -> a -> Pure
nf = NF
{-# INLINE nf #-}

-- | Perform an action, then evaluate its result to head normal form.
-- This is particularly useful for forcing a lazy IO action to be
-- completely performed.
nfIO :: NFData a => IO a -> IO ()
nfIO a = evaluate . rnf =<< a
{-# INLINE nfIO #-}

-- | Perform an action, then evaluate its result to weak head normal
-- form (WHNF).  This is useful for forcing an IO action whose result
-- is an expression to be evaluated down to a more useful value.
whnfIO :: IO a -> IO ()
whnfIO a = a >>= evaluate >> return ()
{-# INLINE whnfIO #-}

instance Benchmarkable Pure where
    run p@(WHNF _ _) = go p
      where
        go fx@(WHNF f x) n
            | n <= 0    = return ()
            | otherwise = evaluate (f x) >> go fx (n-1)
    run p@(NF _ _) = go p
      where
        go fx@(NF f x) n
            | n <= 0    = return ()
            | otherwise = evaluate (rnf (f x)) >> go fx (n-1)
    {-# INLINE run #-}

instance Benchmarkable (IO a) where
    run a n
        | n <= 0    = return ()
        | otherwise = a >> run a (n-1)
    {-# INLINE run #-}

-- | A benchmark may consist of either a single 'Benchmarkable' item
-- with a name, created with 'bench', or a (possibly nested) group of
-- 'Benchmark's, created with 'bgroup'.
data Benchmark where
    Benchmark    :: Benchmarkable b =>
                    Criterion ()
                 -> Criterion ()
                 -> String
                 -> b
                 -> Benchmark
    BenchGroup   :: String -> [Benchmark] -> Benchmark
    BenchCompare :: [Benchmark] -> Benchmark

-- | Create a single benchmark.
bench :: Benchmarkable b =>
         String                 -- ^ A name to identify the benchmark.
      -> b
      -> Benchmark
bench = Benchmark (return ()) (return ())

-- | Create a single benchmark with a setup and a teardown function.  The
-- setup function is called before the benchmark is run, and the teardown is
-- run afterwards.  Note that Criterion runs each benchmark repeatedly, while
-- these setup and teardown functions are run once per bench.  This limits the
-- utility of the setup and teardown functions somewhat, but they can still
-- ensure that each bench is run in an environment that is clear from the
-- effects of other bench runs.
bench' :: Benchmarkable b =>
          Criterion ()
       -> Criterion ()
       -> String
       -> b
       -> Benchmark
bench' = Benchmark

-- | Group several benchmarks together under a common name.
bgroup :: String                -- ^ A name to identify the group of benchmarks.
       -> [Benchmark]           -- ^ Benchmarks to group under this name.
       -> Benchmark
bgroup = BenchGroup

-- | Compare benchmarks against a reference benchmark
-- (The first 'bench' in the given list).
--
-- The results of the comparisons are written to a CSV file specified using the
-- @-r@ command line flag. The CSV file uses the following format:
--
-- @Reference,Name,% faster than the reference@
bcompare :: [Benchmark] -> Benchmark
bcompare = BenchCompare

-- | Retrieve the names of all benchmarks.  Grouped benchmarks are
-- prefixed with the name of the group they're in.
benchNames :: Benchmark -> [String]
benchNames (Benchmark _ _ d _)   = [d]
benchNames (BenchGroup d bs) = map ((d ++ "/") ++) . concatMap benchNames $ bs
benchNames (BenchCompare bs) =                       concatMap benchNames $ bs

instance Show Benchmark where
    show (Benchmark _ _ d _)  = ("Benchmark " ++ show d)
    show (BenchGroup d _) = ("BenchGroup " ++ show d)
    show (BenchCompare _) = ("BenchCompare")
