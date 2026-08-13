# Records `quarto render` building a report shell from examples/demo-report/report.qmd
# and the committed templates/org-reference.docx -- no R, no Python, no reportifyr.
# {rpfy}: placeholders stay literal in the output; that's expected, pass 2 hasn't run.
#
# Run from the repo root, with `quarto` on $PATH:
#   vhs docs/assets/tapes/quarto-only.tape
#
# Regenerate whenever examples/demo-report/report.qmd or the reference-doc's visible
# styling changes, so the GIF never drifts from what the tool actually produces.

Output docs/assets/img/quarto-only.gif

Require quarto

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 40ms

Hide
Type `cd examples/demo-report && clear`
Enter
Sleep 500ms
Show

Type `quarto render report.qmd --to docx --reference-doc ../../templates/org-reference.docx -M document-status:DRAFT`
Enter
Sleep 10s

Type `ls report/shell/`
Enter
Sleep 2s
