# Backward Compatibility

Please note that this framework supports older OS X versions down to 10.6. When changing the code, be careful not to call any API functions not available in 10.6 or call them conditionally, only where supported.

# Commit Messages

Please use descriptive commit message. As an example, _Bug fix_ commit message doesn’t say much, while _Fix a memory-management bug in formatting code_ works much better. A [nice detailed article about writing commit messages](http://chris.beams.io/posts/git-commit/) is also available.

# How to Release a New Version

First, update the version numbers. (MASShortcut uses [Semantic Versioning](http://semver.org/), so please read the docs if you’re not sure what the deal is.) The version number is stored in `Framework/Info.plist` and `MASShortcut.podspec` (twice in both files).

Then update the `CHANGES` file. Add information about the new version (see the previous versions for an example) and add the release date.

Now commit the changes:

    $ git commit -a -m "Version bump to x.y.z."

And tag the last commit:

    $ git tag -a x.y.z

Now push both the commits and tags (`--tags`) to GitHub and push the new podspec to CocoaPods:

    $ pod trunk push MASShortcut.podspec

This will run sanity checks on the podspec and fail if the spec does not validate.

That’s it. Go have a beer or a cup of tea to celebrate.
