Do not automatically choose another simulator.

Do not create new simulators.

Do not delete simulators.

Do not change simulator runtimes.

Do not install additional iOS runtimes.

we have already simulators set up for testing, and we want to maintain consistency across our testing environment.
you can use the following command to list the available simulators and their runtimes:
xcrun simctl list
iOS 18.0 (18.0 - 22A3351) - com.apple.CoreSimulator.SimRuntime.iOS-18-0
iOS 18.1 (18.1 - 22B81) - com.apple.CoreSimulator.SimRuntime.iOS-18-1
iOS 18.2 (18.2 - 22C150) - com.apple.CoreSimulator.SimRuntime.iOS-18-2
iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6
iOS 26.5 (26.5 - 23F77) - com.apple.CoreSimulator.SimRuntime.iOS-26-5
iOS 27.0 (27.0 - 24A434) - com.apple.CoreSimulator.SimRuntime.iOS-27-0
== Devices ==
-- iOS 18.0 --
-- iOS 18.1 --
-- iOS 18.2 --
-- iOS 18.6 --
    GameCatch iOS 18 (CD5D9933-3BF4-4803-8CB5-DFE04BB13EDD) (Shutdown) 
    Veilpic Store iOS 18 (54DAECAC-F547-45CF-BE97-50285BC2CCE9) (Booted) 
-- iOS 26.5 --
    iPhone 17 Pro (A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6) (Booted) 
-- iOS 27.0 --
    Iphone 17 pro (FF342D30-5351-4648-AE50-29E812802F2F) (Shutdown) 
    Veilpic App Store (B16FEEB6-1693-44A9-AFAB-244351510B1E) (Shutdown) 
    GameCatch iPad Pro 13 (EEBC0A84-C715-4D00-9D2B-84C043A6C314) (Shutdown) 
== Device Pairs ==

# Xcode source membership

- After adding, removing or renaming Swift files, run `python3 scripts/generate_project.py` and `python3 scripts/generate_project.py --check`.
- If the project is open in Xcode, close and reopen that project after generation, preserving the selected destination. Do not quit unrelated projects or discard unsaved edits.
- Run `python3 -m unittest discover -s scripts -p 'test_*.py'` after modifying the generator or source-membership guard. Keep the guard enabled for all targets and keep script sandboxing enabled.
- For a user-reported Xcode build failure, verify Build in the user's Xcode session after the fix. A separate successful command-line build does not establish that the open session reloaded its project. If UI access is unavailable, report that verification gap explicitly.
- Source-list errors require reloading the project; do not reset simulators or delete unrelated DerivedData to hide them. Make durable target/signing changes in the generator.
