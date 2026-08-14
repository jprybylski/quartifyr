# Records `quartifyr-styling build` generating a docx reference-doc from a style YAML.
# Writes to a scratch output path, not the committed inst/templates/org-reference.docx
# -- scripts/check_template_freshness.py --check confirms the committed copy stays
# untouched.
#
# Run from the repo root, with the Python venv activated (quartifyr-styling on $PATH):
#   source .venv/bin/activate
#   vhs dev/tapes/styling-build.tape
#
# Regenerate whenever inst/python/styles/default.yaml's schema or defaults change.

Output man/figures/styling-build.gif

Require quartifyr-styling

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 500
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 40ms

Hide
Type `mkdir -p /tmp/quartifyr-docs-scratch && clear`
Enter
Sleep 500ms
Show

Type `quartifyr-styling build --style inst/python/styles/default.yaml --out /tmp/quartifyr-docs-scratch/org-reference.docx`
Enter
Sleep 4s

Type `ls -la /tmp/quartifyr-docs-scratch/`
Enter
Sleep 2s
