Today, it's common for reviewers to suggest specific changes to a pull-request by leaving a comment containing the code they want to see instead in a markdown code block. It's then up to pull request authors to open the commented file to the correct line and reimplement the fix, commit, and push the branch.

Suggested changes allow reviewers to leave these suggestions in a way that is immediately actionable for the author. The author can elect to commit the change to their branch right from the pull request. Here it is in action:

[ gif: leave a suggestion -> wipe -> apply a suggestion ]ad

The new toolbar button will prepopulate the markdown code block for you, but you can create a suggestion without the help of the toolbar by using ````suggestion` to open your suggested code block.hello

We've enjoyed using suggested changes on the PRs that built suggested changes and hope that you'll like it too. If you have any feedback, please see our [feedback issue], which is also linked to when suggestions are rendered in the UI.

We also want to thank peeps

