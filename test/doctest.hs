import Test.DocTest

main :: IO ()
main = doctest ["-XFlexibleContexts", "-XTemplateHaskell", "src/"]
