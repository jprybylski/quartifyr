# Records the full two-pass pipeline on examples/demo-report via render.R: a draft
# render, then a final render, showing real reportifyr fill-pass output (add tables,
# add plots, add footnotes, finalize) and the resulting docx paths.
#
# Run from examples/demo-report/, with the r/ and demo-report rv environments synced
# (`rv sync` in both) and `reportifyr::initialize_report_project(project_dir = getwd())`
# already run at least once:
#   cd examples/demo-report
#   rm -rf report/draft report/final
#   Rscript -e 'reportifyr::initialize_report_project(project_dir = getwd())'
#   vhs ../../docs/assets/tapes/render-pipeline.tape
#
# Regenerate whenever render_report()'s own step output changes, so the GIF never
# drifts from what the tool actually prints.

Output ../../docs/assets/img/render-pipeline.gif

Require Rscript

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 750
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 40ms

Hide
Type `clear`
Enter
Sleep 300ms
Show

Type `Rscript render.R`
Enter
Sleep 6s

Type `Rscript render.R --final`
Enter
Sleep 6s

Type `ls report/draft report/final`
Enter
Sleep 2s
